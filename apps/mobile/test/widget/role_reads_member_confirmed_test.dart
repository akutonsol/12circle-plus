import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/classes/presentation/classes_screen.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:circle_fitness/features/exercise_database/data/models/exercise_detail_model.dart';
import 'package:circle_fitness/features/exercise_database/domain/custom_exercise_provider.dart';
import 'package:circle_fitness/features/exercise_database/domain/exercise_database_provider.dart';
import 'package:circle_fitness/features/exercise_database/presentation/create_exercise_screen.dart';
import 'package:circle_fitness/features/exercise_database/presentation/exercise_database_screen.dart';
import 'package:circle_fitness/features/exercise_database/presentation/exercise_detail_screen.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_focus_section.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/profile/presentation/personal_info_screen.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/train_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-45b · every role/profile-derived decision outside the shell and the
// paywall uses a role read CONFIRMED for the member signed in now.
//
// Riverpod keeps the previous value through a re-read. These sites read
// `currentUserProfileProvider.valueOrNull?['role']` (or `.value`, or
// `whenOrNull(data:)`, or the whole row), so after member A signs out and
// member B signs in, while B's read was IN FLIGHT or had FAILED, B got A's
// role: A coach's "New Class"/"New Exercise"/"Edit" controls, the coach
// editor in Coach Focus, the coach tile on Train, A's "Coach" chip, A's name
// and A's client rows on Profile/Settings; an admin's "Enrich with AI" and
// full-edit rights in Create Exercise. Coach Focus also read the role ONCE in
// initState — a coach whose read was still loading got the client view until
// the screen was reopened.
//
// Each site runs the same matrix as P0-FL-44 (app_shell_role_read_failure_test):
// switches in both directions (and admin → client where admin matters), B's
// read FAILED / IN FLIGHT / SUCCEEDED, with the sign-out observed or in the
// same frame; A's DELAYED answer landing after B signed in; sign-out with
// nobody signing in; and a same-member refresh that fails after a good read
// (keeps the role).
//
// HOW TO SEE IT FAIL: `git checkout 185261e -- <the site's lib file>`.

enum _P { ok, server, pending }

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    );

const _names = {'user-a': 'Alice', 'user-b': 'Bruno'};

final _signedIn = StateProvider<User?>((ref) => _user('user-a'));

/// The profile read, controllable per member (P0-FL-44's harness).
class _Profile {
  _Profile(String aRole, String bRole)
      : roles = {'user-a': aRole, 'user-b': bRole};
  final Map<String, String> roles;
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
          'role': roles[uid],
          'first_name': _names[uid],
          'last_name': 'Smith',
          'email': '$uid@example.com',
          'unit_preference': 'metric',
        };
    }
  }
}

/// Answers Coach Focus's client view (an RPC is a POST, which the parent
/// treats as a write) with an overlay, and records which view was read.
class _Server extends RowCheckingPostgrest {
  _Server() : super('user-a');
  final views = <String>[];

  /// When set, the client view's answer waits for it (a SLOW overlay read).
  Completer<void>? clientGate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/rpc/resolve_exercise_media')) {
      views.add('client');
      final gate = clientGate;
      if (gate != null) await gate.future;
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({
            'has_coach_overlay': true,
            'focus': ['Slow on the way down'],
            'coach_name': 'Coach Zee',
          }))),
          200,
          request: request,
          headers: {'content-type': 'application/json'});
    }
    if (path.endsWith('/coach_exercise_media')) views.add('staff');
    return super.send(request);
  }
}

/// Create Exercise edits a PLATFORM exercise (no owner): only an admin gets
/// the full editor; anyone else is media-only.
class _Svc extends CustomExerciseService {
  @override
  Future<List<ExerciseDetail>> getMyExercises() async => const [];
  @override
  Future<Map<String, dynamic>?> getRawById(String id) async => {
        'id': id,
        'name': 'Goblet Squat',
        'coach_id': null,
        'content_status': 'approved',
        'visibility': 'global',
        'instructions': ['Brace and sit down between the heels'],
      };
}

final _exercise = ExerciseDetail(
  id: 'ex-1',
  name: 'Goblet Squat',
  category: 'Strength',
  muscleGroup: 'Legs',
  secondaryMuscles: const [],
  equipment: 'Dumbbell',
  difficulty: 'Beginner',
  description: 'A squat holding one weight at the chest.',
  instructions: const ['Brace', 'Sit down'],
  coachingCues: const [],
  commonMistakes: const [],
  alternatives: const [],
  tags: const [],
);

