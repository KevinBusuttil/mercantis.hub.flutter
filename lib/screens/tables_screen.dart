import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../hospitality/tab_service.dart';
import '../ledger/ledger_values.dart';
import '../payments/pos_checkout.dart';

const _systemRoles = {'System Manager'};

/// Everything the floor screen needs in one load.
class TablesData {
  const TablesData({
    required this.tables,
    required this.openTabsByTable,
    required this.barTabs,
    required this.items,
    required this.profile,
    required this.sessionId,
  });

  final List<Document> tables;

  /// table id → its OPEN tab (at most one, enforced by TabService).
  final Map<String, Document> openTabsByTable;

  /// Open tabs with no table (the bar).
  final List<Document> barTabs;

  final List<Document> items;
  final Document? profile;
  final String? sessionId;
}

final tablesDataProvider =
    FutureProvider.autoDispose<TablesData>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final tables = [
    for (final t
        in await engine.list('POS Table', userRoles: _systemRoles))
      if (t.payload['enabled'] == null || isTrue(t.payload['enabled'])) t,
  ]..sort((a, b) =>
      '${a.payload['area']}${a.payload['table_name']}'
          .compareTo('${b.payload['area']}${b.payload['table_name']}'));

  final tabs = await engine.list('POS Tab', userRoles: _systemRoles);
  final open = <String, Document>{};
  final bar = <Document>[];
  for (final header in tabs) {
    if ('${header.payload['status']}' != 'Open') continue;
    // list() doesn't hydrate lines; the floor needs them for totals.
    final tab = await engine.fetch('POS Tab', header.id) ?? header;
    final table = asNonEmpty(tab.payload['table']);
    if (table == null) {
      bar.add(tab);
    } else {
      open[table] = tab;
    }
  }

  final items = await engine.list('Item', userRoles: _systemRoles);
  final profiles =
      await engine.list('POS Profile', userRoles: _systemRoles);
  final profile = profiles.isEmpty ? null : profiles.first;
  String? sessionId;
  if (profile != null) {
    for (final s in await engine.list('POS Session',
        filters: {'pos_profile': profile.id}, userRoles: _systemRoles)) {
      if (s.payload['status'] == 'Open') {
        sessionId = s.id;
        break;
      }
    }
  }
  return TablesData(
    tables: tables,
    openTabsByTable: open,
    barTabs: bar,
    items: items,
    profile: profile,
    sessionId: sessionId,
  );
});

