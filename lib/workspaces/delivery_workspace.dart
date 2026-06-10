import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const deliveryWorkspace = WorkspaceDescriptor(
  id: 'delivery',
  label: 'Delivery & Routes',
  shortLabel: 'Delivery',
  icon: Icons.local_shipping_outlined,
  selectedIcon: Icons.local_shipping,
  subtitle: 'Plan routes, drive deliveries, capture POD',
  accentColor: MercantisBrandColors.accentDelivery,
  order: 40,
  sections: [
    WorkspaceSection(
      label: 'Today',
      items: [
        CustomWorkspaceItem(
          routeName: 'driver-today',
          label: 'Driver view',
          icon: Icons.directions_car_outlined,
          description: 'Stops, navigation and POD',
        ),
      ],
    ),
    WorkspaceSection(
      label: 'Planning',
      items: [
        CustomWorkspaceItem(
          routeName: 'route',
          label: 'Open route',
          icon: Icons.route_outlined,
          description: 'Today\'s active route',
        ),
        DocTypeWorkspaceItem(docType: 'Delivery Route',
          icon: Icons.alt_route_outlined),
        DocTypeWorkspaceItem(docType: 'Delivery Note',
          icon: Icons.receipt_long_outlined),
      ],
    ),
    WorkspaceSection(
      label: 'Fleet',
      items: [
        DocTypeWorkspaceItem(docType: 'Driver', icon: Icons.person_pin_circle_outlined),
        DocTypeWorkspaceItem(docType: 'Vehicle', icon: Icons.local_shipping_outlined),
      ],
    ),
    WorkspaceSection(
      label: 'Tracking',
      items: [
        DocTypeWorkspaceItem(docType: 'Delivery Status Event',
          icon: Icons.history_outlined),
      ],
    ),
  ],
  quickActions: [
    QuickAction(id: 'd_new_route', label: 'New Delivery Route',
      icon: Icons.alt_route_outlined, docType: 'Delivery Route'),
    QuickAction(id: 'd_open_route', label: 'Open today\'s route',
      icon: Icons.route_outlined, routeName: '/w/delivery/route'),
    QuickAction(id: 'd_driver', label: 'Driver view',
      icon: Icons.directions_car_outlined,
      routeName: '/w/delivery/driver-today'),
  ],
);
