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

  /// Cash/card entry for [total] (pre-tax). Returns null on cancel.
  Future<List<PosTender>?> _tenderDialog(num total, {String? note}) async {
    if (!mounted) return null;
    final cashCtrl =
        TextEditingController(text: total.toStringAsFixed(2));
    final cardCtrl = TextEditingController(text: '0.00');
    return showDialog<List<PosTender>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) {
          final cash = num.tryParse(cashCtrl.text.trim()) ?? 0;
          final card = num.tryParse(cardCtrl.text.trim()) ?? 0;
          return AlertDialog(
            title: Text('Settle — ${total.toStringAsFixed(2)} (ex VAT)'
                '${note != null ? '\n$note' : ''}'),
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
  }

  num _serviceChargePercent(TablesData data) =>
      asNum(data.profile?.payload['service_charge_percent']);

  /// Settles [rowIndexes] of the tab (null = everything) through the
  /// tender dialog, applying the profile's service charge to the settled
  /// portion.
  Future<void> _settle(Document tab, TablesData data,
      {List<int>? rowIndexes}) async {
    final service = await _tabs;
    final fresh = await (await ref.read(documentEngineProvider.future))
        .fetch('POS Tab', tab.id);
    if (fresh == null) return;

    final rows = fresh.children['items'] ?? const <ChildRow>[];
    num total = 0;
    for (var i = 0; i < rows.length; i++) {
      if (rowIndexes != null && !rowIndexes.contains(i)) continue;
      total += asNum(rows[i].payload['qty']) *
          (asNum(rows[i].payload['rate']) +
              asNum(rows[i].payload['modifier_amount']));
    }
    total = round2(total);
    final pct = _serviceChargePercent(data);
    final charge = pct > 0 ? round2(total * pct / 100) : 0;

    final tenders = await _tenderDialog(
      round2(total + charge),
      note: charge > 0 ? 'incl. $charge service charge ($pct%)' : null,
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
        rowIndexes: rowIndexes,
        serviceChargePercent: pct,
        serviceChargeItem:
            asNonEmpty(data.profile?.payload['service_charge_item']),
      );
      _toast('Settled as ${invoice.id}');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(tablesDataProvider);
    }
  }

  /// Split: pick lines, settle just those into their own invoice. The
  /// rest of the tab stays open on the table.
  Future<void> _split(Document tab, TablesData data) async {
    final fresh = await (await ref.read(documentEngineProvider.future))
        .fetch('POS Tab', tab.id);
    if (fresh == null || !mounted) return;
    final rows = fresh.children['items'] ?? const <ChildRow>[];
    if (rows.length < 2) {
      _toast('Nothing to split — the tab has ${rows.length} line(s).');
      return;
    }
    final chosen = <int>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: const Text('Split — settle these lines'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rows.length; i++)
                CheckboxListTile(
                  dense: true,
                  title: Text(
                      '${asNum(rows[i].payload['qty'])} × '
                      '${rows[i].payload['item']}'),
                  secondary: Text((asNum(rows[i].payload['qty']) *
                          (asNum(rows[i].payload['rate']) +
                              asNum(rows[i].payload['modifier_amount'])))
                      .toStringAsFixed(2)),
                  value: chosen.contains(i),
                  onChanged: (v) => setDialogState(
                      () => v == true ? chosen.add(i) : chosen.remove(i)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: chosen.isEmpty
                    ? null
                    : () => Navigator.pop(c, true),
                child: const Text('Settle selection')),
          ],
        ),
      ),
    );
    if (ok != true || chosen.isEmpty) return;
    await _settle(fresh, data, rowIndexes: chosen.toList()..sort());
  }

  /// Merge this tab into another open tab (parties joining up).
  Future<void> _merge(Document tab, TablesData data) async {
    final targets = [
      ...data.openTabsByTable.values,
      ...data.barTabs,
    ]..removeWhere((t) => t.id == tab.id);
    if (targets.isEmpty) {
      _toast('No other open tab to merge into.');
      return;
    }
    if (!mounted) return;
    final target = await showDialog<Document>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Merge into…'),
        children: [
          for (final t in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, t),
              child: Text(
                  '${t.id} · ${asNonEmpty(t.payload['table']) ?? 'Bar'}'),
            ),
        ],
      ),
    );
    if (target == null) return;
    try {
      await (await _tabs).mergeTabs(tab.id, target.id);
      _toast('Merged into ${target.id}');
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

  /// V2-5: comp a line — off the bill, on the record.
  Future<void> _comp(Document tab, int rowIndex) async {
    final reasonCtrl = TextEditingController();
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Comp this item?'),
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
              child: const Text('Comp')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await (await _tabs).compLine(tab.id, rowIndex,
          reason: reasonCtrl.text);
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
                  for (var i = 0; i < lines.length; i++)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              '${asNum(lines[i].payload['qty'])} × '
                              '${lines[i].payload['item']}'
                              '${asNonEmpty(lines[i].payload['modifiers']) != null ? ' (${lines[i].payload['modifiers']})' : ''}'
                              '  ${isTrue(lines[i].payload['comp']) ? 'comp' : (asNum(lines[i].payload['qty']) * (asNum(lines[i].payload['rate']) + asNum(lines[i].payload['modifier_amount']))).toStringAsFixed(2)}',
                              style: isTrue(lines[i].payload['comp'])
                                  ? Theme.of(c).textTheme.bodyMedium!
                                      .copyWith(
                                          decoration:
                                              TextDecoration.lineThrough)
                                  : null),
                        ),
                        if (!isTrue(lines[i].payload['comp']))
                          IconButton(
                            icon: const Icon(Icons.money_off_outlined,
                                size: 18),
                            tooltip: 'Comp (free of charge)',
                            visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              final index = i;
                              Navigator.pop(c);
                              await _comp(tab, index);
                            },
                          ),
                      ],
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
                    FilledButton.tonal(
                      onPressed: () async {
                        Navigator.pop(c);
                        try {
                          final ticket =
                              await (await _tabs).sendToKitchen(tab.id);
                          _toast('Sent ${ticket.id} to the kitchen');
                        } catch (e) {
                          _toast(e);
                        } finally {
                          ref.invalidate(tablesDataProvider);
                        }
                      },
                      child: const Text('Send to kitchen'),
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
                        await _split(tab, data);
                      },
                      child: const Text('Split'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        await _merge(tab, data);
                      },
                      child: const Text('Merge'),
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
