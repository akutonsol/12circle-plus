import 'dart:convert';

import 'package:circle_fitness/features/onboarding/presentation/intake_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, SemanticsNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-52 · Intake, Coaching Mode step at large text.
//
// The cycle-9 UX review recorded that the Coaching Mode step overflows at 2×
// text. Each option's title sat in a Row with a Spacer and the 22px check
// circle, so a title wider than its column ("Coach Guided" at 2× on a 320dp
// phone) overflowed to the right instead of wrapping. The bottom button had a
// FIXED 56px height, so its label wrapped to two lines at large text and was
// clipped by the button.
//
// Pins here:
//   * no overflow on 320dp and 390dp at 1.0×, 1.3× and 2.0× — before and
//     after each option is selected, with the whole step scrolled through;
//   * every option stays selectable, is >= 44px tall, and is announced as a
//     button with its selected state (only one selected at a time);
//   * the bottom button's label is never clipped;
//   * at 1× on 390dp the geometry is exactly what it was (measured on
//     1b94044);
//   * the Consent step's "I Agree — Start My Journey" fits its button at 1×
//     on 320dp (cycle-9 note).
//
// NOTE: widget tests draw text in the FlutterTest font, whose glyphs are one
// em wide — wider than the app's real font. On 320dp the 1.0× case therefore
// overflowed on the base under this font too; with the real font that case is
// a device check. The 2× case overflows with any font.
//
// HOW TO SEE IT FAIL: run against 1b94044's intake_flow_screen.dart.

const _uid = '00000000-0000-4000-8000-0000000f1052';

const _modePage = 22; // PageView index of Coaching Mode
const _consentPage = 25; // PageView index of Consent

const _modes = ['Self Guided', 'AI Guided', 'Coach Guided'];

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

/// Answers the stored-answers read with a profile parked on [step]; every
/// write succeeds (204, or the row when `select=` asks for it).
class _Server extends http.BaseClient {
  int step = _modePage;

  /// The stored coaching_mode; null leaves it unset (the flow's default).
  String? coachingMode;

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
        final profile = {
          'id': _uid,
          'onboarding_step': step,
          if (coachingMode != null) 'coaching_mode': coachingMode,
        };
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

  setUp(() {
    server.step = _modePage;
    server.coachingMode = null;
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

  /// Collects the first line of every FlutterError (overflow reports
  /// included) while [body] runs, so a failure lists EVERY overflow.
  Future<List<String>> collecting(Future<void> Function() body) async {
    final previous = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError =
        (d) => errors.add(d.exceptionAsString().split('\n').first);
    try {
      await body();
    } finally {
      FlutterError.onError = previous;
    }
    return errors;
  }

  Future<void> open(WidgetTester tester,
      {required Size size, required double scale}) async {
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
  }

  /// The step's own vertical scroll view (NOT the flow's PageView: scrolling
  /// that would move to another step).
  Finder stepScroll() => find
      .ancestor(
          of: find.text('Choose your coaching experience.'),
          matching: find.byType(Scrollable))
      .first;

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 60, scrollable: stepScroll());
    await settle(tester);
  }

