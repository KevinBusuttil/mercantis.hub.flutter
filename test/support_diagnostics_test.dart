import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/features/hub_feature.dart';
import 'package:mercantis_hub_app/screens/startup_error_screen.dart';
import 'package:mercantis_hub_app/screens/support_screen.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';
import 'package:mercantis_hub_app/support/diagnostic_log.dart';
import 'package:mercantis_hub_app/support/support_diagnostics.dart';
import 'package:mercantis_hub_app/sync/company_sync.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// M1.6 support readiness: the diagnostics bundle carries what support
/// needs and none of the customer's business data or secrets.
void main() {
  setUpAll(sqfliteFfiInit);

  group('DiagnosticRedactor', () {
    String r(String s) => DiagnosticRedactor.redact(s);

    test('removes e-mail addresses, tokens and keys', () {
      expect(r('mail anna.borg@harbour-lane.mt failed'),
          'mail [email] failed');
      expect(r('Authorization: Bearer abc.DEF-123_xyz'),
          isNot(contains('abc.DEF-123_xyz')));
      expect(r('api_key=sk-example-example-example rejected'),
          isNot(contains('sk-example')));
      expect(r('{"password": "hunter22"}'), isNot(contains('hunter22')));
      expect(r('token eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl'),
          isNot(contains('eyJzdWIiOi')));
      expect(r('GET https://api.example.com/v1/orders?consumer_key=ck_1&x=2'),
          'GET https://api.example.com/v1/orders?[query]');
    });

    test('removes card, IBAN, phone numbers and money amounts', () {
      expect(r('card 4111 1111 1111 1111'), 'card [number]');
      expect(r('card 4111-1111-1111-1111'), 'card [number]');
      expect(r('IBAN MT84MALT011000012345MTLCAST001S'), 'IBAN [account]');
      expect(r('call +356 2123 4567'), 'call [number]');
      expect(r('outstanding 12,570.80 and 41.60 and 12570.80 and 9,99'),
          'outstanding [amount] and [amount] and [amount] and [amount]');
      expect(r('kernel 6.18.44, Atlas v1.0.12'), 'kernel 6.18.44, Atlas v1.0.12');
    });

    test('keeps what support needs: document numbers, dates, counts', () {
      const msg = 'SINV-2026-00001 posted on 2026-10-22: 3 of 5 rows';
      expect(r(msg), msg);
    });

    test('hides the user name in file paths and caps the length', () {
      expect(r('/Users/kevin/Library/x.db'), '/Users/[user]/Library/x.db');
      expect(r(r'C:\Users\kevin\AppData'), r'C:\Users\[user]\AppData');
      expect(r('x' * 2000).length, DiagnosticRedactor.maxMessageLength + 1);
    });
  });

  group('DiagnosticLog', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('diag_log_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('keeps the newest events, redacted, and survives a restart',
        () async {
      final log = DiagnosticLog(capacity: 3);
      log.record('boot', 'early failure for anna@example.com');
      await log.attach(dir.path);
      for (var i = 0; i < 4; i++) {
        log.record('posting', StateError('failure $i'), StackTrace.current);
      }
      expect(log.events, hasLength(3));
      expect(log.events.last.message, contains('failure 3'));

      // A torn line from a crash is ignored, not fatal.
      final file =
          File(p.join(dir.path, DiagnosticLog.folderName, DiagnosticLog.fileName));
      await file.writeAsString('{"at": "2026-', mode: FileMode.append);

      final reopened = DiagnosticLog(capacity: 3);
      await reopened.attach(dir.path);
      expect([for (final e in reopened.events) e.message],
          [for (final e in log.events) e.message]);
      expect(file.readAsStringSync(), isNot(contains('anna@example.com')));

      await reopened.clear();
      final again = DiagnosticLog();
      await again.attach(dir.path);
      expect(again.events, isEmpty);
    });
  });

  group('SupportDiagnostics on a populated book', () {
    late Directory dir;
    late String dbPath;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('diag_books_');
      dbPath = p.join(dir.path, 'mercantis.db');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('reports status and counts, never names, amounts or paths',
        () async {
      final h = await BooksHarness.open(dbPath);
      await h.save(Document(id: 'CUST-Z', docType: 'Customer', payload: {
        'customer_name': 'Zebra Confidential Ltd',
        'customer_type': 'Company',
        'email_id': 'accounts@zebra-confidential.mt',
      }));
      await h.save(Document(
          id: 'WH', docType: 'Warehouse', payload: {'warehouse_name': 'Main'}));
      await h.save(Document(id: 'SVC', docType: 'Item', payload: {
        'item_code': 'SVC',
        'item_name': 'Secret consulting retainer',
        'item_type': 'Service',
        'stock_uom': 'Nos',
      }));
      final si = Document(id: '', docType: 'Sales Invoice', payload: {
        'customer': 'CUST-Z',
        'posting_date': isoToday(),
      });
      si.children['items'] = [
        itemLine('Sales Invoice', {'item': 'SVC', 'qty': 1, 'rate': 1234.56}),
      ];
      await h.saveAndSubmit(si);

      final log = DiagnosticLog();
      log.record('posting',
          'Sales Invoice posting failed for accounts@zebra-confidential.mt '
          'amount 1,234.56');

      final report = await SupportDiagnostics.collect(
        database: h.db.db,
        dataDirectory: dir.path,
        settings: const HubSettings(
            businessPresetId: 'services',
            features: {HubFeature.stock, HubFeature.projects}),
        sync: const SyncStatus(deviceId: 'device-secret-id'),
        deviceId: 'device-secret-id',
        lastBackupAt: DateTime.now().subtract(const Duration(days: 9)),
        localBackupCount: 2,
        events: log.events,
      );
      final text = report.toText();
      final json = report.toPrettyJson();

      // What support needs.
      expect(text, contains('schema version: ${MigrationRunner.latestVersion}'));
      expect(text, contains('integrity: ok'));
      expect(text, contains('Sales Invoice: submitted 1'));
      expect(text, contains('Customer: draft/master 1'));
      expect(text, contains('postings owed (failed): 0'));
      expect(text, contains('this device only (Solo)'));
      expect(text, contains('(9 days ago)'));
      expect(text, contains(HubFeature.stock.label));
      expect(text, contains('[posting]'));
      expect(report.diagnosticId, hasLength(12));

      // What must never leave the device.
      for (final secret in [
        'Harbour Lane Trading', // company
        'Zebra Confidential', // customer
        'zebra-confidential.mt', // e-mail
        'Secret consulting retainer', // item description
        '1234.56', '1,234.56', '1234,56', // the invoice amount
        dir.path, // data folder
        'device-secret-id', // raw device id
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
        expect(json, isNot(contains(secret)), reason: secret);
      }
      await h.close();
    });

    test('still produces a report when boot failed before the database',
        () async {
      final report = await SupportDiagnostics.collect(
          bootError: const UnsupportedSchemaVersionException(9, 8).toString());
      expect(report.toText(), contains('Database ==\nstatus: not open'));
      expect(report.toText(), contains('schema v9'));
    });
  });

  group('screens', () {
    testWidgets('the report view shows its privacy promise and copies',
        (tester) async {
      final report = await SupportDiagnostics.collect(
          bootError: 'x', includeIntegrityCheck: false);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: DiagnosticsReportView(report: report))));
      expect(find.textContaining('does not contain customer'), findsOneWidget);
      expect(find.text('Diagnostic id: ${report.diagnosticId}'), findsOneWidget);
      await tester.tap(find.text('Copy report'));
      await tester.pump();
      expect(copied, report.toText());
    });

    testWidgets('a newer-schema database asks for an update, not a reinstall',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: StartupErrorScreen(
              error: UnsupportedSchemaVersionException(9, 8))));
      await tester.pumpAndSettle();
      expect(find.text('Update Atlas to open your books'), findsOneWidget);
      expect(find.textContaining('has not been changed'), findsOneWidget);
    });

    testWidgets('any other start-up failure says data is safe', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: StartupErrorScreen(error: FileSystemException('locked'))));
      await tester.pumpAndSettle();
      expect(find.text('Atlas could not start'), findsOneWidget);
      expect(find.textContaining('Do not uninstall Atlas'), findsOneWidget);
    });
  });
}
