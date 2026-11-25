import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/nutrition/presentation/widgets/ai_scan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, Supabase;

import '../support/fake_image_picker.dart';
import '../support/pump_until.dart';
import '../support/pump_until_quiet.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-61 round 2 · Log Meal › Scan: whose meal it is, and what the notice
// tells the member to press.
//
// At 924bbf0 a photo read for A was sent for analysis when B signed in between
// the last check and the request; A's finished result was saved by B's tap,
// and A's typed description was sent by it. The notice said "add the meal
// manually" — no control is called that.
//
// The view is mounted on its own (no AccountScope) and NO FRAME is drawn
// between the sign-in and the tap or answer that follows it.
//
// HOW TO SEE IT FAIL: run against 924bbf0's ai_scan_view.dart.

const _result = <String, Object?>{
  'name': 'Rice',
  'calories': 640,
  'protein_g': 45,
  'carbs_g': 60,
  'fat_g': 18,
  'confidence': 88,
};

class _Server extends TwoMemberPostgrest {
  Map<String, Object?> result = _result;

  /// `<who>: photo` or `<who>: <description>`, one per analysis asked for.
  final analyses = <String>[];

  /// Requests taken and not yet answered.
  int busy = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    busy++;
    try {
      return await _send(request);
    } finally {
      busy--;
    }
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('/analyze-food-image')) {
      return super.send(request);
    }
    final body = jsonDecode((request as http.Request).body) as Map;
    analyses.add('${TwoMemberPostgrest.who(request)}: '
        '${body['description'] ?? (body.containsKey('imageBase64') ? 'photo' : '?')}');
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'result': result}))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  final server = _Server();
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];
  final accepted = <ScanResult>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    picker.install();
  });
  tearDownAll(picker.dispose);
  setUp(() async {
    await signInAs(memberA);
    server
      ..reset()
      ..result = _result
      ..busy = 0
      ..analyses.clear();
    picker.reset();
    reported.clear();
    accepted.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> mount(WidgetTester t, {bool searchInstead = true}) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 2400);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiScanView(
          onAccept: accepted.add,
          onSearchInstead: searchInstead ? () {} : null,
        ),
      ),
    ));
    await t.pump();
  }

  /// Until nothing is on its way to the server, then the frames that draw
  /// what came back (round 3: polled, not a fixed budget).
  Future<void> settle(WidgetTester t) => pumpUntilQuiet(
      t, () => server.busy == 0,
      what: 'the server to be quiet',
      calm: 8,
      step: const Duration(milliseconds: 50));

  Future<void> waitFor(WidgetTester t, String text) => pumpUntil(
      t, () => find.text(text).evaluate().isNotEmpty, what: '"$text"');

  Future<void> describe(WidgetTester t) async {
    await t.enterText(find.byType(TextField), 'chicken salad');
    await t.tap(find.byIcon(Icons.auto_awesome));
    await t.pump();
  }

  Future<void> scanned(WidgetTester t) async {
    await describe(t);
    await waitFor(t, '640 kcal');
  }

  /// B, signed in on the same device; no frame is drawn.
  Future<void> bSignsIn(WidgetTester t) async {
    await t.runAsync(() => signInAs(memberB));
    expect(Supabase.instance.client.auth.currentUser?.id, memberB);
  }

  /// A's member event that really fires: the token refreshed.
  Future<void> tokenRefresh(WidgetTester t) async {
    final events = <AuthChangeEvent>[];
    final sub = Supabase.instance.client.auth.onAuthStateChange
        .listen((s) => events.add(s.event));
    await t.runAsync(refreshSession);
    expect(events, contains(AuthChangeEvent.tokenRefreshed),
        reason: 'premise: the event really arrived');
    unawaited(sub.cancel());
  }

  /// Runs [then] inside the rebuild the view asks for when its photo has been
  /// read — after its last check of the member, before the request. No frame.
  void whenPhotoRead(WidgetTester t, void Function() then) {
    final owner = t.binding.buildOwner!;
    final original = owner.onBuildScheduled;
    final view = t.element(find.byType(AiScanView));
    var done = false;
    addTearDown(() => owner.onBuildScheduled = original);
    owner.onBuildScheduled = () {
      original?.call();
      // (Only the view's own: its text field rebuilds for reasons of its own.)
      if (done || !view.dirty) return;
      done = true;
      then();
    };
  }

  Future<void> photo(WidgetTester t, {required void Function() read}) async {
    final gate = Completer<Object?>();
    picker.answer = (_) => gate.future;
    await t.tap(find.text('Choose from Gallery'));
    await settle(t); // the picker is open, and drawn as such
    gate.complete(picker.photoPath);
    whenPhotoRead(t, read);
  }

  // ── _analyze ─────────────────────────────────────────────────────────────

  testWidgets("A's photo is read; B signs in before it is sent: it is not "
      'sent, nothing is said, it is recorded', (t) async {
    await mount(t);
    var switched = false;
    await photo(t, read: () {
      switched = true;
      unawaited(signInAs(memberB));
      expect(Supabase.instance.client.auth.currentUser?.id, memberB,
          reason: 'premise: at once, with no frame');
    });
    await pumpUntil(
        t, () => reported.isNotEmpty || server.analyses.isNotEmpty,
        what: 'the refusal');
    await settle(t);
    expect(switched, isTrue, reason: 'premise');
    expect(server.analyses, isEmpty, reason: "THE defect: A's photo, sent");
    expect(origins(), ['nutrition.scan.identity']);
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(find.text('Analyzing your meal...'), findsNothing);
    // B's own photo works.
    picker.answer = (_) async => picker.photoPath;
    await t.tap(find.text('Choose from Gallery'));
    await waitFor(t, '640 kcal');
    expect(server.analyses, ['$memberB: photo']);
  });

  testWidgets("SAME ACCOUNT: A's token is refreshed at that moment: the photo "
      'is sent, answered, and saved once', (t) async {
    await mount(t);
    final events = <AuthChangeEvent>[];
    final sub = Supabase.instance.client.auth.onAuthStateChange
        .listen((s) => events.add(s.event));
    await photo(t, read: () => unawaited(refreshSession()));
    await waitFor(t, '640 kcal');
    expect(events, contains(AuthChangeEvent.tokenRefreshed),
        reason: 'premise: the event really arrived');
    expect(server.analyses, ['$memberA: photo']);
    await t.tap(find.text('Save to lunch'));
    expect(accepted, hasLength(1));
    expect(reported, isEmpty);
    unawaited(sub.cancel());
  });

  // ── Save ─────────────────────────────────────────────────────────────────

  for (final (how, press) in <(String, void Function(WidgetTester))>[
    (
      'touch',
      (t) => t
          .widget<GestureDetector>(find
              .ancestor(
                  of: find.text('Save to lunch'),
                  matching: find.byType(GestureDetector))
              .first)
          .onTap!()
    ),
    (
      'a screen reader',
      (t) {
        final n = t.getSemantics(find.bySemanticsLabel('Save to lunch'));
        n.owner!.performAction(n.id, SemanticsAction.tap);
      }
    ),
  ]) {
    testWidgets("A's result is on screen; B signs in and saves ($how), no "
        'frame between: nothing is saved or said, and it is gone', (t) async {
      final handle = t.ensureSemantics();
      await mount(t);
      await scanned(t);
      await bSignsIn(t);
      press(t);
      expect(accepted, isEmpty, reason: "THE defect: A's meal, B's log");
      expect(origins(), ['nutrition.scan.identity']);
      await settle(t);
      for (final text in ['Rice', '640 kcal', 'chicken salad']) {
        expect(find.text(text), findsNothing, reason: text);
      }
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(find.text('Scan Meal'), findsOneWidget, reason: 'usable');
      // B's own scan saves.
      await scanned(t);
      press(t);
      expect(accepted, hasLength(1));
      expect(server.analyses.last, startsWith(memberB));
      handle.dispose();
    });
  }

  testWidgets('signed out with a result on screen: Save saves nothing',
      (t) async {
    await mount(t);
    await scanned(t);
    await t.runAsync(signOut);
    await t.tap(find.text('Save to lunch'));
    expect(accepted, isEmpty);
    await settle(t);
    expect(find.text('Rice'), findsNothing);
  });

  testWidgets('SAME ACCOUNT: a token refresh keeps the result; it saves once',
      (t) async {
    await mount(t);
    await scanned(t);
    await tokenRefresh(t);
    await t.tap(find.text('Save to lunch'));
    expect(accepted.single.calories, 640);
    await settle(t);
    expect(find.text('640 kcal'), findsOneWidget);
    expect(reported, isEmpty);
  });

  // ── the typed description ────────────────────────────────────────────────

  for (final (how, send) in <(String, Future<void> Function(WidgetTester))>[
    ('the button', (t) => t.tap(find.byIcon(Icons.auto_awesome))),
    ('the keyboard', (t) => t.testTextInput.receiveAction(TextInputAction.send)),
  ]) {
    testWidgets("A's words are in the field; B signs in and sends them ($how), "
        'no frame between: they are not sent, and are cleared', (t) async {
      await mount(t);
      await t.enterText(find.byType(TextField), 'chicken salad');
      await t.pump();
      await bSignsIn(t);
      await send(t);
      await pumpUntil(
          t, () => reported.isNotEmpty || server.analyses.isNotEmpty,
          what: 'the refusal');
      await settle(t);
      expect(server.analyses, isEmpty, reason: "THE defect: A's words, as B");
      expect(origins(), ['nutrition.scan.identity']);
      expect(find.text('chicken salad'), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
      // B's own words work.
      await scanned(t);
      expect(server.analyses, ['$memberB: chicken salad']);
    });
  }

  testWidgets("B types on at the end of A's words: they are still A's, and are "
      'not sent', (t) async {
    await mount(t);
    await t.enterText(find.byType(TextField), 'chicken salad');
    await t.pump();
    await bSignsIn(t);
    await t.enterText(find.byType(TextField), 'chicken salad and rice');
    await t.tap(find.byIcon(Icons.auto_awesome));
    await pumpUntil(
        t, () => reported.isNotEmpty || server.analyses.isNotEmpty,
        what: 'the refusal');
    await settle(t);
    expect(server.analyses, isEmpty);
    expect(find.text('chicken salad and rice'), findsNothing);
    // Emptied and typed again by B, they are B's.
    await scanned(t);
    expect(server.analyses, ['$memberB: chicken salad']);
  });

  testWidgets("A's words are still being analysed when B signs in: B is left "
      'neither the answer nor the words', (t) async {
    await mount(t);
    await describe(t);
    await bSignsIn(t);
    await pumpUntil(t, () => reported.isNotEmpty, what: 'the refusal');
    await settle(t);
    expect(find.text('640 kcal'), findsNothing);
    expect(find.text('chicken salad'), findsNothing);
    expect(origins(), ['nutrition.scan.identity']);
  });

  testWidgets('SAME ACCOUNT: a token refresh keeps the words; they are sent',
      (t) async {
    await mount(t);
    await t.enterText(find.byType(TextField), 'chicken salad');
    await t.pump();
    await tokenRefresh(t);
    await t.pump();
    expect(find.text('chicken salad'), findsOneWidget);
    await t.tap(find.byIcon(Icons.auto_awesome));
    await waitFor(t, '640 kcal');
    expect(server.analyses, ['$memberA: chicken salad']);
    expect(reported, isEmpty);
  });

  // ── the notice ───────────────────────────────────────────────────────────

  testWidgets('a missing value: the notice names the control that is there',
      (t) async {
    server.result = {..._result, 'fat_g': null};
    await mount(t);
    await describe(t);
    await waitFor(t, 'Retake');
    expect(
        find.text("Couldn't read the fat for this meal — retake it, or tap "
            'Search instead to add it yourself. Saving is off for this scan.'),
        findsOneWidget);
    expect(find.text('Search instead'), findsOneWidget);
    expect(find.textContaining('manually'), findsNothing);
  });

  testWidgets('NEGATIVE CONTROL: with no Search instead, it is not named',
      (t) async {
    server.result = {..._result, 'fat_g': null};
    await mount(t, searchInstead: false);
    await describe(t);
    await waitFor(t, 'Retake');
    expect(
        find.text("Couldn't read the fat for this meal — retake it. Saving is "
            'off for this scan.'),
        findsOneWidget);
    expect(find.textContaining('Search instead'), findsNothing);
  });
}
