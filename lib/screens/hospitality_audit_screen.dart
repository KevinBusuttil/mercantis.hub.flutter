import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../hospitality/hospitality_audit.dart';

final hospitalityAuditProvider =
    FutureProvider.autoDispose<HospitalityAudit>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return buildHospitalityAudit(engine);
});

/// V2-5: everything that left the money trail on purpose — voided tabs,
/// comped lines and cancelled fiscal invoices, each with its reason and
/// value. This is what the Thirteenth Schedule auditor asks to see, and
/// what an owner reads to spot shrinkage.
class HospitalityAuditScreen extends ConsumerWidget {
  const HospitalityAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hospitalityAuditProvider);
    return ResponsiveScaffold(
      title: 'Void & comp audit',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (audit) {
          if (audit.voids.isEmpty &&
              audit.comps.isEmpty &&
              audit.cancellations.isEmpty) {
            return const EmptyState(
              title: 'Nothing given away',
              message: 'Voided tabs, comped lines and cancelled fiscal '
                  'invoices appear here, each with its reason and value.',
              icon: Icons.fact_check_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            children: [
              _section(context, 'Voided tabs', audit.voidValue,
                  audit.voids),
              _section(context, 'Comped items', audit.compValue,
                  audit.comps),
              _section(context, 'Cancelled fiscal invoices',
                  audit.cancelValue, audit.cancellations),
            ],
          );
        },
      ),
    );
  }

  Widget _section(BuildContext context, String label, num total,
      List<HospitalityAuditEntry> entries) {
    final theme = Theme.of(context);
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: MercantisSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('$label (${entries.length})',
                      style: theme.textTheme.titleSmall)),
              Text(total.toStringAsFixed(2),
                  style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: MercantisSpacing.sm),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: MercantisSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${e.id} · ${e.detail}',
                            style: theme.textTheme.bodyMedium),
                        if (e.reason.isNotEmpty)
                          Text('“${e.reason}”',
                              style: theme.textTheme.bodySmall!.copyWith(
                                  fontStyle: FontStyle.italic)),
                        if (e.when != null)
                          Text(e.when!.toIso8601String().split('T').first,
                              style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                  Text(e.value.toStringAsFixed(2),
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
