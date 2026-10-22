import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'auth/auth_store.dart';
import 'backup/app_restart.dart';
import 'hub_app.dart';
import 'ledger/hub_interceptors.dart';
import 'navigation/hub_navigation.dart';
import 'navigation/hub_shell.dart';
import 'printing/hub_print_formats.dart';
import 'team/team_posting_service.dart';

void main() {
  runApp(
    // A restore restarts everything below this from boot (see HubBackup).
    AtlasRestartScope(builder: (_) => ProviderScope(
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
        // Business profile, optional features and Owner/Accountant view drive
        // the shell: live navigation, the phone bar, deep-link gating and
        // business language.
        ...hubShellOverrides,
      ],
      child: const MercantisHubApp(),
    )),
  );
}
