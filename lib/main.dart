import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth/auth_store.dart';
import 'hub_app.dart';
import 'ledger/hub_interceptors.dart';
import 'navigation/hub_navigation.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        hubCurrentUserOverride,
        // Business-profile defaults + fiscal-year posting guard.
        hubInterceptorsOverride,
        // Approval inbox scans every submittable DocType for drafts.
        metadataApprovalInboxSourceOverride,
      ],
      child: const MercantisHubApp(),
    ),
  );
}