/// One role-derived site: how to mount it, and what it must show for a
/// confirmed role (`null` = the role is UNKNOWN for the member signed in).
class _Site {
  const _Site(this.name, this.build, this.expectFor,
      {this.overrides = const [], this.adminMatters = false});
  final String name;
  final Widget Function() build;
  final void Function(String? role, String? member) expectFor;
  final List<Override> overrides;
  final bool adminMatters;
}

void _shows(String text, bool shown, String why) =>
    expect(find.text(text), shown ? findsWidgets : findsNothing, reason: why);

/// Neither member's name may be on screen unless that member is confirmed.
void _onlyNameOf(String? member) {
  for (final e in _names.entries) {
    expect(find.textContaining(e.value), e.key == member ? findsWidgets : findsNothing,
        reason: '${e.value} is ${e.key}\'s name');
  }
}

final _sites = <_Site>[
  _Site('Classes', () => const ClassesScreen(), (role, _) {
    _shows('New Class', role == 'coach', 'New Class is a coach control');
  }),
  _Site('Exercise Database', () => const ExerciseDatabaseScreen(), (role, _) {
    _shows('New Exercise', role == 'coach', 'New Exercise is a coach control');
    expect(find.byIcon(Icons.video_library_outlined),
        role == 'coach' || role == 'admin' ? findsOneWidget : findsNothing,
        reason: 'bulk video enrichment is a staff tool');
  }, overrides: [
    myExercisesProvider.overrideWith((ref) async => const []),
    globalApprovedExercisesProvider.overrideWith((ref) async => const []),
  ], adminMatters: true),
  _Site('Exercise Detail', () => const ExerciseDetailScreen(), (role, _) {
    _shows('Edit', role == 'coach' || role == 'admin', 'Edit is a staff control');
    // The exercise has instructions, so the admin control reads "Regenerate".
    _shows('Regenerate with AI', role == 'admin', 'AI enrichment is admin-only');
  }, overrides: [
    selectedExerciseDetailProvider.overrideWith((ref) => _exercise),
  ], adminMatters: true),
  _Site('Coach Focus',
      () => const Scaffold(
          body: SingleChildScrollView(child: CoachFocusSection(exerciseId: 'ex-1'))),
      (role, _) {
    final staff = role == 'coach' || role == 'admin';
    _shows('Add your coaching — a focus, a note, your own video', staff,
        'the overlay editor is a staff view');
    _shows('COACH FOCUS TODAY', role != null && !staff,
        "the coach's overlay is the client view");
  }, adminMatters: true),
  _Site('Create Exercise', () => const CreateExerciseScreen(), (role, _) {
    expect(find.textContaining('This is a library exercise'),
        role == 'admin' ? findsNothing : findsOneWidget,
        reason: 'only an admin fully edits a platform exercise; an unknown '
            'role is media-only, as "no role" always was');
  }, overrides: [
    customExerciseSvcProvider.overrideWithValue(_Svc()),
    editingExerciseProvider.overrideWith((ref) => 'ex-1'),
  ], adminMatters: true),
  _Site('Train hub', () => const TrainHubScreen(), (role, _) {
    _shows('Create Exercise', role == 'coach', 'the coach tile');
    _shows('Habits', role != 'coach', 'the client tile (also on unknown)');
  }, overrides: [
    currentStreakProvider.overrideWith((ref) async => 0),
    weeklyWorkoutCountProvider.overrideWith((ref) async => 0),
    totalWorkoutCountProvider.overrideWith((ref) async => 0),
    completionRateProvider.overrideWith((ref) async => 0),
    activeSessionProvider.overrideWith((ref) async => null),
    assignedWorkoutsProvider.overrideWith((ref) async => []),
    personalRecordsProvider.overrideWith((ref) async => []),
  ]),
  _Site('Profile', () => const ProfileScreen(), (role, member) {
    _shows('Coach', role == 'coach', "the 'Coach' chip");
    _shows('Member', role == 'client', "the 'Member' chip");
    _shows('Coach Dashboard', role == 'coach', 'the coach row');
    _shows('Subscription', role == 'client', 'the client row');
    _onlyNameOf(member);
  }, overrides: [
    clientPlanProvider.overrideWith((ref) async => ClientPlan.selfGuided),
  ]),
  _Site('Settings', () => const SettingsScreen(), (role, member) {
    _shows('Subscription', role == 'client', 'the client row');
    _shows('Coaching Mode', role == 'client', 'the client row');
    _onlyNameOf(member);
  }, overrides: [
    clientPlanProvider.overrideWith((ref) async => ClientPlan.selfGuided),
  ]),
  _Site('Personal Info', () => const PersonalInfoScreen(), (role, member) {
    _shows('COACHING PROFILE', role == 'coach', 'the coach section');
    _shows('BODY METRICS', role != 'coach', 'the client section (also unknown)');
    expect(find.text('Alice'), member == 'user-a' ? findsOneWidget : findsNothing,
        reason: "A's first name in the form");
    expect(find.text('Bruno'), member == 'user-b' ? findsOneWidget : findsNothing,
        reason: "B's first name in the form");
  }),
];

