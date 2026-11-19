import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/admin/presentation/observability_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
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
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:circle_fitness/features/payments/presentation/manage_subscription_screen.dart';
import 'package:circle_fitness/features/profile/presentation/widgets/profile_load_failed_notice.dart';
import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/train_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-40 · a failed read is never shown as a role or plan fact.
//
// 1. Nine role-gated screens read the role as
//    `currentUserProfileProvider.valueOrNull?['role']`. Since P0-FL-16 that
//    provider rethrows, so a FAILED (or still LOADING) profile read was null
//    and the screen told a coach "Coaches only." / an admin "Admins only." /
//    "Admins & content managers only.".
// 2. Manage subscription rendered a failed mySubscriptions / myCoaches read as
//    nothing at all — the same as having no membership and no coaches.
// 3. The Train hub rendered a failed active-session lookup as "nothing to
//    resume" (EC-G6), hiding Resume from a member mid-workout.
//
// HOW TO SEE THEM FAIL: `git checkout 6f8918f -- <the 11 lib screens>`; the
// failure/loading tests find "… only." / no "Couldn't load", and the retry
// tests find no Try again.

const _uid = '00000000-0000-4000-8000-0000000f4040';
const _profileFailed = "Couldn't load your profile — try again in a moment. "
    'If it keeps happening, contact support.';
const _profileOffline =
    "Couldn't load your profile — check your connection and try again.";

enum _Read { ok, network, server, pending }

/// One controllable read: failed (network or server), held in flight, or
/// answered with [value].
class _Source<T> {
  _Source(this.value);
  T value;
  _Read mode = _Read.ok;
  int reads = 0;

  /// When set, a read is counted at once but answered only when it completes.
  Completer<void>? gate;

  Future<T> read() async {
    reads++;
    if (gate != null) await gate!.future;
    switch (mode) {
      case _Read.network:
        throw http.ClientException('Connection refused');
      case _Read.server:
        throw const PostgrestException(message: 'refused', code: 'XX000');
      case _Read.pending:
        return Completer<T>().future; // never answers
      case _Read.ok:
        return value;
    }
  }
}

class _Gated {
  const _Gated(this.name, this.build, this.only, this.allowedRole,
      {this.deniedRole = 'client', String? title})
      : title = title ?? name;
  final String name;
  /// The screen's own AppBar title, which the gate keeps (UX-1).
  final String title;
  final Widget Function() build;
  final String only;
  final String allowedRole;
  final String deniedRole;
}

final _gated = <_Gated>[
  _Gated('Coach Copilot', () => const CoachCopilotScreen(), 'Coaches only.', 'coach'),
  _Gated('Continuous Coaching', () => const ContinuousCoachingScreen(),
      'Coaches only.', 'coach'),
  _Gated('Program Builder',
      () => const DynamicProgramBuilderScreen(engineWeekGeneration: false),
      'Coaches only.', 'admin'),
  _Gated('Weekly Review', () => const WeeklyReviewScreen(), 'Coaches only.', 'coach'),
  _Gated('Observability', () => const ObservabilityScreen(), 'Admins only.', 'admin',
      deniedRole: 'coach', title: 'Coaching Observability'),
  _Gated('Content Review Queue', () => const ContentReviewQueueScreen(),
      'Admins & content managers only.', 'content_manager', deniedRole: 'coach',
      title: 'Review Queue'),
  _Gated('Exercise Content Center', () => const ExerciseContentCenterScreen(),
      'Admins & content managers only.', 'admin', deniedRole: 'coach',
      title: 'Content Center'),
  _Gated('Intelligence Review', () => const IntelligenceReviewScreen(),
      'Admins & content managers only.', 'content_manager', deniedRole: 'coach',
      title: 'Knowledge Review'),
  _Gated('MIE Debugger', () => const MieDebuggerScreen(),
      'Admins & content managers only.', 'admin', deniedRole: 'coach'),
];

