import 'dart:async';

import 'package:circle_fitness/features/admin/presentation/observability_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/presentation/coach_copilot_screen.dart';
import 'package:circle_fitness/features/coach/presentation/continuous_coaching_screen.dart';
import 'package:circle_fitness/features/coach/presentation/dynamic_program_builder_screen.dart';
import 'package:circle_fitness/features/coach/presentation/weekly_review_screen.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart'
    show coachClientsProvider;
import 'package:circle_fitness/features/exercise_database/presentation/content_review_queue_screen.dart';
import 'package:circle_fitness/features/exercise_database/presentation/exercise_content_center_screen.dart';
import 'package:circle_fitness/features/exercise_database/presentation/intelligence_review_screen.dart';
import 'package:circle_fitness/features/exercise_database/presentation/mie_debugger_screen.dart';
import 'package:circle_fitness/features/profile/presentation/widgets/profile_load_failed_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-45a · role-gated screens take the role only from a read CONFIRMED for
// the member signed in now.
//
// P0-FL-40 gave nine role-only screens a private `_unreadRoleGate` and then
// read `profileAsync.value?['role']` with no member check. Riverpod keeps the
// previous value through a re-read, so after a sign-out/sign-in the PREVIOUS
// member's role opened (or closed) the screen:
//  * same-frame switch (sign-out and sign-in before one rebuild): B's read
//    starts from A's ROW — A's coach/admin role opened the tool for client B;
//  * observed sign-out: B's read starts from a `null` value — "… only." was
//    shown to a coach whose read was still in flight or had failed;
//  * and a same-member refresh that failed after a good read hid the screen
//    behind the failure notice although the role was known.
// The screens now share `roleGate` (lib/core/widgets/role_gate.dart), which
// uses P0-FL-44's `confirmedRoleRead`.
//
// Six screens also started their role-only service read in initState, before
// the role was known; it now starts once the gate has let the member in.
//
// HOW TO SEE IT FAIL: `git checkout 185261e -- <the nine lib screens>` (and
// delete lib/core/widgets/role_gate.dart): the switch, refresh and fetch tests
// fail. Removing the member check from `roleGate` alone (use
// `profile.value?['role']` when the profile hasValue) fails the same-frame
// switch tests.

Finder get _loadingAccount => find.bySemanticsLabel('Loading your account');

const _uid = '00000000-0000-4000-8000-0000000f4545';

enum _P { ok, server, pending }

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    );

final _signedIn = StateProvider<User?>((ref) => _user('user-a'));

/// The profile read, per member: role, failure mode, delay.
class _Profile {
  _Profile(String aRole) : roles = {'user-a': aRole};
  final Map<String, String> roles;
  final Map<String, _P> modes = {};
  final Map<String, Duration> delays = {};
  final List<String> answered = [];
  int reads = 0;

  Future<Map<String, dynamic>?> read(String uid) async {
    reads++;
    final delay = delays[uid];
    if (delay != null) await Future<void>.delayed(delay);
    switch (modes[uid] ?? _P.ok) {
      case _P.server:
        throw const PostgrestException(message: 'refused', code: 'XX000');
      case _P.pending:
        return Completer<Map<String, dynamic>?>().future;
      case _P.ok:
        answered.add(uid);
        return <String, dynamic>{'id': uid, 'role': roles[uid]};
    }
  }
}

/// Records every request a screen's service makes (all answered "empty").
class _Recording extends RowCheckingPostgrest {
  _Recording(super.uid);
  final requests = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!request.url.path.startsWith('/auth/')) {
      requests.add('${request.method} ${request.url.path}');
    }
    return super.send(request);
  }
}

class _Gated {
  const _Gated(this.title, this.build, this.only, this.allowed,
      {this.fetchesOnOpen = false});
  final String title;
  final Widget Function() build;
  final String only;

  /// The screen's allowed roles — EXACTLY as before this package.
  final List<String> allowed;

  /// Whether the screen reads its role-only data as it opens.
  final bool fetchesOnOpen;
}

