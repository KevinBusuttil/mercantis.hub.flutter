import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// A customer statement (Phase 1A): every Customer Transaction subledger row
/// for one customer in a date range — invoices, credit notes, payments,
/// adjustments — with an opening balance and a running balance. The subledger
/// signs amounts (positive = the customer owes more), so the statement's
/// closing balance IS the customer's outstanding position; reversals net out
/// because their negated rows are included like any other.
class StatementLine {
  const StatementLine({
    required this.date,
    required this.kind,
    required this.reference,
    required this.amount,
    required this.balance,
  });

  final String date;
  final String kind; // Invoice / CreditNote / Payment / Adjustment
  final String reference; // voucher "type · no"
  final num amount; // signed: + owes more, − owes less
  final num balance; // running balance after this line
}

class CustomerStatement {
  const CustomerStatement({
    required this.customer,
    required this.from,
    required this.to,
    required this.openingBalance,
    required this.lines,
  });

  final String customer;
  final String from;
  final String to;
  final num openingBalance;
  final List<StatementLine> lines;

  num get closingBalance =>
      lines.isEmpty ? openingBalance : lines.last.balance;

  /// The statement as plain text — shareable/pastable anywhere until the
  /// branded-PDF path takes over document sending.
  String toText({String currency = '€'}) {
    String money(num v) => '$currency${v.toDouble().toStringAsFixed(2)}';
    final b = StringBuffer()
      ..writeln('Statement of account — $customer')
      ..writeln('Period: $from to $to')
      ..writeln('')
      ..writeln('Opening balance: ${money(openingBalance)}');
    for (final l in lines) {
      b.writeln(
          '${l.date}  ${l.kind.padRight(10)}  ${l.reference.padRight(28)}'
          '  ${money(l.amount).padLeft(12)}  ${money(l.balance).padLeft(12)}');
    }
    b
      ..writeln('')
      ..writeln('Closing balance: ${money(closingBalance)}');
    return b.toString();
  }
}

/// Builds statements from the Customer Transaction subledger.
class CustomerStatementBuilder {
  CustomerStatementBuilder(this._list);

  final DocumentListFn _list;

  Future<CustomerStatement> build({
    required String customer,
    required String from,
    required String to,
    Set<String>? userRoles,
  }) async {
    final rows = await _list('Customer Transaction',
        filters: {'customer': customer}, userRoles: userRoles);

    String dateOf(Document d) {
      final v = d.payload['posting_date'];
      if (v is String && v.isNotEmpty) return v.split('T').first;
      if (v is int) {
        return DateTime.fromMillisecondsSinceEpoch(v)
            .toIso8601String()
            .split('T')
            .first;
      }
      return '';
    }

    final dated = [for (final d in rows) (date: dateOf(d), doc: d)]
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.doc.id.compareTo(b.doc.id);
      });

    num opening = 0;
    var balance = 0.0;
    final lines = <StatementLine>[];
    for (final entry in dated) {
      final amount = asNum(entry.doc.payload['amount']);
      if (entry.date.compareTo(from) < 0) {
        opening += amount;
        continue;
      }
      if (entry.date.compareTo(to) > 0) continue;
      balance = (lines.isEmpty ? opening : lines.last.balance) + amount + 0.0;
      lines.add(StatementLine(
        date: entry.date,
        kind: '${entry.doc.payload['trans_type'] ?? ''}',
        reference:
            '${entry.doc.payload['voucher_type'] ?? ''} · ${entry.doc.payload['voucher_no'] ?? ''}',
        amount: amount,
        balance: balance,
      ));
    }

    return CustomerStatement(
      customer: customer,
      from: from,
      to: to,
      openingBalance: opening,
      lines: lines,
    );
  }
}
