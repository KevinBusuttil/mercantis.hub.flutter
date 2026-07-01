import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/hub_tax_engine.dart';
import '../ledger/ledger_values.dart';
import '../modules/pos/pos_shift_report.dart' as shift;
import '../payments/pos_checkout.dart';

const _systemRoles = {'System Manager'};

/// Everything the till needs to run: catalogue, parties, warehouses, the active
/// POS profile defaults, and the enabled tax codes (for live VAT).
class _TillContext {
  const _TillContext({
    required this.items,
    required this.customers,
    required this.warehouses,
    required this.profiles,
    required this.rateByCode,
    this.defaultWarehouse,
    this.profileTaxCode,
    this.company,
    this.sessionId,
    this.openingFloat = 0,
  });

  final List<Document> items;
  final List<Document> customers;
  final List<Document> warehouses;
  final List<Document> profiles;
  final Map<String, TaxRateInfo> rateByCode;
  final String? defaultWarehouse;
  final String? profileTaxCode;
  final String? company;

  /// The open POS Session this till posts sales into (null when no POS Profile
  /// is configured, so a session can't be opened). Drives the shift reports.
  final String? sessionId;
  final num openingFloat;
}

final _tillContextProvider = FutureProvider<_TillContext>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final items = await engine.list('Item', userRoles: _systemRoles);
  final customers = await engine.list('Customer', userRoles: _systemRoles);
  final warehouses = await engine.list('Warehouse', userRoles: _systemRoles);
  final profiles = await engine.list('POS Profile', userRoles: _systemRoles);
  final companies = await engine.list('Company', userRoles: _systemRoles);
  final company = companies.isEmpty ? null : companies.first;

  final rateByCode = <String, TaxRateInfo>{};
  for (final c in await engine.list('Tax Code', userRoles: _systemRoles)) {
    final enabled = c.payload['enabled'];
    final on = enabled == null || enabled == true || enabled == '1' || enabled == 1;
    if (!on) continue;
    rateByCode[c.id] = TaxRateInfo(
      codeId: c.id,
      description: asNonEmpty(c.payload['tax_code_name']) ?? c.id,
      rate: asNum(c.payload['rate']),
      account: asNonEmpty(c.payload['tax_account']),
    );
  }

  final profile = profiles.isEmpty ? null : profiles.first;

  // Resolve the open POS Session for *this* profile (or open one) so sales are
  // attributed to the right shift and the X/Z reports aggregate the right
  // invoices. Sessions are scoped by `pos_profile`, so a session is only
  // resolvable/creatable once a profile is configured.
  Document? session;
  if (profile != null) {
    for (final s in await engine.list('POS Session',
        filters: {'pos_profile': profile.id}, userRoles: _systemRoles)) {
      if (s.payload['status'] == 'Open') {
        session = s;
        break;
      }
    }
    session ??= await engine.save(
      Document(id: '', docType: 'POS Session', payload: {
        'pos_profile': profile.id,
        'status': 'Open',
        'opening_date': DateTime.now().toIso8601String().split('T').first,
        'opening_amount': 0,
      }),
      _systemRoles,
    );
  }

  return _TillContext(
    items: items,
    customers: customers,
    warehouses: warehouses,
    profiles: profiles,
    rateByCode: rateByCode,
    defaultWarehouse: asNonEmpty(profile?.payload['warehouse']) ??
        (warehouses.isEmpty ? null : warehouses.first.id),
    profileTaxCode: asNonEmpty(profile?.payload['tax_code']),
    company: company?.id,
    sessionId: session?.id,
    openingFloat: asNum(session?.payload['opening_amount']),
  );
});

/// A point-of-sale till: add items to a cart, see live net/VAT/total, take a
/// cash tender, and complete the sale — which posts a submitted POS Invoice
/// (cash + output VAT GL + stock issue) via the existing derivation.
class PosTillScreen extends ConsumerStatefulWidget {
  const PosTillScreen({super.key});

  @override
  ConsumerState<PosTillScreen> createState() => _PosTillScreenState();
}

class _CartLine {
  _CartLine({required this.item, required this.name, required this.taxCode, required this.rate})
      : qtyCtrl = TextEditingController(text: '1'),
        rateCtrl = TextEditingController(text: rate.toStringAsFixed(2));
  final String item;
  final String name;
  final String? taxCode;
  final num rate;
  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;

