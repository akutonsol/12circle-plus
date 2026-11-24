import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:circle_fitness/features/exercise_database/data/models/exercise_detail_model.dart';
import 'package:circle_fitness/features/exercise_database/domain/custom_exercise_provider.dart';
import 'package:circle_fitness/features/exercise_database/domain/exercise_database_provider.dart';
import 'package:circle_fitness/features/exercise_database/presentation/exercise_detail_screen.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_focus_section.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/failing_reads_postgrest.dart';
import '../support/pump_until.dart';
import '../support/row_checking_postgrest.dart';
import '../support/rpc_answering_postgrest.dart';

// P0-FL-53a · the exercise library says a failure as one.
//
//  (a) Coach Focus: a FAILED overlay read was null = "no overlay", so a coach
//      was offered "Add your coaching" — and saving that blank editor
//      overwrote the overlay they have; a client silently saw no coaching.
//      The sheet's re-reads (after a voice note is cleared/recorded) did the
//      same.
//  (b) Saving a cue pack ignored the result: a failed save looked saved.
//  (d) AI enrichment showed the backend's raw error text, and a failed slug
//      back-fill went on to enrich a slug the exercise does not have.
//  ((c), the 0-row global-library submission, is in
//  test/unit/exercise_library_failures_test.dart.)
//
// HOW TO SEE THEM FAIL: `git checkout b7ec6ef --` custom_exercise_service.dart,
// coach_focus_section.dart and exercise_detail_screen.dart.

const _uid = '00000000-0000-4000-8000-0000000f5054';
const _otherwise = SectionLoadFailure.otherwiseHint;
const _generic = 'try again in a moment. If it keeps happening, contact support.';
const _addPrompt = 'Add your coaching — a focus, a note, your own video';

Map<String, dynamic> _overlayRow({String? voice}) => {
      'coach_id': _uid,
      'exercise_id': 'ex-1',
      'focus': ['Brace hard'],
      'note': 'Slow down',
      if (voice != null) 'voice_url': voice,
    };

