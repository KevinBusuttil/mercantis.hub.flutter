import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../field_service/equipment_service.dart';
import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// The equipment desk in one load: every enabled unit, its owner's name,
/// and its service history.
class EquipmentData {
  const EquipmentData({
    required this.equipment,
    required this.customerNames,
    required this.historyByEquipment,
  });

  final List<Document> equipment;
  final Map<String, String> customerNames;
  final Map<String, List<Document>> historyByEquipment;
}

final equipmentDataProvider =
    FutureProvider.autoDispose<EquipmentData>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final service = EquipmentService(engine);
  final equipment = [
    for (final e in await engine.list('Customer Equipment',
        userRoles: _systemRoles))
      if (e.payload['enabled'] == null || isTrue(e.payload['enabled'])) e,
  ]..sort((a, b) => '${a.payload['equipment_name']}'
      .compareTo('${b.payload['equipment_name']}'));
  final names = <String, String>{
    for (final c in await engine.list('Customer', userRoles: _systemRoles))
      c.id: '${c.payload['customer_name']}',
  };
  final history = <String, List<Document>>{
    for (final e in equipment) e.id: await service.history(e.id),
  };
  return EquipmentData(
    equipment: equipment,
    customerNames: names,
    historyByEquipment: history,
  );
});

/// V4: the register of customer units (cars, boilers, machines) with
/// each one's service history a tap away — and "Book it in" raising a
/// prefilled Service Request into the dispatch queue.
class EquipmentScreen extends ConsumerStatefulWidget {
  const EquipmentScreen({super.key});

  @override
  ConsumerState<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends ConsumerState<EquipmentScreen> {
  void _toast(Object message) {
    if (!mounted) return;
    final text = '$message';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text.startsWith('Bad state: ')
            ? text.substring('Bad state: '.length)
            : text)));
  }

  Future<void> _bookIn(Document equipment) async {
    final subjectCtrl = TextEditingController(
        text: 'Service — ${equipment.payload['equipment_name']}');
    final meterCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Book in ${equipment.payload['equipment_name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: subjectCtrl,
              decoration: const InputDecoration(
                  labelText: 'What needs doing',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: meterCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Meter reading (optional)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Book in')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final request = await EquipmentService(engine).requestService(
        equipment.id,
        subject: subjectCtrl.text.trim(),
        meterReading: num.tryParse(meterCtrl.text.trim()),
      );
      _toast('Booked in as ${request.id} — it\'s in the dispatch queue.');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(equipmentDataProvider);
    }
  }

  Future<void> _historySheet(Document equipment, EquipmentData data) async {
    final history = data.historyByEquipment[equipment.id] ?? const [];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MercantisSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${equipment.payload['equipment_name']}',
                  style: Theme.of(c).textTheme.titleMedium),
              Text(
                  [
                    if (asNonEmpty(equipment.payload['make']) != null)
                      '${equipment.payload['make']}',
                    if (asNonEmpty(equipment.payload['model']) != null)
                      '${equipment.payload['model']}',
                    if (asNonEmpty(equipment.payload['registration_no']) !=
                        null)
                      '${equipment.payload['registration_no']}',
                    if (asNonEmpty(equipment.payload['serial_no']) != null)
                      'S/N ${equipment.payload['serial_no']}',
                  ].join(' · '),
                  style: Theme.of(c).textTheme.bodySmall),
              const SizedBox(height: MercantisSpacing.sm),
              if (history.isEmpty)
                const Text('No service history yet.')
              else
                for (final job in history)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                        '${(asNonEmpty(job.payload['starts_at']) ?? job.createdAt.toIso8601String()).split('T').first}'
                        '  ${job.id} — ${job.payload['subject']} '
                        '(${job.payload['status']}'
                        '${asNonEmpty(job.payload['sales_invoice']) != null ? ' · ${job.payload['sales_invoice']}' : ''})'),
                  ),
              const SizedBox(height: MercantisSpacing.md),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(c);
                  await _bookIn(equipment);
                },
                icon: const Icon(Icons.build_outlined),
                label: const Text('Book it in'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(equipmentDataProvider);
    final theme = Theme.of(context);
    return ResponsiveScaffold(
      title: 'Equipment',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          if (data.equipment.isEmpty) {
            return const EmptyState(
              title: 'No equipment on file',
              message: 'Register the customer\'s cars, boilers or '
                  'machines here — every job on a unit builds its '
                  'service history.',
              icon: Icons.directions_car_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            children: [
              for (final e in data.equipment)
                InkWell(
                  onTap: () => _historySheet(e, data),
                  child: Padding(
                    padding: const EdgeInsets.only(
                        bottom: MercantisSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${e.payload['equipment_name']}'
                                  '${asNonEmpty(e.payload['registration_no']) != null ? ' · ${e.payload['registration_no']}' : ''}',
                                  style: theme.textTheme.titleSmall),
                              Text(
                                  '${data.customerNames['${e.payload['customer']}'] ?? e.payload['customer']}'
                                  ' · ${(data.historyByEquipment[e.id] ?? const []).length} visit(s)',
                                  style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
