/// Builds the payment-reminder message for an overdue invoice (Phase 1A) —
/// friendly on the first nudge, firmer once it is well past due. Pure text so
/// it can be copied into any channel (email, WhatsApp, SMS) until in-app
/// sending lands.
String buildPaymentReminder({
  required String invoiceId,
  required String customerName,
  required num outstanding,
  required String dueDate,
  required String asOf,
  String? companyName,
  String currency = '€',
}) {
  final due = DateTime.tryParse(dueDate);
  final today = DateTime.tryParse(asOf);
  final daysOverdue = (due != null && today != null)
      ? today.difference(due).inDays
      : 0;
  final amount = '$currency${outstanding.toDouble().toStringAsFixed(2)}';
  final from = companyName == null ? '' : '\n\n$companyName';

  if (daysOverdue <= 14) {
    return 'Hi $customerName,\n\n'
        'Just a friendly reminder that invoice $invoiceId for $amount was '
        'due on $dueDate. If you have already paid, please ignore this '
        'message — otherwise we would appreciate payment at your earliest '
        'convenience.\n\n'
        'Thank you!$from';
  }
  return 'Dear $customerName,\n\n'
      'Invoice $invoiceId for $amount was due on $dueDate and is now '
      '$daysOverdue days overdue. Please arrange payment as soon as '
      'possible, or get in touch if something is holding it up.\n\n'
      'Kind regards$from';
}