final _gated = <_Gated>[
  _Gated('Coach Copilot', () => const CoachCopilotScreen(), 'Coaches only.',
      ['coach', 'admin']),
  _Gated('Continuous Coaching', () => const ContinuousCoachingScreen(),
      'Coaches only.', ['coach', 'admin'], fetchesOnOpen: true),
  _Gated('Program Builder',
      () => const DynamicProgramBuilderScreen(engineWeekGeneration: false),
      'Coaches only.', ['coach', 'admin']),
  _Gated('Weekly Review', () => const WeeklyReviewScreen(), 'Coaches only.',
      ['coach', 'admin'], fetchesOnOpen: true),
  _Gated('Coaching Observability', () => const ObservabilityScreen(),
      'Admins only.', ['admin'], fetchesOnOpen: true),
  _Gated('Review Queue', () => const ContentReviewQueueScreen(),
      'Admins & content managers only.', ['admin', 'content_manager'],
      fetchesOnOpen: true),
  _Gated('Content Center', () => const ExerciseContentCenterScreen(),
      'Admins & content managers only.', ['admin', 'content_manager'],
      fetchesOnOpen: true),
  _Gated('Knowledge Review', () => const IntelligenceReviewScreen(),
      'Admins & content managers only.', ['admin', 'content_manager'],
      fetchesOnOpen: true),
  _Gated('MIE Debugger', () => const MieDebuggerScreen(),
      'Admins & content managers only.', ['admin', 'content_manager']),
];

