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
    this.pricesIncludeTax = false,
    this.company,
    this.profileId,
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
  final bool pricesIncludeTax;
  final String? company;

  /// The configured POS Profile (null until one exists).
  final String? profileId;

  /// The open POS Session this till posts sales into (null until the operator
  /// opens the till with a counted float). Drives the shift reports.
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
    // No open session → the screen shows the Open-till panel, which creates
    // one with a real counted opening float (Phase 6: no more hardcoded 0).
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
    pricesIncludeTax: isTrue(profile?.payload['prices_include_tax']),
    company: company?.id,
    profileId: profile?.id,
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
      : qty = 1,
        lineRate = rate;
  final String item;
  final String name;
  final String? taxCode;

  /// Catalogue default rate (used only to seed [lineRate]).
  final num rate;

  /// Editable per-line quantity and rate, held as plain values so the Atlas
  /// stepper / input rows can drive them via value+onChanged (they own their
  /// own text controllers).
  num qty;
  num lineRate;

  num get amount => qty * lineRate;
}

class _PosTillScreenState extends ConsumerState<PosTillScreen> {
  final List<_CartLine> _cart = [];
  String? _customer;
  String? _warehouse;
  bool _posting = false;
  String? _result;
  String? _error;

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

  Future<void> _checkout(_TillContext ctx, List<PosTender> tenders) async {
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
        pricesIncludeTax: ctx.pricesIncludeTax,
        company: ctx.company,
        posSession: ctx.sessionId,
        lines: [
          for (final l in _cart)
            PosCartLine(item: l.item, qty: l.qty, rate: l.lineRate, taxCode: l.taxCode),
        ],
        tenders: tenders,
      );
      final saved = await engine.save(draft, _systemRoles);
      final posted = await engine.submit(saved, _systemRoles);
      if (!mounted) return;
      setState(() {
        _posting = false;
        _result = '${posted.id} — total ${asNum(posted.payload['grand_total']).toStringAsFixed(2)}';
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

  /// Opens the shift with a counted cash float (Phase 6: the float used to be
  /// hardcoded to 0, which made every cash-variance check meaningless).
  Future<void> _openTill(_TillContext ctx) async {
    final profileId = ctx.profileId;
    if (profileId == null) return;
    final ctrl = TextEditingController(text: '0.00');
    final float = await showDialog<num>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Open till'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Opening cash float',
            helperText: 'Count the drawer before trading — the Z-report '
                'compares expected cash against this.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(c, num.tryParse(ctrl.text.trim()) ?? 0),
              child: const Text('Open till')),
        ],
      ),
    );
    if (float == null) return;
    final engine = await ref.read(documentEngineProvider.future);
    await engine.save(
      Document(id: '', docType: 'POS Session', payload: {
        'pos_profile': profileId,
        'status': 'Open',
        'opening_date': DateTime.now().toIso8601String().split('T').first,
        'opening_amount': float,
      }),
      _systemRoles,
    );
    ref.invalidate(_tillContextProvider);
  }

  /// Collects the tender split — cash, card, or both. Validates that the
  /// tendered total covers the sale and shows the change due live.
  Future<void> _takePayment(_TillContext ctx) async {
    final total = _totals(ctx).grandTotal;
    final cashCtrl = TextEditingController(text: total.toStringAsFixed(2));
    final cardCtrl = TextEditingController(text: '0.00');
    final tenders = await showDialog<List<PosTender>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) {
          final cash = num.tryParse(cashCtrl.text.trim()) ?? 0;
          final card = num.tryParse(cardCtrl.text.trim()) ?? 0;
          final tendered = cash + card;
          final change = tendered - total;
          return AlertDialog(
            title: Text('Take payment — €${total.toStringAsFixed(2)}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: cashCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Cash', isDense: true),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cardCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Card', isDense: true),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setDialogState(() {
                        cashCtrl.text = total.toStringAsFixed(2);
                        cardCtrl.text = '0.00';
                      }),
                      child: const Text('Exact cash'),
                    ),
                    TextButton(
                      onPressed: () => setDialogState(() {
                        cashCtrl.text = '0.00';
                        cardCtrl.text = total.toStringAsFixed(2);
                      }),
                      child: const Text('Exact card'),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    change >= 0
                        ? 'Change due: €${change.toStringAsFixed(2)}'
                        : 'Short by €${(-change).toStringAsFixed(2)}',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: tendered + 0.0001 < total
                    ? null
                    : () => Navigator.pop(c, [
                          if (cash > 0) PosTender(type: 'Cash', amount: cash),
                          if (card > 0) PosTender(type: 'Card', amount: card),
                        ]),
                child: const Text('Complete sale'),
              ),
            ],
          );
        },
      ),
    );
    if (tenders == null || tenders.isEmpty) return;
    await _checkout(ctx, tenders);
  }

  Future<void> _showXReport(_TillContext ctx) async {
    final sessionId = ctx.sessionId;
    if (sessionId == null) return;
    final engine = await ref.read(documentEngineProvider.future);
    final report = await shift.PosShiftReportService(
            engine: engine, roles: _systemRoles)
        .report(sessionId);
    if (!mounted) return;
    await _showReportSheet('X-report (snapshot)', report, doneLabel: 'Close');
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
    await _showReportSheet('Shift closed (Z-report)', z, doneLabel: 'Done');
  }

  Future<num?> _promptCountedCash() {
    return showAtlasBottomSheet<num?>(
      context,
      // Small fixed form — a plain modal / desktop dialog, not a draggable sheet.
      draggable: false,
      builder: (_, __) => const _CountedCashSheet(),
    );
  }

  Future<void> _showReportSheet(String title, shift.PosShiftReport r,
      {required String doneLabel}) {
    return showAtlasBottomSheet<void>(
      context,
      draggable: false,
      builder: (sheetCtx, __) => AtlasBottomSheet(
        showHandle: false,
        title: title,
        body: Padding(
          padding: const EdgeInsets.all(MercantisSpacing.lg),
          child: _reportFigures(r),
        ),
        footer: AtlasBottomActionBar(
          primaryLabel: doneLabel,
          onPrimary: () => Navigator.of(sheetCtx).pop(),
        ),
      ),
    );
  }

  Widget _reportFigures(shift.PosShiftReport r) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AtlasTotalRow(label: 'Transactions', value: '${r.transactions}'),
        AtlasTotalRow(label: 'Gross sales', value: r.grossSales.toStringAsFixed(2)),
        AtlasTotalRow(label: 'Refunds', value: r.refunds.toStringAsFixed(2)),
        AtlasTotalRow(label: 'Net sales', value: r.netSales.toStringAsFixed(2)),
        AtlasTotalRow(label: 'Items sold', value: '${r.itemsSold}'),
        AtlasTotalRow(label: 'Tax collected', value: r.taxCollected.toStringAsFixed(2)),
        const Divider(),
        for (final e in r.tenderTotals.entries)
          AtlasTotalRow(label: e.key, value: e.value.toStringAsFixed(2)),
        const Divider(),
        AtlasTotalRow(label: 'Opening float', value: r.openingFloat.toStringAsFixed(2)),
        AtlasTotalRow(label: 'Expected cash', value: r.expectedCash.toStringAsFixed(2)),
        if (r.isZReport) ...[
          AtlasTotalRow(
              label: 'Counted cash', value: (r.countedCash ?? 0).toStringAsFixed(2)),
          AtlasTotalRow(
              label: 'Over / short', value: (r.overShort ?? 0).toStringAsFixed(2)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctxAsync = ref.watch(_tillContextProvider);
    final sessionId = ctxAsync.asData?.value.sessionId;
    return ResponsiveScaffold(
      title: 'Point of Sale',
      padBody: false,
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
      body: ctxAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Padding(
                padding: const EdgeInsets.all(MercantisSpacing.xl),
                child: Text('Failed to load: $e'))),
        data: _till,
      ),
    );
  }

  Widget _till(_TillContext ctx) {
    // No open shift yet: offer to open the till with a counted float (or
    // point at Setup when there's no POS Profile at all).
    if (ctx.sessionId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.point_of_sale_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              ctx.profileId == null
                  ? 'Create a POS Profile first (Sales → POS Profile) — it '
                      'names the warehouse, cash account and taxes this till '
                      'uses.'
                  : 'The till is closed. Count the drawer and open a shift '
                      'to start selling.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (ctx.profileId != null)
              FilledButton.icon(
                onPressed: () => _openTill(ctx),
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Open till'),
              ),
          ],
        ),
      );
    }
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
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AtlasTotalRow(label: 'Net', value: totals.netTotal.toStringAsFixed(2)),
                AtlasTotalRow(label: 'VAT', value: totals.totalTax.toStringAsFixed(2)),
                AtlasTotalRow(
                    label: 'Total',
                    value: totals.grandTotal.toStringAsFixed(2),
                    emphasize: true),
                const SizedBox(height: MercantisSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_posting || _cart.isEmpty || ctx.sessionId == null)
                        ? null
                        : () => _takePayment(ctx),
                    icon: _posting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.point_of_sale),
                    label: Text('Take payment ${totals.grandTotal.toStringAsFixed(2)}'),
                  ),
                ),
                if (_result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: MercantisSpacing.sm),
                    child: Text('Completed $_result', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: MercantisSpacing.sm),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cartTile(_CartLine l) {
    final theme = Theme.of(context);
    // Keyed by line identity so each Atlas stepper / input row keeps its own
    // state when lines are added or removed (the widgets own their controllers).
    return Card(
      key: ObjectKey(l),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: MercantisSpacing.md, vertical: MercantisSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text(l.amount.toStringAsFixed(2),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove',
                  onPressed:
                      _posting ? null : () => setState(() => _cart.remove(l)),
                ),
              ],
            ),
            AtlasQuantityStepper(
              label: 'Qty',
              value: l.qty,
              min: 0,
              readOnly: _posting,
              onChanged: (v) => setState(() => l.qty = v ?? 0),
            ),
            AtlasTextInputRow(
              label: 'Rate',
              value: l.lineRate.toStringAsFixed(2),
              readOnly: _posting,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) =>
                  setState(() => l.lineRate = num.tryParse(v.trim()) ?? 0),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet prompt for the drawer count when closing a shift. Pops the
/// parsed amount (0 when unparseable) on confirm, or null on cancel — matching
/// the previous dialog's return contract.
class _CountedCashSheet extends StatefulWidget {
  const _CountedCashSheet();

  @override
  State<_CountedCashSheet> createState() => _CountedCashSheetState();
}

class _CountedCashSheetState extends State<_CountedCashSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AtlasBottomSheet(
      showHandle: false,
      title: 'Close shift',
      body: Padding(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Counted cash in drawer',
              border: OutlineInputBorder()),
        ),
      ),
      footer: AtlasBottomActionBar(
        primaryLabel: 'Close shift',
        onPrimary: () => Navigator.of(context)
            .pop(num.tryParse(_controller.text.trim()) ?? 0),
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.of(context).pop(null),
      ),
    );
  }
}
