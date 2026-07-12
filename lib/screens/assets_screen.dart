import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../assets/asset_service.dart';
import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// The asset register in one load: hydrated assets (the schedule drives
/// NBV) plus how many depreciation periods are due right now.
class AssetsData {
  const AssetsData({required this.assets, required this.dueCount});

  final List<Document> assets;
  final int dueCount;
}

final assetsDataProvider =
    FutureProvider.autoDispose<AssetsData>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final today = DateTime.now().toIso8601String().split('T').first;
  final assets = <Document>[];
  var due = 0;
  for (final header in await engine.list('Asset', userRoles: _systemRoles)) {
    final asset = await engine.fetch('Asset', header.id) ?? header;
    assets.add(asset);
    if ('${asset.payload['status']}' != 'In Use') continue;
    for (final row in asset.children['schedule'] ?? const <ChildRow>[]) {
      if (!isTrue(row.payload['posted']) &&
          '${row.payload['period_date']}'.compareTo(today) <= 0) {
        due++;
      }
    }
  }
  assets.sort(
      (a, b) => '${a.payload['asset_name']}'.compareTo('${b.payload['asset_name']}'));
  return AssetsData(assets: assets, dueCount: due);
});

/// S10: the fixed-asset register — every asset with its gross, what's
/// been depreciated, and the net book value — plus one button that posts
/// every depreciation period due to date as Journal Entries.
class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  bool _posting = false;

  Future<void> _postDue() async {
    setState(() => _posting = true);
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final posted = await AssetService(engine).postDueDepreciation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(posted == 0
                ? 'Nothing due — depreciation is up to date.'
                : 'Posted $posted depreciation '
                    'entr${posted == 1 ? 'y' : 'ies'}.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
      ref.invalidate(assetsDataProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(assetsDataProvider);
    final theme = Theme.of(context);
    return ResponsiveScaffold(
      title: 'Fixed assets',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          if (data.assets.isEmpty) {
            return const EmptyState(
              title: 'No assets yet',
              message: 'Create an Asset, capitalise it, and its '
                  'straight-line schedule posts here month by month.',
              icon: Icons.precision_manufacturing_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            children: [
              FilledButton.icon(
                onPressed: _posting || data.dueCount == 0 ? null : _postDue,
                icon: const Icon(Icons.play_arrow_outlined),
                label: Text(data.dueCount == 0
                    ? 'Depreciation up to date'
                    : 'Post due depreciation (${data.dueCount})'),
              ),
              const SizedBox(height: MercantisSpacing.md),
              for (final asset in data.assets) _assetRow(asset, theme),
            ],
          );
        },
      ),
    );
  }

  Widget _assetRow(Document asset, ThemeData theme) {
    final gross = asNum(asset.payload['gross_purchase_amount']);
    final nbv = AssetService.netBookValue(asset);
    final status = '${asset.payload['status']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: MercantisSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${asset.payload['asset_name']} · ${asset.id}',
                    style: theme.textTheme.titleSmall),
                Text(
                    '$status · gross ${gross.toStringAsFixed(2)} · '
                    'depreciated ${(gross - nbv).toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(nbv.toStringAsFixed(2),
                  style: theme.textTheme.titleMedium),
              Text('book value', style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}
