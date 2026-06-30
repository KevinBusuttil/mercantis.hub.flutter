import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';

/// H2 — the compliance (tax filing) DocTypes are registered and shaped for the
/// return builder.
void main() {
  final byId = {for (final dt in HubManifest.build().docTypes) dt.id: dt};
  DocType doc(String id) => byId[id]!;
  FieldDefinition field(String docId, String key) =>
      doc(docId).fields.firstWhere((f) => f.key == key);

  test('Tax Filing + Tax Filing Box are registered', () {
    expect(byId.containsKey('Tax Filing'), isTrue);
    expect(byId.containsKey('Tax Filing Box'), isTrue);
    expect(doc('Tax Filing Box').isChild, isTrue);
  });

  test('Tax Filing carries the period, status, and headline totals', () {
    expect(field('Tax Filing', 'from_date').required, isTrue);
    expect(field('Tax Filing', 'to_date').required, isTrue);
    final status = field('Tax Filing', 'status');
    expect(status.defaultValue, 'Draft');
    expect(status.options, contains('Filed'));
    for (final key in const ['output_tax', 'input_tax', 'net_tax']) {
      expect(field('Tax Filing', key).type, FieldType.currency);
    }
  });

  test('the boxes table points at the registered child DocType', () {
    final boxes = field('Tax Filing', 'boxes');
    expect(boxes.type, FieldType.table);
    expect(boxes.tableDocType, 'Tax Filing Box');
  });
}
