import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_focus_section.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_voice.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../support/coach_tools_server.dart';
import '../support/fake_coach_audio.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59d round 5 · coach A, coach B, and A back, with nothing drawn: the
// "Coach this exercise" sheet is still up (or about to open), and "is A signed
// in?" is yes again.
//
//  * R4-1: the editor waits for the cue packs; the voice note was taken from
//    the section AFTER that, when the section was B's.
//  * The sheet's own reads (packs, voice note) went out as whoever was signed
//    in when Try again arrived, and were kept for A.
//  * An answer A asked for before leaving passed "is A signed in?" after.
//
// Nothing here pumps between the switch and what follows it, and there is no
// AccountScope.
//
// HOW TO SEE IT FAIL: `git checkout 30e2472 -- apps/mobile/lib/features/
// exercise_database/presentation/widgets/coach_focus_section.dart`; the
// controls pass, everything else fails.

void main() {
  final server = CoachToolsServer();
  final audio = FakeCoachAudio();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    audio.install();
    server.tables['user_profiles'] = [
      for (final u in [memberA, memberB]) {'id': u, 'role': 'coach'},
    ];
    server.tables['coach_exercise_media'] = [
      {'coach_id': memberA, 'exercise_id': 'ex-1', 'focus': ['A brace'], 'note': 'A note',
        'voice_url': 'voice/a.m4a'},
      {'coach_id': memberB, 'exercise_id': 'ex-1', 'focus': ['B hips'], 'note': 'B note',
        'voice_url': 'voice/b.m4a'},
    ];
    server.tables['coach_coaching_packs'] = [
      {'id': 'p-a', 'coach_id': memberA, 'name': 'A pack', 'cues': ['A cue']},
      {'id': 'p-b', 'coach_id': memberB, 'name': 'B pack', 'cues': ['B cue']},
    ];
  });
  tearDown(() {
    resetFailureSink();
    audio.uninstall();
  });

  final sheet = find.text('Coach this exercise');

  Future<void> mount(WidgetTester t) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2600);
    addTearDown(t.view.reset);
    await t.runAsync(() => signInAs(memberA));
    await t.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: CoachFocusSection(exerciseId: 'ex-1'))))));
    await settleReal(t);
  }

  List<String> players(WidgetTester t) => [
        for (final p in t.widgetList<CoachVoicePlayer>(find.byType(CoachVoicePlayer))) p.url
      ];
  List<String> typed(WidgetTester t) => [
        for (final f in t.widgetList<TextField>(find.byType(TextField))) f.controller!.text
      ];

  Iterable<Sent> reads(String table) =>
      server.log.where((s) => !s.isWrite && s.table == table);

  /// The Try again of the failure about [what], as it was drawn.
  VoidCallback retryOf(WidgetTester t, String what) => t
      .widget<ButtonStyleButton>(find.descendant(
          of: find.byWidgetPredicate((w) => w is SectionLoadFailure && w.what == what),
          matching: find.bySubtype<ButtonStyleButton>()))
      .onPressed!;

  /// B signs in and A is back in ONE turn, [meanwhile] in between: neither
  /// event has been heard when it is over, so no route of A's was closed.
  Future<void> inOneTurn(WidgetTester t, [void Function()? meanwhile]) async {
    await t.runAsync(() async {
      final auth = Supabase.instance.client.auth;
      final b = signInAs(memberB);
      expect(auth.currentUser?.id, memberB, reason: 'premise');
      meanwhile?.call();
      final a = signInAs(memberA);
      expect(auth.currentUser?.id, memberA, reason: 'premise');
      await Future.wait([b, a]);
    });
    await settleNoFrame(t);
  }

  /// The same coach's new token, heard on the stream.
  Future<void> newToken(WidgetTester t) async {
    final heard = <String?>[];
    final sub = Supabase.instance.client.auth.onAuthStateChange
        .listen((s) => heard.add(s.session?.accessToken));
    await settleNoFrame(t); // (what it replays to a new listener)
    heard.clear();
    await refreshNoFrame(t);
    expect(heard, [Supabase.instance.client.auth.currentSession?.accessToken],
        reason: 'premise: the event arrived');
    await t.runAsync(sub.cancel);
  }

  void nothingOfBs(WidgetTester t) {
    expect(find.textContaining('B pack'), findsNothing, reason: "B's pack, drawn to A");
    expect(players(t), isNot(contains('voice/b.m4a')), reason: "B's voice, drawn to A");
    expect(typed(t).join(), isNot(contains('B ')), reason: "B's text, drawn to A");
    expect(find.text('B hips'), findsNothing);
  }

  group('R4-1 · Edit, waiting for the cue packs', () {
    for (final mode in ['Bdrawn', 'one turn', 'control: same coach, a new token']) {
      testWidgets(mode, (t) async {
        await mount(t);
        final packs = server.hold((s) => s.table == 'coach_coaching_packs');
        await t.tap(find.text('Edit'));
        await settleReal(t);
        expect(sheet, findsNothing, reason: 'premise: it waits');
        server.held.clear();
        switch (mode) {
          case 'Bdrawn':
            await switchTo(t, memberB);
            expect(find.text('B hips'), findsOneWidget, reason: "premise: B's is drawn");
            await switchNoFrame(t, memberA);
          case 'one turn':
            // (What the packs answer now is what A is offered: 30e2472 kept the
            // answer from before A left.)
            server.tables['coach_coaching_packs']!.first['name'] = 'A pack, later';
            await inOneTurn(t);
          default:
            await newToken(t);
        }
        packs.complete();
        await settleNoFrame(t);
        await settleReal(t);
        nothingOfBs(t);
        expect(sheet, findsOneWidget, reason: "A's own editor opens");
        expect(players(t).toSet(), {'voice/a.m4a'});
        expect(typed(t).take(2), ['A brace', 'A note']);
        expect(find.text(mode == 'one turn' ? 'A pack, later' : 'A pack'), findsOneWidget);
        expect(reads('coach_coaching_packs').map((s) => s.who).toSet(), {memberA});
        // Read once when the same coach was there all along.
        expect(reads('coach_coaching_packs').length, mode.startsWith('control') ? 1 : 2);
        expect(reported, isEmpty);
        await unmountAll(t);
      });
    }
  });

  // The two reads the sheet has a Try again for.
  for (final (name, what, table) in <(String, String, String)>[
    ('cue packs', 'your cue packs', 'coach_coaching_packs'),
    ('voice note', 'your voice note', 'coach_exercise_media'),
  ]) {
    group("the sheet's $name", () {
      /// The sheet is up and says it couldn't load them.
      Future<void> failed(WidgetTester t) async {
        await mount(t);
        if (table == 'coach_coaching_packs') {
          server.failing = (s) => s.table == table;
          await t.tap(find.text('Edit'));
          await settleReal(t);
        } else {
          await t.tap(find.text('Edit'));
          await settleReal(t);
          // The sheet's re-read after a new note fails; the section's own,
          // right after it, does not.
          var once = false;
          server.failing = (s) {
            if (s.table != table || s.isWrite || once) return false;
            return once = true;
          };
          t.widget<CoachVoiceRecorder>(find.byType(CoachVoiceRecorder)).onRecorded();
          await settleReal(t);
        }
        server.failing = (_) => false;
        expect(find.text("Couldn't load $what"), findsOneWidget, reason: 'premise');
        expect(sheet, findsOneWidget, reason: 'premise');
        reported.clear();
      }

      /// A is shown A's own after a Try again of A's.
      Future<void> retried(WidgetTester t) async {
        retryOf(t, what)();
        await settleReal(t);
        expect(find.text("Couldn't load $what"), findsNothing);
        table == 'coach_coaching_packs'
            ? expect(find.text('A pack'), findsOneWidget)
            : expect(players(t), everyElement('voice/a.m4a'));
        nothingOfBs(t);
      }

      for (final answer in ['answers', 'fails']) {
        testWidgets('Try again, delivered as B, A back in the same turn ($answer): '
            'nothing is sent, nothing of B\'s is drawn or recorded', (t) async {
          await failed(t);
          final retry = retryOf(t, what);
          final from = server.log.length;
          if (answer == 'fails') server.failing = (s) => s.who == memberB;
          await inOneTurn(t, retry);
          await settleReal(t);
          expect(server.log.skip(from).where((s) => s.who == memberB), isEmpty,
              reason: "A's read, sent as B");
          expect(server.log.skip(from).where((s) => s.query.contains(memberB)), isEmpty);
          expect(server.log.skip(from).where((s) => s.table == table), isEmpty);
          nothingOfBs(t);
          expect(reported, isEmpty, reason: "B's failure, recorded as A's");
          // As it was before the tap, and not left busy.
          expect(sheet, findsOneWidget, reason: 'premise: the sheet is still up');
          expect(find.text("Couldn't load $what"), findsOneWidget);
          server.failing = (_) => false;
          await retried(t);
          await unmountAll(t);
        });

        testWidgets('Try again, delivered as B, everything has heard of it, A back '
            '($answer): nothing is sent', (t) async {
          await failed(t);
          final retry = retryOf(t, what);
          final from = server.log.length;
          await switchNoFrame(t, memberB);
          final heard = server.log.length;
          if (answer == 'fails') server.failing = (s) => s.who == memberB;
          retry();
          await settleNoFrame(t);
          expect(server.log.length, heard, reason: "A's read, sent as B");
          expect(reported, isEmpty, reason: "B's failure, recorded as A's");
          server.failing = (_) => false;
          await switchNoFrame(t, memberA);
          await settleReal(t);
          nothingOfBs(t);
          expect(server.log.skip(from).where((s) => s.table == table && s.who == memberB),
              isEmpty);
          await unmountAll(t);
        });

        // "Is A signed in?" is yes before and after: only the count of sign-ins
        // knows. What A is shown is read again, as A.
        testWidgets("Try again by A, away and back before it $answer: it is asked again",
            (t) async {
          await failed(t);
          final hold = server.hold((s) => s.table == table && !s.isWrite);
          if (answer == 'fails') server.failing = (s) => s.table == table;
          retryOf(t, what)();
          await settleNoFrame(t);
          expect(server.log.last.table, table, reason: 'premise: on its way');
          final from = server.log.length;
          server.held.clear();
          server.failing = (_) => false;
          await inOneTurn(t);
          hold.complete();
          await settleNoFrame(t);
          await settleReal(t);
          final again = server.log.skip(from).where((s) => s.table == table);
          expect(again.map((s) => s.who), [memberA], reason: 'asked again, as A');
          expect(find.text("Couldn't load $what"), findsNothing);
          nothingOfBs(t);
          expect(sheet, findsOneWidget);
          await unmountAll(t);
        });
      }

      testWidgets('control: Try again, the same coach with a new token meanwhile',
          (t) async {
        await failed(t);
        final hold = server.hold((s) => s.table == table && !s.isWrite);
        final from = server.log.length;
        retryOf(t, what)();
        await settleNoFrame(t);
        await newToken(t);
        hold.complete();
        await settleNoFrame(t);
        await settleReal(t);
        expect(server.log.skip(from).where((s) => s.table == table).map((s) => s.who),
            [memberA], reason: 'asked once');
        expect(find.text("Couldn't load $what"), findsNothing);
        expect(sheet, findsOneWidget, reason: 'it stays');
        nothingOfBs(t);
        expect(reported, isEmpty);
        await unmountAll(t);
      });

      testWidgets('negative control: a Try again that fails for A is still said, once',
          (t) async {
        await failed(t);
        server.failing = (s) => s.table == table;
        retryOf(t, what)();
        await settleReal(t);
        expect(find.text("Couldn't load $what"), findsOneWidget);
        expect(reported, hasLength(1));
        server.failing = (_) => false;
        await retried(t);
        await unmountAll(t);
      });
    });
  }

  group("the section's own read", () {
    for (final fails in [false, true]) {
      testWidgets("A's first read ${fails ? 'fails' : 'answers'} after A was away and back "
          'in one turn: read again', (t) async {
        final first = server.hold((s) => s.table == 'coach_exercise_media');
        if (fails) server.failing = (s) => s.table == 'coach_exercise_media';
        await mount(t);
        expect(reads('coach_exercise_media').map((s) => s.who), [memberA], reason: 'premise');
        server.held.clear();
        server.failing = (_) => false;
        server.tables['coach_exercise_media']!.first['focus'] = ['A brace, later'];
        await inOneTurn(t);
        first.complete();
        await settleNoFrame(t);
        await settleReal(t);
        nothingOfBs(t);
        expect(find.textContaining("Couldn't"), findsNothing);
        expect(find.text('A brace, later'), findsOneWidget);
        expect(reads('coach_exercise_media').map((s) => s.who).toSet(), {memberA});
        await unmountAll(t);
      });
    }

    testWidgets('control: the same coach, a new token meanwhile: read once', (t) async {
      final first = server.hold((s) => s.table == 'coach_exercise_media');
      await mount(t);
      await newToken(t);
      first.complete();
      await settleNoFrame(t);
      await settleReal(t);
      expect(find.text('A brace'), findsOneWidget);
      expect(reads('coach_exercise_media'), hasLength(1));
      expect(reported, isEmpty);
      await unmountAll(t);
    });
  });

  // A sheet that outlives the switch is A's still: what A does in it is A's.
  testWidgets('A, away and back in one turn, with the sheet up: Save writes A\'s',
      (t) async {
    await mount(t);
    await t.tap(find.text('Edit'));
    await settleReal(t);
    await inOneTurn(t);
    await settleReal(t);
    expect(sheet, findsOneWidget, reason: 'premise');
    nothingOfBs(t);
    await t.tap(find.text('Save coaching'));
    await settleReal(t);
    expect(server.writes.single.who, memberA);
    expect(server.writes.single.body, allOf(contains('A brace'), contains('A note')));
    expect(sheet, findsNothing);
    await unmountAll(t);
  });
}
