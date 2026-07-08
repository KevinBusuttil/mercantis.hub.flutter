import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../team/team_account_client.dart';
import '../team/team_session.dart';

/// Atlas Team connection (Team milestone 2): create a company on the Team
/// backend or join one with an invitation, registering this device either
/// way. The stored session's device token is what the sync plane uses; the
/// user token stays available for invitations and admin calls.
class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  final _serverController =
      TextEditingController(text: 'https://team.neuradix.app');
  final _deviceController = TextEditingController(text: 'My device');

  // Create-company form.
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();

  // Join form.
  final _inviteController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _serverController, _deviceController, _companyController,
      _emailController, _nameController, _inviteController,
      _displayNameController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<TeamSession> Function(TeamAccountClient) flow) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client =
          TeamAccountClient(baseUrl: _serverController.text.trim());
      final session = await flow(client);
      await ref.read(teamSessionProvider.notifier).connect(session);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Connected to '
              '${session.companyName.isEmpty ? session.companyId : session.companyName}')));
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _error = e is CloudHttpException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite(TeamSession session) async {
    final emailCtrl = TextEditingController();
    var role = 'sales';
    final sent = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: const Text('Invite a teammate'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(
                    labelText: 'Role', border: OutlineInputBorder()),
                items: [
                  for (final r in const [
                    'admin', 'sales', 'purchasing', 'stock', 'pos',
                    'accountant', 'advisor',
                  ])
                    DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (v) => setDialogState(() => role = v ?? 'sales'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Create invitation')),
          ],
        ),
      ),
    );
    if (sent != true || !mounted) return;
    try {
      final client = TeamAccountClient(baseUrl: session.baseUrl);
      final invitation = await client.createInvitation(
        companyId: session.companyId,
        authToken: session.userToken,
        email: emailCtrl.text.trim(),
        role: role,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Invitation created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Send this token to your teammate — it works once '
                  'and expires in 7 days:'),
              const SizedBox(height: 12),
              SelectableText(invitation.token,
                  style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: invitation.token));
                Navigator.pop(c);
              },
              child: const Text('Copy & close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is CloudHttpException ? e.message : '$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(teamSessionProvider);
    return ResponsiveScaffold(
      title: 'Atlas Team',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      padBody: false,
      body: ListView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        children:
            session == null ? _disconnected() : _connected(session),
      ),
    );
  }

  List<Widget> _connected(TeamSession session) {
    final theme = Theme.of(context);
    return [
      AtlasSectionCard(
        name: 'Connected',
        child: Padding(
          padding: const EdgeInsets.all(MercantisSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  session.companyName.isEmpty
                      ? session.companyId
                      : session.companyName,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Server: ${session.baseUrl}'),
              Text('Company id: ${session.companyId}'),
              Text('This device: ${session.deviceName}'),
            ],
          ),
        ),
      ),
      const SizedBox(height: MercantisSpacing.md),
      FilledButton.icon(
        onPressed: () => _invite(session),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Invite a teammate'),
      ),
      const SizedBox(height: MercantisSpacing.sm),
      OutlinedButton.icon(
        onPressed: () async {
          final sure = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Disconnect from Atlas Team?'),
              content: const Text(
                  'This forgets this device\'s connection and credentials. '
                  'Your local data stays on this device; rejoining later '
                  'needs a new invitation or the owner token.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Disconnect')),
              ],
            ),
          );
          if (sure == true) {
            await ref.read(teamSessionProvider.notifier).disconnect();
          }
        },
        icon: const Icon(Icons.link_off_outlined),
        label: const Text('Disconnect'),
      ),
    ];
  }

  List<Widget> _disconnected() {
    final theme = Theme.of(context);
    return [
      Text(
          'Connect this device to an Atlas Team backend to share company '
          'data with your team. Solo use needs none of this.',
          style: theme.textTheme.bodySmall),
      const SizedBox(height: MercantisSpacing.md),
      AtlasSectionCard(
        name: 'Server & device',
        child: Padding(
          padding: const EdgeInsets.all(MercantisSpacing.md),
          child: Column(
            children: [
              TextField(
                controller: _serverController,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: 'Team server',
                    helperText: 'e.g. https://team.neuradix.app',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: MercantisSpacing.md),
              TextField(
                controller: _deviceController,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: 'Name this device',
                    helperText: 'Shows in the company\'s device list and '
                        'audit trail',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: MercantisSpacing.md),
      AtlasSectionCard(
        name: 'Start a new Team company',
        child: Padding(
          padding: const EdgeInsets.all(MercantisSpacing.md),
          child: Column(
            children: [
              TextField(
                controller: _companyController,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: 'Company name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: MercantisSpacing.md),
              TextField(
                controller: _emailController,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: 'Your email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: MercantisSpacing.md),
              TextField(
                controller: _nameController,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: 'Your name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: MercantisSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run((client) => client.createAndConnect(
                            companyName: _companyController.text.trim(),
                            ownerEmail: _emailController.text.trim(),
                            ownerName: _nameController.text.trim(),
                            deviceName: _deviceController.text.trim(),
                          )),
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Create company & connect'),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: MercantisSpacing.md),
      AtlasSectionCard(
        name: 'Join with an invitation',
        child: Padding(
          padding: const EdgeInsets.all(MercantisSpacing.md),
          child: Column(
            children: [
              TextField(
                controller: _inviteController,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: 'Invitation token',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: MercantisSpacing.md),
              TextField(
                controller: _displayNameController,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: 'Your name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: MercantisSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run((client) => client.joinAndConnect(
                            invitationToken: _inviteController.text.trim(),
                            displayName:
                                _displayNameController.text.trim(),
                            deviceName: _deviceController.text.trim(),
                          )),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Join & connect'),
                ),
              ),
            ],
          ),
        ),
      ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.all(MercantisSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: MercantisSpacing.md),
          child: Text(_error!,
              style: TextStyle(color: theme.colorScheme.error)),
        ),
    ];
  }
}
