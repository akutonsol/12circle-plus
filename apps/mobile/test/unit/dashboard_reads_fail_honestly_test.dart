import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/observability/network_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/dashboard_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/activity_server.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60b (a) · the streak and the two Upcoming reads answered 0 / [] when
// they failed, recorded nowhere; and the glasses of water were reset by an
// edit to the SAME member's sign-up details.
//
// Real auth client, real transitions.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- lib/features/dashboard/domain/
// dashboard_provider.dart`; the controls pass.

void main() {
  late ActivityServer server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = ActivityServer();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  for (final (table, provider, origin) in <(
    String,
    FutureProvider<Object?>,
    String
  )>[
    ('daily_scores', streakProvider, 'streakProvider'),
    ('classes', upcomingClassesProvider, 'upcomingClassesProvider'),
    ('events', upcomingEventsProvider, 'upcomingEventsProvider'),
  ]) {
    // postgrest repeats an unreachable GET for 7 s before it gives up: once.
    for (final network in [false, if (provider == streakProvider) true]) {
      test('$table ${network ? 'unreachable' : 'refused'}: an error (recorded), '
          'not 0 / []', () async {
        (network ? server.offline : server.fails).add(table);
        final c = container();
        c.listen(provider, (_, __) {});
        await settle();
        for (var i = 0; i < 200 && c.read(provider).isLoading; i++) {
          await settle();
        }
        final read = c.read(provider);
        expect(read.hasError, isTrue, reason: 'THE defect: $read');
        expect(isNetworkFailure(read.error), network);
        // (The ticker's first value reads the streak twice, as before.)
        expect(reported.map((f) => f.origin).toSet(), {origin});
      });
    }

    test('NEGATIVE CONTROL: $table read and empty is still 0 / []', () async {
      final c = container();
      c.listen(provider, (_, __) {});
      await settle();
      final read = c.read(provider);
      expect(read.hasError, isFalse);
      expect(read.requireValue, anyOf(0, isEmpty));
      expect(reported, isEmpty);
    });

    test('POSITIVE CONTROL: $table read again after a failure answers', () async {
      server
        ..days[memberA] = 4
        ..classes.add({'id': 'k1'})
        ..events.add({'id': 'e1'})
        ..fails.add(table);
      final c = container();
      c.listen(provider, (_, __) {});
      await settle();
      server.fails.clear();
      c.invalidate(provider);
      await settle();
      final read = c.read(provider);
      expect(read.hasError, isFalse);
      expect(read.requireValue, anyOf(4, hasLength(1)));
    });
  }

  test('the streak is keyed by uid: a token refresh reads nothing again', () async {
    server.days[memberA] = 2;
    final c = container();
    c.listen(streakProvider, (_, __) {});
    await settle();
    Iterable<String> reads() =>
        server.calls.where((k) => k.contains('daily_scores'));
    final before = reads().length;
    await refreshSession();
    await settle();
    expect(c.read(streakProvider).requireValue, 2);
    expect(reads().toSet(), {'GET daily_scores:$memberA'});
    expect(reads(), hasLength(before),
        reason: 'THE defect: the whole User was the key');
  });

  group('water', () {
    ProviderContainer fiveGlasses() {
      final c = container();
      c.listen(waterIntakeProvider, (_, __) {});
      c.read(waterIntakeProvider.notifier).state = 5;
      return c;
    }

    test("the same member's session event (a new User object) keeps it",
        () async {
      final c = fiveGlasses();
      final before = c.read(currentUserProvider);
      await refreshSession();
      await settle();
      expect(c.read(currentUserProvider), isNot(before),
          reason: 'premise: the same member, as a different User');
      expect(c.read(waterIntakeProvider), 5,
          reason: 'THE defect (A-35): a metadata edit reset it');
    });

    test('CONTROL: A → B starts at 0, and A coming back does too', () async {
      final c = fiveGlasses();
      await signInAs(memberB);
      await settle();
      expect(c.read(waterIntakeProvider), 0);
      await signInAs(memberA);
      await settle();
      expect(c.read(waterIntakeProvider), 0);
    });

    test('CONTROL: signed out, it is gone', () async {
      final c = fiveGlasses();
      await signOut();
      await settle();
      expect(c.read(waterIntakeProvider), 0);
    });
  });
}
