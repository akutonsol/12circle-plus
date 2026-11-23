import 'dart:async';
import 'dart:convert';

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

// P0-FL-45a review round · a role-only screen's LOADED state belongs to the
// member the gate let in.
//
// 3daa2af made the GATE member-aware, but `RoleConfirmedLoad` never reset and
// the screens' State (_data, _programs, Copilot's _client, Builder's _plan, …)
// survived a SAME-ROLE switch while the screen stayed mounted: coach A → coach
// B (or admin A → admin B) and, once B's read confirmed, B saw A's loaded data
// with no new read, and A's late answers landed on B's screen.
//
// Every test here runs against a fake server that answers with the data of
// the member signed in WHEN THE REQUEST WAS SENT ("alphamark" for A,
// "bravomark" for B, "charliemark" for C) and can hold A's answers so they
// land after the switch.
//
// Also pinned (same review round):
//  * a CONFIRMED coach is denied on the admin-only and admin/content-manager
//    screens (QA mutant 6: widening allowedRoles fails a test);
//  * the denied state has the screen's AppBar with a back control (UX F1),
//    denied copy unchanged.
//
// HOW TO SEE IT FAIL: `git checkout 3daa2af -- lib/core/widgets/role_gate.dart
// <the nine screens>` — the switch / late-answer / back-control tests fail.
// Removing the member check alone (`if (_member != member)` → `if (_member ==
// null)` in RoleConfirmedLoad.gate) fails the same-frame switch tests.

const _uid = '00000000-0000-4000-8000-0000000f4545';
const _markA = 'alphamark', _markB = 'bravomark', _markC = 'charliemark';

String _mark(String member) => switch (member) {
      'user-a' => _markA,
      'user-b' => _markB,
      _ => _markC,
    };

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    );

final _signedIn = StateProvider<User?>((ref) => _user('user-a'));

enum _P { ok, server, pending }

/// The profile read, per member.
class _Profile {
  _Profile(String aRole) : roles = {'user-a': aRole};
  final Map<String, String> roles;
  final Map<String, _P> modes = {};
  final Map<String, Duration> delays = {};

  Future<Map<String, dynamic>?> read(String uid) async {
    final delay = delays[uid];
    if (delay != null) await Future<void>.delayed(delay);
    switch (modes[uid] ?? _P.ok) {
      case _P.server:
        throw const PostgrestException(message: 'refused', code: 'XX000');
      case _P.pending:
        return Completer<Map<String, dynamic>?>().future;
      case _P.ok:
        return <String, dynamic>{'id': uid, 'role': roles[uid]};
    }
  }
}

/// A fake PostgREST that answers each request with the data of the member
/// signed in when it was SENT, optionally holding that member's answers.
class _MemberServer extends RowCheckingPostgrest {
  _MemberServer() : super(_uid);

  String member = 'user-a';

  /// While set for a member, requests sent as that member wait for it —
  /// only those to [holdOnly] when that is set.
  final Map<String, Completer<void>> holds = {};
  String? holdOnly;

  /// `member endpoint` for every request.
  final sent = <String>[];

  void clear() {
    member = 'user-a';
    holds.clear();
    holdOnly = null;
    sent.clear();
  }

