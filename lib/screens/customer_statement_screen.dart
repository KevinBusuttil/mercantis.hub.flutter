import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../modules/selling/customer_statement.dart';

/// Statement parameters: customer id + inclusive ISO date range.
typedef StatementRequest = ({String customer, String from, String to});

final customerStatementProvider = FutureProvider.autoDispose
    .family<CustomerStatement, StatementRequest>((ref, req) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return CustomerStatementBuilder(engine.list).build(
    customer: req.customer,
    from: req.from,
    to: req.to,
    userRoles: ref.watch(currentUserProvider).roles,
  );
});

/// A customer's statement of account: opening balance, every invoice /
/// credit note / payment in the period with a running balance, and a
/// copy-as-text action to send it on.
class CustomerStatementScreen extends ConsumerStatefulWidget {
  const CustomerStatementScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<CustomerStatementScreen> createState() =>
      _CustomerStatementScreenState();
}

class _CustomerStatementScreenState
    extends ConsumerState<CustomerStatementScreen> {
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _from = DateTime(now.year, 1, 1); // year to date by default
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _money(num v) => '€${v.toDouble().toStringAsFixed(2)}';

  /// Hands the statement text to the phone's share sheet (mail, messaging),
  /// which is how a statement leaves a phone; Copy stays for desktops.
  Future<void> _share(BuildContext context, CustomerStatement s) async {
    try {
      await SharePlus.instance.share(ShareParams(
        text: s.toText(),
        subject: 'Statement of account — ${widget.customerId}',
      ));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: s.toText()));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sharing is not available here, so the '
                'statement was copied instead')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = (
      customer: widget.customerId,
      from: _iso(_from),
      to: _iso(_to),
    );
    final async = ref.watch(customerStatementProvider(req));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Statement — ${widget.customerId}'),
        actions: [
          IconButton(
            tooltip: 'Share statement',
            icon: const Icon(Icons.share_outlined),
            onPressed: async.valueOrNull == null
                ? null
                : () => _share(context, async.value!),
          ),
          IconButton(
            tooltip: 'Copy as text',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: async.valueOrNull == null
                ? null
                : () async {
                    await Clipboard.setData(
                        ClipboardData(text: async.value!.toText()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Statement copied — paste it into an '
                              'email or message')));
                    }
                  },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not build statement: $e')),
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DateRange(
              from: AtlasDateFieldRow(
                label: 'From',
                value: req.from,
                onChanged: (v) => setState(() => _from = DateTime.parse(v)),
              ),
              to: AtlasDateFieldRow(
                label: 'To',
                value: req.to,
                onChanged: (v) => setState(() => _to = DateTime.parse(v)),
              ),
            ),
            const SizedBox(height: 12),
            _BalanceCard(
                label: 'Opening balance', value: _money(s.openingBalance)),
            for (final l in s.lines)
              _StatementLineRow(
                line: l,
                amount: _money(l.amount),
                balance: _money(l.balance),
              ),
            _BalanceCard(
                label: 'Closing balance', value: _money(s.closingBalance)),
            if (s.lines.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No activity in this period.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

/// True when there is not room to lay things side by side: a phone, or any
/// width once the text is enlarged.
bool _isCompact(BuildContext context, double width) =>
    width < 520 || MediaQuery.textScalerOf(context).scale(1) > 1.3;

/// The From / To pickers: side by side when there is room, stacked on a
/// phone or at large text sizes.
class _DateRange extends StatelessWidget {
  const _DateRange({required this.from, required this.to});
  final Widget from;
  final Widget to;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (_isCompact(context, c.maxWidth)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [from, const SizedBox(height: 8), to],
        );
      }
      return Row(children: [
        Expanded(child: from),
        const SizedBox(width: 12),
        Expanded(child: to),
      ]);
    });
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              Text(value, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// One statement line. The amount and running balance are labelled, so a
/// screen reader says "Amount €100.00, balance €250.00" rather than two bare
/// numbers, and they move under the reference on a narrow screen instead of
/// squeezing it.
class _StatementLineRow extends StatelessWidget {
  const _StatementLineRow({
    required this.line,
    required this.amount,
    required this.balance,
  });

  final StatementLine line;
  final String amount;
  final String balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = Icon(switch (line.kind) {
      'Payment' => Icons.payments_outlined,
      'CreditNote' => Icons.undo_outlined,
      _ => Icons.receipt_long_outlined,
    });
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line.reference, style: theme.textTheme.bodyMedium),
        Text('${line.date} · ${line.kind}', style: theme.textTheme.bodySmall),
      ],
    );
    return MergeSemantics(
      child: Semantics(
        label: '${line.reference}, ${line.date}, ${line.kind}, '
            'amount $amount, balance $balance',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LayoutBuilder(builder: (context, c) {
            final figures = Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(amount, style: theme.textTheme.bodyMedium),
                Text('Balance $balance', style: theme.textTheme.bodySmall),
              ],
            );
            if (_isCompact(context, c.maxWidth)) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        text,
                        const SizedBox(height: 4),
                        Align(alignment: Alignment.centerRight, child: figures),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Row(children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
              const SizedBox(width: 12),
              figures,
            ]);
          }),
        ),
      ),
    );
  }
}
