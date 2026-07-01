import 'package:mercantis_core/mercantis_core.dart';

/// One financial statement chosen for the accountant export pack (HU1).
typedef ExportStatement = ({String title, ReportResult result});

/// Builds the accountant export "pack" (HU1 — the Swift `HubAccountantExportView`
/// hand-over): the selected statements concatenated as CSV, each under a
/// `# <Title>` banner and blank-line separated. Pure — reuses each
/// [ReportResult]'s own `toCsv()` so the numbers match what's on screen.
String buildAccountantExport(List<ExportStatement> statements) {
  final buffer = StringBuffer();
  for (var i = 0; i < statements.length; i++) {
    if (i > 0) buffer.writeln();
    buffer.writeln('# ${statements[i].title}');
    buffer.write(statements[i].result.toCsv());
  }
  return buffer.toString();
}
