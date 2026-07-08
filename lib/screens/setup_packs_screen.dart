import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../settings/hub_settings.dart';
import '../setup_library/builtin_packs.dart';
import '../setup_library/setup_pack.dart';
import '../setup_library/setup_pack_applier.dart';

const _systemRoles = {'System Manager'};

/// What the catalogue shows: the built-in packs and which versions this
/// install has applied (from the recorded Setup Pack Application diffs).
typedef _Catalogue = ({
  List<Document> applications,
  Set<String> appliedKeys, // '{packId}@{version}'
});

final _catalogueProvider = FutureProvider.autoDispose<_Catalogue>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final applications = await engine.list('Setup Pack Application',
      userRoles: _systemRoles);
  applications.sort((a, b) =>
      '${b.payload['applied_at']}'.compareTo('${a.payload['applied_at']}'));
  return (
    applications: applications,
    appliedKeys: {
      for (final a in applications)
        '${a.payload['pack_id']}@${a.payload['pack_version']}',
    },
  );
});

/// The Setup Library catalogue (design doc §2): built-in packs applied with
/// one tap, side-loaded bundles imported (integrity-checked), and the full
/// history of what every pack changed.
class SetupPacksScreen extends ConsumerStatefulWidget {
  const SetupPacksScreen({super.key});

  @override
  ConsumerState<SetupPacksScreen> createState() => _SetupPacksScreenState();
}

class _SetupPacksScreenState extends ConsumerState<SetupPacksScreen> {
  bool _busy = false;

  Future<void> _apply(SetupPack pack) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final result = await SetupPackApplier(engine: engine).apply(pack);

      // Module visibility the pack implies, through the settings that own it.
      if (result.moduleToggles.isNotEmpty) {
        final settings = ref.read(hubSettingsProvider);
        final t = result.moduleToggles;
        await ref.read(hubSettingsProvider.notifier).save(
              engine,
              settings.copyWith(
                stockEnabled: t['stock'] ?? settings.stockEnabled,
                posEnabled: t['pos'] ?? settings.posEnabled,
                projectsEnabled: t['projects'] ?? settings.projectsEnabled,
                manufacturingEnabled:
                    t['manufacturing'] ?? settings.manufacturingEnabled,
                deliveriesEnabled:
                    t['deliveries'] ?? settings.deliveriesEnabled,
              ),
            );
      }

      messenger.showSnackBar(SnackBar(
          content: Text(result.alreadyApplied
              ? '${pack.name} ${pack.version} was already applied — '
                  'nothing changed.'
              : '${pack.name} applied: ${result.created} added, '
                  '${result.skipped} already present.')));
      ref.invalidate(_catalogueProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Solo side-load: paste a pack bundle; the integrity check rejects
  /// anything tampered or truncated before a single document is touched.
  Future<void> _importBundle() async {
    final ctrl = TextEditingController();
    final json = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import a setup pack bundle'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Paste the pack bundle JSON. Its integrity hash is '
                  'verified before anything is applied.',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text),
              child: const Text('Verify & apply')),
        ],
      ),
    );
    if (json == null || json.trim().isEmpty) return;
    try {
      final pack = SetupPack.fromBundleJson(json.trim());
      await _apply(pack);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _showDiff(Document application) {
    final List<dynamic> diff;
    try {
      diff = jsonDecode('${application.payload['diff']}') as List;
    } catch (_) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${application.payload['pack_id']} '
            '${application.payload['pack_version']} — what changed'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final change in diff)
                ListTile(
                  dense: true,
                  leading: Icon(change['action'] == 'skipped'
                      ? Icons.skip_next_outlined
                      : Icons.add_circle_outline),
                  title: Text('${change['doctype']}: ${change['id']}'),
                  subtitle: Text('${change['action']}'),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(c), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(_catalogueProvider);
    return ResponsiveScaffold(
      title: 'Setup packs',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      padBody: false,
      actions: [
        IconButton(
          tooltip: 'Import a pack bundle',
          icon: const Icon(Icons.file_download_outlined),
          onPressed: _busy ? null : _importBundle,
        ),
      ],
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (catalogue) => ListView(
          padding: const EdgeInsets.all(MercantisSpacing.lg),
          children: [
            Text(
                'Packs configure Atlas for a business shape — accounts, '
                'defaults, modules and deterministic rules. Applying is '
                'safe: nothing you already have is overwritten, and every '
                'change is recorded.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: MercantisSpacing.md),
            AtlasSectionCard(
              name: 'Catalogue',
              child: Column(
                children: [
                  for (final pack in builtinSetupPacks)
                    ListTile(
                      title: Text('${pack.name}  ·  ${pack.version}'),
                      subtitle: Text(pack.description),
                      trailing: catalogue.appliedKeys
                              .contains('${pack.id}@${pack.version}')
                          ? const Chip(label: Text('Applied'))
                          : FilledButton.tonal(
                              onPressed:
                                  _busy ? null : () => _apply(pack),
                              child: const Text('Apply'),
                            ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: MercantisSpacing.md),
            AtlasSectionCard(
              name: 'Applied history',
              child: catalogue.applications.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(MercantisSpacing.md),
                      child: Text('No packs applied yet.'),
                    )
                  : Column(
                      children: [
                        for (final a in catalogue.applications)
                          ListTile(
                            dense: true,
                            title: Text('${a.payload['pack_id']} '
                                '${a.payload['pack_version']}'),
                            subtitle: Text(
                                '${'${a.payload['applied_at']}'.split('T').first} — '
                                '${a.payload['created_count']} added, '
                                '${a.payload['skipped_count']} already present'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showDiff(a),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
