import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/action_items/domain/action_item_provider.dart';
import 'package:circle_fitness/features/admin/domain/admin_provider.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/classes/data/models/class_model.dart';
import 'package:circle_fitness/features/classes/domain/class_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:circle_fitness/features/vendor/domain/vendor_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/two_coach_postgrest.dart';

// P0-FL-59f · provider families keyed by a client (or a program, an event, a
// class) and not by who is signed in. RLS decides what each coach may read, so
// the answer belongs to the coach who asked: kept for the next account it is
// one coach's PAR-Q, schedule, attendee emails or meeting link on another's
// screen.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- lib/features`.

const _client = 'cl-1';

void main() {
  late TwoCoachPostgrest server;
  late ProviderContainer c;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoCoachPostgrest();
    await initTwoMemberSupabase(server);
  });

  Future<void> until(bool Function() ok, String what) async {
    for (var i = 0; i < 400 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ok(), isTrue, reason: 'never: $what');
  }

  setUp(() async {
    server.reset();
    setFailureSink((_) {});
    await signInAs(memberA);
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
    ]);
    c.listen(currentUserProvider, (_, __) {});
    await until(() => c.read(currentUserProvider)?.id == memberA, 'A');
    await pumpEventQueue();
  });

  tearDown(() {
    resetFailureSink();
    c.dispose();
  });

  Future<void> becomes(String? uid) async {
    if (uid == null) {
      await signOut();
    } else {
      await signInAs(uid);
    }
    await until(() => c.read(currentUserProvider)?.id == uid, 'signed in $uid');
    await pumpEventQueue();
  }

  Future<void> tokenRefreshed() async {
    final before = c.read(currentUserProvider);
    await refreshSession();
    await until(() => c.read(currentUserProvider) != before, 'a new User');
    expect(c.read(currentUserProvider)?.id, memberA, reason: 'premise');
    await pumpEventQueue();
  }

  /// Watches [provider] until its read settled; how often it was asked as A
  /// (a first realtime tick re-reads some of them).
  Future<int> asked(
      String request, ProviderListenable<AsyncValue<Object?>> provider) async {
    c.listen<AsyncValue<Object?>>(provider, (_, __) {});
    await until(() => !c.read(provider).isLoading, "A's read");
    await pumpEventQueue();
    await until(() => !c.read(provider).isLoading, "A's read");
    expect(server.count('$request:$memberA'), greaterThan(0));
    return server.count('$request:$memberA');
  }

  // name → (provider, the request that asks for it)
  final families = <String, (ProviderListenable<AsyncValue<Object?>>, String)>{
    'the client page (profile, photos, weights, check-ins)': (
      clientDetailProvider(_client),
      'GET user_profiles'
    ),
    'the PAR-Q and medical assessment (the LOGGED read)': (
      clientAssessmentProvider(_client),
      'POST rpc/get_client_assessment'
    ),
    'the paid-plan check': (
      clientHasPaidPlanProvider(_client),
      'GET subscriptions'
    ),
    'the training schedule': (
      clientScheduleProvider(_client),
      'GET client_schedules'
    ),
    'the score': (clientScoreProvider(_client), 'GET user_scores'),
    'the action items': (
      clientActionItemsProvider(_client),
      'GET action_items'
    ),
    'the completion stats': (
      actionCompletionProvider(_client),
      'GET action_items'
    ),
    "a program's workouts": (
      programWorkoutsProvider('prog-1'),
      'GET program_workouts'
    ),
    "an event's attendees": (
      eventRegistrationsProvider('ev-1'),
      'GET event_registrations'
    ),
  };

  for (final e in families.entries) {
    final (provider, request) = e.value;
    group(e.key, () {
      test('coach A -> coach B: asked again, as B', () async {
        final asA = await asked(request, provider);
        await becomes(memberB);
        await until(() => server.count('$request:$memberB') > 0,
            "B's own read (THE defect: A's answer was kept for B)");
        expect(server.count('$request:$memberA'), asA);
      });

      test('coach A -> signed out -> coach B: never served from A', () async {
        await asked(request, provider);
        await becomes(null);
        await becomes(memberB);
        await until(
            () => server.count('$request:$memberB') > 0, "B's own read");
      });

      test('control: the same coach refreshing their token is not asked again',
          () async {
        final asA = await asked(request, provider);
        await tokenRefreshed();
        expect(server.count('$request:$memberA'), asA,
            reason: 'a refreshed token is the same coach (and for the '
                'assessment would log a read nobody made)');
      });

      test('control: the same coach signing out and back in reads their own',
          () async {
        final asA = await asked(request, provider);
        await becomes(null);
        await becomes(memberA);
        await until(
            () => server.count('$request:$memberA') > asA, "A's second read");
      });
    });
  }

  test("A's late assessment does not land on B, before B's own or after it",
      () async {
    server.seed('rpc/get_client_assessment', memberA, [
      {'client_id': _client, 'has_assessment': true, 'risk_level': 'high'}
    ]);
    final holdA =
        server.holds['POST rpc/get_client_assessment:$memberA'] = Completer();
    final holdB =
        server.holds['POST rpc/get_client_assessment:$memberB'] = Completer();
    final p = clientAssessmentProvider(_client);
    c.listen(p, (_, __) {});
    await until(
        () => server.calls.contains('POST rpc/get_client_assessment:$memberA'),
        "A's read sent");
    await becomes(memberB);
    holdA.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(p).hasValue, isFalse, reason: "A's answer landed on B");
    await until(
        () => server.calls.contains('POST rpc/get_client_assessment:$memberB'),
        "B's read sent");
    holdB.complete();
    await until(() => c.read(p) is AsyncData, "B's answer");
    expect(c.read(p).requireValue.status, ClientAssessmentStatus.noRow);
  });

  group('what the client page tells A\'s paid plan from its own by', () {
    setUp(() => server.seed('subscriptions', memberA, [
          {'id': 's-1'}
        ]));

    test("B's failed read is B's failure, not A's yes", () async {
      final p = clientHasPaidPlanProvider(_client);
      c.listen(p, (_, __) {});
      await until(() => c.read(p) is AsyncData, 'A');
      expect(c.read(p).requireValue, isTrue, reason: 'premise');
      server.fails.add('GET subscriptions:$memberB');
      await becomes(memberB);
      await until(() => c.read(p) is AsyncError, 'B failed');
    });

    test('a refresh by the same coach stays AsyncData; an account change is '
        'AsyncLoading, even with an invalidate in that window', () async {
      final p = clientHasPaidPlanProvider(_client);
      c.listen(p, (_, __) {});
      await until(() => c.read(p) is AsyncData, 'A');
      c.invalidate(p);
      expect(c.read(p), isA<AsyncData<bool>>());
      expect(c.read(p).isLoading, isTrue);
      await until(() => !c.read(p).isLoading, 're-read');
      server.holds['GET subscriptions:$memberB'] = Completer();
      await becomes(memberB);
      expect(c.read(p), isA<AsyncLoading<bool>>());
      c.invalidate(p);
      expect(c.read(p), isNot(isA<AsyncData<bool>>()));
    });

    test('an invalidate that lands WITH the account change does not make A\'s '
        'answer an AsyncData for B', () async {
      final p = clientHasPaidPlanProvider(_client);
      c.listen(p, (_, __) {});
      await until(() => c.read(p) is AsyncData, 'A');
      server.holds['GET subscriptions:$memberB'] = Completer();
      c.listen(currentUserProvider, (_, u) {
        if (u?.id == memberB) c.invalidate(p);
      });
      await becomes(memberB);
      expect(c.read(p), isNot(isA<AsyncData<bool>>()));
    });
  });

  FitnessClass opened() => FitnessClass(
        id: 'k-1',
        title: 'Spin',
        description: '',
        category: ClassCategory.values.first,
        status: ClassStatus.upcoming,
        startTime: DateTime(2026, 12, 1, 9),
        durationMinutes: 45,
        capacity: 10,
        bookedCount: 1,
        waitlistCount: 0,
        instructor: ClassInstructor(
            id: 'i', name: 'Coach', role: 'Coach', rating: 5),
        location: 'Online',
        isVirtual: true,
        streamUrl: 'https://meet.example/a-secret',
        isBooked: true,
        isWaitlisted: false,
        tags: const [],
      );

  group('the opened class (its meeting link)', () {
    for (final next in [memberB, null]) {
      test('is dropped when A ${next == null ? 'signs out' : 'becomes B'}',
          () async {
        c.listen(selectedClassProvider, (_, __) {});
        c.read(selectedClassProvider.notifier).state = opened();
        await becomes(next);
        expect(c.read(selectedClassProvider), isNull);
      });
    }

    test('A signs out and B signs in with nothing watching it', () async {
      c.read(selectedClassProvider.notifier).state = opened();
      await becomes(null);
      await becomes(memberB);
      expect(c.read(selectedClassProvider), isNull);
    });

    test('control: a refreshed token keeps it open', () async {
      c.read(selectedClassProvider.notifier).state = opened();
      await tokenRefreshed();
      expect(c.read(selectedClassProvider)?.id, 'k-1');
    });

    Map<String, Object?> row() => {
          'id': 'k-1',
          'title': 'Spin',
          'type': 'hiit',
          'is_online': true,
          'meeting_link': 'https://meet.example/a-secret',
          'scheduled_at': DateTime.now()
              .add(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
        };

    test("A's booked classes are not B's schedule while B's read is out, nor "
        'after it fails', () async {
      for (final who in [memberA, memberB]) {
        server.seed('classes', who, [row()]);
      }
      server.seed('class_bookings', memberA, [
        {'class_id': 'k-1', 'status': 'confirmed'}
      ]);
      c.listen(scheduleClassesProvider, (_, __) {});
      c.listen(liveNowClassesProvider, (_, __) {});
      await until(() => c.read(scheduleClassesProvider).isNotEmpty, 'A');
      expect(c.read(scheduleClassesProvider).single.isBooked, isTrue);
      final hold = server.holds['GET classes:$memberB'] = Completer<void>();
      await becomes(memberB);
      expect(c.read(scheduleClassesProvider), isEmpty,
          reason: "THE defect: A's booked row (and its link) was B's to open");
      server.fails.add('GET classes:$memberB');
      hold.complete();
      await until(() => c.read(liveClassesFromDbProvider) is AsyncError, 'fail');
      expect(c.read(scheduleClassesProvider), isEmpty);
      server.fails.clear();
      c.invalidate(liveClassesFromDbProvider);
      await until(() => c.read(scheduleClassesProvider).isNotEmpty, "B's own");
      expect(c.read(scheduleClassesProvider).single.isBooked, isFalse);
    });

    test('control: the same member keeps theirs through a re-read that fails',
        () async {
      server.seed('classes', memberA, [row()]);
      c.listen(scheduleClassesProvider, (_, __) {});
      await until(() => c.read(scheduleClassesProvider).isNotEmpty, 'A');
      server.fails.add('GET classes:$memberA');
      c.read(refreshClassesProvider.notifier).state++;
      expect(c.read(scheduleClassesProvider), hasLength(1));
      await until(() => c.read(liveClassesFromDbProvider) is AsyncError, 'fail');
      expect(c.read(scheduleClassesProvider), hasLength(1));
    });
  });

  group('the admin search boxes', () {
    for (final (name, box) in [
      ('People', adminUserSearchProvider),
      ('Events', adminEventSearchProvider),
    ]) {
      for (final next in [memberB, null]) {
        test('$name: empty once A ${next == null ? 'signs out' : 'becomes B'}',
            () async {
          c.read(box.notifier).state = 'jane@client.example';
          await becomes(next);
          expect(c.read(box), '');
        });
      }
      test('$name: control: a refreshed token keeps the text', () async {
        c.read(box.notifier).state = 'jane@client.example';
        await tokenRefreshed();
        expect(c.read(box), 'jane@client.example');
      });
    }
  });
}