  int count(String member, String endpoint) =>
      sent.where((s) => s == '$member $endpoint').length;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.startsWith('/auth/')) {
      return http.StreamedResponse(const Stream.empty(), 204,
          request: request);
    }
    final who = member;
    final endpoint = path.split('/').last;
    sent.add('$who $endpoint');
    final hold = holds[who];
    if (hold != null && (holdOnly == null || holdOnly == endpoint)) {
      await hold.future;
    }
    final m = _mark(who);
    final Object? body = switch (endpoint) {
      'decision_analytics' => {'most_triggered_rule': m},
      'movement_graph_stats' => {
          'nodes': 1,
          'edges': 1,
          'edges_by_type': {m: 3},
        },
      'exercises' => [
          {
            'id': 'ex-$who',
            'name': m,
            'content_status': 'ai_generated',
            'ai_confidence': 50,
          }
        ],
      'intelligence_review_queue' => [
          {
            'exercise_id': 'ex-$who',
            'name': m,
            'confidence': 50,
            'status': 'draft'
          }
        ],
      'workout_programs' => [
          {'id': 'p-$who', 'name': m, 'engine_generated': true}
        ],
      'plan_program' => {
          'mesocycles': [
            {'name': m, 'weeks': [1, 4]}
          ],
          'weeks': [],
        },
      'generate_workout' => {
          'rules_triggered': [m],
          'selected': [],
          'trace': [],
        },
      'predict_client' => {
          'status': 'ok',
          'alerts': [m],
          'goal': {},
          'weeks_completed': 1,
          'duration_weeks': 4,
        },
      _ => path.contains('/rpc/') ? null : [],
    };
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

class _Screen {
  const _Screen(this.title, this.build, this.only, this.allowed,
      {this.endpoint, this.trigger, this.markEndpoint, this.denies = const []});
  final String title;
  final Widget Function() build;
  final String only;

  /// The screen's real allowedRoles.
  final List<String> allowed;

  /// Roles that must be denied (QA mutant 6).
  final List<String> denies;

  /// The endpoint of the FIRST request the screen sends as it opens (null
  /// when it loads only on a tap). Its answer may not be the one that shows
  /// the member's mark — Observability and Content Center read several.
  final String? endpoint;

  /// The request whose answer puts the member's mark on screen, when it is
  /// not [endpoint] (Observability and Content Center read several in a
  /// row): the late-answer test holds THIS one.
  final String? markEndpoint;

  /// For screens that load only on a tap: the label to tap, and the endpoint
  /// that tap reads.
  final (String, String)? trigger;
}

final _screens = <_Screen>[
  _Screen('Coach Copilot', () => const CoachCopilotScreen(), 'Coaches only.',
      ['coach', 'admin'],
      // Selecting A's client reads that client's outlook.
      trigger: (_markA, 'predict_client')),
  _Screen('Continuous Coaching', () => const ContinuousCoachingScreen(),
      'Coaches only.', ['coach', 'admin'],
      endpoint: 'workout_programs'),
  _Screen('Program Builder',
      () => const DynamicProgramBuilderScreen(engineWeekGeneration: false),
      'Coaches only.', ['coach', 'admin'],
      trigger: ('Plan program', 'plan_program')),
  _Screen('Weekly Review', () => const WeeklyReviewScreen(), 'Coaches only.',
      ['coach', 'admin'],
      endpoint: 'workout_programs'),
  _Screen('Coaching Observability', () => const ObservabilityScreen(),
      'Admins only.', ['admin'],
      endpoint: 'workout_programs',
      markEndpoint: 'decision_analytics',
      denies: ['coach', 'content_manager']),
  _Screen('Review Queue', () => const ContentReviewQueueScreen(),
      'Admins & content managers only.', ['admin', 'content_manager'],
      endpoint: 'exercises',
      denies: ['coach']),
  _Screen('Content Center', () => const ExerciseContentCenterScreen(),
      'Admins & content managers only.', ['admin', 'content_manager'],
      endpoint: 'exercises',
      markEndpoint: 'movement_graph_stats',
      denies: ['coach']),
  _Screen('Knowledge Review', () => const IntelligenceReviewScreen(),
      'Admins & content managers only.', ['admin', 'content_manager'],
      endpoint: 'intelligence_review_queue', denies: ['coach']),
  _Screen('MIE Debugger', () => const MieDebuggerScreen(),
      'Admins & content managers only.', ['admin', 'content_manager'],
      trigger: ('Generate & trace', 'generate_workout'), denies: ['coach']),
];

