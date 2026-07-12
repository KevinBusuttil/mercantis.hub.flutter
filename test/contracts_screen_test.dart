import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/screens/contracts_screen.dart';

/// V6: the contracts board shows the certified position and retention
/// per contract with the right action per status.
void main() {
  Document contract(String id, String status,
      {List<ChildRow> valuations = const []}) {
    final doc = Document(
      id: id,
      docType: 'Construction Contract',
      payload: {
        'contract_name': 'Villa shell works',
        'customer': 'EMP-1',
        'status': status,
        'contract_value': 100000,
        'retention_percent': 10,
        'retention_cap_percent': 5,
        'billing_item': 'WORKS',
      },
    );
    doc.children['valuations'] = valuations;
    return doc;
  }

  ChildRow valuation(int no, num pct, num gross, num retained, num net) =>
      ChildRow(
        id: 'v$no', parentId: 'CC-1',
        parentDocType: 'Construction Contract',
        tableName: 'valuations', rowIndex: no - 1,
        payload: {
          'valuation_no': no,
          'valuation_date': '2026-08-31',
          'cumulative_percent': pct,
          'gross_this_time': gross,
          'retention_this_time': retained,
          'net_this_time': net,
          'sales_invoice': 'SINV-$no',
        },
      );

  Future<void> pump(WidgetTester tester, List<Document> contracts) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        contractsProvider.overrideWith((ref) async => contracts),
      ],
      child: const MaterialApp(home: ContractsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('an Active contract shows its position and billing actions',
      (tester) async {
    await pump(tester, [
      contract('CC-1', 'Active', valuations: [
        valuation(1, 45, 45000, 4500, 40500),
      ]),
    ]);
    expect(find.text('Villa shell works · CC-1'), findsOneWidget);
    expect(
        find.text('Active · 45% certified · billed 40500.00 · '
            'retention held 4500.00'),
        findsOneWidget);
    expect(find.text('Certify & bill'), findsOneWidget);
    expect(find.text('Practically complete'), findsOneWidget);
  });

  testWidgets('status drives the action: Draft activates, PC releases',
      (tester) async {
    await pump(tester, [
      contract('CC-2', 'Draft'),
      contract('CC-3', 'Practically Complete', valuations: [
        valuation(1, 100, 100000, 5000, 95000),
      ]),
    ]);
    expect(find.text('Activate'), findsOneWidget);
    expect(find.text('Release retention'), findsOneWidget);
  });
}
