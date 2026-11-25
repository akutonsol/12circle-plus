// P0-FL-59e · W7 / E3: one member's weights, measurements and body photos are
// never shown to, or saved for, another; and (routed from FL-60) a photo that
// cannot be opened is not "no photo".
//
// The screen read once and stayed: after A -> B in another tab it showed A's
// signed body-photo URLs and weights to B, and A's Log Weight sheet (prefilled
// with A's values) inserted under a fresh `currentUser` — B.
//
// HOW TO SEE IT FAIL: put back a82f993's progress_screen.dart; every test but
// the POSITIVE / NEGATIVE CONTROLs fails. (Round 2's "while A's photo is being
// stored", "B's Add Photo", missing-photo and large-text tests fail on 5f8b7f3
// too.)
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/progress/presentation/progress_screen.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_image_picker.dart';
import '../support/member_switch_server.dart';
import '../support/pump_until.dart';

void main() {
  final server = MemberSwitchServer();
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    picker.install();
  });
  tearDownAll(picker.dispose);

  setUp(() async {
    server.reset();
    picker.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
    const at = '2026-11-20T08:00:00Z';
    server.rows.addAll({
      'user_profiles': {
        memberA: [{'weight_kg': 91.1, 'weight_goal_kg': 81.5}],
        memberB: [{'weight_kg': 61.1, 'weight_goal_kg': 55.5}],
      },
      'weight_logs': {
        memberA: [{'weight_kg': 91.7, 'logged_at': at}],
        memberB: [{'weight_kg': 62.3, 'logged_at': at}],
      },
      'body_measurements': {
        memberA: [{'waist_cm': 99.9, 'logged_at': at}],
        memberB: [{'waist_cm': 66.6, 'logged_at': at}],
      },
    });
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);
  Iterable<SeenRequest> asB() => server.writes().where((w) => w.who == memberB);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t,
      {String? tab, Size size = const Size(500, 2600)}) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ProgressScreen())));
    await settle(t);
    if (tab != null) {
      await t.tap(find.text(tab));
      await settle(t);
    }
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  Future<void> switchTo(WidgetTester t, String uid) =>
      t.runAsync(() => signInAs(uid));

  /// URLs of every photo on screen.
  Iterable<String> photos(WidgetTester t) => t
      .widgetList<Image>(find.byType(Image))
      .map((i) => i.image)
      .whereType<NetworkImage>()
      .map((i) => i.url);

  void nothingOfA(WidgetTester t) {
    for (final s in ['91.7', '91.7 kg', '91.1', '81.5', '99.9 cm']) {
      expect(find.text(s), findsNothing, reason: "A's $s is on screen");
    }
    expect(photos(t).where((u) => u.contains(memberA)), isEmpty,
        reason: "A's body photos are on screen");
  }

  Future<void> quiet(WidgetTester t) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      // QAX-UI-01/02: recorded pre-existing overflows of the weight sheet.
      if (d.exceptionAsString().contains('A RenderFlex overflowed')) return;
      previous?.call(d);
    };
    addTearDown(() => FlutterError.onError = previous);
  }

  /// The whole text is laid out, unshrunk, inside every box that clips it.
  void expectWhole(WidgetTester t, Finder text, double scale) {
    final widget = t.widget<Text>(text);
    expect(widget.overflow, isNull);
    expect(widget.maxLines, isNull);
    expect(
        find.ancestor(of: text, matching: find.byType(FittedBox)), findsNothing);
    final box = t.getRect(text);
    final lines = t.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)));
    expect(lines.textScaler.scale(widget.style!.fontSize!),
        closeTo(widget.style!.fontSize! * scale, .01));
    expect(lines.didExceedMaxLines, isFalse);
    for (final clip in find
        .ancestor(of: text, matching: find.byType(ClipPath))
        .evaluate()
        .followedBy(
            find.ancestor(of: text, matching: find.byType(Stack)).evaluate())) {
      final r = t.getRect(find.byElementPredicate((e) => e == clip));
      expect(r.top, lessThanOrEqualTo(box.top + .01));
      expect(r.bottom, greaterThanOrEqualTo(box.bottom - .01),
          reason: 'cut off by ${clip.widget}');
    }
    for (final slot in find
        .ancestor(of: text, matching: find.byType(AspectRatio))
        .evaluate()) {
      final r = t.getRect(find.byElementPredicate((e) => e == slot));
      expect(r.bottom, greaterThanOrEqualTo(box.bottom - .01),
          reason: 'taller than its slot');
    }
  }

  group('what is shown', () {
    testWidgets("A -> B: A's numbers and photos go, B's own are read",
        (t) async {
      server.objects.addAll(['$memberA/front.jpg', '$memberB/side.jpg']);
      await open(t, tab: 'Photos');
      expect(photos(t).where((u) => u.contains(memberA)), isNotEmpty,
          reason: 'premise');
      server.seen.clear();
      await switchTo(t, memberB);
      await settle(t);
      nothingOfA(t);
      expect(photos(t).where((u) => u.contains(memberB)), isNotEmpty);
      await t.tap(find.text('Weight'));
      await settle(t);
      expect(find.text('62.3'), findsWidgets);
      nothingOfA(t);
      expect(server.seen.map((r) => r.who).toSet(), {memberB});
      await close(t);
    });

    testWidgets("B's read pending, then failed: never A's; Try again loads B's",
        (t) async {
      await open(t);
      final hold = server.holds['GET weight_logs:$memberB'] = Completer();
      server.fails.add('GET weight_logs:$memberB');
      await switchTo(t, memberB);
      await settle(t);
      nothingOfA(t);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('No entries yet'), findsNothing);
      hold.complete();
      await settle(t);
      nothingOfA(t);
      expect(find.text('Could not load your progress'), findsOneWidget);
      server.fails.clear();
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text('62.3'), findsWidgets);
      await close(t);
    });

    testWidgets("A's load answers after B signed in (before and after B's "
        'own): dropped', (t) async {
      for (final aFirst in [true, false]) {
        await switchTo(t, memberA);
        final holdA = server.holds['GET weight_logs:$memberA'] = Completer();
        final holdB = server.holds['GET weight_logs:$memberB'] = Completer();
        await open(t);
        await switchTo(t, memberB);
        await settle(t);
        server.seen.clear();
        (aFirst ? holdA : holdB).complete();
        await settle(t);
        nothingOfA(t);
        (aFirst ? holdB : holdA).complete();
        await settle(t);
        nothingOfA(t);
        expect(find.text('62.3'), findsWidgets, reason: 'aFirst: $aFirst');
        expect(server.seen.where((r) => '${r.query}'.contains(memberA)), isEmpty,
            reason: "the rest of A's load was asked as B");
        await close(t);
      }
    });

    testWidgets("signed out: A's progress goes away, and nothing is claimed; "
        'A back in: theirs again', (t) async {
      await open(t);
      await t.runAsync(signOut);
      await settle(t);
      nothingOfA(t);
      expect(find.textContaining('No entries yet'), findsNothing);
      expect(find.textContaining("You're signed out"), findsOneWidget);
      await switchTo(t, memberA);
      await settle(t);
      expect(find.text('91.7'), findsWidgets);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: a token refresh reads nothing and keeps the '
        'screen', (t) async {
      await open(t);
      server.seen.clear();
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text('91.7'), findsWidgets);
      // (The shared scaffold re-reads its own profile; this screen nothing.)
      expect(server.reads('weight_logs'), isEmpty);
      expect(server.reads('body_measurements'), isEmpty);
      await close(t);
    });

    testWidgets('NEGATIVE CONTROL: a member with nothing logged is empty, not '
        'a failure', (t) async {
      server.rows.clear();
      await open(t);
      expect(find.textContaining('No entries yet'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      await t.tap(find.text('Photos'));
      await settle(t);
      expect(find.text('Add'), findsNWidgets(3));
      expect(find.text('No check-ins yet'), findsOneWidget);
      expect(find.byType(SectionLoadFailure), findsNothing);
      expect(reported, isEmpty);
      await close(t);
    });
  });

  group('Log Weight', () {
    Future<void> openSheet(WidgetTester t) async {
      await quiet(t);
      await open(t);
      await t.tap(find.byIcon(Icons.add).last);
      await settle(t);
      expect(find.text('Save Entry'), findsOneWidget, reason: 'premise');
      server.seen.clear();
    }

    testWidgets("Save tapped in A's undrawn sheet once B is signed in: no row "
        "for B, and the sheet with A's value is gone", (t) async {
      await openSheet(t);
      await switchTo(t, memberB);
      await t.tap(find.text('Save Entry'), warnIfMissed: false);
      await settle(t);
      expect(server.writes('weight_logs'), isEmpty,
          reason: "A's weight is in B's weight_logs");
      expect(find.text('Save Entry'), findsNothing);
      nothingOfA(t);
      expect(find.textContaining("Couldn't"), findsNothing);
      await close(t);
    });

    testWidgets("A's save answers after B signed in: nothing more, nothing "
        'said to B', (t) async {
      await openSheet(t);
      final hold = server.holds['POST weight_logs:$memberA'] = Completer();
      server.fails.add('POST weight_logs:$memberA');
      await t.tap(find.text('Save Entry'));
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writes('weight_logs').single.row['user_id'], memberA);
      expect(asB(), isEmpty);
      expect(find.text(progressSaveFailedMessage), findsNothing);
      nothingOfA(t);
      await close(t);
    });

    testWidgets('signed out with the sheet open: nothing is sent', (t) async {
      await openSheet(t);
      await t.runAsync(signOut);
      await t.tap(find.text('Save Entry'), warnIfMissed: false);
      await settle(t);
      expect(server.writes(), isEmpty);
      expect(find.text('Save Entry'), findsNothing);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: after a token refresh the sheet is still '
        "there and saves to its member's row", (t) async {
      await openSheet(t);
      await t.runAsync(refreshSession);
      await settle(t);
      await t.tap(find.text('Save Entry'));
      await settle(t);
      expect(server.writes('weight_logs').single.row['user_id'], memberA);
      expect(server.writes('weight_logs').single.row['weight_kg'], 91.7);
      expect(find.text('Save Entry'), findsNothing);
      await close(t);
    });
  });

  group('Log Measurements', () {
    Future<void> openSheet(WidgetTester t) async {
      await open(t, tab: 'Measurements');
      await t.tap(find.text('Log Measurement'));
      await settle(t);
      expect(find.widgetWithText(TextField, '99.9'), findsOneWidget, reason: 'premise: prefilled');
      server.seen.clear();
    }

    testWidgets("Save tapped in A's undrawn sheet once B is signed in: no row "
        'and no points for B', (t) async {
      await openSheet(t);
      await switchTo(t, memberB);
      await t.tap(find.text('Save Measurements'), warnIfMissed: false);
      await settle(t);
      expect(server.writes(), isEmpty);
      expect(find.text('99.9'), findsNothing);
      expect(find.text('66.6 cm'), findsOneWidget, reason: "B's own");
      await close(t);
    });

    testWidgets("A's row is stored after B signed in: no check-in points for B",
        (t) async {
      await openSheet(t);
      final hold = server.holds['POST body_measurements:$memberA'] = Completer();
      await t.tap(find.text('Save Measurements'));
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writes('body_measurements').single.row['user_id'], memberA);
      expect(asB(), isEmpty);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: stored and awarded to its member',
        (t) async {
      await openSheet(t);
      await t.tap(find.text('Save Measurements'));
      await settle(t);
      expect(server.writes('body_measurements').single.row['user_id'], memberA);
      expect(server.writes('daily_scores').single.row['user_id'], memberA);
      await close(t);
    });
  });

  group('photos', () {
    testWidgets("A's upload fails after B signed in: B is not told",
        (t) async {
      await open(t, tab: 'Photos');
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await t.tap(find.text('Add Photo'));
      await settle(t);
      await t.tap(find.text('Choose from Gallery'));
      await settle(t);
      final hold = server.holds['POST progress_photo_logs:$memberA'] =
          Completer();
      server.fails.add('POST progress_photo_logs:$memberA');
      gate.complete(picker.photoPath);
      await pumpUntil(
          t, () => server.writes('progress_photo_logs').isNotEmpty,
          what: 'the row');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(find.byType(SnackBar), findsNothing,
          reason: "B was told about A's photo");
      expect(origins(), contains('progress.photo.save'));
      expect(asB(), isEmpty);
      nothingOfA(t);
      await close(t);
    });

    testWidgets("B signs in between A's upload and its log row: no row is "
        'sent as B', (t) async {
      await open(t, tab: 'Photos');
      await t.tap(find.text('Add Photo'));
      await settle(t);
      // Every upload of A's is held (its path has a timestamp).
      final held = Completer<void>();
      server.holdUploadsOf = memberA;
      server.uploadGate = held;
      await t.tap(find.text('Choose from Gallery'));
      await pumpUntil(
          t,
          () => server
              .writes()
              .any((w) => w.target.startsWith('progress-photos/')),
          what: 'the upload');
      await switchTo(t, memberB);
      held.complete();
      await settle(t);
      expect(server.writes('progress_photo_logs'), isEmpty);
      expect(asB(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await close(t);
    });

    testWidgets("B signs in while A's photo is being stored: B's own progress "
        'is read and shown, and no failure is claimed', (t) async {
      await open(t, tab: 'Photos');
      final hold = server.holds['POST progress_photo_logs:$memberA'] =
          Completer();
      await t.tap(find.text('Add Photo'));
      await settle(t);
      await t.tap(find.text('Choose from Gallery'));
      await pumpUntil(
          t, () => server.writes('progress_photo_logs').isNotEmpty,
          what: 'the row');
      server.seen.clear();
      await switchTo(t, memberB);
      await settle(t);
      expect(find.text('Could not load your progress'), findsNothing);
      expect(server.reads('weight_logs', memberB), hasLength(1));
      hold.complete();
      await settle(t);
      expect(server.reads('weight_logs', memberB), hasLength(1),
          reason: "A's photo reloaded B's screen");
      expect(
          server.seen.where(
              (r) => r.who == memberB && '${r.query}'.contains(memberA)),
          isEmpty);
      await t.tap(find.text('Weight'));
      await settle(t);
      expect(find.text('62.3'), findsWidgets);
      expect(asB(), isEmpty);
      await close(t);
    });

    testWidgets("A's picker is unanswered: B's Add Photo opens; A's late answer "
        "neither stores as B nor unlocks B's", (t) async {
      await open(t, tab: 'Photos');
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await t.tap(find.text('Add Photo'));
      await settle(t);
      await t.tap(find.text('Choose from Gallery'));
      await settle(t);
      await switchTo(t, memberB);
      await settle(t);
      await t.tap(find.text('Add Photo'));
      await settle(t);
      expect(find.text('Take Photo'), findsOneWidget,
          reason: "B's Add Photo did nothing");
      gate.complete(picker.photoPath);
      await settle(t);
      expect(server.writes(), isEmpty);
      // B's own source sheet is still the one up, and only one.
      expect(find.text('Take Photo'), findsOneWidget);
      await close(t);
    });

    for (final kind in ['fails', 'unreadable']) {
      testWidgets("A's pick $kind after B signed in: recorded, B is not told",
          (t) async {
        await open(t, tab: 'Photos');
        final gate = Completer<Object?>();
        picker.answer = (_) => gate.future;
        await t.tap(find.text('Add Photo'));
        await settle(t);
        await t.tap(find.text('Choose from Gallery'));
        await settle(t);
        await switchTo(t, memberB);
        kind == 'fails'
            ? gate.completeError(
                PlatformException(code: 'photo_access_denied'))
            : gate.complete('/nowhere/none.png');
        await pumpUntil(
            t, () => origins().any((o) => o.startsWith('progress.photo.')),
            what: 'the record');
        await settle(t);
        expect(find.byType(SnackBar), findsNothing);
        expect(server.writes(), isEmpty);
        await close(t);
      });
    }

    testWidgets("A's baseline upload fails after B signed in: recorded, B is "
        'not told', (t) async {
      await open(t, tab: 'Photos');
      final key = 'POST progress-photos/$memberA/front.png:$memberA';
      final hold = server.holds[key] = Completer();
      server.fails.add(key);
      await t.tap(find.text('Front'));
      await settle(t);
      await t.tap(find.text('Choose from Gallery'));
      await pumpUntil(
          t,
          () => server.writes().any((w) => w.target.contains('front.png')),
          what: 'the upload');
      await switchTo(t, memberB);
      await settle(t);
      hold.complete();
      await pumpUntil(t, () => origins().contains('progress.baseline.upload'),
          what: 'the record');
      await settle(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(asB(), isEmpty);
      await close(t);
    });

    testWidgets("A's photo source sheet goes with A", (t) async {
      await open(t, tab: 'Photos');
      await t.tap(find.text('Add Photo'));
      await settle(t);
      expect(find.text('Take Photo'), findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      await settle(t);
      expect(find.text('Take Photo'), findsNothing);
      await close(t);
    });

    testWidgets('a stored baseline that cannot be opened: recorded, said, not '
        '"Add"; Try again opens it', (t) async {
      server.objects.add('$memberA/front.jpg');
      server.unsignable.add('$memberA/front.jpg');
      await open(t, tab: 'Photos');
      expect(origins(), ['ProgressScreen.openPhoto']);
      expect(find.text("Couldn't load some of your photos"), findsOneWidget);
      expect(find.text("Couldn't open"), findsOneWidget);
      expect(find.text('Add'), findsNWidgets(2),
          reason: 'side and back really are absent');
      expect(find.textContaining('SECRET'), findsNothing);
      final retry = find.widgetWithText(TextButton, 'Try again');
      expect(t.getSize(retry).height, greaterThanOrEqualTo(44));
      await t.tap(find.text('Measurements'));
      await settle(t);
      expect(find.text('No photo'), findsNothing,
          reason: 'the comparison called it "No photo"');
      expect(find.text("Couldn't open"), findsNWidgets(2));
      await t.tap(find.text('Photos'));
      await settle(t);

      server.unsignable.clear();
      server.seen.clear();
      final hold = server.holds['GET weight_logs:$memberA'] = Completer();
      await t.tap(retry);
      await t.pump();
      expect(find.bySemanticsLabel('Retrying'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Retrying'), warnIfMissed: false);
      await settle(t, 2);
      hold.complete();
      await settle(t);
      expect(server.reads('weight_logs'), hasLength(1), reason: 'no double fire');
      expect(find.byType(SectionLoadFailure), findsNothing);
      expect(photos(t).where((u) => u.contains('front.jpg')), isNotEmpty);
      await close(t);
    });

    group('a logged photo whose file is gone', () {
      setUp(() {
        server.objects.add('$memberA/gallery_1.jpg');
        server.rows['progress_photo_logs'] = {
          memberA: [
            for (final n in [2, 1])
              {
                'storage_path': '$memberA/gallery_$n.jpg',
                'side': 'gallery',
                'logged_at': '2026-11-2${n}T08:00:00Z',
              },
          ],
        };
      });

      testWidgets('is said to be gone, recorded; there is no Try again for it, '
          'and it is not "Today" from another day', (t) async {
        await open(t, tab: 'Photos');
        expect(find.text(progressPhotoMissingMessage), findsOneWidget);
        expect(find.text('This photo is no longer available.'), findsOneWidget);
        expect(find.byType(SectionLoadFailure), findsNothing,
            reason: 'asking again cannot bring the file back');
        expect(find.text('Nov 22, 2026'), findsOneWidget);
        expect(photos(t).where((u) => u.contains('gallery_1')), hasLength(1));
        expect(origins(), ['ProgressScreen.openPhoto']);
        await t.tap(find.byIcon(Icons.view_list_rounded));
        await settle(t);
        expect(find.text(progressPhotoMissingMessage), findsOneWidget);
        await t.tap(find.text('Measurements'));
        await settle(t);
        expect(photos(t).where((u) => u.contains('gallery_1')), isEmpty);
        expect(find.text(progressPhotoMissingMessage), findsOneWidget);
        await close(t);
      });

      testWidgets('beside one that cannot be opened: only that one has a Try '
          'again, and it does not go round for the missing one', (t) async {
        server.objects.add('$memberA/gallery_3.jpg');
        server.unsignable.add('$memberA/gallery_3.jpg');
        server.rows['progress_photo_logs']![memberA]!.add({
          'storage_path': '$memberA/gallery_3.jpg',
          'side': 'gallery',
          'logged_at': '2026-11-01T08:00:00Z',
        });
        await open(t, tab: 'Photos');
        expect(find.byType(SectionLoadFailure), findsOneWidget);
        expect(find.text(progressPhotoMissingMessage), findsOneWidget);
        server.unsignable.clear();
        await t.tap(find.widgetWithText(TextButton, 'Try again'));
        await settle(t);
        expect(find.byType(SectionLoadFailure), findsNothing);
        expect(find.text(progressPhotoMissingMessage), findsOneWidget);
        await close(t);
      });

      for (final scale in [1.0, 2.0, 3.0]) {
        testWidgets('320 wide, ${scale}x text: whole, at its size, in both '
            'places', (t) async {
          t.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          await quiet(t);
          await open(t, tab: 'Photos', size: const Size(320, 9000));
          for (final where in ['Photos', 'Measurements']) {
            await t.tap(find.text(where).first, warnIfMissed: false);
            await settle(t);
            final text = find.text(progressPhotoMissingMessage);
            expect(text, findsOneWidget, reason: where);
            expectWhole(t, text, scale);
          }
          await close(t);
        });
      }
    });

    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('320 wide, ${scale}x text: a baseline that cannot be opened '
          'is named to a screen reader, and its words are whole', (t) async {
        final handle = t.ensureSemantics();
        server.objects.addAll(['$memberA/front.jpg', '$memberA/side.jpg']);
        server.unsignable.add('$memberA/front.jpg');
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await quiet(t);
        await open(t, tab: 'Photos', size: const Size(320, 9000));
        final slot = find.bySemanticsLabel("Front photo, couldn't open");
        expect(slot, findsOneWidget);
        final data = t.getSemantics(slot).getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(find.bySemanticsLabel("Back photo, couldn't open"), findsNothing,
            reason: 'there is none');
        expectWhole(t, find.text("Couldn't open").first, scale);
        // It still opens the source sheet.
        await t.tap(find.text('Front'));
        await settle(t);
        expect(find.text('Take Photo'), findsOneWidget);
        handle.dispose();
        await close(t);
      });
    }

    testWidgets('a gallery photo that cannot be opened is not shown as another '
        'photo, nor an older one as "Today"', (t) async {
      server.objects.addAll([
        '$memberA/back.jpg', '$memberA/gallery_1.jpg', '$memberA/gallery_2.jpg',
      ]);
      server.unsignable.add('$memberA/gallery_2.jpg');
      server.rows['progress_photo_logs'] = {
        memberA: [
          for (final n in [2, 1])
            {
              'storage_path': '$memberA/gallery_$n.jpg',
              'side': 'gallery',
              'logged_at': '2026-11-2${n}T08:00:00Z',
            },
        ],
      };
      await open(t, tab: 'Photos');
      expect(photos(t).where((u) => u.contains('back.jpg')), hasLength(1),
          reason: 'the back baseline stood in for the gallery photo');
      expect(photos(t).where((u) => u.contains('gallery_1')), hasLength(1));
      expect(find.byType(SectionLoadFailure), findsOneWidget);
      await t.tap(find.text('Measurements'));
      await settle(t);
      expect(photos(t).where((u) => u.contains('gallery_1')), isEmpty,
          reason: 'the 21st was shown as "Today" for the 22nd');
      expect(find.text("Couldn't open"), findsOneWidget);
      await close(t);
    });
  });

  testWidgets('same member, a refresh fails after a save: what was shown is '
      'kept and the failure is said', (t) async {
    await quiet(t);
    await open(t);
    await t.tap(find.byIcon(Icons.add).last);
    await settle(t);
    server.fails.add('GET weight_logs:$memberA');
    await t.tap(find.text('Save Entry'));
    await settle(t);
    expect(find.text('91.7'), findsWidgets);
    expect(find.text('Could not load your progress'), findsNothing);
    expect(find.text("Couldn't refresh your progress — $tryAgainHint"),
        findsOneWidget);
    await close(t);
  });

  testWidgets('a retry of a failed first load does not claim "no entries" '
      'while it runs', (t) async {
    server.fails.add('GET weight_logs:$memberA');
    await open(t);
    server.fails.clear();
    final hold = server.holds['GET weight_logs:$memberA'] = Completer();
    await t.tap(find.text('Try again'));
    await settle(t, 2);
    expect(find.textContaining('No entries yet'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    hold.complete();
    await settle(t);
    expect(find.text('91.7'), findsWidgets);
    await close(t);
  });
}
