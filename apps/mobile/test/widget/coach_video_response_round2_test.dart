import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_video_response_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fit_matrix.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-58 round 2 · Video Response, review fixes.
//
// At 4f3d76b: Record Now / From Gallery / Send to Client were announced in
// other words than they show; a device with no camera was told to try it
// again; failure text on red took the theme's colour; Record, Choose and
// Remove stayed live while a response was being sent; the note field had no
// name once it had text. The connection hint was never reached by a test.
//
// HOW TO SEE IT FAIL: `git checkout 4f3d76b -- lib/features/coach/
// presentation/coach_video_response_screen.dart`; only the controls pass.

const _uid = '00000000-0000-4000-8000-0000000f58c2';
const _client = 'Alexandria Montgomery';
const _generic = 'try again in a moment. If it keeps happening, contact support.';
const _network = 'check your connection and try again.';
const _useGallery = "Couldn't open the camera — you can use From Gallery instead.";
const _file = 'weekly-review.mp4';
const _path = '/tmp/$_file';
const _channel = MethodChannel('plugins.flutter.io/image_picker');

const _record = 'Record Now, for $_client';
const _gallery = 'From Gallery, for $_client';
const _select = 'Select a video for $_client, up to 5 minutes';
const _remove = 'Remove $_file';

void main() {
  late RowCheckingPostgrest server;
  final reported = <AppFailure>[];
  final calls = <String>[];
  late Future<Object?> Function() answer;
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;

  void answerByChannel() => messenger.setMockMethodCallHandler(_channel, (call) {
        calls.add((call.arguments as Map)['source'] == 0 ? 'camera' : 'gallery');
        return answer();
      });

  setUpAll(() async {
    server = RowCheckingPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    calls.clear();
    answer = () async => _path;
    answerByChannel();
    setFailureSink(reported.add);
  });
  tearDown(() {
    resetFailureSink();
    messenger.setMockMethodCallHandler(_channel, null);
  });

  Future<void> show(WidgetTester tester, {ThemeData? theme}) async {
    fitWindow(tester, 390, 2000, 1);
    await tester.pumpWidget(MaterialApp(theme: theme,
        home: const CoachVideoResponseScreen(clientId: 'client-1', clientName: _client)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> dismiss(WidgetTester tester) async {
    ScaffoldMessenger.of(tester.element(find.text('Record Now'))).clearSnackBars();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing, reason: 'premise');
  }

  SemanticsData node(WidgetTester tester, String label) =>
      tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();

  void expectEnabled(WidgetTester tester, String label, bool enabled) {
    final d = node(tester, label);
    expect(d.flagsCollection.isButton, isTrue, reason: label);
    expect(d.flagsCollection.isEnabled, enabled ? Tristate.isTrue : Tristate.isFalse,
        reason: label);
    expect(d.hasAction(SemanticsAction.tap), enabled, reason: label);
  }

  double alpha(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!.a;

  testWidgets('a name starts with the words on the button', (tester) async {
    final h = tester.ensureSemantics();
    await show(tester);
    for (final (shown, label) in [('Record Now', _record), ('From Gallery', _gallery),
        ('Send to Client', 'Send to Client, $_client')]) {
      expect(find.text(shown), findsOneWidget);
      expect(label, startsWith(shown));
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    h.dispose();
  });

  group('record / pick failures', () {
    for (final (button, network, other) in [
      ('Record Now', "Couldn't open the camera — $_network", _useGallery),
      ('From Gallery', "Couldn't open your videos — $_network",
          "Couldn't open your videos — $_generic"),
    ]) {
      testWidgets('$button: the connection hint for a network failure, and only then',
          (tester) async {
        // Below the channel's codec, which turns every exception into a
        // PlatformException: the screen catches the SocketException itself.
        messenger.setMockMessageHandler(_channel.name,
            (_) => Future<ByteData?>.error(const SocketException('SECRET_HOST_X')));
        await show(tester);
        await tap(tester, button);
        expect(reported.single.error, isA<SocketException>(), reason: 'premise');
        expect(find.text(network), findsOneWidget);
        expect(find.textContaining('SECRET_HOST_X'), findsNothing);
        expect(tester.takeException(), isNull);
        await dismiss(tester);

        // Negative control: the same button, not a network failure.
        answerByChannel();
        answer = () async => throw PlatformException(code: 'x');
        await tap(tester, button);
        expect(find.text(other), findsOneWidget);
        expect(find.textContaining('connection'), findsNothing);
        expect(reported, hasLength(2));
      });
    }

    testWidgets('a camera that cannot open points to the gallery, which still works',
        (tester) async {
      answer = () async => throw PlatformException(code: 'no_available_camera');
      await show(tester);
      await tap(tester, 'Record Now');
      expect(find.text(_useGallery), findsOneWidget);
      expect(find.textContaining('try again'), findsNothing,
          reason: 'THE defect: a device with no camera was told to try it again');
      expect(reported.map((f) => f.origin), ['CoachVideoResponseScreen._recordVideo']);
      answer = () async => _path;
      await tap(tester, 'From Gallery');
      expect(find.text(_file), findsOneWidget);
    });

    testWidgets('control: cancelling says and records nothing', (tester) async {
      answer = () async => null;
      await show(tester);
      await tap(tester, 'Record Now');
      expect(calls, ['camera']);
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
    });

    for (final (name, theme) in [('dark', ThemeData.dark()), ('light', ThemeData.light())]) {
      testWidgets('failure text is white on red ($name theme)', (tester) async {
        Color ink(String text) => tester.renderObject<RenderParagraph>(find.descendant(
            of: find.text(text), matching: find.byType(RichText)).first).text.style!.color!;
        void onRed() => expect(
            tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.red);
        answer = () async => throw PlatformException(code: 'x');
        await show(tester, theme: theme);
        await tap(tester, 'Record Now');
        onRed();
        expect(ink(_useGallery), Colors.white);
        await dismiss(tester);
        // A failed send is said on red too.
        await tester.enterText(find.byType(TextField), 'Great week');
        await tester.pump();
        server.mode = WriteMode.serverError;
        await tap(tester, 'Send to Client');
        onRed();
        expect(ink("Couldn't send your response — $_generic"), Colors.white);
      });
    }
  });

  group('while a response is being sent', () {
    testWidgets('Record, Choose and the empty preview do nothing; a failed send gives '
        'them back', (tester) async {
      final h = tester.ensureSemantics();
      await show(tester);
      for (final l in [_record, _gallery, _select]) {
        expectEnabled(tester, l, true);
      }
      await tester.enterText(find.byType(TextField), 'Great week');
      await tester.pump();
      server
        ..gate = Completer<void>()
        ..mode = WriteMode.serverError;
      await tester.tap(find.text('Send to Client'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget, reason: 'premise: sending');
      for (final l in [_record, _gallery, _select]) {
        expectEnabled(tester, l, false);
      }
      for (final t in ['Record Now', 'From Gallery']) {
        expect(alpha(tester, t), lessThan(1), reason: '$t is dimmed');
      }
      for (final t in ['Record Now', 'From Gallery', 'Tap to select a video']) {
        await tester.tap(find.text(t));
        await tester.pump();
      }
      expect(calls, isEmpty, reason: 'THE defect: the picker opened over a send in flight');

      server.gate!.complete();
      server.gate = null;
      await tester.pumpAndSettle();
      expect(find.text("Couldn't send your response — $_generic"), findsOneWidget);
      for (final l in [_record, _gallery, _select]) {
        expectEnabled(tester, l, true);
      }
      expect(alpha(tester, 'Record Now'), 1);
      await tap(tester, 'From Gallery');
      expect(calls, ['gallery']);
      expect(find.text(_file), findsOneWidget);
      h.dispose();
    });

    testWidgets('the video being sent can be neither removed nor replaced', (tester) async {
      final h = tester.ensureSemantics();
      final bytes = Completer<Uint8List>();
      IOOverrides.global = _HeldFiles(bytes.future);
      addTearDown(() => IOOverrides.global = null);
      await show(tester);
      await tap(tester, 'From Gallery');
      expectEnabled(tester, _remove, true);
      await tester.tap(find.text('Send to Client'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget, reason: 'premise: sending');
      for (final l in [_record, _gallery, _remove]) {
        expectEnabled(tester, l, false);
      }
      expect(alpha(tester, 'Remove'), lessThan(1), reason: 'dimmed');
      for (final t in ['Record Now', 'From Gallery', 'Remove']) {
        await tester.tap(find.text(t));
        await tester.pump();
      }
      expect(calls, ['gallery']);
      expect(find.text(_file), findsOneWidget,
          reason: 'THE defect: the video being sent could be removed');

      // The send fails: the video is kept and the controls come back.
      bytes.completeError(const FileSystemException('SECRET_PATH_X'));
      await tester.pumpAndSettle();
      expect(find.text(_file), findsOneWidget);
      expect(find.textContaining('SECRET_PATH_X'), findsNothing);
      for (final l in [_record, _gallery, _remove]) {
        expectEnabled(tester, l, true);
      }
      await tap(tester, 'Remove');
      expect(find.text(_file), findsNothing);
      h.dispose();
    });

    testWidgets('positive control: a note still sends, once', (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextField), 'Great week');
      await tester.pump();
      await tap(tester, 'Send to Client');
      expect(server.writes.where((w) => w.contains('/coach_video_responses')), hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
    });
  });

  group('the note field', () {
    testWidgets('keeps its name once text is in it', (tester) async {
      final h = tester.ensureSemantics();
      await show(tester);
      await expectFieldNamed(tester, find.byType(TextField), 'Written Notes (optional)');
      expectTargets(tester, find.byType(CoachVideoResponseScreen), atLeast: 5);
      h.dispose();
    });

    testWidgets('negative control: empty, it is empty and its hint is said', (tester) async {
      final h = tester.ensureSemantics();
      await show(tester);
      final d = tester.getSemantics(find.byType(EditableText)).getSemanticsData();
      expect(d.value, isEmpty);
      expect('${d.label}\n${d.hint}', contains('Add a written note to accompany your video'));
      h.dispose();
    });
  });
}

/// Files whose bytes arrive when the test says so.
final class _HeldFiles extends IOOverrides {
  _HeldFiles(this.bytes);
  final Future<Uint8List> bytes;
  @override
  File createFile(String path) =>
      path == _path ? _HeldFile(path, bytes) : super.createFile(path);
}

class _HeldFile extends Fake implements File {
  _HeldFile(this.path, this.bytes);
  @override
  final String path;
  final Future<Uint8List> bytes;
  @override
  Future<Uint8List> readAsBytes() => bytes;
}
