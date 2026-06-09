import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';

/// Phase 2 guardrail: the Hub manifest must be internally consistent. Every
/// child-table and link reference has to resolve to a registered DocType, and
/// every submittable document must bind to a real workflow. This is a pure
/// Dart check — no database, no Flutter bindings — so it runs fast in CI.
void main() {
  final manifest = HubManifest.build();
  final byId = {for (final dt in manifest.docTypes) dt.id: dt};
  final workflowIds = {for (final wf in manifest.workflows) wf.id};

  group('DocType registration', () {
    test('no duplicate DocType ids', () {
      final ids = manifest.docTypes.map((d) => d.id).toList();
      expect(ids.length, byId.length, reason: 'duplicate DocType id present');
    });

    test('every table field points at a registered child DocType', () {
      for (final dt in manifest.docTypes) {
        for (final f in dt.fields.where((f) => f.type == FieldType.table)) {
          final target = f.tableDocType;
          expect(target, isNotNull,
              reason: '${dt.id}.${f.key} table has no tableDocType');
          expect(byId.containsKey(target), isTrue,
              reason: '${dt.id}.${f.key} -> "$target" is not registered');
          expect(byId[target]!.isChild, isTrue,
              reason: 'child table "$target" must have isChild: true');
        }
      }
    });

    test('every static link field points at a registered DocType', () {
      for (final dt in manifest.docTypes) {
        for (final f in dt.fields.where((f) => f.type == FieldType.link)) {
          final target = f.linkDocType;
          expect(byId.containsKey(target), isTrue,
              reason: '${dt.id}.${f.key} links to unregistered "$target"');
        }
      }
    });
  });

  group('Workflows', () {
    test('every DocType.workflowId resolves to a registered workflow', () {
      for (final dt in manifest.docTypes.where((d) => d.workflowId != null)) {
        expect(workflowIds.contains(dt.workflowId), isTrue,
            reason: '${dt.id} binds missing workflow "${dt.workflowId}"');
      }
    });

    test('every submittable DocType binds a workflow', () {
      for (final dt in manifest.docTypes.where((d) => d.isSubmittable)) {
        expect(dt.workflowId, isNotNull,
            reason: '${dt.id} is submittable but has no workflowId');
      }
    });

    test('each workflow has exactly one default state', () {
      for (final wf in manifest.workflows) {
        final defaults = wf.states.where((s) => s.isDefault).length;
        expect(defaults, 1,
            reason: '${wf.id} must have exactly one default state, has $defaults');
      }
    });

    test('every transition references states that exist in its workflow', () {
      for (final wf in manifest.workflows) {
        final states = wf.states.map((s) => s.name).toSet();
        for (final t in wf.transitions) {
          expect(states.contains(t.fromState), isTrue,
              reason: '${wf.id} transition "${t.action}" from unknown "${t.fromState}"');
          expect(states.contains(t.toState), isTrue,
              reason: '${wf.id} transition "${t.action}" to unknown "${t.toState}"');
        }
      }
      // Transition ids must be unique across the manifest.
      final allIds = manifest.workflows.expand((w) => w.transitions).map((t) => t.id).toList();
      expect(allIds.toSet().length, allIds.length, reason: 'duplicate transition id');
    });

    test('invoice "Mark as Paid" carries the outstanding-amount guard', () {
      for (final id in ['wf-sales-invoice', 'wf-purchase-invoice']) {
        final wf = manifest.workflows.firstWhere((w) => w.id == id);
        final paid = wf.transitions.where((t) => t.toState == 'Paid');
        expect(paid, isNotEmpty);
        for (final t in paid) {
          expect(t.conditionExpression, 'outstanding_amount <= 0');
        }
      }
    });
  });

  group('Item child tables + Supplier Quotation', () {
    test('Item carries uoms + suppliers child tables', () {
      final item = byId['Item']!;
      for (final key in ['uoms', 'suppliers']) {
        final f = item.fields.firstWhere((f) => f.key == key);
        expect(f.type, FieldType.table, reason: 'Item.$key must be a table');
        expect(byId[f.tableDocType]?.isChild, isTrue,
            reason: 'Item.$key -> ${f.tableDocType} must be a child DocType');
      }
    });

    test('Supplier Quotation is submittable, bound, with a line-item table', () {
      final sq = byId['Supplier Quotation'];
      expect(sq, isNotNull);
      expect(sq!.isSubmittable, isTrue);
      expect(sq.workflowId, 'wf-supplier-quotation');
      expect(workflowIds.contains(sq.workflowId), isTrue);
      final items = sq.fields.firstWhere((f) => f.key == 'items');
      expect(items.tableDocType, 'Supplier Quotation Item');
      expect(byId['Supplier Quotation Item']?.isChild, isTrue);
    });
  });

  group('Ledger subledgers', () {
    test('derived ledgers exist and are append-only, non-submittable', () {
      const ledgers = [
        'GL Entry',
        'Customer Transaction',
        'Supplier Transaction',
        'Settlement',
        'Tax Transaction',
        'Stock Ledger Entry',
      ];
      for (final id in ledgers) {
        final dt = byId[id];
        expect(dt, isNotNull, reason: '$id ledger not registered');
        expect(dt!.isSubmittable, isFalse, reason: '$id must not be submittable');
        expect(dt.syncPolicy.conflictResolution, ConflictResolution.appendOnly,
            reason: '$id must be append-only');
      }
    });
  });
}
