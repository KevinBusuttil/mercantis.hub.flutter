import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';
import 'package:mercantis_hub_app/ledger/stock_balance.dart';

/// Phase 3 correctness suite for the ledger spine. All pure — no database —
/// so it directly exercises the accounting/stock logic that must be exact.
void main() {
  Document src(
    String docType, {
    required String id,
    Map<String, dynamic> payload = const {},
    Map<String, List<Map<String, dynamic>>> children = const {},
  }) {
    final doc = Document(id: id, docType: docType, payload: Map.of(payload));
    children.forEach((table, rows) {
      doc.children[table] = [
        for (var i = 0; i < rows.length; i++)
          ChildRow(
            id: '$table-$i',
            parentId: id,
            parentDocType: docType,
            tableName: table,
            rowIndex: i,
            payload: Map.of(rows[i]),
          ),
      ];
    });
    return doc;
  }

  int glCount(List rows) => rows.where((r) => r.docType == 'GL Entry').length;

  num glDebit(List rows) =>
      rows.where((r) => r.docType == 'GL Entry').fold<num>(0, (s, r) => s + asNum(r.payload['debit']));
  num glCredit(List rows) =>
      rows.where((r) => r.docType == 'GL Entry').fold<num>(0, (s, r) => s + asNum(r.payload['credit']));

  group('Sales Invoice', () {
    Document invoice() => src('Sales Invoice', id: 'SINV-1', payload: {
          'grand_total': 1000,
          'customer': 'C1',
          'debit_to': 'Debtors',
          'income_account': 'Sales',
          'posting_date': '2026-01-01',
          'currency': 'EUR',
        });

    test('posts a balanced 2-leg GL + customer invoice row', () {
      final rows = LedgerDerivation.derive(invoice(), reversal: false);
      expect(glDebit(rows), 1000);
      expect(glCredit(rows), 1000);
      final ids = rows.where((r) => r.docType == 'GL Entry').map((r) => r.id);
      expect(ids, containsAll(['GL-SINV-1-debit', 'GL-SINV-1-credit']));

      final ct = rows.firstWhere((r) => r.docType == 'Customer Transaction');
      expect(ct.id, 'CT-SINV-1');
      expect(ct.payload['trans_type'], 'Invoice');
      expect(ct.payload['amount'], 1000); // positive = customer owes
    });

    test('cancel reverses: net GL is zero and the subledger backs out', () {
      final normal = LedgerDerivation.derive(invoice(), reversal: false);
      final reversed = LedgerDerivation.derive(invoice(), reversal: true);
      final all = [...normal, ...reversed];

      // Every GL leg nets to zero across submit + cancel.
      expect(glDebit(all), glCredit(all));
      final net = all
          .where((r) => r.docType == 'GL Entry')
          .fold<num>(0, (s, r) => s + asNum(r.payload['debit']) - asNum(r.payload['credit']));
      expect(net, 0);

      final revCt = reversed.firstWhere((r) => r.docType == 'Customer Transaction');
      expect(revCt.id, 'CT-SINV-1-reversal');
      expect(revCt.payload['trans_type'], 'CreditNote');
      expect(revCt.payload['amount'], -1000);
      expect(revCt.payload['is_reversal'], true);
    });

    test('derivation is deterministic (idempotent ids)', () {
      final a = LedgerDerivation.derive(invoice(), reversal: false).map((r) => r.id).toList();
      final b = LedgerDerivation.derive(invoice(), reversal: false).map((r) => r.id).toList();
      expect(a, b);
    });
  });

  group('Sales Invoice with VAT', () {
    Document invoice() => src('Sales Invoice', id: 'SINV-2', payload: {
          'grand_total': 1180,
          'customer': 'C1',
          'debit_to': 'Debtors',
          'income_account': 'Sales',
          'posting_date': '2026-01-01',
          'currency': 'EUR',
        }, children: {
          'taxes': [
            {
              'tax_code': 'VAT18',
              'tax_type': 'VAT',
              'rate': 18,
              'tax_account': 'VAT Output',
              'taxable_amount': 1000,
              'tax_amount': 180,
            },
          ],
        });

    test('splits income net + output VAT into a balanced 3-leg GL', () {
      final rows = LedgerDerivation.derive(invoice(), reversal: false);
      expect(glCount(rows), 3);
      expect(glDebit(rows), 1180); // Dr Receivable gross
      expect(glCredit(rows), 1180); // Cr Income 1000 + Cr VAT 180

      final income = rows.firstWhere((r) => r.id == 'GL-SINV-2-credit');
      expect(income.payload['credit'], 1000); // net of tax

      final vat = rows.firstWhere((r) => r.id == 'GL-SINV-2-tax-0');
      expect(vat.payload['account'], 'VAT Output');
      expect(vat.payload['credit'], 180); // output VAT credited
      expect(vat.payload['debit'], 0);

      // Customer still owes the gross amount.
      final ct = rows.firstWhere((r) => r.docType == 'Customer Transaction');
      expect(ct.payload['amount'], 1180);
    });

    test('writes a signed Tax Transaction subledger row', () {
      final rows = LedgerDerivation.derive(invoice(), reversal: false);
      final tt = rows.firstWhere((r) => r.docType == 'Tax Transaction');
      expect(tt.id, 'TT-SINV-2-0');
      expect(tt.payload['tax_type'], 'VAT');
      expect(tt.payload['tax'], 'VAT18');
      expect(tt.payload['base_amount'], 1000);
      expect(tt.payload['tax_amount'], 180);
      expect(tt.payload['rate'], 18);
      expect(tt.payload['party_type'], 'Customer');
      expect(tt.payload['party'], 'C1');
      expect(tt.payload['voucher_no'], 'SINV-2');
    });

    test('cancel reverses VAT: GL nets zero and the subledger backs out', () {
      final all = [
        ...LedgerDerivation.derive(invoice(), reversal: false),
        ...LedgerDerivation.derive(invoice(), reversal: true),
      ];
      expect(glDebit(all), glCredit(all));
      final net = all
          .where((r) => r.docType == 'GL Entry')
          .fold<num>(0, (s, r) => s + asNum(r.payload['debit']) - asNum(r.payload['credit']));
      expect(net, 0);

      final revVat = all.firstWhere((r) => r.id == 'GL-SINV-2-tax-0-reversal');
      expect(revVat.payload['debit'], 180); // reversed output VAT debits

      final revTt = all.firstWhere((r) => r.id == 'TT-SINV-2-0-reversal');
      expect(revTt.payload['base_amount'], -1000);
      expect(revTt.payload['tax_amount'], -180);
      expect(revTt.payload['is_reversal'], true);
    });

    test('zero-rated line: no VAT GL leg but a Tax Transaction is still recorded', () {
      final zero = src('Sales Invoice', id: 'SINV-3', payload: {
        'grand_total': 500,
        'customer': 'C1',
        'debit_to': 'Debtors',
        'income_account': 'Sales',
        'posting_date': '2026-01-01',
      }, children: {
        'taxes': [
          {'tax_code': 'VAT0', 'tax_type': 'VAT', 'rate': 0, 'tax_account': 'VAT Output', 'taxable_amount': 500, 'tax_amount': 0},
        ],
      });
      final rows = LedgerDerivation.derive(zero, reversal: false);
      expect(rows.where((r) => r.id == 'GL-SINV-3-tax-0'), isEmpty); // no zero leg
      expect(glDebit(rows), 500);
      expect(glCredit(rows), 500); // income == gross (net of 0 tax)
      final tt = rows.firstWhere((r) => r.docType == 'Tax Transaction');
      expect(tt.payload['base_amount'], 500);
      expect(tt.payload['tax_amount'], 0);
    });
  });

  group('Purchase Invoice with VAT', () {
    test('splits expense net + input VAT (debit) into a balanced 3-leg GL', () {
      final rows = LedgerDerivation.derive(
        src('Purchase Invoice', id: 'PINV-2', payload: {
          'grand_total': 590,
          'supplier': 'S1',
          'credit_to': 'Creditors',
          'expense_account': 'Expenses',
          'posting_date': '2026-01-01',
        }, children: {
          'taxes': [
            {'tax_code': 'VAT18', 'tax_type': 'VAT', 'rate': 18, 'tax_account': 'VAT Input', 'taxable_amount': 500, 'tax_amount': 90},
          ],
        }),
        reversal: false,
      );
      expect(glCount(rows), 3);
      expect(glDebit(rows), 590); // Dr Expense 500 + Dr Input VAT 90
      expect(glCredit(rows), 590); // Cr Payable gross

      final expense = rows.firstWhere((r) => r.id == 'GL-PINV-2-debit');
      expect(expense.payload['debit'], 500); // net of tax

      final vat = rows.firstWhere((r) => r.id == 'GL-PINV-2-tax-0');
      expect(vat.payload['account'], 'VAT Input');
      expect(vat.payload['debit'], 90); // input VAT debited (recoverable)
      expect(vat.payload['credit'], 0);

      final tt = rows.firstWhere((r) => r.docType == 'Tax Transaction');
      expect(tt.payload['party_type'], 'Supplier');
      expect(tt.payload['party'], 'S1');
      expect(tt.payload['tax_amount'], 90);
    });
  });

  group('Purchase Invoice', () {
    test('balanced GL with payable credit + supplier owes row', () {
      final rows = LedgerDerivation.derive(
        src('Purchase Invoice', id: 'PINV-1', payload: {
          'grand_total': 500,
          'supplier': 'S1',
          'credit_to': 'Creditors',
          'expense_account': 'Expenses',
          'posting_date': '2026-01-01',
        }),
        reversal: false,
      );
      expect(glDebit(rows), 500);
      expect(glCredit(rows), 500);
      final vt = rows.firstWhere((r) => r.docType == 'Supplier Transaction');
      expect(vt.id, 'VT-PINV-1');
      expect(vt.payload['amount'], 500);
    });
  });

  group('POS Invoice (cash sale)', () {
    Document pos() => src('POS Invoice', id: 'POS-1', payload: {
          'grand_total': 1180,
          'customer': 'C1',
          'cash_account': 'Bank',
          'income_account': 'Sales',
          'set_warehouse': 'WH1',
          'posting_date': '2026-01-01',
        }, children: {
          'items': [
            {'item': 'ITM', 'qty': 2, 'rate': 500, 'warehouse': 'WH1'},
          ],
          'taxes': [
            {'tax_code': 'VAT18', 'tax_type': 'VAT', 'rate': 18, 'tax_account': 'VAT Output', 'taxable_amount': 1000, 'tax_amount': 180},
          ],
        });

    test('Dr Cash / Cr Income(net) + output VAT, issues stock, no receivable', () {
      final rows = LedgerDerivation.derive(pos(), reversal: false);

      // Balanced cash sale: Dr Cash 1180 = Cr Income 1000 + Cr VAT 180.
      expect(glDebit(rows), 1180);
      expect(glCredit(rows), 1180);
      expect(rows.firstWhere((r) => r.id == 'GL-POS-1-cash').payload['debit'], 1180);
      expect(rows.firstWhere((r) => r.id == 'GL-POS-1-income').payload['credit'], 1000);
      expect(rows.firstWhere((r) => r.id == 'GL-POS-1-tax-0').payload['credit'], 180);

      // Stock issued from the line warehouse.
      final sle = rows.firstWhere((r) => r.docType == 'Stock Ledger Entry');
      expect(sle.id, 'SLE-POS-1-0');
      expect(sle.payload['warehouse'], 'WH1');
      expect(sle.payload['qty_change'], -2);
      expect(sle.payload['trans_type'], 'Issue');

      // Cash sale → no customer subledger / settlement.
      expect(rows.where((r) => r.docType == 'Customer Transaction'), isEmpty);
      expect(rows.where((r) => r.docType == 'Settlement'), isEmpty);

      // Tax subledger still recorded.
      final tt = rows.firstWhere((r) => r.docType == 'Tax Transaction');
      expect(tt.id, 'TT-POS-1-0');
      expect(tt.payload['party_type'], 'Customer');
    });

    test('cancel reverses GL to zero and returns stock', () {
      final all = [
        ...LedgerDerivation.derive(pos(), reversal: false),
        ...LedgerDerivation.derive(pos(), reversal: true),
      ];
      expect(glDebit(all), glCredit(all));
      final net = all
          .where((r) => r.docType == 'GL Entry')
          .fold<num>(0, (s, r) => s + asNum(r.payload['debit']) - asNum(r.payload['credit']));
      expect(net, 0);
      expect(all.firstWhere((r) => r.id == 'SLE-POS-1-0-reversal').payload['qty_change'], 2);
    });
  });

  group('Payment Entry (Receive)', () {
    test('balanced GL + negative customer payment + settlement', () {
      final rows = LedgerDerivation.derive(
        src('Payment Entry', id: 'PE-1', payload: {
          'paid_amount': 400,
          'payment_type': 'Receive',
          'party': 'C1',
          'paid_from': 'Debtors',
          'paid_to': 'Bank',
          'posting_date': '2026-01-02',
        }, children: {
          'references': [
            {'reference_doctype': 'Sales Invoice', 'reference_name': 'SINV-1', 'allocated_amount': 400},
          ],
        }),
        reversal: false,
      );
      expect(glDebit(rows), 400);
      expect(glCredit(rows), 400);

      final ct = rows.firstWhere((r) => r.docType == 'Customer Transaction');
      expect(ct.payload['trans_type'], 'Payment');
      expect(ct.payload['amount'], -400); // reduces what the customer owes

      final stl = rows.firstWhere((r) => r.docType == 'Settlement');
      expect(stl.id, 'STL-PE-1-0');
      expect(stl.payload['invoice_voucher_no'], 'SINV-1');
      expect(stl.payload['party_type'], 'Customer');
      expect(stl.payload['allocated_amount'], 400);
    });
  });

  group('Journal Entry', () {
    test('one GL per line (balanced) + party adjustment with correct sign', () {
      final rows = LedgerDerivation.derive(
        src('Journal Entry', id: 'JV-1', payload: {'posting_date': '2026-01-03'}, children: {
          'accounts': [
            {'account': 'Bank', 'debit': 100, 'credit': 0},
            {'account': 'Debtors', 'debit': 0, 'credit': 100, 'party_type': 'Customer', 'party': 'C1'},
          ],
        }),
        reversal: false,
      );
      expect(glCount(rows), 2);
      expect(glDebit(rows), 100);
      expect(glCredit(rows), 100);

      final ct = rows.firstWhere((r) => r.docType == 'Customer Transaction');
      expect(ct.id, 'CT-JV-1-1');
      // Row credited the receivable (net = debit-credit = -100) → customer owes less.
      expect(ct.payload['amount'], -100);
    });
  });

  group('Stock Entry (transfer)', () {
    test('two-leg movement: -qty from source, +qty to target; reversal flips', () {
      Document entry() => src('Stock Entry', id: 'STE-1', payload: {
            'stock_entry_type': 'Material Transfer',
            'posting_date': '2026-01-04',
          }, children: {
            'items': [
              {'item': 'ITM', 'qty': 5, 'source_warehouse': 'WH1', 'target_warehouse': 'WH2', 'valuation_rate': 10},
            ],
          });

      final rows = LedgerDerivation.derive(entry(), reversal: false);
      final out = rows.firstWhere((r) => r.id == 'SLE-STE-1-0-out');
      final inn = rows.firstWhere((r) => r.id == 'SLE-STE-1-0-in');
      expect(out.payload['warehouse'], 'WH1');
      expect(out.payload['qty_change'], -5);
      expect(out.payload['trans_type'], 'Transfer');
      expect(inn.payload['warehouse'], 'WH2');
      expect(inn.payload['qty_change'], 5);

      final rev = LedgerDerivation.derive(entry(), reversal: true);
      expect(rev.firstWhere((r) => r.id == 'SLE-STE-1-0-out-reversal').payload['qty_change'], 5);
      expect(rev.firstWhere((r) => r.id == 'SLE-STE-1-0-in-reversal').payload['qty_change'], -5);
    });
  });

  group('Fulfilment stock', () {
    test('purchase receipt adds stock; delivery note removes it', () {
      final receipt = LedgerDerivation.derive(
        src('Purchase Receipt', id: 'PR-1', payload: {'set_warehouse': 'WH1', 'posting_date': '2026-01-05'}, children: {
          'items': [
            {'item': 'ITM', 'qty': 3, 'rate': 10},
          ],
        }),
        reversal: false,
      );
      final rcv = receipt.single;
      expect(rcv.payload['qty_change'], 3);
      expect(rcv.payload['warehouse'], 'WH1'); // inherited from set_warehouse
      expect(rcv.payload['trans_type'], 'Receipt');
      expect(rcv.payload['valuation_rate'], 10); // from rate fallback

      final delivery = LedgerDerivation.derive(
        src('Delivery Note', id: 'DN-1', payload: {'set_warehouse': 'WH1', 'posting_date': '2026-01-06'}, children: {
          'items': [
            {'item': 'ITM', 'qty': 2, 'warehouse': 'WH2', 'valuation_rate': 10},
          ],
        }),
        reversal: false,
      );
      final del = delivery.single;
      expect(del.payload['qty_change'], -2);
      expect(del.payload['warehouse'], 'WH2'); // line override
      expect(del.payload['trans_type'], 'Issue');
    });
  });

  group('StockBalance.compute', () {
    test('folds the full ledger into qty / value / moving rate', () {
      final snap = StockBalance.compute([
        {'qty_change': 10, 'valuation_rate': 5, 'posting_date': '2026-01-01'},
        {'qty_change': -4, 'valuation_rate': 5, 'posting_date': '2026-01-03'},
      ]);
      expect(snap.actualQty, 6);
      expect(snap.stockValue, 30);
      expect(snap.valuationRate, 5);
      expect(snap.lastMovementDate, '2026-01-03');
    });

    test('reversal rows net naturally to zero', () {
      final snap = StockBalance.compute([
        {'qty_change': 7, 'valuation_rate': 2, 'posting_date': '2026-01-01', 'is_reversal': false},
        {'qty_change': -7, 'valuation_rate': 2, 'posting_date': '2026-01-02', 'is_reversal': true},
      ]);
      expect(snap.actualQty, 0);
      expect(snap.stockValue, 0);
      expect(snap.valuationRate, 0); // guarded divide-by-zero
    });
  });

  group('Account fallbacks', () {
    test('invoices map posting accounts to company defaults', () {
      expect(LedgerDerivation.accountFallbacks('Sales Invoice'), {
        'debit_to': 'default_receivable_account',
        'income_account': 'default_income_account',
      });
      expect(LedgerDerivation.accountFallbacks('Purchase Invoice'), {
        'credit_to': 'default_payable_account',
        'expense_account': 'default_expense_account',
      });
    });

    test('payment fallbacks depend on direction', () {
      expect(
        LedgerDerivation.accountFallbacks('Payment Entry', paymentType: 'Receive'),
        {'paid_from': 'default_receivable_account', 'paid_to': 'default_cash_account'},
      );
      expect(
        LedgerDerivation.accountFallbacks('Payment Entry', paymentType: 'Pay'),
        {'paid_from': 'default_cash_account', 'paid_to': 'default_payable_account'},
      );
      // No direction / unknown doctype → no fallbacks.
      expect(LedgerDerivation.accountFallbacks('Payment Entry'), isEmpty);
      expect(LedgerDerivation.accountFallbacks('Journal Entry'), isEmpty);
    });
  });

  group('Outstanding amount', () {
    test('grand total less signed settlement allocations (idempotent)', () {
      expect(outstandingAmount(1000, const []), 1000); // freshly submitted
      // Two allocations of 300 + 200, then a reversal of the 200.
      expect(outstandingAmount(1000, [300, 200, -200]), 700);
      // Fully settled.
      expect(outstandingAmount(1000, [600, 400]), 0);
    });
  });
}
