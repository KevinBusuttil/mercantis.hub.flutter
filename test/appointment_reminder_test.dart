import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/selling/hub_reminder_actions.dart';
import 'package:mercantis_hub_app/scheduling/appointment_reminder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// B-3 — visit reminders on Appointments (the payment reminder is the
/// pattern): a neutral copy-ready message, a due list windowed on
/// starts_at, and a sent stamp so nobody is nagged twice.
void main() {
  setUpAll(sqfliteFfiInit);

  test('the reminder text is neutral: service and slot, nothing else', () {
    final text = buildAppointmentReminder(
      customerName: 'Maria Borg',
      subject: 'Consultation',
      startsAt: DateTime(2026, 8, 3, 9, 30),
      location: 'Valletta Clinic',
      companyName: 'Busuttil Medical',
    );
    expect(text, contains('Maria Borg'));
    expect(text, contains('Consultation on Monday 3 August 2026 at 09:30'));
    expect(text, contains('Valletta Clinic'));
    expect(text, contains('Busuttil Medical'));
    // The §6.1 discipline: the message carries only what was passed in —
    // no field for a visit reason exists on the builder at all.
  });

  test('location and company are optional', () {
    final text = buildAppointmentReminder(
      customerName: 'Maria',
      subject: 'Consultation',
      startsAt: DateTime(2026, 8, 3, 14, 0),
    );
    expect(text, contains('at 14:00.'));
    expect(text.trim(), endsWith('See you then!'));
  });

  group('AppointmentReminderService (engine)', () {
    late MercantisDatabase db;
    late DocumentEngine engine;
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
        deviceId: 'front-desk',
        userId: 'reception',
        interceptors: const [],
      );
      await engine.save(
          Document(id: 'DOC', docType: 'Schedulable Resource', payload: {
            'resource_name': 'Doctor',
            'resource_type': 'Person',
          }),
          roles);
    });

    tearDown(() async => db.close());

    Future<Document> appointment(String id, DateTime startsAt,
        {String status = 'Scheduled', String? reminderSentAt}) {
      return engine.save(
          Document(id: id, docType: 'Appointment', payload: {
            'subject': 'Consultation',
            'resource': 'DOC',
            'starts_at': startsAt.toIso8601String(),
            'ends_at':
                startsAt.add(const Duration(minutes: 30)).toIso8601String(),
            'status': status,
            if (reminderSentAt != null) 'reminder_sent_at': reminderSentAt,
          }),
          roles);
    }

    test('dueReminders windows on starts_at and skips sent/closed/past',
        () async {
      final now = DateTime(2026, 8, 1, 8, 0);
      await appointment('APT-SOON', now.add(const Duration(hours: 4)));
      await appointment('APT-TOMORROW', now.add(const Duration(hours: 30)));
      await appointment('APT-FAR', now.add(const Duration(hours: 80)));
      await appointment('APT-PAST', now.subtract(const Duration(hours: 2)));
      await appointment('APT-DONE', now.add(const Duration(hours: 5)),
          status: 'Completed');
      await appointment('APT-CANCELLED', now.add(const Duration(hours: 6)),
          status: 'Cancelled');
      await appointment('APT-SENT', now.add(const Duration(hours: 7)),
          reminderSentAt: now.toIso8601String());

      final service = AppointmentReminderService(engine);
      final due = await service.dueReminders(now);

      // Only the open, unsent, in-window pair — soonest first.
      expect(due.map((a) => a.id), ['APT-SOON', 'APT-TOMORROW']);
    });

    test('markSent stamps the appointment and retires it from the list',
        () async {
      final now = DateTime(2026, 8, 1, 8, 0);
      await appointment('APT-1', now.add(const Duration(hours: 4)));

      final service = AppointmentReminderService(engine);
      expect((await service.dueReminders(now)).map((a) => a.id), ['APT-1']);

      await service.markSent('APT-1', at: now);

      expect(await service.dueReminders(now), isEmpty);
      final apt = (await engine.fetch('Appointment', 'APT-1'))!;
      expect('${apt.payload['reminder_sent_at']}',
          startsWith('2026-08-01T08:00'));
    });

    test('the document action offers only on open, upcoming appointments',
        () async {
      final registry = MetadataRegistry(db.db);
      final docType = (await registry.get('Appointment'))!;
      final future = DateTime.now().add(const Duration(hours: 4));
      final past = DateTime.now().subtract(const Duration(hours: 4));

      Document apt(String status, DateTime startsAt) =>
          Document(id: 'A', docType: 'Appointment', payload: {
            'subject': 'Consultation',
            'status': status,
            'starts_at': startsAt.toIso8601String(),
          });

      expect(
          hubReminderActionsFor(apt('Scheduled', future), docType)
              .map((a) => a.id),
          ['appointment-visit-reminder']);
      expect(
          hubReminderActionsFor(apt('Confirmed', future), docType), hasLength(1));
      expect(hubReminderActionsFor(apt('Completed', future), docType), isEmpty);
      expect(hubReminderActionsFor(apt('No Show', future), docType), isEmpty);
      expect(hubReminderActionsFor(apt('Scheduled', past), docType), isEmpty);
    });
  });
}
