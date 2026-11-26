import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_tools_server.dart';
import '../support/fake_coach_audio.dart';
import '../support/fit_matrix.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59d (W10, and routed from FL-60/FL-61) · coach voice notes.
//
//  * One coach across upload + set: a switch between them pointed B's overlay
//    at A's recording.
//  * record / stop / play / upload failures were swallowed or never recorded,
//    and what was said sat under the sheet the recorder is in.
//  * The recorder is a hold gesture: a screen reader could not record at all;
//    neither control had a name, a role or a state.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- apps/mobile/lib/features/
// exercise_database/presentation/widgets/coach_voice.dart`; only the controls
// pass.

// Each starts with the words on the bar (round 2, UX-3).
const _idle = 'Hold to record a voice note, up to 30 seconds. Double-tap to start or stop';
const _stopLabel = 'Recording… Double-tap to stop and send';

void main() {
  final server = CoachToolsServer();
  final audio = FakeCoachAudio();
  final reported = <AppFailure>[];
  var recorded = 0;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    await audio.warmUp();
  });

  setUp(() {
    server.reset();
    reported.clear();
    recorded = 0;
    setFailureSink(reported.add);
    audio.install();
  });
  tearDown(() {
    resetFailureSink();
    audio.uninstall();
  });

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> mount(WidgetTester t, Widget child, {String uid = memberA}) async {
    await t.runAsync(() => signInAs(uid));
    await t.pumpWidget(MaterialApp(home: Scaffold(
        body: SingleChildScrollView(child: child))));
    await settleReal(t);
  }

  Future<void> recorder(WidgetTester t, {String uid = memberA}) => mount(t,
      CoachVoiceRecorder(
          exerciseId: 'ex-1', resolveExpiry: () => null, onRecorded: () => recorded++),
      uid: uid);

  Future<void> player(WidgetTester t, {String url = 'voice/$memberA/x.m4a',
          int? ms = 12000, String? name = 'Coach Ana'}) =>
      mount(t, CoachVoicePlayer(url: url, durationMs: ms, coachName: name));

  final bar = find.byType(CoachVoiceRecorder);
  bool isRecording(WidgetTester t) =>
      find.textContaining('release to send').evaluate().isNotEmpty;

  /// Holds the bar; the recorder is running when this returns.
  Future<TestGesture> hold(WidgetTester t, {bool runs = true}) async {
    // (The bar itself: a failure is said under it.)
    final g = await t.startGesture(t.getCenter(
        find.descendant(of: bar, matching: find.byType(GestureDetector)).first));
    await t.pump(const Duration(milliseconds: 700));
    if (runs) {
      await pumpUntil(t, () => isRecording(t), what: 'recording');
    } else {
      await settleReal(t);
    }
    return g;
  }

  /// Long enough not to be a tap (the recorder reads the real clock).
  Future<void> hear(WidgetTester t) => t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 850)));

  Future<void> idle(WidgetTester t) => pumpUntil(t,
      () => find.text('Hold to record a voice note').evaluate().isNotEmpty, what: 'idle');

  group('recording is one coach\'s', () {
    testWidgets('positive control: hold, release — uploaded and set as A, once; '
        'the capture is removed', (t) async {
      await recorder(t);
      final g = await hold(t);
      await refreshToken(t); // the same coach: still recording
      expect(isRecording(t), isTrue);
      await hear(t);
      await g.up();
      await pumpUntil(t, () => recorded == 1, what: 'sent');
      await idle(t);
      expect(server.writes.map((s) => s.who).toSet(), {memberA});
      expect(server.writes, hasLength(2));
      expect(server.writes.first.path, contains('voice/$memberA/ex-1-'));
      expect(server.writes.last.body, allOf(contains(memberA), contains('voice/$memberA/')));
      expect(audio.filesLeft, isEmpty);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets('control: a tap-length hold is discarded, not a failure', (t) async {
      await recorder(t);
      final g = await hold(t);
      await g.up();
      await idle(t);
      expect(server.writes, isEmpty);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets("switch between upload and set: B's overlay is not touched", (t) async {
      await recorder(t);
      final g = await hold(t);
      await hear(t);
      final upload = server.hold((s) => s.path.startsWith('/storage/v1/'));
      await g.up();
      await pumpUntil(t, () => server.writes.isNotEmpty, what: 'the upload');
      await switchTo(t, memberB);
      upload.complete();
      await settleReal(t);
      expect(server.writesBy(memberB), isEmpty,
          reason: "B's overlay points at A's recording");
      expect(recorded, 0);
      expect(origins(), ['CustomExerciseService.setCoachVoice']);
      expect(find.textContaining("Couldn't"), findsNothing);
      await pumpUntil(t, () => audio.filesLeft.isEmpty, what: 'capture removed');
      await unmountAll(t);
    });

    testWidgets('switch while recording: it stops, is dropped and removed', (t) async {
      await recorder(t);
      final g = await hold(t);
      await hear(t);
      await switchTo(t, memberB);
      expect(isRecording(t), isFalse);
      await g.up();
      await settleReal(t);
      await t.pump(const Duration(seconds: 31)); // the 30 s limit sends nothing
      await settleReal(t);
      expect(audio.calls, contains('stop'));
      expect(server.writes, isEmpty);
      expect(recorded, 0);
      await pumpUntil(t, () => audio.filesLeft.isEmpty, what: 'capture removed');
      await unmountAll(t);
    });

    for (final drawn in [true, false]) {
      testWidgets('sign-out while recording (${drawn ? 'drawn' : 'no frame'}): it '
          'stops, is dropped and removed; it stays A\'s, and B\'s own is B\'s', (t) async {
        await recorder(t);
        var g = await hold(t);
        await hear(t);
        drawn ? await signOutNow(t) : await switchNoFrame(t, null);
        await pumpUntil(t, () => audio.filesLeft.isEmpty, what: 'capture removed');
        expect(audio.calls, contains('stop'), reason: 'the microphone is closed');
        await g.up();
        await settleReal(t);
        expect(isRecording(t), isFalse);
        expect(server.writes, isEmpty);
        expect(find.textContaining("Couldn't"), findsNothing);

        // B cannot record on A's recorder (round 3, R2-5); A's never goes out.
        await switchTo(t, memberB);
        await t.pump(const Duration(seconds: 31)); // A's 30 s limit
        await settleReal(t);
        expect(server.writes, isEmpty);
        expect(reported, isEmpty);
        audio.calls.clear();
        g = await hold(t, runs: false);
        await hear(t);
        await g.up();
        await settleReal(t);
        expect(audio.calls, isNot(contains('start')));
        expect(server.writes, isEmpty);
        expect(recorded, 0);
        expect(origins(), ['CoachVoiceRecorder._start']);
        expect(find.textContaining("Couldn't"), findsNothing);
        reported.clear();

        // The same coach back: at rest, and theirs to use.
        await signOutNow(t);
        await switchTo(t, memberA);
        server.log.clear();
        expect(find.text('Hold to record a voice note'), findsOneWidget);
        g = await hold(t);
        await hear(t);
        await g.up();
        await pumpUntil(t, () => recorded == 1, what: 'sent');
        await idle(t);
        expect(server.writes.map((s) => s.who).toSet(), {memberA});
        expect(audio.filesLeft, isEmpty);
        expect(reported, isEmpty);

        // B records and sends B's own, on the one B opens.
        await unmountAll(t);
        server.log.clear();
        await recorder(t, uid: memberB);
        g = await hold(t);
        await hear(t);
        await g.up();
        await pumpUntil(t, () => recorded == 2, what: 'sent');
        await idle(t);
        expect(server.writes.map((s) => s.who).toSet(), {memberB});
        expect(server.writes.first.path, contains('voice/$memberB/'));
        expect(audio.filesLeft, isEmpty);
        expect(reported, isEmpty);
        await unmountAll(t);
      });
    }

    for (final way in ['hold', 'assistive tap']) {
      testWidgets("no frame: B's $way on A's recorder records nothing (R2-5)", (t) async {
        final h = t.ensureSemantics();
        await recorder(t);
        final start = way == 'hold'
            ? () => t.widget<GestureDetector>(find.descendant(
                    of: bar, matching: find.byType(GestureDetector)).first)
                .onLongPressStart!(const LongPressStartDetails())
            : t.widget<Semantics>(find.descendant(of: bar, matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == _idle))).properties.onTap!;
        await switchNoFrame(t, memberB);
        audio.calls.clear();
        start();
        await settleNoFrame(t);
        await hear(t);
        expect(audio.calls, isEmpty,
            reason: "B's microphone was opened by A's sheet");
        await settleReal(t);
        expect(isRecording(t), isFalse);
        expect(origins(), ['CoachVoiceRecorder._start']);
        expect(server.writes, isEmpty);
        h.dispose();
        await unmountAll(t);
      });
    }

    testWidgets('A, B, and A back while permission is asked for: the microphone '
        'is not opened', (t) async {
      await recorder(t);
      audio.permissionGate = Completer<void>();
      final g = await hold(t, runs: false);
      await switchNoFrame(t, memberB);
      await switchNoFrame(t, memberA);
      audio.permissionGate!.complete();
      audio.permissionGate = null;
      await settleNoFrame(t);
      await settleReal(t);
      expect(audio.calls, isNot(contains('start')));
      expect(isRecording(t), isFalse);
      expect(origins(), ['CoachVoiceRecorder._start']);
      await g.up();
      // Theirs to use again.
      final g2 = await hold(t);
      await g2.up();
      await idle(t);
      await unmountAll(t);
    });

    testWidgets("A, B, and A back while sending: the old send does not end the new "
        "one's busy state", (t) async {
      await recorder(t);
      var g = await hold(t);
      await hear(t);
      final first = server.hold((s) => s.path.startsWith('/storage/v1/'));
      await g.up();
      await pumpUntil(t, () => server.writes.length == 1, what: 'the first upload');
      await switchNoFrame(t, memberB);
      await switchNoFrame(t, memberA);
      await settleReal(t);
      g = await hold(t);
      await hear(t);
      server.held.clear();
      final second = server.hold((s) => s.path.startsWith('/storage/v1/'));
      await g.up();
      await pumpUntil(t, () => server.writes.length == 2, what: 'the second upload');
      first.complete();
      await settleReal(t);
      expect(find.text('Sending…'), findsOneWidget);
      second.complete();
      await idle(t);
      expect(server.writes.map((s) => s.who).toSet(), {memberA});
      await unmountAll(t);
    });

    testWidgets('control: the same coach, a new token and no frame — a hold records',
        (t) async {
      await recorder(t);
      await refreshNoFrame(t);
      final g = await hold(t);
      await hear(t);
      await g.up();
      await pumpUntil(t, () => recorded == 1, what: 'sent');
      await idle(t);
      expect(server.writes.map((s) => s.who).toSet(), {memberA});
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets('A, out, and A back while recording: the old capture is not sent',
        (t) async {
      await recorder(t);
      final g = await hold(t);
      await hear(t);
      await switchNoFrame(t, null);
      await switchNoFrame(t, memberA);
      await g.up();
      await settleReal(t);
      expect(server.writes, isEmpty, reason: 'it was dropped when they left');
      expect(isRecording(t), isFalse);
      await pumpUntil(t, () => audio.filesLeft.isEmpty, what: 'capture removed');
      await unmountAll(t);
    });

    // (A control: `record` runs one call at a time, so with it A's late stop
    // cannot meet the next file. The local copy of the path is for one that
    // does. Round 3: the next recording is A's, back again.)
    testWidgets("control: A's stop that fails late does not remove the next recording",
        (t) async {
      await recorder(t);
      var g = await hold(t);
      await hear(t);
      audio.stopGate = Completer<void>();
      audio.stopFails = 'x';
      await g.up();
      await settleReal(t);
      await switchTo(t, memberB);
      await switchTo(t, memberA);
      g = await hold(t, runs: false);
      audio.stopGate!.complete();
      audio.stopGate = null;
      await settleReal(t);
      audio.stopFails = null;
      await pumpUntil(t, () => isRecording(t), what: 'the next recording');
      expect(audio.filesLeft, hasLength(1), reason: 'the next capture was deleted');
      await hear(t);
      await g.up();
      await pumpUntil(t, () => recorded == 1, what: 'sent');
      expect(server.writes.map((s) => s.who).toSet(), {memberA});
      await unmountAll(t);
    });

    testWidgets('a note that was sent is announced, once; one that was not, never',
        (t) async {
      Iterable<String> said() => t.takeAnnouncements().map((a) => a.message);
      await recorder(t);
      said();
      var g = await hold(t);
      await hear(t);
      await g.up();
      await pumpUntil(t, () => recorded == 1, what: 'sent');
      await idle(t);
      expect(said(), ['Voice note sent'], reason: 'the bar only went back to rest');
      server.failing = (s) => s.table == 'coach_exercise_media';
      g = await hold(t);
      await hear(t);
      await g.up();
      await idle(t);
      expect(said(), isEmpty, reason: 'it was not sent');
      server.failing = (_) => false;
      final set = server.hold((s) => s.table == 'coach_exercise_media' && s.who == memberA);
      final before = server.to('coach_exercise_media').length;
      g = await hold(t);
      await hear(t);
      await g.up();
      await pumpUntil(t, () => server.to('coach_exercise_media').length > before, what: 'set');
      await switchNoFrame(t, memberB);
      set.complete();
      await settleReal(t);
      expect(said(), isEmpty, reason: "A's note is not announced to B");
      expect(recorded, 1);
      await unmountAll(t);
    });

    testWidgets('switch while permission is asked for: the microphone is not opened',
        (t) async {
      for (final granted in [true, false]) {
        audio.calls.clear();
        reported.clear();
        audio.permission = granted;
        await recorder(t);
        audio.permissionGate = Completer<void>();
        final g = await hold(t, runs: false);
        await switchTo(t, memberB);
        audio.permissionGate!.complete();
        await settleReal(t);
        await g.up();
        await settleReal(t);
        expect(audio.calls, isNot(contains('start')));
        expect(find.text(micDeniedMessage), findsNothing, reason: "A's answer, said to B");
        expect(origins(), granted ? ['CoachVoiceRecorder._start'] : isEmpty);
        await unmountAll(t);
      }
    });

    testWidgets('switch while the recorder starts: nothing is recorded for B',
        (t) async {
      await recorder(t);
      audio.startGate = Completer<void>();
      final g = await hold(t, runs: false);
      await switchTo(t, memberB);
      audio.startGate!.complete();
      await settleReal(t);
      expect(isRecording(t), isFalse);
      await g.up();
      await settleReal(t);
      expect(server.writes, isEmpty);
      expect(origins(), ['CoachVoiceRecorder._start']);
      await pumpUntil(t, () => audio.filesLeft.isEmpty, what: 'capture removed');
      await unmountAll(t);
    });

    testWidgets("a save that failed for A is not said to B", (t) async {
      await recorder(t);
      final g = await hold(t);
      await hear(t);
      final set = server.hold((s) => s.table == 'coach_exercise_media');
      server.failing = (s) => s.table == 'coach_exercise_media';
      await g.up();
      await pumpUntil(t, () => server.to('coach_exercise_media').isNotEmpty, what: 'set');
      await switchTo(t, memberB);
      set.complete();
      await settleReal(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(origins(), ['CustomExerciseService.setCoachVoice']);
      await unmountAll(t);
    });

    testWidgets('closed while recording: stopped and removed, nothing sent', (t) async {
      await recorder(t);
      final g = await hold(t);
      await unmountAll(t);
      await g.up();
      await pumpUntil(t, () => audio.filesLeft.isEmpty, what: 'capture removed');
      expect(audio.calls, contains('stop'));
      expect(server.writes, isEmpty);
    });
  });

  group('recorder failures are said beside it, and recorded', () {
    const sendFailed = "Couldn't send your voice note — try again in a moment. "
        'If it keeps happening, contact support.';

    Finder said(String text) => find.descendant(of: bar, matching: find.text(text));
    void live(String text) => expect(
        find.ancestor(of: said(text), matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.liveRegion ?? false))),
        findsWidgets, reason: 'announced');

    testWidgets('the microphone is refused: says so (Settings), distinct from a failure',
        (t) async {
      audio.permission = false;
      await recorder(t);
      final g = await hold(t, runs: false);
      await g.up();
      await settleReal(t);
      expect(said(micDeniedMessage), findsOneWidget);
      live(micDeniedMessage);
      expect(find.byType(SnackBar), findsNothing, reason: 'it sat under the sheet');
      expect(reported, isEmpty, reason: 'a refusal is an answer');
      // The next attempt clears it.
      audio.permission = true;
      final g2 = await hold(t);
      expect(said(micDeniedMessage), findsNothing);
      await g2.up();
      await idle(t);
      await unmountAll(t);
    });

    for (final what in ['permission', 'start']) {
      testWidgets('recording will not start ($what): said and recorded', (t) async {
        what == 'start' ? audio.startFails = 'x' : audio.permissionFails = 'x';
        await recorder(t);
        final g = await hold(t, runs: false);
        await g.up();
        await settleReal(t);
        const msg = "Couldn't start recording — try again in a moment. If it "
            'keeps happening, contact support.';
        expect(said(msg), findsOneWidget);
        live(msg);
        expect(origins(), ['CoachVoiceRecorder._start']);
        expect(find.textContaining('SECRET'), findsNothing);
        await unmountAll(t);
      });
    }

    for (final (name, arrange) in <(String, void Function())>[
      ('stop throws', () => audio.stopFails = 'x'),
      ('nothing was captured', () => audio.stopsEmpty = true),
    ]) {
      testWidgets('$name: said and recorded, nothing is sent', (t) async {
        await recorder(t);
        final g = await hold(t);
        await hear(t);
        arrange();
        await g.up();
        await idle(t);
        expect(said(sendFailed), findsOneWidget);
        expect(origins(), ['CoachVoiceRecorder._stop']);
        expect(server.writes, isEmpty);
        expect(recorded, 0);
        await pumpUntil(t, () => audio.filesLeft.isEmpty, what: 'capture removed');
        await unmountAll(t);
      });
    }

    for (final (step, match) in <(String, bool Function(Sent))>[
      ('uploadCoachVoice', (s) => s.path.startsWith('/storage/v1/')),
      ('setCoachVoice', (s) => s.table == 'coach_exercise_media'),
    ]) {
      for (final net in [false, true]) {
        testWidgets('$step ${net ? 'offline' : 'refused'}: not reported as sent, '
            'said, recorded once', (t) async {
          await recorder(t);
          final g = await hold(t);
          await hear(t);
          net ? server.offline = match : server.failing = match;
          await g.up();
          await idle(t);
          expect(
              said(net
                  ? "Couldn't send your voice note — check your connection and try again."
                  : sendFailed),
              findsOneWidget);
          expect(origins(), ['CustomExerciseService.$step']);
          expect(recorded, 0);
          await unmountAll(t);
        });
      }
    }

    testWidgets('a set that stored no row is not a sent note', (t) async {
      await recorder(t);
      final g = await hold(t);
      await hear(t);
      server.zeroRows = (s) => true;
      await g.up();
      await idle(t);
      expect(said(sendFailed), findsOneWidget);
      expect(recorded, 0);
      await unmountAll(t);
    });
  });

  group('recorder for assistive tech', () {
    testWidgets('one activation starts, the next stops and sends; each state is '
        'named and announced', (t) async {
      final h = t.ensureSemantics();
      await recorder(t);
      expectNamedButton(t, _idle);
      final atRest = t.getSemantics(find.bySemanticsLabel(_idle)).getSemanticsData();
      expect(atRest.hasAction(SemanticsAction.longPress), isFalse,
          reason: 'one way in, not two under one name');
      t.semantics.tap(find.semantics.byLabel(_idle));
      await pumpUntil(t, () => isRecording(t), what: 'recording');
      expectNamedButton(t, _stopLabel);
      var d = t.getSemantics(find.bySemanticsLabel(_stopLabel)).getSemanticsData();
      expect(d.flagsCollection.isLiveRegion, isTrue);
      await t.pump(const Duration(seconds: 3));
      expect(find.bySemanticsLabel(_stopLabel), findsOneWidget,
          reason: 'the seconds are not announced one by one');
      await hear(t);
      final upload = server.hold((s) => s.path.startsWith('/storage/v1/'));
      t.semantics.tap(find.semantics.byLabel(_stopLabel));
      await pumpUntil(t, () => server.writes.isNotEmpty, what: 'the upload');
      d = t.getSemantics(find.bySemanticsLabel('Sending… voice note')).getSemanticsData();
      expect(d.hasAction(SemanticsAction.tap), isFalse);
      upload.complete();
      await pumpUntil(t, () => recorded == 1, what: 'sent');
      await idle(t);
      expectNamedButton(t, _idle);
      h.dispose();
      await unmountAll(t);
    });

    testWidgets('control: touch is unchanged — a tap does not record, a hold does',
        (t) async {
      await recorder(t);
      await t.tap(bar);
      await settleReal(t);
      expect(isRecording(t), isFalse);
      expect(audio.calls, isNot(contains('start')));
      final g = await hold(t);
      expect(find.text('Recording… 0s  (release to send)'), findsOneWidget);
      await g.up();
      await idle(t);
      await unmountAll(t);
    });
  });

  group('player', () {
    const playFailed = "Couldn't play this voice note — try again in a moment. "
        'If it keeps happening, contact support.';
    final control = find.byType(CoachVoicePlayer);
    bool playing(WidgetTester t) => find.byIcon(Icons.pause_rounded).evaluate().isNotEmpty;

    testWidgets('plays and pauses by name; the state is announced', (t) async {
      final h = t.ensureSemantics();
      await player(t);
      const play = 'Listen to Coach Ana: play, 12 seconds';
      const pause = 'Listen to Coach Ana: pause, 12 seconds';
      expectNamedButton(t, play);
      t.semantics.tap(find.semantics.byLabel(play));
      await pumpUntil(t, () => playing(t), what: 'playing');
      expectNamedButton(t, pause);
      final d = t.getSemantics(find.bySemanticsLabel(pause)).getSemanticsData();
      expect(d.value, 'Playing');
      expect(d.flagsCollection.isLiveRegion, isTrue);
      expect(audio.playing.single, contains('/object/sign/'));
      t.semantics.tap(find.semantics.byLabel(pause));
      await pumpUntil(t, () => !playing(t), what: 'paused');
      expect(t.getSemantics(find.bySemanticsLabel(play)).getSemanticsData().value, 'Paused');
      expect(reported, isEmpty);
      h.dispose();
      await unmountAll(t);
    });

    testWidgets("the coach's own note, of unknown length, is named", (t) async {
      final h = t.ensureSemantics();
      await player(t, name: null, ms: null);
      expectNamedButton(t, 'Coach voice note: play');
      h.dispose();
      await unmountAll(t);
    });

    testWidgets('will not play: said, announced, recorded once; plays on retry',
        (t) async {
      audio.playFails = 'x';
      await player(t);
      await t.tap(control);
      // (audioplayers gives up on "prepared" after 30 s of its own clock)
      await pumpUntil(t, () => find.text(playFailed).evaluate().isNotEmpty,
          what: 'said', step: const Duration(seconds: 1));
      expect(playing(t), isFalse);
      expect(origins(), ['CoachVoicePlayer._toggle']);
      expect(find.textContaining('SECRET'), findsNothing);
      audio.playFails = null;
      await t.tap(control);
      await pumpUntil(t, () => playing(t), what: 'playing');
      expect(find.text(playFailed), findsNothing);
      await unmountAll(t);
    });

    testWidgets('the recording stops part-way: not "playing", said, recorded once',
        (t) async {
      await player(t);
      await t.tap(control);
      await pumpUntil(t, () => playing(t), what: 'playing');
      audio.streamError();
      await pumpUntil(t, () => find.text(playFailed).evaluate().isNotEmpty, what: 'said');
      expect(playing(t), isFalse);
      expect(origins(), ['CoachVoicePlayer._toggle']);
      await unmountAll(t);
    });

    const pauseFailed = "Couldn't pause this voice note — try again in a moment. "
        'If it keeps happening, contact support.';

    /// What is announced: the button's value ('' = nothing).
    String state(WidgetTester t) => t
        .getSemantics(find.descendant(
            of: control, matching: find.byType(GestureDetector)).first)
        .getSemanticsData()
        .value;

    testWidgets('will not pause: said and recorded; it is still Playing, and the '
        'next tap pauses', (t) async {
      final h = t.ensureSemantics();
      await player(t);
      audio.position = 6000;
      await t.tap(control);
      await pumpUntil(t, () => playing(t), what: 'playing');
      audio.pauseFails = 'x';
      await t.tap(control);
      await pumpUntil(t, () => find.textContaining("Couldn't").evaluate().isNotEmpty, what: 'said');
      expect(find.text(pauseFailed), findsOneWidget, reason: 'it did play');
      expect(playing(t), isTrue, reason: 'THE defect: shown as paused while it played on');
      expect(state(t), 'Playing');
      expect(origins(), ['CoachVoicePlayer._toggle']);
      audio.pauseFails = null;
      await t.tap(control);
      await pumpUntil(t, () => !playing(t), what: 'paused');
      expect(state(t), 'Paused');
      expect(find.text(pauseFailed), findsNothing);
      expect(audio.calls.where((c) => c == 'pause'), hasLength(2));
      expect(origins(), hasLength(1));
      h.dispose();
      await unmountAll(t);
    });

    testWidgets('stops part-way: at rest, and Play loads it again from a new link',
        (t) async {
      final h = t.ensureSemantics();
      await player(t);
      audio.position = 6000;
      await t.tap(control);
      await pumpUntil(t, () => playing(t), what: 'playing');
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100)); // half-way through
        await settleReal(t, rounds: 1);
      }
      audio.streamError();
      await pumpUntil(t, () => find.text(playFailed).evaluate().isNotEmpty, what: 'said');
      await settleReal(t); // a position that lands late is not a place to resume
      expect(playing(t), isFalse);
      expect(state(t), '', reason: 'it is not "Paused"');
      await t.tap(control);
      await pumpUntil(t, () => playing(t), what: 'playing');
      expect(audio.playing, hasLength(2),
          reason: 'THE defect: "Playing" a source that failed, with no sound');
      expect(server.log.where((s) => s.path.contains('/object/sign/')), hasLength(2));
      expect(state(t), 'Playing');
      expect(find.text(playFailed), findsNothing);
      // A second, different failure is recorded too.
      audio.streamError();
      await pumpUntil(t, () => find.text(playFailed).evaluate().isNotEmpty, what: 'said');
      expect(origins(), ['CoachVoicePlayer._toggle', 'CoachVoicePlayer._toggle']);
      h.dispose();
      await unmountAll(t);
    });

    testWidgets('control: paused half-way, it resumes the same source', (t) async {
      final h = t.ensureSemantics();
      await player(t);
      audio.position = 6000;
      await t.tap(control);
      await pumpUntil(t, () => playing(t), what: 'playing');
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
        await settleReal(t, rounds: 1);
      }
      await t.tap(control);
      await pumpUntil(t, () => !playing(t), what: 'paused');
      expect(state(t), 'Paused');
      await t.tap(control);
      await pumpUntil(t, () => playing(t), what: 'playing');
      expect(audio.playing, hasLength(1));
      h.dispose();
      await unmountAll(t);
    });

    testWidgets('never "Paused" while it loads or after a first play that failed',
        (t) async {
      final h = t.ensureSemantics();
      await player(t);
      expect(state(t), '');
      final sign = server.hold((s) => s.path.contains('/object/sign/'));
      server.failing = (s) => s.path.contains('/object/sign/');
      await t.tap(control);
      await settleReal(t);
      expect(state(t), 'Loading', reason: 'THE defect: announced "Paused"');
      sign.complete();
      await settleReal(t);
      expect(find.text(playFailed), findsOneWidget, reason: 'premise');
      expect(state(t), '', reason: 'nothing was ever paused');
      // Played to its end, it is at rest too.
      server.failing = (_) => false;
      await t.tap(control);
      await pumpUntil(t, () => playing(t), what: 'playing');
      audio.event({'event': 'audio.onComplete'});
      await pumpUntil(t, () => !playing(t), what: 'ended');
      expect(state(t), '');
      h.dispose();
      await unmountAll(t);
    });

    group('goes with its account', () {
      for (final to in [memberB, null]) {
        final who = to == null ? 'signed out' : 'A→B';
        testWidgets("$who, nothing drawn: A's note stops; the next tap plays nothing",
            (t) async {
          await player(t);
          await t.tap(control);
          await pumpUntil(t, () => playing(t), what: 'playing');
          audio.calls.clear();
          final tap = t.widget<GestureDetector>(
              find.descendant(of: control, matching: find.byType(GestureDetector)).first).onTap!;
          await switchNoFrame(t, to);
          expect(audio.calls, contains('release'),
              reason: 'THE defect: it played on in the next session');
          final asked = server.log.length;
          tap();
          await settleNoFrame(t);
          expect(server.log.length, asked, reason: "A's note is not signed for them");
          expect(audio.calls, isNot(contains('resume')));
          expect(origins(), ['CoachVoicePlayer._toggle']);
          expect('${reported.single.error}', contains('signed-in account changed'));
          await t.pump();
          expect(playing(t), isFalse);
          expect(find.textContaining("Couldn't"), findsNothing);
          // A again: at rest, and it plays.
          await switchTo(t, memberA);
          expect(playing(t), isFalse);
          await t.tap(control);
          await pumpUntil(t, () => playing(t), what: 'playing');
          await unmountAll(t);
        });

        testWidgets('$who while it loads: it does not start', (t) async {
          await player(t);
          audio.playGate = Completer<void>();
          await t.tap(control);
          await pumpUntil(t, () => audio.calls.contains('setSourceUrl'), what: 'loading');
          await switchNoFrame(t, to);
          audio.playGate!.complete();
          await settleNoFrame(t);
          expect(audio.calls, isNot(contains('resume')));
          await settleReal(t);
          expect(playing(t), isFalse);
          expect(find.textContaining("Couldn't"), findsNothing);
          await unmountAll(t);
        });
      }

      for (final heard in [true, false]) {
        testWidgets("A's failure landing after B is recorded, not said "
            "(${heard ? 'the player has' : 'it has not yet'} heard of B)", (t) async {
          await player(t);
          await t.tap(control);
          await pumpUntil(t, () => playing(t), what: 'playing');
          if (heard) await switchNoFrame(t, memberB);
          final b = heard ? null : t.runAsync(() => signInAs(memberB));
          audio.streamError();
          await b;
          await settleReal(t);
          expect(find.textContaining("Couldn't"), findsNothing);
          expect(origins(), ['CoachVoicePlayer._toggle']);
          await unmountAll(t);
        });
      }

      testWidgets('A, out and A back while it loads: the old play is not "Playing"',
          (t) async {
        await player(t);
        audio.playGate = Completer<void>();
        await t.tap(control);
        await pumpUntil(t, () => audio.calls.contains('setSourceUrl'), what: 'loading');
        await switchNoFrame(t, null);
        await switchNoFrame(t, memberA);
        audio.playGate!.complete();
        audio.playGate = null;
        await settleReal(t);
        expect(audio.calls, isNot(contains('resume')), reason: 'premise: no sound');
        expect(playing(t), isFalse);
        await t.tap(control);
        await pumpUntil(t, () => playing(t), what: 'playing');
        expect(audio.calls.where((c) => c == 'resume'), hasLength(1));
        await unmountAll(t);
      });

      testWidgets('control: a token refresh plays on', (t) async {
        await player(t);
        await t.tap(control);
        await pumpUntil(t, () => playing(t), what: 'playing');
        audio.calls.clear();
        await refreshToken(t);
        expect(playing(t), isTrue);
        expect(audio.calls, isNot(contains('release')));
        expect(audio.calls, isNot(contains('stop')));
        await t.tap(control);
        await pumpUntil(t, () => !playing(t), what: 'paused');
        expect(reported, isEmpty);
        await unmountAll(t);
      });
    });

    for (final net in [false, true]) {
      testWidgets('the link cannot be signed (${net ? 'offline' : 'refused'}): said, '
          'recorded once, nothing unplayable is played', (t) async {
        bool sign(Sent s) => s.path.contains('/object/sign/');
        net ? server.offline = sign : server.failing = sign;
        await player(t);
        await t.tap(control);
        await settleReal(t);
        expect(
            find.text(net
                ? "Couldn't play this voice note — check your connection and try again."
                : playFailed),
            findsOneWidget);
        expect(origins(), ['CustomExerciseService.signedCoachVoiceUrl']);
        expect(audio.playing, isEmpty);
        await unmountAll(t);
      });
    }

    testWidgets('control: a legacy public link still plays when signing fails', (t) async {
      server.failing = (s) => s.path.contains('/object/sign/');
      const legacy = 'https://x.test/storage/v1/object/public/coach-media/voice/u/x.m4a';
      await player(t, url: legacy);
      await t.tap(control);
      await pumpUntil(t, () => playing(t), what: 'playing');
      expect(audio.playing, [legacy]);
      await unmountAll(t);
    });

    testWidgets("A's note is not played to B, nor to nobody's screen", (t) async {
      for (final gone in [false, true]) {
        server.held.clear();
        final sign = server.hold((s) => s.path.contains('/object/sign/'));
        await player(t);
        await t.tap(control);
        await settleReal(t);
        gone ? await t.pumpWidget(const SizedBox()) : await switchTo(t, memberB);
        sign.complete();
        await settleReal(t);
        expect(audio.playing, isEmpty);
        await unmountAll(t);
      }
    });

    testWidgets('no double start', (t) async {
      final sign = server.hold((s) => s.path.contains('/object/sign/'));
      await player(t);
      await t.tap(control);
      await t.pump();
      await t.tap(control);
      await settleReal(t);
      sign.complete();
      await pumpUntil(t, () => playing(t), what: 'playing');
      expect(audio.playing, hasLength(1));
      await unmountAll(t);
    });
  });

  group('fit: no overflow, no shrunk text, 44px', () {
    for (final w in fitPhones.keys) {
      for (final s in fitScales) {
        testWidgets('${w}dp at ${s}x', (t) async {
          fitWindow(t, w, 4000, s);
          final seen = recordOverflows();
          audio.permission = false;
          await mount(t, Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            CoachVoicePlayer(url: 'voice/$memberA/x.m4a', durationMs: 12000,
                coachName: 'Alexandria Montgomery'),
            const SizedBox(height: 8),
            CoachVoiceRecorder(exerciseId: 'ex-1', resolveExpiry: () => null, onRecorded: () {}),
          ])));
          void fits() {
            expect(seen, isEmpty, reason: seen.join('\n\n'));
            for (final f in [bar, find.byType(CoachVoicePlayer)]) {
              expectTextNotShrunk(t, f, s);
              final area = find.descendant(of: f, matching: find.byType(GestureDetector)).first;
              expect(t.getSize(area).height, greaterThanOrEqualTo(44));
            }
            for (final e in find.byType(RichText).evaluate()) {
              final r = t.getRect(find.byWidget(e.widget));
              expect(r.left >= 0 && r.right <= w, isTrue, reason: 'cut off: $r');
            }
          }

          fits();
          expect(renderedFontSize(t, find.text('Hold to record a voice note')),
              closeTo(13.5 * s, 0.01));
          // Its longest failure, then recording.
          var g = await hold(t, runs: false);
          await g.up();
          await settleReal(t);
          expect(find.text(micDeniedMessage), findsOneWidget, reason: 'premise');
          fits();
          audio.permission = true;
          g = await hold(t);
          fits();
          expect(renderedFontSize(t, find.text('30s')), closeTo(11 * s, 0.01));
          expect(renderedFontSize(t, find.text('0:12')), closeTo(11 * s, 0.01));
          await g.up();
          await idle(t);
          await unmountAll(t);
        });
      }
    }
  });
}
