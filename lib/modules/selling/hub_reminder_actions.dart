import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../../ledger/ledger_values.dart';
import '../../scheduling/appointment_reminder.dart';
import '../accounting/invoice_status_service.dart';
import 'payment_reminder.dart';

/// Reminder actions: on an overdue Sales Invoice, "Copy payment
/// reminder" (Phase 1A); on an upcoming Appointment, "Copy visit
/// reminder" (Clinic Pack B-3) — both put a ready-to-send message on
/// the clipboard, and the visit reminder stamps the appointment sent.
void registerHubReminderActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubReminderActionsFor);
}

/// Pure and synchronous — exposed for tests.
List<DocumentAction> hubReminderActionsFor(Document doc, DocType docType) {
  if (docType.id == 'Appointment') return _appointmentActions(doc);
  if (docType.id != 'Sales Invoice') return const [];
  final today = DateTime.now().toIso8601String().split('T').first;
  final status = InvoiceStatus.compute(
    docStatus: doc.docStatus,
    grandTotal: asNum(doc.payload['grand_total']),
    outstanding: _outstanding(doc),
    dueDate: asNonEmpty(doc.payload['due_date']),
    asOf: today,
    isReturn: isTrue(doc.payload['is_return']),
  );
  if (status != InvoiceStatus.overdue) return const [];
  return const [
    DocumentAction(
      id: 'invoice-payment-reminder',
      label: 'Copy payment reminder',
      icon: Icons.notification_important_outlined,
      invoke: _copyReminder,
    ),
  ];
}

List<DocumentAction> _appointmentActions(Document doc) {
  final status = '${doc.payload['status']}';
  if (status != 'Scheduled' && status != 'Confirmed') return const [];
  final starts = DateTime.tryParse('${doc.payload['starts_at']}');
  if (starts == null || !starts.isAfter(DateTime.now())) return const [];
  return const [
    DocumentAction(
      id: 'appointment-visit-reminder',
      label: 'Copy visit reminder',
      icon: Icons.notifications_active_outlined,
      invoke: copyVisitReminder,
    ),
  ];
}

/// Copies the neutral visit-reminder text and stamps the appointment
/// `reminder_sent_at` — the copy IS the send in the copy-first doctrine,
/// and the stamp keeps the due list from nagging twice.
Future<void> copyVisitReminder(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  final starts = DateTime.tryParse('${doc.payload['starts_at']}');
  if (starts == null) return;
  final customerId = asNonEmpty(doc.payload['customer']);
  final customer =
      customerId == null ? null : await engine.fetch('Customer', customerId);
  final customerName =
      asNonEmpty(customer?.payload['customer_name']) ?? customerId ?? 'there';

  final text = buildAppointmentReminder(
    customerName: customerName,
    subject: '${doc.payload['subject']}',
    startsAt: starts,
    location: asNonEmpty(doc.payload['location']),
    companyName: await _companyNameFor(engine, doc),
  );
  await Clipboard.setData(ClipboardData(text: text));
  await AppointmentReminderService(engine).markSent(doc.id);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Reminder copied and marked sent — paste it into '
            'an email or message')));
  }
}

Future<String?> _companyNameFor(DocumentEngine engine, Document doc) async {
  final companyId = doc.company;
  if (companyId != null) {
    return asNonEmpty(
        (await engine.fetch('Company', companyId))?.payload['company_name']);
  }
  final companies = await engine.list('Company', userRoles: _systemRoles);
  if (companies.isEmpty) return null;
  return asNonEmpty(companies.first.payload['company_name']);
}

num _outstanding(Document doc) {
  final raw = doc.payload['outstanding_amount'];
  if (raw is num) return raw;
  if (raw is String) return num.tryParse(raw.trim()) ?? asNum(doc.payload['grand_total']);
  return asNum(doc.payload['grand_total']);
}

const _systemRoles = {'System Manager'};

Future<void> _copyReminder(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  final today = DateTime.now().toIso8601String().split('T').first;

  // Prefer the customer's display name and the company sign-off when present.
  final customerId = asNonEmpty(doc.payload['customer']) ?? 'customer';
  final customer = await engine.fetch('Customer', customerId);
  final customerName =
      asNonEmpty(customer?.payload['customer_name']) ?? customerId;
  final companyName = await _companyNameFor(engine, doc);

  final text = buildPaymentReminder(
    invoiceId: doc.id,
    customerName: customerName,
    outstanding: _outstanding(doc),
    dueDate: asNonEmpty(doc.payload['due_date']) ?? today,
    asOf: today,
    companyName: companyName,
  );
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Reminder copied — paste it into an email or message')));
  }
}
