import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/admin/presentation/exercise_review_screen.dart';
import 'package:circle_fitness/features/admin/presentation/observability_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:circle_fitness/features/exercise_database/data/models/exercise_detail_model.dart';
import 'package:circle_fitness/features/exercise_database/domain/custom_exercise_provider.dart';
import 'package:circle_fitness/features/exercise_database/domain/exercise_database_provider.dart';
import 'package:circle_fitness/features/exercise_database/presentation/create_exercise_screen.dart';
import 'package:circle_fitness/features/exercise_database/presentation/exercise_detail_screen.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_focus_section.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/swap_substitutes_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/failing_reads_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-50a · the callers of CustomExerciseService say a failure as one.
//
//  * Global Library Review: a failed pending read said "No pending
//    submissions." — an admin would think the queue was clear. A refused or
//    0-row approve/reject said "approved" (the update never asked for its row)
//    or the vague "Action failed".
//  * Coaching Observability: a failed count rendered as 0 — a false KPI.
//  * Coach Focus editor: a failed packs read looked like having no packs.
//  * Edit Exercise: a failed prefill left a BLANK form, and Save (once a name
//    was typed) wrote it over the exercise.
//  * Exercise detail: a failed re-read after AI enrichment was silent.
//  * Active-workout swap: a failed global read said "No substitutes found."
//
// HOW TO SEE THEM FAIL: `git checkout 1b94044 --` the service, the provider,
// exercise_review_screen, observability_screen, coach_focus_section,
// create_exercise_screen, exercise_detail_screen and active_workout_screen.
// (SwapSubstitutesList is new — its swap-path proof on the base is the
// service test's getSubstitutes case; here it pins the sheet's states.)

const _uid = '00000000-0000-4000-8000-0000000f5051';
const _generic = 'try again in a moment. If it keeps happening, contact support.';

Map<String, dynamic> _pendingRow() => {
      'id': 'ex-1',
      'name': 'Goblet Squat',
      'muscle_group': 'Legs',
      'equipment': 'Dumbbell',
      'difficulty': 'Beginner',
      'submission_status': 'pending',
      'visibility': 'private',
    };

