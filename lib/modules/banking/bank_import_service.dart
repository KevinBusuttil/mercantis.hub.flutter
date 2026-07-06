import 'package:mercantis_core/mercantis_core.dart';

import 'bank_statement_csv_importer.dart';

/// The outcome of one CSV import: how many lines were created, how many were
/// already in the book (idempotent re-import), and how many rows the parser
/// couldn't read.
class BankImportResult {
  const BankImportResult({
    required this.imported,
    required this.duplicates,
    required this.skipped,
    required this.batchId,
  });

  final int imported;
  final int duplicates;
  final int skipped;
  final String batchId;
}

/// Persists parsed bank-statement lines (Phase 4). The audit found the CSV
/// parser was invoked only from tests and nothing saved its output — and a
/// re-import would have duplicated every line. Each line gets a
/// DETERMINISTIC id derived from (account, date, amounts, description,
/// reference, occurrence ordinal), so importing the same file twice creates
/// nothing new, while two genuinely identical transactions inside one file
/// (same coffee twice in a day) stay distinct via the ordinal.
class BankImportService {
  BankImportService({required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  Future<BankImportResult> importCsv({
    required String bankAccountId,
    required String csv,
    String? company,
  }) async {
    final parsed = BankStatementCsvImporter.parse(csv);
    final batchId = 'IMP-${DateTime.now().millisecondsSinceEpoch}';

    var imported = 0;
    var duplicates = 0;
    final seen = <String, int>{};
    for (final line in parsed.lines) {
      final key = [
        bankAccountId,
        line.postingDate,
        '${line.deposit}',
        '${line.withdrawal}',
        line.description ?? '',
        line.reference ?? '',
      ].join('|');
      final ordinal = seen[key] = (seen[key] ?? 0) + 1;
      final id = 'BSL-${_fnv1a(key)}-$ordinal';

      if (await engine.fetch('Bank Statement Line', id) != null) {
        duplicates++;
        continue;
      }
      await engine.save(
        Document(id: id, docType: 'Bank Statement Line', company: company, payload: {
          'bank_account': bankAccountId,
          'posting_date': line.postingDate,
          if (line.description != null) 'description': line.description,
          if (line.reference != null) 'reference_number': line.reference,
          'deposit': line.deposit,
          'withdrawal': line.withdrawal,
          'status': 'Unreconciled',
          'import_batch': batchId,
        }),
        roles,
      );
      imported++;
    }

    return BankImportResult(
      imported: imported,
      duplicates: duplicates,
      skipped: parsed.skipped,
      batchId: batchId,
    );
  }

  /// FNV-1a 64-bit over [input], hex-encoded — stable, dependency-free, and
  /// plenty for statement-line identity.
  static String _fnv1a(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
