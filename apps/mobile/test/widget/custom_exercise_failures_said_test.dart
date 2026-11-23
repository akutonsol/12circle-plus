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
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/swap_substitutes_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
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
const _otherwise = SectionLoadFailure.otherwiseHint;

/// The shared notice (SectionLoadFailure) for [what], said as one sentence.
Finder _notice(String what, {String hint = _otherwise, String? detail}) =>
    find.bySemanticsLabel(
        "Couldn't load $what. $hint${detail == null ? '' : ' $detail'}");

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
      {String role = 'coach',
      List<Override> overrides = const [],
      Size size = const Size(900, 2400),
      bool settle = true}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
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
      final handle = tester.ensureSemantics();
      expect(find.byType(SectionLoadFailure), findsOneWidget, reason: 'one voice');
      expect(find.text("Couldn't load the submissions"), findsOneWidget);
      expect(_notice('the submissions'), findsOneWidget);
      expect(origins(), ['CustomExerciseService.getPendingGlobalSubmissions']);
      expect(find.bySemanticsLabel('Try again: load the submissions'), findsOneWidget);
      handle.dispose();
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
      // The notice stays while the retry is in flight, busy (no second fire).
      expect(find.byType(SectionLoadFailure), findsOneWidget);
      expect(tester.widget<SectionLoadFailure>(find.byType(SectionLoadFailure)).busy, isTrue);
      await tester.tap(find.byType(TextButton), warnIfMissed: false);
      await tester.pump();
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
      expect(find.text(SectionLoadFailure.networkHint), findsOneWidget);
      expect(find.text(_otherwise), findsNothing);
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
      expect(find.byType(SectionLoadFailure), findsOneWidget, reason: 'one voice');
      expect(find.text("Couldn't load 1 figure"), findsOneWidget);
      expect(find.text('$_otherwise Those show as —.'), findsOneWidget);
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
      expect(find.text("Couldn't load your cue packs"), findsOneWidget,
          reason: 'THE defect: a failed read looked like having no packs');
      expect(find.byType(SectionLoadFailure), findsOneWidget, reason: 'one voice');
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
      expect(find.text("Couldn't load this exercise"), findsOneWidget,
          reason: 'THE defect: a failed read left a blank form presented as the exercise');
      expect(find.text('$_otherwise Saving is paused until it loads.'), findsOneWidget);
      expect(find.byType(SectionLoadFailure), findsOneWidget, reason: 'one voice');
      expect(origins(), ['CustomExerciseService.getRawById']);

      // The blank form takes no input, and Save writes nothing.
      expect(find.byType(TextFormField).first.hitTestable(), findsNothing);
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
      expect(find.byType(TextFormField).first.hitTestable(), findsNothing);
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
                librarySubs: library,
                loadGlobal: load,
                onPick: (_) {},
                text: Colors.white,
                muted: Colors.grey,
                accent: Colors.purple)),
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
      expect(find.text("Couldn't load substitutes"), findsOneWidget);
      expect(find.byType(SectionLoadFailure), findsOneWidget, reason: 'one voice');
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
      expect(tester.widget<SectionLoadFailure>(find.byType(SectionLoadFailure)).busy, isTrue,
          reason: 'the notice stays, busy, while the retry runs');
      await tester.tap(find.byType(TextButton), warnIfMissed: false);
      await tester.pump();
      expect(calls, 2, reason: 'no second fire');
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

  // ── Round 2 (UX / QA / lead-mutant findings) ──────────────────────────────
  group('Edit Exercise Save is held while the prefill is pending', () {
    final editing = [editingExerciseProvider.overrideWith((ref) => 'ex-1')];
    final loadedRow = {
      'id': 'ex-1',
      'name': 'Cossack Squat',
      'coach_id': _uid,
      'visibility': 'private',
    };

    Iterable<String> patches() => server.writes
        .where((w) => w.startsWith('PATCH') && w.contains('/custom_exercises'));

    // The surviving lead mutant gave Save its tap back while the prefill was
    // pending (`onTap: _saving ? null : _save`). Save must be ANNOUNCED
    // disabled, carry NO tap action, and a tap must write nothing.
    Future<void> expectSaveHeld(WidgetTester tester) async {
      final handle = tester.ensureSemantics();
      final save = find.bySemanticsLabel('Save');
      expect(save, findsOneWidget);
      expect(
          tester.getSemantics(save),
          isSemantics(
              label: 'Save',
              isButton: true,
              hasEnabledState: true,
              isEnabled: false,
              hasTapAction: false));
      await tester.tap(find.text('Save'), warnIfMissed: false);
      await tester.pump();
      expect(server.writes, isEmpty, reason: 'nothing is saved over the exercise');
      expect(find.byType(TextFormField).first.hitTestable(), findsNothing,
          reason: 'the form takes no input until the exercise has loaded');
      handle.dispose();
    }

    testWidgets('LOADING (read in flight): announced disabled, no write',
        (tester) async {
      server.reads['custom_exercises'] = loadedRow;
      server.readGate = Completer<void>();
      await mount(tester, const CreateExerciseScreen(),
          overrides: editing, settle: false);
      expect(find.text('Loading the exercise…'), findsOneWidget);
      await expectSaveHeld(tester);
      server.readGate!.complete();
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('FAILED: announced disabled, no write', (tester) async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      await mount(tester, const CreateExerciseScreen(), overrides: editing);
      expect(find.text("Couldn't load this exercise"), findsOneWidget);
      await expectSaveHeld(tester);
      await unmount(tester);
    });

    testWidgets('MISSING: announced disabled, no write', (tester) async {
      await mount(tester, const CreateExerciseScreen(), overrides: editing);
      expect(find.textContaining("This exercise wasn't found"), findsOneWidget);
      await expectSaveHeld(tester);
      await unmount(tester);
    });

    testWidgets('POSITIVE CONTROL: once loaded, Save is enabled and writes one PATCH',
        (tester) async {
      server.reads['custom_exercises'] = loadedRow;
      await mount(tester, const CreateExerciseScreen(), overrides: editing);
      expect(find.text('Cossack Squat'), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(
          tester.getSemantics(find.bySemanticsLabel('Save')),
          isSemantics(
              label: 'Save',
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              hasTapAction: true));
      expect(find.byType(TextFormField).first.hitTestable(), findsOneWidget);
      handle.dispose();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // The text-content update of THIS row (the media step patches it too).
      expect(
          patches()
              .where((w) =>
                  w.contains('id=eq.ex-1') && w.contains('"name":"Cossack Squat"'))
              .length,
          1,
          reason: 'the no-write checks above can fail: a loaded form does save');
      await unmount(tester);
    });

    testWidgets('a retry of a failed prefill keeps the notice, busy', (tester) async {
      server.failReads['custom_exercises'] = ReadFailure.server;
      await mount(tester, const CreateExerciseScreen(), overrides: editing);
      server.failReads.clear();
      server.reads['custom_exercises'] = loadedRow;
      server.readGate = Completer<void>();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(tester.widget<SectionLoadFailure>(find.byType(SectionLoadFailure)).busy,
          isTrue);
      await tester.tap(
          find.descendant(
              of: find.byType(SectionLoadFailure), matching: find.byType(TextButton)),
          warnIfMissed: false);
      await tester.pump();
      expect(server.readCounts['custom_exercises'], 2, reason: 'no second fire');
      server.readGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Cossack Squat'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the failed banner fits 320dp at 2.0x text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      server.failReads['custom_exercises'] = ReadFailure.server;
      await mount(tester, const CreateExerciseScreen(),
          overrides: editing, size: const Size(320, 1400));
      expect(find.text("Couldn't load this exercise"), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      await unmount(tester);
    });
  });

  group('Coaching Observability unknown figures', () {
    testWidgets('a failed or null figure is a NEUTRAL "—", announced unavailable',
        (tester) async {
      server.failReads['workout_programs'] = ReadFailure.server;
      await mount(tester, const ObservabilityScreen(), role: 'admin');
      final handle = tester.ensureSemantics();
      Text valueText(String label) => tester.widget<Text>(find
          .descendant(
              of: find
                  .ancestor(of: find.text(label), matching: find.byType(Column))
                  .first,
              matching: find.byWidgetPredicate((w) => w is Text && w.data != label))
          .first);
      Color labelColor(String label) =>
          tester.widget<Text>(find.text(label)).style!.color!;
      // A failed count (was drawn in the brand colour) and a null average.
      for (final label in ['Programs generated', 'Avg client adherence']) {
        final upper = label.toUpperCase();
        expect(valueText(upper).data, '—');
        expect(valueText(upper).style!.color, labelColor(upper),
            reason: '$label: an unknown figure is neutral, not graded');
        expect(find.bySemanticsLabel('$label: unavailable'), findsOneWidget);
      }
      // An answered figure is not called unavailable.
      expect(find.bySemanticsLabel('Decision traces: unavailable'), findsNothing);
      handle.dispose();
      await unmount(tester);
    });

    testWidgets('the failed-figures banner fits 320dp at 2.0x text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      server.failReads['workout_programs'] = ReadFailure.server;
      await mount(tester, const ObservabilityScreen(),
          role: 'admin', size: const Size(320, 3000));
      expect(find.text("Couldn't load 1 figure"), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      await unmount(tester);
    });

    testWidgets('its retry keeps the notice on screen, busy', (tester) async {
      server.failReads['workout_programs'] = ReadFailure.server;
      await mount(tester, const ObservabilityScreen(), role: 'admin');
      server.readGate = Completer<void>();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(tester.widget<SectionLoadFailure>(find.byType(SectionLoadFailure)).busy,
          isTrue);
      server.readGate!.complete();
      await tester.pumpAndSettle();
      await unmount(tester);
    });
  });

  // P0-FL-50a round 3 · large text must make the KPI readouts LARGER. A
  // FittedBox in a fixed-ratio cell shrank them back (~0.47 at 320dp/2.0x), so
  // the member's text setting did nothing. "No overflow" alone can't see that.
  group('Coaching Observability KPI tiles grow with text size', () {
    const labels = [
      'PROGRAMS GENERATED', 'DECISION TRACES', 'PREDICTIONS MADE',
      'WEEKLY REVIEWS SENT', 'AVG CLIENT ADHERENCE', 'AVG GOAL CONFIDENCE',
      'AVG RECOVERY (TRACED)', 'REVIEWS (ALL STATES)', 'EXERCISE CERTIFICATION',
      'WORKOUT-READY', 'INTELLIGENCE PROFILED', 'KNOWLEDGE CONFIDENCE',
    ];
    Finder column(String upper) =>
        find.ancestor(of: find.text(upper), matching: find.byType(Column)).first;
    Finder value(String upper) => find
        .descendant(
            of: column(upper),
            matching: find.byWidgetPredicate((w) => w is Text && w.data != upper))
        .first;
    Finder tile(String upper) =>
        find.ancestor(of: find.text(upper), matching: find.byType(Container)).first;

    // Rendered (on-screen, transform-aware) rects of a tile's value and label,
    // plus the tile's own size; fails on overflow or on any scale-down.
    Future<Map<String, Rect>> render(WidgetTester tester, double width, double scale) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await mount(tester, const ObservabilityScreen(),
          role: 'admin', size: Size(width, 8000));
      expect(tester.takeException(), isNull, reason: 'no overflow at ${width}dp ${scale}x');
      for (final l in labels) {
        for (final f in [value(l), find.text(l)]) {
          // getRect is transform-aware, getSize is not: equal ⇒ not scaled down.
          expect(tester.getRect(f).height, closeTo(tester.getSize(f).height, 0.01),
              reason: '$l at ${width}dp ${scale}x: the readout must not be shrunk');
        }
      }
      // The height of ONE rendered line of text (wrapping differs between the
      // one- and two-column layouts, so whole-box heights don't compare):
      // the paragraph's line height × any scale applied on the way to screen.
      double line(Finder f) {
        final p = tester.renderObject<RenderParagraph>(
            find.descendant(of: f, matching: find.byType(RichText)));
        final lineH = p.getFullHeightForCaret(const TextPosition(offset: 0));
        return lineH * tester.getRect(f).height / tester.getSize(f).height;
      }
      final t = tester.getRect(tile('PROGRAMS GENERATED'));
      final out = {
        'value': Rect.fromLTWH(0, 0, 0, line(value('PROGRAMS GENERATED'))),
        'label': Rect.fromLTWH(0, 0, 0, line(find.text('PROGRAMS GENERATED'))),
        'tile': t,
        // The tallest tile content in the first grid (what the row must hold).
        'content': Rect.fromLTWH(0, 0, 0, [
          for (final l in labels.take(4)) tester.getSize(column(l)).height
        ].reduce((a, b) => a > b ? a : b)),
      };
      await unmount(tester);
      return out;
    }

    for (final width in [320.0, 390.0]) {
      testWidgets('at ${width.toInt()}dp, 2.0x text renders the value and label >= 1.5x '
          'their 1.0x size, nothing shrunk at 1.0x/1.3x/2.0x', (tester) async {
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final one = await render(tester, width, 1.0);
        await render(tester, width, 1.3);
        final two = await render(tester, width, 2.0);
        expect(two['value']!.height, greaterThanOrEqualTo(one['value']!.height * 1.5),
            reason: 'THE defect: the value came out no larger than at 1.0x');
        expect(two['label']!.height, greaterThanOrEqualTo(one['label']!.height * 1.5),
            reason: 'THE defect: the label came out no larger than at 1.0x');
        expect(two['tile']!.height, greaterThan(one['tile']!.height),
            reason: 'the tile grows with the text');
      });

      testWidgets('at ${width.toInt()}dp, 1.0x keeps the original two-column '
          'width/2.2 tile (grown only if its content would not fit)', (tester) async {
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final out = await render(tester, width, 1.0);
        // ListView padding 16+16, crossAxisSpacing 8, childAspectRatio 2.2.
        final cellW = (width - 32 - 8) / 2;
        expect(out['tile']!.width, closeTo(cellW, 0.01), reason: 'two columns, same width');
        // Exactly the original height unless the content (+14 padding top and
        // bottom) is taller — then exactly tall enough, never shrunk.
        final contentH = (out['content']!.height + 28).ceilToDouble();
        expect(out['tile']!.height,
            closeTo(contentH > cellW / 2.2 ? contentH : cellW / 2.2, 0.01));
      });
    }
  });

  group('Swap substitutes loading', () {
    testWidgets('the spinner is a live region "Loading substitutes"', (tester) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        Flexible(
            child: SwapSubstitutesList(
                librarySubs: const [],
                loadGlobal: () => pending.future,
                onPick: (_) {},
                text: Colors.white,
                muted: Colors.grey,
                accent: Colors.purple)),
      ]))));
      await tester.pump();
      expect(tester.getSemantics(find.bySemanticsLabel('Loading substitutes')),
          isSemantics(label: 'Loading substitutes', isLiveRegion: true));
      pending.complete(const []);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Loading substitutes'), findsNothing);
      handle.dispose();
    });
  });

  group('SectionLoadFailure detail + couldntMessage (one source)', () {
    testWidgets('detail follows the hint in the text and the live region',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SectionLoadFailure(
                  what: 'this exercise',
                  error: StateError('x'),
                  busy: false,
                  onRetry: () {},
                  detail: 'Saving is paused until it loads.'))));
      expect(find.text('$_otherwise Saving is paused until it loads.'), findsOneWidget);
      expect(
          tester.getSemantics(
              _notice('this exercise', detail: 'Saving is paused until it loads.')),
          isSemantics(isLiveRegion: true));
      handle.dispose();
    });

    test('couldntMessage builds its next step from the shared hints', () {
      expect(couldntMessage('approve "X"', StateError('x')),
          'Couldn\'t approve "X" — $_generic');
      expect(_otherwise.substring(1), _generic.substring(1));
      expect(
          couldntMessage('load it', http.ClientException('Connection refused')),
          "Couldn't load it — check your connection and try again.");
    });
  });
}

class _EnrichOkSvc extends CustomExerciseService {
  @override
  Future<({bool ok, String? error})> enrichWithAI(String slug) async =>
      (ok: true, error: null);
}
