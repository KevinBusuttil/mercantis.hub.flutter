import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';
import '../rental/rental_service.dart';

const _systemRoles = {'System Manager'};

/// The hire desk in one load: the fleet, who's got what out, and the
/// open agreements waiting for handover or return.
class RentalDeskData {
  const RentalDeskData({
    required this.units,
    required this.customers,
    required this.openAgreements,
  });

  final List<Document> units;
  final List<Document> customers;

  /// Draft (booked) and Out agreements, oldest first.
  final List<Document> openAgreements;

  String unitName(String id) {
    for (final u in units) {
      if (u.id == id) return '${u.payload['unit_name']}';
    }
    return id;
  }

  String customerName(String id) {
    for (final c in customers) {
      if (c.id == id) return '${c.payload['customer_name']}';
    }
    return id;
  }

  /// The Out agreement holding [unitId], if any.
  Document? outOn(String unitId) {
    for (final a in openAgreements) {
      if ('${a.payload['status']}' == 'Out' &&
          '${a.payload['unit']}' == unitId) {
        return a;
      }
    }
    return null;
  }
}

final rentalDeskProvider =
    FutureProvider.autoDispose<RentalDeskData>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final units = [
    for (final u
        in await engine.list('Rental Unit', userRoles: _systemRoles))
      if (u.payload['enabled'] == null || isTrue(u.payload['enabled'])) u,
  ]..sort((a, b) =>
      '${a.payload['unit_name']}'.compareTo('${b.payload['unit_name']}'));
  final customers =
      await engine.list('Customer', userRoles: _systemRoles);
  final open = [
    for (final a
        in await engine.list('Rental Agreement', userRoles: _systemRoles))
      if ('${a.payload['status']}' == 'Draft' ||
          '${a.payload['status']}' == 'Out')
        a,
  ]..sort((a, b) =>
      '${a.payload['starts_at']}'.compareTo('${b.payload['starts_at']}'));
  return RentalDeskData(
      units: units, customers: customers, openAgreements: open);
});

/// V3-2: the hire desk — the fleet with who's got what out, the open
/// agreements with their next action (hand over / take back / cancel),
/// and a New hire dialog that books through the S1 calendar hold.
class RentalsScreen extends ConsumerStatefulWidget {
  const RentalsScreen({super.key});

  @override
  ConsumerState<RentalsScreen> createState() => _RentalsScreenState();
}

class _RentalsScreenState extends ConsumerState<RentalsScreen> {
  Future<RentalService> get _rental async =>
      RentalService(await ref.read(documentEngineProvider.future));

