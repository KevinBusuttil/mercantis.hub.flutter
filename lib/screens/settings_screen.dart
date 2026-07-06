import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../auth/auth_store.dart';
import '../auth/operator_setup_screen.dart';
import '../build_info.dart';
import '../modules/accounting/coa_repair.dart';
import '../modules/accounting/year_end_close_service.dart';
import '../settings/hub_settings.dart';
import 'company_sync_screen.dart';
import 'numbering_series_screen.dart';

/// App preferences: the signed-in operator (passcode lock managed by the auth
/// gate), optional-module visibility, and the advanced toggle. Module/advanced
/// settings persist to the `Hub Settings` singleton; visibility changes apply
/// on next launch.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late HubSettings _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(hubSettingsProvider);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final engine = await ref.read(documentEngineProvider.future);
    await ref.read(hubSettingsProvider.notifier).save(engine, _draft);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  void _lock() => ref.read(authProvider.notifier).lock();

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'You will need to pick an operator and enter a passcode to sign '
            'back in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true) return;
    final engine = await ref.read(documentEngineProvider.future);
    await ref.read(authProvider.notifier).signOut(engine);
  }

  Future<void> _addOperator() {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const OperatorSetupScreen(firstRun: false),
    ));
  }

  Future<void> _repairCoa() async {
    final engine = await ref.read(documentEngineProvider.future);
    final roles = ref.read(currentUserProvider).roles;
    final CoaRepairSummary summary =
        await ChartOfAccountsRepair(engine: engine, roles: roles).repair();
    if (!mounted) return;
    final message = summary.repairedAnything
        ? 'Repaired: ${summary.accountsCreated} account(s) re-created, '
            '${summary.accountsReparented} re-grouped, '
            '${summary.defaultsRewired} default(s) re-wired; '
            '${summary.mastersCreated} master(s) re-created, '
            '${summary.mastersReparented} re-grouped.'
        : 'Chart of accounts & masters are healthy — nothing to repair.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _closeYear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Close financial year?'),
        content: const Text(
            'This drafts a Closing Entry journal that zeroes every income and '
            'expense account into Retained Earnings, dated today. It is a Draft '
            'you can review and submit — nothing posts yet.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Draft closing entry')),
        ],
      ),
    );
    if (confirmed != true) return;
    final engine = await ref.read(documentEngineProvider.future);
    final roles = ref.read(currentUserProvider).roles;
    final postingDate = DateTime.now().toIso8601String().split('T').first;
    try {
      final je = await YearEndCloseService(engine: engine, roles: roles)
          .prepare(postingDate: postingDate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Draft closing entry ${je.id} created — review and '
              'submit it from Journal Entries.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is DocumentEngineError ? e.humanMessage : '$e')));
    }
  }

  Future<void> _changePasscode() async {
    final auth = ref.read(authProvider);
    final active = auth.active;
    if (active == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ChangePasscodeDialog(profileId: active.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final active = auth.active;

    return ResponsiveScaffold(
      title: 'Settings',
      padBody: false,
      body: ListView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        children: [
          AtlasSectionCard(
            name: 'Signed in',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                  child: Text(_initials(active?.name ?? '?'))),
              title: Text(active?.name ?? 'No operator'),
              subtitle: Text([
                if ((active?.email ?? '').isNotEmpty) active!.email,
                active == null
                    ? ''
                    : active.roles.join(', '),
              ].where((s) => s.isNotEmpty).join('  ·  ')),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: active == null ? null : _changePasscode,
                icon: const Icon(Icons.password),
                label: const Text('Change passcode'),
              ),
              OutlinedButton.icon(
                onPressed: _addOperator,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add operator'),
              ),
              OutlinedButton.icon(
                onPressed: _lock,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Lock'),
              ),
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
          if (auth.profiles.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${auth.profiles.length} operators on this device',
                  style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: MercantisSpacing.lg),
          AtlasSectionCard(
            name: 'Setup',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Appearance'),
                  subtitle: const Text('Theme (light, dark, system)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SettingsView(
                      appName: 'Neuradix Atlas',
                      appVersion: BuildInfo.appVersion,
                    ),
                  )),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: const Text('Company sync'),
                  subtitle:
                      const Text('Share this company across devices, serverless'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const CompanySyncScreen(),
                  )),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.tag),
                  title: const Text('Numbering series'),
                  subtitle:
                      const Text('Inspect and set document number sequences'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const NumberingSeriesScreen(),
                  )),
                ),
              ],
            ),
          ),
          const SizedBox(height: MercantisSpacing.lg),
          AtlasSectionCard(
            name: 'Tools',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.healing_outlined),
                  title: const Text('Repair chart of accounts'),
                  subtitle: const Text(
                      'Re-create missing starter accounts and re-wire broken '
                      'company default-account links'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _repairCoa,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('Close financial year'),
                  subtitle: const Text(
                      'Draft a closing entry that zeroes the P&L into '
                      'Retained Earnings for review'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _closeYear,
                ),
              ],
            ),
          ),
          const SizedBox(height: MercantisSpacing.lg),
          AtlasSectionCard(
            name: 'Optional modules',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: MercantisSpacing.xs),
                  child: Text('Hidden modules apply on next launch.',
                      style: theme.textTheme.bodySmall),
                ),
                AtlasFieldRow(
                  label: 'Stock & Warehousing',
                  onTap: _saving
                      ? null
                      : () => setState(() => _draft =
                          _draft.copyWith(stockEnabled: !_draft.stockEnabled)),
                  trailing: Switch(
                    value: _draft.stockEnabled,
                    onChanged: _saving
                        ? null
                        : (v) => setState(
                            () => _draft = _draft.copyWith(stockEnabled: v)),
                  ),
                ),
                AtlasFieldRow(
                  label: 'Point of Sale',
                  onTap: _saving
                      ? null
                      : () => setState(() =>
                          _draft = _draft.copyWith(posEnabled: !_draft.posEnabled)),
                  trailing: Switch(
                    value: _draft.posEnabled,
                    onChanged: _saving
                        ? null
                        : (v) => setState(
                            () => _draft = _draft.copyWith(posEnabled: v)),
                  ),
                ),
                AtlasFieldRow(
                  label: 'Manufacturing',
                  onTap: _saving
                      ? null
                      : () => setState(() => _draft = _draft.copyWith(
                          manufacturingEnabled: !_draft.manufacturingEnabled)),
                  trailing: Switch(
                    value: _draft.manufacturingEnabled,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() =>
                            _draft = _draft.copyWith(manufacturingEnabled: v)),
                  ),
                ),
                AtlasFieldRow(
                  label: 'Deliveries (routes & fleet)',
                  onTap: _saving
                      ? null
                      : () => setState(() => _draft = _draft.copyWith(
                          deliveriesEnabled: !_draft.deliveriesEnabled)),
                  trailing: Switch(
                    value: _draft.deliveriesEnabled,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() =>
                            _draft = _draft.copyWith(deliveriesEnabled: v)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MercantisSpacing.lg),
          AtlasSectionCard(
            name: 'Mode',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<HubUserMode>(
                  segments: [
                    for (final mode in HubUserMode.values)
                      ButtonSegment<HubUserMode>(
                          value: mode, label: Text(mode.title)),
                  ],
                  selected: {_draft.userMode},
                  onSelectionChanged: _saving
                      ? null
                      : (selection) => setState(
                          () => _draft = _draft.withUserMode(selection.first)),
                ),
                const SizedBox(height: MercantisSpacing.sm),
                Text(_draft.userMode.blurb, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: MercantisSpacing.lg),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Save settings'),
          ),
          const SizedBox(height: MercantisSpacing.lg),
          AtlasSectionCard(
            name: 'About',
            child: Column(
              children: [
                const AtlasFieldRow(
                  label: 'Version',
                  value: 'v${BuildInfo.appVersion}',
                  readOnly: true,
                ),
                AtlasFieldRow(
                  label: 'Commit',
                  value: BuildInfo.commitLabel,
                  placeholder: '—',
                  readOnly: true,
                ),
                if (BuildInfo.ref.isNotEmpty)
                  const AtlasFieldRow(
                    label: 'Branch',
                    value: BuildInfo.ref,
                    readOnly: true,
                  ),
                if (BuildInfo.buildTime.isNotEmpty)
                  const AtlasFieldRow(
                    label: 'Built',
                    value: BuildInfo.buildTime,
                    readOnly: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Re-derive the active operator's passcode after verifying the current one.
class _ChangePasscodeDialog extends ConsumerStatefulWidget {
  const _ChangePasscodeDialog({required this.profileId});
  final String profileId;

  @override
  ConsumerState<_ChangePasscodeDialog> createState() =>
      _ChangePasscodeDialogState();
}

class _ChangePasscodeDialogState extends ConsumerState<_ChangePasscodeDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text.length < 4) {
      setState(() => _error = 'New passcode must be at least 4 digits.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'New passcodes do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final engine = await ref.read(documentEngineProvider.future);
    final ok = await ref.read(authProvider.notifier).changePasscode(
          engine,
          profileId: widget.profileId,
          current: _current.text,
          next: _next.text,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Current passcode is incorrect.';
      });
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Passcode updated')));
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) =>
        InputDecoration(labelText: label, border: const OutlineInputBorder());
    final formatters = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: const Text('Change passcode'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: deco('Current passcode'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _next,
            obscureText: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: deco('New passcode'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: deco('Confirm new passcode'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _busy ? null : _submit, child: const Text('Update')),
      ],
    );
  }
}
