import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// One money row of a payment-provider payout/balance report, in provider
/// terms: what the customer paid ([gross]), what the provider kept ([fee]),
/// and what reaches the bank ([net]). Refund rows carry negative amounts.
class PayoutReportRow {
  const PayoutReportRow({
    required this.gross,
    required this.fee,
    required this.net,
    this.reference,
    this.description,
  });

  final num gross;
  final num fee;
  final num net;
  final String? reference;
  final String? description;
}

/// The parsed report: the charge/refund rows that make up the payout, and
/// how many rows were skipped (unreadable, or payout/transfer rows — the
/// movement to the bank itself, which the bank statement already shows).
class PayoutReport {
  const PayoutReport({required this.rows, required this.skipped});

  final List<PayoutReportRow> rows;
  final int skipped;

  num get gross => rows.fold<num>(0, (s, r) => s + r.gross);
  num get fee => rows.fold<num>(0, (s, r) => s + r.fee);
  num get net => rows.fold<num>(0, (s, r) => s + r.net);
}

/// Pure CSV → payout-report parser (Phase 5's payment-fee reconciliation).
/// Reads the balance/payout export Stripe (and lookalikes: SumUp, PayPal
/// with renamed columns) produce: one row per charge with Amount / Fee /
/// Net columns. Same CSV tolerances as the bank importer: auto-detected
/// delimiter, header-name column mapping, US/EU number formats.
abstract final class PayoutReportCsvParser {
  static PayoutReport parse(String csv) {
    final rows = _rows(csv);
    _Columns? cols;
    var delimiter = ',';
    var dataStart = 0;
    for (var i = 0; i < rows.length && i < 20 && cols == null; i++) {
      if (rows[i].trim().isEmpty) continue;
      for (final d in const [',', ';', '\t']) {
        final candidate = _mapColumns(_split(rows[i], d));
        if (candidate.usable) {
          cols = candidate;
          delimiter = d;
          dataStart = i + 1;
          break;
        }
      }
    }
    if (cols == null) return const PayoutReport(rows: [], skipped: 0);

    final parsed = <PayoutReportRow>[];
    var skipped = 0;
    for (var i = dataStart; i < rows.length; i++) {
      if (rows[i].trim().isEmpty) continue;
      final cells = _split(rows[i], delimiter);
      String? at(int? c) =>
          (c != null && c >= 0 && c < cells.length) ? cells[c].trim() : null;

      // The payout/transfer row is the money moving to the bank — the bank
      // statement line already carries it, so counting it here would double
      // the movement.
      final type = (at(cols.type) ?? '').toLowerCase();
      if (type.contains('payout') || type.contains('transfer')) {
        skipped++;
        continue;
      }
      final gross = _parseAmount(at(cols.gross) ?? '');
      if (gross == null) {
        skipped++;
        continue;
      }
      final fee = _parseAmount(at(cols.fee) ?? '') ?? 0;
      final net = _parseAmount(at(cols.net) ?? '') ?? (gross - fee);
      final ref = at(cols.reference);
      final desc = at(cols.description);
      parsed.add(PayoutReportRow(
        gross: gross,
        fee: fee,
        net: net,
        reference: (ref != null && ref.isNotEmpty) ? ref : null,
        description: (desc != null && desc.isNotEmpty) ? desc : null,
      ));
    }
    return PayoutReport(rows: parsed, skipped: skipped);
  }

  static List<String> _rows(String csv) =>
      csv.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

  static List<String> _split(String line, String delimiter) {
    final out = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == delimiter && !inQuotes) {
        out.add(sb.toString());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    out.add(sb.toString());
    return out;
  }

