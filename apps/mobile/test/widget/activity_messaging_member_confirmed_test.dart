import 'dart:async';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/activity/presentation/activity_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/challenges/data/models/challenge_model.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/community/data/models/post_model.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart'
    show conversationsProvider;
import 'package:circle_fitness/features/messaging/presentation/messaging_screen.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-49 · Activity's notification-driven sections and the Messages empty
// state decide from a profile read CONFIRMED for the member signed in now.
//
// Riverpod keeps the previous value through a re-read. At 1b94044:
//  * Activity › Challenges read `currentUserProfileProvider.valueOrNull
//    ?['notif_challenges']`, so while B's read was IN FLIGHT or had FAILED,
//    A's preference decided whether B was asked to "Enable challenge alerts";
//  * Activity › Community hid the whole section on A's `notif_community ==
//    false` (or showed it on A's `true`) for B;
//  * Messages decided the plan pitch ("No coach yet") with
//    `maybeWhen(data: p?['role'] != 'coach')` — no member check: a signed-out
//    app (a null profile) counted as a member and was pitched, and a failed
//    same-member refresh dropped a confirmed member's pitch.
//
// The matrix (as in role_reads_member_confirmed_test): switches in both
// directions (member→coach, coach→member, member A→member B with different
// notif_* values), B's read FAILED / IN FLIGHT / SUCCEEDED, the sign-out
// observed or in the same frame; A's DELAYED answer landing after B signed in;
// sign-out with nobody signing in; a same-member refresh that fails after a
// good read (keeps the confirmed value). For Messages also the coach list
// (`myCoachesProvider`): A's list never decides B's pitch.
//
// HOW TO SEE IT FAIL: `git checkout 1b94044 -- <the site's lib file>`.

enum _P { ok, server, pending }

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    );

final _signedIn = StateProvider<User?>((ref) => _user('user-a'));

/// One member's profile row (the columns these sites read).
class _Row {
  const _Row(this.role, {this.challenges, this.community});
  final String role;
  final bool? challenges;
  final bool? community;
}

/// The profile read, controllable per member.
class _Profile {
  _Profile(_Row a, _Row b) : rows = {'user-a': a, 'user-b': b};
  final Map<String, _Row> rows;
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
        final r = rows[uid]!;
        return <String, dynamic>{
          'id': uid,
          'role': r.role,
          'notif_challenges': r.challenges,
          'notif_community': r.community,
        };
    }
  }
}

/// The active-coach read, controllable per member (follows the signed-in
/// user, as `myCoachesProvider` does).
class _Coaches {
  _Coaches(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b)
      : lists = {'user-a': a, 'user-b': b};
  final Map<String, List<Map<String, dynamic>>> lists;
  final Map<String, _P> modes = {};
  final Map<String, Duration> delays = {};
  final List<String> answered = [];

  Future<List<Map<String, dynamic>>> read(String? uid) async {
    if (uid == null) return const [];
    final delay = delays[uid];
    if (delay != null) await Future<void>.delayed(delay);
    switch (modes[uid] ?? _P.ok) {
      case _P.server:
        throw const PostgrestException(message: 'refused', code: 'XX000');
      case _P.pending:
        return Completer<List<Map<String, dynamic>>>().future;
      case _P.ok:
        answered.add(uid);
        return lists[uid]!;
    }
  }
}

const _coach = <String, dynamic>{'id': 'coach-1', 'first_name': 'Ada'};

// ── what each site must show for a CONFIRMED member (null = unconfirmed) ─────

const _prompt = 'Enable challenge alerts';
const _communityLink = 'Explore'; // the Community section's header link
const _pitch = 'No coach yet';
const _neutral = 'No conversations yet';

void _expectActivity(_Profile p, String? member) {
  final row = member == null ? null : p.rows[member];
  expect(find.text(_prompt),
      row != null && row.challenges != true ? findsOneWidget : findsNothing,
      reason: 'the challenge-alerts prompt follows only a confirmed '
          "preference (${member ?? 'unconfirmed'})");
  expect(find.text(_communityLink),
      row != null && row.community == false ? findsNothing : findsOneWidget,
      reason: 'only a confirmed notif_community == false hides Community '
          "(${member ?? 'unconfirmed'})");
}