  /// The tappable card of option [label].
  Finder card(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
      .first;

  /// The bottom button's label ('Build My Plan' / 'Choose My Coach').
  Finder bottomLabel() => find.byWidgetPredicate((w) =>
      w is Text && (w.data == 'Build My Plan' || w.data == 'Choose My Coach'));

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
          'P0-FL-52: Coaching Mode at ${scale}x text on ${width.toInt()}dp — '
          'no overflow, before and after each option is selected; every '
          'option is reachable, >= 44px and selectable; the bottom label is '
          'not clipped', (tester) async {
        final errors = await collecting(() async {
          await open(tester, size: Size(width, 568), scale: scale);
          expect(page(tester), _modePage.toDouble(),
              reason: 'premise: the flow opened on Coaching Mode');
          for (final mode in _modes) {
            await reveal(tester, find.text(mode));
            expect(find.text(mode).hitTestable(), findsOneWidget,
                reason: '"$mode" is on screen and tappable');
            expect(tester.getSize(card(mode)).height, greaterThanOrEqualTo(44));
            await tester.tap(find.text(mode));
            await settle(tester);
            // The check mark marks exactly the chosen option.
            expect(
                find.descendant(
                    of: card(mode), matching: find.byIcon(Icons.check)),
                findsOneWidget,
                reason: 'tapping "$mode" selects it');
            expect(find.byIcon(Icons.check), findsOneWidget,
                reason: 'only one option is selected at a time');
            // The bottom button's label sits wholly inside the button.
            final label = bottomLabel();
            expect(label, findsOneWidget);
            final button = tester.getRect(find
                .ancestor(of: label, matching: find.byType(AnimatedContainer))
                .first);
            final text = tester.getRect(label);
            expect(
                text.top >= button.top - 0.01 &&
                    text.bottom <= button.bottom + 0.01,
                isTrue,
                reason: 'the bottom label ($text) is clipped by its button '
                    '($button)');
            expect(button.height, greaterThanOrEqualTo(44));
          }
          await reveal(
              tester, find.textContaining('You can change your coaching mode'));
        });
        expect(errors, isEmpty,
            reason: 'P0-FL-52: Coaching Mode must lay out with no overflow at '
                '${scale}x on ${width.toInt()}dp:\n${errors.join('\n')}');
      });
    }
  }

  testWidgets(
      'P0-FL-52: each option is announced as a button with its selected state '
      '(the default, Self Guided, starts selected); selecting one unselects '
      'the others', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester, size: const Size(390, 1400), scale: 1);
    expect(page(tester), _modePage.toDouble());

    SemanticsNode node(String mode) => tester.getSemantics(find.text(mode));

    for (final mode in _modes) {
      expect(
          node(mode),
          matchesSemantics(
            isButton: true,
            hasTapAction: true,
            hasSelectedState: true,
            // The flow's default (IntakeData.coachingMode) is unchanged.
            isSelected: mode == 'Self Guided',
            isInMutuallyExclusiveGroup: true,
          ),
          reason: '"$mode" is a button; only the default is selected');
      expect(node(mode).label, startsWith(mode),
          reason: 'the option is announced by its title');
    }

    await tester.tap(card('AI Guided'));
    await settle(tester);
    for (final mode in _modes) {
      expect(
          node(mode),
          matchesSemantics(
            isButton: true,
            hasTapAction: true,
            hasSelectedState: true,
            isSelected: mode == 'AI Guided',
            isInMutuallyExclusiveGroup: true,
          ),
          reason: '"$mode" selected state after choosing AI Guided');
    }
    // The announced label carries the option's tagline, not only its title.
    expect(node('AI Guided').label,
        contains('I want smart guidance without a human coach'));
    handle.dispose();
  });

  testWidgets(
      'P0-FL-52 1x pin: on a 390dp phone at 1x text the option cards, '
      'titles, check circles and bottom button keep their 1b94044 geometry',
      (tester) async {
    // Tall enough that the whole step fits without scrolling.
    await open(tester, size: const Size(390, 1400), scale: 1);
    expect(page(tester), _modePage.toDouble());
    await tester.tap(card('Coach Guided'));
    await settle(tester);

    Rect r(Finder f) => tester.getRect(f);
    Rect check(String mode) => r(find
        .ancestor(
            of: find.descendant(
                of: card(mode), matching: find.byIcon(Icons.check)),
            matching: find.byType(AnimatedContainer))
        .first);

    // Measured on 1b94044 (FlutterTest font).
    final want = <String, Rect>{
      'card Self Guided': _pin['card Self Guided']!,
      'card AI Guided': _pin['card AI Guided']!,
      'card Coach Guided': _pin['card Coach Guided']!,
      'check Coach Guided': _pin['check Coach Guided']!,
      'bottom button': _pin['bottom button']!,
    };
    final got = <String, Rect>{
      for (final m in _modes) 'card $m': r(card(m)),
      'check Coach Guided': check('Coach Guided'),
      'bottom button': r(find
          .ancestor(of: bottomLabel(), matching: find.byType(AnimatedContainer))
          .first),
    };
    for (final k in want.keys) {
      expect(got[k], want[k], reason: '$k moved at 1x');
    }
    // A title's glyphs start where they did and keep one line's height.
    for (final m in _modes) {
      final t = r(find.text(m));
      expect(t.topLeft, _titleTopLeft[m], reason: '"$m" title moved at 1x');
      expect(t.height, 24, reason: '"$m" title is one line at 1x');
    }
  });

  // The rect-inside-rect check above cannot see a FIXED-height button: the
  // paragraph is squeezed to the button's height and still "fits", while its
  // second line is cut off. Here the label's full laid-out text height (its
  // intrinsic height at its own width) is compared with what it was given and
  // with the button. A 56px button fails at 2x on 320dp, where the label wraps.
  for (final (mode, text) in [
    ('Coach Guided', 'Choose My Coach'),
    ('Self Guided', 'Build My Plan'),
  ]) {
    testWidgets(
        'P0-FL-52: at 2.0x on 320dp the bottom button "$text" wraps and the '
        'button grows to hold every line (label paragraph not clipped)',
        (tester) async {
      await collecting(() async {
        await open(tester, size: const Size(320, 568), scale: 2);
        expect(page(tester), _modePage.toDouble());
        await reveal(tester, find.text(mode));
        await tester.tap(find.text(mode));
        await settle(tester);
      });
      final label = find.text(text);
      expect(label, findsOneWidget);
      final p = tester.renderObject<RenderParagraph>(label);
      final full = p.getMaxIntrinsicHeight(p.size.width);
      // One unwrapped line's height, from the paragraph itself.
      final line = p.getMaxIntrinsicHeight(double.infinity);
      expect(full, greaterThanOrEqualTo(2 * line - 0.01),
          reason: 'premise: "$text" wraps to 2+ lines at 2x on 320dp '
              '(full text height $full)');
      expect(p.size.height, greaterThanOrEqualTo(full - 0.01),
          reason: 'the "$text" paragraph was squeezed to ${p.size.height}px; '
              'its lines need ${full}px — the label is clipped');
      final button = tester.getRect(find
          .ancestor(of: label, matching: find.byType(AnimatedContainer))
          .first);
      expect(button.height, greaterThanOrEqualTo(full + 16 - 0.01),
          reason: 'the button ($button) must hold the label ($full) plus its '
              '8px vertical padding');
      final r = tester.getRect(label);
      expect(r.top >= button.top - 0.01 && r.bottom <= button.bottom + 0.01,
          isTrue);
    });
  }

  // UX F1: a wrapped title keeps 8px clear of the 22px check circle.
  for (final scale in [2.0, 3.0]) {
    testWidgets(
        'P0-FL-52: at ${scale}x on 320dp each option title ends at least 8px '
        'before its check circle', (tester) async {
      final errors = await collecting(() async {
        await open(tester, size: const Size(320, 568), scale: scale);
        expect(page(tester), _modePage.toDouble());
      });
      for (final mode in _modes) {
        errors.addAll(await collecting(() => reveal(tester, find.text(mode))));
        final title = tester.getRect(find.text(mode));
        final circle = tester.getRect(find.descendant(
            of: card(mode),
            matching: find.byWidgetPredicate((w) =>
                w is AnimatedContainer &&
                w.constraints ==
                    const BoxConstraints.tightFor(width: 22, height: 22))));
        expect(title.right + 8, lessThanOrEqualTo(circle.left + 0.01),
            reason: '"$mode" title ($title) must end 8px before its check '
                'circle ($circle) at ${scale}x');
      }
      // At 3x the shared step bar (_IntakeStepBar, "20 / 24") overflows on
      // 320dp — outside this package, reported separately; the option cards
      // themselves are checked at 2x by the no-overflow tests above.
      if (scale <= 2) {
        expect(errors, isEmpty,
            reason: 'no overflow at ${scale}x on 320dp:\n${errors.join('\n')}');
      }
    });
  }

  // UX F2: the Continue button is one announced button with its label and
  // whether it can be pressed.
  testWidgets(
      'P0-FL-52: the bottom button is announced as an enabled button with its '
      'visible label, and follows the selection', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester, size: const Size(390, 1400), scale: 1);
    expect(page(tester), _modePage.toDouble());
    expect(
        tester.getSemantics(find.bySemanticsLabel('Build My Plan')),
        matchesSemantics(
          label: 'Build My Plan',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ));
    await tester.tap(card('Coach Guided'));
    await settle(tester);
    expect(
        tester.getSemantics(find.bySemanticsLabel('Choose My Coach')),
        matchesSemantics(
          label: 'Choose My Coach',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ));
    handle.dispose();
  });

  testWidgets(
      'P0-FL-52: with no coaching mode chosen the bottom button is announced '
      'as a disabled button with the hint "Choose a coaching mode first"',
      (tester) async {
    server.coachingMode = ''; // a stored answer with no mode chosen
    final handle = tester.ensureSemantics();
    await open(tester, size: const Size(390, 1400), scale: 1);
    expect(page(tester), _modePage.toDouble());
    expect(find.byIcon(Icons.check), findsNothing,
        reason: 'premise: no option is selected');
    expect(
        tester.getSemantics(find.bySemanticsLabel('Build My Plan')),
        matchesSemantics(
          label: 'Build My Plan',
          hint: 'Choose a coaching mode first',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ));
    // Choosing a mode enables it and drops the hint.
    await tester.tap(card('AI Guided'));
    await settle(tester);
    expect(
        tester.getSemantics(find.bySemanticsLabel('Build My Plan')),
        matchesSemantics(
          label: 'Build My Plan',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ));
    handle.dispose();
  });

  testWidgets(
      'cycle-9 note: the Consent button "I Agree — Start My Journey" fits '
      'its button at 1x on 320dp (no overflow, label inside the button)',
      (tester) async {
    server.step = _consentPage;
    final errors = await collecting(() async {
      await open(tester, size: const Size(320, 568), scale: 1);
      expect(page(tester), _consentPage.toDouble(),
          reason: 'premise: the flow opened on Consent');
    });
    expect(errors, isEmpty, reason: errors.join('\n'));
    final label = find.text('I Agree — Start My Journey');
    expect(label.hitTestable(), findsOneWidget);
    final button = tester.getRect(find
        .ancestor(of: label, matching: find.byType(AnimatedContainer))
        .first);
    final text = tester.getRect(label);
    expect(
        button.contains(text.topLeft) &&
            button.contains(text.bottomRight - const Offset(0.01, 0.01)),
        isTrue,
        reason: 'the label ($text) is clipped by its button ($button)');
    expect(button.height, greaterThanOrEqualTo(54));
  });
}

/// 1b94044 geometry at 390×1400, 1x, Coach Guided selected (see the 1x pin).
const _pin = <String, Rect>{
  'card Self Guided': Rect.fromLTRB(24.0, 286.0, 366.0, 592.0),
  'card AI Guided': Rect.fromLTRB(24.0, 592.0, 366.0, 935.0),
  'card Coach Guided': Rect.fromLTRB(24.0, 935.0, 366.0, 1222.0),
  'check Coach Guided': Rect.fromLTRB(322.5, 957.5, 344.5, 979.5),
  'bottom button': Rect.fromLTRB(24.0, 1328.0, 366.0, 1384.0),
};

const _titleTopLeft = <String, Offset>{
  'Self Guided': Offset(109.0, 307.0),
  'AI Guided': Offset(109.0, 613.0),
  'Coach Guided': Offset(109.5, 956.5),
};
