import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'hub_app.dart';
import 'navigation/hub_navigation.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        hubCurrentUserOverride,
        // Prototype: feed the approval inbox with mock entries. Swap for
        // [metadataApprovalInboxSourceOverride] once real documents exist.
        mockApprovalInboxSourceOverride,
      ],
      child: const MercantisHubApp(),
    ),
  );
}
