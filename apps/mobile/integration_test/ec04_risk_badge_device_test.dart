// EC-04 · the risk badge, measured on real hardware.
//
// THIS PROBE DELIBERATELY ASSERTS LESS THAN ITS FIRST DRAFT DID. That draft also walked
// the accessibility tree — and the walk was wrong: it read
// `binding.rootPipelineOwner.semanticsOwner`, which is null under the test binding, so it
// produced an EMPTY label list. Only a non-vacuity guard stopped that from reading as
// "the tree contains no 'low risk', assertion satisfied". The semantics guarantee now
// lives in `test/widget/ec04_risk_badge_semantics_test.dart`, on the HOST, where it is
// debuggable, runs on every `flutter test`, and uses the accessors this repository
// already proved in `fit032_needs_you_device_test.dart`.
//
// WHAT IS LEFT HERE IS WHAT ONLY HARDWARE CAN ANSWER. The host harness renders in Ahem,
// where every glyph is a full em square (the F-24 class), so it cannot say whether
// "NOT ASSESSED" — a longer string than the "LOW RISK" it replaced — still fits the pill
// it is drawn in, at the real font and a real device pixel ratio. A clipped or
// overflowing badge would put EC-04's fix back in the same place it started: a coach
// unable to read that the assessment is absent.
//
// NOTHING IS SIGNED IN AND NO BACKEND IS TOUCHED. `clientDetailProvider` is overridden
// with an in-memory profile, so this leaves no fixture behind and makes no claim about
// any real client's risk.
//
// It emits MARKER lines, and tool/negative_control/ec04_risk_badge_e2e.sh refuses to
// report success unless they appear — a green exit over a screen nobody mounted is the
// most expensive kind of false evidence.
//
//   flutter test integration_test/ec04_risk_badge_device_test.dart \
//     -d linux --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';

const _clientId = 'ec04-probe-client';

Map<String, dynamic> _profile({String? riskLevel}) => {
      'id': _clientId,
      'first_name': 'Probe',
      'last_name': 'Client',
      'role': 'client',
      if (riskLevel != null) 'risk_level': riskLevel,
    };

Future<void> _mount(WidgetTester t, {String? riskLevel}) async {
  await t.pumpWidget(ProviderScope(
    // EVERY provider the screen reads is overridden, not just the one under test.
    //
    // THE FIRST VERSION OVERRODE ONLY clientDetailProvider, and the others then made REAL
    // NETWORK CALLS to QA from inside a device probe. The job's duration escalated
    // 2m -> 8m -> past its 25-minute timeout, which cancelled it — and a cancelled job is
    // not a pass. Raising the timeout would have hidden the cause: a probe whose purpose
    // is to measure a badge at the real font and dpr has no business touching the
    // network, and one that does is neither fast nor deterministic.
    overrides: [
      clientDetailProvider(_clientId)
          .overrideWith((ref) async => _profile(riskLevel: riskLevel)),
      clientHasPaidPlanProvider(_clientId).overrideWith((ref) async => false),
      clientScheduleProvider(_clientId).overrideWith((ref) async => null),
      clientScoreProvider(_clientId).overrideWith((ref) async => null),
      myProgramsProvider.overrideWith((ref) async => const <Map<String, dynamic>>[]),
    ],
    child: MaterialApp(
      home: ClientDetailScreen(clientId: _clientId, clientName: 'Probe Client'),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Drains the provider errors the screen's unmocked fan-out raises, and rethrows
/// anything else so this cannot hide a real failure. An OVERFLOW is explicitly NOT
/// drained — it is the defect this probe exists to detect.
void _drain(WidgetTester t) {
  while (true) {
    final e = t.takeException();
    if (e == null) return;
    final s = e.toString();
    if (s.contains('overflowed')) {
      throw StateError('the badge OVERFLOWED at the real font and dpr: $s');
    }
    final expected = s.contains('Supabase') ||
        s.contains('not initialized') ||
        s.contains('initialize') ||
        s.contains('SocketException') ||
        s.contains('ClientException');
    if (!expected) throw StateError('unexpected exception from the screen: $s');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the unassessed badge fits its pill at the real font and dpr', (t) async {
    await _mount(t);
    _drain(t);
    debugPrint('EC04-MARKER mounted=client_detail');

    final badge =
        find.textContaining(RegExp('not assessed', caseSensitive: false)).first;
    expect(badge, findsOneWidget,
        reason: 'the badge must say the assessment is absent');

    final size = t.getSize(badge);
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
    debugPrint('EC04-MARKER fits=1 dpr=${t.view.devicePixelRatio} '
        'badge=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}');
  });

  testWidgets('an ASSESSED low-risk client still renders, on the device', (t) async {
    await _mount(t, riskLevel: 'low');
    _drain(t);
    expect(find.textContaining(RegExp(r'low\s*risk', caseSensitive: false)),
        findsWidgets);
    debugPrint('EC04-MARKER assessed_low=rendered');
  });

  testWidgets('a HIGH-risk client still renders, on the device', (t) async {
    await _mount(t, riskLevel: 'high');
    _drain(t);
    expect(find.textContaining(RegExp('high risk', caseSensitive: false)),
        findsWidgets);
    debugPrint('EC04-MARKER assessed_high=rendered');
  });
}