  static _Columns _mapColumns(List<String> header) {
    final cols = _Columns();
    for (var i = 0; i < header.length; i++) {
      final h = header[i].trim().toLowerCase();
      if (h.isEmpty) continue;
      if (cols.fee == null && h.contains('fee')) {
        cols.fee = i;
      } else if (cols.net == null && h.contains('net')) {
        cols.net = i;
      } else if (cols.gross == null &&
          (h == 'amount' || h.contains('gross') ||
              h.contains('customer facing amount'))) {
        cols.gross = i;
      } else if (cols.type == null && h == 'type') {
        cols.type = i;
      } else if (cols.reference == null &&
          (h == 'id' || h.contains('reference') || h.contains('charge'))) {
        cols.reference = i;
      } else if (cols.description == null && h.contains('description')) {
        cols.description = i;
      }
    }
    return cols;
  }

  static num? _parseAmount(String raw) {
    var s = raw.replaceAll(RegExp(r'[^\d.,\-]'), '');
    if (s.isEmpty || s == '-') return null;
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      if (lastComma > lastDot) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (lastComma >= 0) {
      final after = s.length - lastComma - 1;
      s = after == 2 ? s.replaceAll(',', '.') : s.replaceAll(',', '');
    }
    return num.tryParse(s);
  }
}

class _Columns {
  int? gross, fee, net, type, reference, description;
  bool get usable => gross != null && fee != null;
}

/// Books a payment-provider payout (Phase 5's fee reconciliation through the
/// Phase-4 clearing machinery): one balanced Journal Entry per report —
///
///   Dr  Bank            net    (what actually arrived — matches the
///                               statement line the bank import staged)
///   Dr  Payment Fees    fee    (the provider's cut, now a visible expense)
///   Cr  Payment Clearing gross (clears what the sales collected there)
///
/// Channel/POS sales are received INTO Payment Clearing (guided payment,
/// paid-to = Payment Clearing); this entry drains it, so a nonzero clearing
/// balance means uninvoiced or unpaid-out sales — a number worth watching.
/// The JE is left as a draft for review unless [submit] is true.
class PayoutImportService {
  PayoutImportService({
    required this.engine,
    this.roles = const {'System Manager'},
  });

  final DocumentEngine engine;
  final Set<String> roles;

  static const clearingAccountId = 'Payment Clearing';
  static const feesAccountId = 'Payment Fees';

  Future<Document> importPayoutCsv({
    required String csv,
    required String postingDate,
    required String bankGlAccount,
    String? provider,
    bool submit = false,
  }) async {
    final report = PayoutReportCsvParser.parse(csv);
    if (report.rows.isEmpty) {
      throw StateError('No charge rows found — is this the provider\'s '
          'balance/payout CSV export?');
    }
    final gross = round2(report.gross);
    final fee = round2(report.fee);
    final net = round2(gross - fee);

    await _ensureAccount(clearingAccountId, rootType: 'Asset',
        accountType: 'Current Asset');
    await _ensureAccount(feesAccountId, rootType: 'Expense',
        accountType: 'Expense');

    final je = Document(id: '', docType: 'Journal Entry', payload: {
      'voucher_type': 'Bank Entry',
      'posting_date': postingDate,
      'user_remark': '${provider ?? 'Provider'} payout — '
          '${report.rows.length} charge(s), gross $gross, fees $fee',
    });
    ChildRow row(int i, Map<String, dynamic> payload) => ChildRow(
          id: '', parentId: '', parentDocType: 'Journal Entry',
          tableName: 'accounts', rowIndex: i,
          payload: payload,
        );
    je.children['accounts'] = [
      row(0, {'account': bankGlAccount, 'debit': net, 'credit': 0}),
      if (fee != 0)
        row(1, {'account': feesAccountId, 'debit': fee, 'credit': 0}),
      row(2, {'account': clearingAccountId, 'debit': 0, 'credit': gross}),
    ];
    final saved = await engine.save(je, roles);
    return submit ? engine.submit(saved, roles) : saved;
  }

  Future<void> _ensureAccount(String id,
      {required String rootType, required String accountType}) async {
    if (await engine.fetch('Account', id) != null) return;
    await engine.save(
      Document(id: id, docType: 'Account', payload: {
        'account_name': id,
        'root_type': rootType,
        'account_type': accountType,
      }),
      roles,
    );
  }
}
