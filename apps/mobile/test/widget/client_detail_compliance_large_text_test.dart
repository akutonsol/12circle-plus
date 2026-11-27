import 'dart:convert';

import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/two_member_postgrest.dart' show memberA, signInAs;

// P0-FL-52 · Client detail, "12 Circle Score + Compliance" at large text.
//
// The four _ComplianceCard tiles share one Row. Cycle 9 left them UNVERIFIED
// at 2× text on a 320dp phone. These tests are the verification pin:
//   * no overflow on 320dp (and 390dp) at 1.0×, 1.3× and 2.0×;
//   * each tile shows its whole figure, "/max" and label inside its border;
//   * at 1× the four tiles keep their geometry (measured on 1b94044).
//
// RESULT ON 1b94044: the no-overflow pins pass — the row does NOT overflow
// (each tile is an Expanded column whose texts wrap). But at 2× on 320dp a
// tile is ~45px inside and its label breaks mid-word, so above 1.5× the four
// tiles now lay out 2×2 (the 2×2 tests fail on 1b94044), and each tile is
// announced once as "<label>: <pts> of <max>".
//
// Every provider the page reads is overridden, so no request leaves the test;
// Supabase is initialised against a fake that answers everything empty in case
// a child widget reads directly.

const _clientId = '00000000-0000-4000-8000-00000000c152';

class _Empty extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
          Stream.value(utf8.encode(request.method == 'GET' ? '[]' : '')),
          request.method == 'GET' ? 200 : 204,
          request: request,
          headers: {'content-type': 'application/json'});
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

Map<String, dynamic> _detail() => {
      'id': _clientId,
      'first_name': 'Jordan',
      'last_name': 'Test',
      'role': 'client',
      'coaching_mode': 'coached',
      // The widest figures each tile can show.
      'today_score': {
        'total_score': 90,
        'workout_points': 30,
        'nutrition_points': 30,
        'habits_points': 20,
        'checkin_points': 10,
      },
    };

