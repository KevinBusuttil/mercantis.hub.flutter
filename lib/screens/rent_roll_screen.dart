import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../property/lease_service.dart';

const _systemRoles = {'System Manager'};

/// The roll plus the Draft leases still waiting for activation.
class RentRollData {
  const RentRollData({required this.lines, required this.drafts});

  final List<RentRollLine> lines;
  final List<Document> drafts;
}

final rentRollProvider =
    FutureProvider.autoDispose<RentRollData>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final lines = await LeaseService(engine).rentRoll();
  final drafts = [
    for (final l in await engine.list('Lease', userRoles: _systemRoles))
      if ('${l.payload['status']}' == 'Draft') l,
  ];
  return RentRollData(lines: lines, drafts: drafts);
});

/// V5: the landlord's morning list — every active tenancy with its rent,
/// when it bills next, and what the tenant owes, worst first. Ending a
/// lease deactivates its rent template on the spot.
class RentRollScreen extends ConsumerStatefulWidget {
  const RentRollScreen({super.key});

  @override
  ConsumerState<RentRollScreen> createState() => _RentRollScreenState();
}

class _RentRollScreenState extends ConsumerState<RentRollScreen> {
  Future<void> _endLease(RentRollLine line) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('End lease ${line.lease.id}?'),
        content: Text(
            'Rent billing for ${line.propertyName} stops today. '
            'Invoices already raised stand'
            '${line.arrears > 0 ? ' — ${line.arrears.toStringAsFixed(2)} is still owed' : ''}. '
            'The deposit refund (or offset) is a manual payment.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('End lease')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      final engine = await ref.read(documentEngineProvider.future);
      await LeaseService(engine).end(line.lease.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${line.lease.id} ended — billing stopped.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      ref.invalidate(rentRollProvider);
    }
  }

  /// Activate a Draft lease: take the deposit (optional) and start the
  /// rent billing.
  Future<void> _activate(Document lease) async {
    final depositCtrl = TextEditingController(text: '0.00');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Activate ${lease.id}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rent starts billing itself each period from the '
                'lease start date.'),
            const SizedBox(height: 12),
            TextField(
              controller: depositCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Tenancy deposit taken now (0 for none)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Not yet')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Activate')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final engine = await ref.read(documentEngineProvider.future);
      await LeaseService(engine).activate(lease.id,
          depositAmount: num.tryParse(depositCtrl.text.trim()) ?? 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${lease.id} active — rent bills itself.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      ref.invalidate(rentRollProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rentRollProvider);
    final theme = Theme.of(context);
    return ResponsiveScaffold(
      title: 'Rent roll',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          final lines = data.lines;
          if (lines.isEmpty && data.drafts.isEmpty) {
            return const EmptyState(
              title: 'No active leases',
              message: 'Create a Lease on a Property and activate it — '
                  'rent then bills itself every period and lands here '
                  'with its arrears.',
              icon: Icons.apartment_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            children: [
              if (data.drafts.isNotEmpty) ...[
                Text('Waiting to start',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: MercantisSpacing.sm),
                for (final draft in data.drafts)
                  Padding(
                    padding: const EdgeInsets.only(
                        bottom: MercantisSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                              '${draft.id} · ${draft.payload['property']} '
                              '· ${draft.payload['tenant']}',
                              style: theme.textTheme.bodyMedium),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _activate(draft),
                          child: const Text('Activate'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: MercantisSpacing.md),
              ],
              for (final line in lines)
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: MercantisSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${line.propertyName} · ${line.tenant} '
                                '· ${line.lease.id}',
                                style: theme.textTheme.titleSmall),
                            Text(
                                '${line.rent.toStringAsFixed(2)} '
                                '${line.frequency.toLowerCase()}'
                                '${line.nextInvoiceDate != null ? ' · next ${line.nextInvoiceDate}' : ''}',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(line.arrears.toStringAsFixed(2),
                              style: theme.textTheme.titleMedium!.copyWith(
                                  color: line.arrears > 0
                                      ? theme.colorScheme.error
                                      : null)),
                          Text('owed', style: theme.textTheme.labelSmall),
                        ],
                      ),
                      const SizedBox(width: MercantisSpacing.sm),
                      OutlinedButton(
                        onPressed: () => _endLease(line),
                        child: const Text('End lease'),
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
