import 'dart:convert';

import 'package:circle_fitness/features/onboarding/presentation/intake_flow_screen.dart';
import 'package:circle_fitness/features/onboarding/presentation/widgets/intake_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show FlexParentData, RenderFlex, RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-53c (carries FL-55's item) · the intake step bar at large text.
//
// `_IntakeStepBar` (back button · 24 progress pills · "20 / 24" or "Skip") is
// the top of almost every intake step. It was one Row: the back button, an
// Expanded row of pills, then the counter at its natural width. As text grew
// the counter took the width and the pills got what was left — at 2× on a
// 320dp phone the pills were squeezed to nothing (the progress vanished), and
// at 3× the counter no longer fit and the Row overflowed. The counter was
// announced as its glyphs ("20 / 24"); the "Skip" variant gave a screen
// reader no step at all, and its Skip was a bare text-height tap target with
// no button role.
//
// Measured on b7ec6ef (FlutterTest font): each pill was 0.54px at 1.3× on
// 320dp, negative (invisible) at 2× on 320/360dp and at 3× on 390/430dp, and
// the Row overflowed at 3× on 320dp.
//
// Now, when the trailing label would leave the pills less than 1px each, it
// moves to its own line under the pills (the bar grows; no text is shrunk). The bar announces "Step 20 of 24"; Skip is a >= 44px
// labelled button. At 1× on 390dp the geometry is exactly what it was.
//
// NOTE: widget tests draw text in the FlutterTest font (one em per glyph),
// wider than the app's font, so the stacking point here is lower than on a
// device. The pins are geometric and hold for any font.
//
// HOW TO SEE IT FAIL: run against b7ec6ef's intake_flow_screen.dart.

const _uid = '00000000-0000-4000-8000-0000000f1055';

const _modePage = 22; // Coaching Mode: step bar "20 / 24"
const _photosPage = 21; // Progress Photos: step bar with Skip (step 19)

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
          1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({
        'sub': _uid,
        'role': 'authenticated',
        'exp': exp,
        'aud': 'authenticated'
      })}.'
      'not-verified-client-side';
}