const _tiles = [
  ('Workout', '30', '/30'),
  ('Nutrition', '30', '/30'),
  ('Habits', '20', '/20'),
  ('Check-In', '10', '/10'),
];

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Empty(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
    // P0-FL-59f: the client page is drawn for the coach it was opened by only.
    await signInAs(memberA);
  });

  /// Pumps the Overview with every FlutterError collected (first line), so a
  /// failing expectation lists every overflow on the page.
  Future<List<String>> pump(WidgetTester t,
      {required double width, required double scale}) async {
    t.view
      ..devicePixelRatio = 1
      // Tall enough that the ListView builds every Overview card at 2×.
      ..physicalSize = Size(width, scale > 1 ? 16000 : 4000);
    addTearDown(t.view.reset);
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final previous = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError =
        (d) => errors.add(d.exceptionAsString().split('\n').first);
    try {
      await t.pumpWidget(ProviderScope(
        overrides: [
          clientDetailProvider(_clientId)
              .overrideWith((ref) async => _detail()),
          clientAssessmentProvider(_clientId).overrideWith((ref) async =>
              const ClientAssessment(ClientAssessmentStatus.loaded,
                  {'has_assessment': true, 'risk_level': 'low'})),
          clientHasPaidPlanProvider(_clientId)
              .overrideWith((ref) async => false),
          clientScheduleProvider(_clientId).overrideWith((ref) async => null),
          clientScoreProvider(_clientId).overrideWith((ref) async => null),
          myProgramsProvider
              .overrideWith((ref) async => const <Map<String, dynamic>>[]),
        ],
        child: const MaterialApp(
          home: ClientDetailScreen(
              clientId: _clientId, clientName: 'Jordan', owner: memberA),
        ),
      ));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    } finally {
      FlutterError.onError = previous;
    }
    return errors;
  }

  /// The decorated tile that holds [label].
  Finder tile(String label) => find
      .ancestor(
          of: find.text(label),
          matching: find
              .byWidgetPredicate((w) => w is Container && w.decoration != null))
      .first;

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
          'P0-FL-52: the Compliance row at ${scale}x text on ${width.toInt()}dp '
          'lays out with no overflow and every tile shows its figure, max and '
          'label inside its border', (t) async {
        final errors = await pump(t, width: width, scale: scale);
        expect(find.text('Compliance'), findsOneWidget,
            reason: 'premise: the Overview card was built');
        expect(errors, isEmpty,
            reason: 'no overflow at ${scale}x on ${width.toInt()}dp:\n'
                '${errors.join('\n')}');
        for (final (label, pts, max) in _tiles) {
          final box = t.getRect(tile(label));
          for (final s in [pts, max, label]) {
            final r = t.getRect(
                find.descendant(of: tile(label), matching: find.text(s)));
            expect(
                r.left >= box.left - 0.01 &&
                    r.right <= box.right + 0.01 &&
                    r.top >= box.top - 0.01 &&
                    r.bottom <= box.bottom + 0.01,
                isTrue,
                reason: '"$s" ($r) spills out of the $label tile ($box)');
          }
        }
      });
    }
  }

  // Above 1.5x text the four tiles go two by two: on 320dp at 2x a tile in
  // the single row is ~45px inside, so "Nutrition", "Workout" and "Habits"
  // broke mid-word.
  //
  // FlutterTest font note: its glyphs are one em wide (a 9pt label at 2x is
  // 18px a letter), so "Nutrition" (162px) cannot sit on one line even in a
  // half-width tile here; with the real font (~0.55em a letter, ~90px) it
  // should fit, but that is a device check. What IS asserted: the 2x2 geometry
  // (equal halves, 8px gaps), each tile at least twice its single-row width,
  // and each label in at most 2 lines in this font.
  for (final width in [320.0, 390.0]) {
    testWidgets(
        'P0-FL-52: at 2.0x on ${width.toInt()}dp the Compliance tiles lay out '
        '2x2 (Workout|Nutrition over Habits|Check-In, 8px gaps) and no label '
        'is broken into more than 2 lines', (t) async {
      expect(await pump(t, width: width, scale: 2), isEmpty);
      final w = t.getRect(tile('Workout'));
      final n = t.getRect(tile('Nutrition'));
      final h = t.getRect(tile('Habits'));
      final c = t.getRect(tile('Check-In'));
      // Two per row: Workout and Nutrition share a row, Habits and Check-In
      // the next one (each row centres its tiles vertically).
      expect(w.center.dy, closeTo(n.center.dy, 0.01));
      expect(h.center.dy, closeTo(c.center.dy, 0.01));
      final row1Bottom = w.bottom > n.bottom ? w.bottom : n.bottom;
      final row2Top = h.top < c.top ? h.top : c.top;
      expect(row2Top - row1Bottom, closeTo(8, 0.01),
          reason: 'the second row sits 8px below the first');
      // Same columns, 8px apart, equal widths.
      expect(h.left, closeTo(w.left, 0.01));
      expect(c.left, closeTo(n.left, 0.01));
      expect(n.left - w.right, closeTo(8, 0.01));
      expect(c.left - h.right, closeTo(8, 0.01));
      expect(n.width, closeTo(w.width, 0.01));
      // The single row on 1b94044 at this width: four tiles, three gaps.
      final rowWidth = c.right - w.left;
      expect(w.width, greaterThanOrEqualTo(2 * (rowWidth - 24) / 4),
          reason: 'each tile is at least twice its single-row width');
      for (final (label, _, _) in _tiles) {
        final p = t.renderObject<RenderParagraph>(
            find.descendant(of: tile(label), matching: find.text(label)));
        // One unwrapped line's height, from the paragraph itself.
        final oneLine = p.getMaxIntrinsicHeight(double.infinity);
        final lines = (p.size.height / oneLine).round();
        expect(lines, lessThanOrEqualTo(2),
            reason: '"$label" is broken into $lines lines '
                '(${p.size.width}px wide tile label)');
      }
    });

    testWidgets(
        'P0-FL-52: at 1.3x on ${width.toInt()}dp the Compliance tiles stay in '
        'one row', (t) async {
      expect(await pump(t, width: width, scale: 1.3), isEmpty);
      final tops = [
        for (final (label, _, _) in _tiles) t.getRect(tile(label)).center.dy
      ];
      for (final y in tops) {
        expect(y, closeTo(tops.first, 0.01));
      }
      final w = t.getRect(tile('Workout'));
      final n = t.getRect(tile('Nutrition'));
      expect(n.left - w.right, closeTo(8, 0.01));
    });
  }

  testWidgets(
      'P0-FL-52: each Compliance tile is announced once as "<label>: <pts> of '
      '<max>"', (t) async {
    final handle = t.ensureSemantics();
    expect(await pump(t, width: 390, scale: 1), isEmpty);
    for (final (label, pts, max) in _tiles) {
      final spoken = '$label: $pts of ${max.substring(1)}';
      expect(find.bySemanticsLabel(spoken), findsOneWidget,
          reason: 'the $label tile reads "$spoken"');
    }
    // The fragments are not announced on their own.
    expect(find.bySemanticsLabel('/30'), findsNothing);
    handle.dispose();
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
        'P0-FL-52 1x pin: at 1x on ${width.toInt()}dp the four Compliance '
        'tiles keep their 1b94044 geometry', (t) async {
      expect(await pump(t, width: width, scale: 1), isEmpty);
      for (final (label, _, _) in _tiles) {
        expect(t.getRect(tile(label)), _pin[width.toInt()]![label],
            reason: '$label tile moved at 1x on ${width.toInt()}dp');
      }
    });
  }
}

/// 1b94044 geometry at 1x, FlutterTest font (see the 1x pin).
const _pin = <int, Map<String, Rect>>{
  320: {
    'Workout': Rect.fromLTRB(33.0, 506.5, 90.5, 608.5),
    'Nutrition': Rect.fromLTRB(98.5, 500.0, 156.0, 615.0),
    'Habits': Rect.fromLTRB(164.0, 506.5, 221.5, 608.5),
    'Check-In': Rect.fromLTRB(229.5, 506.5, 287.0, 608.5),
  },
  390: {
    'Workout': Rect.fromLTRB(33.0, 470.0, 108.0, 572.0),
    'Nutrition': Rect.fromLTRB(116.0, 470.0, 191.0, 572.0),
    'Habits': Rect.fromLTRB(199.0, 476.5, 274.0, 565.5),
    'Check-In': Rect.fromLTRB(282.0, 470.0, 357.0, 572.0),
  },
};
