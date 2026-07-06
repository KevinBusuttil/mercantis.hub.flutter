import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/selling/hub_reminder_actions.dart';
import 'package:mercantis_hub_app/modules/selling/payment_reminder.dart';

/// The payment-reminder text and the action's overdue gating.
void main() {
  group('buildPaymentReminder', () {
    test('friendly within 14 days, firm after, with company sign-off', () {
      final friendly = buildPaymentReminder(
        invoiceId: 'SINV-1',
        customerName: 'Acme Ltd',
        outstanding: 1180,
        dueDate: '2026-07-01',
        asOf: '2026-07-06',
        companyName: 'Neuradix',
      );
      expect(friendly, contains('friendly reminder'));
      expect(friendly, contains('SINV-1'));
      expect(friendly, contains('€1180.00'));
      expect(friendly, contains('Neuradix'));

      final firm = buildPaymentReminder(
        invoiceId: 'SINV-1',
        customerName: 'Acme Ltd',
        outstanding: 1180,
        dueDate: '2026-05-01',
        asOf: '2026-07-06',
      );
      expect(firm, contains('66 days overdue'));
      expect(firm, isNot(contains('friendly')));
    });
  });

  group('action gating', () {
    DocType invoiceType() =>
        HubManifest.build().docTypes.firstWhere((d) => d.id == 'Sales Invoice');

    Document invoice(
            {int docStatus = 1, num outstanding = 100, String? due}) =>
        Document(id: 'SINV-1', docType: 'Sales Invoice', docStatus: docStatus, payload: {
          'grand_total': 100,
          'outstanding_amount': outstanding,
          'due_date': due ?? '2020-01-01', // long overdue by default
        });

    test('offered only on overdue submitted invoices', () {
      expect(hubReminderActionsFor(invoice(), invoiceType()).map((a) => a.id),
          ['invoice-payment-reminder']);
      // Paid → nothing.
      expect(hubReminderActionsFor(invoice(outstanding: 0), invoiceType()),
          isEmpty);
      // Not yet due → nothing.
      expect(hubReminderActionsFor(invoice(due: '2999-01-01'), invoiceType()),
          isEmpty);
      // Draft → nothing.
      expect(hubReminderActionsFor(invoice(docStatus: 0), invoiceType()),
          isEmpty);
    });
  });
}
