import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_focus_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/failing_reads_postgrest.dart';
import '../support/held_reads_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-53a round 2 · the Coach Focus sheet after review.
//
//  1. (UX F1) the sheet did not scroll: with its failure notices, at 2.0×
//     text, 320dp wide and the keyboard up it overflowed and Save was lost.
//  2. (UX F2/F3) a pack save in flight looked idle; its failure stayed up
//     after the cues were edited.
//  3. (S-53a-1) an OLDER successful overlay read landing after a NEWER failed
//     one cleared the failure and gave Edit back (and the reverse).
//  4. (a) "Save coaching" closed the sheet when the save failed, losing what
//     was typed; (b) a failed voice-note removal was ignored.
//  5. (QA gap) a 0-row cue-pack save through the sheet.
//
// HOW TO SEE THEM FAIL: `git checkout a9b4bb6 --` coach_focus_section.dart
// and custom_exercise_service.dart (5 passes there: it fails on b7ec6ef).

const _uid = '00000000-0000-4000-8000-0000000f5055';
const _generic = 'try again in a moment. If it keeps happening, contact support.';
const _voice = 'voice/$_uid/ex-1-1.m4a';

Map<String, dynamic> _row({String? voice, String note = 'Slow down'}) => {
      'coach_id': _uid,
      'exercise_id': 'ex-1',
      'focus': ['Brace hard'],
      'note': note,
      if (voice != null) 'voice_url': voice,
    };

