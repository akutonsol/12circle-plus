import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/classes/presentation/create_class_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_tools_server.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-62a2 (W22) · the New Class form belongs to the coach who opened it,
// with the REAL class service and real sign-ins on one device, and NO
// AccountScope.
//
// The class was created as whoever was signed in when Publish landed: coach A's
// typed form, saved after coach B signed in, made A's class B's. The form
// stayed filled for B. A failure was "Could not create class." and recorded
// nowhere; an insert that came back with no row closed the screen as created.
//
// HOW TO SEE IT FAIL: `git checkout a446926 -- apps/mobile/lib/features/classes`;
// only the controls pass.

void main() {
  final server = CoachToolsServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> changed() => reported
      .where((f) => '${f.error}'.contains('signed-in account changed'))
      .map((f) => f.origin);
  Iterable<Sent> inserts() =>
      server.writes.where((s) => s.table == 'classes' && s.method == 'POST');
  final title = find.byType(TextField).first;
  String typedTitle(WidgetTester t) =>
      t.widget<TextField>(find.byType(TextField).first).controller!.text;

  late Routes routes;
  late bool? popped;

  /// The form, pushed over a page (as Classes and My Classes push it), for A.
  Future<void> open(WidgetTester t) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 3000);
    addTearDown(t.view.reset);
    await t.runAsync(() => signInAs(memberA));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    routes = Routes();
    popped = null;
    await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            navigatorObservers: [routes],
            home: Builder(builder: (ctx) => Scaffold(body: TextButton(
                onPressed: () async => popped = await Navigator.of(ctx).push<bool>(
                    MaterialPageRoute(builder: (_) => const CreateClassScreen())),
                child: const Text('go')))))));
    await t.tap(find.text('go'));
    await settleReal(t);
    expect(find.text('New Class'), findsOneWidget, reason: 'premise');
  }

  Future<void> type(WidgetTester t, [String text = 'A private yoga']) async {
    await t.enterText(title, text);
    await t.pump();
  }

  Future<void> formGone(WidgetTester t) async {
    await t.pump(const Duration(seconds: 1)); // the route's way out
    expect(find.byType(CreateClassScreen), findsNothing, reason: "A's form stayed open for B");
    expect(find.text('A private yoga'), findsNothing, reason: "A's form is shown to B");
    expect(find.text('go'), findsOneWidget);
  }

  group('another coach signs in', () {
    testWidgets("coach A→coach B: A's form is cleared and closed; its Publish creates nothing",
        (t) async {
      await open(t);
      await type(t);
      final publish = tapOf(t, 'Publish Class');
      await switchTo(t, memberB);
      await formGone(t);
      publish(); // the tap already on its way
      await settleReal(t);
      expect(server.writes, isEmpty, reason: "A's class was created as B: ${server.writes.toList()}");
      expect(find.byType(SnackBar), findsNothing);
      await unmountAll(t);
    });

    testWidgets('a Publish tapped before anything was drawn creates nothing as B',
        (t) async {
      await open(t);
      await type(t);
      final publish = tapOf(t, 'Publish Class');
      await switchNoFrame(t, memberB);
      expect(typedTitle(t), isEmpty, reason: "A's typed form is kept for B");
      publish();
      await settleNoFrame(t);
      await settleReal(t);
      expect(server.writes, isEmpty, reason: "A's class was created as B: ${server.writes.toList()}");
      expect(changed(), ['CreateClassScreen._save']);
      expect(find.byType(SnackBar), findsNothing);
      await formGone(t);
      await unmountAll(t);
    });

    testWidgets("switch during the save: the class was A's; B is told nothing",
        (t) async {
      await open(t);
      await type(t);
      final hold = server.hold((s) => s.isWrite);
      await t.tap(find.text('Publish Class'));
      await settleReal(t);
      expect(inserts().single.who, memberA, reason: 'premise');
      expect(inserts().single.json, containsPair('coach_id', memberA));
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(server.writes, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      expect(popped, isNot(true), reason: "B's list was refreshed as if B made A's class");
      expect(changed(), ['CreateClassScreen._save']);
      await formGone(t);
      await unmountAll(t);
    });

    testWidgets("switch during a save the server refused: A's failure is not said to B",
        (t) async {
      await open(t);
      await type(t);
      final hold = server.hold((s) => s.isWrite);
      server.failing = (s) => s.isWrite;
      await t.tap(find.text('Publish Class'));
      await settleReal(t);
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(find.byType(SnackBar), findsNothing, reason: "A's failure was said to B");
      expect(find.textContaining('create'), findsNothing);
      expect(changed(), ['CreateClassScreen._save']);
      await formGone(t);
      await unmountAll(t);
    });

    testWidgets('signed out: the form is cleared and closed; nothing is created',
        (t) async {
      await open(t);
      await type(t);
      final publish = tapOf(t, 'Publish Class');
      await signOutNow(t);
      // Before any tap: A's form is gone with A.
      await formGone(t);
      publish();
      await settleReal(t);
      expect(server.writes, isEmpty);
      expect(popped, isNot(true), reason: 'a signed-out Publish closed as created');
      // The same coach, back in: a blank form of their own that creates once.
      await switchTo(t, memberA);
      await t.tap(find.text('go'));
      await settleReal(t);
      expect(typedTitle(t), isEmpty);
      await type(t, 'Again');
      await t.tap(find.text('Publish Class'));
      await settleReal(t);
      expect(inserts().single.json, allOf(containsPair('coach_id', memberA), containsPair('title', 'Again')));
      await unmountAll(t);
    });
  });

  group('a failure is a failure', () {
    testWidgets('an insert that came back with no row is not "created"', (t) async {
      server.zeroRows = (s) => s.isWrite;
      await open(t);
      await type(t);
      await t.tap(find.text('Publish Class'));
      await settleReal(t);
      expect(inserts().single.query, contains('select=id'),
          reason: 'the insert must ask for its row back');
      expect(popped, isNot(true), reason: 'closed as created');
      expect(find.textContaining("Couldn't create the class — try again in a moment"),
          findsOneWidget);
      expect(reported.map((f) => f.origin), ['CreateClassScreen._save']);
      expect(typedTitle(t), 'A private yoga', reason: 'the form is kept to try again');
      await unmountAll(t);
    });

    testWidgets('a refused insert is recorded once and said in the existing voice, never raw',
        (t) async {
      server.failing = (s) => s.isWrite;
      await open(t);
      await type(t);
      await t.tap(find.text('Publish Class'));
      await settleReal(t);
      expect(find.textContaining("Couldn't create the class — try again in a moment"),
          findsOneWidget);
      expect(find.textContaining('SECRET_TABLE'), findsNothing);
      expect(reported.map((f) => f.origin), ['CreateClassScreen._save']);
      expect(find.text('Publish Class'), findsOneWidget, reason: 'the button is back');
      await unmountAll(t);
    });

    testWidgets('offline: the connection is named', (t) async {
      server.offline = (s) => s.isWrite;
      await open(t);
      await type(t);
      await t.tap(find.text('Publish Class'));
      await settleReal(t);
      expect(find.textContaining("Couldn't create the class — check your connection"),
          findsOneWidget);
      await unmountAll(t);
    });

    testWidgets('a second Publish landing before the busy button was drawn creates nothing more',
        (t) async {
      await open(t);
      await type(t);
      final publish = tapOf(t, 'Publish Class');
      final hold = server.hold((s) => s.isWrite);
      publish();
      publish(); // two taps in one frame
      await settleReal(t);
      hold.complete();
      await settleReal(t);
      expect(inserts(), hasLength(1), reason: 'the class was created twice');
      await unmountAll(t);
    });
  });

  group('positive controls: the same coach', () {
    testWidgets('Publish creates the class once, as A, and closes as created', (t) async {
      await open(t);
      await type(t);
      final hold = server.hold((s) => s.isWrite);
      await t.tap(find.text('Publish Class'));
      await t.pump();
      expect(find.text('Publish Class'), findsNothing, reason: 'busy while it saves');
      await settleReal(t);
      hold.complete();
      await settleReal(t);
      await t.pump(const Duration(seconds: 1));
      expect(inserts(), hasLength(1));
      expect(inserts().single.who, memberA);
      expect(inserts().single.json,
          allOf(containsPair('coach_id', memberA), containsPair('title', 'A private yoga')));
      expect(popped, isTrue);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets('validation is unchanged: no title, "Add a class title", nothing sent',
        (t) async {
      await open(t);
      await t.tap(find.text('Publish Class'));
      await t.pump();
      expect(find.text('Add a class title'), findsWidgets);
      expect(server.writes, isEmpty);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets('a token refresh keeps the typed form; Publish then creates it as A',
        (t) async {
      await open(t);
      await type(t);
      await refreshToken(t);
      expect(typedTitle(t), 'A private yoga', reason: 'a refresh wiped the form');
      expect(find.byType(CreateClassScreen), findsOneWidget);
      await t.tap(find.text('Publish Class'));
      await settleReal(t);
      expect(inserts().single.who, memberA);
      expect(inserts().single.json, containsPair('coach_id', memberA));
      expect(reported, isEmpty);
      await unmountAll(t);
    });
  });
}