  num get qty => num.tryParse(qtyCtrl.text.trim()) ?? 0;
  num get lineRate => num.tryParse(rateCtrl.text.trim()) ?? 0;
  num get amount => qty * lineRate;
}

class _PosTillScreenState extends ConsumerState<PosTillScreen> {
  final List<_CartLine> _cart = [];
  String? _customer;
  String? _warehouse;
  bool _posting = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    for (final l in _cart) {
      l.qtyCtrl.dispose();
      l.rateCtrl.dispose();
    }
    super.dispose();
  }

  TaxComputation _totals(_TillContext ctx) => HubTaxEngine.compute(
        [
          for (final l in _cart)
            TaxLine(l.amount, l.taxCode ?? ctx.profileTaxCode),
        ],
        ctx.rateByCode,
      );

  void _addItem(Document item, _TillContext ctx) {
    setState(() {
      _cart.add(_CartLine(
        item: item.id,
        name: (item.payload['item_name'] as String?) ?? item.id,
        taxCode: asNonEmpty(item.payload['tax_code']),
        rate: asNum(item.payload['standard_rate']),
      ));
    });
  }

  Future<void> _checkout(_TillContext ctx) async {
    if (_cart.isEmpty) return;
    setState(() {
      _posting = true;
      _error = null;
      _result = null;
    });
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final draft = PosCheckout.buildPosInvoice(
        postingDate: DateTime.now().toIso8601String().split('T').first,
        customer: _customer,
        warehouse: _warehouse ?? ctx.defaultWarehouse,
        taxCode: ctx.profileTaxCode,
        company: ctx.company,
        posSession: ctx.sessionId,
        lines: [
          for (final l in _cart)
            PosCartLine(item: l.item, qty: l.qty, rate: l.lineRate, taxCode: l.taxCode),
        ],
        tenders: [PosTender(type: 'Cash', amount: _totals(ctx).grandTotal)],
      );
      final saved = await engine.save(draft, _systemRoles);
      final posted = await engine.submit(saved, _systemRoles);
      if (!mounted) return;
      setState(() {
        _posting = false;
        _result = '${posted.id} — total ${asNum(posted.payload['grand_total']).toStringAsFixed(2)}';
        for (final l in _cart) {
          l.qtyCtrl.dispose();
          l.rateCtrl.dispose();
        }
        _cart.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sale ${posted.id} completed')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        _error = e is DocumentEngineError ? e.humanMessage : '$e';
      });
    }
  }

  Future<void> _showXReport(_TillContext ctx) async {
    final sessionId = ctx.sessionId;
    if (sessionId == null) return;
    final engine = await ref.read(documentEngineProvider.future);
    final report = await shift.PosShiftReportService(
            engine: engine, roles: _systemRoles)
        .report(sessionId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('X-report (snapshot)'),
        content: _reportFigures(report),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _closeShift(_TillContext ctx) async {
    final sessionId = ctx.sessionId;
    if (sessionId == null) return;
    final counted = await _promptCountedCash();
    if (counted == null || !mounted) return;
    final engine = await ref.read(documentEngineProvider.future);
    final service =
        shift.PosShiftReportService(engine: engine, roles: _systemRoles);
    final z = await service.report(sessionId, countedCash: counted);
    await service.closeShift(sessionId,
        countedCash: counted,
        closingDate: DateTime.now().toIso8601String().split('T').first);
    if (!mounted) return;
    // Reopen a fresh session for the next shift on the next load.
    ref.invalidate(_tillContextProvider);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Shift closed (Z-report)'),
        content: _reportFigures(z),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done')),
        ],
      ),
    );
  }

  Future<num?> _promptCountedCash() {
    final controller = TextEditingController();
    return showDialog<num?>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Close shift'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Counted cash in drawer',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(null),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(c)
                  .pop(num.tryParse(controller.text.trim()) ?? 0),
              child: const Text('Close shift')),
        ],
      ),
    );
  }

  Widget _reportFigures(shift.PosShiftReport r) {
    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(k), Text(v)],
          ),
        );
    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          line('Transactions', '${r.transactions}'),
          line('Gross sales', r.grossSales.toStringAsFixed(2)),
          line('Refunds', r.refunds.toStringAsFixed(2)),
          line('Net sales', r.netSales.toStringAsFixed(2)),
          line('Items sold', '${r.itemsSold}'),
          line('Tax collected', r.taxCollected.toStringAsFixed(2)),
          const Divider(),
          for (final e in r.tenderTotals.entries)
            line(e.key, e.value.toStringAsFixed(2)),
          const Divider(),
          line('Opening float', r.openingFloat.toStringAsFixed(2)),
          line('Expected cash', r.expectedCash.toStringAsFixed(2)),
          if (r.isZReport) ...[
            line('Counted cash', (r.countedCash ?? 0).toStringAsFixed(2)),
            line('Over / short', (r.overShort ?? 0).toStringAsFixed(2)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctxAsync = ref.watch(_tillContextProvider);
    final sessionId = ctxAsync.asData?.value.sessionId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Point of Sale'),
        actions: [
          if (sessionId != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.assessment_outlined),
              tooltip: 'Shift reports',
              onSelected: (v) {
                final ctx = ctxAsync.asData!.value;
                if (v == 'x') _showXReport(ctx);
                if (v == 'z') _closeShift(ctx);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'x', child: Text('X-report (snapshot)')),
                PopupMenuItem(value: 'z', child: Text('Close shift (Z-report)')),
              ],
            ),
        ],
      ),
      body: ctxAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Failed to load: $e'))),
        data: _till,
      ),
    );
  }

  Widget _till(_TillContext ctx) {
    final totals = _totals(ctx);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _customer,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Customer (optional)', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Walk-in')),
                    for (final c in ctx.customers)
                      DropdownMenuItem(value: c.id, child: Text((c.payload['customer_name'] as String?) ?? c.id)),
                  ],
                  onChanged: _posting ? null : (v) => setState(() => _customer = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _warehouse ?? ctx.defaultWarehouse,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Warehouse', border: OutlineInputBorder()),
                  items: [
                    for (final w in ctx.warehouses)
                      DropdownMenuItem(value: w.id, child: Text((w.payload['warehouse_name'] as String?) ?? w.id)),
                  ],
                  onChanged: _posting ? null : (v) => setState(() => _warehouse = v),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: DropdownButtonFormField<String>(
            initialValue: null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Add item', border: OutlineInputBorder()),
            items: [
              for (final it in ctx.items)
                DropdownMenuItem(value: it.id, child: Text((it.payload['item_name'] as String?) ?? it.id)),
            ],
            onChanged: _posting
                ? null
                : (v) {
                    final it = ctx.items.firstWhere((d) => d.id == v);
                    _addItem(it, ctx);
                  },
          ),
        ),
        Expanded(
          child: _cart.isEmpty
              ? const Center(child: Text('Add items to start a sale'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _cart.length,
                  itemBuilder: (_, i) => _cartTile(_cart[i]),
                ),
        ),
        Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _totalRow('Net', totals.netTotal),
                _totalRow('VAT', totals.totalTax),
                _totalRow('Total', totals.grandTotal, bold: true),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_posting || _cart.isEmpty) ? null : () => _checkout(ctx),
                    icon: _posting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.point_of_sale),
                    label: Text('Take cash ${totals.grandTotal.toStringAsFixed(2)}'),
                  ),
                ),
                if (_result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Completed $_result', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cartTile(_CartLine l) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text(l.name)),
              SizedBox(
                width: 56,
                child: TextField(
                  controller: l.qtyCtrl,
                  enabled: !_posting,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: l.rateCtrl,
                  enabled: !_posting,
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Rate', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 72, child: Text(l.amount.toStringAsFixed(2), textAlign: TextAlign.right)),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: _posting
                    ? null
                    : () => setState(() {
                          l.qtyCtrl.dispose();
                          l.rateCtrl.dispose();
                          _cart.remove(l);
                        }),
              ),
            ],
          ),
        ),
      );

  Widget _totalRow(String label, num value, {bool bold = false}) {
    final style = bold ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value.toStringAsFixed(2), style: style)],
      ),
    );
  }
}
