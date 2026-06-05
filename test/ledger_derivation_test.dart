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
    final invoice = () => src('Sales Invoice', id: 'SINV-1', payload: {
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
      final entry = () => src('Stock Entry', id: 'STE-1', payload: {
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
