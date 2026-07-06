import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../../ledger/ledger_values.dart';
import '../accounting/invoice_status_service.dart';
import 'payment_reminder.dart';

/// Payment-reminder action (Phase 1A): on an overdue Sales Invoice, "Copy
/// payment reminder" puts a ready-to-send message (invoice, amount, due
/// date, days overdue, company sign-off) on the clipboard.
void registerHubReminderActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubReminderActionsFor);
}

/// Pure and synchronous — exposed for tests.
List<DocumentAction> hubReminderActionsFor(Document doc, DocType docType) {
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
  String? companyName;
  final companyId = doc.company;
  if (companyId != null) {
    companyName = asNonEmpty(
        (await engine.fetch('Company', companyId))?.payload['company_name']);
  } else {
    final companies = await engine.list('Company', userRoles: _systemRoles);
    if (companies.isNotEmpty) {
      companyName = asNonEmpty(companies.first.payload['company_name']);
    }
  }

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
