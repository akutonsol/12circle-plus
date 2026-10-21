import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';

/// EC-04 · what a coach using a SCREEN READER is told about an unassessed client.
///
/// The fix distinguishes "unassessed" from "low risk" by COLOUR and by LABEL. A screen
/// reader conveys no colour, so if the label did not reach the accessibility tree the
/// defect would persist for exactly the users least able to notice it — and EC-04's harm
/// is a coach being told a client is low risk when nobody assessed them.
///
/// THE SEMANTICS TREE IS AVAILABLE ON THE HOST, so this assertion does not need a device
/// and is not deferred to one. The sibling device probe
/// (`integration_test/ec04_risk_badge_device_test.dart`) keeps only what genuinely needs
/// real hardware: the real font at a real device pixel ratio, where Ahem's full-em
/// squares cannot answer whether the label fits its pill.
///
/// Nothing is signed in: `clientDetailProvider` is overridden with an in-memory profile.
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
    child: const MaterialApp(
      home: ClientDetailScreen(clientId: _clientId, clientName: 'Probe Client'),
    ),
  ));
  // The screen fans out to several live providers. They are ALLOWED to fail here — that
  // is the read-failure path EC-04 is partly about — so the frames are pumped rather
  // than settled, and any exception they raise is drained below.
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Drains provider errors raised by the screen's unmocked fan-out. Anything that is NOT
/// such an error is rethrown, so this cannot hide a real failure.
void _drain(WidgetTester t) {
  while (true) {
    final e = t.takeException();
    if (e == null) return;
    final s = e.toString();
    final expected = s.contains('Supabase') ||
        s.contains('not initialized') ||
        s.contains('initialize') ||
        s.contains('SocketException') ||
        s.contains('ClientException');
    if (!expected) throw StateError('unexpected exception from the screen: $s');
  }
}

/// Reads the accessibility tree the way this repository already does in
/// `fit032_needs_you_device_test.dart`: through `find.bySemanticsLabel` and
/// `tester.getSemantics`, not by walking a pipeline owner.
///
/// My first version walked `binding.rootPipelineOwner.semanticsOwner.rootSemanticsNode`,
/// which is null under `flutter_test` — so it produced an EMPTY label list. The guard
/// below (`expect(joined, isNotEmpty)`) is the only reason that did not read as "the tree
/// contains no 'low risk', assertion satisfied". A semantics check with no semantics is
/// the vacuous-success class this programme keeps finding.
bool _semanticsContains(WidgetTester t, String needle) =>
    find.bySemanticsLabel(RegExp(needle, caseSensitive: false)).evaluate().isNotEmpty;

/// Every label actually present, for the failure message and for the non-vacuity guard.
List<String> _semanticLabels(WidgetTester t) {
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final d = w.data;
    if (d != null && d.isNotEmpty) out.add(d);
  }
  return out;
}

void main() {
  testWidgets('an UNASSESSED client is labelled unassessed on screen', (t) async {
    await _mount(t);
    _drain(t);
    expect(find.textContaining(RegExp('not assessed', caseSensitive: false)),
        findsWidgets,
        reason: 'the badge must say the assessment is absent');
    expect(find.textContaining(RegExp(r'low\s*risk', caseSensitive: false)),
        findsNothing,
        reason: 'an unassessed client must never be presented as low risk');
  });

  testWidgets('…and a screen reader is TOLD so — the assertion colour cannot make',
      (t) async {
    final handle = t.ensureSemantics();
    await _mount(t);
    _drain(t);
    final joined = _semanticLabels(t).join(' | ').toLowerCase();
    // NON-VACUITY FIRST. If the surface produced nothing, every "does not contain"
    // assertion below would pass for the wrong reason.
    expect(joined, isNotEmpty,
        reason: 'the surface rendered no text at all, so this proves nothing');
    expect(_semanticsContains(t, 'not assessed'), isTrue,
        reason: 'a coach on a screen reader must be TOLD the assessment is absent. '
            'Rendered: $joined');
    expect(_semanticsContains(t, r'low\s*risk'), isFalse,
        reason: 'the accessibility tree must not claim a low assessment: $joined');
    handle.dispose();
  });

  testWidgets('an ASSESSED low-risk client is still labelled low risk, so the fix did '
      'not simply delete the state', (t) async {
    await _mount(t, riskLevel: 'low');
    _drain(t);
    expect(find.textContaining(RegExp(r'low\s*risk', caseSensitive: false)),
        findsWidgets);
    expect(find.textContaining(RegExp('not assessed', caseSensitive: false)),
        findsNothing);
  });

  testWidgets('a HIGH-risk client is unaffected', (t) async {
    await _mount(t, riskLevel: 'high');
    _drain(t);
    expect(find.textContaining(RegExp('high risk', caseSensitive: false)),
        findsWidgets);
  });
}
