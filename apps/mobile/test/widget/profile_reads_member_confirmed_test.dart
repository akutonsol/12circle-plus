import 'dart:async';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/core/widgets/app_top_nav.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/load_format.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';
import 'package:circle_fitness/shared/widgets/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-45b · the remaining PROFILE reads (name, avatar, unit) use a row read
// for the member signed in NOW (`confirmedProfileRead`).
//
// Riverpod keeps the previous value through a re-read, and these sites read
// `currentUserProfileProvider.valueOrNull`. After member A signed out and
// member B signed in, while B's read was IN FLIGHT or had FAILED (or when A's
// slow answer landed late), B was shown A's first name and avatar (app
// scaffold, top nav, coach dashboard, every "Hi <name>" greeting) — and B's
// loads were drawn in A's unit, and B's typed set correction in the Workout
// Zone was CONVERTED with A's unit before it was stored (security P2: B's own
// row stored off by ~2.2x).
//
// While nothing is confirmed for B, every site does what it already did for a
// member whose profile is unread or has no row: the unit is the app default
// (lb, load_format.dart's documented rule), the name/avatar fall back to THIS
// session's own metadata (none here, so neutral: no name, placeholder avatar).
//
// The matrix is P0-FL-44's (app_shell_role_read_failure_test): switches in
// both directions (coach → client and client → coach, each with the units the
// other way round), B's read FAILED / IN FLIGHT / SUCCEEDED, the sign-out
// observed or in the same frame; A's DELAYED first read or refresh landing
// after B signed in; sign-out with nobody signing in; and a same-member
// refresh that fails after a good read (keeps the value).
//
// HOW TO SEE IT FAIL: `git checkout 2abf37c -- <the site's lib file>` (for
// the two providers, auth_provider.dart / load_format.dart).

enum _P { ok, server, pending }

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    );

const _names = {'user-a': 'Alice', 'user-b': 'Bruno'};
const _avatars = {
  'user-a': 'https://a.example/alice.png',
  'user-b': 'https://b.example/bruno.png',
};

final _signedIn = StateProvider<User?>((ref) => _user('user-a'));

/// One direction of the switch: A's role/unit → B's role/unit.
class _Pair {
  const _Pair(this.aRole, this.aUnit, this.bRole, this.bUnit);
  final String aRole, aUnit, bRole, bUnit;
  String unitOf(String member) => member == 'user-a' ? aUnit : bUnit;
  @override
  String toString() => '$aRole ($aUnit) A → $bRole ($bUnit) B';
}

const _pairs = [
  _Pair('coach', 'metric', 'client', 'imperial'),
  _Pair('client', 'imperial', 'coach', 'metric'),
];

class _Profile {
  _Profile(this.pair);
  final _Pair pair;
  final Map<String, _P> modes = {};
  final Map<String, Duration> delays = {};
  final List<String> answered = [];
  _P mode = _P.ok;

  Future<Map<String, dynamic>?> read(String uid) async {
    final delay = delays[uid];
    if (delay != null) await Future<void>.delayed(delay);
    switch (modes[uid] ?? mode) {
      case _P.server:
        throw const PostgrestException(message: 'refused', code: 'XX000');
      case _P.pending:
        return Completer<Map<String, dynamic>?>().future;
      case _P.ok:
        answered.add(uid);
        return <String, dynamic>{
          'id': uid,
          'role': uid == 'user-a' ? pair.aRole : pair.bRole,
          'first_name': _names[uid],
          'last_name': 'Smith',
          'avatar_url': _avatars[uid],
          'unit_preference': pair.unitOf(uid),
        };
    }
  }
}

/// What a site must show for [member] (`null` = nothing confirmed).
typedef _Expect = void Function(String? member, _Pair pair);

class _Site {
  const _Site(this.name, this.build, this.expectFor,
      {this.overrides = const [], this.enter});
  final String name;
  final Widget Function() build;
  final _Expect expectFor;
  final List<Override> overrides;
  final Future<void> Function(WidgetTester tester)? enter;
}

/// The unit a member's loads are shown and entered in; unconfirmed → lb.
String _unit(String? member, _Pair pair) =>
    member != null && pair.unitOf(member) == 'metric' ? 'kg' : 'lb';

Finder _avatar(String url) => find.byWidgetPredicate(
    (w) => w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == url,
    description: 'avatar $url');

/// Only [member]'s name (or nobody's) on screen.
void _onlyNameOf(String? member) {
  for (final e in _names.entries) {
    expect(find.textContaining(e.value),
        e.key == member ? findsWidgets : findsNothing,
        reason: "${e.value} is ${e.key}'s name");
  }
}

