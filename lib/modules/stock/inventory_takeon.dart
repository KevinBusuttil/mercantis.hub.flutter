import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// The one-time inventory take-on (Phase 1B A8, upgrade path): databases that
/// received stock before perpetual-inventory GL posting existed have value in
/// their Bins but a zero GL inventory account. This builder measures the gap
/// (Σ bin stock_value − GL balance of Stock-type accounts) and drafts the
/// balancing journal:
///
///   gap > 0:  Dr Inventory Asset / Cr Opening Balance Equity
///   gap < 0:  Dr Opening Balance Equity / Cr Inventory Asset
///
/// Returns null when the ledgers already agree (within a cent) — nothing to
/// post. The draft is an `Opening Entry` journal for the caller to review and
/// submit; after submission the Stock ↔ GL Reconciliation report reads 0.00.
class InventoryTakeOn {
  InventoryTakeOn(this._list);

  final DocumentListFn _list;

  static const _tolerance = 0.005;

  /// The current gap: positive = bins carry more value than the GL knows.
  Future<num> gap({Set<String>? userRoles}) async {
    num bins = 0;
    for (final b in await _list('Bin', userRoles: userRoles)) {
      bins += asNum(b.payload['stock_value']);
    }
    final accounts = await _list('Account', userRoles: userRoles);
    final inventoryAccounts = {
      for (final a in accounts)
        if ('${a.payload['account_type'] ?? ''}' == 'Stock') a.id,
    };
    num gl = 0;
    for (final e in await _list('GL Entry', userRoles: userRoles)) {
      if (!inventoryAccounts.contains(asNonEmpty(e.payload['account']))) {
        continue;
      }
      gl += asNum(e.payload['debit']) - asNum(e.payload['credit']);
    }
    return bins - gl;
  }

  /// Drafts the take-on journal, or returns null when nothing needs posting.
  Future<Document?> build({
    required String postingDate,
    String inventoryAccount = 'Stock',
    String equityAccount = 'Opening Balance Equity',
    String? company,
    Set<String>? userRoles,
  }) async {
    final diff = round2(await gap(userRoles: userRoles));
    if (diff.abs() < _tolerance) return null;

    final magnitude = diff.abs();
    final doc = Document(
      id: '',
      docType: 'Journal Entry',
      company: company,
      payload: {
        'workflow_state': 'Draft',
        'voucher_type': 'Opening Entry',
        'posting_date': postingDate,
        'total_debit': magnitude,
        'total_credit': magnitude,
        'difference': 0,
        'user_remark': 'Inventory take-on: align the GL inventory account '
            'with the stock ledger (one-time perpetual-inventory upgrade).',
      },
    );
    doc.children['accounts'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Journal Entry',
        tableName: 'accounts', rowIndex: 0,
        payload: {
          'account': inventoryAccount,
          'debit': diff > 0 ? magnitude : 0,
          'credit': diff > 0 ? 0 : magnitude,
        },
      ),
      ChildRow(
        id: '', parentId: '', parentDocType: 'Journal Entry',
        tableName: 'accounts', rowIndex: 1,
        payload: {
          'account': equityAccount,
          'debit': diff > 0 ? 0 : magnitude,
          'credit': diff > 0 ? magnitude : 0,
        },
      ),
    ];
    return doc;
  }
}
