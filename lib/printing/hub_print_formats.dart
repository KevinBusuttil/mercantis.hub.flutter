import 'package:mercantis_core/mercantis_core.dart';

/// Field types that don't belong in a plain fields block (tables get their own
/// section; layout markers render nothing).
const _skipTypes = {
  FieldType.table,
  FieldType.tableMultiSelect,
  FieldType.heading,
  FieldType.sectionBreak,
  FieldType.columnBreak,
};

/// The Hub's default [PrintFormat] for a DocType (HU2 foundation): a heading,
/// one fields block over the scalar fields, then a table section per child
/// table — the same shape the core print button auto-generates, but reusable
/// so the print designer / preview can start from it. Pure.
/// The Hub's letterhead id — registered at boot from the Company profile and
/// applied to both the hub default formats and (via
/// `defaultLetterHeadIdProvider`) the record print button's auto formats.
const hubLetterHeadId = 'company';

/// Builds the company letterhead from the business profile: name, address,
/// contact line and VAT number in the header, a courtesy footer. Pure — pass
/// the Company document's payload.
LetterHead companyLetterHead(Map<String, dynamic> company) {
  String? v(String key) {
    final raw = company[key];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return null;
  }

  final contact = [
    if (v('phone') != null) v('phone'),
    if (v('email') != null) v('email'),
    if (v('website') != null) v('website'),
  ].join(' · ');

  final lines = [
    v('company_name') ?? 'My Business',
    if (v('address') != null) v('address')!,
    if (contact.isNotEmpty) contact,
    if (v('tax_id') != null) 'VAT: ${v('tax_id')}',
  ];

  return LetterHead(
    id: hubLetterHeadId,
    name: 'Company letterhead',
    header: lines.join('\n'),
    footer: 'Thank you for your business.',
  );
}

PrintFormat hubDefaultPrintFormat(DocType docType) {
  final fieldKeys = [
    for (final f in docType.fields)
      if (!_skipTypes.contains(f.type)) f.key,
  ];
  final tableKeys = [
    for (final f in docType.fields)
      if (f.type == FieldType.table) f.key,
  ];
  return PrintFormat(
    id: 'hub-default-${docType.id}',
    name: docType.name,
    docType: docType.id,
    letterHeadId: hubLetterHeadId,
    sections: [
      HeadingSection(docType.name),
      FieldsSection(keys: fieldKeys),
      for (final t in tableKeys) TableSection(tableKey: t),
    ],
  );
}
