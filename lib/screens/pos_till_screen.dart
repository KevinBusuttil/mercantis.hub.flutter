import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/hub_tax_engine.dart';
import '../ledger/ledger_values.dart';
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
  });

  final List<Document> items;
  final List<Document> customers;
  final List<Document> warehouses;
  final List<Document> profiles;
  final Map<String, TaxRateInfo> rateByCode;
  final String? defaultWarehouse;
  final String? profileTaxCode;
  final String? company;
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

  @override
  Widget build(BuildContext context) {
    final ctxAsync = ref.watch(_tillContextProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Point of Sale')),
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
                  value: _customer,
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
                  value: _warehouse ?? ctx.defaultWarehouse,
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
            value: null,
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
