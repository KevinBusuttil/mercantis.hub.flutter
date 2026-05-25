import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'hub_module.dart';
import 'hub_modules.dart';

/// Renders a [HubModule] workspace: header + quick actions + grouped items.
class ModuleWorkspaceView extends StatelessWidget {
  const ModuleWorkspaceView({super.key, required this.moduleId});

  final String moduleId;

  @override
  Widget build(BuildContext context) {
    final module = HubModules.byId(moduleId);
    if (module == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Unknown module')),
        body: Center(child: Text('No module found for "$moduleId"')),
      );
    }

    final docTypeItems = <HubDocTypeItem>[];
    for (final g in module.groups) {
      for (final item in g.items) {
        if (item is HubDocTypeItem) docTypeItems.add(item);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(module.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _ModuleHeader(module: module),
          if (docTypeItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            _QuickActionsSection(items: docTypeItems),
          ],
          for (final group in module.groups) ...[
            const SizedBox(height: 24),
            _GroupSection(group: group),
          ],
        ],
      ),
    );
  }
}

class _ModuleHeader extends StatelessWidget {
  const _ModuleHeader({required this.module});
  final HubModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            module.icon,
            color: theme.colorScheme.onPrimaryContainer,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(module.label, style: theme.textTheme.headlineSmall),
              if (module.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    module.subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection({required this.items});
  final List<HubDocTypeItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Quick actions',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text('New ${item.label}'),
                onPressed: () =>
                    GoRouter.of(context).go('/form/${item.docType}/new'),
              ),
          ],
        ),
      ],
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.group});
  final HubMenuGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.label != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              group.label!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < group.items.length; i++) ...[
                _MenuItemTile(item: group.items[i]),
                if (i < group.items.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({required this.item});
  final HubMenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled =
        item is HubDocTypeItem; // reports/dashboards are not yet rendered
    return ListTile(
      leading: Icon(item.icon,
          color: enabled
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant),
      title: Text(item.label),
      subtitle: enabled
          ? null
          : Text(
              'Coming soon',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: const Icon(Icons.chevron_right),
      enabled: enabled,
      onTap: enabled ? () => GoRouter.of(context).go(item.route) : null,
    );
  }
}
