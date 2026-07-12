import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/team/team_posting_service.dart';

/// Team posting authority, client half: the command body built from a
/// hydrated draft, and the command-plane client against a mock backend.
void main() {
  ChildRow row(String parentType, String table, int i,
          Map<String, dynamic> payload) =>
      ChildRow(
        id: '', parentId: '', parentDocType: parentType,
        tableName: table, rowIndex: i, payload: payload,
      );

  group('buildSubmitCommand', () {
    test('invoice: header payload + items list + deterministic key', () {
      final doc = Document(id: 'SINV-7', docType: 'Sales Invoice', payload: {
        'customer': 'CUST-1',
        'posting_date': '2026-07-08',
        'update_stock': 1,
        'set_warehouse': 'WH',
      });
      doc.children['items'] = [
        row('Sales Invoice', 'items', 0, {'item': 'ITEM-A', 'qty': 3, 'rate': 12}),
      ];

      final cmd = buildSubmitCommand(doc);
      expect(cmd['doctype'], 'Sales Invoice');
      expect(cmd['document_id'], 'SINV-7');
      expect(cmd['payload'], {
        'customer': 'CUST-1',
        'posting_date': '2026-07-08',
        'update_stock': 1,
        'set_warehouse': 'WH',
      });
      expect(cmd['items'], [
        {'item': 'ITEM-A', 'qty': 3, 'rate': 12},
      ]);
      // Deterministic: a retried command replays, never double-posts.
      expect(cmd['idempotency_key'], 'submit-Sales Invoice-SINV-7');
      expect(buildSubmitCommand(doc)['idempotency_key'],
          cmd['idempotency_key']);
    });

    test('payment: references fold INTO the payload; items stay empty', () {
      final doc = Document(id: 'PAY-1', docType: 'Payment Entry', payload: {
        'payment_type': 'Receive',
        'party': 'CUST-1',
        'paid_amount': 60,
        'posting_date': '2026-07-08',
      });
      doc.children['references'] = [
        row('Payment Entry', 'references', 0, {
          'reference_doctype': 'Sales Invoice',
          'reference_name': 'SINV-7',
          'allocated_amount': 60,
        }),
      ];

      final cmd = buildSubmitCommand(doc);
      expect(cmd['items'], isEmpty);
      expect((cmd['payload'] as Map)['references'], [
        {
          'reference_doctype': 'Sales Invoice',
          'reference_name': 'SINV-7',
          'allocated_amount': 60,
        },
      ]);
    });
  });

  group('TeamPostingClient', () {
    TeamPostingClient client(MockClient mock) => TeamPostingClient(
          baseUrl: 'https://team.neuradix.app/',
          companyId: 'comp-1',
          deviceToken: 'dev-token',
          client: mock,
        );

    test('submit posts the command with device auth and returns the outcome',
        () async {
      http.Request? seen;
      final mock = MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode({
              'document_id': 'SINV-7',
              'number': 'SINV-00001',
              'docstatus': 1,
            }),
            200);
      });

      final outcome = await client(mock).submitDocument({
        'doctype': 'Sales Invoice',
        'document_id': 'SINV-7',
        'payload': {'customer': 'CUST-1'},
        'items': const [],
        'idempotency_key': 'submit-Sales Invoice-SINV-7',
      });

      expect(seen!.url.toString(),
          'https://team.neuradix.app/companies/comp-1/commands/submit-document');
      expect(seen!.headers['Authorization'], 'Bearer dev-token');
      expect(jsonDecode(seen!.body)['idempotency_key'],
          'submit-Sales Invoice-SINV-7');
      expect(outcome['number'], 'SINV-00001');
      expect(outcome['docstatus'], 1);
    });

    test('cancel posts doctype + id with its own deterministic key',
        () async {
      http.Request? seen;
      final mock = MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'docstatus': 2}), 200);
      });
      await client(mock)
          .cancelDocument(docType: 'Sales Invoice', documentId: 'SINV-7');
      expect(seen!.url.path, '/companies/comp-1/commands/cancel-document');
      expect(jsonDecode(seen!.body), {
        'doctype': 'Sales Invoice',
        'document_id': 'SINV-7',
        'idempotency_key': 'cancel-Sales Invoice-SINV-7',
      });
    });

    test('a rejected posting surfaces the backend reason (role, lock, stock)',
        () async {
      final mock = MockClient((_) async => http.Response(
          jsonEncode({
            'error': 'negative stock for ITEM-A@WH (would be -2)'
          }),
          409));
      await expectLater(
        client(mock).submitDocument({
          'doctype': 'Sales Invoice',
          'document_id': 'SINV-8',
          'payload': const {},
          'items': const [],
          'idempotency_key': 'submit-Sales Invoice-SINV-8',
        }),
        throwsA(isA<CloudHttpException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', contains('negative stock'))),
      );
    });
  });

  test('the override claims the backend-posted doctypes — and never POS', () {
    const posting = TeamOfficialPosting();
    expect(teamPostedDocTypes, contains('Delivery Note'));
    for (final dt in teamPostedDocTypes) {
      expect(posting.handles(dt), isTrue, reason: dt);
    }
    expect(posting.handles('Quotation'), isFalse);
    expect(posting.handles('Journal Entry'), isFalse);
    // The deliberate carve-out (gap analysis §8-C5): a till must complete a
    // sale with zero network, so POS Invoice posts locally even in Team
    // mode. Changing this requires the offline-submit-queue design — do not
    // "fix" it by adding POS Invoice to the set.
    expect(posting.handles('POS Invoice'), isFalse);
  });
}
