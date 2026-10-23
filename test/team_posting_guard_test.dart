import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/payments/pos_checkout.dart';
import 'package:mercantis_hub_app/team/team_posting_guard.dart';
import 'package:mercantis_hub_app/team/team_posting_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// Engine-level Team posting authority: in a Team company no flow can post
/// official accounting on this device alone, whichever screen or service
/// calls [DocumentEngine.submit]. POS keeps its offline policy under a till
/// series. Solo (no Team session) is untouched.
void main() {
  sqfliteFfiInit();

  late Directory root;
  late BooksHarness h;
  late String company;
  var team = true;

  setUp(() async {
    team = true;
    root = await Directory.systemTemp.createTemp('team-guard');
    h = await BooksHarness.open(p.join(root.path, 'books.db'), interceptors: [
      TeamPostingAuthorityGuard(() => team),
      ...hubInterceptors,
    ]);
    company = (await h.engine.list('Company', userRoles: systemRoles)).single.id;
    await h.save(Document(id: 'SVC-T', docType: 'Item', payload: {
      'item_code': 'SVC-T',
      'item_name': 'Service',
      'item_type': 'Service',
      'stock_uom': 'Nos',
    }));
    await h.save(Document(id: 'CUST-T', docType: 'Customer', payload: {
      'customer_name': 'Guard Customer',
      'customer_type': 'Company',
    }));
  });

  tearDown(() async {
    await h.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Document salesInvoice() =>
      Document(id: '', docType: 'Sales Invoice', company: company, payload: {
        'customer': 'CUST-T',
        'posting_date': isoToday(),
        'due_date': isoToday(),
      })
        ..children['items'] = [
          itemLine('Sales Invoice', {'item': 'SVC-T', 'qty': 1, 'rate': 100}),
        ];

  Document posSale({String? tillSeries}) => PosCheckout.buildPosInvoice(
        postingDate: isoToday(),
        company: company,
        tillSeries: tillSeries,
        lines: const [PosCartLine(item: 'SVC-T', qty: 1, rate: 10)],
        tenders: const [PosTender(type: 'Cash', amount: 10)],
      );

  Matcher refusedWith(String text) => throwsA(isA<DocumentEngineError>()
      .having((e) => e.validationErrors.map((v) => v.message).join(' '),
          'messages', contains(text)));

  test('a server-posted doctype cannot be submitted on the device', () async {
    final draft = await h.save(salesInvoice());
    await expectLater(
        h.submit(draft), refusedWith('posted by the Team server'));
    expect((await h.engine.fetch('Sales Invoice', draft.id))!.docStatus, 0);
    expect(await h.rowCount('GL Entry'), 0, reason: 'nothing posted locally');
  });

  test('a doctype the server cannot post yet stays a draft', () async {
    final je = await h.save(
        Document(id: '', docType: 'Journal Entry', company: company, payload: {
      'posting_date': isoToday(),
    })
          ..children['accounts'] = [
            itemLine('Journal Entry', {'account': 'Cash', 'debit': 5}, 0, 'accounts'),
            itemLine('Journal Entry', {'account': 'Sales', 'credit': 5}, 1, 'accounts'),
          ]);
    await expectLater(h.submit(je), refusedWith('cannot be posted in Atlas Team yet'));
    expect(await h.rowCount('GL Entry'), 0);
  });

  test('a till sale needs its till series, then posts offline', () async {
    await expectLater(h.saveAndSubmit(posSale()), refusedWith('receipt series'));

    final sale = await h.saveAndSubmit(posSale(tillSeries: 'T1'));
    expect(sale.id, startsWith('POS-.T1.-')); // the till's own series
    expect(sale.docStatus, 1);
    expect(await h.rowCount('GL Entry', {'voucher_no': sale.id}), greaterThan(0),
        reason: 'checkout never needs the network');
    expect(await h.trialBalanceDifference(), 0);

    // Reversed with a return, never cancelled on the device.
    await expectLater(h.engine.cancel(sale, systemRoles),
        refusedWith('Reverse it with a return'));
    expect((await h.engine.fetch('POS Invoice', sale.id))!.docStatus, 1);
  });

  test('documents that post nothing still submit in Team', () async {
    final quote = await h.saveAndSubmit(
        Document(id: '', docType: 'Quotation', company: company, payload: {
      'customer': 'CUST-T',
      'transaction_date': isoToday(),
    })
          ..children['items'] = [
            itemLine('Quotation', {'item': 'SVC-T', 'qty': 1, 'rate': 100}),
          ]);
    expect(quote.docStatus, 1);
  });

  test('Solo is unaffected: the guard is inert without a Team session',
      () async {
    team = false;
    final si = await h.saveAndSubmit(salesInvoice());
    expect(si.docStatus, 1);
    expect(await h.rowCount('GL Entry', {'voucher_no': si.id}), greaterThan(0));
    await h.engine.cancel(si, systemRoles);
    expect((await h.engine.fetch('Sales Invoice', si.id))!.docStatus, 2);
  });

  test('the server command carries the VAT rows, not just the items', () {
    final doc = salesInvoice()
      ..children['taxes'] = [
        itemLine('Sales Invoice',
            {'account_head': 'VAT Output', 'rate': 18, 'tax_amount': 18}, 0, 'taxes'),
      ];
    final cmd = buildSubmitCommand(doc);
    expect((cmd['payload'] as Map)['taxes'], [
      {'account_head': 'VAT Output', 'rate': 18, 'tax_amount': 18},
    ]);
    expect(cmd['items'], hasLength(1));
  });

  test('pure refusal helper agrees with the guard', () {
    expect(teamLocalSubmitRefusal(Document(id: 'q', docType: 'Quotation', payload: {})),
        isNull);
    expect(teamLocalSubmitRefusal(posSale(tillSeries: 'T9')), isNull);
    expect(teamLocalSubmitRefusal(posSale()), contains('receipt series'));
    expect(teamLocalSubmitRefusal(Document(id: 'e', docType: 'Expense', payload: {})),
        contains('cannot be posted in Atlas Team yet'));
    expect(teamLocalSubmitRefusal(Document(id: 'p', docType: 'Payment Entry', payload: {})),
        contains('posted by the Team server'));
  });
}
