import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/accounting/hub_compliance_actions.dart';

/// HU1 — the compliance command-bar action builder (pure).
void main() {
  const filing = DocType(id: 'Tax Filing', name: 'Tax Filing', fields: []);
  const item = DocType(id: 'Item', name: 'Item', fields: []);

  Document doc(String id, String type) =>
      Document(id: id, docType: type, payload: {});

  test('offers "Prepare return" on a saved Tax Filing', () {
    final actions = hubComplianceActionsFor(doc('TF-1', 'Tax Filing'), filing);
    expect(actions.map((a) => a.id).toList(), ['tax-filing-prepare']);
    expect(actions.single.label, 'Prepare return');
  });

  test('offers nothing on an unsaved filing', () {
    expect(hubComplianceActionsFor(doc('', 'Tax Filing'), filing), isEmpty);
  });

  test('offers nothing on a different doctype', () {
    expect(hubComplianceActionsFor(doc('ITM', 'Item'), item), isEmpty);
  });
}
