import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:mercantis_hub_app/setup_library/builtin_packs.dart';
import 'package:mercantis_hub_app/setup_library/setup_pack.dart';
import 'package:mercantis_hub_app/setup_library/setup_pack_applier.dart';
import 'package:mercantis_hub_app/setup_library/setup_rule_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Setup Library foundation: tamper-evident pack bundles, idempotent apply
/// with a recorded diff, and the deterministic (never-AI) rule engine with
/// explainable matches.
void main() {
  group('SetupPack bundles', () {
    test('bundle round-trips and verifies its integrity hash', () {
      final bundle = stockAndCogsPack.toBundleJson();
      final parsed = SetupPack.fromBundleJson(bundle);
      expect(parsed.id, 'stock-and-cogs');
      expect(parsed.version, '1.0.0');
      expect(parsed.masters.length, 4);
      expect(parsed.companyDefaults['default_cogs_account'], 'COGS');
      expect(parsed.moduleToggles['stock'], isTrue);
    });

    test('a tampered bundle is rejected, never half-applied', () {
      final decoded = jsonDecode(bankRulesStarterPack.toBundleJson())
          as Map<String, dynamic>;
      // An attacker redirects the rule's account after signing.
      ((decoded['pack']['rules'] as List).first
          as Map)['set_account'] = 'Owner Drawings';
      expect(
        () => SetupPack.fromBundleJson(jsonEncode(decoded)),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('integrity'))),
      );
    });
  });

  group('SetupPackApplier (engine)', () {
    setUpAll(sqfliteFfiInit);
    late MercantisDatabase db;
    late DocumentEngine engine;
    late SetupPackApplier applier;
    const roles = {'System Manager'};

    setUp(() async {
      db = await MercantisDatabase.open(
          factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final registry = MetadataRegistry(db.db);
      final sync = SyncEngine(database: db.db, registry: registry);
      await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
          .install(HubManifest.build());
      engine = DocumentEngine(
        database: db.db,
        registry: registry,
        metaComposer: MetaComposer(registry, db.db),
        permissionEngine: const PermissionEngine(),
        workflowEngine: WorkflowEngine(db.db),
        expressionEvaluator: ExpressionEvaluator(),
        namingService: NamingService(),
        syncEngine: sync,
        emitter: EventEmitter(),
        deviceId: 'devA',
        userId: 'u',
        interceptors: const [],
      );
      await HubSeeder(engine, roles: roles).seed(
          businessName: 'Acme',
          currencyCode: 'EUR',
          year: DateTime.now().year);
      applier = SetupPackApplier(engine: engine);
    });

    tearDown(() async => db.close());

    test('apply creates what is missing, skips what exists, records a diff',
        () async {
      final result = await applier.apply(bankRulesStarterPack);
      expect(result.alreadyApplied, isFalse);

      // The Bank Charges account was new; the rules were added.
      final account = await engine.fetch('Account', 'Bank Charges');
      expect(account!.payload['root_type'], 'Expense');
      final rules = await engine.list('Setup Rule', userRoles: roles);
      expect(rules.length, 2);
      // Built-in provenance and the source pack are stamped.
      expect(rules.every((r) => r.payload['provenance'] == 'built-in'),
          isTrue);
      expect(rules.first.payload['source_pack'],
          'bank-rules-starter@1.0.0');

      // The recorded diff answers "what did this pack change".
      final application = await engine.fetch(
          'Setup Pack Application', result.applicationId);
      final diff =
          jsonDecode('${application!.payload['diff']}') as List;
      expect(diff.any((c) => c['id'] == 'Bank Charges'), isTrue);
      expect(asNum(application.payload['created_count']),
          result.created);
    });

    test('re-applying the same version is a recorded no-op', () async {
      final first = await applier.apply(bankRulesStarterPack);
      final second = await applier.apply(bankRulesStarterPack);
      expect(second.alreadyApplied, isTrue);
      expect(second.applicationId, first.applicationId);
      expect(second.changes, isEmpty);
      // Nothing duplicated.
      expect((await engine.list('Setup Rule', userRoles: roles)).length, 2);
    });

    test('the clinic pack composes a GP practice onto a seeded book',
        () async {
      await applier.apply(appointmentsPack);
      final result = await applier.apply(clinicPack);

      // The medical exempt band carries its full e-invoice identity.
      final exempt = (await engine.fetch('Tax Code', 'VAT-EX-MED'))!;
      expect(exempt.payload['vat_category'], 'Exempt');
      expect('${exempt.payload['exemption_reason']}',
          contains('Article 132(1)'));

      // Therapeutic services bill exempt; the certificate deliberately
      // carries NO code so the book's default (standard) band applies.
      final consult = (await engine.fetch('Item', 'CONSULT'))!;
      expect(consult.payload['tax_code'], 'VAT-EX-MED');
      expect(consult.payload['item_type'], 'Service');
      expect(consult.payload['item_group'], 'IG-Medical');
      final cert = (await engine.fetch('Item', 'MED-CERT'))!;
      expect(asNonEmpty(cert.payload['tax_code']), isNull);

      // A Doctor diary to book against, and the clinic module shape.
      expect((await engine.fetch('Schedulable Resource', 'Doctor'))!
          .payload['resource_type'], 'Person');
      expect(result.moduleToggles['appointments'], isTrue);
      expect(result.moduleToggles['stock'], isFalse);
      expect(result.moduleToggles['pos'], isFalse);
    });

    test('packs never overwrite existing documents or set defaults', () async {
      // The seeder already created the stock accounts AND the company
      // defaults — the pack must skip all of it.
      final result = await applier.apply(stockAndCogsPack);
      expect(result.changes.where((c) => c.action == 'created'), isEmpty);
      expect(
          result.changes.where((c) => c.action == 'default-set'), isEmpty);
      expect(result.skipped, 4); // the four accounts, untouched
      expect(result.moduleToggles, {'stock': true}); // caller applies these
    });
  });

  group('SetupRuleEngine', () {
    Document rule(String id, Map<String, dynamic> payload) =>
        Document(id: id, docType: 'Setup Rule', payload: {
          'rule_type': 'Bank Categorisation',
          'active': 1,
          'priority': 100,
          ...payload,
        });

    test('deterministic: priority order, id tiebreak, first match wins', () {
      final rules = [
        rule('RULE-b', {
          'rule_name': 'Generic fees',
          'match_contains': 'fee',
          'set_account': 'Bank Charges',
        }),
        rule('RULE-a', {
          'rule_name': 'Card fees',
          'match_contains': 'fee',
          'set_account': 'Payment Fees',
        }),
        rule('RULE-c', {
          'rule_name': 'Priority fees',
          'priority': 5,
          'match_contains': 'fee',
          'set_account': 'Priority Account',
        }),
      ];
      final match = SetupRuleEngine.categoriseBankLine(
          rules: rules, description: 'Monthly FEE', amount: -5);
      expect(match!.account, 'Priority Account'); // priority 5 first
      expect(match.explanation, contains('Priority fees'));

      // Remove the priority rule: the id tiebreak (RULE-a before RULE-b)
      // decides — storage order never does.
      final tie = SetupRuleEngine.categoriseBankLine(
          rules: rules.sublist(0, 2), description: 'fee', amount: -5);
      expect(tie!.account, 'Payment Fees');
    });

    test('all set conditions must hold, and the match explains itself', () {
      final rules = [
        rule('RULE-1', {
          'rule_name': 'Big card fees',
          'match_contains': 'stripe',
          'match_direction': 'Money Out',
          'match_min_amount': 10,
          'set_account': 'Payment Fees',
          'affects_accounting': 1,
        }),
      ];
      // Money in — direction fails.
      expect(
          SetupRuleEngine.categoriseBankLine(
              rules: rules, description: 'STRIPE payout', amount: 50),
          isNull);
      // Too small.
      expect(
          SetupRuleEngine.categoriseBankLine(
              rules: rules, description: 'stripe fee', amount: -2),
          isNull);
      final match = SetupRuleEngine.categoriseBankLine(
          rules: rules, description: 'STRIPE FEE 2026', amount: -12.50);
      expect(match!.account, 'Payment Fees');
      expect(match.affectsAccounting, isTrue);
      expect(match.explanation, contains('description contains "stripe"'));
      expect(match.explanation, contains('money out'));
      expect(match.explanation, contains('amount ≥ 10'));
    });

    test('inactive rules and condition-free rules never match', () {
      expect(
        SetupRuleEngine.categoriseBankLine(rules: [
          rule('RULE-off',
              {'rule_name': 'Off', 'match_contains': 'fee', 'active': 0}),
          rule('RULE-empty', {'rule_name': 'No conditions'}),
        ], description: 'fee', amount: -1),
        isNull,
      );
    });

    test('mapKey: exact case-insensitive key match for SKU mapping', () {
      final rules = [
        Document(id: 'RULE-sku', docType: 'Setup Rule', payload: {
          'rule_name': 'Widget SKU',
          'rule_type': 'SKU Mapping',
          'active': 1,
          'priority': 10,
          'match_key': 'WOO-42',
          'set_item': 'ITEM-A',
        }),
      ];
      final match = SetupRuleEngine.mapKey(
          rules: rules, ruleType: 'SKU Mapping', key: 'woo-42');
      expect(match!.item, 'ITEM-A');
      expect(SetupRuleEngine.mapKey(
              rules: rules, ruleType: 'SKU Mapping', key: 'WOO-43'),
          isNull);
    });
  });
}
