import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_pricing_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_tools_server.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59d (W8) · the Coaching Price sheet saves the coach it loaded.
//
// It stayed open over a switch on this device, and Save wrote the price coach
// A had loaded or typed onto coach B's `pricing_monthly`.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- apps/mobile/lib/features/
// coach/presentation/coach_pricing_sheet.dart`; only the controls pass.

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
    server.tables['user_profiles'] = [
      {'id': memberA, 'pricing_monthly': 120},
      {'id': memberB, 'pricing_monthly': 300},
    ];
  });
  tearDown(resetFailureSink);

  Future<void> open(WidgetTester t, {String? uid = memberA}) async {
    if (uid == null) {
      await t.runAsync(signOut);
    } else {
      await t.runAsync(() => signInAs(uid));
    }
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(
        onPressed: () => showCoachPricingSheet(c), child: const Text('open'))))));
    await t.tap(find.text('open'));
    await settleReal(t);
  }

  final sheet = find.text('Coaching Price');
  Finder price(String p) => find.widgetWithText(TextField, p);
  const saved = 'Pricing updated. Clients will see your new rate.';

  testWidgets("A→B: A's price goes with A; the Save already tapped writes nothing",
      (t) async {
    await open(t);
    await t.enterText(find.byType(TextField), '150');
    final save = tapOf(t, 'Save price');
    await switchTo(t, memberB);
    expect(sheet, findsNothing);
    expect(find.text('150'), findsNothing);
    save();
    await settleReal(t);
    expect(server.writes, isEmpty, reason: "A's price was saved on B");
    expect(reported.map((f) => f.origin), ['CoachPricingSheet._save']);
    expect('${reported.single.error}', contains('signed-in account changed'));
    expect(find.byType(SnackBar), findsNothing);
    await unmountAll(t);
  });

  testWidgets('a Save tapped before the sheet noticed writes nothing', (t) async {
    await open(t);
    final save = tapOf(t, 'Save price');
    await t.runAsync(() => signInAs(memberB));
    save();
    await settleReal(t);
    expect(server.writes, isEmpty);
    expect(sheet, findsNothing);
    await unmountAll(t);
  });

  for (final fails in [false, true]) {
    testWidgets('switch during the save (${fails ? 'it fails' : 'it saves'}): '
        "A's row only, and B is told nothing", (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), '150');
      final hold = server.hold((s) => s.isWrite);
      if (fails) server.failing = (s) => s.isWrite;
      await t.tap(find.text('Save price'));
      await settleReal(t);
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(server.writes.single.who, memberA);
      expect(server.writes.single.query, contains('id=eq.$memberA'));
      expect(find.byType(SnackBar), findsNothing);
      expect(sheet, findsNothing);
      expect(reported.length, fails ? 1 : 0, reason: 'a failure is still recorded');
      await unmountAll(t);
    });
  }

  testWidgets("A's late price is never put in a field for B", (t) async {
    final late = server.hold((s) => s.who == memberA);
    await open(t);
    await switchTo(t, memberB);
    late.complete();
    await settleReal(t);
    expect(find.text('120'), findsNothing);
    expect(reported, isEmpty);
    await unmountAll(t);
  });

  testWidgets('signed out: the sheet closes', (t) async {
    await open(t);
    await signOutNow(t);
    expect(sheet, findsNothing);
    expect(find.text('120'), findsNothing);
    expect(server.writes, isEmpty);
    await unmountAll(t);
  });

  testWidgets('opened signed out, then B signs in: B\'s own price', (t) async {
    await open(t, uid: null);
    expect(find.textContaining("You're signed out"), findsOneWidget, reason: 'premise');
    await switchTo(t, memberB);
    expect(price('300'), findsOneWidget);
    expect(find.textContaining("You're signed out"), findsNothing);
    await unmountAll(t);
  });

  testWidgets('positive control: a token refresh keeps what was typed, and Save '
      'saves it', (t) async {
    await open(t);
    expect(price('120'), findsOneWidget);
    await t.enterText(find.byType(TextField), '150');
    await refreshToken(t);
    expect(price('150'), findsOneWidget);
    await t.tap(find.text('Save price'));
    await settleReal(t);
    final w = server.writes.single;
    expect(w.who, memberA);
    expect(w.query, contains('id=eq.$memberA'));
    expect(w.json, {'pricing_monthly': 150.0});
    expect(find.text(saved), findsOneWidget);
    expect(reported, isEmpty);
    await unmountAll(t);
  });

  testWidgets('negative control: no price yet is an empty field, not an error',
      (t) async {
    server.tables['user_profiles'] = [{'id': memberA, 'pricing_monthly': null}];
    await open(t);
    expect(price(''), findsOneWidget);
    expect(find.textContaining("Couldn't"), findsNothing);
    await unmountAll(t);
  });
}
