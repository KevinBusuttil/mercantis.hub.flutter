import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/selling/customer_statement.dart';
import 'package:mercantis_hub_app/screens/bank_reconcile_screen.dart';
import 'package:mercantis_hub_app/screens/customer_statement_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// UX-BANKREC and phone statements (C2): bank reconciliation and the
/// customer statement on a 360 dp phone, at normal and 200% text, with
/// semantics on. A layout overflow fails these tests on its own (Flutter
/// reports it as an exception), so "no exception" is part of every case.
///
/// What this does not prove: how the screens feel on a physical phone, or
/// what TalkBack/VoiceOver actually read aloud. Those stay manual rows in
/// docs/release/ACCESSIBILITY_ACCEPTANCE.md.
void main() {
  setUpAll(sqfliteFfiInit);

  const phone = Size(360, 740);
  const desktop = Size(1280, 800);
  const roles = {'System Manager'};

  Future<void> setScreen(WidgetTester tester, Size size, double text) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// Lets real (isolate-backed) database work finish between frames.
  Future<void> settle(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 100 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(until, findsWidgets);
  }

  group('bank reconciliation', () {
    late MercantisDatabase db;
    late DocumentEngine engine;

    Future<void> openBooks(WidgetTester tester) async {
      await tester.runAsync(() async {
        db = await MercantisDatabase.open(
            factory: databaseFactoryFfi, path: inMemoryDatabasePath);
        final registry = MetadataRegistry(db.db);
        final sync = SyncEngine(database: db.db, registry: registry);
        await AppInstaller(
                database: db.db, registry: registry, syncEngine: sync)
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
        await engine.save(
            Document(id: 'Bank', docType: 'Account', payload: {
              'account_name': 'Bank',
              'root_type': 'Asset',
              'account_type': 'Bank',
            }),
            roles);
        await engine.save(
            Document(id: 'BA1', docType: 'Bank Account', payload: {
              'account_name': 'Business current account',
              'gl_account': 'Bank',
            }),
            roles);
        for (final (id, dep, wd, desc) in const [
          ('L1', 0, 42.50, 'CARD PAYMENT TO A VERY LONG MERCHANT NAME LTD'),
          ('L2', 1200, 0, 'Transfer from customer for invoice 2026-0007'),
        ]) {
          await engine.save(
              Document(id: id, docType: 'Bank Statement Line', payload: {
                'bank_account': 'BA1',
                'posting_date': '2026-10-01',
                'deposit': dep,
                'withdrawal': wd,
                'amount': dep - wd,
                'description': desc,
                'status': 'Unreconciled',
              }),
              roles);
        }
      });
      addTearDown(() => tester.runAsync(() => db.close()));
    }

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [documentEngineProvider.overrideWith((ref) async => engine)],
        child: MaterialApp(
          theme: MercantisTheme.light(),
          home: const BankReconcileScreen(),
        ),
      ));
      await settle(tester, find.text('Bank account'));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Business current account').last);
      await tester.pump();
      await settle(tester, find.text('Book balance'));
    }

    /// The list is lazy: at large text the lines start below the fold.
    Future<void> reveal(WidgetTester tester, Finder f) async {
      await tester.scrollUntilVisible(f, 120,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }

    for (final text in const [1.0, 2.0]) {
      testWidgets('fits a 360 dp phone at ${(text * 100).round()}% text',
          (tester) async {
        final semantics = tester.ensureSemantics();
        await setScreen(tester, phone, text);
        await openBooks(tester);
        await pumpScreen(tester);
        expect(tester.takeException(), isNull);

        // Actions sit below the description on a phone, so the description
        // keeps most of the card width instead of a sliver.
        final title =
            find.text('CARD PAYMENT TO A VERY LONG MERCHANT NAME LTD');
        final createExpense = find.text('Create expense');
        await reveal(tester, createExpense);
        expect(tester.getTopLeft(createExpense).dy,
            greaterThan(tester.getBottomLeft(title).dy));
        expect(tester.getSize(title).width, greaterThan(phone.width * 0.5));

        // Every action keeps a full-size tap target and a screen-reader
        // label; the in/out icons say which way the money went.
        for (final label in const ['Create expense', 'Reconcile']) {
          await reveal(tester, find.text(label).first);
          final button = find.ancestor(
              of: find.text(label).first, matching: find.byType(TextButton));
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48),
              reason: '$label tap target');
        }
        expect(find.bySemanticsLabel(RegExp('Money out')), findsOneWidget);
        await reveal(tester, find.bySemanticsLabel(RegExp('Money in')));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        // The four totals wrap rather than overflow, and each is read as one
        // phrase.
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(RegExp(r'^€0\.00\s+Book balance$')),
            findsOneWidget);
        semantics.dispose();
      });
    }

    testWidgets('keeps actions on the same row on a desktop', (tester) async {
      await setScreen(tester, desktop, 1.0);
      await openBooks(tester);
      await pumpScreen(tester);
      expect(tester.takeException(), isNull);
      final title = find.text('CARD PAYMENT TO A VERY LONG MERCHANT NAME LTD');
      await reveal(tester, find.text('Create expense'));
      final reconcile = find.text('Reconcile').first;
      // Negative check of the breakpoint: on a wide screen the actions are
      // NOT moved below the text.
      expect(tester.getTopLeft(reconcile).dy,
          lessThan(tester.getBottomLeft(title).dy + 24));
      expect(tester.getTopLeft(reconcile).dx,
          greaterThan(tester.getTopRight(title).dx));
    });

    testWidgets('Reconcile still works from the phone layout', (tester) async {
      await setScreen(tester, phone, 2.0);
      await openBooks(tester);
      await pumpScreen(tester);
      await reveal(tester, find.text('Create expense'));
      final reconcile = find.text('Reconcile').first;
      await reveal(tester, reconcile);
      await tester.tap(reconcile);
      await tester.pump();
      List<String> statuses = const [];
      for (var i = 0; i < 100 && !statuses.contains('Reconciled'); i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        statuses = (await tester.runAsync(() async => [
              for (final l
                  in await engine.list('Bank Statement Line', userRoles: roles))
                '${l.payload['status']}',
            ]))!;
      }
      expect(statuses..sort(), ['Reconciled', 'Unreconciled']);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('customer statement', () {
    const statement = CustomerStatement(
      customer: 'CUST-0001',
      from: '2026-01-01',
      to: '2026-10-31',
      openingBalance: 0,
      lines: [
        StatementLine(
            date: '2026-02-03',
            kind: 'Invoice',
            reference: 'Sales Invoice · SINV-.2026.-0001',
            amount: 1234.56,
            balance: 1234.56),
        StatementLine(
            date: '2026-02-20',
            kind: 'Payment',
            reference: 'Payment Entry · PAY-.2026.-0003',
            amount: -1000,
            balance: 234.56),
      ],
    );

    Future<void> pumpStatement(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          customerStatementProvider.overrideWith((ref, req) async => statement),
        ],
        child: MaterialApp(
          theme: MercantisTheme.light(),
          home: const CustomerStatementScreen(customerId: 'CUST-0001'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    for (final text in const [1.0, 2.0]) {
      testWidgets('fits a 360 dp phone at ${(text * 100).round()}% text',
          (tester) async {
        final semantics = tester.ensureSemantics();
        await setScreen(tester, phone, text);
        await pumpStatement(tester);
        expect(tester.takeException(), isNull);

        // Dates stack on a phone.
        expect(
            tester.getTopLeft(find.byType(AtlasDateFieldRow).last).dy,
            greaterThan(
                tester.getTopLeft(find.byType(AtlasDateFieldRow).first).dy));

        // Each line is announced with labelled figures, not bare numbers.
        expect(
            find.bySemanticsLabel(RegExp(
                r'SINV-\.2026\.-0001.*amount €1234\.56, balance €1234\.56')),
            findsOneWidget);
        expect(find.text('Balance €234.56'), findsOneWidget);

        // Share for phones, Copy for desktops; both labelled.
        expect(find.byTooltip('Share statement'), findsOneWidget);
        expect(find.byTooltip('Copy as text'), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await tester.scrollUntilVisible(find.text('Closing balance'), 100);
        expect(find.text('€234.56'), findsOneWidget);
        semantics.dispose();
      });
    }

    testWidgets('keeps the dates side by side on a desktop', (tester) async {
      await setScreen(tester, desktop, 1.0);
      await pumpStatement(tester);
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.byType(AtlasDateFieldRow).last).dy,
          tester.getTopLeft(find.byType(AtlasDateFieldRow).first).dy);
    });
  });
}
