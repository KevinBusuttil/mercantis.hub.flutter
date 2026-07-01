import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/printing/hub_print_formats.dart';
import 'package:mercantis_hub_app/printing/hub_print_actions.dart';

/// HU2 — default print format + the print-preview action gating (pure).
void main() {
  const docType = DocType(
    id: 'Sales Invoice',
    name: 'Sales Invoice',
    fields: [
      FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.data),
      FieldDefinition(
          key: 'grand_total', label: 'Total', type: FieldType.currency),
      FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
      FieldDefinition(key: 'items', label: 'Items', type: FieldType.table,
          tableDocType: 'Sales Invoice Item'),
    ],
  );

  test('default format: heading, scalar fields block, a section per table', () {
    final format = hubDefaultPrintFormat(docType);
    expect(format.docType, 'Sales Invoice');
    expect(format.sections, hasLength(3));

    final heading = format.sections[0] as HeadingSection;
    expect(heading.text, 'Sales Invoice');

    final fields = format.sections[1] as FieldsSection;
    // Scalar fields included; the table field excluded.
    expect(fields.keys, ['customer', 'grand_total', 'notes']);

    final table = format.sections[2] as TableSection;
    expect(table.tableKey, 'items');
  });

  test('print-preview action is offered only on a saved document', () {
    expect(
        hubPrintActionsFor(
                Document(id: 'SI-1', docType: 'Sales Invoice', payload: {}),
                docType)
            .map((a) => a.id)
            .toList(),
        ['print-preview']);
    expect(
        hubPrintActionsFor(
            Document(id: '', docType: 'Sales Invoice', payload: {}), docType),
        isEmpty);
  });
}
