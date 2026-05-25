import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../mock/mock_data.dart';

class CustomerAccountScreen extends StatelessWidget {
  const CustomerAccountScreen({super.key, this.customerId});
  final String? customerId;

  @override
  Widget build(BuildContext context) {
    final customer = customerId ?? 'ACME Ltd';
    final theme = Theme.of(context);
    final bp = Breakpoint.of(context);

    final body = ListView(
      padding: EdgeInsets.all(bp.isPhone ? MercantisSpacing.lg : MercantisSpacing.xl),
      children: [
        Wrap(
          spacing: MercantisSpacing.md,
          runSpacing: MercantisSpacing.md,
          children: [
            SizedBox(
              width: bp.isPhone ? double.infinity : 220,
              child: const KpiCard(
                title: 'Outstanding', value: '€3,240',
                subtitle: '4 invoices',
                icon: Icons.account_balance_wallet_outlined,
                accentColor: MercantisBrandColors.accentFinance,
              ),
            ),
            SizedBox(
              width: bp.isPhone ? double.infinity : 220,
              child: const KpiCard(
                title: 'Overdue', value: '€1,100',
                subtitle: '12 days late',
                trend: KpiTrend.flat,
                icon: Icons.error_outline,
                accentColor: MercantisBrandColors.statusOverdue,
              ),
            ),
            SizedBox(
              width: bp.isPhone ? double.infinity : 220,
              child: const KpiCard(
                title: 'Sales YTD', value: '€54,210',
                subtitle: 'last 12 months',
                trend: KpiTrend.up, trendLabel: '+12%',
                icon: Icons.trending_up,
                accentColor: MercantisBrandColors.accentSales,
              ),
            ),
            SizedBox(
              width: bp.isPhone ? double.infinity : 220,
              child: const KpiCard(
                title: 'Last order', value: '3 days',
                subtitle: 'SO-0142',
                icon: Icons.schedule,
                accentColor: MercantisBrandColors.accentSales,
              ),
            ),
          ],
        ),
        const SizedBox(height: MercantisSpacing.xl),
        Text('Documents', style: theme.textTheme.titleMedium),
        const SizedBox(height: MercantisSpacing.sm),
        ListCard(
          title: 'Recent documents',
          icon: Icons.history,
          accentColor: MercantisBrandColors.accentSales,
          rows: [
            for (final r in MockData.salesRecent.take(4))
              ListCardRow(
                title: r.title,
                subtitle: '${r.docType} · ${r.timestamp}',
                trailing: r.amount != null
                    ? Text(r.amount!,
                        style: const TextStyle(fontWeight: FontWeight.w600))
                    : null,
              ),
          ],
        ),
      ],
    );

    return ResponsiveScaffold(
      title: customer,
      subtitle: 'Customer account',
      actions: [
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.email_outlined, size: 16),
          label: const Text('Email statement'),
        ),
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.payments_outlined, size: 16),
          label: const Text('Collect payment'),
        ),
      ],
      body: body,
      padBody: false,
    );
  }
}
