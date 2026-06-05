import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        // Prototype: feed the approval inbox with mock entries. Swap for
        // [metadataApprovalInboxSourceOverride] once real documents exist.
        mockApprovalInboxSourceOverride,
      ],
      child: const MercantisHubApp(),
    ),
  );
}
