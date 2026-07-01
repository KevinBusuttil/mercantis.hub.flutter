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
    sections: [
      HeadingSection(docType.name),
      FieldsSection(keys: fieldKeys),
      for (final t in tableKeys) TableSection(tableKey: t),
    ],
  );
}
