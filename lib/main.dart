import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'auth/auth_store.dart';
import 'hub_app.dart';
import 'ledger/hub_interceptors.dart';
import 'navigation/hub_navigation.dart';
import 'printing/hub_print_formats.dart';
import 'team/team_posting_service.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        hubCurrentUserOverride,
        // Business-profile defaults + fiscal-year posting guard.
        hubInterceptorsOverride,
        // Approval inbox scans every submittable DocType for drafts.
        metadataApprovalInboxSourceOverride,
        // Record-button PDFs use the company letterhead registered at boot.
        defaultLetterHeadIdProvider.overrideWithValue(hubLetterHeadId),
        // Team mode: official submits/cancels of the five posted doctypes
        // route to the backend posting authority (null while disconnected).
        teamOfficialPostingOverride,
      ],
      child: const MercantisHubApp(),
    ),
  );
}
