import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/migration/opening_reconciliation.dart';
import 'package:mercantis_hub_app/migration/opening_take_on.dart';
import 'package:mercantis_hub_app/migration/take_on_templates.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// Guided opening-data migration (M1.3): dry run, import, re-run and resume
/// on a real SQLite book with the production interceptors and ledger.
void main() {
  sqfliteFfiInit();
  final year = DateTime.now().year;
  final openingDate = '$year-09-30';

  late Directory dir;
  late BooksHarness h;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('takeon');
    h = await BooksHarness.open('${dir.path}/books.db');
  });
  tearDown(() async {
    await h.close();
    await dir.delete(recursive: true);
  });

  Map<TakeOnSection, TakeOnInput> templates() => {
        for (final t in TakeOnTemplate.all) t.section: TakeOnInput(t.csv()),
      };

  String csv(List<String> lines) => '${lines.join('\n')}\n';

  test('templates: the example trial balance balances and every template '
      'round-trips through the parser', () async {
    final plan = await OpeningTakeOn(h.engine)
        .plan(openingDate: openingDate, inputs: templates());
    expect(plan.problems, isEmpty);
    for (final s in plan.sections.values) {
      expect(s.problems, isEmpty, reason: s.template.title);
      expect(s.notAccepted, isEmpty,
          reason: '${s.template.title}: '
              '${s.rows.expand((r) => r.problems).join('; ')}');
    }
    expect(plan.canImport, isTrue);
  });

  test('dry run writes nothing', () async {
    final before = await h.rowCount('GL Entry');
    final customers = await h.rowCount('Customer');
    await OpeningTakeOn(h.engine)
        .plan(openingDate: openingDate, inputs: templates());
    expect(await h.rowCount('GL Entry'), before);
    expect(await h.rowCount('Customer'), customers);
  });

  test('import posts the opening position exactly and reconciles to the '
      'trial balance', () async {
    final (plan, result) = await OpeningTakeOn(h.engine)
        .commit(openingDate: openingDate, inputs: templates());
    expect(result.errors, isEmpty);
    expect(plan.canImport, isTrue);

    expect(await h.engine.fetch('Customer', 'C001'), isNotNull);
    expect(await h.engine.fetch('Supplier', 'S001'), isNotNull);
    expect(await h.engine.fetch('Item', 'WIDGET-1'), isNotNull);
    expect(await h.engine.fetch('Warehouse', 'MAIN'), isNotNull);

    // Every TB line lands on its account, to the cent.
    expect(await h.balance('Bank'), 12500);
    expect(await h.balance('Debtors'), 590);
    expect(await h.balance('Stock'), 200);
    expect(await h.balance('Creditors'), -236);
    expect(await h.balance('VAT'), -410);
    expect(await h.balance('Retained Earnings'), -12644);
    // The take-on is self-cancelling through Opening Balance Equity.
    expect(await h.balance('Opening Balance Equity'), 0);
    expect(await h.trialBalanceDifference(), 0);
    // No VAT, income or expense from opening documents.
    expect(await h.balance('Sales'), 0);
    expect(await h.rowCount('Tax Transaction'), 0);

    final bin = await h.bin('WIDGET-1', 'MAIN');
    expect(bin!.payload['actual_qty'], 40);
    expect(await h.stockValue(), 200);

    final inv = await h.engine.fetch('Sales Invoice', 'OPEN-AR:INV-1042');
    expect(inv!.docStatus, 1);
    expect(inv.payload['outstanding_amount'], 590);
    final bill =
        await h.engine.fetch('Purchase Invoice', 'OPEN-AP:S001:AP-5531');
    expect(bill!.docStatus, 1);
    expect(bill.payload['outstanding_amount'], 236);
    expect(await h.ledger!.outstandingPostings(), isEmpty);
  });

  test('re-importing the same files changes nothing', () async {
    final takeOn = OpeningTakeOn(h.engine);
    await takeOn.commit(openingDate: openingDate, inputs: templates());
    final gl = await h.rowCount('GL Entry');
    final sle = await h.rowCount('Stock Ledger Entry');

    final (plan, result) =
        await takeOn.commit(openingDate: openingDate, inputs: templates());
    expect(result.errors, isEmpty);
    expect(result.created, isEmpty);
    expect(result.posted, isEmpty);
    for (final s in plan.sections.values) {
      for (final r in s.rows) {
        expect(r.status,
            isIn([TakeOnRowStatus.unchanged, TakeOnRowStatus.control,
              TakeOnRowStatus.skipped]),
            reason: '${s.template.title} line ${r.line}');
      }
    }
    expect(await h.rowCount('GL Entry'), gl);
    expect(await h.rowCount('Stock Ledger Entry'), sle);
    expect(await h.balance('Bank'), 12500);
  });

  test('an interrupted import resumes: drafts left behind are posted once',
      () async {
    final takeOn = OpeningTakeOn(h.engine);
    final inputs = templates();
    // Simulate a run that died after saving the opening invoice and stock
    // entry but before submitting them.
    final plan = await takeOn.plan(openingDate: openingDate, inputs: inputs);
    expect(plan.canImport, isTrue);
    await takeOn.commit(openingDate: openingDate, inputs: {
      for (final s in [
        TakeOnSection.customers,
        TakeOnSection.suppliers,
        TakeOnSection.items,
        TakeOnSection.warehouses,
      ])
        s: inputs[s]!,
    });
    await h.save(Document(
        id: OpeningTakeOn.openingItemCode,
        docType: 'Item',
        payload: {
          'item_code': OpeningTakeOn.openingItemCode,
          'item_name': 'Opening balance (previous system)',
          'item_type': 'Service',
          'stock_uom': 'Nos',
        }));
    final company =
        (await h.engine.list('Company', userRoles: systemRoles)).single.id;
    final draft = Document(
        id: 'OPEN-AR:INV-1042',
        docType: 'Sales Invoice',
        company: company,
        payload: {
          'customer': 'C001',
          'posting_date': openingDate,
          'due_date': '$year-10-15',
          'is_opening': 1,
          'income_account': OpeningTakeOn.equityAccount,
        });
    draft.children['items'] = [
      itemLine('Sales Invoice', {
        'item': OpeningTakeOn.openingItemCode,
        'qty': 1,
        'rate': 590,
      }),
    ];
    await h.save(draft);

    final (plan2, result) =
        await takeOn.commit(openingDate: openingDate, inputs: inputs);
    expect(result.errors, isEmpty);
    expect(plan2[TakeOnSection.receivables]!.rows.single.status,
        TakeOnRowStatus.resume);
    expect(result.posted[TakeOnSection.receivables], 1);
    expect(await h.balance('Debtors'), 590);
    expect(await h.trialBalanceDifference(), 0);
    expect(await h.rowCount('Sales Invoice', {'customer': 'C001'}), 1);
  });

  test('row-level validation: duplicates, bad numbers, unknown references '
      'and invented values are rejected with a reason', () async {
    final plan = await OpeningTakeOn(h.engine).plan(
      openingDate: openingDate,
      inputs: {
        TakeOnSection.customers: TakeOnInput(csv([
          'Code,Customer Name,Type',
          'C1,Alpha,Company',
          'C1,Alpha again,Company',
          'C2,,Company',
          'C3,Gamma,Partnership',
          'C/4,Delta,Company',
        ])),
        TakeOnSection.items: TakeOnInput(csv([
          'item_code,item_name,item_type,uom,selling_price',
          'A,Apple,Stock,Nos,1.00',
          'B,Banana,Stock,Nos,1.234',
          'S,Service,Service,Hour,10',
          'Z,Zest,Stock,Nos,1,234.00',
        ])),
        TakeOnSection.openingStock: TakeOnInput(csv([
          'item_code,warehouse_code,qty,value',
          'S,Main Store,1,10.00',
          'NOPE,Main Store,1,10.00',
          'A,Main Store,0,0',
          'A,Nowhere,1,1.00',
          'A,Main@Store,1,1.00',
        ])),
        TakeOnSection.receivables: TakeOnInput(csv([
          'invoice_no,customer_code,invoice_date,outstanding',
          'I1,C1,$year-09-01,100.00',
          'I1,C1,$year-09-01,100.00',
          'I2,C9,$year-09-01,100.00',
          'I3,C1,$year-10-05,100.00',
          'I4,C1,$year-09-01,-5.00',
          'I5,C1,01/09/$year,5.00',
        ])),
      },
    );
    final customers = plan[TakeOnSection.customers]!;
    expect(customers.rows.map((r) => r.status).toList(), [
      TakeOnRowStatus.create,
      TakeOnRowStatus.rejected, // duplicate code
      TakeOnRowStatus.rejected, // missing name
      TakeOnRowStatus.rejected, // bad type
      TakeOnRowStatus.rejected, // '/' in code
    ]);
    expect(customers.rows[1].problems.single, contains('line 2'));
    expect(customers.blocked, isFalse, reason: 'masters import valid rows');

    final items = plan[TakeOnSection.items]!;
    // Unquoted "1,234.00" is two fields: the row is refused, never read as 1.
    expect(items.rows[3].status, TakeOnRowStatus.rejected);
    expect(items.rows[3].problems.single, contains('6 values'));
    expect(items.rows[1].status, TakeOnRowStatus.rejected);
    expect(items.rows[1].problems.single, contains('2 decimals'));

    final stock = plan[TakeOnSection.openingStock]!;
    expect(stock.rows.every((r) => r.status == TakeOnRowStatus.rejected),
        isTrue);
    expect(stock.rows[0].problems.single, contains('Service'));
    expect(stock.rows[1].problems.single, contains('not in Atlas'));
    expect(stock.rows[2].problems.single, contains('above 0'));
    expect(stock.rows[3].problems.single, contains('Warehouse'));
    expect(stock.rows[4].problems, contains(contains('"@"')),
        reason: '"@" would let two item/warehouse pairs share one id');
    expect(stock.blocked, isTrue);

    final ar = plan[TakeOnSection.receivables]!;
    expect(ar.rows.map((r) => r.status).toList(), [
      TakeOnRowStatus.create,
      TakeOnRowStatus.rejected, // duplicate invoice
      TakeOnRowStatus.rejected, // unknown customer
      TakeOnRowStatus.rejected, // after the opening date
      TakeOnRowStatus.rejected, // negative
      TakeOnRowStatus.rejected, // not ISO date
    ]);
    expect(ar.blocked, isTrue);
    expect(plan.canImport, isFalse);

    final rejected = ar.rejectedCsv();
    expect(rejected.split('\n').first, startsWith('line,'));
    expect(rejected, contains('Dated after the opening date'));
  });

  test('a blocked posting section posts nothing at all', () async {
    final inputs = templates();
    inputs[TakeOnSection.receivables] = TakeOnInput(csv([
      'invoice_no,customer_code,invoice_date,outstanding',
      'INV-1042,C001,$year-09-15,590.00',
      'INV-1043,C404,$year-09-15,10.00',
    ]));
    final (plan, result) = await OpeningTakeOn(h.engine)
        .commit(openingDate: openingDate, inputs: inputs);
    expect(plan[TakeOnSection.receivables]!.blocked, isTrue);
    expect(await h.engine.fetch('Sales Invoice', 'OPEN-AR:INV-1042'), isNull);
    // The TB now disagrees with the (rejected) receivables, so it is
    // blocked too and nothing posts to the ledger from it.
    expect(plan[TakeOnSection.trialBalance]!.blocked, isTrue);
    expect(await h.balance('Bank'), 0);
    expect(result.created[TakeOnSection.customers], 1);
  });

  test('an unbalanced trial balance is refused, never plugged', () async {
    final inputs = templates();
    inputs[TakeOnSection.trialBalance] = TakeOnInput(csv([
      'account,debit,credit',
      'Bank,12500.00,',
      'Debtors,590.00,',
      'Stock,200.00,',
      'Creditors,,236.00',
      'VAT,,410.00',
      'Retained Earnings,,12643.99',
    ]));
    final (plan, _) = await OpeningTakeOn(h.engine)
        .commit(openingDate: openingDate, inputs: inputs);
    final tb = plan[TakeOnSection.trialBalance]!;
    expect(tb.problems.single, contains('difference 0.01'));
    expect(await h.balance('Bank'), 0);
    expect(await h.balance('Opening Balance Equity'), isNot(-0.01));
  });

  test('control totals must agree with the detail files', () async {
    final inputs = templates();
    inputs[TakeOnSection.openingStock] = TakeOnInput(csv([
      'item_code,warehouse_code,qty,value',
      'WIDGET-1,MAIN,40,199.99',
    ]));
    final plan = await OpeningTakeOn(h.engine)
        .plan(openingDate: openingDate, inputs: inputs);
    final tb = plan[TakeOnSection.trialBalance]!;
    expect(tb.problems.single, contains('stock'));
    expect(tb.problems.single, contains('0.01'));
    expect(plan.canImport, isFalse);
  });

  test('changed values on a re-import are conflicts, never overwrites',
      () async {
    final takeOn = OpeningTakeOn(h.engine);
    await takeOn.commit(openingDate: openingDate, inputs: templates());
    final changed = templates();
    changed[TakeOnSection.customers] = TakeOnInput(csv([
      'customer_code,customer_name',
      'C001,Blue Fig Cafe Renamed',
    ]));
    changed[TakeOnSection.receivables] = TakeOnInput(csv([
      'invoice_no,customer_code,invoice_date,outstanding',
      'INV-1042,C001,$year-09-15,600.00',
    ]));
    final (plan, result) =
        await takeOn.commit(openingDate: openingDate, inputs: changed);
    expect(plan[TakeOnSection.customers]!.rows.single.status,
        TakeOnRowStatus.conflict);
    expect(plan[TakeOnSection.receivables]!.rows.single.status,
        TakeOnRowStatus.conflict);
    expect(result.created, isEmpty);
    final c = await h.engine.fetch('Customer', 'C001');
    expect(c!.payload['customer_name'], 'Blue Fig Café');
    expect(await h.balance('Debtors'), 590);
  });

  test('a re-import with a different due date is a conflict', () async {
    final takeOn = OpeningTakeOn(h.engine);
    final inputs = templates();
    inputs[TakeOnSection.receivables] = TakeOnInput(csv([
      'invoice_no,customer_code,invoice_date,due_date,outstanding',
      'INV-1042,C001,$year-09-15,$year-10-15,590.00',
    ]));
    await takeOn.commit(openingDate: openingDate, inputs: inputs);
    final again = await takeOn.plan(openingDate: openingDate, inputs: inputs);
    expect(again[TakeOnSection.receivables]!.rows.single.status,
        TakeOnRowStatus.unchanged);
    inputs[TakeOnSection.receivables] = TakeOnInput(csv([
      'invoice_no,customer_code,invoice_date,due_date,outstanding',
      'INV-1042,C001,$year-09-15,$year-11-15,590.00',
    ]));
    final changed = await takeOn.plan(openingDate: openingDate, inputs: inputs);
    final row = changed[TakeOnSection.receivables]!.rows.single;
    expect(row.status, TakeOnRowStatus.conflict);
    expect(row.problems.single, contains('due date'));
  });

  test('opening stock into a position that already holds stock is refused',
      () async {
    final takeOn = OpeningTakeOn(h.engine);
    final inputs = templates();
    await takeOn.commit(openingDate: openingDate, inputs: {
      for (final s in [
        TakeOnSection.items,
        TakeOnSection.warehouses,
      ])
        s: inputs[s]!,
    });
    // Stock arrives by a normal receipt first.
    await h.saveAndSubmit(Document(
        id: '',
        docType: 'Stock Entry',
        payload: {
          'stock_entry_type': 'Material Receipt',
          'posting_date': openingDate,
          'to_warehouse': 'MAIN',
        })
      ..children['items'] = [
        itemLine('Stock Entry', {
          'item': 'WIDGET-1',
          'qty': 1,
          'target_warehouse': 'MAIN',
          'valuation_rate': 5,
        }),
      ]);
    final plan = await takeOn.plan(openingDate: openingDate, inputs: inputs);
    final row = plan[TakeOnSection.openingStock]!.rows.single;
    expect(row.status, TakeOnRowStatus.rejected);
    expect(row.problems.single, contains('already holds'));
  });

  test('money parsing is exact and refuses anything ambiguous', () {
    expect(parseCents('12'), 1200);
    expect(parseCents('12.5'), 1250);
    expect(parseCents('-0.01'), -1);
    expect(parseCents('0.10'), 10);
    expect(parseCents('1,000.00'), isNull);
    expect(parseCents('€10'), isNull);
    expect(parseCents('1.005'), isNull);
    expect(parseCents('1e3'), isNull);
    expect(parseQty('0.000001'), 0.000001);
    expect(parseQty('1.0000001'), isNull);
    expect(parseQty('-1'), isNull);
    expect(formatCents(-123456), '-1234.56');
  });

  test('a period with no financial year is refused', () async {
    final plan = await OpeningTakeOn(h.engine)
        .plan(openingDate: '1999-12-31', inputs: templates());
    expect(plan.problems.single, contains('financial year'));
    expect(plan.canImport, isFalse);
  });

  group('reconciliation', () {
    test('a clean import reconciles in every area, exactly', () async {
      final takeOn = OpeningTakeOn(h.engine);
      final (plan, _) =
          await takeOn.commit(openingDate: openingDate, inputs: templates());
      final rec = await OpeningReconciliation.compute(h.engine, plan);
      expect(rec.exceptions.map((l) => '${l.area.name} ${l.key}'), isEmpty);
      expect(rec.totals(ReconciliationArea.receivables), (59000, 59000));
      expect(rec.totals(ReconciliationArea.payables), (23600, 23600));
      expect(rec.totals(ReconciliationArea.bankCash), (1250000, 1250000));
      final stock = rec.area(ReconciliationArea.stock).first;
      expect(stock.actualQty, 40);
      expect(stock.actualCents, 20000);
      // Drill-down names the opening vouchers behind each figure.
      final debtors = rec
          .area(ReconciliationArea.trialBalance)
          .firstWhere((l) => l.key == 'Debtors');
      expect(debtors.vouchers, ['Sales Invoice OPEN-AR:INV-1042']);
    });

    test('trading after the opening date does not disturb the opening '
        'reconciliation', () async {
      final takeOn = OpeningTakeOn(h.engine);
      await takeOn.commit(openingDate: openingDate, inputs: templates());
      final company =
          (await h.engine.list('Company', userRoles: systemRoles)).single.id;
      await h.saveAndSubmit(Document(
          id: '',
          docType: 'Sales Invoice',
          company: company,
          payload: {
            'customer': 'C001',
            'posting_date': '$year-10-02',
            'due_date': '$year-10-30',
          })
        ..children['items'] = [
          itemLine('Sales Invoice', {'item': 'CONSULT', 'qty': 2, 'rate': 60}),
        ]);
      final plan = await takeOn.plan(openingDate: openingDate, inputs: templates());
      final rec = await OpeningReconciliation.compute(h.engine, plan);
      expect(rec.reconciled, isTrue,
          reason: rec.exceptions.map((l) => l.key).join(', '));

      // Ledger rows may carry the posting date as epoch milliseconds; those
      // must be compared as dates, not as text.
      final changed = await h.db.db.rawUpdate(
          "UPDATE documents SET payload = json_set(payload, '\$.posting_date', ?) "
          "WHERE doctype = 'GL Entry' "
          "AND json_extract(payload, '\$.posting_date') > ?",
          [DateTime(year, 10, 2).millisecondsSinceEpoch, openingDate]);
      expect(changed, greaterThan(0));
      final epoch = await OpeningReconciliation.compute(h.engine, plan);
      expect(epoch.reconciled, isTrue,
          reason: epoch.exceptions.map((l) => l.key).join(', '));
    });

    test('differences are reported, never absorbed', () async {
      final inputs = templates();
      final takeOn = OpeningTakeOn(h.engine);
      await takeOn.commit(openingDate: openingDate, inputs: inputs);
      // The bank statement disagrees with the old trial balance by 12.34.
      inputs[TakeOnSection.bankBalances] = TakeOnInput(csv([
        'account,statement_balance',
        'Bank,12487.66',
      ]));
      final plan = await takeOn.plan(openingDate: openingDate, inputs: inputs);
      final rec = await OpeningReconciliation.compute(h.engine, plan);
      final bank = rec.exceptions.single;
      expect(bank.area, ReconciliationArea.bankCash);
      expect(bank.differenceCents, 1234);
      expect(await h.balance('Bank'), 12500, reason: 'nothing adjusted');
    });

    test('a rejected trial-balance row is an exception with its reason',
        () async {
      final inputs = templates();
      final tbLines = inputs[TakeOnSection.trialBalance]!.csv.trim().split('\n');
      // The same account twice: the second row is rejected as a duplicate.
      inputs[TakeOnSection.trialBalance] =
          TakeOnInput([...tbLines, tbLines[1]].join('\n'));
      final plan =
          await OpeningTakeOn(h.engine).plan(openingDate: openingDate, inputs: inputs);
      final dup = plan[TakeOnSection.trialBalance]!.rows.last;
      expect(dup.status, TakeOnRowStatus.rejected);
      final rec = await OpeningReconciliation.compute(h.engine, plan);
      expect(
          rec.area(ReconciliationArea.trialBalance)
              .where((l) => l.note?.startsWith('Line ${dup.line}:') ?? false),
          hasLength(1));
    });

    test('a rejected stock row with no usable figures is still an exception',
        () async {
      final inputs = templates();
      inputs[TakeOnSection.openingStock] = TakeOnInput(csv([
        'item_code,warehouse_code,qty,value',
        'NOPE,Main Store,x,y',
      ]));
      final plan = await OpeningTakeOn(h.engine)
          .plan(openingDate: openingDate, inputs: inputs);
      final rec = await OpeningReconciliation.compute(h.engine, plan);
      final line = rec
          .area(ReconciliationArea.stock)
          .singleWhere((l) => l.key == 'NOPE@Main Store');
      expect(line.note, startsWith('Line 2:'));
      expect(rec.exceptions, contains(line));
    });

    test('rows that did not import show as differences', () async {
      final inputs = templates();
      inputs[TakeOnSection.receivables] = TakeOnInput(csv([
        'invoice_no,customer_code,invoice_date,outstanding',
        'INV-1042,C001,$year-09-15,590.00',
        'INV-1043,C404,$year-09-15,10.00',
      ]));
      final (plan, _) = await OpeningTakeOn(h.engine)
          .commit(openingDate: openingDate, inputs: inputs);
      final rec = await OpeningReconciliation.compute(h.engine, plan);
      final ar = rec.area(ReconciliationArea.receivables);
      expect({for (final l in ar) l.key: l.differenceCents},
          {'C001': -59000, 'C404': -1000});
      expect(rec.reconciled, isFalse);
    });

    test('a rejected invoice row with no usable amount is still an exception',
        () async {
      final inputs = templates();
      inputs[TakeOnSection.receivables] = TakeOnInput(csv([
        'invoice_no,customer_code,invoice_date,outstanding',
        'INV-9,C001,$year-09-15,0',
      ]));
      final plan = await OpeningTakeOn(h.engine)
          .plan(openingDate: openingDate, inputs: inputs);
      final rec = await OpeningReconciliation.compute(h.engine, plan);
      final line = rec.area(ReconciliationArea.receivables).single;
      expect(line.differenceCents, 0);
      expect(line.note, startsWith('Line 2:'));
      expect(rec.exceptions, contains(line));
    });
  });
}
