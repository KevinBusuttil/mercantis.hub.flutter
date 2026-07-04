import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../payments/guided_payment.dart';

const _systemRoles = {'System Manager'};

/// Static context a guided payment needs: the parties to pick from, selectable
/// cash/bank accounts, and the active Company's defaults.
class _PaymentContext {
  const _PaymentContext({
    required this.parties,
    required this.bankAccounts,
    this.defaultBank,
    this.company,
    this.currency,
  });

  final List<Document> parties;
  final List<Document> bankAccounts;
  final String? defaultBank;
  final String? company;
  final String? currency;
}

/// Loads parties (Customer for receive, Supplier for pay), cash/bank accounts,
/// and the active Company's defaults. Keyed by direction.
final _paymentContextProvider =
    FutureProvider.family<_PaymentContext, bool>((ref, receive) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final parties =
      await engine.list(receive ? 'Customer' : 'Supplier', userRoles: _systemRoles);
  final accounts = await engine.list('Account', userRoles: _systemRoles);
  final companies = await engine.list('Company', userRoles: _systemRoles);
  final company = companies.isEmpty ? null : companies.first;

  bool cashLike(Document a) {
    final t = a.payload['account_type'];
    return t == 'Bank' || t == 'Cash';
  }

  final banks = accounts.where(cashLike).toList();
  return _PaymentContext(
    parties: parties,
    bankAccounts: banks.isEmpty ? accounts : banks,
    defaultBank: company?.payload['default_cash_account'] as String?,
    company: company?.id,
    currency: company?.payload['default_currency'] as String?,
  );
});

/// Guided Receive Payment / Pay Supplier flow: pick a party, see their open
/// invoices, allocate amounts, and post a submitted Payment Entry in one screen.
/// The Payment Entry's `references` drive the existing ledger derivation
/// (Settlement rows + invoice `outstanding_amount` upkeep).
class GuidedPaymentScreen extends ConsumerStatefulWidget {
  const GuidedPaymentScreen({super.key, required this.receive});

  /// true = Receive Payment (customers), false = Pay Supplier (suppliers).
  final bool receive;

  @override
  ConsumerState<GuidedPaymentScreen> createState() => _GuidedPaymentScreenState();
}

class _GuidedPaymentScreenState extends ConsumerState<GuidedPaymentScreen> {
  String? _party;
  String? _bank;
  DateTime _postingDate = DateTime.now();
  List<_AllocRow> _rows = [];
  bool _loadingInvoices = false;
  bool _saving = false;
  String? _error;
  String? _successId;

  bool get _receive => widget.receive;
  String get _title => _receive ? 'Receive Payment' : 'Pay Supplier';
  String get _partyLabel => _receive ? 'Customer' : 'Supplier';
  String get _docLabel => _receive ? 'invoice' : 'bill';

  @override
  void dispose() {
    for (final r in _rows) {
      r.ctrl.dispose();
    }
    super.dispose();
  }

  num get _total {
    num t = 0;
    for (final r in _rows) {
      if (r.selected) t += num.tryParse(r.ctrl.text.trim()) ?? 0;
    }
    return t;
  }

  String _partyName(Document d) =>
      (d.payload[_receive ? 'customer_name' : 'supplier_name'] as String?) ?? d.id;

