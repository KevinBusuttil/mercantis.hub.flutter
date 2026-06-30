import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/modules/banking/bank_statement_csv_importer.dart';

/// H1 — the bank statement CSV importer across the formats banks actually emit.
void main() {
  test('EU export: semicolons, comma decimals, debit/credit, quoted commas', () {
    const csv = 'Date;Description;Debit;Credit;Balance\n'
        '05/01/2026;"ACME, Inc";;1.234,56;5.000,00\n'
        '06/01/2026;Rent;800,00;;4.200,00\n';
    final r = BankStatementCsvImporter.parse(csv);

    expect(r.lines.length, 2);
    expect(r.skipped, 0);
    final a = r.lines[0];
    expect(a.postingDate, '2026-01-05');
    expect(a.description, 'ACME, Inc'); // quoted comma preserved
    expect(a.deposit, 1234.56);
    expect(a.amount, 1234.56);
    final b = r.lines[1];
    expect(b.postingDate, '2026-01-06');
    expect(b.withdrawal, 800);
    expect(b.amount, -800);
  });

  test('US export: commas, dot decimals, a single signed amount column', () {
    const csv = 'Date,Description,Amount\n'
        '2026-02-10,Salary,"2,500.00"\n'
        '2026-02-11,Coffee,-4.50\n';
    final r = BankStatementCsvImporter.parse(csv);

    expect(r.lines.length, 2);
    expect(r.lines[0].deposit, 2500);
    expect(r.lines[0].amount, 2500);
    expect(r.lines[1].withdrawal, 4.5);
    expect(r.lines[1].amount, -4.5);
  });

  test('header need not be the first row (skips export preamble)', () {
    const csv = 'My Bank plc\n'
        'Statement for account 1234\n'
        '\n'
        'Posting Date,Narrative,Reference,Amount\n'
        '12/03/2026,Transfer,REF99,100.00\n';
    final r = BankStatementCsvImporter.parse(csv);

    expect(r.lines.length, 1);
    final l = r.lines.single;
    expect(l.postingDate, '2026-03-12'); // day-first
    expect(l.description, 'Transfer');
    expect(l.reference, 'REF99');
    expect(l.deposit, 100);
  });

  test('rows without a parseable date or amount are skipped, not dropped silently', () {
    const csv = 'Date,Description,Amount\n'
        '2026-04-01,Good,10.00\n'
        'not-a-date,Bad,5.00\n'
        '2026-04-02,NoAmount,\n';
    final r = BankStatementCsvImporter.parse(csv);

    expect(r.lines.length, 1);
    expect(r.lines.single.description, 'Good');
    expect(r.skipped, 2);
  });

  test('a single comma is a thousands separator when not 2 trailing digits', () {
    const csv = 'Date,Amount\n2026-05-01,"1,234"\n';
    final r = BankStatementCsvImporter.parse(csv);
    expect(r.lines.single.amount, 1234); // not 1.234
  });

  test('toPayload yields a ready Bank Statement Line body', () {
    const csv = 'Date,Description,Amount\n2026-06-01,Test,42.00\n';
    final p = BankStatementCsvImporter.parse(csv).lines.single.toPayload();
    expect(p['posting_date'], '2026-06-01');
    expect(p['amount'], 42);
    expect(p['deposit'], 42);
    expect(p['withdrawal'], 0);
    expect(p['status'], 'Unreconciled');
  });

  test('empty / headerless input yields no lines', () {
    expect(BankStatementCsvImporter.parse('').lines, isEmpty);
    expect(BankStatementCsvImporter.parse('just,some,noise\n1,2,3\n').lines,
        isEmpty);
  });
}
