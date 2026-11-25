import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_video_response_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_tools_server.dart';
import '../support/fake_image_picker.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59d (W17) · a video response is sent by the coach who made it.
//
// The page stayed up over a switch on this device: coach B saw coach A's
// client and note, and Send sent them as B. A switch during the upload left
// the response refused and the next steps running as B.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- apps/mobile/lib/features/
// coach/presentation/coach_video_response_screen.dart`; only the controls pass.

void main() {
  final server = CoachToolsServer();
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];

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
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> open(WidgetTester t) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(t.view.reset);
    await t.runAsync(() => signInAs(memberA));
    await t.pumpWidget(const MaterialApp(home: CoachVideoResponseScreen(
        clientId: 'client-ana', clientName: 'Ana Client', checkinId: 'chk-1')));
    await settleReal(t);
  }

  Future<void> note(WidgetTester t, [String text = 'Great depth']) async {
    await t.enterText(find.byType(TextField), text);
    await t.pump();
  }

  Future<void> pick(WidgetTester t) async {
    await t.tap(find.text('From Gallery'));
    await settleReal(t);
    expect(find.text('photo.png'), findsOneWidget, reason: 'premise: picked');
  }

  bool uploads(Sent s) => s.path.startsWith('/storage/v1/') && s.isWrite;
  Iterable<Sent> inserts() => server.to('coach_video_responses');
  Iterable<String> changed() => reported
      .where((f) => '${f.error}'.contains('signed-in account changed'))
      .map((f) => f.origin);

  void blank(WidgetTester t) {
    expect(find.textContaining('Ana'), findsNothing, reason: "A's client is named to B");
    expect(find.text('Great depth'), findsNothing, reason: "A's note is shown to B");
    expect(find.text('photo.png'), findsNothing);
    expect(find.text('Send to Client'), findsNothing);
  }

  testWidgets("A→B: A's client, note and video are gone; the Send already tapped "
      'sends nothing', (t) async {
    await open(t);
    await pick(t);
    await note(t);
    final send = tapOf(t, 'Send to Client');
    await t.runAsync(() => signInAs(memberB));
    send(); // before the page noticed
    await settleReal(t);
    blank(t);
    expect(server.writes, isEmpty, reason: "A's response was sent as B");
    expect(changed(), isNotEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await unmountAll(t);
  });

  testWidgets('signed out: gone; the same coach back again: theirs to use, empty',
      (t) async {
    await open(t);
    await note(t);
    await signOutNow(t);
    blank(t);
    await switchTo(t, memberB);
    blank(t);
    await signOutNow(t);
    await switchTo(t, memberA);
    expect(find.text('To Ana Client'), findsOneWidget);
    expect(find.text('Great depth'), findsNothing);
    await note(t, 'Second try');
    await t.tap(find.text('Send to Client'));
    await settleReal(t);
    expect(inserts().single.json, containsPair('coach_id', memberA));
    expect(inserts().single.json, containsPair('notes', 'Second try'));
    await unmountAll(t);
  });

  testWidgets('switch before the upload: nothing is stored (no orphan)', (t) async {
    await open(t);
    await pick(t);
    await t.tap(find.text('Send to Client'));
    // The file is being read (real I/O); nothing has been sent yet.
    expect(server.writes, isEmpty, reason: 'premise');
    await t.runAsync(() => signInAs(memberB));
    await pumpUntil(t, () => changed().isNotEmpty || server.writes.isNotEmpty,
        what: 'the send to stop');
    await settleReal(t);
    expect(server.writes, isEmpty, reason: "an upload ran on B's session");
    blank(t);
    await unmountAll(t);
  });

  testWidgets('switch during the upload: no response and no notification as B',
      (t) async {
    await open(t);
    await pick(t);
    final hold = server.hold(uploads);
    await t.tap(find.text('Send to Client'));
    await pumpUntil(t, () => server.writes.isNotEmpty, what: 'the upload');
    expect(server.writes.single.who, memberA);
    await switchTo(t, memberB);
    hold.complete();
    await settleReal(t);
    expect(server.writes, hasLength(1));
    expect(changed(), ['CoachVideoResponseScreen._send']);
    blank(t);
    await unmountAll(t);
  });

  testWidgets('switch during the insert: the client is not notified as B', (t) async {
    await open(t);
    await note(t);
    final hold = server.hold((s) => s.table == 'coach_video_responses');
    await t.tap(find.text('Send to Client'));
    await settleReal(t);
    await switchTo(t, memberB);
    hold.complete();
    await settleReal(t);
    expect(server.to('notifications'), isEmpty);
    expect(find.text('Video Sent!'), findsNothing);
    expect(changed(), ['CoachVideoResponseScreen._send']);
    await unmountAll(t);
  });

  testWidgets("A's failed send is recorded, and not said to B", (t) async {
    await open(t);
    await note(t);
    final hold = server.hold((s) => s.isWrite);
    server.failing = (s) => s.isWrite;
    await t.tap(find.text('Send to Client'));
    await settleReal(t);
    await switchTo(t, memberB);
    hold.complete();
    await settleReal(t);
    expect(reported.map((f) => f.origin), ['CoachVideoResponseScreen._send']);
    expect(find.byType(SnackBar), findsNothing);
    await unmountAll(t);
  });

  testWidgets("a video A picked is not put on B's page", (t) async {
    await open(t);
    final gate = Completer<String?>();
    picker.answer = (_) => gate.future;
    await t.tap(find.text('From Gallery'));
    await settleReal(t);
    await switchTo(t, memberB);
    gate.complete(picker.photoPath);
    await settleReal(t);
    blank(t);
    await switchTo(t, memberA);
    expect(find.text('photo.png'), findsNothing, reason: 'it was dropped, not kept');
    await unmountAll(t);
  });

  testWidgets('positive control: a token refresh keeps the draft; A sends video '
      'and note (OD-57 copy unchanged)', (t) async {
    await open(t);
    await pick(t);
    await note(t);
    await refreshToken(t);
    expect(find.text('photo.png'), findsOneWidget);
    await t.tap(find.text('Send to Client'));
    await pumpUntil(t, () => find.text('Video Sent!').evaluate().isNotEmpty,
        what: 'Video Sent!');
    expect(server.writes.map((s) => s.who).toSet(), {memberA});
    final path = server.writes.first.path;
    expect(path, contains('coach-videos/$memberA/client-ana/'));
    final row = inserts().single.json;
    expect(row, allOf(containsPair('coach_id', memberA), containsPair('client_id', 'client-ana'),
        containsPair('checkin_id', 'chk-1'), containsPair('notes', 'Great depth')));
    expect(path, endsWith('${row['video_url']}'));
    expect(server.to('notifications').single.json['body'],
        'Your coach recorded a personal video response for you. Tap to watch.');
    expect(find.text('Ana Client has been notified and can watch your response.'),
        findsOneWidget);
    expect(reported, isEmpty);
    await unmountAll(t);
  });

  testWidgets('negative control: nothing to send stays nothing to send', (t) async {
    await open(t);
    await note(t, '   ');
    expect(t.widget<ElevatedButton>(find.bySubtype<ElevatedButton>()).onPressed, isNull);
    expect(server.writes, isEmpty);
    await unmountAll(t);
  });
}