  Future<void> _onPartySelected(String? id) async {
    for (final r in _rows) {
      r.ctrl.dispose();
    }
    setState(() {
      _party = id;
      _rows = [];
      _error = null;
      _successId = null;
    });
    if (id == null) return;

    setState(() => _loadingInvoices = true);
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final invoices = await engine.list(
        GuidedPayment.invoiceDocType(receive: _receive),
        filters: {GuidedPayment.partyField(receive: _receive): id},
        userRoles: _systemRoles,
      );
      final open = GuidedPayment.openInvoices(invoices, receive: _receive);
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final inv in open)
            _AllocRow(
              inv: inv,
              selected: true,
              ctrl: TextEditingController(text: inv.outstanding.toStringAsFixed(2)),
            ),
        ];
        _loadingInvoices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingInvoices = false;
      });
    }
  }

  Future<void> _post(_PaymentContext ctx) async {
    final allocations = <PaymentAllocation>[];
    for (final r in _rows) {
      if (!r.selected) continue;
      final amt = num.tryParse(r.ctrl.text.trim()) ?? 0;
      if (amt <= 0) continue;
      allocations.add(PaymentAllocation(
        invoiceId: r.inv.id,
        invoiceDocType: r.inv.docType,
        total: r.inv.total,
        outstanding: r.inv.outstanding,
        allocated: amt,
      ));
    }
    if (_party == null || allocations.isEmpty) {
      setState(() => _error = 'Select a $_partyLabel and at least one $_docLabel with an amount.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _successId = null;
    });
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final draft = GuidedPayment.buildPaymentEntry(
        receive: _receive,
        party: _party!,
        postingDate: _isoDate(_postingDate),
        bankAccount: _bank ?? ctx.defaultBank,
        company: ctx.company,
        currency: ctx.currency,
        allocations: allocations,
      );
      final saved = await engine.save(draft, _systemRoles);
      final submitted = await engine.submit(saved, _systemRoles);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _successId = submitted.id;
        _party = null;
        _rows = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Posted ${submitted.id}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is DocumentEngineError ? e.humanMessage : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctxAsync = ref.watch(_paymentContextProvider(_receive));
    return ResponsiveScaffold(
      title: _title,
      padBody: false,
      body: ctxAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(MercantisSpacing.xl),
            child: Text('Failed to load: $e', textAlign: TextAlign.center),
          ),
        ),
        data: _form,
      ),
    );
  }

  Widget _form(_PaymentContext ctx) {
    final bankValue = _bank ??
        (ctx.bankAccounts.any((a) => a.id == ctx.defaultBank) ? ctx.defaultBank : null);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(MercantisSpacing.lg),
      children: [
        AtlasSectionCard(
          name: 'Payment',
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _party,
                decoration: InputDecoration(
                    labelText: '$_partyLabel *',
                    border: const OutlineInputBorder()),
                items: [
                  for (final p in ctx.parties)
                    DropdownMenuItem(value: p.id, child: Text(_partyName(p))),
                ],
                onChanged: _saving ? null : (v) => _onPartySelected(v),
              ),
              const SizedBox(height: MercantisSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: bankValue,
                decoration: const InputDecoration(
                    labelText: 'Cash / Bank account',
                    border: OutlineInputBorder()),
                items: [
                  for (final a in ctx.bankAccounts)
                    DropdownMenuItem(
                      value: a.id,
                      child:
                          Text((a.payload['account_name'] as String?) ?? a.id),
                    ),
                ],
                onChanged: _saving ? null : (v) => setState(() => _bank = v),
              ),
              const SizedBox(height: MercantisSpacing.sm),
              AtlasDateFieldRow(
                label: 'Posting date',
                readOnly: _saving,
                value: _isoDate(_postingDate),
                onChanged: (s) =>
                    setState(() => _postingDate = DateTime.parse(s)),
              ),
            ],
          ),
        ),
        const SizedBox(height: MercantisSpacing.lg),
        AtlasSectionCard(
          name: 'Open ${_docLabel}s',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loadingInvoices)
                const Padding(
                    padding: EdgeInsets.all(MercantisSpacing.lg),
                    child: Center(child: CircularProgressIndicator()))
              else if (_party == null)
                Text('Select a $_partyLabel to see open ${_docLabel}s.',
                    style: theme.textTheme.bodySmall)
              else if (_rows.isEmpty)
                Text('No open ${_docLabel}s for this $_partyLabel.',
                    style: theme.textTheme.bodySmall)
              else
                for (final row in _rows) _invoiceRow(row),
            ],
          ),
        ),
        const SizedBox(height: MercantisSpacing.lg),
        AtlasTotalRow(
          label: 'Total',
          value: _total.toStringAsFixed(2),
          emphasize: true,
        ),
        const SizedBox(height: MercantisSpacing.lg),
        FilledButton.icon(
          onPressed: (_saving || _total <= 0) ? null : () => _post(ctx),
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: Text(_receive ? 'Receive Payment' : 'Pay Supplier'),
        ),
        if (_successId != null)
          Padding(
            padding: const EdgeInsets.only(top: MercantisSpacing.md),
            child: Text('Posted $_successId',
                style: TextStyle(color: theme.colorScheme.primary)),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: MercantisSpacing.md),
            child: Text(_error!,
                style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }

  Widget _invoiceRow(_AllocRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: row.selected,
            onChanged: _saving ? null : (v) => setState(() => row.selected = v ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.inv.id),
                Text('Outstanding ${row.inv.outstanding.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: row.ctrl,
              enabled: row.selected && !_saving,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Allocate', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _AllocRow {
  _AllocRow({required this.inv, required this.selected, required this.ctrl});
  final OpenInvoice inv;
  bool selected;
  final TextEditingController ctrl;
}
