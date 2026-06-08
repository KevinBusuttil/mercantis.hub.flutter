import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Whether the install has been set up — true once a Company exists. Drives the
/// boot gate: when false, onboarding is shown instead of the workspace shell.
/// Invalidate after seeding to re-evaluate.
final companyExistsProvider = FutureProvider<bool>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final companies = await engine.list('Company', userRoles: const {'System Manager'});
  return companies.isNotEmpty;
});