void main() {
  late _Server server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    server.views.clear();
    server.clientGate = null;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

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
      // No realtime channel (its retry timer outlives the test).
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
      // AppScaffold's bell (a realtime stream) stays off the network.
      unreadCountProvider.overrideWith((ref) async => 0),
      ...site.overrides,
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => site.build()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
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

  for (final site in _sites) {
    group(site.name, () {
      final pairs = [
        ('coach', 'client'),
        ('client', 'coach'),
        if (site.adminMatters) ('admin', 'client'),
      ];

      for (final observe in [true, false]) {
        final how = observe ? 'sign-out observed' : 'same-frame switch';
        for (final (aRole, bRole) in pairs) {
          for (final bMode in _P.values) {
            testWidgets(
                '$aRole A → $bRole B ($how), B\'s read ${bMode.name}: never '
                "A's role", (tester) async {
              final p = _Profile(aRole, bRole)..modes['user-b'] = bMode;
              final c = await pump(tester, site, p);
              site.expectFor(aRole, 'user-a'); // precondition: A's own view

              await switchTo(tester, c, 'user-b', observeSignOut: observe);
              if (bMode == _P.server) {
                expect(c.read(currentUserProfileProvider).hasError, isTrue,
                    reason: "precondition: B's read really failed");
              }
              site.expectFor(bMode == _P.ok ? bRole : null,
                  bMode == _P.ok ? 'user-b' : null);
              await unmount(tester);
            });
          }
        }
      }

      for (final (aRole, bRole) in pairs) {
        for (final slow in const ['first', 'refresh']) {
          for (final bMode in const [_P.ok, _P.server]) {
            testWidgets(
                "$aRole A's slow $slow read lands after $bRole B signed in "
                "(B's read ${bMode.name}): A's late answer is never B's role",
                (tester) async {
              const lag = Duration(seconds: 5);
              final p = _Profile(aRole, bRole)..modes['user-b'] = bMode;
              if (slow == 'first') p.delays['user-a'] = lag;
              final c = await pump(tester, site, p);
              if (slow == 'first') {
                site.expectFor(null, null);
              } else {
                site.expectFor(aRole, 'user-a');
                p.delays['user-a'] = lag;
                c.invalidate(currentUserProfileProvider);
                await settle(tester);
              }
              await switchTo(tester, c, 'user-b', observeSignOut: false);
              void expectB() => site.expectFor(
                  bMode == _P.ok ? bRole : null, bMode == _P.ok ? 'user-b' : null);
              expectB();
              await tester.pump(lag);
              await settle(tester);
              expect(p.answered.where((u) => u == 'user-a').length,
                  slow == 'first' ? 1 : 2,
                  reason: "precondition: A's late answer really arrived");
              expectB();
              await unmount(tester);
            });
          }
        }
      }

      testWidgets('A signs out, nobody signs in: nothing of A\'s role remains',
          (tester) async {
        final p = _Profile(pairs.first.$1, 'client');
        final c = await pump(tester, site, p);
        site.expectFor(pairs.first.$1, 'user-a');
        c.read(_signedIn.notifier).state = null;
        await settle(tester);
        // Signed out, the provider answers "no profile" (null) for nobody: no
        // role, no name.
        for (final t in ['New Class', 'New Exercise', 'Edit', 'Regenerate with AI',
            'Create Exercise', 'Coach', 'Coach Dashboard', 'COACHING PROFILE',
            'Add your coaching — a focus, a note, your own video']) {
          expect(find.text(t), findsNothing, reason: '"$t" was A\'s');
        }
        expect(find.textContaining('Alice'), findsNothing);
        await unmount(tester);
      });

      testWidgets('a refresh that FAILS after a good read of the SAME member '
          'keeps that member\'s role', (tester) async {
        final role = pairs.first.$1;
        final p = _Profile(role, 'client');
        final c = await pump(tester, site, p);
        site.expectFor(role, 'user-a');
        p.mode = _P.server;
        c.invalidate(currentUserProfileProvider);
        await settle(tester);
        expect(c.read(currentUserProfileProvider).hasError, isTrue,
            reason: 'precondition: the refresh really failed');
        site.expectFor(role, 'user-a');
        await unmount(tester);
      });
    });
  }

  // Coach Focus read the role ONCE, in initState: a coach whose read was still
  // in flight got the client view until the screen was reopened.
  testWidgets('Coach Focus: a coach whose read lands AFTER the section opened '
      'gets the coach editor without reopening', (tester) async {
    final site = _sites.firstWhere((s) => s.name == 'Coach Focus');
    final p = _Profile('coach', 'client')
      ..delays['user-a'] = const Duration(seconds: 2);
    await pump(tester, site, p);
    site.expectFor(null, null);
    expect(server.views, isEmpty,
        reason: 'no view is read while the role is unknown');
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    site.expectFor('coach', 'user-a');
    expect(server.views, ['staff']);
    await unmount(tester);
  });

  testWidgets('Coach Focus: a client → coach switch reads the coach\'s own '
      'overlay, not the client view again', (tester) async {
    final site = _sites.firstWhere((s) => s.name == 'Coach Focus');
    final p = _Profile('client', 'coach');
    final c = await pump(tester, site, p);
    site.expectFor('client', 'user-a');
    await switchTo(tester, c, 'user-b', observeSignOut: false);
    site.expectFor('coach', 'user-b');
    expect(server.views, ['client', 'staff']);
    await unmount(tester);
  });

  // The lead's mutant `if (!mounted || _loadedKey != key) return;` ->
  // `if (!mounted) return;` survived: every overlay answer above was instant.
  // Here A's (client) overlay answer is HELD until after B (a coach) signed in;
  // it must not replace what B is shown.
  for (final bMode in const [_P.ok, _P.pending, _P.server]) {
    testWidgets("Coach Focus: client A's DELAYED overlay answer lands after "
        "coach B signed in (B's read ${bMode.name}): never shown to B",
        (tester) async {
      final site = _sites.firstWhere((s) => s.name == 'Coach Focus');
      final gate = Completer<void>();
      server.clientGate = gate;
      final p = _Profile('client', 'coach')..modes['user-b'] = bMode;
      final c = await pump(tester, site, p);
      expect(server.views, ['client'],
          reason: "precondition: A's overlay read is in flight");
      site.expectFor(null, null); // nothing shown before it answers
      await switchTo(tester, c, 'user-b', observeSignOut: false);
      final bRole = bMode == _P.ok ? 'coach' : null;
      site.expectFor(bRole, null);
      gate.complete(); // A's answer lands now
      await settle(tester);
      expect(server.views.first, 'client',
          reason: "precondition: A's late answer was the client view");
      site.expectFor(bRole, null);
      expect(find.textContaining('Slow on the way down'), findsNothing,
          reason: "A's coach focus shown to B");
      await unmount(tester);
    });
  }

  testWidgets("Coach Focus: A's DELAYED overlay answer lands after A signed "
      'out and nobody signed in: nothing is shown', (tester) async {
    final site = _sites.firstWhere((s) => s.name == 'Coach Focus');
    final gate = Completer<void>();
    server.clientGate = gate;
    final c = await pump(tester, site, _Profile('client', 'coach'));
    c.read(_signedIn.notifier).state = null;
    await settle(tester);
    gate.complete();
    await settle(tester);
    expect(find.text('COACH FOCUS TODAY'), findsNothing);
    expect(find.textContaining('Slow on the way down'), findsNothing);
    await unmount(tester);
  });

  testWidgets("Coach Focus: the SAME member's delayed answer still lands "
      '(control)', (tester) async {
    final site = _sites.firstWhere((s) => s.name == 'Coach Focus');
    final gate = Completer<void>();
    server.clientGate = gate;
    await pump(tester, site, _Profile('client', 'coach'));
    site.expectFor(null, null);
    gate.complete();
    await settle(tester);
    site.expectFor('client', 'user-a');
    await unmount(tester);
  });
}