class _SeededSession extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => jsonEncode({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 315360000,
        'refresh_token': 'test-refresh',
        'user': {
          'id': _uid,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
  @override
  Future<bool> hasAccessToken() async => true;
  @override
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async {}
}

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

class _Server extends http.BaseClient {
  int step = _modePage;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.contains('/auth/v1/')) {
      return _json({'error': 'offline'}, 400, request);
    }
    if (path.startsWith('/storage/')) {
      return _json({
        'statusCode': '404',
        'error': 'not_found',
        'message': 'Object not found'
      }, 400, request);
    }
    if (path == '/rest/v1/user_profiles') {
      if (request.method == 'GET') {
        final profile = {'id': _uid, 'onboarding_step': step};
        final single =
            request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
        return _json(single ? profile : [profile], 200, request);
      }
      return request.url.queryParameters.containsKey('select')
          ? _json([
              {'id': _uid}
            ], 200, request)
          : http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  final server = _Server();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  double page(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!;

  /// Opens the flow on [step] at [size] and [scale]. Overflows ELSEWHERE on
  /// the page (step bodies are other packages' files) are tolerated here; the
  /// step bar is checked geometrically below.
  Future<void> open(WidgetTester tester,
      {required int step, required Size size, required double scale}) async {
    server.step = step;
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) previous?.call(d);
    };
    addTearDown(() => FlutterError.onError = previous);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const IntakeFlowScreen(),
      ),
    ));
    await settle(tester);
    expect(page(tester), step.toDouble(), reason: 'premise: on step $step');
  }

  /// The step bar on the page in view.
  Finder bar() => find.byElementPredicate((e) {
        if (e.widget.runtimeType.toString() != '_IntakeStepBar') return false;
        final box = e.renderObject as RenderBox?;
        if (box == null || !box.attached) return false;
        return box.localToGlobal(Offset.zero).dx.abs() < 1; // the page in view
      });

  Finder inBar(Finder f) => find.descendant(of: bar(), matching: f);

  /// Every flex inside the bar lays its children out inside itself.
  List<String> overflows(WidgetTester tester) {
    final out = <String>[];
    final root = tester.renderObject(bar());
    void visit(RenderObject o) {
      if (o is RenderFlex) {
        var child = o.firstChild;
        while (child != null) {
          final pd = child.parentData! as FlexParentData;
          final r = pd.offset & child.size;
          if (r.left < -0.01 ||
              r.top < -0.01 ||
              r.right > o.size.width + 0.01 ||
              r.bottom > o.size.height + 0.01) {
            out.add('${o.direction.name} flex ${o.size} child $r');
          }
          child = pd.nextSibling;
        }
      }
      o.visitChildren(visit);
    }

    visit(root);
    return out;
  }

  /// The pills: the 4px-tall bars (each wrapped in its 2px side margins).
  List<double> pillWidths(WidgetTester tester) {
    final f = inBar(find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxHeight == 4));
    return [
      for (var i = 0; i < f.evaluate().length; i++)
        tester.getSize(f.at(i)).width - 4,
    ];
  }

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.3, 2.0, 3.0]) {
      for (final variant in ['counter', 'skip']) {
        final step = variant == 'counter' ? _modePage : _photosPage;
        final label = variant == 'counter' ? '20 / 24' : 'Skip';
        final announced = variant == 'counter' ? 'Step 20 of 24' : 'Step 19 of 24';
        testWidgets(
            'step bar ($variant) at ${scale}x on ${width.toInt()}dp: no '
            'overflow, label fully on screen at full size, pills visible, '
            'Back >= 44px, announced "$announced"', (tester) async {
          final semantics = tester.ensureSemantics();
          await open(tester,
              step: step, size: Size(width, 900), scale: scale);

          expect(overflows(tester), isEmpty,
              reason: 'the bar lays out inside itself');

          final text = inBar(find.text(label));
          expect(text, findsOneWidget);
          final r = tester.getRect(text);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(width),
              reason: '"$label" is not pushed off screen');
          final p = tester.renderObject<RenderParagraph>(text);
          final fontSize = variant == 'counter' ? 12.0 : 13.0;
          expect(p.textScaler.scale(fontSize), closeTo(fontSize * scale, 0.01),
              reason: 'the label is never shrunk');
          expect(p.didExceedMaxLines, isFalse);
          expect(r.height, greaterThanOrEqualTo(fontSize * scale - 0.01),
              reason: 'the label is drawn at its full size, not clipped');

          final pills = pillWidths(tester);
          expect(pills, hasLength(24));
          for (final w in pills) {
            expect(w, greaterThanOrEqualTo(1),
                reason: 'every progress pill stays visible: $pills');
          }

          final back = inBar(find.byType(IntakeBackButton));
          expect(tester.getSize(back).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(back).height, greaterThanOrEqualTo(44));

          expect(find.bySemanticsLabel(announced), findsOneWidget,
              reason: 'the step is announced in words');
          if (variant == 'counter') {
            expect(find.bySemanticsLabel(label), findsNothing,
                reason: 'not read out as its glyphs "$label"');
          } else {
            final skip = find.bySemanticsLabel('Skip');
            expect(skip, findsOneWidget);
            expect(tester.getSemantics(skip),
                matchesSemantics(
                    label: 'Skip', isButton: true, hasTapAction: true,
                    hasEnabledState: true, isEnabled: true),
                reason: 'Skip is announced as a button');
            final size = tester.getSize(find
                .ancestor(of: text, matching: find.byType(GestureDetector))
                .first);
            expect(size.height, greaterThanOrEqualTo(44));
            expect(size.width, greaterThanOrEqualTo(44));
          }
          semantics.dispose();
        });
      }
    }
  }

  // Measured on b7ec6ef: at 1× on 390dp the bar is unchanged to the pixel.
  for (final (s, label, labelRect, pill) in [
    (_modePage, '20 / 24', const Rect.fromLTRB(288.3, 25.5, 374.0, 42.5),
        4.510416666666666),
    (_photosPage, 'Skip', const Rect.fromLTRB(321.0, 24.5, 374.0, 43.5),
        5.875),
  ]) {
    testWidgets(
        'POSITIVE CONTROL: at 1x on 390dp the "$label" bar is one row with '
        'the geometry it had', (tester) async {
      await open(tester, step: s, size: const Size(390, 900), scale: 1);
      expect(tester.getRect(bar()), const Rect.fromLTRB(0, 0, 390, 72));
      expect(tester.getRect(inBar(find.byType(IntakeBackButton))),
          const Rect.fromLTRB(16, 12, 60, 56));
      final r = tester.getRect(inBar(find.text(label)));
      expect(r.left, closeTo(labelRect.left, 0.1));
      expect(r.top, closeTo(labelRect.top, 0.1));
      expect(r.right, closeTo(labelRect.right, 0.1));
      expect(r.bottom, closeTo(labelRect.bottom, 0.1));
      expect(pillWidths(tester).first, closeTo(pill, 0.01));
    });
  }

  testWidgets(
      'at 3x on 320dp the counter sits on its own line UNDER the pills, at '
      'full size, and the bar grew to hold it', (tester) async {
    await open(tester, step: _modePage, size: const Size(320, 900), scale: 3);
    final label = tester.getRect(inBar(find.text('20 / 24')));
    final back = tester.getRect(inBar(find.byType(IntakeBackButton)));
    expect(label.top, greaterThanOrEqualTo(back.bottom),
        reason: 'stacked: $label under $back');
    expect(label.height, greaterThanOrEqualTo(36 - 0.01));
    expect(tester.getRect(bar()).bottom, greaterThanOrEqualTo(label.bottom),
        reason: 'the bar holds its label');
  });
}
