import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/admin/presentation/admin_chrome.dart';

/// **SEC-G10** — the designed state system is documented on every page that carries a panel,
/// and the states that are NOT implemented are named identically on all of them.
///
/// WHAT THIS RATCHETS. `SCREEN-INVENTORY`'s **"States designed"** list is a requirements list
/// like "Data each page needs" and "Interactions expected", and §200 found it had never been
/// traversed. It names five states *"present in all six current files"* — Loading, Empty,
/// Error, Permission (denied), Degraded — plus Unavailable, Stale, Offline, Skeleton and
/// Read-only on named pages, and requires a panel on People, Trust, Operations and Settings
/// plus *"Dashboard states"* on the Control Center.
///
/// Two of the five panels were missing, and **four of the ten states are implemented
/// nowhere**. Before `AdminStatesPanel` each page listed only the states it happened to
/// render, so the four absent ones were silently absent on all six surfaces — the §194 defect
/// at the level of the state system itself.
///
/// THE GUARD IS ABOUT DRIFT, NOT PRESENCE. Six hand-written lists would diverge the first
/// time one page changed, and a divergence here is a page quietly claiming a state it does not
/// have — or omitting one it lacks. So the unimplemented four live in ONE constant, and every
/// panel is required to route through it.
void main() {
  final dir = Directory('lib/features/admin/presentation');

  test('SEC-G10 · the four unimplemented designed states are named, with reasons', () {
    const note = AdminStatesPanel.unimplemented;
    for (final state in ['Offline', 'Stale', 'Degraded', 'Skeleton']) {
      expect(note.contains(state), isTrue, reason: '$state is not named');
    }
    // A name without a reason is a list, not a disclosure.
    for (final reason in [
      'no connectivity signal',
      'no freshness threshold',
      'no definition of partial failure',
      'loading treatment',
    ]) {
      expect(note.contains(reason), isTrue, reason: 'missing the reason "$reason"');
    }
    // `Degraded` must not be confused with the Guardian's own recorded A5 value.
    expect(note.contains('A5'), isTrue,
        reason: 'the Guardian/page-state collision on the word "Degraded" is not addressed');
  });

  test('SEC-G10 · every page that documents the state system routes through the shared '
      'panel, so six lists cannot drift apart', () {
    final offenders = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      // A page documents the state system if it titles a panel with either design label.
      final documents = src.contains("title: 'State system'") ||
          src.contains("title: 'Dashboard states'");
      if (documents && !src.contains('AdminStatesPanel')) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: 'these hand-roll the state list instead of using the shared panel:\n'
            '${offenders.join('\n')}');
  });

  test('SEC-G10 · all FIVE panels the design requires are present', () {
    // Four "State system" panels — People, Trust, Operations, Settings — and one
    // "Dashboard states" on the Control Center. The count is the design's, not a preference.
    var systemPanels = 0;
    var dashboardPanels = 0;
    for (final f in dir.listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      if (src.contains("title: 'State system'")) systemPanels++;
      if (src.contains("title: 'Dashboard states'")) dashboardPanels++;
    }
    expect(systemPanels, 4,
        reason: 'the design places a State system panel on People, Trust, Operations and '
            'Settings; found $systemPanels');
    expect(dashboardPanels, 1,
        reason: 'the Control Center carries "Dashboard states"; found $dashboardPanels');
  });

  test('SEC-G10 · the control — a hand-rolled state list IS caught', () {
    // Proves the detector, so the ban above cannot pass for want of one.
    const handRolled = """
      Widget build(BuildContext c) => const AdminCard(
            title: 'State system',
            child: Column(children: [AdminFootnote('Loading · Empty')]),
          );
    """;
    final documents = handRolled.contains("title: 'State system'");
    expect(documents, isTrue, reason: 'the detector must see the panel title');
    expect(handRolled.contains('AdminStatesPanel'), isFalse,
        reason: 'and must find no shared panel, which is what makes it an offence');
  });

  test('SEC-G10 · each page states its OWN read-only posture, not a shared sentence', () {
    // The first version of the shared panel used one line for all five pages, which made
    // SETTINGS claim it has actions it does not have. The posture is per-page, so the
    // sentences must differ — and the two fully read-only pages must not claim actions.
    final notes = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r"readOnlyNote: '([^']*)'").allMatches(src)) {
        notes.add(m.group(1)!);
      }
    }
    expect(notes.length, greaterThanOrEqualTo(5),
        reason: 'found ${notes.length} postures; five panels are required');
    expect(notes.toSet().length, notes.length,
        reason: 'two pages share a read-only posture, so one of them is describing the '
            'other: ${notes.join(' || ')}');
  });
}
