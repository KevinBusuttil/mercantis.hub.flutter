import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/selling/hub_document_lineage.dart';
import 'package:mercantis_hub_app/modules/selling/hub_lineage_actions.dart';

/// HU4 — conversion-lineage inspector (pure logic).
void main() {
  group('upstream', () {
    test('reads a document\'s own back-link fields', () {
      final si = Document(id: 'SI-1', docType: 'Sales Invoice', payload: {
        'sales_order': 'SO-1',
        'delivery_note': 'DN-1',
      });
      final ups = HubDocumentLineage.upstream(si, 'Sales Invoice');
      expect(ups.map((r) => '${r.docType}:${r.id}').toSet(),
          {'Sales Order:SO-1', 'Delivery Note:DN-1'});
    });

    test('surfaces a return_against original', () {
      final ret = Document(id: 'SI-2', docType: 'Sales Invoice', payload: {
        'return_against': 'SI-1',
      });
      final ups = HubDocumentLineage.upstream(ret, 'Sales Invoice');
      expect(ups.single.relation, 'Return against');
      expect(ups.single.id, 'SI-1');
    });

    test('a blank back-link yields nothing', () {
      final so = Document(id: 'SO-9', docType: 'Sales Order', payload: {
        'quotation': '',
      });
      expect(HubDocumentLineage.upstream(so, 'Sales Order'), isEmpty);
    });

    test('participation gate', () {
      expect(HubDocumentLineage.participates('Sales Order'), isTrue);
      expect(HubDocumentLineage.participates('Quotation'), isTrue);
      expect(HubDocumentLineage.participates('Purchase Invoice'), isTrue);
      expect(HubDocumentLineage.participates('Item'), isFalse);
    });
  });

  group('action builder', () {
    const so = DocType(id: 'Sales Order', name: 'Sales Order', fields: []);
    const item = DocType(id: 'Item', name: 'Item', fields: []);

    test('offers "Related" on a saved participating doc', () {
      final actions = hubLineageActionsFor(
          Document(id: 'SO-1', docType: 'Sales Order', payload: {}), so);
      expect(actions.map((a) => a.id).toList(), ['related-docs']);
    });

    test('nothing on an unsaved doc or a non-participating type', () {
      expect(
          hubLineageActionsFor(
              Document(id: '', docType: 'Sales Order', payload: {}), so),
          isEmpty);
      expect(
          hubLineageActionsFor(
              Document(id: 'ITM', docType: 'Item', payload: {}), item),
          isEmpty);
    });
  });
}
