import 'dart:async';
import 'dart:io' show SocketException;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_video_response_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fit_matrix.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-58 (c) · Video Response: fit, targets, and what it said.
//
// At f191d48:
//  * Record Now / From Gallery overflowed sideways (from 1.0× at 390dp in the
//    test font, 363px at 3×) and the fixed 200px preview overflowed at 2×.
//  * Nothing rebuilt the screen while the note was typed, so Send stayed
//    disabled: a written note alone could never be sent. A BLANK note, once
//    something did rebuild it, enabled a Send that did nothing.
//  * A failed record / pick was said in its own words and never recorded
//    (there WERE catches; they did not report).
//
// A primary coach flow, so the matrix includes 3.0×.
//
// HOW TO SEE IT FAIL: `git checkout f191d48 -- lib/features/coach/
// presentation/coach_video_response_screen.dart`; only the controls pass.

const _uid = '00000000-0000-4000-8000-0000000f58c0';
const _client = 'Alexandria Montgomery';
const _generic = 'try again in a moment. If it keeps happening, contact support.';
const _fromGallery = ' You can also use From Gallery.';
const _file = 'weekly-review-for-alexandria-september-final.mp4';
const _channel = MethodChannel('plugins.flutter.io/image_picker');

void main() {
  late RowCheckingPostgrest server;
  final reported = <AppFailure>[];
  final calls = <String>[];
  late Future<Object?> Function(MethodCall call) answer;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RowCheckingPostgrest(_uid);
    await initSignedInSupabase(server);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
      final source = (call.arguments as Map)['source'];
      calls.add('${call.method}:${source == 0 ? 'camera' : 'gallery'}'
          ':${(call.arguments as Map)['maxDuration']}');
      return answer(call);
    });
  });

  setUp(() {
    server.reset();
    reported.clear();
    calls.clear();
    answer = (_) async => '/tmp/$_file';
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> show(WidgetTester tester,
      {num width = 390, double height = 4000, double scale = 1}) async {
    fitWindow(tester, width, height, scale);
    await tester.pumpWidget(const MaterialApp(
        home: CoachVideoResponseScreen(clientId: 'client-1', clientName: _client)));
    await tester.pumpAndSettle();
  }

  final screen = find.byType(CoachVideoResponseScreen);
  Finder body() => find.byType(SingleChildScrollView).first;
  ElevatedButton send(WidgetTester tester) => tester.widget<ElevatedButton>(
      find.ancestor(of: find.text('Send to Client'), matching: find.byWidgetPredicate(
          (w) => w is ElevatedButton)));
  bool live(WidgetTester tester, Finder f) => tester
      .widgetList<Semantics>(find.ancestor(of: f, matching: find.byType(Semantics)))
      .any((s) => s.properties.liveRegion ?? false);
  Future<void> record(WidgetTester tester) async {
    await tester.tap(find.text('Record Now'));
    await tester.pumpAndSettle();
  }
  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.text('From Gallery'));
    await tester.pumpAndSettle();
  }
  void whole(WidgetTester tester, String text, double size, double scale) {
    expect(find.text(text), findsOneWidget, reason: text);
    expect(renderedFontSize(tester, find.text(text)), closeTo(size * scale, 0.01), reason: text);
  }

  group('fit: no overflow, no shrunk text', () {
    for (final w in fitPhones.keys) {
      for (final s in fitScales) {
        testWidgets('the form, then with a video chosen, ${w}dp at ${s}x', (tester) async {
          final seen = recordOverflows();
          await show(tester, width: w, scale: s);
          expect(seen, isEmpty, reason: seen.join('\n\n'));
          expectTextNotShrunk(tester, body(), s);
          for (final (t, size) in [('Record Now', 13.0), ('From Gallery', 13.0),
              ('Tap to select a video', 14.0), ('Up to 5 minutes', 12.0),
              ('Send to Client', 16.0)]) {
            whole(tester, t, size, s);
          }
          // Each label is inside its own button.
          for (final t in ['Record Now', 'From Gallery']) {
            final button = tester.getRect(
                find.ancestor(of: find.text(t), matching: find.byType(Container)).first);
            final text = tester.getRect(find.text(t));
            expect(button.contains(text.topLeft) &&
                button.contains(text.bottomRight - const Offset(.1, .1)), isTrue,
                reason: '$t $text outside its button $button');
            expect(button.height, greaterThanOrEqualTo(44));
          }
          await pick(tester);
          expect(seen, isEmpty, reason: seen.join('\n\n'));
          whole(tester, _file, 12, s);
          whole(tester, 'Remove', 12, s);
          if (s > 1.3) {
            expect(tester.widget<Text>(find.text(_file)).overflow, isNull,
                reason: 'the file name is not cut at large text');
          }
        });
      }
    }

    for (final MapEntry(key: w, value: h) in fitPhones.entries) {
      testWidgets('3.0x on a real $w×${h.toInt()} phone: Send can be reached', (tester) async {
        final seen = recordOverflows();
        await show(tester, width: w, height: h, scale: 3);
        await tester.enterText(find.byType(TextField), 'Great week');
        await tester.pump();
        await tester.ensureVisible(find.text('Send to Client'));
        await tester.pumpAndSettle();
        expect(find.text('Send to Client').hitTestable(), findsOneWidget);
        expect(seen, isEmpty, reason: seen.join('\n\n'));
      });
    }
  });

  group('targets', () {
    for (final s in [1.0, 3.0]) {
      testWidgets('every target is 44×44 and named for its item (${s}x)', (tester) async {
        final h = tester.ensureSemantics();
        await show(tester, width: 320, scale: s);
        expectTargets(tester, screen, atLeast: 5);
        expectNamedButton(tester, 'Record a video for $_client now');
        expectNamedButton(tester, 'Choose a video for $_client from your gallery');
        expectNamedButton(tester, 'Select a video for $_client, up to 5 minutes');
        expect(find.byTooltip('Close video response'), findsOneWidget);
        expect(find.bySemanticsLabel('Send to $_client'), findsOneWidget);
        await pick(tester);
        expectTargets(tester, screen, atLeast: 5);
        expectNamedButton(tester, 'Remove $_file');
        expect(find.bySemanticsLabel(RegExp('^Select a video')), findsNothing,
            reason: 'a chosen video is not an empty picker');
        h.dispose();
      });
    }

    testWidgets('a screen reader can record, choose and remove', (tester) async {
      final h = tester.ensureSemantics();
      await show(tester);
      tester.semantics.tap(find.semantics.byLabel('Record a video for $_client now'));
      await tester.pumpAndSettle();
      expect(calls, ['pickVideo:camera:300']);
      tester.semantics.tap(find.semantics.byLabel('Remove $_file'));
      await tester.pumpAndSettle();
      expect(find.text(_file), findsNothing);
      tester.semantics.tap(
          find.semantics.byLabel('Choose a video for $_client from your gallery'));
      await tester.pumpAndSettle();
      expect(calls.last, 'pickVideo:gallery:null');
      expect(find.text(_file), findsOneWidget);
      h.dispose();
    });
  });

  group('Send follows the note', () {
    testWidgets('typing enables Send, clearing disables it, blank is nothing to send',
        (tester) async {
      await show(tester);
      expect(send(tester).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Great week');
      await tester.pump();
      expect(send(tester).onPressed, isNotNull,
          reason: 'THE defect: nothing rebuilt the screen; a note alone could not be sent');
      await tester.enterText(find.byType(TextField), '   \n ');
      await tester.pump();
      expect(send(tester).onPressed, isNull, reason: 'a blank note enabled a Send that did nothing');
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(send(tester).onPressed, isNull);
    });

    testWidgets('the success path: a typed note sends, once, as typed', (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextField), ' Great week ');
      await tester.pump();
      await tester.tap(find.text('Send to Client'));
      await tester.pumpAndSettle();
      expect(find.text('Video Sent!'), findsOneWidget);
      final posts = server.writes.where((w) => w.contains('/coach_video_responses')).toList();
      expect(posts, hasLength(1));
      expect(posts.single, contains('"notes":"Great week"'));
      expect(reported, isEmpty);
    });

    testWidgets('control: a chosen video alone enables Send; removing it disables it',
        (tester) async {
      await show(tester);
      await pick(tester);
      expect(send(tester).onPressed, isNotNull);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(send(tester).onPressed, isNull);
    });

    testWidgets('a failed send keeps the note and can be sent again', (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextField), 'Great week');
      await tester.pump();
      server.mode = WriteMode.serverError;
      await tester.tap(find.text('Send to Client'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't send your response — $_generic"), findsOneWidget);
      expect(find.text('Great week'), findsOneWidget);
      expect(send(tester).onPressed, isNotNull);
    });
  });

  group('record / pick failures', () {
    for (final (name, tap, origin, message) in [
      ('record', record, 'CoachVideoResponseScreen._recordVideo',
          "Couldn't open the camera — $_generic$_fromGallery"),
      ('pick', pick, 'CoachVideoResponseScreen._pickVideo',
          "Couldn't open your videos — $_generic"),
    ]) {
      testWidgets('$name: a failure is recorded once and said in the one voice',
          (tester) async {
        answer = (_) async => throw PlatformException(
            code: 'no_available_camera', message: 'SECRET_PLATFORM_X');
        await show(tester);
        await tap(tester);
        expect(find.text(message), findsOneWidget);
        expect(live(tester, find.text(message)), isTrue, reason: 'announced');
        expect(find.textContaining('SECRET_PLATFORM_X'), findsNothing);
        expect(find.textContaining('connection'), findsNothing);
        expect(reported.map((f) => f.origin), [origin],
            reason: 'THE defect: the failure was never recorded');
        expect(reported.single.error, isA<PlatformException>());
        expect(reported.single.stackTrace, isNotNull);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$name: cancelling is silent', (tester) async {
        answer = (_) async => null;
        await show(tester);
        await tap(tester);
        expect(calls, hasLength(1), reason: 'premise: the picker opened');
        expect(find.byType(SnackBar), findsNothing);
        expect(reported, isEmpty);
        expect(find.text('Tap to select a video'), findsOneWidget);
      });

      testWidgets('$name: a failure, and a cancel, keep the video already chosen',
          (tester) async {
        await show(tester);
        await pick(tester);
        expect(find.text(_file), findsOneWidget);
        answer = (_) async => null;
        await tap(tester);
        expect(find.text(_file), findsOneWidget);
        answer = (_) async => throw PlatformException(code: 'x');
        await tap(tester);
        expect(find.text(_file), findsOneWidget);
        expect(send(tester).onPressed, isNotNull);
        expect(reported, hasLength(1));
      });

      testWidgets('$name: it can be tried again after a failure', (tester) async {
        answer = (_) async => throw PlatformException(code: 'x');
        await show(tester);
        await tap(tester);
        answer = (_) async => '/tmp/$_file';
        await tap(tester);
        expect(find.text(_file), findsOneWidget);
        expect(reported, hasLength(1));
      });
    }

    for (final (name, tap, code, message) in [
      ('record', record, 'camera_access_denied',
          "Couldn't open the camera — allow camera access in Settings, then try again."),
      ('pick', pick, 'photo_access_denied',
          "Couldn't open your videos — allow photo access in Settings, then try again."),
    ]) {
      testWidgets('$name: access denied points to Settings', (tester) async {
        answer = (_) async => throw PlatformException(code: code);
        await show(tester);
        await tap(tester);
        expect(find.text(message), findsOneWidget);
        expect(reported, hasLength(1));
      });
    }

    testWidgets('the connection hint only for a network failure', (tester) async {
      // Not a PlatformException from the channel: thrown by the plugin itself.
      answer = (_) async => throw const SocketException('offline');
      await show(tester);
      await pick(tester);
      // The channel mock turns it into a PlatformException, as a platform
      // would: it is NOT a connection failure and says so.
      expect(find.textContaining('connection'), findsNothing);
      expect(reported, hasLength(1));
    });

    testWidgets('one picker at a time', (tester) async {
      final open = Completer<Object?>();
      answer = (_) => open.future;
      await show(tester);
      await tester.tap(find.text('From Gallery'));
      await tester.tap(find.text('From Gallery'));
      await tester.tap(find.text('Record Now'));
      await tester.pump();
      expect(calls, ['pickVideo:gallery:null']);
      open.complete('/tmp/$_file');
      await tester.pumpAndSettle();
      expect(find.text(_file), findsOneWidget);
      // And the next one opens.
      await record(tester);
      expect(calls, hasLength(2));
    });

    testWidgets('positive control: a chosen video shows its name, nothing said',
        (tester) async {
      await show(tester);
      await record(tester);
      expect(calls, ['pickVideo:camera:300'], reason: 'still limited to 5 minutes');
      expect(find.text(_file), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
    });
  });

  testWidgets('control: 1.0x on 390dp keeps its layout', (tester) async {
    recordOverflows(); // the base overflows its buttons by 16px in the test font
    await show(tester, height: 844);
    Rect box(String t) => tester.getRect(
        find.ancestor(of: find.text(t), matching: find.byType(Container)).first);
    final rec = box('Record Now'), gal = box('From Gallery');
    expect(rec.top, gal.top, reason: 'side by side');
    expect(rec.left, 20);
    expect(gal.right, 370);
    expect(gal.left - rec.right, 12);
    expect(rec.width, closeTo(169, 0.1));
    final preview = box('Tap to select a video');
    expect(preview.height, 200);
    expect(preview.top, 76);
    final sendRect = tester.getRect(find.ancestor(
        of: find.text('Send to Client'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)));
    expect(sendRect.width, 350);
  });
}
