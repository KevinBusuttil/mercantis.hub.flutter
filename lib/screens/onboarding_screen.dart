import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../onboarding/business_preset.dart';
import '../onboarding/hub_seeder.dart';
import '../onboarding/onboarding_providers.dart';
import '../settings/hub_settings.dart';

/// First-run wizard: name the business, pick a currency + a business preset,
/// then seed the chart of accounts, fiscal year, VAT bands, and a wired Company
/// so the app is immediately usable. Shown by the boot gate when no Company
/// exists; on success it invalidates [companyExistsProvider] and the shell loads.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController(text: 'My Business');
  String _currency = 'EUR';
  JurisdictionPreset _jurisdiction = JurisdictionPreset.malta;
  BusinessPreset _preset = BusinessPreset.services;
  bool _seeding = false;
  String? _error;

  static const _currencies = ['EUR', 'USD', 'GBP'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _seeding = true;
      _error = null;
    });
    try {
      final engine = await ref.read(documentEngineProvider.future);
      await HubSeeder(engine).seed(
        businessName: _name.text,
        currencyCode: _currency,
        jurisdiction: _jurisdiction,
      );
      // Make the chosen preset functional: persist it and set the module
      // toggles it implies (workspace visibility follows on this launch).
      final settings = ref.read(hubSettingsProvider);
      await ref
          .read(hubSettingsProvider.notifier)
          .save(engine, settings.applyingPreset(_preset));
      ref.invalidate(companyExistsProvider);
      // The boot gate rebuilds on the invalidated provider and shows the shell.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _seeding = false;
        _error = e is DocumentEngineError ? e.humanMessage : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.hub, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Text('Set up Neuradix Atlas', style: theme.textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'We’ll create your chart of accounts, this year’s fiscal year, '
                'VAT codes, and a company profile so you can start invoicing.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                enabled: !_seeding,
                decoration: const InputDecoration(
                  labelText: 'Business name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _jurisdiction.id,
                decoration: const InputDecoration(
                  labelText: 'Country / Tax region',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final j in JurisdictionPreset.all)
                    DropdownMenuItem(value: j.id, child: Text(j.label)),
                ],
                // Picking a region loads its tax bands and its usual currency.
                onChanged: _seeding
                    ? null
                    : (v) => setState(() {
                          _jurisdiction = JurisdictionPreset.byId(v);
                          _currency = _jurisdiction.currencyCode;
                        }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                // Re-key so the field re-initialises when a region selection
                // changes the currency programmatically.
                key: ValueKey(_currency),
                initialValue: _currency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in _currencies)
                    DropdownMenuItem(value: c, child: Text('$c  ${HubSeeder.currencySymbol(c)}')),
                ],
                onChanged: _seeding ? null : (v) => setState(() => _currency = v ?? 'EUR'),
              ),
              const SizedBox(height: 24),
              Text('Business type', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final p in BusinessPreset.all)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    selected: _preset.id == p.id,
                    leading: Icon(_preset.id == p.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked),
                    title: Text(p.label),
                    subtitle: Text(p.description),
                    onTap: _seeding ? null : () => setState(() => _preset = p),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _seeding ? null : _start,
                icon: _seeding
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.rocket_launch_outlined),
                label: const Text('Get started'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
