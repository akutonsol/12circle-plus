import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_focus_section.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fit_matrix.dart';
import '../support/held_reads_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-58 (d) · Coach Focus: targets that were under 44px before cycle 11.
//
//   Edit (49×17) · each pack chip (31–33px) · "Save these as a pack" (31px) ·
//   the three voice-note expiry chips (28px) · the hold-to-record bar (42px).
// None had a button role or named its item; the voice-note delete had no name
// at all; a pack chip with a long name overflowed (471px at 320dp, 3×).
//
// HOW TO SEE IT FAIL: `git checkout f191d48 -- lib/features/
// exercise_database/presentation/widgets/coach_focus_section.dart`; only the
// controls pass.

const _uid = '00000000-0000-4000-8000-0000000f58d0';
const _longPack = 'Squat and hinge cues for long femurs';

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
    server.reads['coach_exercise_media'] = {
      'coach_id': _uid, 'exercise_id': 'ex-1', 'focus': ['Brace hard'],
      'note': 'Slow down', 'voice_url': 'voice/$_uid/ex-1-1.m4a',
    };
    server.reads['coach_coaching_packs'] = [
      {'id': 'p1', 'name': _longPack, 'cues': ['Knees out', 'Chest up']},
      {'id': 'p2', 'name': 'Bench', 'cues': ['Feet flat']},
    ];
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in _audio) {
      m.setMockMethodCallHandler(MethodChannel(c), (_) async => null);
    }
  });
  tearDown(() {
    resetFailureSink();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in _audio) {
      m.setMockMethodCallHandler(MethodChannel(c), null);
    }
  });

  Future<void> mount(WidgetTester tester, {num width = 390, double height = 5000,
      double scale = 1, String matchText = 'back squat'}) async {
    fitWindow(tester, width, height, scale);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider
            .overrideWithValue(Supabase.instance.client.auth.currentUser),
        currentUserProfileProvider
            .overrideWith((ref) async => {'id': _uid, 'role': 'coach'}),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: CoachFocusSection(exerciseId: 'ex-1', matchText: matchText)))),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Coach this exercise'), findsOneWidget);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  final sheet = find.byType(BottomSheet);
  // 'squat' of {squat, hinge, long, femurs} — 'cues', 'and', 'for' are stop words.
  const applyLong = 'Apply pack $_longPack, 25% match';
  Finder focusField() => find.byWidgetPredicate((w) =>
      w is TextField && (w.decoration?.hintText ?? '').startsWith('Control the descent'));

  group('fit: no overflow, no shrunk text', () {
    for (final w in fitPhones.keys) {
      for (final s in fitScales) {
        testWidgets('card and sheet, ${w}dp at ${s}x', (tester) async {
          final seen = recordOverflows();
          await mount(tester, width: w, scale: s);
          expect(seen, isEmpty, reason: seen.join('\n\n'));
          expect(renderedFontSize(tester, find.text('Edit')), closeTo(12 * s, 0.01));
          await openEditor(tester);
          expect(seen, isEmpty, reason: seen.join('\n\n'));
          expectTextNotShrunk(tester, sheet, s);
          for (final (t, size) in [(_longPack, 12.0), ('This week', 11.0),
              ('＋ Save these as a pack', 12.0)]) {
            expect(renderedFontSize(tester, find.text(t)), closeTo(size * s, 0.01), reason: t);
            final r = tester.getRect(find.text(t));
            expect(r.left >= 0 && r.right <= w, isTrue, reason: '$t is cut off: $r');
          }
          await unmount(tester);
        });
      }
    }
  });

  group('targets', () {
    testWidgets('card: Edit is a named 44×44 button', (tester) async {
      final h = tester.ensureSemantics();
      await mount(tester, width: 320);
      expectNamedButton(tester, 'Edit your coaching for this exercise');
      tester.semantics.tap(find.semantics.byLabel('Edit your coaching for this exercise'));
      await tester.pumpAndSettle();
      expect(find.text('Coach this exercise'), findsOneWidget);
      h.dispose();
      await unmount(tester);
    });

    testWidgets('no coaching yet: the Add prompt is a named 44×44 button', (tester) async {
      final h = tester.ensureSemantics();
      server.reads.remove('coach_exercise_media');
      await mount(tester, width: 320);
      const label = 'Add your coaching for this exercise — a focus, a note, your own video';
      expectNamedButton(tester, label);
      tester.semantics.tap(find.semantics.byLabel(label));
      await tester.pumpAndSettle();
      expect(find.text('Coach this exercise'), findsOneWidget);
      h.dispose();
      await unmount(tester);
    });

    for (final s in [1.0, 3.0]) {
      testWidgets('sheet: every target is 44×44, named for its item (${s}x)', (tester) async {
        final h = tester.ensureSemantics();
        await mount(tester, width: 320, height: 12000, scale: s);
        await openEditor(tester);
        for (final l in [applyLong, 'Apply pack Bench', 'Save these as a pack',
            'Voice note expires: Today', 'Voice note expires: This week',
            'Voice note expires: Never']) {
          expectNamedButton(tester, l);
        }
        expect(find.byTooltip('Remove your voice note'), findsOneWidget);
        // (byTooltip is the 40px disc inside the button's padded 48px target.)
        expect(tester.getSize(find.ancestor(of: find.byTooltip('Remove your voice note'),
            matching: find.byType(IconButton))).shortestSide, greaterThanOrEqualTo(44));
        // The recorder's gesture area itself, not only the room it is given.
        expect(tester.getSize(find.descendant(of: find.byType(CoachVoiceRecorder),
            matching: find.byType(GestureDetector)).first).height, greaterThanOrEqualTo(44));
        expectTargets(tester, sheet, atLeast: 9);
        h.dispose();
        await unmount(tester);
      });
    }

    testWidgets('r2: the hold-to-record bar is 44px with its text on one line (1.0x)',
        (tester) async {
      // Wide, so the text is on one line in the (wide) test font too: wrapped,
      // the bar is over 44px by itself and proves nothing.
      await mount(tester, width: 800);
      await openEditor(tester);
      expectWholeOnOneLine(tester, find.text('Hold to record a voice note'));
      final bar = find.descendant(
          of: find.byType(CoachVoiceRecorder), matching: find.byType(GestureDetector)).first;
      expect(tester.getSize(bar).height, greaterThanOrEqualTo(44));
      // The drawn bar is that tall, not only the room around it.
      expect(tester.getSize(find.descendant(of: bar, matching: find.byType(Container)).first),
          tester.getSize(bar));
      await unmount(tester);
    });

    testWidgets('r2: the fields keep their names once text is in them', (tester) async {
      final h = tester.ensureSemantics();
      server.reads.remove('coach_exercise_media'); // nothing saved: all empty
      await mount(tester);
      await tester.tap(find.textContaining('Add your coaching'));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: sheet, matching: find.byType(TextField));
      expect(fields, findsNWidgets(3), reason: 'premise');
      for (final (i, name) in const [(0, 'Coach focus today'), (1, 'Note (optional)'),
          (2, 'Your video (optional — YouTube link or id)')]) {
        await expectFieldNamed(tester, fields.at(i), name);
      }
      await tester.tap(find.text('＋ Save these as a pack'));
      await tester.pumpAndSettle();
      await expectFieldNamed(tester, find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Pack name');
      h.dispose();
      await unmount(tester);
    });

    testWidgets('r2 negative control: an empty field is still empty, and its hint is said',
        (tester) async {
      final h = tester.ensureSemantics();
      server.reads.remove('coach_exercise_media');
      await mount(tester);
      await tester.tap(find.textContaining('Add your coaching'));
      await tester.pumpAndSettle();
      final d = tester.getSemantics(find.descendant(
          of: find.descendant(of: sheet, matching: find.byType(TextField)).at(1),
          matching: find.byType(EditableText))).getSemanticsData();
      expect(d.value, isEmpty);
      expect('${d.label}\n${d.hint}', contains('A short message to your clients'));
      h.dispose();
      await unmount(tester);
    });

    testWidgets('control: a field still saves what was typed in it', (tester) async {
      await mount(tester);
      await openEditor(tester);
      await tester.enterText(
          find.descendant(of: sheet, matching: find.byType(TextField)).at(1), 'Tempo 3-1-1');
      await tester.tap(find.text('Save coaching'));
      await tester.pumpAndSettle();
      expect(server.writes.where((w) => w.contains('/coach_exercise_media') &&
          w.contains('Tempo 3-1-1')), hasLength(1));
      expect(reported, isEmpty);
      await unmount(tester);
    });

    testWidgets('a screen reader applies the pack it named', (tester) async {
      final h = tester.ensureSemantics();
      await mount(tester);
      await openEditor(tester);
      tester.semantics.tap(find.semantics.byLabel(applyLong));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(focusField()).controller!.text, 'Knees out\nChest up');
      h.dispose();
      await unmount(tester);
    });

    testWidgets('expiry: touching the edge of the target chooses it, and it is announced',
        (tester) async {
      final h = tester.ensureSemantics();
      await mount(tester);
      await openEditor(tester);
      bool selected(String l) => tester.getSemantics(find.bySemanticsLabel(l))
          .getSemanticsData().flagsCollection.isSelected == Tristate.isTrue;
      expect(selected('Voice note expires: Never'), isTrue);
      final r = tester.getRect(find.bySemanticsLabel('Voice note expires: This week'));
      await tester.tapAt(r.bottomCenter - const Offset(0, 2));
      await tester.pumpAndSettle();
      expect(selected('Voice note expires: This week'), isTrue);
      expect(selected('Voice note expires: Never'), isFalse);
      final recorder = tester.widget<CoachVoiceRecorder>(find.byType(CoachVoiceRecorder));
      final days = recorder.resolveExpiry()!.difference(DateTime.now()).inHours / 24;
      expect(days, closeTo(7, 0.1), reason: 'the choice reaches the recorder');
      h.dispose();
      await unmount(tester);
    });

    testWidgets('a pack save in flight is announced and has no action', (tester) async {
      final h = tester.ensureSemantics();
      await mount(tester);
      await openEditor(tester);
      await tester.enterText(focusField(), 'Brace');
      tester.semantics.tap(find.semantics.byLabel('Save these as a pack'));
      await tester.pumpAndSettle();
      server.gate = Completer<void>();
      await tester.enterText(find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Mine');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final d = tester.getSemantics(find.bySemanticsLabel('Saving pack…')).getSemanticsData();
      expect(d.hasAction(SemanticsAction.tap), isFalse, reason: 'no second save');
      expect(d.flagsCollection.isLiveRegion, isTrue);
      server.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Save these as a pack'), findsOneWidget);
      h.dispose();
      await unmount(tester);
    });
  });

  testWidgets('control: the chips look as they did, only the target grew', (tester) async {
    await mount(tester);
    await openEditor(tester);
    final chip = tester.getSize(
        find.ancestor(of: find.text('Today'), matching: find.byType(Container)).first);
    expect(chip.height, lessThan(44), reason: 'the drawn chip is not inflated');
    // Its own text plus padding (10 + 10) and border (1 + 1), in any font.
    expect(chip.width, closeTo(tester.getSize(find.text('Today')).width + 22, 0.1));
    expectWholeOnOneLine(tester, find.text('Today'));
    expect(tester.getRect(find.text('Today')).top, tester.getRect(find.text('Never')).top,
        reason: 'one line');
    await unmount(tester);
  });

  testWidgets('control: no packs shows no pack chips; saving the coaching still works',
      (tester) async {
    server.reads['coach_coaching_packs'] = [];
    await mount(tester);
    await openEditor(tester);
    expect(find.text('APPLY A PACK'), findsNothing);
    expect(find.text('SUGGESTED PACKS'), findsNothing);
    await tester.tap(find.text('Save coaching'));
    await tester.pumpAndSettle();
    expect(find.text('Coach this exercise'), findsNothing);
    expect(reported, isEmpty);
    await unmount(tester);
  });
}

// audioplayers talks to its platform side over these; a widget test has none.
const _audio = [
  'xyz.luan/audioplayers',
  'xyz.luan/audioplayers.global',
  'xyz.luan/audioplayers.global/events',
];