/// Only [member]'s avatar (or the placeholder) on screen.
void _onlyAvatarOf(String? member) {
  for (final e in _avatars.entries) {
    expect(_avatar(e.value), e.key == member ? findsWidgets : findsNothing,
        reason: "${e.key}'s avatar");
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final _sites = <_Site>[
  _Site('memberPrefersMetricProvider (loads on Train, History, Progress)',
      () => Consumer(
          builder: (_, ref, __) =>
              Text('unit=${ref.watch(memberPrefersMetricProvider) ? 'kg' : 'lb'}')),
      (member, pair) {
    expect(find.text('unit=${_unit(member, pair)}'), findsOneWidget,
        reason: "the unit is the signed-in member's, else the default");
  }),
  _Site('currentFirstNameProvider (greetings)',
      () => Consumer(
          builder: (_, ref, __) =>
              Text('first=${ref.watch(currentFirstNameProvider)}')),
      (member, _) {
    expect(find.text('first=${member == null ? '' : _names[member]}'),
        findsOneWidget,
        reason: "the signed-in member's name, else this session's own (none)");
  }),
  _Site('AppScaffold header',
      () => const AppScaffold(body: SizedBox.shrink()),
      (member, _) {
    _onlyNameOf(member);
    _onlyAvatarOf(member);
  }),
  _Site('AppTopNavRow',
      () => const Scaffold(body: AppTopNavRow()),
      (member, _) {
    _onlyNameOf(member);
    _onlyAvatarOf(member);
  }),
  _Site('Coach dashboard header avatar', () => const CoachDashboardScreen(),
      (member, _) {
    _onlyAvatarOf(member);
  }, overrides: [
    coachClientsProvider.overrideWith((ref) async => const []),
    clientCheckinsProvider.overrideWith((ref) async => const []),
    clientWorkoutLogsProvider.overrideWith((ref) async => const []),
    coachNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
    currentUserDisplayNameProvider.overrideWithValue('Coach'),
    pendingRequestsProvider.overrideWith((ref) async => const []),
    sentInvitesProvider.overrideWith((ref) async => const []),
    coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
    coachLeaderboardProvider.overrideWith((ref) async => const []),
    coachTriageSignalsProvider.overrideWith((ref) async => const []),
  ]),
  _Site('Workout Zone (set entry/correction unit)',
      () => const ActiveWorkoutScreen(),
      (member, pair) {
    final u = _unit(member, pair).toUpperCase();
    final other = u == 'KG' ? 'LB' : 'KG';
    expect(find.text('WEIGHT ($u)'), findsWidgets,
        reason: 'sets are entered — and corrections converted — in this unit');
    expect(find.text('WEIGHT ($other)'), findsNothing);
  }, overrides: [
    selectedWorkoutProvider
        .overrideWith((ref) => WorkoutService().getSampleWorkouts().first),
  ], enter: (tester) async {
    // Signed in, the Zone opens with its warm-up question.
    final warm = find.textContaining('Warmed Up');
    if (warm.evaluate().isNotEmpty) {
      await tester.tap(warm.first);
      await _settle(tester);
    }
  }),
];

void main() {
  late RowCheckingPostgrest server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RowCheckingPostgrest('user-a');
    await initSignedInSupabase(server);
  });

  setUp(() => server.reset());

  Future<ProviderContainer> pump(
      WidgetTester tester, _Site site, _Profile p) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 3000);
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
      currentUserProfileProvider.overrideWith((ref) async {
        final u = ref.watch(currentUserProvider);
        if (u == null) return null;
        return p.read(u.id);
      }),
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
      unreadCountProvider.overrideWith((ref) async => 0),
      ...site.overrides,
    ]);
    addTearDown(container.dispose);
    // Kept listened whatever the site does (the old Workout Zone only
    // `ref.read` it), so a refresh really runs and its failure is observed.
    container.listen(currentUserProfileProvider, (_, __) {});
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => site.build()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await _settle(tester);
    await site.enter?.call(tester);
    return container;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> switchTo(WidgetTester tester, ProviderContainer c, String uid,
      {required bool observeSignOut}) async {
    c.read(_signedIn.notifier).state = null; // A signs out
    if (observeSignOut) await _settle(tester);
    c.read(_signedIn.notifier).state = _user(uid); // B signs in
    await _settle(tester);
  }

  test('confirmedProfileRead: only a row read for the signed-in member', () {
    final a = <String, dynamic>{'id': 'user-a', 'first_name': 'Alice'};
    final ua = _user('user-a'), ub = _user('user-b');
    expect(confirmedProfileRead(AsyncData(a), ua), a);
    expect(confirmedProfileRead(AsyncData(a), ub), isNull, reason: "A's row, B");
    expect(confirmedProfileRead(AsyncData(a), null), isNull, reason: 'signed out');
    expect(confirmedProfileRead(const AsyncData(null), ua), isNull,
        reason: 'no row: nothing confirmed (callers fall back as before)');
    expect(confirmedProfileRead(const AsyncLoading<Map<String, dynamic>?>(), ua),
        isNull);
    // Riverpod's re-read: the previous value carried through loading/error.
    final reloading = const AsyncLoading<Map<String, dynamic>?>()
        .copyWithPrevious(AsyncData(a));
    expect(confirmedProfileRead(reloading, ua), a, reason: 'same member reloading');
    expect(confirmedProfileRead(reloading, ub), isNull, reason: "B's read in flight");
    final failed = AsyncError<Map<String, dynamic>?>('x', StackTrace.empty)
        .copyWithPrevious(AsyncData(a));
    expect(confirmedProfileRead(failed, ua), a,
        reason: 'a same-member refresh that failed keeps the good read');
    expect(confirmedProfileRead(failed, ub), isNull, reason: "B's read failed");
  });

  for (final site in _sites) {
    group(site.name, () {
      for (final observe in [true, false]) {
        final how = observe ? 'sign-out observed' : 'same-frame switch';
        for (final pair in _pairs) {
          for (final bMode in _P.values) {
            testWidgets("$pair ($how), B's read ${bMode.name}: never A's",
                (tester) async {
              final p = _Profile(pair)..modes['user-b'] = bMode;
              final c = await pump(tester, site, p);
              site.expectFor('user-a', pair); // precondition: A's own

              await switchTo(tester, c, 'user-b', observeSignOut: observe);
              if (bMode == _P.server) {
                expect(c.read(currentUserProfileProvider).hasError, isTrue,
                    reason: "precondition: B's read really failed");
              }
              site.expectFor(bMode == _P.ok ? 'user-b' : null, pair);
              await unmount(tester);
            });
          }
        }
      }

      for (final pair in _pairs) {
        for (final slow in const ['first', 'refresh']) {
          for (final bMode in const [_P.ok, _P.server]) {
            testWidgets(
                "$pair: A's slow $slow read lands after B signed in (B's read "
                "${bMode.name}): A's late answer is never B's", (tester) async {
              const lag = Duration(seconds: 5);
              final p = _Profile(pair)..modes['user-b'] = bMode;
              if (slow == 'first') p.delays['user-a'] = lag;
              final c = await pump(tester, site, p);
              if (slow == 'first') {
                site.expectFor(null, pair);
              } else {
                site.expectFor('user-a', pair);
                p.delays['user-a'] = lag;
                c.invalidate(currentUserProfileProvider);
                await _settle(tester);
              }
              await switchTo(tester, c, 'user-b', observeSignOut: false);
              final b = bMode == _P.ok ? 'user-b' : null;
              site.expectFor(b, pair);
              await tester.pump(lag);
              await _settle(tester);
              expect(p.answered.where((u) => u == 'user-a').length,
                  slow == 'first' ? 1 : 2,
                  reason: "precondition: A's late answer really arrived");
              site.expectFor(b, pair);
              await unmount(tester);
            });
          }
        }
      }

      testWidgets("A signs out, nobody signs in: nothing of A's remains",
          (tester) async {
        final pair = _pairs.first;
        final c = await pump(tester, site, _Profile(pair));
        site.expectFor('user-a', pair);
        c.read(_signedIn.notifier).state = null;
        await _settle(tester);
        site.expectFor(null, pair);
        await unmount(tester);
      });

      testWidgets('a refresh that FAILS after a good read of the SAME member '
          "keeps that member's value", (tester) async {
        final pair = _pairs.first;
        final p = _Profile(pair);
        final c = await pump(tester, site, p);
        site.expectFor('user-a', pair);
        p.mode = _P.server;
        c.invalidate(currentUserProfileProvider);
        await _settle(tester);
        expect(c.read(currentUserProfileProvider).hasError, isTrue,
            reason: 'precondition: the refresh really failed');
        site.expectFor('user-a', pair);
        await unmount(tester);
      });
    });
  }
}
