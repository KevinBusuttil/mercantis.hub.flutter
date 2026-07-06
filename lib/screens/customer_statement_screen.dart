import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

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
            Row(
              children: [
                Expanded(
                  child: AtlasDateFieldRow(
                    label: 'From',
                    value: req.from,
                    onChanged: (v) =>
                        setState(() => _from = DateTime.parse(v)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AtlasDateFieldRow(
                    label: 'To',
                    value: req.to,
                    onChanged: (v) => setState(() => _to = DateTime.parse(v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: const Text('Opening balance'),
                trailing: Text(_money(s.openingBalance),
                    style: theme.textTheme.titleMedium),
              ),
            ),
            for (final l in s.lines)
              ListTile(
                dense: true,
                leading: Icon(switch (l.kind) {
                  'Payment' => Icons.payments_outlined,
                  'CreditNote' => Icons.undo_outlined,
                  _ => Icons.receipt_long_outlined,
                }),
                title: Text(l.reference),
                subtitle: Text('${l.date} · ${l.kind}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_money(l.amount)),
                    Text(_money(l.balance),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            Card(
              child: ListTile(
                title: const Text('Closing balance'),
                trailing: Text(_money(s.closingBalance),
                    style: theme.textTheme.titleMedium),
              ),
            ),
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