void main() {
  late _MemberServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _MemberServer();
    await initSignedInSupabase(server);
  });

  setUp(() => server.clear());

  Future<void> settle(WidgetTester tester) async {
    // Spinners animate forever: pump, never settle.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Finder shows(String mark) => find.textContaining(mark, skipOffstage: false);

  /// Pumps [s] PUSHED over a home page (so the AppBar has a back control).
  Future<WidgetRef> pumpScreen(
      WidgetTester tester, _Screen s, _Profile p) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 3000);
    addTearDown(tester.view.reset);
    late WidgetRef captured;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
        currentUserProfileProvider.overrideWith((ref) async {
          final u = ref.watch(currentUserProvider);
          if (u == null) return null;
          return p.read(u.id);
        }),
        // Each coach has their own roster.
        coachClientsProvider.overrideWith((ref) async {
          final u = ref.watch(currentUserProvider);
          if (u == null) return const [];
          return [
            {'id': 'client-of-${u.id}', 'first_name': _mark(u.id)}
          ];
        }),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        home: Consumer(builder: (context, ref, _) {
          captured = ref;
          return const Scaffold(body: Text('home page'));
        }),
      ),
    ));
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => s.build()));
    await settle(tester);
    return captured;
  }

  /// Signs [member] in (after signing the current member out).
  Future<void> switchTo(WidgetTester tester, WidgetRef ref, String member,
      {required bool observeSignOut}) async {
    ref.read(_signedIn.notifier).state = null;
    if (observeSignOut) await settle(tester);
    server.member = member;
    ref.read(_signedIn.notifier).state = _user(member);
    await settle(tester);
  }

  /// A's data on screen: opened (first read) or tapped (user-triggered).
  Future<void> loadAsA(WidgetTester tester, _Screen s) async {
    final t = s.trigger;
    if (t != null) {
      await tester.tap(find.text(t.$1).first);
      await settle(tester);
    }
  }

  String endpointOf(_Screen s) => s.endpoint ?? s.trigger!.$2;

  void expectOpen(_Screen s) {
    expect(find.text(s.only), findsNothing);
    expect(find.byType(ProfileLoadFailedNotice), findsNothing);
    expect(find.bySemanticsLabel('Loading your account'), findsNothing);
  }

  /// B's screen right after admit: B's own data when the screen reads as it
  /// opens; nothing selected / no result when it loads only on a tap.
  void expectFreshFor(_Screen s, String member) {
    expect(shows(_markA), findsNothing,
        reason: "THE defect: A's loaded data is shown to ${_mark(member)}");
    if (s.endpoint != null) {
      expect(shows(_mark(member)), findsWidgets,
          reason: "the new member's own first read ran and is shown");
      expect(server.count(member, s.endpoint!), 1,
          reason: "the new member's first read runs exactly once");
    } else {
      expect(server.count(member, s.trigger!.$2), 0,
          reason: 'nothing is read for the new member until they ask');
      if (s.title == 'Coach Copilot') {
        expect(find.text('Recovery'), findsNothing,
            reason: "A's selected client is not B's selection");
      }
    }
  }

  for (final s in _screens) {
    group(s.title, () {
      // 1 · SAME-ROLE switch with the screen mounted.
      for (final role in s.allowed) {
        for (final observe in [true, false]) {
          final how = observe ? 'sign-out observed' : 'same-frame switch';
          testWidgets('$role A → $role B ($how): B never sees A\'s data; '
              "B's first read runs once", (tester) async {
            final p = _Profile(role)..roles['user-b'] = role;
            final ref = await pumpScreen(tester, s, p);
            await loadAsA(tester, s);
            expectOpen(s);
            expect(shows(_markA), findsWidgets,
                reason: "precondition: A's data is on screen");
            expect(server.count('user-a', endpointOf(s)), 1);

            await switchTo(tester, ref, 'user-b', observeSignOut: observe);
            expectOpen(s);
            expectFreshFor(s, 'user-b');
            await unmount(tester);
          });

          testWidgets("$role A → $role B ($how): A's late answer, landing "
              'after the switch, is ignored', (tester) async {
            final p = _Profile(role)..roles['user-b'] = role;
            final aHold = Completer<void>();
            final held = s.markEndpoint ?? endpointOf(s);
            server
              ..holds['user-a'] = aHold
              ..holdOnly = held;
            final ref = await pumpScreen(tester, s, p);
            await loadAsA(tester, s);
            expect(server.count('user-a', held), 1,
                reason: "precondition: A's read is on the wire");
            // (Copilot and Weekly Review show A's roster: one chip.)
            expect(shows(_markA).evaluate().length,
                {'Coach Copilot', 'Weekly Review'}.contains(s.title) ? 1 : 0,
                reason: "precondition: A's answer has not landed yet");

            await switchTo(tester, ref, 'user-b', observeSignOut: observe);
            aHold.complete(); // A's answers land now, B signed in
            await settle(tester);
            await tester.pump(const Duration(seconds: 1));
            await settle(tester);
            expect(shows(_markA), findsNothing,
                reason: "THE defect: A's late answer landed on B's screen");
            expectFreshFor(s, 'user-b');
            await unmount(tester);
          });
        }
      }

      // 2 · B's own profile read FAILS / is IN FLIGHT, then SUCCEEDS.
      final role = s.allowed.first;
      testWidgets("$role A → $role B: B's read FAILS, then a retry succeeds → "
          "only B's data, read once", (tester) async {
        final p = _Profile(role)
          ..roles['user-b'] = role
          ..modes['user-b'] = _P.server;
        final ref = await pumpScreen(tester, s, p);
        await loadAsA(tester, s);
        expect(shows(_markA), findsWidgets);
        await switchTo(tester, ref, 'user-b', observeSignOut: false);
        expect(find.byType(ProfileLoadFailedNotice), findsOneWidget);
        expect(shows(_markA), findsNothing);
        p.modes['user-b'] = _P.ok;
        await tester.tap(find.text('Try again'));
        await settle(tester);
        expectOpen(s);
        expectFreshFor(s, 'user-b');
        await unmount(tester);
      });

      testWidgets("$role A → $role B: B's read IN FLIGHT → loading, then "
          "B's data only, read once", (tester) async {
        final p = _Profile(role)
          ..roles['user-b'] = role
          ..delays['user-b'] = const Duration(seconds: 2);
        final ref = await pumpScreen(tester, s, p);
        await loadAsA(tester, s);
        await switchTo(tester, ref, 'user-b', observeSignOut: true);
        expect(find.bySemanticsLabel('Loading your account'), findsOneWidget);
        expect(shows(_markA), findsNothing);
        expect(server.count('user-b', endpointOf(s)), 0,
            reason: 'nothing role-only is read before B is confirmed');
        await tester.pump(const Duration(seconds: 2));
        await settle(tester);
        expectOpen(s);
        expectFreshFor(s, 'user-b');
        await unmount(tester);
      });

      // 3 · Through a client: A → client B → C of A's role.
      testWidgets('$role A → client B → $role C: C starts fresh',
          (tester) async {
        final p = _Profile(role)
          ..roles['user-b'] = 'client'
          ..roles['user-c'] = role;
        final ref = await pumpScreen(tester, s, p);
        await loadAsA(tester, s);
        await switchTo(tester, ref, 'user-b', observeSignOut: true);
        expect(find.text(s.only), findsOneWidget);
        expect(shows(_markA), findsNothing);
        await switchTo(tester, ref, 'user-c', observeSignOut: false);
        expectOpen(s);
        expectFreshFor(s, 'user-c');
        await unmount(tester);
      });

      testWidgets('client A → $role B: B\'s first read runs once, B\'s data',
          (tester) async {
        final p = _Profile('client')..roles['user-b'] = role;
        final ref = await pumpScreen(tester, s, p);
        expect(find.text(s.only), findsOneWidget);
        expect(server.sent, isEmpty);
        await switchTo(tester, ref, 'user-b', observeSignOut: false);
        expectOpen(s);
        expectFreshFor(s, 'user-b');
        await unmount(tester);
      });

      // 4 · Sign-out, nobody signs in: closed, and A's late answer is dropped.
      testWidgets('$role A signs out with a read in flight; nobody signs in → '
          "closed; then A signs back in → a fresh read", (tester) async {
        final p = _Profile(role);
        final aHold = Completer<void>();
        server.holds['user-a'] = aHold;
        final ref = await pumpScreen(tester, s, p);
        await loadAsA(tester, s);
        ref.read(_signedIn.notifier).state = null;
        await settle(tester);
        aHold.complete();
        await settle(tester);
        // Nobody signed in: the profile read answers "no row", so the gate
        // shows "… only." (or loading) — never the tool.
        expect(
            find.text(s.only).evaluate().isNotEmpty ||
                find.bySemanticsLabel('Loading your account')
                    .evaluate()
                    .isNotEmpty,
            isTrue,
            reason: 'nobody signed in: the tool stays shut');
        expect(shows(_markA), findsNothing);
        server.holds.clear();
        ref.read(_signedIn.notifier).state = _user('user-a');
        await settle(tester);
        expectOpen(s);
        if (s.endpoint != null) {
          expect(shows(_markA), findsWidgets);
          expect(server.count('user-a', s.endpoint!), 2,
              reason: 'a new session reads again, once');
        }
        await unmount(tester);
      });

      // 5 · SAME member: a refresh (good or failed) neither clears nor re-reads.
      for (final refresh in [_P.ok, _P.server]) {
        testWidgets('same member: a ${refresh == _P.ok ? 'good' : 'FAILED'} '
            'profile refresh keeps A\'s data and does not re-read',
            (tester) async {
          final p = _Profile(role);
          final ref = await pumpScreen(tester, s, p);
          await loadAsA(tester, s);
          expect(shows(_markA), findsWidgets);
          p.modes['user-a'] = refresh;
          ref.invalidate(currentUserProfileProvider);
          await settle(tester);
          if (refresh == _P.server) {
            expect(ref.read(currentUserProfileProvider).hasError, isTrue,
                reason: 'precondition: the refresh really failed');
          }
          expectOpen(s);
          expect(shows(_markA), findsWidgets,
              reason: 'the same member keeps what they loaded');
          expect(server.count('user-a', endpointOf(s)), 1,
              reason: 'a profile refresh does not re-run the load');
          await unmount(tester);
        });
      }

      // 6 · QA mutant 6: a CONFIRMED coach (etc.) is denied.
      for (final denied in s.denies) {
        testWidgets('a confirmed $denied is denied ("${s.only}")',
            (tester) async {
          await pumpScreen(tester, s, _Profile(denied));
          expect(find.text(s.only), findsOneWidget,
              reason: '$denied is not in allowedRoles ${s.allowed}');
          expect(server.sent, isEmpty, reason: 'nothing role-only is read');
          await unmount(tester);
        });
      }

      // 7 · UX F1: the denied state keeps the AppBar and a back control.
      testWidgets('denied state: same AppBar title and a working back control; '
          'copy unchanged', (tester) async {
        await pumpScreen(tester, s, _Profile('client'));
        expect(find.text(s.only), findsOneWidget);
        expect(
            find.descendant(
                of: find.byType(AppBar), matching: find.text(s.title)),
            findsOneWidget);
        expect(find.byType(BackButton), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await settle(tester);
        expect(find.text('home page'), findsOneWidget,
            reason: 'back leaves the denied screen');
        await unmount(tester);
      });
    });
  }
}
