import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/backup/backup_protection.dart';
import 'package:mercantis_hub_app/backup/business_summary.dart';
import 'package:mercantis_hub_app/backup/hub_backup.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// R2: Backup Protection. Automatic, encrypted backups to a folder outside
/// Atlas's data, with freshness, failure detection, rotation, integrity and
/// recovery on a fresh install with the recovery passphrase alone. Real
/// SQLite books, real files, real encryption (Argon2 kept small for speed).
void main() {
  sqfliteFfiInit();
  const passphrase = 'harbour lane recovery 2026';
  final fastKdf = BackupKdfParams.generate(memoryKiB: 1024, iterations: 1);

  late Directory root;
  late String data;
  late String dest;
  late BooksHarness h;
  late MemoryBackupKeyStore keys;
  late DateTime now;
  late HubBackup hubBackup;

  BackupProtectionService service() => BackupProtectionService(
        backup: hubBackup,
        database: () async => h.db.db,
        keys: keys,
        clock: () => now,
        kdf: fastKdf,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('backup-protection');
    data = p.join(root.path, 'data');
    dest = p.join(root.path, 'usb-drive', 'Atlas Backups');
    Directory(data).createSync();
    Directory(dest).createSync(recursive: true);
    h = await BooksHarness.open(p.join(data, 'mercantis.db'));
    await h.save(Document(
        id: 'C1',
        docType: 'Customer',
        payload: {'customer_name': 'Blue Fig', 'customer_type': 'Company'}));
    await h.save(Document(id: 'SV', docType: 'Item', payload: {
      'item_code': 'SV',
      'item_name': 'Consulting',
      'item_type': 'Service',
      'stock_uom': 'Nos',
    }));
    keys = MemoryBackupKeyStore();
    now = DateTime(2026, 11, 5, 9);
    hubBackup = HubBackup(dataDirectory: data, factory: databaseFactoryFfi);
  });

  tearDown(() async {
    await h.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<String> sell(num rate) async {
    final co = (await h.engine.list('Company', userRoles: systemRoles)).single.id;
    return (await h.saveAndSubmit(Document(
            id: '',
            docType: 'Sales Invoice',
            company: co,
            payload: {
          'customer': 'C1',
          'posting_date': isoToday(),
          'due_date': isoToday(),
        })
          ..children['items'] = [
            itemLine('Sales Invoice', {'item': 'SV', 'qty': 1, 'rate': rate}),
          ]))
        .id;
  }

  List<String> autoFiles() => [
        for (final f in Directory(dest).listSync().whereType<File>())
          if (p.basename(f.path).startsWith('atlas-auto-')) p.basename(f.path),
      ]..sort();

  test('first automatic backup: encrypted, verified, in the chosen folder',
      () async {
    await sell(100);
    final s = service();
    final r = await s.enable(destination: dest, passphrase: passphrase);
    expect(r.ok, isTrue, reason: '${r.failure} ${r.detail}');
    expect(autoFiles(), hasLength(1));
    final header = await AtlasBackupService.readHeader(r.report!.path);
    expect(header.formatVersion, BackupHeader.keyringFormat);
    expect(await s.freshness(), BackupFreshness.fresh);
    // Opens with this device's key, without the passphrase.
    final m = await hubBackup.service
        .verifyBackup(r.report!.path, null, deviceKey: keys.key);
    expect((m['business_summary'] as Map)['submitted_counts'],
        containsPair('Sales Invoice', 1));
  });

  test('not due within the interval; due and run after it, with new '
      'transactions included', () async {
    final s = service();
    await s.enable(destination: dest, passphrase: passphrase);
    now = now.add(const Duration(hours: 3));
    expect((await s.runIfDue()).ran, isFalse);
    await sell(50);
    now = now.add(const Duration(hours: 22));
    expect(await s.freshness(), BackupFreshness.due);
    final r = await s.runIfDue();
    expect(r.ok, isTrue);
    expect(autoFiles(), hasLength(2));
    final m = await hubBackup.service
        .verifyBackup(r.report!.path, null, deviceKey: keys.key);
    expect((m['business_summary'] as Map)['submitted_counts'],
        containsPair('Sales Invoice', 1));
  });

  test('survives an app restart: policy, key and schedule persist', () async {
    await service().enable(destination: dest, passphrase: passphrase);
    // A new service instance reads the same preferences and secure storage.
    now = now.add(const Duration(hours: 2));
    final restarted = service();
    expect((await restarted.policy()).enabled, isTrue);
    expect((await restarted.policy()).destination, dest);
    expect(await restarted.keyring(), isNotNull);
    expect((await restarted.runIfDue()).ran, isFalse);
    now = now.add(const Duration(hours: 23));
    expect((await restarted.runIfDue()).ok, isTrue);
  });

  test('an interrupted backup leaves no file and keeps the previous one',
      () async {
    final s = service();
    await s.enable(destination: dest, passphrase: passphrase);
    final before = autoFiles();
    now = now.add(const Duration(days: 1));
    hubBackup.service.faultHook = (step) async {
      if (step == 'database-written') throw StateError('battery died');
    };
    final r = await s.runIfDue();
    hubBackup.service.faultHook = null;
    expect(r.failure, BackupFailure.failed);
    expect(autoFiles(), before);
    expect(Directory(dest).listSync().where((f) => f.path.endsWith('.partial')),
        isEmpty);
    expect(await s.freshness(), BackupFreshness.failing);
    // The next run recovers.
    expect((await s.runIfDue()).ok, isTrue);
    expect(await s.freshness(), BackupFreshness.fresh);
  });

  test('an unavailable destination is reported, and recovers', () async {
    final s = service();
    await s.enable(destination: dest, passphrase: passphrase);
    final moved = '$dest-unplugged';
    Directory(dest).renameSync(moved);
    now = now.add(const Duration(days: 1));
    final r = await s.runIfDue();
    expect(r.failure, BackupFailure.destinationMissing);
    expect((await s.state()).consecutiveFailures, 1);
    expect(await s.freshness(), BackupFreshness.failing);
    Directory(moved).renameSync(dest);
    expect((await s.runIfDue()).ok, isTrue);
  });

  test('insufficient storage is classified and leaves nothing behind',
      () async {
    final s = service();
    await s.enable(destination: dest, passphrase: passphrase);
    now = now.add(const Duration(days: 1));
    hubBackup.service.faultHook = (step) async {
      if (step == 'database-written') {
        throw const FileSystemException('write failed', 'x',
            OSError('No space left on device', 28));
      }
    };
    final r = await s.runIfDue();
    hubBackup.service.faultHook = null;
    expect(r.failure, BackupFailure.noSpace);
    expect(autoFiles(), hasLength(1));
  });

  test('incorrect permissions and folders inside Atlas data are refused',
      () async {
    expect(
        BackupProtectionService.classify(const FileSystemException(
            'open failed', 'x', OSError('Permission denied', 13))),
        BackupFailure.permissionDenied);
    expect(
        BackupProtectionService.classify(const FileSystemException(
            'open failed', 'x', OSError('Access is denied.', 5))),
        BackupFailure.permissionDenied);
    // A "folder" that is a file cannot hold backups.
    final file = File(p.join(root.path, 'not-a-folder'))..writeAsStringSync('x');
    expect(await BackupProtectionService.probeDestination(file.path, data),
        isNotNull);
    // The app's own data folder is lost with the device: refused.
    final inside = Directory(p.join(data, 'backups'))..createSync();
    await expectLater(
        service().enable(destination: inside.path, passphrase: passphrase),
        throwsA(isA<BackupProtectionException>()));
    expect((await service().policy()).enabled, isFalse);
  });

  test('rotation keeps the newest N automatic backups and never touches '
      'others', () async {
    final s = service();
    await s.enable(destination: dest, passphrase: passphrase);
    await s.changeSchedule(keep: 3);
    final manual = File(p.join(dest, 'my-own-copy.atlasbackup'))
      ..writeAsStringSync('not ours');
    for (var i = 0; i < 5; i++) {
      now = now.add(const Duration(days: 1));
      expect((await s.runIfDue()).ok, isTrue);
    }
    final files = autoFiles();
    expect(files, hasLength(3));
    expect(files.last, contains('20261110'), reason: 'newest kept');
    expect(manual.existsSync(), isTrue);
  });

  test('integrity: every kept backup verifies; a damaged one is detected',
      () async {
    final s = service();
    await s.enable(destination: dest, passphrase: passphrase);
    now = now.add(const Duration(days: 1));
    await s.runIfDue();
    for (final f in autoFiles()) {
      await hubBackup.service
          .verifyBackup(p.join(dest, f), null, deviceKey: keys.key);
    }
    final victim = File(p.join(dest, autoFiles().first));
    final bytes = victim.readAsBytesSync();
    bytes[bytes.length - 40] ^= 0xFF;
    victim.writeAsBytesSync(bytes);
    await expectLater(
        hubBackup.service.verifyBackup(victim.path, null, deviceKey: keys.key),
        throwsA(isA<BackupException>()));
  });

  test('fresh installation: the recovery passphrase alone restores it',
      () async {
    await sell(120);
    await sell(80);
    final s = service();
    final r = await s.enable(destination: dest, passphrase: passphrase);
    final summary = await BusinessSummary.compute(h.db.db);

    // The phone and its secure storage are gone. A new install, a new
    // data folder, no device key.
    final fresh = p.join(root.path, 'new-phone');
    Directory(fresh).createSync();
    final b = HubBackup(dataDirectory: fresh, factory: databaseFactoryFfi);
    await expectLater(b.stage(r.report!.path, null),
        throwsA(isA<BackupException>()),
        reason: 'no key and no passphrase');
    final staged = await b.stage(r.report!.path, passphrase);
    expect(staged.businessSummary, summary);
    await b.commit(staged, deviceId: 'new-phone');
    final restored = await BooksHarness.open(p.join(fresh, 'mercantis.db'),
        deviceId: 'new-phone');
    try {
      expect(await BusinessSummary.compute(restored.db.db), summary);
    } finally {
      await restored.close();
    }
  });

  test('no plaintext financial data or secrets in the backup folder',
      () async {
    await sell(4242.42);
    final s = service();
    await s.enable(destination: dest, passphrase: passphrase);
    for (final f in Directory(dest).listSync().whereType<File>()) {
      final hay = latin1.decode(f.readAsBytesSync(), allowInvalid: true);
      expect(hay, isNot(contains('Blue Fig')));
      expect(hay, isNot(contains('4242.42')));
      expect(hay, isNot(contains('Harbour Lane')));
      expect(hay, isNot(contains(passphrase)));
      expect(hay, isNot(contains(base64Encode(keys.key!))));
    }
    // Preferences hold the recovery slot (passphrase-encrypted) only.
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      final v = '${prefs.get(k)}';
      expect(v, isNot(contains(passphrase)));
      expect(v, isNot(contains(base64Encode(keys.key!))));
    }
  });

  test('a sale posted while the backup is written: no corruption', () async {
    final s = service();
    await s.enable(destination: dest, passphrase: passphrase);
    now = now.add(const Duration(days: 1));
    String? during;
    hubBackup.service.faultHook = (step) async {
      if (step == 'snapshot') during = await sell(77);
    };
    final r = await s.runIfDue();
    hubBackup.service.faultHook = null;
    expect(r.ok, isTrue);
    expect(during, isNotNull);
    expect(await h.trialBalanceDifference(), 0);
    // The backup restores to a consistent book (the sale came after the
    // snapshot, so it is not in it), verified to the cent by the restore.
    final fresh = p.join(root.path, 'check');
    Directory(fresh).createSync();
    final b = HubBackup(dataDirectory: fresh, factory: databaseFactoryFfi);
    final staged = await b.stage(r.report!.path, null, deviceKey: keys.key);
    await b.commit(staged);
    final restored = await BooksHarness.open(p.join(fresh, 'mercantis.db'),
        deviceId: 'check');
    try {
      expect(await restored.engine.fetch('Sales Invoice', during!), isNull);
      expect(await restored.trialBalanceDifference(), 0);
    } finally {
      await restored.close();
    }
  });

  test('overlapping backups are refused, in this process and another',
      () async {
    final s = service();
    await s.enable(destination: dest, passphrase: passphrase);
    now = now.add(const Duration(days: 1));
    final results = await Future.wait([s.runIfDue(), s.runIfDue()]);
    expect(results.where((r) => r.ok), hasLength(1));
    expect(results.where((r) => r.failure == BackupFailure.busy), hasLength(1));
    // Another process holds the lock.
    final lock = File(p.join(data, 'backup-work', 'auto-backup.lock'))
      ..createSync(recursive: true);
    now = now.add(const Duration(days: 1));
    lock.setLastModifiedSync(DateTime.now());
    expect((await s.runIfDue()).failure, BackupFailure.busy);
    // A lock left by a crash goes stale.
    lock.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 3)));
    now = DateTime.now();
    expect((await s.runIfDue(force: true)).ok, isTrue);
  });

  test('lost secure storage: backups stop (never unencrypted) until the '
      'passphrase recovers the key', () async {
    final s = service();
    await s.enable(destination: dest, passphrase: passphrase);
    final original = List.of(keys.key!);
    keys.key = null;
    now = now.add(const Duration(days: 1));
    expect((await s.runIfDue()).failure, BackupFailure.keyMissing);
    expect(autoFiles(), hasLength(1));
    await expectLater(
        s.recoverKey('wrong passphrase entirely'), throwsA(isA<BackupException>()));
    await s.recoverKey(passphrase);
    expect(keys.key, original);
    expect((await s.runIfDue()).ok, isTrue);
  });

  test('secure storage unavailable at set-up: automatic backup stays off',
      () async {
    keys.failWrites = true;
    await expectLater(
        service().enable(destination: dest, passphrase: passphrase),
        throwsA(isA<BackupProtectionException>()));
    expect((await service().policy()).enabled, isFalse);
    expect(autoFiles(), isEmpty);
  });

  test('freshness: overdue after twice the interval without a good backup',
      () {
    const policy = BackupProtectionPolicy(enabled: true, destination: '/x');
    final t = DateTime(2026, 11, 5);
    expect(
        BackupProtectionService.freshnessOf(
            policy, BackupProtectionState(lastSuccessAt: t), t.add(const Duration(hours: 49))),
        BackupFreshness.overdue);
    expect(
        BackupProtectionService.freshnessOf(
            policy, const BackupProtectionState(), t),
        BackupFreshness.overdue);
    expect(
        BackupProtectionService.freshnessOf(
            const BackupProtectionPolicy(), const BackupProtectionState(), t),
        BackupFreshness.off);
  });
}