void main() {
  late _Recording server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Recording(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server
      ..reset()
      ..requests.clear();
  });

  Future<void> settle(WidgetTester tester) async {
    // Spinners animate forever: pump, never settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Future<WidgetRef> pumpScreen(
      WidgetTester tester, _Gated g, _Profile p) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 3000);
    addTearDown(tester.view.reset);
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
        currentUserProfileProvider.overrideWith((ref) async {
          final u = ref.watch(currentUserProvider);
          if (u == null) return null;
          return p.read(u.id);
        }),
        coachClientsProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          captured = ref;
          return g.build();
        }),
      ),
    ));
    await settle(tester);
    return captured;
  }

  Future<void> switchTo(WidgetTester tester, WidgetRef ref, String uid,
      {required bool observeSignOut}) async {
    ref.read(_signedIn.notifier).state = null; // A signs out
    if (observeSignOut) await settle(tester);
    ref.read(_signedIn.notifier).state = _user(uid); // B signs in
    await settle(tester);
  }


  void expectOpen(_Gated g) {
    expect(find.text(g.only), findsNothing, reason: 'a confirmed role is in');
    expect(find.byType(ProfileLoadFailedNotice), findsNothing);
    expect(_loadingAccount, findsNothing);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text(g.title)),
        findsOneWidget);
  }

  void expectDenied(_Gated g) {
    expect(find.text(g.only), findsOneWidget,
        reason: 'a confirmed role without access gets "${g.only}"');
    expect(find.byType(ProfileLoadFailedNotice), findsNothing);
    expect(_loadingAccount, findsNothing);
  }

  void expectFailure(_Gated g) {
    expect(find.byType(ProfileLoadFailedNotice), findsOneWidget,
        reason: 'the new member\'s role is unknown: say so');
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text(g.only), findsNothing,
        reason: 'unknown is not "lacks the role"');
    expect(find.byIcon(Icons.refresh_rounded), findsNothing,
        reason: 'nothing role-only is shown');
  }

  void expectPending(_Gated g) {
    expect(_loadingAccount, findsOneWidget);
    expect(find.byType(ProfileLoadFailedNotice), findsNothing);
    expect(find.text(g.only), findsNothing);
  }

  void expectNotOpen(_Gated g) {
    final shut = find.text(g.only).evaluate().isNotEmpty ||
        find.byType(ProfileLoadFailedNotice).evaluate().isNotEmpty ||
        _loadingAccount.evaluate().isNotEmpty;
    expect(shut, isTrue, reason: 'the tool must not stay open');
  }

  for (final g in _gated) {
    group(g.title, () {
      for (final observe in [true, false]) {
        final how = observe ? 'sign-out observed' : 'same-frame switch';

        // 1 · ALLOWED → CLIENT, for each allowed role.
        for (final role in g.allowed) {
          group('$role A → client B ($how)', () {
            testWidgets("B's read FAILS → failure notice, never A's access",
                (tester) async {
              final p = _Profile(role)
                ..roles['user-b'] = 'client'
                ..modes['user-b'] = _P.server;
              final ref = await pumpScreen(tester, g, p);
              expectOpen(g);
              await switchTo(tester, ref, 'user-b', observeSignOut: observe);
              expect(ref.read(currentUserProfileProvider).hasError, isTrue,
                  reason: "precondition: B's read really failed");
              expectFailure(g);
              await unmount(tester);
            });

            testWidgets("B's read IN FLIGHT → neutral loading, not A's access",
                (tester) async {
              final p = _Profile(role)
                ..roles['user-b'] = 'client'
                ..modes['user-b'] = _P.pending;
              final ref = await pumpScreen(tester, g, p);
              expectOpen(g);
              await switchTo(tester, ref, 'user-b', observeSignOut: observe);
              expectPending(g);
              await unmount(tester);
            });

            testWidgets("B's read SUCCEEDS → \"${g.only}\"", (tester) async {
              final p = _Profile(role)
                ..roles['user-b'] = 'client'
                ..delays['user-b'] = const Duration(seconds: 2);
              final ref = await pumpScreen(tester, g, p);
              expectOpen(g);
              await switchTo(tester, ref, 'user-b', observeSignOut: observe);
              expectPending(g); // still on the wire
              await tester.pump(const Duration(seconds: 2));
              await settle(tester);
              expectDenied(g);
              await unmount(tester);
            });
          });
        }

        // 2 · CLIENT → ALLOWED.
        final bRole = g.allowed.first;
        group('client A → $bRole B ($how)', () {
          testWidgets("B's read FAILS → failure notice, never \"${g.only}\"",
              (tester) async {
            final p = _Profile('client')
              ..roles['user-b'] = bRole
              ..modes['user-b'] = _P.server;
            final ref = await pumpScreen(tester, g, p);
            expectDenied(g);
            await switchTo(tester, ref, 'user-b', observeSignOut: observe);
            expectFailure(g);
            await unmount(tester);
          });

          testWidgets("B's read IN FLIGHT → neutral loading, not \"${g.only}\"",
              (tester) async {
            final p = _Profile('client')
              ..roles['user-b'] = bRole
              ..modes['user-b'] = _P.pending;
            final ref = await pumpScreen(tester, g, p);
            expectDenied(g);
            await switchTo(tester, ref, 'user-b', observeSignOut: observe);
            expectPending(g);
            await unmount(tester);
          });

          testWidgets("B's read SUCCEEDS → the screen", (tester) async {
            final p = _Profile('client')
              ..roles['user-b'] = bRole
              ..delays['user-b'] = const Duration(seconds: 2);
            final ref = await pumpScreen(tester, g, p);
            expectDenied(g);
            await switchTo(tester, ref, 'user-b', observeSignOut: observe);
            expectPending(g);
            await tester.pump(const Duration(seconds: 2));
            await settle(tester);
            expectOpen(g);
            await unmount(tester);
          });
        });

        // 3 · A's DELAYED response lands after B signed in.
        for (final dir in [(bRole, 'client'), ('client', bRole)]) {
          final (aRole, bR) = dir;
          for (final bMode in _P.values) {
            testWidgets(
                "A=$aRole's slow refresh lands after B=$bR signed in ($how), "
                "B's read ${bMode.name} — never B's answer", (tester) async {
              const lag = Duration(seconds: 5);
              final p = _Profile(aRole)
                ..roles['user-b'] = bR
                ..modes['user-b'] = bMode;
              final ref = await pumpScreen(tester, g, p);
              aRole == 'client' ? expectDenied(g) : expectOpen(g);
              p.delays['user-a'] = lag;
              ref.invalidate(currentUserProfileProvider); // A's slow refresh
              await settle(tester);

              await switchTo(tester, ref, 'user-b', observeSignOut: observe);
              void expectB() {
                switch (bMode) {
                  case _P.ok:
                    bR == 'client' ? expectDenied(g) : expectOpen(g);
                  case _P.server:
                    expectFailure(g);
                  case _P.pending:
                    expectPending(g);
                }
              }

              expectB();
              await tester.pump(lag);
              await settle(tester);
              expect(p.answered.where((u) => u == 'user-a').length, 2,
                  reason: "precondition: A's late answer really arrived");
              expectB();
              await unmount(tester);
            });
          }
        }
      }

      // 4 · SIGN-OUT, nobody signs in.
      testWidgets('${g.allowed.first} A signs out, nobody signs in → closed',
          (tester) async {
        final ref = await pumpScreen(tester, g, _Profile(g.allowed.first));
        expectOpen(g);
        ref.read(_signedIn.notifier).state = null;
        await settle(tester);
        expectNotOpen(g);
        await unmount(tester);
      });

      testWidgets("A signs out while A's refresh is slow; the late answer "
          'lands with nobody signed in → still closed', (tester) async {
        final p = _Profile(g.allowed.first);
        final ref = await pumpScreen(tester, g, p);
        expectOpen(g);
        p.delays['user-a'] = const Duration(seconds: 5);
        ref.invalidate(currentUserProfileProvider);
        await settle(tester);
        ref.read(_signedIn.notifier).state = null;
        await settle(tester);
        await tester.pump(const Duration(seconds: 5));
        await settle(tester);
        expect(p.answered.length, 2,
            reason: "precondition: A's late refresh arrived");
        expectNotOpen(g);
        await unmount(tester);
      });

      // 5 · SAME MEMBER, a refresh fails after a good read: the role stays.
      testWidgets('same member: a failed refresh after a good read keeps the '
          'screen open', (tester) async {
        final p = _Profile(g.allowed.first);
        final ref = await pumpScreen(tester, g, p);
        expectOpen(g);
        p.modes['user-a'] = _P.server;
        ref.invalidate(currentUserProfileProvider);
        await settle(tester);
        expect(ref.read(currentUserProfileProvider).hasError, isTrue,
            reason: 'precondition: the refresh really failed');
        expectOpen(g);
        await unmount(tester);
      });

      testWidgets('same member: a failed refresh after a good client read '
          'keeps "${g.only}"', (tester) async {
        final p = _Profile('client');
        final ref = await pumpScreen(tester, g, p);
        expectDenied(g);
        p.modes['user-a'] = _P.server;
        ref.invalidate(currentUserProfileProvider);
        await settle(tester);
        expectDenied(g);
        await unmount(tester);
      });

      // 6 · The role-only read waits for a confirmed role.
      if (g.fetchesOnOpen) {
        group('first read', () {
          testWidgets('none while the role is loading; once confirmed', (tester) async {
            final p = _Profile(g.allowed.first)
              ..delays['user-a'] = const Duration(seconds: 2);
            await pumpScreen(tester, g, p);
            expectPending(g);
            expect(server.requests, isEmpty,
                reason: 'THE defect: initState read role-only data before the '
                    'role was known');
            await tester.pump(const Duration(seconds: 2));
            await settle(tester);
            expectOpen(g);
            expect(server.requests, isNotEmpty,
                reason: 'a confirmed member gets the data as before');
            await unmount(tester);
          });

          testWidgets('none when the profile read failed', (tester) async {
            final p = _Profile(g.allowed.first)..modes['user-a'] = _P.server;
            await pumpScreen(tester, g, p);
            expectFailure(g);
            expect(server.requests, isEmpty);
            await unmount(tester);
          });

          testWidgets('none for a confirmed client', (tester) async {
            await pumpScreen(tester, g, _Profile('client'));
            expectDenied(g);
            expect(server.requests, isEmpty);
            await unmount(tester);
          });

          testWidgets('once — a profile refresh does not re-read', (tester) async {
            final p = _Profile(g.allowed.first);
            final ref = await pumpScreen(tester, g, p);
            expectOpen(g);
            final first = List<String>.of(server.requests);
            expect(first, isNotEmpty);
            ref.invalidate(currentUserProfileProvider);
            await settle(tester);
            expectOpen(g);
            expect(server.requests, first,
                reason: 'the first read is started once, not per rebuild');
            await unmount(tester);
          });
        });
      }
    });
  }
}
