import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/backup/business_summary.dart';
import 'package:mercantis_hub_app/backup/hub_backup.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' show asNum;
import 'package:mercantis_hub_app/migration/opening_reconciliation.dart';
import 'package:mercantis_hub_app/migration/opening_take_on.dart';
import 'package:mercantis_hub_app/migration/take_on_templates.dart';
import 'package:mercantis_hub_app/modules/selling/hub_document_conversion.dart';
import 'package:mercantis_hub_app/payments/guided_payment.dart';
import 'package:mercantis_hub_app/reports/aggregating_reports.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// Atlas Solo financial acceptance fixture (Section F of the Solo hardening
/// brief, docs/SOLO_ACCEPTANCE_MATRIX.md):
///
///   company setup → opening-data migration and reconciliation → purchase
///   order → receipt → supplier invoice → supplier payment → quotation →
///   sales order → sales invoice → part payment → final payment → return
///   (credit note) → stock valuation → VAT → TB → P&L → BS → encrypted
///   backup → restore into a CLEAN installation (a new, empty data folder)
///   → identical documents, attachments and reports → normal use resumes.
///
/// Prices are VAT-exclusive at the seeded default 18 %.
void main() {
  sqfliteFfiInit();
  const passphrase = 'correct horse battery staple';
  final year = DateTime.now().year;
  final openingDate = '$year-09-30';

  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('solo-acc'));
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<HubAggregatingReports> reportsFor(BooksHarness h) async =>
      HubAggregatingReports(
        (docType,
                {filters,
                whereExpression,
                sortBy,
                limit,
                offset,
                userRoles}) =>
            h.engine.list(docType,
                filters: filters,
                whereExpression: whereExpression,
                sortBy: sortBy,
                limit: limit,
                offset: offset,
                userRoles: systemRoles),
        fetch: h.engine.fetch,
      );

  /// Every report the owner and accountant rely on, rendered to plain JSON.
  Future<Map<String, Object?>> reportSet(BooksHarness h) async {
    final r = await reportsFor(h);
    Object? rows(ReportResult x) => jsonDecode(jsonEncode(x.rows));
    final asOf = DateTime(year, 12, 31);
    return {
      'trial_balance': rows(await r.trialBalance(userRoles: systemRoles)),
      'profit_and_loss': rows(await r.profitAndLoss(userRoles: systemRoles)),
      'balance_sheet': rows(await r.balanceSheet(userRoles: systemRoles)),
      'stock_valuation': rows(await r.stockValuation(userRoles: systemRoles)),
      'stock_gl_reconciliation':
          rows(await r.stockGlReconciliation(userRoles: systemRoles)),
      'ar_aging': rows(await r.arAging(asOf: asOf, userRoles: systemRoles)),
      'ap_aging': rows(await r.apAging(asOf: asOf, userRoles: systemRoles)),
    };
  }

  /// Every row of every table (documents, child rows, audit trail, sync
  /// queue, posting outbox, numbering, attachments metadata…), as sorted
  /// JSON so row order inside the file does not matter. `apps` and
  /// `doctypes` are left out: they are the app's own manifest, rewritten from
  /// the installed build on every start, not business data.
  Future<Map<String, List<String>>> allTables(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' AND name NOT IN ('apps', 'doctypes') "
        'ORDER BY name');
    return {
      for (final t in tables)
        '${t['name']}': [
          for (final r in await db.rawQuery('SELECT * FROM "${t['name']}"'))
            jsonEncode(r),
        ]..sort(),
    };
  }

  Future<Document> submitted(BooksHarness h, Document d) => h.saveAndSubmit(d);

  test('setup → migration → trade → backup → clean restore: identical books',
      () async {
    final dataA = p.join(root.path, 'device-a');
    Directory(dataA).createSync();
    final h = await BooksHarness.open(p.join(dataA, 'mercantis.db'));
    final company =
        (await h.engine.list('Company', userRoles: systemRoles)).single.id;

    // ---- Opening data from the previous system ----------------------------
    final inputs = {
      for (final t in TakeOnTemplate.all) t.section: TakeOnInput(t.csv()),
    };
    final takeOn = OpeningTakeOn(h.engine);
    final dry = await takeOn.plan(openingDate: openingDate, inputs: inputs);
    expect(dry.canImport, isTrue);
    final (imported, result) =
        await takeOn.commit(openingDate: openingDate, inputs: inputs);
    expect(result.errors, isEmpty);
    final opening = await OpeningReconciliation.compute(h.engine, imported);
    expect(opening.reconciled, isTrue);

    // ---- Purchase: order → receipt → bill → payment ----------------------
    final po = await submitted(
        h,
        Document(id: '', docType: 'Purchase Order', company: company, payload: {
          'supplier': 'S001',
          'transaction_date': isoToday(),
          'set_warehouse': 'MAIN',
        })
          ..children['items'] = [
            itemLine('Purchase Order',
                {'item': 'WIDGET-1', 'qty': 10, 'rate': 6, 'warehouse': 'MAIN'}),
          ]);
    final receipt = await submitted(
        h, HubDocumentConversion.purchaseOrderToReceipt(po));
    expect((await h.bin('WIDGET-1', 'MAIN'))!.payload['actual_qty'], 50);
    // The receipt carries no tax; the bill is entered with the supplier's VAT.
    final bill = await submitted(h,
        HubDocumentConversion.receiptToInvoice(receipt)..payload['tax_code'] = 'VAT 18%');
    expect(asNum(bill.payload['grand_total']), 70.80);
    await submitted(
        h,
        GuidedPayment.buildPaymentEntry(
          receive: false,
          party: 'S001',
          postingDate: isoToday(),
          bankAccount: 'Bank',
          partyAccount: 'Creditors',
          company: company,
          allocations: [
            PaymentAllocation(
                invoiceId: bill.id,
                invoiceDocType: 'Purchase Invoice',
                total: 70.80,
                outstanding: 70.80,
                allocated: 70.80),
          ],
        ));
    expect(
        asNum((await h.engine.fetch('Purchase Invoice', bill.id))!
            .payload['outstanding_amount']),
        0);

    // ---- Sale: quotation → order → invoice → part + final payment --------
    final quote = await submitted(
        h,
        Document(id: '', docType: 'Quotation', company: company, payload: {
          'customer': 'C001',
          'transaction_date': isoToday(),
          'set_warehouse': 'MAIN',
          'tax_code': 'VAT 18%',
        })
          ..children['items'] = [
            itemLine('Quotation',
                {'item': 'WIDGET-1', 'qty': 5, 'rate': 12, 'warehouse': 'MAIN'}),
            itemLine('Quotation', {'item': 'CONSULT', 'qty': 1, 'rate': 60}, 1),
          ]);
    final so =
        await submitted(h, HubDocumentConversion.quotationToSalesOrder(quote));
    final siDraft = HubDocumentConversion.salesOrderToInvoice(so)
      ..payload['update_stock'] = 1
      ..payload['set_warehouse'] = 'MAIN'
      ..payload['due_date'] = isoToday();
    final si = await submitted(h, siDraft);
    expect(asNum(si.payload['grand_total']), 141.60);

    // The signed invoice is attached to the sale.
    final attachments = AttachmentManager(
        h.db.db, AttachmentStore(p.join(dataA, 'attachments')));
    final scan = List<int>.generate(300000, (i) => (i * 7) % 256);
    await attachments.attach(
        documentId: si.id,
        docType: 'Sales Invoice',
        fileName: 'signed-invoice.pdf',
        mimeType: 'application/pdf',
        data: scan,
        userId: 'owner');

    Future<void> receive(num amount, num outstanding) => submitted(
        h,
        GuidedPayment.buildPaymentEntry(
          receive: true,
          party: 'C001',
          postingDate: isoToday(),
          bankAccount: 'Bank',
          partyAccount: 'Debtors',
          company: company,
          allocations: [
            PaymentAllocation(
                invoiceId: si.id,
                invoiceDocType: 'Sales Invoice',
                total: 141.60,
                outstanding: outstanding,
                allocated: amount),
          ],
        ));
    await receive(100, 141.60);
    expect(
        asNum((await h.engine.fetch('Sales Invoice', si.id))!
            .payload['outstanding_amount']),
        41.60);
    await receive(41.60, 41.60);
    expect(
        asNum((await h.engine.fetch('Sales Invoice', si.id))!
            .payload['outstanding_amount']),
        0);

    // ---- Return one widget: credit note, stock back at cost --------------
    final credit = HubDocumentConversion.salesInvoiceReturn(si)
      ..payload['update_stock'] = 1
      ..payload['set_warehouse'] = 'MAIN'
      ..payload['due_date'] = isoToday();
    credit.children['items'] = [
      for (final row in credit.children['items']!)
        if (row.payload['item'] == 'WIDGET-1') row..payload['qty'] = -1,
    ];
    final cn = await submitted(h, credit);
    expect(asNum(cn.payload['grand_total']), -14.16);

    // ---- The books --------------------------------------------------------
    expect(await h.ledger!.outstandingPostings(), isEmpty);
    expect(await h.trialBalanceDifference(), 0);
    final expected = <String, num>{
      'Bank': 12570.80, // 12500 − 70.80 + 141.60
      'Debtors': 575.84, // opening 590 − credit note 14.16
      'Creditors': -236, // opening bill still open, new bill paid
      'Stock': 239.20, // 200 + 60 − 26 (5 × 5.20) + 5.20
      'GRNI': 0,
      'VAT': -418.64, // −410 + 10.80 − 21.60 + 2.16
      'Sales': -108, // 120 − 12
      'COGS': 20.80, // 26 − 5.20
      'Retained Earnings': -12644,
      'Opening Balance Equity': 0,
    };
    for (final e in expected.entries) {
      expect(await h.balance(e.key), e.value, reason: e.key);
    }
    final bin = await h.bin('WIDGET-1', 'MAIN');
    expect(bin!.payload['actual_qty'], 46);
    expect(await h.stockValue(), 239.20);

    // VAT: output 21.60 − 2.16 on the credit note; input 10.80.
    num output = 0, input = 0;
    for (final t in await h.engine.list('Tax Transaction', userRoles: systemRoles)) {
      final amt = asNum(t.payload['tax_amount']);
      if (t.payload['voucher_type'] == 'Sales Invoice') output += amt;
      if (t.payload['voucher_type'] == 'Purchase Invoice') input += amt;
    }
    expect(output.toStringAsFixed(2), '19.44');
    expect(input.toStringAsFixed(2), '10.80');

    final reports = await reportsFor(h);
    final pl = await reports.profitAndLoss(userRoles: systemRoles);
    expect(jsonEncode(pl.rows), contains('87.2'));
    final stockGl = await reports.stockGlReconciliation(userRoles: systemRoles);
    expect(jsonEncode(stockGl.rows), isNot(contains('MISMATCH')));

    final summaryBefore = await BusinessSummary.compute(h.db.db);
    final reportsBefore = await reportSet(h);
    final docsBefore = await allTables(h.db.db);

    // ---- Encrypted backup --------------------------------------------------
    final backupA = HubBackup(dataDirectory: dataA, factory: databaseFactoryFfi);
    final backupFile = p.join(root.path, 'offsite', 'books.atlasbackup');
    Directory(p.dirname(backupFile)).createSync();
    final report = await backupA.createBackup(
        database: h.db.db,
        passphrase: passphrase,
        outputPath: backupFile,
        preferences: const {'core.theme_mode': 'dark'});
    expect(report.missingAttachments, isEmpty);
    // The passphrase is nowhere in the file, and the books are not readable.
    final raw = File(backupFile).readAsBytesSync();
    expect(latin1.decode(raw, allowInvalid: true), isNot(contains(passphrase)));
    expect(latin1.decode(raw, allowInvalid: true), isNot(contains('Blue Fig')));
    await h.close();

    // ---- Lose the device: restore into a clean installation ---------------
    final dataB = p.join(root.path, 'device-b');
    Directory(dataB).createSync();
    final backupB = HubBackup(dataDirectory: dataB, factory: databaseFactoryFfi);
    await expectLater(backupB.stage(backupFile, 'wrong passphrase!!'),
        throwsA(isA<BackupException>()));
    final staged = await backupB.stage(backupFile, passphrase);
    expect(staged.businessSummary, summaryBefore);
    await backupB.commit(staged);

    final r = await BooksHarness.open(p.join(dataB, 'mercantis.db'),
        deviceId: 'device-b');
    try {
      final docsAfter = await allTables(r.db.db);
      expect(docsAfter, docsBefore);
      expect(await BusinessSummary.compute(r.db.db), summaryBefore);
      expect(await reportSet(r), reportsBefore);
      final restoredAttachments = AttachmentManager(
          r.db.db, AttachmentStore(p.join(dataB, 'attachments')));
      final a = (await restoredAttachments.attachmentsForDocument(si.id)).single;
      expect(await restoredAttachments.read(a), scan);
      expect(await r.ledger!.outstandingPostings(), isEmpty);

      // The opening position still reconciles on the new device.
      final again = await OpeningReconciliation.compute(r.engine,
          await OpeningTakeOn(r.engine)
              .plan(openingDate: openingDate, inputs: inputs));
      expect(again.reconciled, isTrue);

      // Normal use resumes: settle the opening receivable.
      await r.saveAndSubmit(GuidedPayment.buildPaymentEntry(
        receive: true,
        party: 'C001',
        postingDate: isoToday(),
        bankAccount: 'Bank',
        partyAccount: 'Debtors',
        company: company,
        allocations: const [
          PaymentAllocation(
              invoiceId: 'OPEN-AR:INV-1042',
              invoiceDocType: 'Sales Invoice',
              total: 590,
              outstanding: 590,
              allocated: 590),
        ],
      ));
      expect(await r.balance('Bank'), 13160.80);
      expect(
          asNum((await r.engine.fetch('Sales Invoice', 'OPEN-AR:INV-1042'))!
              .payload['outstanding_amount']),
          0);
      expect(await r.trialBalanceDifference(), 0);
    } finally {
      await r.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
