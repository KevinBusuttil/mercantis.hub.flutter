import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';

/// H1 — the banking master data + reconciliation DocTypes are registered and
/// shaped as the matching/import services will expect.
void main() {
  final byId = {for (final dt in HubManifest.build().docTypes) dt.id: dt};
  DocType doc(String id) => byId[id]!;
  FieldDefinition field(String docId, String key) =>
      doc(docId).fields.firstWhere((f) => f.key == key);

  test('banking DocTypes are registered', () {
    expect(byId.containsKey('Bank Account'), isTrue);
    expect(byId.containsKey('Bank Statement Line'), isTrue);
    expect(byId.containsKey('Bank Reconciliation'), isTrue);
  });

  test('Bank Account maps to a ledger Account', () {
    final gl = field('Bank Account', 'gl_account');
    expect(gl.type, FieldType.link);
    expect(gl.linkDocType, 'Account');
  });

  test('Bank Statement Line carries a signed amount and reconcile status', () {
    expect(field('Bank Statement Line', 'amount').formulaExpression,
        'deposit - withdrawal');
    final status = field('Bank Statement Line', 'status');
    expect(status.type, FieldType.select);
    expect(status.defaultValue, 'Unreconciled');
    expect(field('Bank Statement Line', 'bank_account').linkDocType,
        'Bank Account');
  });

  test('Bank Reconciliation tracks statement vs ledger and the difference', () {
    for (final key in const [
      'statement_closing_balance',
      'ledger_balance',
      'difference',
    ]) {
      expect(field('Bank Reconciliation', key).type, FieldType.currency);
    }
  });
}
