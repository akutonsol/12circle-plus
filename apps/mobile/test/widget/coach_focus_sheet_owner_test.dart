import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_focus_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_tools_server.dart';
import '../support/fake_coach_audio.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59d (W9) · the Coach Focus editor writes the overlay of the coach who
// opened it.
//
// The section follows the signed-in coach; the sheet over it did not. After a
// switch on this device Save replaced coach B's overlay — what B's clients see
// — with coach A's cues, note and video; "Save these as a pack" made B a pack
// of A's cues; removing the voice note removed B's.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- apps/mobile/lib/features/
// exercise_database/presentation/widgets/coach_focus_section.dart`; only the
// controls pass.

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
        'voice_url': 'voice/$memberA/x.m4a'},
      {'coach_id': memberB, 'exercise_id': 'ex-1', 'focus': ['B hips'], 'note': 'B note',
        'voice_url': 'voice/$memberB/x.m4a'},
    ];
    server.tables['coach_coaching_packs'] = [
      {'id': 'p-a', 'coach_id': memberA, 'name': 'A pack', 'cues': ['A cue']},
    ];
  });
  tearDown(() {
    resetFailureSink();
    audio.uninstall();
  });

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
    expect(find.text('A brace'), findsOneWidget, reason: 'premise');
  }

  final sheet = find.text('Coach this exercise');

  Future<void> openEditor(WidgetTester t) async {
    await t.tap(find.text('Edit'));
    await settleReal(t);
    expect(sheet, findsOneWidget, reason: 'premise');
  }

  Iterable<String> changed() => reported
      .where((f) => '${f.error}'.contains('signed-in account changed'))
      .map((f) => f.origin);

  testWidgets("A→B: A's sheet closes; the Save already tapped writes nothing",
      (t) async {
    await mount(t);
    await openEditor(t);
    final save = tapOf(t, 'Save coaching');
    await switchTo(t, memberB);
    expect(sheet, findsNothing);
    expect(find.textContaining('A note'), findsNothing);
    expect(find.text('B hips'), findsOneWidget, reason: "B's own section");
    await t.runAsync(() async => save());
    await settleReal(t);
    expect(server.writes, isEmpty, reason: "A's coaching replaced B's overlay");
    await unmountAll(t);
  });

  testWidgets('a Save tapped as B signed in writes nothing, recorded once', (t) async {
    await mount(t);
    await openEditor(t);
    final save = tapOf(t, 'Save coaching');
    // The sheet is still up: nothing has been drawn since the switch.
    final b = t.runAsync(() => signInAs(memberB));
    save();
    await b;
    await settleReal(t);
    expect(server.writesBy(memberB), isEmpty);
    expect(sheet, findsNothing);
    expect(find.textContaining("Couldn't"), findsNothing);
    await unmountAll(t);
  });

  for (final fails in [false, true]) {
    testWidgets('switch during the save (${fails ? 'fails' : 'saves'}): as A, '
        'and B is told nothing', (t) async {
      await mount(t);
      await openEditor(t);
      final hold = server.hold((s) => s.isWrite);
      if (fails) server.failing = (s) => s.isWrite;
      await t.tap(find.text('Save coaching'));
      await settleReal(t);
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(server.writes.single.who, memberA);
      expect(server.writes.single.body, contains(memberA));
      expect(sheet, findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(find.text('B hips'), findsOneWidget);
      await unmountAll(t);
    });
  }

  testWidgets('signed out: the sheet closes', (t) async {
    await mount(t);
    await openEditor(t);
    await signOutNow(t);
    expect(sheet, findsNothing);
    expect(find.textContaining('A note'), findsNothing);
    await unmountAll(t);
  });

  testWidgets("A's packs still being read when B signs in: no sheet opens for B",
      (t) async {
    await mount(t);
    final hold = server.hold((s) => s.table == 'coach_coaching_packs');
    await t.tap(find.text('Edit'));
    await settleReal(t);
    expect(sheet, findsNothing, reason: 'premise: waiting for the packs');
    await switchTo(t, memberB);
    hold.complete();
    await settleReal(t);
    expect(sheet, findsNothing, reason: "A's editor opened on B's session");
    await unmountAll(t);
  });

  testWidgets('an Edit tapped as B signed in opens nothing', (t) async {
    await mount(t);
    final edit = t
        .widget<GestureDetector>(
            find.ancestor(of: find.text('Edit'), matching: find.byType(GestureDetector)).first)
        .onTap!;
    await t.runAsync(() => signInAs(memberB));
    edit();
    await t.pump();
    expect(sheet, findsNothing);
    expect(changed(), ['CoachFocusSection._openEditor']);
    await unmountAll(t);
  });

  testWidgets("the pack-name dialog closes with the sheet; no pack for B", (t) async {
    await mount(t);
    await openEditor(t);
    await t.tap(find.text('＋ Save these as a pack'));
    await settleReal(t);
    await t.enterText(find.byType(TextField).last, 'A secret pack');
    await switchTo(t, memberB);
    expect(find.text('Save cue pack'), findsNothing);
    expect(sheet, findsNothing);
    expect(server.writes, isEmpty);
    await unmountAll(t);
  });

  testWidgets('switch while a pack is saved: as A only', (t) async {
    await mount(t);
    await openEditor(t);
    await t.tap(find.text('＋ Save these as a pack'));
    await settleReal(t);
    await t.enterText(find.byType(TextField).last, 'Pack two');
    final hold = server.hold((s) => s.isWrite);
    await t.tap(find.widgetWithText(TextButton, 'Save'));
    await settleReal(t);
    await switchTo(t, memberB);
    hold.complete();
    await settleReal(t);
    expect(server.writes.single.who, memberA);
    expect(server.writes.single.json, containsPair('coach_id', memberA));
    expect(sheet, findsNothing);
    await unmountAll(t);
  });

  testWidgets("removing A's voice note never removes B's", (t) async {
    await mount(t);
    await openEditor(t);
    final remove = t
        .widget<IconButton>(find.ancestor(
            of: find.byTooltip('Remove your voice note'), matching: find.byType(IconButton)))
        .onPressed!;
    await t.runAsync(() => signInAs(memberB));
    remove();
    await settleReal(t);
    expect(server.writes, isEmpty, reason: "B's recording was removed");
    expect(changed(), ['CustomExerciseService.clearCoachVoice']);
    expect(find.textContaining("Couldn't"), findsNothing);
    await unmountAll(t);
  });

  testWidgets('positive control: a token refresh keeps the sheet and what was '
      "typed; Save writes A's overlay", (t) async {
    await mount(t);
    await openEditor(t);
    await t.enterText(find.byType(TextField).at(1), 'Slower today');
    await refreshToken(t);
    expect(sheet, findsOneWidget);
    expect(find.text('Slower today'), findsOneWidget);
    await t.tap(find.text('Save coaching'));
    await settleReal(t);
    final w = server.writes.single;
    expect(w.who, memberA);
    final body = w.body;
    expect(body, allOf(contains(memberA), contains('Slower today'), contains('A brace')));
    expect(sheet, findsNothing);
    expect(reported, isEmpty);
    await unmountAll(t);
  });

  testWidgets("positive control: A saves a pack and removes A's note", (t) async {
    await mount(t);
    await openEditor(t);
    await t.tap(find.text('＋ Save these as a pack'));
    await settleReal(t);
    await t.enterText(find.byType(TextField).last, 'Pack two');
    await t.tap(find.widgetWithText(TextButton, 'Save'));
    await settleReal(t);
    expect(server.writes.single.json, containsPair('name', 'Pack two'));
    await t.tap(find.byTooltip('Remove your voice note'));
    await settleReal(t);
    expect(server.writes.map((s) => s.method), ['POST', 'DELETE', 'PATCH']);
    expect(server.writes.last.query, contains('coach_id=eq.$memberA'));
    expect(reported, isEmpty);
    await unmountAll(t);
  });

  testWidgets('negative control: no overlay yet is an offer to add, not an error',
      (t) async {
    await mount(t);
    server.tables['coach_exercise_media'] = [];
    await switchTo(t, memberB);
    expect(find.textContaining('Add your coaching'), findsOneWidget);
    expect(find.textContaining("Couldn't"), findsNothing);
    await unmountAll(t);
  });
}