void main() {
  late RowCheckingPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RowCheckingPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> settle(WidgetTester tester, {required bool settle}) async {
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
  }

  /// Unmount, then let any scaffold/chrome timer run out.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  // ── 1 · role gates ─────────────────────────────────────────────────────────
  group('role gates', () {
    Future<_Source<Map<String, dynamic>?>> openGate(
        WidgetTester tester, _Gated g, _Source<Map<String, dynamic>?> profile,
        {bool settleIt = true}) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(900, 3000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider
              .overrideWithValue(Supabase.instance.client.auth.currentUser),
          currentUserProfileProvider.overrideWith((ref) => profile.read()),
          coachClientsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(home: g.build()),
      ));
      await settle(tester, settle: settleIt);
      return profile;
    }

    /// The gate is shut: only the screen's own title-only AppBar (UX-1) —
    /// no role-only actions (refresh) — and the gate body.
    void expectGateChrome(_Gated g) {
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text(g.title)),
          findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing,
          reason: 'fail closed: nothing role-only is shown');
    }

    /// The gate has opened: neither its spinner nor its failure notice.
    void expectScreenOpen() {
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(ProfileLoadFailedNotice), findsNothing);
      expect(find.bySemanticsLabel('Loading your account'), findsNothing);
    }

    /// UX-1 · open [g] pushed over a home route, as the app does.
    Future<void> pushGate(
        WidgetTester tester, _Gated g, _Source<Map<String, dynamic>?> profile,
        {required bool settleIt}) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(900, 3000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider
              .overrideWithValue(Supabase.instance.client.auth.currentUser),
          currentUserProfileProvider.overrideWith((ref) => profile.read()),
          coachClientsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          home: Builder(builder: (context) => Scaffold(body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => g.build())),
              child: const Text('HOME'),
            ),
          ))),
        ),
      ));
      await tester.tap(find.text('HOME'));
      await settle(tester, settle: settleIt);
    }

    for (final g in _gated) {
      group(g.name, () {
        for (final pending in [true, false]) {
          final state = pending ? 'loading' : 'failure';
          testWidgets('UX-1 · the $state gate has the title and a back control',
              (tester) async {
            final p = _Source<Map<String, dynamic>?>({'id': _uid, 'role': g.allowedRole})
              ..mode = pending ? _Read.pending : _Read.server;
            await pushGate(tester, g, p, settleIt: !pending);
            expect(pending ? find.bySemanticsLabel('Loading your account')
                           : find.text(_profileFailed), findsOneWidget);
            expect(find.descendant(of: find.byType(AppBar), matching: find.text(g.title)),
                findsOneWidget);
            expect(find.byType(BackButton), findsOneWidget,
                reason: 'THE defect (UX-1): no in-app way out of the gate');
            await tester.tap(find.byType(BackButton));
            await settle(tester, settle: !pending);
            expect(find.text('HOME'), findsOneWidget);
            expect(find.byType(BackButton), findsNothing);
            await unmount(tester);
          });
        }

        testWidgets('failed profile read → the failure notice, not "${g.only}"',
            (tester) async {
          final p = _Source<Map<String, dynamic>?>({'id': _uid, 'role': g.allowedRole})
            ..mode = _Read.server;
          await openGate(tester, g, p);
          expect(find.text(g.only), findsNothing,
              reason: 'THE defect: an unread role was shown as "lacks the role"');
          expect(find.text(_profileFailed), findsOneWidget);
          expect(find.text('Try again'), findsOneWidget);
          expectGateChrome(g);
          await unmount(tester);
        });

        testWidgets('loading → neutral, neither "${g.only}" nor the screen',
            (tester) async {
          final p = _Source<Map<String, dynamic>?>({'id': _uid, 'role': g.allowedRole})
            ..mode = _Read.pending;
          await openGate(tester, g, p, settleIt: false);
          expect(find.text(g.only), findsNothing);
          expect(find.textContaining("Couldn't load"), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expectGateChrome(g);
          await unmount(tester);
        });

        testWidgets('success without the role → "${g.only}" (unchanged)',
            (tester) async {
          final p = _Source<Map<String, dynamic>?>({'id': _uid, 'role': g.deniedRole});
          await openGate(tester, g, p);
          expect(find.text(g.only), findsOneWidget);
          expect(find.textContaining("Couldn't load"), findsNothing);
          await unmount(tester);
        });

        testWidgets('success with the role → the screen (unchanged)', (tester) async {
          final p = _Source<Map<String, dynamic>?>({'id': _uid, 'role': g.allowedRole});
          await openGate(tester, g, p);
          expect(find.text(g.only), findsNothing);
          expect(find.textContaining("Couldn't load your profile"), findsNothing);
          expectScreenOpen();
          await unmount(tester);
        });

        testWidgets('Try again is busy while it re-reads, then opens the screen',
            (tester) async {
          final p = _Source<Map<String, dynamic>?>({'id': _uid, 'role': g.allowedRole})
            ..mode = _Read.server;
          await openGate(tester, g, p);
          expect(find.text(_profileFailed), findsOneWidget);

          p
            ..mode = _Read.ok
            ..gate = Completer<void>();
          await tester.tap(find.text('Try again'));
          await tester.pump();
          await tester.pump();
          expect(p.reads, 2);
          expect(find.text('Loading…'), findsOneWidget,
              reason: 'the notice stays, busy, while the retry is in flight');
          expect(find.text(g.only), findsNothing);
          await tester.tap(find.text('Loading…'), warnIfMissed: false);
          await tester.pump();
          expect(p.reads, 2, reason: 'a busy Try again cannot fire twice');

          p.gate!.complete();
          await tester.pumpAndSettle();
          expect(find.textContaining("Couldn't load"), findsNothing);
          expectScreenOpen();
          await unmount(tester);
        });
      });
    }

    testWidgets('a network failure gets the connection hint, and a live region',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final p = _Source<Map<String, dynamic>?>({'id': _uid, 'role': 'coach'})
        ..mode = _Read.network;
      await openGate(tester, _gated.first, p);
      expect(find.text(_profileOffline), findsOneWidget);
      expect(find.text('Coaches only.'), findsNothing);
      final live = find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false));
      expect(live, findsWidgets);
      final size = tester.getSize(find.widgetWithText(TextButton, 'Try again'));
      expect(size.height, greaterThanOrEqualTo(44));
      semantics.dispose();
      await unmount(tester);
    });
  });

  // ── UX-3 · the notice's live region covers the message only ─────────────
  group('ProfileLoadFailedNotice live region', () {
    Future<void> pumpNotice(WidgetTester tester, {required bool busy}) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: ProfileLoadFailedNotice(
          error: const PostgrestException(message: 'refused', code: 'XX000'),
          busy: busy,
          detail: 'Coach tools stay closed until it loads.',
          onRetry: () {},
        ))));

    final live = find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.liveRegion ?? false));

    for (final busy in [false, true]) {
      testWidgets('busy=$busy · the message is live, Try again is not inside it',
          (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpNotice(tester, busy: busy);
        expect(live, findsOneWidget);
        expect(find.descendant(of: live, matching: find.text(_profileFailed)),
            findsOneWidget);
        expect(find.descendant(of: live, matching: find.byType(TextButton)),
            findsNothing,
            reason: 'THE defect (UX-3): the label flip re-announced the notice');
        expect(find.descendant(of: live,
                matching: find.text('Coach tools stay closed until it loads.')),
            findsNothing);
        // The button keeps its own semantics.
        expect(find.bySemanticsLabel(
                busy ? 'Loading your profile' : 'Try again, load your profile'),
            findsOneWidget);
        expect(tester.getSize(find.byType(TextButton)).height,
            greaterThanOrEqualTo(44));
        semantics.dispose();
      });
    }
  });

  // ── 2 · Manage subscription ────────────────────────────────────────────────
  group('Manage subscription', () {
    Future<void> openManage(
      WidgetTester tester, {
      required _Source<List<Map<String, dynamic>>> subs,
      required _Source<List<Map<String, dynamic>>> coaches,
      bool settleIt = true,
    }) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(600, 3200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider
              .overrideWithValue(Supabase.instance.client.auth.currentUser),
          clientPlanProvider.overrideWith((ref) async => ClientPlan.free),
          mySubscriptionsProvider.overrideWith((ref) => subs.read()),
          myCoachesProvider.overrideWith((ref) => coaches.read()),
        ],
        child: const MaterialApp(home: ManageSubscriptionScreen()),
      ));
      await settle(tester, settle: settleIt);
    }

    const noCoach =
        'You’re not working with a coach yet. Add a fitness or nutrition coach any time.';
    const free = 'You’re on the Free plan. Upgrade any time to unlock more.';

    testWidgets('subscriptions read failed → said so, with Try again that recovers',
        (tester) async {
      final subs = _Source<List<Map<String, dynamic>>>(const [])..mode = _Read.server;
      final coaches = _Source<List<Map<String, dynamic>>>(const []);
      await openManage(tester, subs: subs, coaches: coaches);
      expect(find.text("Couldn't load your subscriptions"), findsOneWidget,
          reason: 'THE defect: a failed read rendered as no membership');
      expect(find.text(
              'Try again in a moment. If it keeps happening, contact support.'),
          findsOneWidget);
      expect(reported.map((f) => f.origin),
          contains('ManageSubscriptionScreen.mySubscriptions'));

      subs
        ..mode = _Read.ok
        ..gate = Completer<void>();
      await tester.tap(find.widgetWithText(TextButton, 'Try again'));
      await tester.pump();
      await tester.pump();
      expect(subs.reads, 2);
      expect(find.text("Couldn't load your subscriptions"), findsOneWidget,
          reason: 'the card stays, busy, during the retry');
      expect(find.widgetWithText(TextButton, 'Try again'), findsNothing);
      subs.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load your subscriptions"), findsNothing);
      expect(find.text(free), findsOneWidget);
    });

    testWidgets('coaches read failed → said so, not "not working with a coach"',
        (tester) async {
      final subs = _Source<List<Map<String, dynamic>>>(const []);
      final coaches = _Source<List<Map<String, dynamic>>>(const [])
        ..mode = _Read.network;
      await openManage(tester, subs: subs, coaches: coaches);
      expect(find.text("Couldn't load your coaches"), findsOneWidget,
          reason: 'THE defect: a failed read rendered as nothing');
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      expect(find.text(noCoach), findsNothing);
      expect(reported.map((f) => f.origin),
          contains('ManageSubscriptionScreen.myCoaches'));

      coaches.mode = _Read.ok;
      await tester.tap(find.widgetWithText(TextButton, 'Try again'));
      await tester.pumpAndSettle();
      expect(coaches.reads, 2);
      expect(find.textContaining("Couldn't load your coaches"), findsNothing);
      expect(find.text(noCoach), findsOneWidget);
    });

    testWidgets('UX-4 · pull to refresh re-reads coaches as well as subscriptions',
        (tester) async {
      final subs = _Source<List<Map<String, dynamic>>>(const []);
      final coaches = _Source<List<Map<String, dynamic>>>(const [])
        ..mode = _Read.server;
      await openManage(tester, subs: subs, coaches: coaches);
      expect(find.text("Couldn't load your coaches"), findsOneWidget);
      expect(subs.reads, 1);
      expect(coaches.reads, 1);

      coaches.mode = _Read.ok;
      // A real pull: drag the page's list down from its top, far enough to arm
      // the indicator (a share of the viewport height — this one is tall).
      final list = find
          .descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable))
          .first;
      await tester.timedDragFrom(tester.getTopLeft(list) + const Offset(20, 20),
          Offset(0, tester.getSize(list).height * 0.6),
          const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(subs.reads, 2);
      expect(coaches.reads, 2,
          reason: 'THE defect (UX-4): the pull never re-read the coaches');
      expect(find.textContaining("Couldn't load your coaches"), findsNothing);
      expect(find.text(noCoach), findsOneWidget);
    });

    testWidgets('loading → neutral placeholders, no empty claims', (tester) async {
      final subs = _Source<List<Map<String, dynamic>>>(const [])..mode = _Read.pending;
      final coaches = _Source<List<Map<String, dynamic>>>(const [])
        ..mode = _Read.pending;
      await openManage(tester, subs: subs, coaches: coaches, settleIt: false);
      expect(find.bySemanticsLabel('Loading your coaches'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading your subscriptions'), findsOneWidget);
      expect(find.text(noCoach), findsNothing);
      expect(find.text(free), findsNothing);
      expect(find.textContaining("Couldn't load"), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('empty success → today\'s empty copy, unchanged', (tester) async {
      await openManage(tester,
          subs: _Source<List<Map<String, dynamic>>>(const []),
          coaches: _Source<List<Map<String, dynamic>>>(const []));
      expect(find.text(free), findsOneWidget);
      expect(find.text(noCoach), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(reported, isEmpty);
    });
  });

  // ── 3 · Train hub active session ───────────────────────────────────────────
  group('Train hub active session', () {
    Future<void> openHub(
        WidgetTester tester, _Source<WorkoutSessionRecord?> session) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(900, 6000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProfileProvider.overrideWith((ref) async => {'role': 'client'}),
          currentStreakProvider.overrideWith((ref) async => 0),
          weeklyWorkoutCountProvider.overrideWith((ref) async => 0),
          totalWorkoutCountProvider.overrideWith((ref) async => 0),
          completionRateProvider.overrideWith((ref) async => 0),
          activeSessionProvider.overrideWith((ref) => session.read()),
          assignedWorkoutsProvider.overrideWith((ref) async => []),
          personalRecordsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: TrainHubScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('failed lookup → said so with Try again, which recovers',
        (tester) async {
      final s = _Source<WorkoutSessionRecord?>(null)..mode = _Read.server;
      await openHub(tester, s);
      expect(find.text("Couldn't load your workout in progress"), findsOneWidget,
          reason: 'THE defect (EC-G6): a failed lookup looked like "nothing to resume"');
      expect(reported.map((f) => f.origin), contains('TrainHubScreen.activeSession'));

      s
        ..mode = _Read.ok
        ..gate = Completer<void>();
      final retry = find.widgetWithText(TextButton, 'Try again');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pump();
      await tester.pump();
      expect(s.reads, 2);
      expect(find.text("Couldn't load your workout in progress"), findsOneWidget,
          reason: 'the card stays, busy, during the retry');
      s.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load your workout"), findsNothing);
      expect(find.text('RESUME WORKOUT'), findsNothing);
      await unmount(tester);
    });

    testWidgets('no session → no banner and no failure, unchanged', (tester) async {
      await openHub(tester, _Source<WorkoutSessionRecord?>(null));
      expect(find.text('RESUME WORKOUT'), findsNothing);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(reported, isEmpty);
      await unmount(tester);
    });
  });
}
