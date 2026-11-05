import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/backup/hub_backup.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/numbering/numbering_recovery.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:mercantis_hub_app/payments/guided_payment.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// R3: restoring an older backup must never let Atlas issue a document
/// number again. The mandatory scenario from the commercialisation brief:
/// invoices through 100, backup, 101–105, restore the older backup, issue
/// more. With the original device (its replaced books are the evidence) the
/// numbers continue at 106; on a replacement device (no evidence) official
/// numbering waits for an explicit, audited decision.
///
/// Before this fix the same-device case issued 101 again (verified against
/// hub main b596937: the restored per-device counter block resumed at the
/// backup's position).
void main() {
  sqfliteFfiInit();
  const passphrase = 'correct horse battery staple';

  late Directory root;
  late String data;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('numbering-recovery');
    data = p.join(root.path, 'device-a');
    Directory(data).createSync();
  });
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<void> masters(BooksHarness h) async {
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
  }

  Future<String> company(BooksHarness h) async =>
      (await h.engine.list('Company', userRoles: systemRoles)).single.id;

  Document invoiceDoc(String co, {num rate = 10, Map<String, dynamic>? extra}) =>
      Document(id: '', docType: 'Sales Invoice', company: co, payload: {
        'customer': 'C1',
        'posting_date': isoToday(),
        'due_date': isoToday(),
        ...?extra,
      })
        ..children['items'] = [
          itemLine('Sales Invoice', {'item': 'SV', 'qty': 1, 'rate': rate}),
        ];

  Future<String> invoice(BooksHarness h) async =>
      (await h.saveAndSubmit(invoiceDoc(await company(h)))).id;

  int numberOf(String id) => int.parse(id.split('-').last);

  Future<String> payment(BooksHarness h, String invoiceId) async =>
      (await h.saveAndSubmit(GuidedPayment.buildPaymentEntry(
        receive: true,
        party: 'C1',
        postingDate: isoToday(),
        bankAccount: 'Bank',
        partyAccount: 'Debtors',
        company: await company(h),
        allocations: [
          PaymentAllocation(
              invoiceId: invoiceId,
              invoiceDocType: 'Sales Invoice',
              total: 10,
              outstanding: 10,
              allocated: 10),
        ],
      )))
          .id;

  /// Books with invoices 1..[before], a backup, then 101..105-style trade.
  Future<(BooksHarness, String, List<String>)> tradeAroundBackup(
      {int before = 100, int after = 5}) async {
    final h = await BooksHarness.open(p.join(data, 'mercantis.db'));
    await masters(h);
    final early = <String>[];
    for (var i = 0; i < before; i++) {
      early.add(await invoice(h));
    }
    expect(numberOf(early.last), before);
    final file = p.join(root.path, 'older.atlasbackup');
    await HubBackup(dataDirectory: data, factory: databaseFactoryFfi)
        .createBackup(
            database: h.db.db, passphrase: passphrase, outputPath: file);
    final later = <String>[];
    for (var i = 0; i < after; i++) {
      later.add(await invoice(h));
    }
    if (later.isNotEmpty) expect(numberOf(later.first), before + 1);
    return (h, file, later);
  }

  test('official doctypes all exist in the Hub manifest', () {
    final names = {for (final d in HubManifest.build().docTypes) d.name};
    expect(officialNumberingDocTypes.difference(names), isEmpty);
  });

  group('original device still exists', () {
    test('restore of an older backup never re-issues 101–105', () async {
      final (h, file, later) = await tradeAroundBackup();
      // A payment and a cancellation after the backup, too.
      final pay = await payment(h, later[0]);
      final cancelled = later[2];
      final c = await h.engine.fetch('Sales Invoice', cancelled);
      await h.engine.cancel(c!, systemRoles);
      final backup = HubBackup(dataDirectory: data, factory: databaseFactoryFfi);
      final staged = await backup.stage(file, passphrase);
      await h.close();
      final (_, result) =
          await backup.commit(staged, deviceId: 'device-a', userId: 'owner');

      expect(result!.mode, NumberingRecoveryMode.advancedFromEvidence);
      expect(result.missingDocuments, containsAll([...later, pay]));
      final r = await BooksHarness.open(p.join(data, 'mercantis.db'));
      try {
        for (final id in later) {
          expect(await r.engine.fetch('Sales Invoice', id), isNull,
              reason: 'the restored books are the older ones');
        }
        final next = await invoice(r);
        expect(numberOf(next), 106, reason: '101–105 were issued already');
        expect(later, isNot(contains(next)));
        // The payment series moved past the post-backup payment too.
        final inv = await invoice(r);
        final pay2 = await payment(r, inv);
        expect(pay2, isNot(pay));
        expect(numberOf(pay2), numberOf(pay) + 1);
        // The audit trail records what happened and why.
        final audit = await r.db.db.query('audit_log',
            where: 'doctype = ?', whereArgs: [numberingAuditDocType]);
        expect(audit.single['action'], 'restore_numbering');
        final payload = jsonDecode(audit.single['payload'] as String) as Map;
        expect(payload['mode'], 'advancedFromEvidence');
        expect(payload['missing_documents'], contains(later.first));
      } finally {
        await r.close();
      }
    });

    test('restoring the newest backup changes nothing', () async {
      final (h, _, _) = await tradeAroundBackup(before: 3, after: 0);
      final file = p.join(root.path, 'newest.atlasbackup');
      final backup = HubBackup(dataDirectory: data, factory: databaseFactoryFfi);
      await backup.createBackup(
          database: h.db.db, passphrase: passphrase, outputPath: file);
      final staged = await backup.stage(file, passphrase);
      await h.close();
      final (_, result) = await backup.commit(staged);
      expect(result!.mode, NumberingRecoveryMode.unchanged);
      final r = await BooksHarness.open(p.join(data, 'mercantis.db'));
      expect(numberOf(await invoice(r)), 4);
      expect(await NumberingRecovery.holds(r.db.db), isEmpty);
      await r.close();
    });

    test('a restore interrupted at any step keeps the live counters', () async {
      for (final step in RestoreStep.values) {
        if (step == RestoreStep.committed) continue;
        final (h, file, later) = await tradeAroundBackup(before: 2, after: 2);
        final backup =
            HubBackup(dataDirectory: data, factory: databaseFactoryFfi);
        final staged = await backup.stage(file, passphrase);
        await h.close();
        await expectLater(
            backup.commit(staged, onStep: (s) async {
              if (s == step) throw StateError('power cut at ${s.name}');
            }),
            throwsStateError);
        AtlasBackupService.recoverInterruptedRestore(backup.target,
            safetyCopyDirectory: backup.safetyCopyDirectory);
        final r = await BooksHarness.open(p.join(data, 'mercantis.db'));
        expect(await r.engine.fetch('Sales Invoice', later.last), isNotNull,
            reason: 'live books back after failure at ${step.name}');
        expect(numberOf(await invoice(r)), 5);
        await r.close();
        await Directory(data).delete(recursive: true);
        Directory(data).createSync();
      }
    });

    test('books of a different business here are not evidence: hold',
        () async {
      final (h, file, _) = await tradeAroundBackup(before: 2, after: 0);
      await h.close();
      // The device now holds another business.
      await File(p.join(data, 'mercantis.db')).delete();
      final other = await BooksHarness.open(p.join(data, 'mercantis.db'),
          seed: false);
      await HubSeeder(other.engine, roles: systemRoles).seed(
          businessName: 'Other Ventures Ltd',
          currencyCode: 'EUR',
          year: DateTime.now().year);
      await other.close();
      final backup = HubBackup(dataDirectory: data, factory: databaseFactoryFfi);
      final (_, result) =
          await backup.commit(await backup.stage(file, passphrase));
      expect(result!.mode, NumberingRecoveryMode.holdPendingDecision);
      expect(result.evidence.single, contains('different business'));
    });
  });

  group('original device destroyed (no evidence survives)', () {
    Future<(BooksHarness, List<String>)> restoreOnNewDevice() async {
      final (h, file, later) = await tradeAroundBackup();
      await h.close();
      final dataB = p.join(root.path, 'replacement');
      Directory(dataB).createSync();
      final backupB =
          HubBackup(dataDirectory: dataB, factory: databaseFactoryFfi);
      final (_, result) = await backupB.commit(
          await backupB.stage(file, passphrase),
          deviceId: 'device-b');
      expect(result!.mode, NumberingRecoveryMode.holdPendingDecision);
      expect(result.describe(), contains('on hold'));
      return (
        await BooksHarness.open(p.join(dataB, 'mercantis.db'),
            deviceId: 'device-b'),
        later
      );
    }

    test('official numbering fails safe until a decision', () async {
      final (r, _) = await restoreOnNewDevice();
      try {
        final before = await r.rowCount('Sales Invoice');
        await expectLater(r.saveAndSubmit(invoiceDoc(await company(r))),
            throwsA(isA<NamingHoldException>()));
        expect(await r.rowCount('Sales Invoice'), before,
            reason: 'nothing saved, no number consumed');
        // Credit notes share the invoice series; receipts are held too.
        await expectLater(
            r.saveAndSubmit(invoiceDoc(await company(r),
                rate: 10, extra: {'is_return': 1})),
            throwsA(isA<NamingHoldException>()));
        await expectLater(payment(r, 'SINV-x'),
            throwsA(isA<NamingHoldException>()));
        // Master data is not held: a new customer can still be added.
        await r.save(Document(
            id: 'C2',
            docType: 'Customer',
            payload: {'customer_name': 'Teal Ltd', 'customer_type': 'Company'}));
      } finally {
        await r.close();
      }
    });

    test('decision 1: a verified last number, never lower than the books',
        () async {
      final (r, later) = await restoreOnNewDevice();
      try {
        final series = (await const CounterBlockAllocator()
                .issuedThrough(r.db.db))
            .keys
            .firstWhere((k) => k.startsWith('SINV-'));
        await expectLater(
            NumberingRecovery.confirmLastIssued(r.db.db, {series: 99},
                userId: 'owner', deviceId: 'device-b'),
            throwsArgumentError);
        expect(await NumberingRecovery.holds(r.db.db), isNotEmpty,
            reason: 'a refused decision changes nothing');
        // The owner checked the sent-invoices folder: the last was 105.
        await NumberingRecovery.confirmLastIssued(r.db.db, {series: 105},
            userId: 'owner', deviceId: 'device-b');
        expect(await NumberingRecovery.holds(r.db.db), isEmpty);
        final next = await invoice(r);
        expect(numberOf(next), 106);
        expect(later, isNot(contains(next)));
        final audit = await r.db.db.query('audit_log',
            where: 'doctype = ? AND action = ?',
            whereArgs: [numberingAuditDocType, 'numbering_confirmed']);
        expect(audit.single['user_id'], 'owner');
      } finally {
        await r.close();
      }
    });

    test('decision 2: a distinct recovery series', () async {
      final (r, later) = await restoreOnNewDevice();
      try {
        final segment = await NumberingRecovery.startRecoverySeries(r.db.db,
            userId: 'owner', deviceId: 'device-b');
        expect(segment, 'R1');
        final next = await invoice(r);
        expect(next, contains('-R1-'));
        expect(numberOf(next), 1);
        expect(later, isNot(contains(next)));
        final inv = await invoice(r);
        expect(await payment(r, inv), contains('-R1-'));
        // Existing identifiers are untouched.
        for (final id in await r.db.db.query('documents',
            columns: ['id'],
            where: 'doctype = ? AND id NOT LIKE ?',
            whereArgs: ['Sales Invoice', '%-R1-%'])) {
          expect(numberOf('${id['id']}'), lessThanOrEqualTo(100));
        }
        expect(await NumberingRecovery.activeSegment(r.db.db), 'R1');
      } finally {
        await r.close();
      }
    });
  });
}
