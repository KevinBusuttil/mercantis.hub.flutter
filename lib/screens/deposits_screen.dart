import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/deposit_service.dart';

/// The deposit liability report (S4): every customer deposit with how much
/// has been applied to invoices and what the business still owes back. The
/// total outstanding is the balance the Customer Deposits liability account
/// should carry.
final depositReportProvider = FutureProvider<List<DepositRow>>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return DepositService(engine).liabilityReport();
});

class DepositsScreen extends ConsumerWidget {
  const DepositsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(depositReportProvider);
    return ResponsiveScaffold(
      title: 'Customer deposits',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
                child: Text('No customer deposits recorded yet.'));
          }
          final outstanding = rows
              .where((r) => r.deposit.docStatus == 1)
              .fold<num>(0, (sum, r) => sum + r.outstanding);
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            children: [
              AtlasSectionCard(
                name: 'Liability',
                child: Padding(
                  padding: const EdgeInsets.all(MercantisSpacing.md),
                  child: AtlasTotalRow(
                    label: 'Outstanding deposits held',
                    value: outstanding.toStringAsFixed(2),
                    emphasize: true,
                  ),
                ),
              ),
              const SizedBox(height: MercantisSpacing.md),
              AtlasSectionCard(
                name: 'Deposits',
                child: Column(
                  children: [
                    for (final r in rows)
                      ListTile(
                        leading: Icon(r.deposit.docStatus == 0
                            ? Icons.edit_note_outlined
                            : r.outstanding <= 0
                                ? Icons.check_circle_outline
                                : Icons.savings_outlined),
                        title: Text(
                            '${r.deposit.id} — ${r.deposit.payload['customer']}'),
                        subtitle: Text([
                          '${r.deposit.payload['posting_date']}',
                          if (r.deposit.docStatus == 0) 'draft',
                          if (r.applied > 0)
                            'applied ${r.applied.toStringAsFixed(2)}',
                          if (r.outstanding < -0.005)
                            'OVER-APPLIED', // cancelled deposit with live uses
                        ].join(' · ')),
                        trailing: Text(
                          r.outstanding.toStringAsFixed(2),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: r.outstanding < -0.005
                                ? theme.colorScheme.error
                                : null,
                          ),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GenericFormView(
                              docTypeName: 'Customer Deposit',
                              documentName: r.deposit.id,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
