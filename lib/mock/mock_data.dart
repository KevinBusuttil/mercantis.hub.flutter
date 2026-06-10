import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Remaining seed data for prototype surfaces that are not yet backed by the
/// document engine. The Sales Orders, Customer Account, Low Stock, Delivery
/// Route and Driver Today screens are now wired to real data (see
/// `lib/screens/screen_providers.dart`); only the approval inbox still reads
/// from here until a server-side approvals feed lands.
class MockData {
  const MockData._();

  // ─── Approvals ────────────────────────────────────────────────────────────
  static List<ApprovalEntry> approvals() => [
        ApprovalEntry(
          id: 'SO-0142', docType: 'Sales Order',
          title: 'SO-0142 — ACME Ltd',
          requestedBy: 'A. Borg',
          requestedAt: DateTime.now().subtract(const Duration(minutes: 12)),
          amount: '€1,820',
          subtitle: 'Discount > 10%',
          icon: Icons.shopping_cart_outlined,
          workspaceId: 'sales_fulfilment',
        ),
        ApprovalEntry(
          id: 'PINV-77', docType: 'Purchase Invoice',
          title: 'PINV-77 — Apex Supplies',
          requestedBy: 'M. Said',
          requestedAt: DateTime.now().subtract(const Duration(hours: 1)),
          amount: '€920',
          subtitle: 'Above budget',
          icon: Icons.receipt_long_outlined,
          workspaceId: 'purchasing',
        ),
        ApprovalEntry(
          id: 'STE-31', docType: 'Stock Entry',
          title: 'STE-31 — Warehouse transfer',
          requestedBy: 'J. Vella',
          requestedAt: DateTime.now().subtract(const Duration(hours: 3)),
          subtitle: 'Cross-warehouse',
          icon: Icons.swap_horiz,
          workspaceId: 'inventory',
        ),
      ];
}