/// V2-2: the floor. Tables colour-coded free/occupied, tap to open a tab,
/// order with the modifier picker, settle through the tender dialog onto
/// the per-till fiscal series. Running totals here are pre-tax; VAT is
/// computed at settlement by the same interceptors as every other sale.
class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({super.key});

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen> {
  Future<TabService> get _tabs async =>
      TabService(await ref.read(documentEngineProvider.future));

  void _toast(Object message) {
    if (!mounted) return;
    final text = '$message';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text.startsWith('Bad state: ')
            ? text.substring('Bad state: '.length)
            : text)));
  }

  Future<void> _openTab(Document table) async {
    var covers = 2;
    final serverCtrl = TextEditingController();
    final opened = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: Text('Open ${table.payload['table_name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: covers,
                decoration: const InputDecoration(
                    labelText: 'Covers', border: OutlineInputBorder()),
                items: [
                  for (var i = 1; i <= 12; i++)
                    DropdownMenuItem(value: i, child: Text('$i')),
                ],
                onChanged: (v) => setDialogState(() => covers = v ?? covers),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: serverCtrl,
                decoration: const InputDecoration(
                    labelText: 'Server (optional)',
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
                child: const Text('Open tab')),
          ],
        ),
      ),
    );
    if (opened != true) return;
    try {
      await (await _tabs).openTab(
        table: table.id,
        covers: covers,
        server: serverCtrl.text.trim().isEmpty
            ? null
            : serverCtrl.text.trim(),
      );
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(tablesDataProvider);
    }
  }

  /// Item picker → (optional) modifier picker → add to tab.
  Future<void> _order(Document tab, TablesData data) async {
    final engine = await ref.read(documentEngineProvider.future);
    if (!mounted) return;
    final item = await showDialog<Document>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Add to order'),
        children: [
          for (final i in data.items)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, i),
              child: Row(
                children: [
                  Expanded(child: Text('${i.payload['item_name']}')),
                  Text(asNum(i.payload['standard_rate'])
                      .toStringAsFixed(2)),
                ],
              ),
            ),
        ],
      ),
    );
    if (item == null) return;

    String? modifiers;
    num modifierAmount = 0;
    final groupId = asNonEmpty(item.payload['modifier_group']);
    if (groupId != null) {
      final group = await engine.fetch('Modifier Group', groupId);
      final options = group?.children['options'] ?? const <ChildRow>[];
      if (options.isNotEmpty && mounted) {
        final chosen = <int>{};
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => StatefulBuilder(
            builder: (c, setDialogState) => AlertDialog(
              title: Text('${group!.payload['group_name']}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < options.length; i++)
                    CheckboxListTile(
                      dense: true,
                      title: Text('${options[i].payload['option_name']}'),
                      subtitle:
                          asNum(options[i].payload['price_delta']) != 0
                              ? Text('+'
                                  '${asNum(options[i].payload['price_delta']).toStringAsFixed(2)}')
                              : null,
                      value: chosen.contains(i),
                      onChanged: (v) => setDialogState(() =>
                          v == true ? chosen.add(i) : chosen.remove(i)),
                    ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Skip')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Add')),
              ],
            ),
          ),
        );
        if (ok == true && chosen.isNotEmpty) {
          modifiers = [
            for (final i in chosen) '${options[i].payload['option_name']}',
          ].join(', ');
          for (final i in chosen) {
            modifierAmount += asNum(options[i].payload['price_delta']);
          }
        }
      }
    }

    try {
      await (await _tabs).addItem(
        tab.id,
        item: item.id,
        modifiers: modifiers,
        modifierAmount: modifierAmount,
        priceList: asNonEmpty(data.profile?.payload['price_list']),
      );
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(tablesDataProvider);
    }
  }

  Future<void> _settle(Document tab, TablesData data) async {
    final service = await _tabs;
    final fresh = await (await ref.read(documentEngineProvider.future))
        .fetch('POS Tab', tab.id);
    if (fresh == null) return;
    final total = TabService.tabTotal(fresh);
    if (!mounted) return;

    final cashCtrl =
        TextEditingController(text: total.toStringAsFixed(2));
    final cardCtrl = TextEditingController(text: '0.00');
    final tenders = await showDialog<List<PosTender>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) {
          final cash = num.tryParse(cashCtrl.text.trim()) ?? 0;
          final card = num.tryParse(cardCtrl.text.trim()) ?? 0;
          return AlertDialog(
            title: Text('Settle — ${total.toStringAsFixed(2)} (ex VAT)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: cashCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Cash', border: OutlineInputBorder()),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cardCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Card', border: OutlineInputBorder()),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(c, [
                  if (cash > 0) PosTender(type: 'Cash', amount: cash),
                  if (card > 0) PosTender(type: 'Card', amount: card),
                ]),
                child: const Text('Take payment'),
              ),
            ],
          );
        },
      ),
    );
    if (tenders == null || tenders.isEmpty) return;

    try {
      final invoice = await service.settleTab(
        tab.id,
        tenders: tenders,
        warehouse: asNonEmpty(data.profile?.payload['warehouse']),
        taxCode: asNonEmpty(data.profile?.payload['tax_code']),
        pricesIncludeTax:
            isTrue(data.profile?.payload['prices_include_tax']),
        posProfile: data.profile?.id,
        posSession: data.sessionId,
        tillSeries: asNonEmpty(data.profile?.payload['receipt_series']),
        priceList: asNonEmpty(data.profile?.payload['price_list']),
      );
      _toast('Settled as ${invoice.id}');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(tablesDataProvider);
    }
  }

  Future<void> _void(Document tab) async {
    final reasonCtrl = TextEditingController();
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Void this tab?'),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Reason (required — kept on record)',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Back')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Void')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await (await _tabs).voidTab(tab.id, reason: reasonCtrl.text);
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(tablesDataProvider);
    }
  }

  Future<void> _tabSheet(Document tab, TablesData data) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) {
        final lines = tab.children['items'] ?? const <ChildRow>[];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${tab.id} · ${tab.payload['covers']} covers'
                    '${asNonEmpty(tab.payload['server']) != null ? ' · ${tab.payload['server']}' : ''}',
                    style: Theme.of(c).textTheme.titleMedium),
                const SizedBox(height: MercantisSpacing.sm),
                if (lines.isEmpty)
                  const Text('Nothing ordered yet.')
                else
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                          '${asNum(l.payload['qty'])} × '
                          '${l.payload['item']}'
                          '${asNonEmpty(l.payload['modifiers']) != null ? ' (${l.payload['modifiers']})' : ''}'
                          '  ${(asNum(l.payload['qty']) * (asNum(l.payload['rate']) + asNum(l.payload['modifier_amount']))).toStringAsFixed(2)}'),
                    ),
                const SizedBox(height: MercantisSpacing.sm),
                Text('Total (ex VAT): '
                    '${TabService.tabTotal(tab).toStringAsFixed(2)}'),
                const SizedBox(height: MercantisSpacing.md),
                Wrap(
                  spacing: MercantisSpacing.sm,
                  runSpacing: MercantisSpacing.sm,
                  children: [
                    FilledButton.tonal(
                      onPressed: () async {
                        Navigator.pop(c);
                        await _order(tab, data);
                      },
                      child: const Text('Add items'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        await _settle(tab, data);
                      },
                      child: const Text('Settle'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        await _void(tab);
                      },
                      child: const Text('Void'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tablesDataProvider);
    return ResponsiveScaffold(
      title: 'Tables',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          if (data.tables.isEmpty && data.barTabs.isEmpty) {
            return const EmptyState(
              title: 'No tables yet',
              message: 'Create POS Tables to lay out your floor — or open '
                  'a bar tab from the button below.',
              icon: Icons.table_bar_outlined,
            );
          }
          final areas = <String, List<Document>>{};
          for (final t in data.tables) {
            areas
                .putIfAbsent(
                    asNonEmpty(t.payload['area']) ?? 'Floor', () => [])
                .add(t);
          }
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            children: [
              for (final area in areas.entries) ...[
                Text(area.key,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: MercantisSpacing.sm),
                Wrap(
                  spacing: MercantisSpacing.sm,
                  runSpacing: MercantisSpacing.sm,
                  children: [
                    for (final table in area.value)
                      _tableCard(table, data),
                  ],
                ),
                const SizedBox(height: MercantisSpacing.md),
              ],
              if (data.barTabs.isNotEmpty) ...[
                Text('Bar tabs',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: MercantisSpacing.sm),
                Wrap(
                  spacing: MercantisSpacing.sm,
                  runSpacing: MercantisSpacing.sm,
                  children: [
                    for (final tab in data.barTabs)
                      ActionChip(
                        avatar: const Icon(Icons.local_bar_outlined,
                            size: 18),
                        label: Text(tab.id),
                        onPressed: () => _tabSheet(tab, data),
                      ),
                  ],
                ),
                const SizedBox(height: MercantisSpacing.md),
              ],
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await (await _tabs).openTab();
                  } catch (e) {
                    _toast(e);
                  } finally {
                    ref.invalidate(tablesDataProvider);
                  }
                },
                icon: const Icon(Icons.local_bar_outlined),
                label: const Text('Open bar tab'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tableCard(Document table, TablesData data) {
    final theme = Theme.of(context);
    final tab = data.openTabsByTable[table.id];
    final occupied = tab != null;
    final color = occupied
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => occupied ? _tabSheet(tab, data) : _openTab(table),
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(MercantisSpacing.md),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${table.payload['table_name']}',
                style: theme.textTheme.titleSmall),
            Text('${table.payload['seats']} seats',
                style: theme.textTheme.labelSmall),
            const SizedBox(height: 6),
            if (occupied) ...[
              Text('${tab.payload['covers']} covers',
                  style: theme.textTheme.labelSmall),
              Text(TabService.tabTotal(tab).toStringAsFixed(2),
                  style: theme.textTheme.titleMedium),
            ] else
              Text('Free', style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
