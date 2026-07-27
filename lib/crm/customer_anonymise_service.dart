import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

/// What one erasure run did — surfaced to the operator and asserted in
/// tests.
class AnonymiseResult {
  const AnonymiseResult({
    required this.pseudonym,
    required this.appointmentsScrubbed,
    required this.contactsDeleted,
    required this.addressesDeleted,
  });

  final String pseudonym;
  final int appointmentsScrubbed;
  final int contactsDeleted;
  final int addressesDeleted;
}

/// GDPR erasure with ledger retention (Clinic Pack B-4, spec §6.2).
///
/// Statutory retention (10-year Maltese accounting records) lawfully
/// overrides erasure for POSTED documents — so posted invoices survive
/// untouched, still referencing the party id. What erasure CAN and must
/// remove is the identity behind that id: the Customer master is scrubbed
/// to a pseudonym, dynamically-linked Contacts and Addresses (pure
/// contact data) are deleted, and appointment history loses its free
/// text. The record itself survives as the pseudonymised party reference.
///
/// Refuses while live obligations exist: an outstanding balance (you
/// cannot chase a debt from a party you erased) or an open upcoming
/// appointment (complete or cancel it first). Deliberately manual and
/// irreversible — run it on a verified erasure request.
class CustomerAnonymiseService {
  CustomerAnonymiseService(this.engine,
      {this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  /// The personal fields scrubbed off the Customer master.
  static const scrubbedFields = ['email', 'tax_id', 'website'];

  Future<AnonymiseResult> anonymise(String customerId,
      {DateTime? asOf}) async {
    final customer = await engine.fetch('Customer', customerId);
    if (customer == null) {
      throw StateError('Customer $customerId not found.');
    }
    if (asNonEmpty(customer.payload['anonymised_at']) != null) {
      throw StateError('$customerId is already anonymised.');
    }
    final now = asOf ?? DateTime.now();

    // Guard 1: an outstanding balance. Missing outstanding_amount means
    // "owes in full" (the ledger service maintains it on submit).
    final invoices = await engine.list('Sales Invoice',
        filters: {'customer': customerId}, userRoles: roles);
    for (final inv in invoices) {
      if (inv.docStatus != 1) continue;
      final raw = inv.payload['outstanding_amount'];
      final outstanding = raw == null
          ? asNum(inv.payload['grand_total'])
          : asNum(raw);
      if (outstanding > 0.005) {
        throw StateError(
            'Cannot anonymise $customerId: invoice ${inv.id} has an '
            'outstanding balance. Settle or write it off first.');
      }
    }

    // Guard 2: open upcoming appointments.
    final appointments = await engine.list('Appointment',
        filters: {'customer': customerId}, userRoles: roles);
    for (final apt in appointments) {
      final status = '${apt.payload['status']}';
      final open = status == 'Scheduled' || status == 'Confirmed';
      final starts = DateTime.tryParse('${apt.payload['starts_at']}');
      if (open && starts != null && starts.isAfter(now)) {
        throw StateError(
            'Cannot anonymise $customerId: appointment ${apt.id} is '
            'still booked for ${apt.payload['starts_at']}. Complete or '
            'cancel it first.');
      }
    }

    // Scrub appointment history: the slot survives for the diary, the
    // free text goes.
    var appointmentsScrubbed = 0;
    for (final apt in appointments) {
      var changed = false;
      if ('${apt.payload['subject']}' != 'Appointment') {
        apt.payload['subject'] = 'Appointment';
        changed = true;
      }
      for (final key in ['notes', 'location']) {
        if (asNonEmpty(apt.payload[key]) != null) {
          apt.payload[key] = '';
          changed = true;
        }
      }
      if (changed) {
        await engine.save(apt, roles);
        appointmentsScrubbed++;
      }
    }

    // Delete dynamically-linked Contacts and Addresses — pure contact
    // data with no retention duty of their own.
    var contactsDeleted = 0;
    var addressesDeleted = 0;
    for (final docType in ['Contact', 'Address']) {
      for (final doc in await engine.list(docType, userRoles: roles)) {
        final full = await engine.fetch(docType, doc.id);
        final links = full?.children['links'] ?? const <ChildRow>[];
        final linked = links.any((l) =>
            '${l.payload['link_doctype']}' == 'Customer' &&
            '${l.payload['link_name']}' == customerId);
        if (!linked) continue;
        await engine.delete(docType, doc.id, roles);
        if (docType == 'Contact') {
          contactsDeleted++;
        } else {
          addressesDeleted++;
        }
      }
    }

    // Scrub the master itself. The pseudonym is deterministic from the
    // id so every device converges on the same replacement.
    final pseudonym = 'Anonymised customer ${_token(customerId)}';
    customer.payload['customer_name'] = pseudonym;
    for (final key in scrubbedFields) {
      if (asNonEmpty(customer.payload[key]) != null) {
        customer.payload[key] = '';
      }
    }
    customer.payload['anonymised_at'] = now.toIso8601String();
    await engine.save(customer, roles);

    return AnonymiseResult(
      pseudonym: pseudonym,
      appointmentsScrubbed: appointmentsScrubbed,
      contactsDeleted: contactsDeleted,
      addressesDeleted: addressesDeleted,
    );
  }

  /// Short, stable, platform-independent token — NOT derived from any
  /// personal field, only from the record id.
  static String _token(String id) {
    var h = 0;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h.toRadixString(36).toUpperCase();
  }
}