  void _toast(Object message) {
    if (!mounted) return;
    final text = '$message';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text.startsWith('Bad state: ')
            ? text.substring('Bad state: '.length)
            : text)));
  }

  Future<void> _newHire(RentalDeskData data) async {
    String? unit = data.units.isEmpty ? null : data.units.first.id;
    String? customer;
    var from = DateTime.now();
    var to = DateTime.now().add(const Duration(days: 1));
    final depositCtrl = TextEditingController(text: '0.00');

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: const Text('New hire'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: unit,
                decoration: const InputDecoration(
                    labelText: 'Unit', border: OutlineInputBorder()),
                items: [
                  for (final u in data.units)
                    DropdownMenuItem(
                        value: u.id,
                        child: Text('${u.payload['unit_name']}')),
                ],
                onChanged: (v) => setDialogState(() => unit = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: customer,
                decoration: const InputDecoration(
                    labelText: 'Customer', border: OutlineInputBorder()),
                items: [
                  for (final cust in data.customers)
                    DropdownMenuItem(
                        value: cust.id,
                        child: Text('${cust.payload['customer_name']}')),
                ],
                onChanged: (v) => setDialogState(() => customer = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: c,
                          initialDate: from,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 1)),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => from = DateTime(picked.year,
                              picked.month, picked.day, 9));
                        }
                      },
                      child: Text('From '
                          '${from.toIso8601String().split('T').first}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: c,
                          initialDate: to,
                          firstDate: from,
                          lastDate: DateTime.now()
                              .add(const Duration(days: 366)),
                        );
                        if (picked != null) {
                          setDialogState(() => to = DateTime(picked.year,
                              picked.month, picked.day, 9));
                        }
                      },
                      child: Text(
                          'To ${to.toIso8601String().split('T').first}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: depositCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Deposit taken now (0 for none)',
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
                child: const Text('Book hire')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final unitId = unit;
    final customerId = customer;
    if (unitId == null || customerId == null) {
      _toast('Pick a unit and a customer.');
      return;
    }
    try {
      final hire = await (await _rental).book(
        unitId: unitId,
        customer: customerId,
        from: from,
        to: to,
        depositAmount: num.tryParse(depositCtrl.text.trim()) ?? 0,
      );
      _toast('Booked ${hire.id}');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(rentalDeskProvider);
    }
  }

  Future<void> _handOver(Document agreement) async {
    final conditionCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Hand over — ${agreement.id}'),
        content: TextField(
          controller: conditionCtrl,
          decoration: const InputDecoration(
              labelText: 'Condition out (optional)',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Back')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hand over')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await (await _rental)
          .checkOut(agreement.id, condition: conditionCtrl.text.trim());
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(rentalDeskProvider);
    }
  }

  Future<void> _takeBack(Document agreement) async {
    final conditionCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Return — ${agreement.id}'),
        content: TextField(
          controller: conditionCtrl,
          decoration: const InputDecoration(
              labelText: 'Condition back (optional)',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Back')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Return & invoice')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final invoice = await (await _rental)
          .returnUnit(agreement.id, condition: conditionCtrl.text.trim());
      _toast('Returned — invoiced as ${invoice.id} '
          '(${asNum(invoice.payload['grand_total']).toStringAsFixed(2)})');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(rentalDeskProvider);
    }
  }

  Future<void> _cancel(Document agreement) async {
    try {
      await (await _rental).cancelBooking(agreement.id);
      _toast('Cancelled ${agreement.id} — the window is free again.');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(rentalDeskProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rentalDeskProvider);
    final theme = Theme.of(context);
    return ResponsiveScaffold(
      title: 'Hire desk',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          if (data.units.isEmpty) {
            return const EmptyState(
              title: 'No rental units',
              message: 'Create Rental Units (each backed by a calendar '
                  'resource) and hire them out from here.',
              icon: Icons.construction_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            children: [
              FilledButton.icon(
                onPressed: () => _newHire(data),
                icon: const Icon(Icons.add),
                label: const Text('New hire'),
              ),
              const SizedBox(height: MercantisSpacing.md),
              Text('Fleet', style: theme.textTheme.titleSmall),
              const SizedBox(height: MercantisSpacing.sm),
              for (final unit in data.units) _unitRow(unit, data, theme),
              const SizedBox(height: MercantisSpacing.md),
              Text('Open hires', style: theme.textTheme.titleSmall),
              const SizedBox(height: MercantisSpacing.sm),
              if (data.openAgreements.isEmpty)
                const Text('Nothing booked or out.')
              else
                for (final a in data.openAgreements)
                  _agreementRow(a, data, theme),
            ],
          );
        },
      ),
    );
  }

  Widget _unitRow(Document unit, RentalDeskData data, ThemeData theme) {
    final out = data.outOn(unit.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: MercantisSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text('${unit.payload['unit_name']}',
                style: theme.textTheme.bodyMedium),
          ),
          if (out != null)
            Text('Out — ${data.customerName('${out.payload['customer']}')}',
                style: theme.textTheme.labelMedium!
                    .copyWith(color: theme.colorScheme.error))
          else
            Text('Free', style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }

  Widget _agreementRow(
      Document a, RentalDeskData data, ThemeData theme) {
    final status = '${a.payload['status']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: MercantisSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${a.id} · ${data.unitName('${a.payload['unit']}')} · '
                    '${data.customerName('${a.payload['customer']}')}',
                    style: theme.textTheme.bodyMedium),
                Text(
                    '$status · '
                    '${'${a.payload['starts_at']}'.split('T').first} → '
                    '${'${a.payload['ends_at']}'.split('T').first}',
                    style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          if (status == 'Draft') ...[
            TextButton(
                onPressed: () => _cancel(a), child: const Text('Cancel')),
            FilledButton.tonal(
                onPressed: () => _handOver(a),
                child: const Text('Hand over')),
          ] else
            FilledButton(
                onPressed: () => _takeBack(a),
                child: const Text('Return')),
        ],
      ),
    );
  }
}
