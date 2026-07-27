import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../../crm/customer_anonymise_service.dart';
import '../../ledger/ledger_values.dart';

/// GDPR erasure action (Clinic Pack B-4): "Anonymise (GDPR erasure)" on a
/// Customer scrubs the identity while posted documents survive with the
/// pseudonymised party reference. Guarded by a typed confirmation — it is
/// deliberately irreversible.
void registerHubPrivacyActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubPrivacyActionsFor);
}

/// Pure and synchronous — exposed for tests. Not offered on records that
/// are already anonymised.
List<DocumentAction> hubPrivacyActionsFor(Document doc, DocType docType) {
  if (docType.id != 'Customer') return const [];
  if (asNonEmpty(doc.payload['anonymised_at']) != null) return const [];
  return const [
    DocumentAction(
      id: 'customer-anonymise',
      label: 'Anonymise (GDPR erasure)',
      icon: Icons.visibility_off_outlined,
      invoke: _anonymise,
    ),
  ];
}

Future<void> _anonymise(
    BuildContext context, WidgetRef ref, Document doc) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Anonymise this customer?'),
      content: Text(
          'This permanently replaces "${doc.payload['customer_name']}" '
          'with a pseudonym, deletes their contacts and addresses, and '
          'scrubs their appointment history. Posted invoices are kept '
          '(statutory retention) but will reference only the pseudonym.\n\n'
          'This cannot be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Anonymise')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final engine = await ref.read(documentEngineProvider.future);
    final result =
        await CustomerAnonymiseService(engine).anonymise(doc.id);
    messenger.showSnackBar(SnackBar(
        content: Text('Anonymised as "${result.pseudonym}": '
            '${result.contactsDeleted} contact(s) and '
            '${result.addressesDeleted} address(es) deleted, '
            '${result.appointmentsScrubbed} appointment(s) scrubbed.')));
  } catch (e) {
    final text = '$e';
    messenger.showSnackBar(SnackBar(
        content: Text(text.startsWith('Bad state: ')
            ? text.substring('Bad state: '.length)
            : text)));
  }
}