void main() {
  late HeldReadsPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = HeldReadsPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    _mockAudioPlayers();
  });
  tearDown(() {
    resetFailureSink();
    _unmockAudioPlayers();
  });

  List<String> origins() => reported.map((f) => f.origin).toList();

  Future<void> mount(WidgetTester tester,
      {Size size = const Size(900, 2400)}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider
            .overrideWithValue(Supabase.instance.client.auth.currentUser),
        currentUserProfileProvider
            .overrideWith((ref) async => {'id': _uid, 'role': 'coach'}),
      ],
      child: const MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: CoachFocusSection(exerciseId: 'ex-1')))),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Coach this exercise'), findsOneWidget);
  }

  Finder focusField() => find.byWidgetPredicate((w) =>
      w is TextField &&
      (w.decoration?.hintText ?? '').startsWith('Control the descent'));
  Finder noteField() => find.byWidgetPredicate((w) =>
      w is TextField &&
      (w.decoration?.hintText ?? '').startsWith('A short message'));
  Finder dialogField() => find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(TextField));
  void expectLive(WidgetTester tester, String label) {
    final h = tester.ensureSemantics();
    expect(tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(isLiveRegion: true));
    h.dispose();
  }

  Future<void> savePack(WidgetTester tester, String name,
      {bool settle = true}) async {
    await tester.ensureVisible(find.text('＋ Save these as a pack'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('＋ Save these as a pack'));
    await tester.pumpAndSettle();
    await tester.enterText(dialogField(), name);
    await tester.tap(find.text('Save'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  // ── 1 · the sheet scrolls; Save stays reachable ───────────────────────────
  group('sheet at 320×640, 2.0× text, keyboard up, every failure shown', () {
    testWidgets('no overflow, and Save coaching is reachable and tappable',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      server.reads['coach_exercise_media'] = _row(voice: _voice);
      server.failReads['coach_coaching_packs'] = ReadFailure.server;
      await mount(tester, size: const Size(320, 640));
      await tester.ensureVisible(find.text('Edit'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load your cue packs"), findsOneWidget);

      // The voice-note re-read (and its removal) fail.
      server.failReads['coach_exercise_media'] = ReadFailure.server;
      await tester.ensureVisible(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load your voice note"), findsOneWidget);

      // The cue-pack save fails.
      await tester.ensureVisible(focusField());
      await tester.enterText(focusField(), 'Brace\nDrive');
      server.mode = WriteMode.serverError;
      server.modeAppliesTo = (w) => w.contains('coach_coaching_packs');
      await savePack(tester, 'Squat cues');
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't save your cue pack — $_generic"),
          findsOneWidget);

      // The keyboard comes up over all of that.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'THE defect: the sheet body overflowed');
      // The rendered text size is the requested 2.0× (nothing shrank it).
      final title = tester.renderObject<RenderParagraph>(
          find.text('Coach this exercise'));
      expect(title.textScaler.scale(18), 36);

      server.failReads.clear();
      server.mode = WriteMode.oneRow;
      server.modeAppliesTo = null;
      await tester.ensureVisible(find.text('Save coaching'));
      await tester.pumpAndSettle();
      expect(find.text('Save coaching').hitTestable(), findsOneWidget,
          reason: 'Save must be reachable, not clipped under the keyboard');
      await tester.tap(find.text('Save coaching'));
      await tester.pumpAndSettle();
      expect(
          server.writes.where((w) =>
              w.startsWith('POST') && w.contains('coach_exercise_media')),
          hasLength(1));
      expect(find.text('Coach this exercise'), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });

  // ── 2 · pack save: busy state; error clears on edit ───────────────────────
  group('Save these as a pack', () {
    testWidgets('a save in flight says "Saving pack…" (dimmed) and ignores taps',
        (tester) async {
      server.reads['coach_exercise_media'] = _row();
      await mount(tester);
      await openEditor(tester);
      await tester.enterText(focusField(), 'Brace\nDrive');
      server.gate = Completer<void>();
      await savePack(tester, 'Squat cues', settle: false);
      await tester.pump(const Duration(seconds: 1)); // the name dialog closes
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Saving pack…'), findsOneWidget,
          reason: 'THE defect: a save in flight looked idle');
      expect(find.text('＋ Save these as a pack'), findsNothing);
      final style = tester.widget<Text>(find.text('Saving pack…')).style!;
      expect(style.color!.a, lessThan(1), reason: 'dimmed while saving');
      expectLive(tester, 'Saving pack…');
      await tester.tap(find.text('Saving pack…'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing, reason: 'no second save');
      expect(server.writes.where((w) => w.contains('coach_coaching_packs')),
          hasLength(1));

      server.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('＋ Save these as a pack'), findsOneWidget);
      expect(find.textContaining("Couldn't save"), findsNothing);
      expect(reported, isEmpty);
      await unmount(tester);
    });

    testWidgets('a pack-save failure clears when the cues are edited',
        (tester) async {
      server.reads['coach_exercise_media'] = _row();
      await mount(tester);
      await openEditor(tester);
      await tester.enterText(focusField(), 'Brace\nDrive');
      server.mode = WriteMode.serverError;
      server.modeAppliesTo = (w) => w.contains('coach_coaching_packs');
      await savePack(tester, 'Squat cues');
      final msg = "Couldn't save your cue pack — $_generic";
      expect(find.text(msg), findsOneWidget);

      // Negative control: editing another field does not clear it.
      await tester.enterText(noteField(), 'Breathe');
      await tester.pump();
      expect(find.text(msg), findsOneWidget);

      await tester.enterText(focusField(), 'Brace\nDrive\nStand tall');
      await tester.pump();
      expect(find.text(msg), findsNothing,
          reason: 'THE defect: a stale failure stayed after the cues changed');
      await unmount(tester);
    });

    testWidgets('a 0-row pack save through the sheet is said (QA gap)',
        (tester) async {
      server.reads['coach_exercise_media'] = _row();
      await mount(tester);
      await openEditor(tester);
      await tester.enterText(focusField(), 'Brace\nDrive');
      server.mode = WriteMode.zeroRows;
      server.modeAppliesTo = (w) => w.contains('coach_coaching_packs');
      await savePack(tester, 'Squat cues');
      expect(find.text("Couldn't save your cue pack — $_generic"),
          findsOneWidget,
          reason: 'an insert that returned no row is not a saved pack');
      expect(origins(), ['CustomExerciseService.createCoachingPack']);
      expect(find.text('Coach this exercise'), findsOneWidget);
      expect(tester.widget<TextField>(focusField()).controller!.text,
          'Brace\nDrive');
      await unmount(tester);
    });
  });

  // ── 3 · overlapping overlay reads: only the newest applies ────────────────
  group('overlapping overlay reads', () {
    /// Opens the sheet, removes the voice note (its section reload, read A,
    /// stays in flight) and saves (read B, newer, in flight too).
    Future<void> twoReadsInFlight(WidgetTester tester) async {
      server.reads['coach_exercise_media'] = _row(voice: _voice);
      await mount(tester);
      await openEditor(tester);
      server.holdTable = 'coach_exercise_media';
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pump();
      server.held[0].complete(true); // clearCoachVoice reads the voice_url
      await tester.pump();
      await tester.pump();
      server.reads['coach_exercise_media'] = _row();
      for (var i = 0; i < 20 && server.held.length < 2; i++) {
        await tester.pump();
      }
      server.held[1].complete(true); // the sheet's re-read
      for (var i = 0; i < 20 && server.held.length < 3; i++) {
        await tester.pump();
      }
      expect(server.held, hasLength(3), reason: 'read A in flight');
      await tester.tap(find.text('Save coaching'));
      for (var i = 0; i < 20 && server.held.length < 4; i++) {
        await tester.pump();
      }
      expect(server.held, hasLength(4), reason: 'read B in flight');
      await tester.pump(const Duration(seconds: 1)); // the sheet closes
      expect(find.text('Coach this exercise'), findsNothing);
    }

    testWidgets('an older success after a newer failure keeps the failure',
        (tester) async {
      await twoReadsInFlight(tester);
      server.held[3].complete(false); // B (newest) fails
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your coaching for this exercise"),
          findsOneWidget);
      server.held[2].complete(true); // A (older) succeeds, late
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your coaching for this exercise"),
          findsOneWidget,
          reason: 'THE defect: an older read cleared the newer failure');
      expect(find.text('Edit'), findsNothing,
          reason: 'editing stays held while the newest read failed');
      await unmount(tester);
    });

    testWidgets('an older failure after a newer success is dropped',
        (tester) async {
      await twoReadsInFlight(tester);
      server.held[3].complete(true); // B (newest) succeeds
      await tester.pumpAndSettle();
      server.held[2].complete(false); // A (older) fails, late
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load"), findsNothing,
          reason: 'an older failure must not replace the newest read');
      expect(find.text('Edit'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('positive control: reads landing in order apply normally',
        (tester) async {
      await twoReadsInFlight(tester);
      server.held[2].complete(true);
      await tester.pumpAndSettle();
      server.held[3].complete(true);
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('Brace hard'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(reported, isEmpty);
      await unmount(tester);
    });
  });

  // ── 4a · Save coaching ────────────────────────────────────────────────────
  group('Save coaching', () {
    for (final mode in [WriteMode.serverError, WriteMode.zeroRows]) {
      testWidgets('${mode.name}: the sheet stays with what was typed, and says it',
          (tester) async {
        server.reads['coach_exercise_media'] = _row();
        await mount(tester);
        await openEditor(tester);
        await tester.enterText(noteField(), 'Breathe out on the way up');
        server.mode = mode;
        server.modeAppliesTo = (w) => w.contains('coach_exercise_media');
        await tester.tap(find.text('Save coaching'));
        await tester.pumpAndSettle();

        expect(find.text('Coach this exercise'), findsOneWidget,
            reason: 'THE defect: the sheet closed on a failed save');
        expect(tester.widget<TextField>(noteField()).controller!.text,
            'Breathe out on the way up');
        final msg = "Couldn't save your coaching — $_generic";
        expect(find.text(msg), findsOneWidget);
        expectLive(tester, msg);
        expect(origins(), ['CustomExerciseService.upsertCoachOverlay']);
        expect(find.text('Save coaching'), findsOneWidget, reason: 'can retry');

        // Retrying, successfully, closes it and clears the message.
        server.mode = WriteMode.oneRow;
        await tester.tap(find.text('Save coaching'));
        await tester.pumpAndSettle();
        expect(find.text('Coach this exercise'), findsNothing);
        expect(find.text(msg), findsNothing);
        await unmount(tester);
      });
    }

    testWidgets('positive control: a saved overlay closes the sheet, nothing said',
        (tester) async {
      server.reads['coach_exercise_media'] = _row();
      await mount(tester);
      await openEditor(tester);
      await tester.tap(find.text('Save coaching'));
      await tester.pumpAndSettle();
      expect(find.text('Coach this exercise'), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(
          server.writes.singleWhere((w) => w.contains('coach_exercise_media')),
          contains('select=exercise_id'));
      expect(find.text('Edit'), findsOneWidget);
      expect(reported, isEmpty);
      await unmount(tester);
    });
  });

  // ── 4b · removing the voice note ──────────────────────────────────────────
  group('Remove voice note', () {
    testWidgets('a failed removal is said and recorded; the note stays',
        (tester) async {
      server.reads['coach_exercise_media'] = _row(voice: _voice);
      await mount(tester);
      await openEditor(tester);
      server.mode = WriteMode.serverError;
      server.modeAppliesTo =
          (w) => w.startsWith('PATCH') && w.contains('coach_exercise_media');
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      final msg = "Couldn't remove your voice note — $_generic";
      expect(find.text(msg), findsOneWidget,
          reason: 'THE defect: a failed removal was ignored');
      expectLive(tester, msg);
      expect(origins(), ['CustomExerciseService.clearCoachVoice']);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget,
          reason: 'the note is still there and can be removed again');
      await unmount(tester);
    });

    testWidgets('a 0-row removal is said too', (tester) async {
      server.reads['coach_exercise_media'] = _row(voice: _voice);
      await mount(tester);
      await openEditor(tester);
      server.mode = WriteMode.zeroRows;
      server.modeAppliesTo =
          (w) => w.startsWith('PATCH') && w.contains('coach_exercise_media');
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't remove your voice note — $_generic"),
          findsOneWidget);
      expect(origins(), ['CustomExerciseService.clearCoachVoice']);
      await unmount(tester);
    });

    testWidgets('positive control: a removed note is gone, nothing said',
        (tester) async {
      server.reads['coach_exercise_media'] = _row(voice: _voice);
      await mount(tester);
      await openEditor(tester);
      // clearCoachVoice reads the voice_url; the re-reads see it gone.
      server.readQueue['coach_exercise_media'] = [_row(voice: _voice)];
      server.reads['coach_exercise_media'] = _row();
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(server.writes, contains(startsWith('DELETE /storage/v1/')));
      expect(
          server.writes.singleWhere((w) => w.startsWith('PATCH')),
          contains('select=exercise_id'));
      expect(reported, isEmpty);
      await unmount(tester);
    });
  });
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
