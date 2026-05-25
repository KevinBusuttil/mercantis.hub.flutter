import 'package:flutter/material.dart';

/// A top-level Hub navigation entry (e.g. CRM, Selling).
///
/// A module exposes one or more [HubMenuGroup]s, each holding a list of
/// [HubMenuItem]s (DocType lists, reports, dashboards, setup actions).
class HubModule {
  const HubModule({
    required this.id,
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.subtitle,
    this.groups = const [],
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final String? subtitle;
  final List<HubMenuGroup> groups;
}

/// A labelled section of items within a [HubModule].
class HubMenuGroup {
  const HubMenuGroup({this.label, required this.items});

  final String? label;
  final List<HubMenuItem> items;
}

/// A single entry in a [HubMenuGroup].
sealed class HubMenuItem {
  const HubMenuItem();

  String get id;
  String get label;
  IconData get icon;
  String get route;
}

/// Routes to a DocType record workspace (`/list/<docType>`).
class HubDocTypeItem extends HubMenuItem {
  const HubDocTypeItem({
    required this.docType,
    this.label0,
    this.icon0 = Icons.article_outlined,
  });

  final String docType;
  final String? label0;
  final IconData icon0;

  @override
  String get id => 'doctype:$docType';
  @override
  String get label => label0 ?? docType;
  @override
  IconData get icon => icon0;
  @override
  String get route => '/list/$docType';
}

/// Routes to a report view (placeholder — Flutter Hub does not yet render
/// reports, but the menu item is still exposed).
class HubReportItem extends HubMenuItem {
  const HubReportItem({
    required this.reportId,
    required this.label0,
    this.icon0 = Icons.bar_chart_outlined,
  });

  final String reportId;
  final String label0;
  final IconData icon0;

  @override
  String get id => 'report:$reportId';
  @override
  String get label => label0;
  @override
  IconData get icon => icon0;
  @override
  String get route => '/report/$reportId';
}

/// Routes to a dashboard view (placeholder — not yet rendered).
class HubDashboardItem extends HubMenuItem {
  const HubDashboardItem({
    required this.dashboardId,
    required this.label0,
    this.icon0 = Icons.dashboard_outlined,
  });

  final String dashboardId;
  final String label0;
  final IconData icon0;

  @override
  String get id => 'dashboard:$dashboardId';
  @override
  String get label => label0;
  @override
  IconData get icon => icon0;
  @override
  String get route => '/dashboard/$dashboardId';
}