void main() {
  late FailingReadsPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = FailingReadsPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  List<String> origins() => reported.map((f) => f.origin).toList();

  Future<void> mount(WidgetTester tester, Widget home,
      {String role = 'coach', List<Override> overrides = const []}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => home),
      GoRoute(
          path: '/exercise-detail',
          builder: (_, __) => const Scaffold(body: Text('REOPENED DETAIL'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider
            .overrideWithValue(Supabase.instance.client.auth.currentUser),
        currentUserProfileProvider
            .overrideWith((ref) async => {'id': _uid, 'role': role}),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  // ── Global Library Review ─────────────────────────────────────────────────
  group('Global Library Review', () {
    testWidgets('a failed queue read says so — not "No pending submissions."',
        (tester) async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      await mount(tester, const ExerciseReviewScreen(), role: 'admin');
      expect(find.text('No pending submissions.'), findsNothing,
          reason: 'THE defect: a failed read was shown as an empty queue');
      expect(find.text("Couldn't load the submissions — $_generic"), findsOneWidget);
      expect(origins(), ['CustomExerciseService.getPendingGlobalSubmissions']);
      expect(find.bySemanticsLabel('Try loading the submissions again'), findsOneWidget);
      expect(tester.getSize(find.byType(TextButton)).height, greaterThanOrEqualTo(44));
      await unmount(tester);
    });

    testWidgets('retry is busy-aware and recovers to the real (empty) answer',
        (tester) async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      await mount(tester, const ExerciseReviewScreen(), role: 'admin');
      expect(server.readCounts['custom_exercises'], 1);

      server.failReads.clear();
      server.readGate = Completer<void>();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      // Whatever is on screen now, a second tap cannot start a second read.
      if (find.text('Try again').evaluate().isNotEmpty) {
        await tester.tap(find.text('Try again'), warnIfMissed: false);
        await tester.pump();
      }
      expect(server.readCounts['custom_exercises'], 2);
      server.readGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('No pending submissions.'), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
      await unmount(tester);
    });

    testWidgets('a connection failure says check your connection', (tester) async {
      server.failReads['custom_exercises'] = ReadFailure.network;
      await mount(tester, const ExerciseReviewScreen(), role: 'admin');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
          find.text("Couldn't load the submissions — check your connection and try again."),
          findsOneWidget);
      await unmount(tester);
    });

    testWidgets('an empty queue is still "No pending submissions."', (tester) async {
      await mount(tester, const ExerciseReviewScreen(), role: 'admin');
      expect(find.text('No pending submissions.'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
      await unmount(tester);
    });

    for (final approve in [true, false]) {
      final verb = approve ? 'approve' : 'reject';
      testWidgets('a 0-row $verb says it did not happen', (tester) async {
        server.reads['custom_exercises'] = [_pendingRow()];
        server.mode = WriteMode.zeroRows;
        await mount(tester, const ExerciseReviewScreen(), role: 'admin');
        await tester.tap(find.text(approve ? 'Approve' : 'Reject'));
        await tester.pumpAndSettle();
        expect(find.text('Couldn\'t $verb "Goblet Squat" — $_generic'), findsOneWidget);
        expect(find.textContaining('approved to the global library'), findsNothing);
        expect(origins(),
            ['CustomExerciseService.${approve ? 'approve' : 'reject'}GlobalExercise']);
        expect(find.text('Goblet Squat'), findsOneWidget, reason: 'still pending');
        await unmount(tester);
      });
    }

    testWidgets('a confirmed approve still says approved', (tester) async {
      server.reads['custom_exercises'] = [_pendingRow()];
      await mount(tester, const ExerciseReviewScreen(), role: 'admin');
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(find.text('"Goblet Squat" approved to the global library.'), findsOneWidget);
      expect(reported, isEmpty);
      await unmount(tester);
    });
  });

  // ── Coaching Observability ────────────────────────────────────────────────
  group('Coaching Observability', () {
    Finder kpiValue(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
        matching: find.byWidgetPredicate((w) => w is Text && w.data != label));

    String valueOf(WidgetTester tester, String label) =>
        (tester.widget(kpiValue(label).first) as Text).data!;

    testWidgets('a failed count is "—" with a notice, never 0', (tester) async {
      server.failReads['workout_programs'] = ReadFailure.server;
      await mount(tester, const ObservabilityScreen(), role: 'admin');
      expect(valueOf(tester, 'PROGRAMS GENERATED'), '—',
          reason: 'THE defect: a failed count was shown as 0');
      expect(valueOf(tester, 'DECISION TRACES'), '0', reason: 'answered: 0 is a fact');
      expect(find.text("Couldn't load 1 figure — $_generic Those show as —."),
          findsOneWidget);
      expect(origins(),
          ['CustomExerciseService.platformObservability.programs_generated']);

      // Retry re-reads; once it answers, the notice goes and the figure shows.
      server.failReads.clear();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(valueOf(tester, 'PROGRAMS GENERATED'), '0');
      await unmount(tester);
    });

    testWidgets('everything answered: no notice', (tester) async {
      await mount(tester, const ObservabilityScreen(), role: 'admin');
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(valueOf(tester, 'PROGRAMS GENERATED'), '0');
      expect(reported, isEmpty);
      await unmount(tester);
    });
  });

  // ── Coach Focus: cue packs ────────────────────────────────────────────────
  group('Coach Focus editor packs', () {
    Future<void> openEditor(WidgetTester tester) async {
      await mount(
          tester,
          const Scaffold(
              body: SingleChildScrollView(child: CoachFocusSection(exerciseId: 'ex-1'))));
      await tester.tap(find.text('Add your coaching — a focus, a note, your own video'));
      await tester.pumpAndSettle();
      expect(find.text('Coach this exercise'), findsOneWidget);
    }

    testWidgets('a failed packs read says so, and retry loads them', (tester) async {
      server.failReads['coach_coaching_packs'] = ReadFailure.server;
      await openEditor(tester);
      expect(find.text("Couldn't load your cue packs — $_generic"), findsOneWidget,
          reason: 'THE defect: a failed read looked like having no packs');
      expect(origins(), ['CustomExerciseService.getCoachingPacks']);

      server.failReads.clear();
      server.reads['coach_coaching_packs'] = [
        {'id': 'p1', 'name': 'Squat cues', 'cues': ['Brace']}
      ];
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('APPLY A PACK'), findsOneWidget);
      expect(find.text('Squat cues'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('no packs: no notice, no pack list', (tester) async {
      await openEditor(tester);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('APPLY A PACK'), findsNothing);
      expect(reported, isEmpty);
      await unmount(tester);
    });
  });

  // ── Edit Exercise prefill ─────────────────────────────────────────────────
  group('Edit Exercise prefill', () {
    final editing = [editingExerciseProvider.overrideWith((ref) => 'ex-1')];

    testWidgets('a failed prefill is said, Save is held, retry fills the form',
        (tester) async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      await mount(tester, const CreateExerciseScreen(), overrides: editing);
      expect(
          find.text("Couldn't load this exercise — $_generic Saving is paused until it loads."),
          findsOneWidget,
          reason: 'THE defect: a failed read left a blank form presented as the exercise');
      expect(origins(), ['CustomExerciseService.getRawById']);

      // A coach types a name into the blank form and saves: nothing is written.
      await tester.enterText(find.byType(TextFormField).first, 'Goblet Squat');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(server.writes, isEmpty,
          reason: 'a blank form must never be saved over the exercise');

      server.failReads.clear();
      server.reads['custom_exercises'] = {
        'id': 'ex-1',
        'name': 'Cossack Squat',
        'coach_id': _uid,
        'visibility': 'private',
      };
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('Cossack Squat'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('no such exercise: said, and Save is held', (tester) async {
      await mount(tester, const CreateExerciseScreen(), overrides: editing);
      expect(find.textContaining("This exercise wasn't found"), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Goblet Squat');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(server.writes, isEmpty);
      expect(reported, isEmpty);
      await unmount(tester);
    });

    testWidgets('a loaded exercise prefills with no notice', (tester) async {
      server.reads['custom_exercises'] = {
        'id': 'ex-1',
        'name': 'Cossack Squat',
        'coach_id': _uid,
        'visibility': 'private',
      };
      await mount(tester, const CreateExerciseScreen(), overrides: editing);
      expect(find.text('Cossack Squat'), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.textContaining("wasn't found"), findsNothing);
      await unmount(tester);
    });
  });

  // ── Exercise detail: refresh after enrichment ─────────────────────────────
  group('Exercise detail refresh after AI enrichment', () {
    final exercise = ExerciseDetail.fromJson({
      'id': 'ex-1',
      'name': 'Goblet Squat',
      'slug': 'goblet-squat',
      'instructions': ['Brace'],
    });
    List<Override> overrides() => [
          customExerciseSvcProvider.overrideWithValue(_EnrichOkSvc()),
          selectedExerciseDetailProvider.overrideWith((ref) => exercise),
        ];

    testWidgets('a failed re-read is said, not silent', (tester) async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      await mount(tester, const ExerciseDetailScreen(),
          role: 'admin', overrides: overrides());
      await tester.tap(find.text('Regenerate with AI'));
      await tester.pumpAndSettle();
      expect(
          find.text("Coaching content generated. Couldn't refresh this page — go "
              'back and reopen the exercise to see it.'),
          findsOneWidget);
      expect(origins(), contains('CustomExerciseService.getExerciseBySlug'));
      await unmount(tester);
    });

    testWidgets('a successful re-read reopens the detail', (tester) async {
      server.reads['custom_exercises'] = {'id': 'ex-1', 'name': 'Goblet Squat'};
      await mount(tester, const ExerciseDetailScreen(),
          role: 'admin', overrides: overrides());
      await tester.tap(find.text('Regenerate with AI'));
      await tester.pumpAndSettle();
      expect(find.text('REOPENED DETAIL'), findsOneWidget);
      expect(find.textContaining("Couldn't refresh"), findsNothing);
      await unmount(tester);
    });
  });

  // ── Active-workout swap: substitutes ──────────────────────────────────────
  group('Swap substitutes', () {
    Future<void> pumpList(WidgetTester tester,
        {List<Map<String, dynamic>> library = const [],
        required Future<List<Map<String, dynamic>>> Function() load}) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        Flexible(
            child: SwapSubstitutesList(
                librarySubs: library, loadGlobal: load, onPick: (_) {})),
      ]))));
      await tester.pumpAndSettle();
    }

    testWidgets('a failed read (via the service) is said and recorded',
        (tester) async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      await pumpList(tester,
          load: () => CustomExerciseService().getSubstitutes('Goblet Squat', 'Legs'));
      expect(find.text('No substitutes found.'), findsNothing,
          reason: 'THE defect: a failed read said there were none');
      expect(find.text("Couldn't load substitutes — $_generic"), findsOneWidget);
      expect(origins(), ['CustomExerciseService.getSubstitutes']);
    });

    testWidgets('retry is busy-aware and shows what loads', (tester) async {
      var calls = 0;
      Completer<List<Map<String, dynamic>>>? pending;
      await pumpList(tester, load: () {
        calls++;
        if (calls == 1) return Future.error(StateError('refused'));
        pending = Completer();
        return pending!.future;
      });
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.text('Try again'), findsNothing, reason: 'no second fire');
      expect(calls, 2);
      pending!.complete([
        {'name': 'Split Squat', 'equipment': 'Dumbbell', 'difficulty': 'Beginner'}
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Split Squat'), findsOneWidget);
    });

    testWidgets('none found is still "No substitutes found."', (tester) async {
      await pumpList(tester,
          load: () => CustomExerciseService().getSubstitutes('Goblet Squat', 'Legs'));
      expect(find.text('No substitutes found.'), findsOneWidget);
      expect(reported, isEmpty);
    });

    testWidgets('library matches are shown without a global read', (tester) async {
      var calls = 0;
      await pumpList(tester, library: [
        {'name': 'Lunge', 'equipment': '', 'difficulty': ''}
      ], load: () async {
        calls++;
        return const [];
      });
      expect(find.text('Lunge'), findsOneWidget);
      expect(calls, 0);
    });
  });
}

class _EnrichOkSvc extends CustomExerciseService {
  @override
  Future<({bool ok, String? error})> enrichWithAI(String slug) async =>
      (ok: true, error: null);
}
