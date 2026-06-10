import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'screen_providers.dart';

/// Customer-accounts overview: every customer with their open receivable
/// balance, summed live from submitted Sales Invoices.
class CustomerAccountScreen extends ConsumerWidget {
  const CustomerAccountScreen({super.key, this.customerId});
  final String? customerId;

  static String _money(double v) => '€${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bp = Breakpoint.of(context);
    final async = ref.watch(customerAccountsProvider);

    return ResponsiveScaffold(
      title: 'Customer accounts',
      subtitle: 'Receivables by customer',
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          final withBalance = rows.where((r) => r.outstanding > 0).toList();
          final totalReceivable =
              rows.fold<double>(0, (s, r) => s + r.outstanding);

          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No customers yet',
              message: 'Add a customer to start tracking receivables.',
              icon: Icons.people_outline,
            );
          }

          return ListView(
            padding: EdgeInsets.all(
                bp.isPhone ? MercantisSpacing.lg : MercantisSpacing.xl),
            children: [
              Wrap(
                spacing: MercantisSpacing.md,
                runSpacing: MercantisSpacing.md,
                children: [
                  SizedBox(
                    width: bp.isPhone ? double.infinity : 240,
                    child: KpiCard(
                      title: 'Total receivable',
                      value: _money(totalReceivable),
                      subtitle: '${withBalance.length} customer(s) with balance',
                      icon: Icons.account_balance_wallet_outlined,
                      accentColor: MercantisBrandColors.accentFinance,
                    ),
                  ),
                  SizedBox(
                    width: bp.isPhone ? double.infinity : 240,
                    child: KpiCard(
                      title: 'Customers',
                      value: '${rows.length}',
                      subtitle: 'on file',
                      icon: Icons.people_outline,
                      accentColor: MercantisBrandColors.accentSales,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MercantisSpacing.xl),
              Text('Balances', style: theme.textTheme.titleMedium),
              const SizedBox(height: MercantisSpacing.sm),
              ErpDataTable(
                columns: const [
                  ErpDataColumn(label: 'Customer', flex: 5),
                  ErpDataColumn(label: 'Open invoices', flex: 2, numeric: true),
                  ErpDataColumn(label: 'Outstanding', flex: 3, numeric: true),
                  ErpDataColumn(label: '', flex: 2),
                ],
                rows: [
                  for (final r in rows)
                    ErpDataRow(
                      onTap: () =>
                          context.go('/form/Customer/${r.customerId}'),
                      cells: [
                        Text(r.customerName),
                        Text('${r.openInvoices}'),
                        Text(_money(r.outstanding)),
                        if (r.outstanding > 0)
                          const StatusChip(
                              label: 'Due',
                              tone: StatusTone.overdue,
                              dense: true)
                        else
                          const StatusChip(
                              label: 'Clear',
                              tone: StatusTone.approved,
                              dense: true),
                      ],
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
