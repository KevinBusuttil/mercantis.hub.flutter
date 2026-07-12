import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// V6: interim valuations and retention. Each application certifies a
/// CUMULATIVE percentage; the service bills the delta less retention
/// (retention% of the application, capped so total held never exceeds
/// cap% of the contract value) as a submitted Sales Invoice, and records
/// the whole position on the contract's valuation rows. Practical
/// completion unlocks the retention release — one final invoice for
/// everything still held.
class ValuationService {
  ValuationService(this._engine, {Set<String> roles = _systemRoles})
      : _roles = roles;

  final DocumentEngine _engine;
  final Set<String> _roles;

  /// Total retention currently held on [contract]: Σ valuations'
  /// retention − what's been released. Computed, never stored.
  static num retentionHeld(Document contract) {
    num held = 0;
    for (final row
        in contract.children['valuations'] ?? const <ChildRow>[]) {
      held += asNum(row.payload['retention_this_time']);
    }
    return round2(held - asNum(contract.payload['retention_released']));
  }

  /// The certified cumulative percentage so far (0 when nothing billed).
  static num certifiedPercent(Document contract) {
    num best = 0;
    for (final row
        in contract.children['valuations'] ?? const <ChildRow>[]) {
      final pct = asNum(row.payload['cumulative_percent']);
      if (pct > best) best = pct;
    }
    return best;
  }

  /// Bills valuation #N at [cumulativePercent] complete. The invoice is
  /// the delta since the last application, less capped retention, and
  /// submits immediately — a certified application is contractual.
  Future<Document> bill(
    String contractId, {
    required num cumulativePercent,
    DateTime? date,
  }) async {
    final contract = await _require(contractId, expected: {'Active'});
    if (cumulativePercent <= 0 || cumulativePercent > 100) {
      throw StateError(
          'A valuation certifies between 0 and 100 percent.');
    }
    final previous = certifiedPercent(contract);
    if (cumulativePercent <= previous) {
      throw StateError(
          'Valuations are cumulative: ${contract.id} is already '
          'certified at $previous% — $cumulativePercent% goes backwards.');
    }
    final value = asNum(contract.payload['contract_value']);
    if (value <= 0) {
      throw StateError('${contract.id} has no contract value.');
    }

    final gross = round2(value * (cumulativePercent - previous) / 100);
    final retentionPct = asNum(contract.payload['retention_percent']);
    final capPct = asNum(contract.payload['retention_cap_percent']);
    final cap = round2(value * capPct / 100);
    final alreadyHeld = round2(retentionHeld(contract) +
        asNum(contract.payload['retention_released']));
    var retention = round2(gross * retentionPct / 100);
    if (alreadyHeld + retention > cap) {
      retention = round2(cap - alreadyHeld);
      if (retention < 0) retention = 0;
    }
    final net = round2(gross - retention);
    if (net <= 0) {
      throw StateError(
          'Application of ${gross.toStringAsFixed(2)} nets to nothing '
          'after retention — check the percentages.');
    }

    final rows = contract.children['valuations'] ?? <ChildRow>[];
    final number = rows.length + 1;
    final when =
        (date ?? DateTime.now()).toIso8601String().split('T').first;

    // The contract's company rides onto the invoice — multi-company
    // books must not fall to the defaults interceptor's first company
    // (Codex, PR #169).
    final invoice = Document(id: '', docType: 'Sales Invoice',
        company: contract.company, payload: {
      'customer': contract.payload['customer'],
      'posting_date': when,
      if (asNonEmpty(contract.payload['tax_code']) != null)
        'tax_code': contract.payload['tax_code'],
    });
    invoice.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {
          'item': contract.payload['billing_item'],
          'qty': 1,
          'rate': net,
          'description': 'Application #$number — '
              '${contract.payload['contract_name']}: '
              '$cumulativePercent% complete '
              '(gross ${gross.toStringAsFixed(2)}, retention '
              '${retention.toStringAsFixed(2)})',
        },
      ),
    ];
    final posted =
        await _engine.submit(await _engine.save(invoice, _roles), _roles);

    rows.add(ChildRow(
      id: '', parentId: contract.id,
      parentDocType: 'Construction Contract',
      tableName: 'valuations', rowIndex: rows.length,
      payload: {
        'valuation_no': number,
        'valuation_date': when,
        'cumulative_percent': cumulativePercent,
        'gross_this_time': gross,
        'retention_this_time': retention,
        'net_this_time': net,
        'sales_invoice': posted.id,
      },
    ));
    contract.children['valuations'] = rows;
    await _engine.save(contract, _roles);
    return posted;
  }

  /// Active → Practically Complete: the works are done; retention can
  /// release.
  Future<Document> markPracticallyComplete(String contractId) async {
    final contract = await _require(contractId, expected: {'Active'});
    contract.payload['status'] = 'Practically Complete';
    return _engine.save(contract, _roles);
  }

  /// Bills everything still held as the final retention invoice and
  /// closes the contract. Only after practical completion — releasing
  /// retention on live works is exactly what the mechanism prevents.
  Future<Document> releaseRetention(String contractId,
      {DateTime? date}) async {
    final contract =
        await _require(contractId, expected: {'Practically Complete'});
    final held = retentionHeld(contract);
    if (held <= 0) {
      throw StateError(
          '${contract.id} holds no retention to release.');
    }
    final item = asNonEmpty(contract.payload['retention_item']) ??
        asNonEmpty(contract.payload['billing_item']);
    final when =
        (date ?? DateTime.now()).toIso8601String().split('T').first;

    final invoice = Document(id: '', docType: 'Sales Invoice',
        company: contract.company, payload: {
      'customer': contract.payload['customer'],
      'posting_date': when,
      if (asNonEmpty(contract.payload['tax_code']) != null)
        'tax_code': contract.payload['tax_code'],
    });
    invoice.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {
          'item': item,
          'qty': 1,
          'rate': held,
          'description': 'Retention release — '
              '${contract.payload['contract_name']}',
        },
      ),
    ];
    final posted =
        await _engine.submit(await _engine.save(invoice, _roles), _roles);

    contract.payload['retention_released'] = round2(
        asNum(contract.payload['retention_released']) + held);
    contract.payload['release_invoice'] = posted.id;
    contract.payload['status'] = 'Closed';
    await _engine.save(contract, _roles);
    return posted;
  }

  Future<Document> _require(String contractId,
      {required Set<String> expected}) async {
    final contract =
        await _engine.fetch('Construction Contract', contractId);
    if (contract == null) {
      throw StateError('Construction Contract $contractId not found.');
    }
    if (!expected.contains('${contract.payload['status']}')) {
      throw StateError(
          '${contract.id} is ${contract.payload['status']}, not '
          '${expected.join('/')}.');
    }
    return contract;
  }
}
