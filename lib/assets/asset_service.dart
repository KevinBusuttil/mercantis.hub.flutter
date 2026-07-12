import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// S10: the fixed-asset lifecycle. Capitalise builds the straight-line
/// schedule and puts the asset In Use; postDueDepreciation turns due
/// periods into submitted Journal Entries (Dr expense / Cr accumulated),
/// stamping each row so a re-run posts nothing twice; dispose clears the
/// gross and the accumulated depreciation, books any proceeds, and sends
/// the balance to gain/loss.
class AssetService {
  AssetService(this._engine, {Set<String> roles = _systemRoles})
      : _roles = roles;

  final DocumentEngine _engine;
  final Set<String> _roles;

  /// Same-day-next-month stepping with an end-of-month clamp, so a
  /// Jan 31 start depreciates on Feb 28, not Mar 3.
  static DateTime _addMonths(DateTime date, int months) {
    final y = date.year + (date.month - 1 + months) ~/ 12;
    final m = (date.month - 1 + months) % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, date.day > lastDay ? lastDay : date.day);
  }

  /// The straight-line schedule: n equal monthly amounts with the LAST
  /// period absorbing the rounding, so the rows always sum to exactly
  /// gross − salvage.
  static List<Map<String, dynamic>> buildSchedule({
    required DateTime start,
    required num gross,
    required num salvage,
    required int months,
  }) {
    if (months <= 0) {
      throw StateError('Useful life must be at least one month.');
    }
    final depreciable = round2(gross - salvage);
    if (depreciable <= 0) {
      throw StateError(
          'Nothing to depreciate: gross $gross, salvage $salvage.');
    }
    final monthly = round2(depreciable / months);
    final rows = <Map<String, dynamic>>[];
    num scheduled = 0;
    for (var i = 0; i < months; i++) {
      final amount = i == months - 1
          ? round2(depreciable - scheduled)
          : monthly;
      scheduled = round2(scheduled + amount);
      rows.add({
        'period_date':
            _addMonths(start, i + 1).toIso8601String().split('T').first,
        'amount': amount,
      });
    }
    return rows;
  }

  /// Puts a Draft asset In Use: resolves accounts (asset else category),
  /// validates them, generates the schedule. Idempotent-hostile on
  /// purpose — an In Use or Disposed asset refuses.
  Future<Document> capitalise(String assetId) async {
    final asset = await _engine.fetch('Asset', assetId);
    if (asset == null) throw StateError('Asset $assetId not found.');
    if ('${asset.payload['status']}' != 'Draft') {
      throw StateError(
          'Asset $assetId is ${asset.payload['status']} — only a Draft '
          'asset capitalises.');
    }
    final accounts = await _resolveAccounts(asset);
    final months = await _usefulLifeMonths(asset);
    final startRaw = asNonEmpty(asset.payload['depreciation_start']) ??
        '${asset.payload['purchase_date']}';
    final start = DateTime.tryParse(startRaw);
    if (start == null) {
      throw StateError('Asset $assetId has no usable start date.');
    }

    final rows = buildSchedule(
      start: start,
      gross: asNum(asset.payload['gross_purchase_amount']),
      salvage: asNum(asset.payload['salvage_value']),
      months: months,
    );
    asset.children['schedule'] = [
      for (var i = 0; i < rows.length; i++)
        ChildRow(
          id: '', parentId: asset.id, parentDocType: 'Asset',
          tableName: 'schedule', rowIndex: i,
          payload: rows[i],
        ),
    ];
    asset.payload['status'] = 'In Use';
    // Pin the resolved accounts so later category edits can't reroute
    // an asset that's already depreciating.
    asset.payload['asset_account'] = accounts.asset;
    asset.payload['accumulated_depreciation_account'] = accounts.accumulated;
    asset.payload['depreciation_expense_account'] = accounts.expense;
    return _engine.save(asset, _roles);
  }

  /// Posts every unposted period up to [asOf] across all In Use assets
  /// (or just [assetId]) — one submitted JE per period, stamped back on
  /// the row. Returns how many periods posted; a re-run returns 0.
  Future<int> postDueDepreciation({DateTime? asOf, String? assetId}) async {
    final cutoff = (asOf ?? DateTime.now()).toIso8601String().split('T').first;
    final assets = assetId != null
        ? [await _engine.fetch('Asset', assetId)]
        : await _engine.list('Asset', userRoles: _roles);
    var posted = 0;
    for (final header in assets) {
      if (header == null) continue;
      if ('${header.payload['status']}' != 'In Use') continue;
      final asset = await _engine.fetch('Asset', header.id) ?? header;
      final rows = asset.children['schedule'] ?? const <ChildRow>[];
      var dirty = false;
      for (final row in rows) {
        if (isTrue(row.payload['posted'])) continue;
        if ('${row.payload['period_date']}'.compareTo(cutoff) > 0) continue;
        final je = await _depreciationEntry(asset, row);
        row.payload['posted'] = 1;
        row.payload['journal_entry'] = je.id;
        dirty = true;
        posted++;
      }
      if (dirty) await _engine.save(asset, _roles);
    }
    return posted;
  }

  Future<Document> _depreciationEntry(Document asset, ChildRow row) async {
    // The JE posts under the ASSET's company — multi-company books must
    // not fall to the defaults interceptor's first company.
    final je = Document(id: '', docType: 'Journal Entry',
        company: asset.company, payload: {
      'voucher_type': 'Depreciation Entry',
      'posting_date': row.payload['period_date'],
      'user_remark': 'Depreciation — ${asset.payload['asset_name']} '
          '(${asset.id})',
    });
    final amount = asNum(row.payload['amount']);
    ChildRow leg(int i, String account, num debit, num credit) => ChildRow(
          id: '', parentId: '', parentDocType: 'Journal Entry',
          tableName: 'accounts', rowIndex: i,
          payload: {'account': account, 'debit': debit, 'credit': credit},
        );
    je.children['accounts'] = [
      leg(0, '${asset.payload['depreciation_expense_account']}', amount, 0),
      leg(1, '${asset.payload['accumulated_depreciation_account']}', 0,
          amount),
    ];
    return _engine.submit(await _engine.save(je, _roles), _roles);
  }

  /// Net book value as of the posted schedule: gross − posted periods.
  static num netBookValue(Document asset) {
    num depreciated = 0;
    for (final row in asset.children['schedule'] ?? const <ChildRow>[]) {
      if (isTrue(row.payload['posted'])) {
        depreciated += asNum(row.payload['amount']);
      }
    }
    return round2(
        asNum(asset.payload['gross_purchase_amount']) - depreciated);
  }

  /// Disposal: one JE clears the asset off the books — Cr gross off the
  /// asset account, Dr the accumulated depreciation posted so far, Dr any
  /// [proceeds] into [proceedsAccount], and the remainder Dr loss / Cr
  /// gain on [gainLossAccount]. The asset goes Disposed and future
  /// depreciation runs skip it; the unposted schedule stays visible as
  /// the record of what never ran.
  Future<Document> dispose(
    String assetId, {
    required String gainLossAccount,
    num proceeds = 0,
    String? proceedsAccount,
    DateTime? date,
  }) async {
    final asset = await _engine.fetch('Asset', assetId);
    if (asset == null) throw StateError('Asset $assetId not found.');
    if ('${asset.payload['status']}' != 'In Use') {
      throw StateError(
          'Asset $assetId is ${asset.payload['status']} — only an In Use '
          'asset disposes.');
    }
    if (proceeds > 0 && proceedsAccount == null) {
      throw StateError('Proceeds need a proceeds account (cash/bank).');
    }

    final gross = asNum(asset.payload['gross_purchase_amount']);
    final accumulated = round2(gross - netBookValue(asset));
    final result = round2(proceeds + accumulated - gross);
    final when =
        (date ?? DateTime.now()).toIso8601String().split('T').first;

    final je = Document(id: '', docType: 'Journal Entry',
        company: asset.company, payload: {
      'voucher_type': 'Disposal Entry',
      'posting_date': when,
      'user_remark': 'Disposal — ${asset.payload['asset_name']} '
          '(${asset.id}), proceeds ${proceeds.toStringAsFixed(2)}',
    });
    var i = 0;
    ChildRow leg(String account, num debit, num credit) => ChildRow(
          id: '', parentId: '', parentDocType: 'Journal Entry',
          tableName: 'accounts', rowIndex: i++,
          payload: {'account': account, 'debit': debit, 'credit': credit},
        );
    je.children['accounts'] = [
      leg('${asset.payload['asset_account']}', 0, gross),
      if (accumulated > 0)
        leg('${asset.payload['accumulated_depreciation_account']}',
            accumulated, 0),
      if (proceeds > 0) leg(proceedsAccount!, proceeds, 0),
      if (result < 0) leg(gainLossAccount, -result, 0), // loss
      if (result > 0) leg(gainLossAccount, 0, result), // gain
    ];
    final posted = await _engine.submit(await _engine.save(je, _roles), _roles);

    asset.payload['status'] = 'Disposed';
    asset.payload['disposal_date'] = when;
    asset.payload['disposal_journal'] = posted.id;
    await _engine.save(asset, _roles);
    return posted;
  }

  Future<({String asset, String accumulated, String expense})>
      _resolveAccounts(Document asset) async {
    Document? category;
    final categoryId = asNonEmpty(asset.payload['category']);
    if (categoryId != null) {
      category = await _engine.fetch('Asset Category', categoryId);
    }
    String? pick(String key) =>
        asNonEmpty(asset.payload[key]) ??
        asNonEmpty(category?.payload[key]);
    final assetAccount = pick('asset_account');
    final accumulated = pick('accumulated_depreciation_account');
    final expense = pick('depreciation_expense_account');
    if (assetAccount == null || accumulated == null || expense == null) {
      throw StateError(
          'Asset ${asset.id} needs asset, accumulated-depreciation and '
          'depreciation-expense accounts (on the asset or its category).');
    }
    return (asset: assetAccount, accumulated: accumulated, expense: expense);
  }

  Future<int> _usefulLifeMonths(Document asset) async {
    var months = asNum(asset.payload['useful_life_months']).toInt();
    if (months <= 0) {
      final categoryId = asNonEmpty(asset.payload['category']);
      if (categoryId != null) {
        final category =
            await _engine.fetch('Asset Category', categoryId);
        months = asNum(category?.payload['useful_life_months']).toInt();
      }
    }
    if (months <= 0) {
      throw StateError(
          'Asset ${asset.id} has no useful life (asset or category).');
    }
    return months;
  }
}