void main() {
  late RpcAnsweringPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RpcAnsweringPostgrest(_uid);
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

  const section = Scaffold(
      body: SingleChildScrollView(child: CoachFocusSection(exerciseId: 'ex-1')));

  // ── (a) Coach Focus: the coach's own overlay ──────────────────────────────
  group('Coach Focus (coach)', () {
    testWidgets('a failed read is said, offers no authoring, and retry loads',
        (tester) async {
      server.failReads['coach_exercise_media'] = ReadFailure.server;
      await mount(tester, section);
      expect(find.text(_addPrompt), findsNothing,
          reason: 'THE defect: a failed read offered authoring over the real '
              'overlay');
      expect(find.byType(SectionLoadFailure), findsOneWidget, reason: 'one voice');
      expect(find.text("Couldn't load your coaching for this exercise"),
          findsOneWidget);
      expect(find.text('$_otherwise Editing is paused until it loads.'),
          findsOneWidget);
      expect(origins(), ['CustomExerciseService.getCoachOverlay']);

      final handle = tester.ensureSemantics();
      expect(
          tester.getSemantics(find.bySemanticsLabel(
              "Couldn't load your coaching for this exercise. $_otherwise "
              'Editing is paused until it loads.')),
          isSemantics(isLiveRegion: true));
      final retry =
          find.bySemanticsLabel('Try again: load your coaching for this exercise');
      expect(retry, findsOneWidget);
      handle.dispose();
      expect(tester.getSize(find.byType(TextButton)).height,
          greaterThanOrEqualTo(44));

      // Busy-aware: a second tap while the retry is in flight sends nothing.
      server.failReads.clear();
      server.reads['coach_exercise_media'] = _overlayRow();
      final before = server.readCounts['coach_exercise_media'] ?? 0;
      server.readGate = Completer<void>();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.text('Try again'), findsNothing, reason: 'busy while in flight');
      await tester.tap(find.byType(TextButton), warnIfMissed: false);
      await tester.pump();
      server.readGate!.complete();
      await tester.pumpAndSettle();
      expect(server.readCounts['coach_exercise_media'], before + 1);

      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('YOUR COACHING'), findsOneWidget);
      expect(find.text('Brace hard'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a network failure gets the connection hint', (tester) async {
      server.failReads['coach_exercise_media'] = ReadFailure.network;
      await mount(tester, section);
      // postgrest retries a connection failure on a (fake-clock) backoff.
      await pumpUntil(
          tester, () => find.byType(SectionLoadFailure).evaluate().isNotEmpty,
          what: 'the load-failure notice', step: const Duration(seconds: 1));
      expect(
          find.text('${SectionLoadFailure.networkHint} Editing is paused until '
              'it loads.'),
          findsOneWidget);
      expect(find.text(_addPrompt), findsNothing);
      await unmount(tester);
    });

    testWidgets('negative control: no overlay offers "Add your coaching"',
        (tester) async {
      await mount(tester, section);
      expect(find.text(_addPrompt), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(reported, isEmpty);
      await unmount(tester);
    });

    testWidgets('positive control: an overlay shows with Edit', (tester) async {
      server.reads['coach_exercise_media'] = _overlayRow();
      await mount(tester, section);
      expect(find.text('Brace hard'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'a failed refresh after a save keeps the overlay shown, says so and '
        'holds Edit', (tester) async {
      server.reads['coach_exercise_media'] = _overlayRow();
      await mount(tester, section);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Coach this exercise'), findsOneWidget);

      server.failReads['coach_exercise_media'] = ReadFailure.server;
      await tester.tap(find.text('Save coaching'));
      await tester.pumpAndSettle();
      expect(server.writes.where((w) => w.contains('coach_exercise_media')),
          hasLength(1));
      expect(find.text('Brace hard'), findsOneWidget,
          reason: 'what was shown is kept');
      expect(find.text("Couldn't load your coaching for this exercise"),
          findsOneWidget);
      expect(find.text('Edit'), findsNothing,
          reason: 'editing the stale copy could overwrite what was just saved');
      await unmount(tester);
    });
  });

  // ── (a) Coach Focus: the client's resolved overlay ────────────────────────
  group('Coach Focus (client)', () {
    testWidgets('a failed read is said — not silently nothing', (tester) async {
      server.rpcFailures['resolve_exercise_media'] = ReadFailure.server;
      await mount(tester, section, role: 'client');
      expect(find.text("Couldn't load your coach's focus"), findsOneWidget,
          reason: 'THE defect: a failed read looked like "no coaching"');
      expect(find.text(_otherwise), findsOneWidget, reason: 'no editing detail');
      expect(origins(), ['CustomExerciseService.resolveExerciseMedia']);

      server.rpcFailures.clear();
      server.rpcAnswers['resolve_exercise_media'] = {
        'has_coach_overlay': true,
        'focus': ['Brace hard'],
        'coach_name': 'Coach Sam',
      };
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('COACH FOCUS TODAY'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('negative control: no coach overlay shows nothing',
        (tester) async {
      server.rpcAnswers['resolve_exercise_media'] = {'has_coach_overlay': false};
      await mount(tester, section, role: 'client');
      expect(find.byType(SectionLoadFailure), findsNothing);
      expect(find.text('COACH FOCUS TODAY'), findsNothing);
      expect(reported, isEmpty);
      await unmount(tester);
    });
  });

  // ── (a) the sheet's re-read after a voice note is cleared ─────────────────
  group('Coach Focus sheet re-read', () {
    setUp(_mockAudioPlayers);
    tearDown(_unmockAudioPlayers);

    testWidgets('a failed re-read is said in place of the voice note',
        (tester) async {
      server.reads['coach_exercise_media'] =
          _overlayRow(voice: 'voice/$_uid/ex-1-1.m4a');
      await mount(tester, section);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

      server.failReads['coach_exercise_media'] = ReadFailure.server;
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your voice note"), findsOneWidget,
          reason: 'THE defect: the failed re-read was thrown away or shown '
              'as no voice note');
      expect(origins(), contains('CustomExerciseService.getCoachOverlay'));

      server.failReads.clear();
      server.reads['coach_exercise_media'] = _overlayRow();
      await tester.tap(find.bySemanticsLabel('Try again: load your voice note'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your voice note"), findsNothing);
      await unmount(tester);
    });
  });

  // ── (b) saving a cue pack ─────────────────────────────────────────────────
  group('Save these as a pack', () {
    Finder focusField() => find.byWidgetPredicate((w) =>
        w is TextField &&
        (w.decoration?.hintText ?? '').startsWith('Control the descent'));

    Future<void> saveAs(WidgetTester tester, String name) async {
      await tester.enterText(focusField(), 'Brace\nDrive');
      await tester.tap(find.text('＋ Save these as a pack'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
          name);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('a failed save is said; the sheet, cues and name are kept',
        (tester) async {
      await mount(tester, section);
      await tester.tap(find.text(_addPrompt));
      await tester.pumpAndSettle();
      server.mode = WriteMode.serverError;
      server.modeAppliesTo = (w) => w.contains('coach_coaching_packs');
      await saveAs(tester, 'Squat cues');

      expect(find.text("Couldn't save your cue pack — $_generic"), findsOneWidget,
          reason: 'THE defect: a failed save looked saved');
      final handle = tester.ensureSemantics();
      expect(
          tester.getSemantics(
              find.bySemanticsLabel("Couldn't save your cue pack — $_generic")),
          isSemantics(isLiveRegion: true));
      handle.dispose();
      expect(origins(), ['CustomExerciseService.createCoachingPack']);
      expect(find.text('Coach this exercise'), findsOneWidget);
      expect(tester.widget<TextField>(focusField()).controller!.text, 'Brace\nDrive');

      // The name typed is offered again.
      await tester.tap(find.text('＋ Save these as a pack'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: find.byType(AlertDialog), matching: find.byType(TextField)))
              .controller!
              .text,
          'Squat cues');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('positive control: a saved pack appears, nothing is said',
        (tester) async {
      await mount(tester, section);
      await tester.tap(find.text(_addPrompt));
      await tester.pumpAndSettle();
      server.reads['coach_coaching_packs'] = [
        {'id': 'p1', 'name': 'Squat cues', 'cues': ['Brace', 'Drive']}
      ];
      await saveAs(tester, 'Squat cues');
      expect(find.textContaining("Couldn't save"), findsNothing);
      expect(find.text('Squat cues'), findsOneWidget);
      expect(server.writes.single, contains('select=id'));
      expect(reported, isEmpty);
      await unmount(tester);
    });
  });

  // ── (d) AI enrichment ─────────────────────────────────────────────────────
  group('Enrich with AI', () {
    ExerciseDetail exercise({String? slug}) => ExerciseDetail.fromJson({
          'id': 'ex-1',
          'name': 'Goblet Squat',
          if (slug != null) 'slug': slug,
        });
    List<Override> overrides(_EnrichSvc svc, ExerciseDetail ex) => [
          customExerciseSvcProvider.overrideWithValue(svc),
          selectedExerciseDetailProvider.overrideWith((ref) => ex),
        ];

    testWidgets('a failed enrichment is said in one voice, never raw',
        (tester) async {
      const leak = 'upstream 429: quota exceeded for key sk-live-abc';
      final svc = _EnrichSvc(result: (ok: false, error: leak));
      await mount(tester, const ExerciseDetailScreen(),
          role: 'admin', overrides: overrides(svc, exercise(slug: 'goblet-squat')));
      await tester.tap(find.text('Enrich with AI'));
      await tester.pumpAndSettle();
      expect(find.textContaining('quota'), findsNothing,
          reason: 'THE defect: the backend text was shown');
      expect(find.text("Couldn't generate coaching content — $_generic"),
          findsOneWidget);
      expect(reported, isEmpty,
          reason: 'P0-FL-57a · the service (faked here) records it, once');
      expect(find.text('Enrich with AI'), findsOneWidget, reason: 'can try again');
      await unmount(tester);
    });

    testWidgets('a failed slug back-fill stops before enriching, and is said',
        (tester) async {
      final svc = _EnrichSvc(result: (ok: true, error: null));
      server.mode = WriteMode.zeroRows;
      await mount(tester, const ExerciseDetailScreen(),
          role: 'admin', overrides: overrides(svc, exercise()));
      await tester.tap(find.text('Enrich with AI'));
      await tester.pumpAndSettle();
      expect(svc.enriched, isEmpty,
          reason: 'THE defect: enrichment ran for a slug that was never saved');
      expect(
          find.text("Couldn't prepare this exercise for AI enrichment — $_generic"),
          findsOneWidget);
      expect(find.text('Coaching content generated ✨'), findsNothing);
      // P0-FL-57a · the service records the failed write, once.
      expect(origins(), ['CustomExerciseService.updateExercise']);
      await unmount(tester);
    });

    testWidgets('positive control: back-fill saved, enrichment runs on it',
        (tester) async {
      final svc = _EnrichSvc(result: (ok: true, error: null));
      server.reads['custom_exercises'] = {'id': 'ex-1', 'name': 'Goblet Squat'};
      await mount(tester, const ExerciseDetailScreen(),
          role: 'admin', overrides: overrides(svc, exercise()));
      await tester.tap(find.text('Enrich with AI'));
      await tester.pumpAndSettle();
      expect(server.writes.single, contains('"slug":"goblet-squat"'));
      expect(svc.enriched, ['goblet-squat']);
      expect(find.text('REOPENED DETAIL'), findsOneWidget);
      expect(reported, isEmpty);
      await unmount(tester);
    });
  });
}

class _EnrichSvc extends CustomExerciseService {
  _EnrichSvc({required this.result});
  final ({bool ok, String? error}) result;
  final enriched = <String>[];
  @override
  Future<({bool ok, String? error})> enrichWithAI(String slug) async {
    enriched.add(slug);
    return result;
  }
}

// audioplayers talks to its platform side over these channels; a widget test
// has none, so they answer null (CoachVoicePlayer is only constructed here).
const _audioChannels = [
  'xyz.luan/audioplayers',
  'xyz.luan/audioplayers.global',
  'xyz.luan/audioplayers.global/events',
];

void _mockAudioPlayers() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final c in _audioChannels) {
    m.setMockMethodCallHandler(MethodChannel(c), (_) async => null);
  }
}

void _unmockAudioPlayers() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final c in _audioChannels) {
    m.setMockMethodCallHandler(MethodChannel(c), null);
  }
}
