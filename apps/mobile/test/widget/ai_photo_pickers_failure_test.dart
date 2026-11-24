import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/ai_nutrition/data/ai_nutrition_service.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/ai_nutrition_provider.dart';
import 'package:circle_fitness/features/ai_nutrition/presentation/ai_nutrition_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/nutrition/presentation/widgets/ai_scan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_image_picker.dart';
import '../support/pump_until.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-56a · the two AI photo pickers.
//
// Nutrition coach chat (ai_nutrition_screen): at f191d48 the picker was
// unguarded (uncaught error, "Scan a meal" did nothing); an unreadable file
// was sent anyway; nothing in the chain was recorded.
//
// Log Meal › Scan (ai_scan_view): the pick and the analysis were caught but
// never recorded, "Couldn't access the camera or gallery." named no next step,
// and both were SnackBars — drawn on the page BEHIND the Log Meal sheet.
//
// HOW TO SEE IT FAIL: run against f191d48's two files.

const _uid = '00000000-0000-4000-8000-00000000d56a';

class _Coach implements AiNutritionService {
  Object? fails;
  final sent = <File?>[];

  @override
  Future<String> sendMessage({
    required String message,
    required List<Map<String, dynamic>> history,
    File? imageFile,
  }) async {
    sent.add(imageFile);
    if (fails != null) throw fails!;
    return 'Looks balanced.';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);
  int analyses = 0;
  int status = 200;
  bool offline = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/analyze-food-image')) {
      analyses++;
      if (offline) throw http.ClientException('refused', request.url);
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(status == 200
              ? {
                  'result': {
                    'name': 'Rice',
                    'calories': 640,
                    'protein_g': 45,
                    'carbs_g': 60,
                    'fat_g': 18,
                    'confidence': 88,
                  }
                }
              : {'error': 'SECRET'}))),
          status,
          request: request,
          headers: {'content-type': 'application/json'});
    }
    return super.send(request);
  }
}

