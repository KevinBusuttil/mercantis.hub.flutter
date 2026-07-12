import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/selling/selling_module.dart';
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

  group('company letterhead (Phase 1A branding)', () {
    test('builds header from the business profile and skips blanks', () {
      final lh = companyLetterHead({
        'company_name': 'Acme Ltd',
        'address': '1 Main Street, Valletta',
        'phone': '+356 2100 0000',
        'email': 'hello@acme.mt',
        'tax_id': 'MT12345678',
        'website': '',
      });
      expect(lh.id, hubLetterHeadId);
      expect(lh.header, contains('Acme Ltd'));
      expect(lh.header, contains('1 Main Street, Valletta'));
      expect(lh.header, contains('+356 2100 0000 · hello@acme.mt'));
      expect(lh.header, contains('VAT: MT12345678'));
      expect(lh.footer, isNotNull);
    });

    test('a bare profile still yields a usable letterhead', () {
      final lh = companyLetterHead(const {});
      expect(lh.header, 'My Business');
    });

    test('hub default formats carry the letterhead id', () {
      const docType = DocType(id: 'X', name: 'X', module: 'm', fields: []);
      expect(hubDefaultPrintFormat(docType).letterHeadId, hubLetterHeadId);
    });

    test('the official number renders on printed documents (Phase 0.2)',
        () async {
      // The posted doctypes declare official_number, so the default format's
      // fields block includes it — the legal number reaches the PDF.
      final salesInvoice = SellingModule.docTypes()
          .firstWhere((d) => d.id == 'Sales Invoice');
      final format = hubDefaultPrintFormat(salesInvoice);
      final fieldsSection =
          format.sections.whereType<FieldsSection>().single;
      expect(fieldsSection.keys, contains('official_number'));

      final result = await const PlainTextPrintRenderer()
          .render(PrintRenderContext(
        format: format,
        document:
            Document(id: 'SINV-2026-0007', docType: 'Sales Invoice', payload: {
          'customer': 'CUST-1',
          'official_number': 'SINV-00012',
        }),
        letterHead: null,
      ));
      expect(String.fromCharCodes(result.bytes), contains('SINV-00012'));
    });
  });
}
