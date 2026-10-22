import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../features/hub_feature.dart';
import '../navigation/hub_surface.dart';
import '../onboarding/business_preset.dart';
import '../settings/hub_settings.dart';

/// The feature catalogue: the business type, the Owner/Accountant view and
/// every optional feature, each with what it adds. Changes save at once and
/// the navigation follows immediately. Turning something off only hides it —
/// its records, postings and history are kept and stay searchable.
class FeaturesScreen extends ConsumerStatefulWidget {
  const FeaturesScreen({super.key});

  @override
  ConsumerState<FeaturesScreen> createState() => _FeaturesScreenState();
}

class _FeaturesScreenState extends ConsumerState<FeaturesScreen> {
  bool _saving = false;

  Future<void> _save(HubSettings next, String message) async {
    setState(() => _saving = true);
    await ref.read(hubSettingsProvider.notifier).apply(next);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeProfile(HubSettings current, BusinessPreset preset) async {
    final adds = preset.features.difference(current.features);
    final hides = current.features.difference(preset.features);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Switch to ${preset.label}?'),
        content: SingleChildScrollView(
          child: Text([
            if (adds.isNotEmpty)
              'Turns on: ${adds.map((f) => f.label).join(', ')}.',
            if (hides.isNotEmpty)
              'Hides: ${hides.map((f) => f.label).join(', ')}. Their records '
                  'are kept and you can turn them back on here.',
            if (adds.isEmpty && hides.isEmpty)
              'Your features stay the same; the phone bar follows the new '
                  'business type.',
          ].join('\n\n')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Switch')),
        ],
      ),
    );
    if (ok != true) return;
    await _save(current.applyingPreset(preset),
        'Business type set to ${preset.label}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(hubSettingsProvider);
    final surface = ref.watch(hubSurfaceProvider);
    final preset = settings.businessPresetId.isEmpty
        ? null
        : BusinessPreset.byId(settings.businessPresetId);

    return ResponsiveScaffold(
      title: 'Business type & features',
      padBody: false,
      body: ListView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        children: [
          if (settings.classicNavigation) ...[
            _ClassicBanner(
              busy: _saving,
              onSimplify: () => _save(
                  settings.copyWith(classicNavigation: false),
                  'Simplified navigation on — nothing was removed'),
            ),
            const SizedBox(height: MercantisSpacing.lg),
          ],
          AtlasSectionCard(
            name: 'Business type',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  preset == null
                      ? 'Not chosen — every feature you had is kept.'
                      : '${preset.label}. ${preset.description}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: MercantisSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PopupMenuButton<BusinessPreset>(
                    tooltip: 'Change business type',
                    enabled: !_saving,
                    onSelected: (p) => _changeProfile(settings, p),
                    itemBuilder: (_) => [
                      for (final p in BusinessPreset.all)
                        PopupMenuItem(value: p, child: Text(p.label)),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz),
                          SizedBox(width: 8),
                          Text('Change business type'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MercantisSpacing.lg),
          AtlasSectionCard(
            name: 'View',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<HubUserMode>(
                  segments: [
                    for (final mode in HubUserMode.values)
                      ButtonSegment<HubUserMode>(
                          value: mode, label: Text(mode.title)),
                  ],
                  selected: {settings.userMode},
                  onSelectionChanged: _saving
                      ? null
                      : (sel) => _save(settings.withUserMode(sel.first),
                          '${sel.first.title} view on'),
                ),
                const SizedBox(height: MercantisSpacing.sm),
                Text(settings.userMode.blurb, style: theme.textTheme.bodySmall),
                const SizedBox(height: MercantisSpacing.xs),
                Text(HubUserMode.disclaimer,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          for (final group in HubFeatureGroup.values) ...[
            const SizedBox(height: MercantisSpacing.lg),
            AtlasSectionCard(
              name: group.label,
              child: Column(
                children: [
                  for (final f in HubFeature.values)
                    if (f.group == group)
                      _FeatureSwitch(
                        feature: f,
                        on: settings.features.contains(f),
                        blockedBy: f.requires != null &&
                                !settings.features.contains(f.requires)
                            ? f.requires
                            : null,
                        enabled: !_saving,
                        onChanged: (v) => _save(settings.withFeature(f, v),
                            '${f.label} ${v ? 'on' : 'hidden — records kept'}'),
                      ),
                ],
              ),
            ),
          ],
          const SizedBox(height: MercantisSpacing.lg),
          AtlasSectionCard(
            name: 'Team and system',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Approvals, users and roles'),
                  subtitle: Text(surface.teamConnected
                      ? 'On — this device is connected to Atlas Team.'
                      : 'Need Atlas Team: approvals and roles route work '
                          'between people.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/w/setup/team'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.build_outlined),
                  title: const Text('System configuration'),
                  subtitle: const Text('Record-type, workflow and custom-field '
                      'designers, users and roles — for implementers.'),
                  value: settings.systemTools,
                  onChanged: _saving
                      ? null
                      : (v) => _save(settings.copyWith(systemTools: v),
                          'System configuration ${v ? 'shown' : 'hidden'}'),
                ),
                if (!settings.classicNavigation)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.view_list_outlined),
                    title: const Text('Classic full navigation'),
                    subtitle: const Text('Show every accounting section '
                        'whatever the view, as before.'),
                    value: false,
                    onChanged: _saving
                        ? null
                        : (v) => _save(
                            settings.copyWith(classicNavigation: true),
                            'Classic navigation on'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: MercantisSpacing.lg),
          Text(
            'Turning a feature off only hides it. Records, postings and '
            'history are kept, stay searchable, and come back when you turn '
            'it on.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _FeatureSwitch extends StatelessWidget {
  const _FeatureSwitch({
    required this.feature,
    required this.on,
    required this.enabled,
    required this.onChanged,
    this.blockedBy,
  });

  final HubFeature feature;
  final bool on;
  final bool enabled;
  final HubFeature? blockedBy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final blocked = blockedBy;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(feature.icon),
      title: Text(feature.label),
      subtitle: Text(blocked == null
          ? feature.description
          : '${feature.description} Needs ${blocked.label}.'),
      value: on && blocked == null,
      onChanged: enabled && blocked == null ? onChanged : null,
    );
  }
}

class _ClassicBanner extends StatelessWidget {
  const _ClassicBanner({required this.busy, required this.onSimplify});

  final bool busy;
  final VoidCallback onSimplify;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.primaryContainer,
      borderRadius: MercantisRadius.rMd,
      child: Padding(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are on the classic full navigation',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: cs.onPrimaryContainer)),
            const SizedBox(height: MercantisSpacing.xs),
            Text(
              'This installation predates business profiles, so everything '
              'it had is still shown. Simplify to see only your features '
              'below, in plain language — nothing is deleted and you can '
              'switch back.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: MercantisSpacing.sm),
            FilledButton(
              onPressed: busy ? null : onSimplify,
              child: const Text('Use simplified navigation'),
            ),
          ],
        ),
      ),
    );
  }
}