void _expectMessaging(_Profile p, _Coaches c, String? member,
    {bool coachesKnown = true}) {
  final pitched = member != null &&
      p.rows[member]!.role != 'coach' &&
      coachesKnown &&
      c.lists[member]!.isEmpty;
  expect(find.text(_pitch), pitched ? findsOneWidget : findsNothing,
      reason: "the plan pitch is only for a confirmed member's own empty "
          "coach list (${member ?? 'unconfirmed'})");
  expect(find.text(_neutral), pitched ? findsNothing : findsOneWidget);
}

void main() {
  late RowCheckingPostgrest server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RowCheckingPostgrest('user-a');
    await initSignedInSupabase(server);
  });

  setUp(() => server.reset());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> pump(WidgetTester tester, Widget screen,
      _Profile p, _Coaches coaches) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 6000);
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
      currentUserProfileProvider.overrideWith((ref) async {
        final u = ref.watch(currentUserProvider);
        if (u == null) return null;
        return p.read(u.id);
      }),
      myCoachesProvider.overrideWith(
          (ref) => coaches.read(ref.watch(currentUserProvider)?.id)),
      conversationsProvider.overrideWith((ref) async => const []),
      liveChallengesProvider.overrideWith((ref) async => const <Challenge>[]),
      liveGroupsProvider.overrideWith((ref) async => const <CommunityGroup>[]),
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
      unreadCountProvider.overrideWith((ref) async => 0),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: screen),
    ));
    await settle(tester);
    return container;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> switchTo(WidgetTester tester, ProviderContainer c, String uid,
      {required bool observeSignOut}) async {
    c.read(_signedIn.notifier).state = null; // A signs out
    if (observeSignOut) await settle(tester);
    c.read(_signedIn.notifier).state = _user(uid); // B signs in
    await settle(tester);
  }

  // ── Activity › Challenges + Community ────────────────────────────────────
  group('Activity', () {
    // A and B always differ on both preferences, so A's value applied to B is
    // visible whichever way it goes.
    final pairs = <String, (_Row, _Row)>{
      'member→coach': (
        const _Row('client', challenges: true, community: false),
        const _Row('coach', challenges: false, community: true),
      ),
      'coach→member': (
        const _Row('coach', challenges: false, community: true),
        const _Row('client', challenges: true, community: false),
      ),
      'member A→member B': (
        const _Row('client', challenges: true, community: false),
        const _Row('client', challenges: null, community: null),
      ),
    };

    for (final observe in [true, false]) {
      final how = observe ? 'sign-out observed' : 'same-frame switch';
      for (final pair in pairs.entries) {
        for (final bMode in _P.values) {
          testWidgets(
              "${pair.key} ($how), B's read ${bMode.name}: never A's "
              'preferences', (tester) async {
            final p = _Profile(pair.value.$1, pair.value.$2)
              ..modes['user-b'] = bMode;
            final c = await pump(tester, const ActivityScreen(), p,
                _Coaches(const [], const []));
            _expectActivity(p, 'user-a'); // precondition: A's own view
            await switchTo(tester, c, 'user-b', observeSignOut: observe);
            if (bMode == _P.server) {
              expect(c.read(currentUserProfileProvider).hasError, isTrue,
                  reason: "precondition: B's read really failed");
            }
            _expectActivity(p, bMode == _P.ok ? 'user-b' : null);
            await unmount(tester);
          });
        }
      }
    }

    for (final pair in pairs.entries) {
      for (final slow in const ['first', 'refresh']) {
        for (final bMode in const [_P.ok, _P.server]) {
          testWidgets(
              "${pair.key}: A's slow $slow read lands after B signed in "
              "(B's read ${bMode.name}) and is never B's", (tester) async {
            const lag = Duration(seconds: 5);
            final p = _Profile(pair.value.$1, pair.value.$2)
              ..modes['user-b'] = bMode;
            if (slow == 'first') p.delays['user-a'] = lag;
            final c = await pump(tester, const ActivityScreen(), p,
                _Coaches(const [], const []));
            if (slow == 'first') {
              _expectActivity(p, null);
            } else {
              _expectActivity(p, 'user-a');
              p.delays['user-a'] = lag;
              c.invalidate(currentUserProfileProvider);
              await settle(tester);
            }
            await switchTo(tester, c, 'user-b', observeSignOut: false);
            final b = bMode == _P.ok ? 'user-b' : null;
            _expectActivity(p, b);
            await tester.pump(lag);
            await settle(tester);
            expect(p.answered.where((u) => u == 'user-a').length,
                slow == 'first' ? 1 : 2,
                reason: "precondition: A's late answer really arrived");
            _expectActivity(p, b);
            await unmount(tester);
          });
        }
      }
    }

    testWidgets("A signs out, nobody signs in: none of A's preferences remain",
        (tester) async {
      final p = _Profile(const _Row('client', challenges: false, community: false),
          const _Row('client'));
      final c = await pump(
          tester, const ActivityScreen(), p, _Coaches(const [], const []));
      _expectActivity(p, 'user-a');
      c.read(_signedIn.notifier).state = null;
      await settle(tester);
      _expectActivity(p, null);
      await unmount(tester);
    });

    for (final row in const [
      _Row('client', challenges: false, community: false),
      _Row('client', challenges: true, community: true),
    ]) {
      testWidgets(
          'a refresh that FAILS after a good read of the SAME member keeps '
          'their preferences (challenges ${row.challenges}, community '
          '${row.community})', (tester) async {
        final p = _Profile(row, const _Row('client'));
        final c = await pump(
            tester, const ActivityScreen(), p, _Coaches(const [], const []));
        _expectActivity(p, 'user-a');
        p.mode = _P.server;
        c.invalidate(currentUserProfileProvider);
        await settle(tester);
        expect(c.read(currentUserProfileProvider).hasError, isTrue,
            reason: 'precondition: the refresh really failed');
        _expectActivity(p, 'user-a');
        await unmount(tester);
      });
    }
  });

  // ── Messages › the empty state ────────────────────────────────────────────
  group('Messages empty state', () {
    // (A's role, A's coaches) → (B's role, B's coaches)
    final pairs = <String, (_Row, List<Map<String, dynamic>>, _Row,
        List<Map<String, dynamic>>)>{
      'member→coach': (const _Row('client'), const [], const _Row('coach'), const []),
      'coach→member': (const _Row('coach'), const [], const _Row('client'), const []),
      'member A (has a coach)→member B (none)':
          (const _Row('client'), const [_coach], const _Row('client'), const []),
      'member A (none)→member B (has a coach)':
          (const _Row('client'), const [], const _Row('client'), const [_coach]),
    };

    for (final observe in [true, false]) {
      final how = observe ? 'sign-out observed' : 'same-frame switch';
      for (final pair in pairs.entries) {
        for (final bMode in _P.values) {
          testWidgets(
              "${pair.key} ($how), B's profile read ${bMode.name}: never "
              "decided from A", (tester) async {
            final v = pair.value;
            final p = _Profile(v.$1, v.$3)..modes['user-b'] = bMode;
            final coaches = _Coaches(v.$2, v.$4);
            final c =
                await pump(tester, const MessagingScreen(), p, coaches);
            _expectMessaging(p, coaches, 'user-a');
            await switchTo(tester, c, 'user-b', observeSignOut: observe);
            _expectMessaging(p, coaches, bMode == _P.ok ? 'user-b' : null);
            await unmount(tester);
          });
        }

        for (final cMode in const [_P.server, _P.pending]) {
          testWidgets(
              "${pair.key} ($how), B's COACH read ${cMode.name}: never A's "
              'coach list', (tester) async {
            final v = pair.value;
            final p = _Profile(v.$1, v.$3);
            final coaches = _Coaches(v.$2, v.$4)..modes['user-b'] = cMode;
            final c =
                await pump(tester, const MessagingScreen(), p, coaches);
            _expectMessaging(p, coaches, 'user-a');
            await switchTo(tester, c, 'user-b', observeSignOut: observe);
            _expectMessaging(p, coaches, 'user-b', coachesKnown: false);
            await unmount(tester);
          });
        }
      }
    }

    for (final pair in pairs.entries) {
      for (final slow in const ['profile', 'coaches']) {
        // A coach's empty state never reads a coach list: nothing to delay.
        if (slow == 'coaches' && pair.value.$1.role == 'coach') continue;
        for (final phase in const ['first', 'refresh']) {
          testWidgets(
              "${pair.key}: A's slow $phase $slow read lands after B signed "
              "in and never decides B's empty state", (tester) async {
            const lag = Duration(seconds: 5);
            final v = pair.value;
            final p = _Profile(v.$1, v.$3);
            final coaches = _Coaches(v.$2, v.$4);
            final delays = slow == 'profile' ? p.delays : coaches.delays;
            if (phase == 'first') delays['user-a'] = lag;
            final c =
                await pump(tester, const MessagingScreen(), p, coaches);
            if (phase == 'first') {
              _expectMessaging(p, coaches, null);
            } else {
              _expectMessaging(p, coaches, 'user-a');
              delays['user-a'] = lag;
              c.invalidate(slow == 'profile'
                  ? currentUserProfileProvider
                  : myCoachesProvider);
              await settle(tester);
            }
            await switchTo(tester, c, 'user-b', observeSignOut: false);
            _expectMessaging(p, coaches, 'user-b');
            await tester.pump(lag);
            await settle(tester);
            final answered = slow == 'profile' ? p.answered : coaches.answered;
            expect(answered.where((u) => u == 'user-a'), isNotEmpty,
                reason: "precondition: A's late answer really arrived");
            _expectMessaging(p, coaches, 'user-b');
            await unmount(tester);
          });
        }
      }
    }

    testWidgets('A signs out, nobody signs in: nobody is pitched a plan',
        (tester) async {
      final p = _Profile(const _Row('client'), const _Row('client'));
      final coaches = _Coaches(const [], const []);
      final c = await pump(tester, const MessagingScreen(), p, coaches);
      _expectMessaging(p, coaches, 'user-a');
      c.read(_signedIn.notifier).state = null;
      await settle(tester);
      _expectMessaging(p, coaches, null);
      await unmount(tester);
    });

    testWidgets(
        'a profile refresh that FAILS after a good read of the SAME member '
        'keeps their confirmed role (the pitch stays)', (tester) async {
      final p = _Profile(const _Row('client'), const _Row('client'));
      final coaches = _Coaches(const [], const []);
      final c = await pump(tester, const MessagingScreen(), p, coaches);
      _expectMessaging(p, coaches, 'user-a');
      p.mode = _P.server;
      c.invalidate(currentUserProfileProvider);
      await settle(tester);
      expect(c.read(currentUserProfileProvider).hasError, isTrue,
          reason: 'precondition: the refresh really failed');
      _expectMessaging(p, coaches, 'user-a');
      await unmount(tester);
    });

    testWidgets(
        'a SAME-member coach refresh that fails is not "no coach" (control)',
        (tester) async {
      final p = _Profile(const _Row('client'), const _Row('client'));
      final coaches = _Coaches(const [_coach], const []);
      final c = await pump(tester, const MessagingScreen(), p, coaches);
      _expectMessaging(p, coaches, 'user-a');
      coaches.modes['user-a'] = _P.server;
      c.invalidate(myCoachesProvider);
      await settle(tester);
      expect(find.text(_pitch), findsNothing);
      expect(find.text(_neutral), findsOneWidget);
      await unmount(tester);
    });
  });
}
