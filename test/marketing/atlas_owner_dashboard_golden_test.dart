import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const _captureKey = Key('atlas-marketing-capture');

const _marketingDashboard = DashboardResult(
  dashboardId: 'marketing-owner-dashboard',
  name: 'Owner dashboard',
  widgets: [
    DashboardWidgetResult(
      id: 'cash_position',
      type: 'sum',
      label: 'Cash position',
      total: 84320,
      display: '€84,320',
    ),
    DashboardWidgetResult(
      id: 'sales_month',
      type: 'sum',
      label: 'Sales this month',
      total: 47850,
      display: '€47,850',
    ),
    DashboardWidgetResult(
      id: 'receivables',
      type: 'sum',
      label: 'Receivables',
      total: 26410,
      display: '€26,410',
    ),
    DashboardWidgetResult(
      id: 'payables',
      type: 'sum',
      label: 'Payables',
      total: 15780,
      display: '€15,780',
    ),
    DashboardWidgetResult(
      id: 'vat_estimate',
      type: 'sum',
      label: 'VAT estimate',
      total: 4280,
      display: '€4,280',
    ),
    DashboardWidgetResult(
      id: 'open_orders',
      type: 'count',
      label: 'Open sales orders',
      count: 14,
    ),
    DashboardWidgetResult(
      id: 'pending_approvals',
      type: 'count',
      label: 'Pending approvals',
      count: 3,
    ),
    DashboardWidgetResult(
      id: 'recent_invoices',
      type: 'list',
      label: 'Recent invoices',
      rows: [
        {
          'invoice': 'INV-2026-0148',
          'customer': 'Harbour Office Supplies',
          'amount': '€3,482.50',
        },
        {
          'invoice': 'INV-2026-0147',
          'customer': 'Valletta Design Studio',
          'amount': '€1,965.00',
        },
        {
          'invoice': 'INV-2026-0146',
          'customer': 'Northshore Services',
          'amount': '€7,240.80',
        },
        {
          'invoice': 'INV-2026-0145',
          'customer': 'Aster Retail',
          'amount': '€895.40',
        },
      ],
    ),
  ],
);

void main() {
  testWidgets('marketing owner dashboard is deterministic', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: MercantisTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: RepaintBoundary(
            key: _captureKey,
            child: SafeArea(
              child: DashboardResultGrid(result: _marketingDashboard),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile('goldens/atlas_owner_dashboard_1440x900.png'),
    );
  });
}