void main() {
  late _Server server;
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await initSignedInSupabase(server);
    picker.install();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugin.csdcorp.com/speech_to_text'),
            (call) async => false);
  });
  tearDownAll(picker.dispose);

  setUp(() {
    server
      ..reset()
      ..analyses = 0
      ..status = 200
      ..offline = false;
    picker.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  void nothingRaw() {
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('vanished'), findsNothing);
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  group('nutrition coach chat', () {
    late _Coach coach;

    Future<void> open(WidgetTester t) async {
      coach = _Coach();
      t.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(900, 2000);
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          aiNutritionServiceProvider.overrideWithValue(coach),
        ],
        child: const MaterialApp(home: AiNutritionScreen()),
      ));
      await settle(t);
    }

    Future<void> scan(WidgetTester t,
        {String row = 'Choose from Gallery'}) async {
      await t.tap(find.byIcon(Icons.camera_alt_outlined));
      await settle(t);
      await t.tap(find.text(row));
      await settle(t);
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 7));
    }

    for (final (row, code, what, access, origin) in [
      ('Choose from Gallery', 'photo_access_denied', 'photos', 'photo',
          'gallery'),
      ('Take Photo', 'camera_access_denied', 'camera', 'camera', 'camera'),
    ]) {
      testWidgets('$code: says where to allow it, recorded, nothing sent',
          (t) async {
        await open(t);
        picker.fails(code);
        await scan(t, row: row);
        final msg = "Couldn't open your $what — allow $access access in "
            'Settings, then try again.';
        expect(find.text(msg), findsOneWidget,
            reason: 'THE defect: uncaught, and the button did nothing');
        expect(liveRegionOver(msg), findsWidgets);
        expect(origins(), ['aiNutrition.photo.pick.$origin']);
        expect(coach.sent, isEmpty);
        nothingRaw();
        await close(t);
      });
    }

    testWidgets('any other picker failure: the generic next step; the next '
        'pick works', (t) async {
      await open(t);
      picker.fails('boom');
      await scan(t);
      expect(find.text("Couldn't open your photos — $tryAgainHint"),
          findsOneWidget);
      nothingRaw();
      picker.cancels();
      // The SnackBar sits over the composer until it times out (4 s).
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 1));
      await scan(t);
      expect(picker.calls, hasLength(2));
      await close(t);
    });

    testWidgets('an unreadable pick: said, recorded, not sent to the coach',
        (t) async {
      await open(t);
      picker.picksUnreadable();
      await scan(t);
      const msg = "Couldn't use that photo — $tryAgainHint";
      await pumpUntil(t, () => find.text(msg).evaluate().isNotEmpty,
          what: 'the read failure', step: const Duration(milliseconds: 5));
      expect(origins(), ['aiNutrition.photo.read']);
      expect(coach.sent, isEmpty);
      expect(find.text('Analyze this meal photo for me.'), findsNothing);
      nothingRaw();
      await close(t);
    });

    testWidgets('NEGATIVE CONTROL: cancelling is silent', (t) async {
      await open(t);
      picker.cancels();
      await scan(t);
      expect(picker.calls, ['pickImage:1']);
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
      expect(coach.sent, isEmpty);
      await close(t);
    });

    testWidgets('a second tap while the picker is open opens nothing',
        (t) async {
      await open(t);
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await scan(t);
      await t.tap(find.byIcon(Icons.camera_alt_outlined));
      await settle(t);
      expect(find.text('Choose from Gallery'), findsNothing);
      gate.complete(null);
      await settle(t);
      expect(picker.calls, hasLength(1));
      await close(t);
    });

    testWidgets('the photo turn fails: shown as failed (as before) and now '
        'recorded', (t) async {
      await open(t);
      coach.fails = const AiNutritionException('The AI coach is busy.');
      await scan(t);
      await pumpUntil(
          t, () => find.text('The AI coach is busy.').evaluate().isNotEmpty,
          what: 'the failed turn', step: const Duration(milliseconds: 5));
      await settle(t);
      expect(find.text('Send it again'), findsOneWidget);
      expect(origins(), ['aiNutrition.photo.analyze']);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: the photo is sent and answered, no notice',
        (t) async {
      await open(t);
      await scan(t);
      await pumpUntil(
          t, () => find.text('Looks balanced.').evaluate().isNotEmpty,
          what: 'the reply', step: const Duration(milliseconds: 5));
      await settle(t);
      expect(coach.sent.single!.path, picker.photoPath);
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
      await close(t);
    });
  });

  group('Log Meal scan', () {
    Finder inView(String text) => find.descendant(
        of: find.byType(AiScanView), matching: find.text(text));

    Future<void> open(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: AiScanView(onAccept: (_) {})),
      ));
      await t.pump();
    }

    Future<void> tap(WidgetTester t, String label) async {
      await t.ensureVisible(find.text(label));
      await t.tap(find.text(label));
      await settle(t);
    }

    Future<void> waitFor(WidgetTester t, String text) =>
        pumpUntil(t, () => inView(text).evaluate().isNotEmpty,
            what: '"$text" in the scan view');

    for (final (label, code, what, access, origin) in [
      ('Choose from Gallery', 'photo_access_denied', 'photos', 'photo',
          'gallery'),
      ('Scan Meal', 'camera_access_denied', 'camera', 'camera', 'camera'),
    ]) {
      testWidgets('$code: said IN the view (the sheet covers a SnackBar), '
          'recorded', (t) async {
        await open(t);
        picker.fails(code);
        await tap(t, label);
        final msg = "Couldn't open your $what — allow $access access in "
            'Settings, then try again.';
        expect(inView(msg), findsOneWidget);
        expect(liveRegionOver(msg), findsWidgets);
        expect(find.byType(SnackBar), findsNothing);
        expect(origins(), ['nutrition.scan.pick.$origin']);
        nothingRaw();
      });
    }

    testWidgets('any other picker failure: the generic next step; a retry '
        'clears the notice', (t) async {
      await open(t);
      picker.fails('boom');
      await tap(t, 'Choose from Gallery');
      const msg = "Couldn't open your photos — $tryAgainHint";
      expect(inView(msg), findsOneWidget);
      expect(origins(), ['nutrition.scan.pick.gallery']);
      picker.cancels();
      await tap(t, 'Choose from Gallery');
      expect(inView(msg), findsNothing, reason: 'it described the last try');
      expect(reported, hasLength(1));
      nothingRaw();
    });

    testWidgets('an unreadable pick: said, recorded, not analysed', (t) async {
      await open(t);
      picker.picksUnreadable();
      await tap(t, 'Choose from Gallery');
      await waitFor(t, "Couldn't use that photo — $tryAgainHint");
      expect(origins(), ['nutrition.scan.read']);
      expect(server.analyses, 0);
      expect(find.text('Scan Meal'), findsOneWidget, reason: 'still usable');
      nothingRaw();
    });

    testWidgets('a refused analysis: said, recorded, never a result',
        (t) async {
      await open(t);
      server.status = 500;
      await tap(t, 'Choose from Gallery');
      await waitFor(
          t,
          "Couldn't analyze that photo — $tryAgainHint "
          'You can also add the meal manually.');
      expect(origins(), ['nutrition.scan.analyze']);
      expect(find.textContaining('kcal'), findsNothing);
      nothingRaw();
    });

    testWidgets('a connection failure in the analysis: the connection hint',
        (t) async {
      await open(t);
      server.offline = true;
      await tap(t, 'Choose from Gallery');
      await waitFor(
          t,
          "Couldn't analyze that photo — check your connection and try again. "
          'You can also add the meal manually.');
      expect(origins(), ['nutrition.scan.analyze']);
    });

    testWidgets('NEGATIVE CONTROL: cancelling is silent', (t) async {
      await open(t);
      picker.cancels();
      await tap(t, 'Choose from Gallery');
      await tap(t, 'Scan Meal');
      expect(picker.calls, ['pickImage:1', 'pickImage:0']);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
      expect(server.analyses, 0);
    });

    testWidgets('a second tap while the picker is open opens no second one',
        (t) async {
      await open(t);
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await tap(t, 'Choose from Gallery');
      await tap(t, 'Scan Meal');
      expect(picker.calls, hasLength(1));
      gate.complete(null);
      await settle(t);
    });

    testWidgets('POSITIVE CONTROL: a readable pick is analysed and shown, no '
        'notice', (t) async {
      await open(t);
      await tap(t, 'Choose from Gallery');
      await waitFor(t, '640 kcal');
      expect(server.analyses, 1);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });

    // (At 2x the idle view's fixed-height frame and buttons already overflow
    // on f191d48 — not this package's — so the notice is pinned at 1x.)
    testWidgets('the notice wraps at full size, inside the screen', (t) async {
      await open(t);
      picker.fails('photo_access_denied');
      await tap(t, 'Choose from Gallery');
      const msg = "Couldn't open your photos — allow photo access in "
          'Settings, then try again.';
      expect(inView(msg), findsOneWidget);
      expect(t.widget<Text>(inView(msg)).style!.fontSize, 13);
      expect(t.getRect(inView(msg)).right, lessThanOrEqualTo(400));
      expect(t.getSize(inView(msg)).height, greaterThan(13 * 1.4 * 1.5),
          reason: 'more than one line: it wraps');
      expect(t.takeException(), isNull);
      expect(find.ancestor(of: inView(msg), matching: find.byType(FittedBox)),
          findsNothing);
    });
  });
}
