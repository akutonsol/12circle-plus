import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_availability_screen.dart';
import 'package:circle_fitness/features/coach/presentation/coach_pricing_sheet.dart';
import 'package:circle_fitness/features/exercise_database/presentation/create_exercise_screen.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_focus_section.dart';
import 'package:circle_fitness/features/exercise_database/presentation/widgets/coach_voice.dart';
import 'package:circle_fitness/features/profile/presentation/integrations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../support/coach_tools_server.dart';
import '../support/fake_coach_audio.dart';
import '../support/fake_image_picker.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59d round 2 · a switch while NOTHING IS DRAWN (a hidden tab).
//
//  * A route pushed just before the switch has not been built: whoever pushed
//    it has no route to close, and its first frame showed A's content to B.
//  * A route removed by the switch keeps its State until the next frame: a save
//    that lands, or a tap, popped — and that closed the PAGE under it.
//
// Nothing here pumps between the switch and what follows it, so no guard that
// waits for a frame (nor FL-59a's AccountScope) can be what passes.
//
// HOW TO SEE IT FAIL: each group says which head it fails on.

void main() {
  final server = CoachToolsServer();
  final audio = FakeCoachAudio();
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];
  late Routes routes;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    picker.install();
  });
  tearDownAll(picker.dispose);

  setUp(() {
    server.reset();
    picker.reset();
    reported.clear();
    routes = Routes();
    setFailureSink(reported.add);
    audio.install();
    server.tables['user_profiles'] = [
      for (final u in [memberA, memberB])
        {'id': u, 'role': 'coach', 'pricing_monthly': u == memberA ? 120 : 300},
    ];
    server.tables['coach_exercise_media'] = [
      {'coach_id': memberA, 'exercise_id': 'ex-1', 'focus': ['A brace'], 'note': 'A note',
        'voice_url': 'voice/$memberA/x.m4a'},
      {'coach_id': memberB, 'exercise_id': 'ex-1', 'focus': ['B hips'], 'note': 'B note'},
    ];
    server.tables['coaching_calls'] = [
      {'id': 'call-1', 'coach_id': memberA, 'scheduled_at': DateTime.now().toUtc()
          .add(const Duration(hours: 30)).toIso8601String(),
        'duration_minutes': 30, 'call_type': 'check_in', 'status': 'scheduled',
        'availability_slot_id': 'slot-1', 'client_id': 'client-1',
        'client': {'first_name': 'Ana', 'last_name': 'Client', 'avatar_url': null}},
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'), (c) async => true);
  });
  tearDown(() {
    resetFailureSink();
    audio.uninstall();
  });

  final under = find.byKey(const ValueKey('page'));

  /// [page] is open over the home page, as A.
  Future<void> open(WidgetTester t, Widget page) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 2600);
    addTearDown(t.view.reset);
    await t.runAsync(() => signInAs(memberA));
    await t.pumpWidget(ProviderScope(
        child: pushedPage(routes, KeyedSubtree(key: const ValueKey('page'), child: page))));
    await t.tap(find.text('go'));
    await settleReal(t);
    expect(under, findsOneWidget, reason: 'premise');
  }

  /// Nothing was closed but what was A's, and nothing is said.
  void pageIsThere() {
    expect(under, findsOneWidget, reason: "B's page was closed by A's save");
    expect(routes.open, hasLength(2), reason: 'the home page and this one: ${routes.open}');
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining("Couldn't"), findsNothing);
  }

  Iterable<String> changed() => reported
      .where((f) => '${f.error}'.contains('signed-in account changed'))
      .map((f) => f.origin);

  /// [event] is on the auth stream, not only in the client.
  Future<void> heardBy(WidgetTester t, Future<void> Function() event) async {
    final heard = <String?>[];
    final sub = Supabase.instance.client.auth.onAuthStateChange
        .listen((s) => heard.add(s.session?.accessToken));
    await settleNoFrame(t); // (what it replays to a new listener)
    heard.clear();
    await event();
    expect(heard, [Supabase.instance.client.auth.currentSession?.accessToken],
        reason: 'premise: the event arrived');
    await t.runAsync(sub.cancel);
  }

  const focusPage = Scaffold(
      body: SingleChildScrollView(child: CoachFocusSection(exerciseId: 'ex-1')));

  group('pushed, then the switch, then the first frame', () {
    // Fails on 2bb3099: the route is A's, over B's page, and stays.
    for (final to in [memberB, null]) {
      final who = to == null ? 'signed out' : 'A→B';

      testWidgets("the coaching editor ($who): A's cues, note and player are never drawn",
          (t) async {
        await open(t, focusPage);
        final packs = server.hold((s) => s.table == 'coach_coaching_packs');
        await t.tap(find.text('Edit'));
        await settleReal(t);
        final before = routes.pushed;
        packs.complete();
        await settleNoFrame(t);
        expect(routes.pushed, before + 1, reason: 'premise: pushed, not drawn');
        await switchNoFrame(t, to);
        await t.pump();
        expect(find.text('Coach this exercise'), findsNothing);
        expect(find.textContaining('A note'), findsNothing);
        expect(find.textContaining('A brace'), findsNothing);
        await settleReal(t);
        expect(find.text('Coach this exercise'), findsNothing);
        pageIsThere();
        if (to == null) return unmountAll(t);
        expect(find.text('B hips'), findsOneWidget);
        // B's own editor opens, and stays.
        await t.tap(find.text('Edit'));
        await settleReal(t);
        expect(find.text('Coach this exercise'), findsOneWidget);
        expect(find.text('B note'), findsWidgets);
        await refreshToken(t);
        expect(find.text('Coach this exercise'), findsOneWidget);
        await unmountAll(t);
      });

      testWidgets('the pack-name dialog ($who)', (t) async {
        await open(t, focusPage);
        await t.tap(find.text('Edit'));
        await settleReal(t);
        final before = routes.pushed;
        await t.tap(find.text('＋ Save these as a pack'));
        expect(routes.pushed, before + 1, reason: 'premise: pushed, not drawn');
        await switchNoFrame(t, to);
        await t.pump();
        expect(find.text('Save cue pack'), findsNothing);
        await settleReal(t);
        expect(find.text('Save cue pack'), findsNothing);
        expect(find.text('Coach this exercise'), findsNothing);
        pageIsThere();
        await unmountAll(t);
      });

      testWidgets('"Exercise Saved!" ($who)', (t) async {
        await open(t, const CreateExerciseScreen());
        await t.enterText(find.widgetWithText(TextFormField, 'Exercise Name *'), 'A squat');
        final last = server.hold((s) => s.table == 'sync_exercise_relations');
        await t.tap(find.text('Save'));
        await settleReal(t);
        final before = routes.pushed;
        last.complete();
        await settleNoFrame(t);
        expect(routes.pushed, before + 1, reason: 'premise: pushed, not drawn');
        await switchNoFrame(t, to);
        await t.pump();
        expect(find.text('Exercise Saved!'), findsNothing, reason: "A's save, said to B");
        await settleReal(t);
        expect(find.text('Exercise Saved!'), findsNothing);
        pageIsThere();
        await unmountAll(t);
      });

      testWidgets('"Cancel session?" ($who)', (t) async {
        await open(t, const CoachAvailabilityScreen());
        final before = routes.pushed;
        await t.tap(find.widgetWithText(TextButton, 'Cancel'));
        expect(routes.pushed, before + 1, reason: 'premise: pushed, not drawn');
        await switchNoFrame(t, to);
        await t.pump();
        expect(find.text('Cancel session?'), findsNothing);
        await settleReal(t);
        expect(find.text('Cancel session?'), findsNothing);
        pageIsThere();
        await unmountAll(t);
      });

      testWidgets('an app\'s Connect sheet ($who)', (t) async {
        await open(t, const IntegrationsScreen());
        final before = routes.pushed;
        await t.tap(find.text('Connect').last);
        expect(routes.pushed, before + 1, reason: 'premise: pushed, not drawn');
        await switchNoFrame(t, to);
        await t.pump();
        expect(find.textContaining('Connect with'), findsNothing);
        await settleReal(t);
        expect(find.textContaining('Connect with'), findsNothing);
        pageIsThere();
        await unmountAll(t);
      });

      testWidgets('Import JSON ($who)', (t) async {
        await open(t, const CreateExerciseScreen());
        final before = routes.pushed;
        await t.tap(find.text('Import JSON'));
        expect(routes.pushed, before + 1, reason: 'premise: pushed, not drawn');
        await switchNoFrame(t, to);
        await t.pump();
        expect(find.text('Paste exercise JSON'), findsNothing);
        await settleReal(t);
        expect(find.text('Paste exercise JSON'), findsNothing);
        pageIsThere();
        await unmountAll(t);
      });
    }

    testWidgets("the add-slot sheet and its date picker", (t) async {
      await open(t, const CoachAvailabilityScreen());
      var before = routes.pushed;
      await t.tap(find.text('Add Slot'));
      expect(routes.pushed, before + 1, reason: 'premise: pushed, not drawn');
      await switchNoFrame(t, memberB);
      await t.pump();
      expect(find.text('Add Availability Slot'), findsNothing);
      await settleReal(t);
      pageIsThere();
      await switchTo(t, memberA);
      await t.tap(find.text('Add Slot'));
      await settleReal(t);
      before = routes.pushed;
      await t.tap(find.byIcon(Icons.calendar_today_rounded));
      expect(routes.pushed, before + 1, reason: 'premise: pushed, not drawn');
      await switchNoFrame(t, memberB);
      await t.pump();
      expect(find.byType(DatePickerDialog), findsNothing);
      await settleReal(t);
      expect(find.byType(DatePickerDialog), findsNothing);
      pageIsThere();
      await unmountAll(t);
    });

    testWidgets('control: the same coach, a new token — all of it is drawn', (t) async {
      await open(t, focusPage);
      final packs = server.hold((s) => s.table == 'coach_coaching_packs');
      await t.tap(find.text('Edit'));
      await settleReal(t);
      packs.complete();
      await settleNoFrame(t);
      await refreshNoFrame(t);
      await settleReal(t);
      expect(find.text('Coach this exercise'), findsOneWidget);
      expect(find.text('A note'), findsWidgets);
      await t.tap(find.text('Save coaching'));
      await settleReal(t);
      expect(server.writes.single.who, memberA);
      expect(find.text('Coach this exercise'), findsNothing);
      expect(under, findsOneWidget);
      await unmountAll(t);
    });

    testWidgets('a save that is closing its sheet stops showing it to B', (t) async {
      await open(t, focusPage);
      await t.tap(find.text('Edit'));
      await settleReal(t);
      await t.tap(find.text('Save coaching'));
      await settleNoFrame(t); // popped: the exit has not begun to be drawn
      expect(routes.open, hasLength(2), reason: 'premise: popped');
      await switchNoFrame(t, memberB);
      await t.pump();
      expect(find.textContaining('A note'), findsNothing);
      expect(find.text('Coach this exercise'), findsNothing);
      await settleReal(t);
      expect(under, findsOneWidget);
      await unmountAll(t);
    });
  });

  group('the switch, then the save that lands', () {
    // Passes on 2bb3099 (the guards are there; nothing tested them), fails on
    // a82f993 and on mutants 1, 2 and 12.
    for (final fails in [false, true]) {
      final how = fails ? 'fails' : 'saves';

      testWidgets('pricing ($how)', (t) async {
        await open(t, Scaffold(body: Builder(builder: (c) => TextButton(
            onPressed: () => showCoachPricingSheet(c), child: const Text('price')))));
        await t.tap(find.text('price'));
        await settleReal(t);
        final write = server.hold((s) => s.isWrite);
        if (fails) server.failing = (s) => s.isWrite;
        await t.tap(find.text('Save price'));
        await settleReal(t);
        await switchNoFrame(t, memberB);
        write.complete();
        await settleNoFrame(t);
        await settleReal(t);
        expect(find.text('Coaching Price'), findsNothing);
        pageIsThere();
        expect(server.writes.single.who, memberA);
        await unmountAll(t);
      });

      testWidgets('add slot ($how)', (t) async {
        await open(t, const CoachAvailabilityScreen());
        await t.tap(find.text('Add Slot'));
        await settleReal(t);
        final write = server.hold((s) => s.isWrite);
        if (fails) server.failing = (s) => s.isWrite;
        await t.tap(find.text('Publish Slot'));
        await settleReal(t);
        await switchNoFrame(t, memberB);
        final asked = server.log.length;
        write.complete();
        await settleNoFrame(t);
        expect(server.log.length, asked, reason: "A's save re-read B's page");
        await settleReal(t);
        expect(find.text('Add Availability Slot'), findsNothing);
        pageIsThere();
        expect(server.writes.single.who, memberA);
        await unmountAll(t);
      });

      testWidgets('coach focus ($how)', (t) async {
        await open(t, focusPage);
        await t.tap(find.text('Edit'));
        await settleReal(t);
        final write = server.hold((s) => s.isWrite);
        if (fails) server.failing = (s) => s.isWrite;
        await t.tap(find.text('Save coaching'));
        await settleReal(t);
        await switchNoFrame(t, memberB);
        final asked = server.log.length;
        write.complete();
        await settleNoFrame(t);
        expect(server.log.length, asked, reason: "A's save re-read B's section");
        await settleReal(t);
        expect(find.text('Coach this exercise'), findsNothing);
        pageIsThere();
        expect(server.writes.single.who, memberA);
        await unmountAll(t);
      });

      testWidgets('A, B, and A back before a frame: coach focus ($how)', (t) async {
        await open(t, focusPage);
        await t.tap(find.text('Edit'));
        await settleReal(t);
        final write = server.hold((s) => s.isWrite);
        if (fails) server.failing = (s) => s.isWrite;
        await t.tap(find.text('Save coaching'));
        await settleReal(t);
        await switchNoFrame(t, memberB);
        await switchNoFrame(t, memberA);
        write.complete();
        await settleNoFrame(t);
        await settleReal(t);
        pageIsThere();
        await unmountAll(t);
      });
    }

    for (final (name, page, tap, button, gone) in <(String, Widget, String, String, String)>[
      ('pricing', Scaffold(body: Builder(builder: (c) => TextButton(
          onPressed: () => showCoachPricingSheet(c), child: const Text('price')))),
          'price', 'Save price', 'Coaching Price'),
      ('add slot', const CoachAvailabilityScreen(),
          'Add Slot', 'Publish Slot', 'Add Availability Slot'),
      ('coach focus', focusPage, 'Edit', 'Save coaching', 'Coach this exercise'),
    ]) {
      testWidgets('control: the same coach, a new token meanwhile — $name saves and closes',
          (t) async {
        await open(t, page);
        await t.tap(find.text(tap));
        await settleReal(t);
        final write = server.hold((s) => s.isWrite);
        await t.tap(find.text(button));
        await settleReal(t);
        await refreshNoFrame(t);
        write.complete();
        await settleNoFrame(t);
        await settleReal(t);
        expect(find.text(gone), findsNothing, reason: 'saved and closed');
        expect(under, findsOneWidget);
        expect(server.writes.single.who, memberA);
        expect(reported, isEmpty);
        await unmountAll(t);
      });
    }
  });

  group('the switch, then the answer that was on its way', () {
    // Fails on 2bb3099: the dialog was removed, and its own pop closed the page.
    testWidgets('the pack name: no pack, and the page stays', (t) async {
      await open(t, focusPage);
      await t.tap(find.text('Edit'));
      await settleReal(t);
      await t.tap(find.text('＋ Save these as a pack'));
      await settleReal(t);
      await t.enterText(find.byType(TextField).last, 'A secret pack');
      final save = tapOf(t, 'Save');
      final cancel = tapOf(t, 'Cancel');
      await switchNoFrame(t, memberB);
      save();
      cancel();
      await settleNoFrame(t);
      await settleReal(t);
      expect(server.writes, isEmpty);
      pageIsThere();
      await unmountAll(t);
    });

    testWidgets('"Cancel session?": nothing is cancelled, and the page stays', (t) async {
      for (final answer in ['Cancel session', 'Keep']) {
        routes.open.clear();
        await open(t, const CoachAvailabilityScreen());
        await t.tap(find.widgetWithText(TextButton, 'Cancel'));
        await settleReal(t);
        final tap = tapOf(t, answer);
        await switchNoFrame(t, memberB);
        tap();
        await settleNoFrame(t);
        await settleReal(t);
        expect(server.writes, isEmpty);
        pageIsThere();
        await unmountAll(t);
      }
    });

    testWidgets('"Exercise Saved!": nothing is submitted, and the page stays', (t) async {
      for (final answer in ['Submit to Global Library', 'Back to Library']) {
        reported.clear();
        routes.open.clear();
        await open(t, const CreateExerciseScreen());
        await t.enterText(find.widgetWithText(TextFormField, 'Exercise Name *'), 'A squat');
        await t.tap(find.text('Save'));
        await settleReal(t);
        expect(find.text('Exercise Saved!'), findsOneWidget, reason: 'premise');
        final tap = tapOf(t, answer);
        final writes = server.writes.length;
        await switchNoFrame(t, memberB);
        tap();
        await settleNoFrame(t);
        await settleReal(t);
        expect(server.writes.length, writes, reason: "A's exercise was published by B");
        expect(changed(), answer == 'Back to Library' ? isEmpty : ['CreateExerciseScreen._submitForGlobal']);
        pageIsThere();
        await unmountAll(t);
      }
    });

    testWidgets('Import: the page stays, B\'s form is blank', (t) async {
      await open(t, const CreateExerciseScreen());
      await t.tap(find.text('Import JSON'));
      await settleReal(t);
      await t.enterText(find.byType(TextField).last, '{"exercise_name":"A private row"}');
      final tap = tapOf(t, 'Import');
      await switchNoFrame(t, memberB);
      tap();
      await settleNoFrame(t);
      await settleReal(t);
      expect(find.textContaining('A private'), findsNothing);
      pageIsThere();
      await unmountAll(t);
    });

    testWidgets("an app's Connect: nothing opens or is stored, and the page stays",
        (t) async {
      await open(t, const IntegrationsScreen());
      await t.tap(find.text('Connect').last);
      await settleReal(t);
      final tap = tapOf(t, 'Connect with Spotify');
      await switchNoFrame(t, memberB);
      tap();
      await settleNoFrame(t);
      await settleReal(t);
      expect(server.writes, isEmpty);
      expect(changed(), ['IntegrationsScreen._showOAuthSheet']);
      pageIsThere();
      await unmountAll(t);
    });

    testWidgets("a Connect drawn for A opens no sheet for B (N-11)", (t) async {
      await open(t, const IntegrationsScreen());
      final tap = t
          .widget<GestureDetector>(find
              .ancestor(of: find.text('Connect').last, matching: find.byType(GestureDetector))
              .first)
          .onTap!;
      await switchNoFrame(t, memberB); // B's own state is loaded, nothing drawn
      tap();
      await settleNoFrame(t);
      await settleReal(t);
      expect(find.textContaining('Connect with'), findsNothing);
      expect(changed(), ['IntegrationsScreen._handleConnect']);
      pageIsThere();
      await unmountAll(t);
    });
  });

  group('a message that waits to be tapped goes with its account', () {
    // Fails on 2bb3099: the page's own listener ended with the page.
    Future<void> leaveWithReopen(WidgetTester t) async {
      await open(t, const CoachAvailabilityScreen());
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settleReal(t);
      server.failing = (s) => s.table == 'coach_availability' && s.isWrite;
      await t.tap(find.text('Cancel session'));
      await settleReal(t);
      await t.tap(find.byTooltip('Back'));
      await settleReal(t, rounds: 10);
      expect(under, findsNothing, reason: 'premise: the page is left');
      expect(find.text('Reopen slot'), findsOneWidget, reason: 'premise: it waits');
      server.failing = (_) => false;
    }

    for (final to in [memberB, null]) {
      testWidgets('"Reopen slot" after the page is left (${to == null ? 'signed out' : 'A→B'})',
          (t) async {
        await leaveWithReopen(t);
        final reopen = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
        final writes = server.writes.length;
        await switchNoFrame(t, to);
        reopen();
        await settleNoFrame(t);
        expect(server.writes.length, writes);
        await t.pump();
        expect(find.text('Reopen slot'), findsNothing,
            reason: "A's action is told to the next account");
        expect(find.textContaining('Session cancelled'), findsNothing);
        await settleReal(t);
        expect(find.byType(SnackBar), findsNothing);
        await unmountAll(t);
      });
    }

    testWidgets('control: for the same coach it waits, and works, after the page is left',
        (t) async {
      await leaveWithReopen(t);
      await refreshToken(t);
      await t.pump(const Duration(seconds: 20));
      expect(find.text('Reopen slot'), findsOneWidget);
      await t.tap(find.text('Reopen slot'));
      await settleReal(t);
      expect(server.writes.last.query, contains('id=eq.slot-1'));
      expect(server.writes.last.who, memberA);
      expect(find.text('Slot reopened.'), findsOneWidget);
      await unmountAll(t);
    });

    // Round 4 (R3-2). Fails on 054bbfc: a timed message, but one that stays for
    // the next account (longer when it waits behind another).
    Future<void> leaveWithCancelled(WidgetTester t, int messages) async {
      const said = 'Session cancelled — client notified.';
      final own = [
        for (var i = 0; i < messages; i++)
          {...server.tables['coaching_calls']!.first, 'id': 'call-$i', 'availability_slot_id': null},
      ];
      server.tables['coaching_calls'] = [...own];
      await open(t, const CoachAvailabilityScreen());
      final notices = server.hold((s) => s.table == 'notifications');
      for (var i = 0; i < messages; i++) {
        await t.tap(find.widgetWithText(TextButton, 'Cancel').first);
        await settleReal(t);
        await t.tap(find.text('Cancel session'));
        await settleReal(t);
      }
      expect(server.to('notifications').length, messages, reason: 'premise: on their way');
      await t.tap(find.byTooltip('Back'));
      await settleReal(t, rounds: 10);
      expect(under, findsNothing, reason: 'premise: the page is left');
      notices.complete();
      await settleReal(t);
      expect(find.text(said), findsOneWidget, reason: 'premise');
    }

    for (final (to, messages) in [(memberB, 1), (null, 1), (memberB, 2)]) {
      testWidgets('"Session cancelled" ×$messages after the page is left goes with its '
          'account (${to == null ? 'signed out' : 'A→B'})', (t) async {
        await leaveWithCancelled(t, messages);
        await switchNoFrame(t, to);
        await t.pump();
        await settleReal(t, rounds: 2);
        expect(find.byType(SnackBar), findsNothing,
            reason: "A's action is told to the next account");
        await unmountAll(t);
      });
    }

    testWidgets('control: "Session cancelled" stays through the same coach\'s token refresh',
        (t) async {
      await leaveWithCancelled(t, 1);
      await heardBy(t, () => refreshNoFrame(t));
      await t.pump();
      await settleReal(t, rounds: 2);
      expect(find.text('Session cancelled — client notified.'), findsOneWidget);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    const closedForm = "Couldn't save again — this form was closed. Open the "
        'exercise from your library to finish it.';

    Future<void> leaveWithSaveAgain(WidgetTester t) async {
      await open(t, const CreateExerciseScreen());
      await t.enterText(find.widgetWithText(TextFormField, 'Exercise Name *'), 'A squat');
      server.failing = (s) => s.table == 'sync_exercise_relations';
      await t.tap(find.text('Save'));
      await settleReal(t);
      expect(find.text('Save again'), findsOneWidget, reason: 'premise');
      t.state<NavigatorState>(find.byType(Navigator).last).pop();
      await settleReal(t, rounds: 10);
      expect(under, findsNothing, reason: 'premise: the screen is left');
      expect(find.text('Save again'), findsOneWidget, reason: 'premise: it waits');
    }

    testWidgets('"Save again" after the form is left', (t) async {
      await leaveWithSaveAgain(t);
      final again = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
      final writes = server.writes.length;
      await switchNoFrame(t, memberB);
      again();
      await settleNoFrame(t);
      expect(server.writes.length, writes);
      await t.pump();
      expect(find.text('Save again'), findsNothing);
      await settleReal(t);
      expect(find.byType(SnackBar), findsNothing);
      await unmountAll(t);
    });

    testWidgets('control: for the same coach it stays', (t) async {
      await leaveWithSaveAgain(t);
      await refreshToken(t);
      expect(find.text('Save again'), findsOneWidget);
      // The form is gone: there is nothing to save again, and it does not throw.
      final writes = server.writes.length;
      await t.tap(find.text('Save again'));
      await settleReal(t);
      expect(server.writes.length, writes);
      // Round 3 (UX-4): and that is said, in place of the message it was on.
      expect(find.text(closedForm), findsOneWidget,
          reason: 'the tap did nothing and said nothing');
      expect(liveRegionOver(closedForm), findsWidgets);
      expect(find.text('Save again'), findsNothing);
      await unmountAll(t);
    });

    // Round 3. Fails on 911b117: nothing was said.
    for (final to in [memberB, null]) {
      testWidgets('why "Save again" could not is not said to the next account '
          '(${to == null ? 'signed out' : 'A→B'})', (t) async {
        await leaveWithSaveAgain(t);
        final again = t.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
        await t.tap(find.text('Save again'));
        await settleReal(t);
        expect(find.text(closedForm), findsOneWidget, reason: 'premise');
        await switchNoFrame(t, to);
        again(); // and a tap still on its way says nothing
        await settleNoFrame(t);
        await t.pump();
        await settleReal(t);
        expect(find.byType(SnackBar), findsNothing);
        await unmountAll(t);
      });
    }

    testWidgets('"Slot reopened." after the page is left goes with its account', (t) async {
      await leaveWithReopen(t);
      await t.tap(find.text('Reopen slot'));
      await settleReal(t);
      expect(find.text('Slot reopened.'), findsOneWidget, reason: 'premise');
      await switchNoFrame(t, memberB);
      await t.pump();
      await settleReal(t, rounds: 2);
      expect(find.text('Slot reopened.'), findsNothing,
          reason: "A's action is told to the next account");
      await unmountAll(t);
    });

    // Round 3 (R2-1). Fails on 911b117 with two messages: the second was queued,
    // and dropping it left its listener behind.
    for (final messages in [1, 2, 3]) {
      testWidgets("$messages \"Reopen slot\" of A's, then B's own: B's token refresh "
          'leaves it', (t) async {
        Map<String, Object?> call(String coach, String name) => {
              ...server.tables['coaching_calls']!.first,
              'id': 'call-$name', 'coach_id': coach, 'availability_slot_id': 'slot-$name',
            };
        final own = [for (var i = 0; i < messages; i++) call(memberA, 'a$i')];
        server.tables['coaching_calls'] = [...own, call(memberB, 'b')];
        server.failing = (s) => s.table == 'coach_availability' && s.isWrite;
        Future<void> cancelOne() async {
          await t.tap(find.widgetWithText(TextButton, 'Cancel').first);
          await settleReal(t);
          await t.tap(find.text('Cancel session'));
          await settleReal(t);
        }

        await open(t, const CoachAvailabilityScreen());
        for (var i = 0; i < messages; i++) {
          server.tables['coaching_calls']!.remove(own[i]); // (what its re-read answers)
          await cancelOne();
        }
        Iterable<Sent> reopens() =>
            server.to('coach_availability').where((s) => s.isWrite);
        expect(reopens().length, messages, reason: 'premise');
        expect(find.text('Reopen slot'), findsOneWidget, reason: 'premise: one shown');
        // A's own token refresh keeps them, too.
        await refreshNoFrame(t);
        await t.pump();
        expect(find.text('Reopen slot'), findsOneWidget);

        await switchNoFrame(t, memberB);
        await t.pump();
        await settleReal(t);
        expect(find.byType(SnackBar), findsNothing, reason: "A's are gone");
        await cancelOne();
        expect(find.text('Reopen slot'), findsOneWidget, reason: "premise: B's own");
        await refreshNoFrame(t);
        await t.pump();
        await settleReal(t);
        expect(find.text('Reopen slot'), findsOneWidget,
            reason: "A's old listener took B's message: the slot stays booked");
        server.failing = (_) => false;
        await t.tap(find.text('Reopen slot'));
        await settleReal(t);
        expect(reopens().last.who, memberB);
        expect(reopens().last.query, contains('id=eq.slot-b'));
        await unmountAll(t);
      });

      testWidgets("$messages \"Save again\" of A's, then B's own: B's token refresh "
          'leaves it', (t) async {
        server.failing = (s) => s.table == 'sync_exercise_relations';
        Future<void> saveOne() async {
          await t.tap(find.text('Save'));
          await settleReal(t);
        }

        final field = find.byType(TextFormField).first;
        await open(t, const CreateExerciseScreen());
        await t.enterText(field, 'A squat');
        for (var i = 0; i < messages; i++) {
          await saveOne();
        }
        expect(server.to('sync_exercise_relations').length, messages, reason: 'premise');
        expect(find.text('Save again'), findsOneWidget, reason: 'premise: one shown');
        await refreshNoFrame(t);
        await t.pump();
        expect(find.text('Save again'), findsOneWidget);

        await switchNoFrame(t, memberB);
        await t.pump();
        await settleReal(t);
        expect(find.byType(SnackBar), findsNothing, reason: "A's are gone");
        await t.enterText(field, 'B squat');
        await saveOne();
        expect(find.text('Save again'), findsOneWidget, reason: "premise: B's own");
        await refreshNoFrame(t);
        await t.pump();
        await settleReal(t);
        expect(find.text('Save again'), findsOneWidget,
            reason: "A's old listener took B's message");
        server.failing = (_) => false;
        await t.tap(find.text('Save again'));
        await settleReal(t);
        expect(server.to('sync_exercise_relations').last.who, memberB);
        expect(find.text('Exercise Saved!'), findsOneWidget);
        await unmountAll(t);
      });
    }
  });

  // Round 3 · the owner of an action is the account its button was drawn for.
  // Fails on 911b117: each read the owner (or the form) at the tap.
  group("a button drawn for A, tapped as B with nothing drawn since", () {
    VoidCallback on(WidgetTester t, Finder label) => t
        .widget<GestureDetector>(
            find.ancestor(of: label, matching: find.byType(GestureDetector)).first)
        .onTap!;

    testWidgets('Save: refused and recorded, nothing is said on B\'s form', (t) async {
      await open(t, const CreateExerciseScreen());
      await t.enterText(find.byType(TextFormField).first, 'A squat');
      final save = on(t, find.text('Save'));
      await switchNoFrame(t, memberB);
      save();
      await settleNoFrame(t);
      await settleReal(t);
      expect(server.writes, isEmpty);
      expect(find.text('Required'), findsNothing, reason: "B is told A's form is wrong");
      expect(changed(), ['CreateExerciseScreen._save']);
      pageIsThere();
      await unmountAll(t);
    });

    testWidgets('Save, with A back again: the form it was drawn on is gone', (t) async {
      await open(t, const CreateExerciseScreen());
      await t.enterText(find.byType(TextFormField).first, 'A squat');
      final save = on(t, find.text('Save'));
      await switchNoFrame(t, memberB);
      await switchNoFrame(t, memberA);
      save();
      await settleNoFrame(t);
      await settleReal(t);
      expect(server.writes, isEmpty);
      expect(find.text('Required'), findsNothing);
      expect(changed(), ['CreateExerciseScreen._save']);
      await unmountAll(t);
    });

    testWidgets('Import JSON opens nothing', (t) async {
      await open(t, const CreateExerciseScreen());
      final import = on(t, find.text('Import JSON'));
      final before = routes.pushed;
      await switchNoFrame(t, memberB);
      import();
      await settleNoFrame(t);
      await settleReal(t);
      expect(routes.pushed, before);
      // Round 4: not recorded as a save. (Fails on 054bbfc; so do the two above
      // and below for the same reason.)
      expect(changed(), ['CreateExerciseScreen._importJson']);
      pageIsThere();
      await unmountAll(t);
    });

    testWidgets("the image and a video: the picker is not opened, and A's removed "
        'video is not looked for in B\'s', (t) async {
      await open(t, const CreateExerciseScreen());
      await t.tap(find.text('MEDIA'));
      await settleReal(t);
      await t.tap(find.byIcon(Icons.add_circle_outline));
      await settleReal(t);
      final image = on(t, find.text('Tap to add image'));
      final video = on(t, find.text('Upload from device'));
      final remove = on(t, find.byIcon(Icons.remove_circle_outline));
      await switchNoFrame(t, memberB);
      image();
      video();
      remove();
      await settleNoFrame(t);
      await settleReal(t);
      expect(t.takeException(), isNull);
      expect(picker.calls, isEmpty);
      expect(changed(), ['CreateExerciseScreen._pickMedia', 'CreateExerciseScreen._pickMedia']);
      expect(find.text('Tap to add image'), findsOneWidget);
      pageIsThere();
      await unmountAll(t);
    });

    testWidgets('Add Slot opens nothing', (t) async {
      await open(t, const CoachAvailabilityScreen());
      final add = t.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed!;
      final before = routes.pushed;
      await switchNoFrame(t, memberB);
      add();
      await settleNoFrame(t);
      await settleReal(t);
      expect(routes.pushed, before);
      expect(changed(), ['CoachAvailabilityScreen._showAddSheet']);
      pageIsThere();
      await unmountAll(t);
    });

    testWidgets('control: the same coach, a new token — each works', (t) async {
      await open(t, const CoachAvailabilityScreen());
      final add = t.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed!;
      await refreshNoFrame(t);
      add();
      await settleReal(t);
      expect(find.text('Add Availability Slot'), findsOneWidget);
      await unmountAll(t);

      routes.open.clear();
      await open(t, const CreateExerciseScreen());
      final import = on(t, find.text('Import JSON'));
      await refreshNoFrame(t);
      import();
      await settleReal(t);
      expect(find.text('Paste exercise JSON'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await settleReal(t);
      await t.enterText(find.byType(TextFormField).first, 'A squat');
      await t.tap(find.text('MEDIA'));
      await settleReal(t);
      final image = on(t, find.text('Tap to add image'));
      await refreshNoFrame(t);
      image();
      await pumpUntil(t, () => find.text('Tap to add image').evaluate().isEmpty,
          what: 'the picked image');
      final save = on(t, find.text('Save'));
      await refreshNoFrame(t);
      save();
      await pumpUntil(t, () => find.text('Exercise Saved!').evaluate().isNotEmpty,
          what: 'saved');
      expect(server.writes.map((s) => s.who).toSet(), {memberA});
      expect(reported, isEmpty);
      await unmountAll(t);
    });
  });

  // Round 4 (R3-1) · the section's re-read goes out as whoever is signed in. With
  // nothing drawn it was kept under A's key: A, back before a frame, was shown
  // B's overlay as "YOUR COACHING", and Edit + Save wrote it over A's.
  group("A, B and A back with nothing drawn: A's coaching is A's", () {
    Iterable<Sent> reads() =>
        server.log.where((s) => !s.isWrite && s.table == 'coach_exercise_media');

    Future<void> edit(WidgetTester t) async {
      await t.tap(find.text('Edit'));
      await settleReal(t);
      expect(find.text('Coach this exercise'), findsOneWidget, reason: 'premise');
    }

    /// What A is shown, offered to edit, and saves — in that order: a Save
    /// closes the sheet and reads again, which hides what it saved.
    Future<void> isAs(WidgetTester t, String focus, {required int from}) async {
      expect(find.text('B hips'), findsNothing, reason: "B's overlay, drawn to A");
      expect(find.textContaining('B note'), findsNothing);
      expect(find.text(focus), findsOneWidget);
      expect(find.text('YOUR COACHING'), findsOneWidget);
      expect(reads().skip(from).where((s) => s.who == memberB), isEmpty,
          reason: "A's re-read, sent as B");
      await edit(t);
      final typed = [for (final f in t.widgetList<TextField>(find.byType(TextField)))
        f.controller!.text];
      expect(typed, containsAllInOrder([focus, 'A note']));
      expect(typed.join(), isNot(contains('B ')));
      final writes = server.writes.length;
      await t.tap(find.text('Save coaching'));
      await settleReal(t);
      final saved = server.writes.skip(writes).single;
      expect(saved.who, memberA);
      expect(saved.body, allOf(contains(focus), contains('A note')));
      expect(saved.body, isNot(contains('B ')));
    }

    /// What the server holds for A from now on.
    void aNow(String focus) =>
        server.tables['coach_exercise_media']!.first['focus'] = [focus];

    // What is answered while B is signed in. The first two fail on 054bbfc with
    // B's overlay on A's screen; the last two with A's own from BEFORE the
    // change (and Edit offered that to be saved again).
    for (final (name, act, waitsFor) in <(String, String, bool Function(Sent))>[
      // (The removal reads the row first: the re-read is the one after its PATCH.)
      ('the re-read after removing the note', 'remove',
        (s) => !s.isWrite && s.table == 'coach_exercise_media' &&
            server.log.any((l) => l.method == 'PATCH')),
      ('the re-read after a new note', 'record',
        (s) => !s.isWrite && s.table == 'coach_exercise_media'),
      ('the removal itself', 'remove', (s) => s.method == 'PATCH'),
      ('the save itself', 'save',
        (s) => s.method == 'POST' && s.table == 'coach_exercise_media'),
    ]) {
      for (final via in [memberB, memberA]) {
        testWidgets(via == memberB ? name : 'control: $name, A with a new token', (t) async {
          await open(t, focusPage);
          await edit(t);
          final wait = server.hold(waitsFor);
          switch (act) {
            case 'remove':
              await t.tap(find.byTooltip('Remove your voice note'));
            case 'record':
              t.widget<CoachVoiceRecorder>(find.byType(CoachVoiceRecorder)).onRecorded();
            default:
              await t.tap(find.text('Save coaching'));
          }
          await settleReal(t);
          expect(waitsFor(server.log.last), isTrue, reason: 'premise: it waits');
          final from = reads().length;
          server.held.clear(); // (only that one waits)
          aNow('A brace, later');
          via == memberB
              ? await switchNoFrame(t, memberB)
              : await heardBy(t, () => refreshNoFrame(t));
          wait.complete();
          await settleNoFrame(t);
          if (via == memberB) await switchNoFrame(t, memberA);
          await settleReal(t);
          if (via == memberA && act != 'save') {
            expect(find.text('Coach this exercise'), findsOneWidget, reason: 'it stays');
            Navigator.of(t.element(find.text('Coach this exercise'))).pop();
            await settleReal(t, rounds: 8);
          }
          await isAs(t, 'A brace, later', from: from);
          expect(reported, isEmpty);
          await unmountAll(t);
        });
      }
    }

    for (final via in [memberB, memberA]) {
      testWidgets(via == memberB
          ? 'Try again, delivered while B is signed in'
          : 'control: Try again, A with a new token', (t) async {
        await open(t, focusPage);
        await edit(t);
        server.failing = (s) => !s.isWrite && s.table == 'coach_exercise_media';
        await t.tap(find.text('Save coaching'));
        await settleReal(t);
        server.failing = (_) => false;
        final retry = tapOf(t, 'Try again');
        final from = reads().length;
        via == memberB
            ? await switchNoFrame(t, memberB)
            : await heardBy(t, () => refreshNoFrame(t));
        retry();
        await settleNoFrame(t);
        final sent = reads().length - from;
        if (via == memberB) await switchNoFrame(t, memberA);
        await settleReal(t);
        await isAs(t, 'A brace', from: from);
        expect(sent, via == memberB ? 0 : 1, reason: 'A\'s own, and only as A');
        await unmountAll(t);
      });

      testWidgets(via == memberB
          ? "a client's Try again, delivered while B is signed in"
          : "control: a client's Try again, A with a new token", (t) async {
        server.tables['user_profiles'] = [
          for (final u in [memberA, memberB]) {'id': u, 'role': 'client'},
        ];
        server.answers['resolve_exercise_media'] =
            {'has_coach_overlay': true, 'focus': ['For A'], 'coach_name': 'Coach Ana'};
        server.failing = (s) => s.table == 'resolve_exercise_media';
        await open(t, focusPage);
        server.failing = (_) => false;
        final retry = tapOf(t, 'Try again');
        via == memberB
            ? await switchNoFrame(t, memberB)
            : await heardBy(t, () => refreshNoFrame(t));
        retry();
        await settleNoFrame(t);
        if (via == memberB) await switchNoFrame(t, memberA);
        await settleReal(t);
        expect(server.to('resolve_exercise_media').map((s) => s.who).toSet(), {memberA},
            reason: "A's re-read, sent as B");
        expect(find.text('For A'), findsOneWidget);
        expect(find.textContaining("Couldn't"), findsNothing);
        await unmountAll(t);
      });
    }

    // The answer to a read that A sent, landing while B is signed in: it is not
    // kept, and the section is not left waiting for it either. Fails on 054bbfc:
    // A, back, is shown what that read said (a failure, or the older cues).
    for (final fails in [false, true]) {
      testWidgets("A's first read ${fails ? 'fails' : 'answers'} while B is signed in: "
          'A reads again', (t) async {
        final first = server.hold(
            (s) => !s.isWrite && s.table == 'coach_exercise_media');
        if (fails) server.failing = (s) => s.table == 'coach_exercise_media';
        await open(t, focusPage);
        expect(reads().single.who, memberA, reason: 'premise');
        server.held.clear();
        server.failing = (_) => false;
        aNow('A brace, later');
        await switchNoFrame(t, memberB);
        first.complete();
        await settleNoFrame(t);
        await switchNoFrame(t, memberA);
        await settleReal(t);
        expect(find.textContaining("Couldn't"), findsNothing);
        await isAs(t, 'A brace, later', from: 0);
        await unmountAll(t);
      });
    }

    testWidgets("with a frame for B in between, B is shown B's own and reads once",
        (t) async {
      await open(t, focusPage);
      await edit(t);
      final wait = server.hold((s) => s.method == 'POST');
      await t.tap(find.text('Save coaching'));
      await settleReal(t);
      await switchTo(t, memberB);
      wait.complete(); // A's save: it does not make B's section read again
      await settleReal(t);
      expect(find.text('B hips'), findsOneWidget);
      expect(reads().where((s) => s.who == memberB), hasLength(1));
      await unmountAll(t);
    });
  });
}
