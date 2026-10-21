import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **SEC-G9** — a capability gate may wrap an ACTION; it may never wrap the DATA.
///
/// THE DEFECT THIS RATCHETS, which shipped three times before it was named. V5 §189 built
/// the Events directory and the People "Edit profile" action by wrapping each list in
/// `adminCapabilityGate`, and found the same shape already in the moderation queue (§188)
/// and the Trust incidents card (§183). The helper is honest — while a check is in flight
/// it renders *"Checking your permissions…"*, and when the check FAILS it says the
/// permission could not be read and that this is not a denial. But a gate chooses between
/// two widgets, so wrapping a list makes that sentence **replace every row**:
///
///   * rows authorized by `·view` vanished because an answer about `·update` was pending;
///   * a single failed `admin_can` RPC emptied a page that had already loaded its data;
///   * and the emptiness read as "there is nothing here", which is the false zero this
///     whole programme exists to prevent — arrived at through authorization rather than
///     through a `?? 0`.
///
/// THE STATIC SIGNATURE IS EXACT. The rows only disappear if they are INSIDE a gate branch,
/// and rows are rendered by a `for (`. So: no `adminCapabilityGate(` call may contain a
/// `for (` within its argument list. An action — a button, a footnote, a dialog opener —
/// never needs one, which is why this is a ban and not a heuristic.
///
/// The explanation still has to be given, so it moves BESIDE the rows: `adminCapabilityNote`
/// returns the denial sentence for a real `false`, the "could not be checked" sentence for a
/// failure, and nothing while loading. A surface that gates a list therefore owes a note,
/// which the second test requires.
void main() {
  final dir = Directory('lib/features/admin/presentation');

  /// The names a capability is read under in this layer.
  ///
  /// EXPLICIT ALTERNATION RATHER THAN `can\w*`, and the control below is why: `can\w*` is
  /// case-SENSITIVE, so it never matched `adminCanUpdateUsersProvider` — the capital `C` —
  /// and the scan that used it was passing on zero matches while a real collapsed read sat
  /// in the tree. `SEC-G6` had the identical defect, where `[Nn]ot\s*[Aa]ssessed` is
  /// case-insensitive only on its first letters and failed against `NOT ASSESSED`. A
  /// case-insensitive `can` would instead swallow `cannot` and `canvas`, so the names are
  /// listed.
  final capabilityName = RegExp(
      r'adminCan|can(Edit|Moderate|Update|Act|View|Create|Resolve)|[Cc]apability');

  /// Returns the source span of each `adminCapabilityGate(` call's argument list, by
  /// matching parentheses — a line-based scan would miss the multi-line calls that are the
  /// only ones big enough to contain a list.
  List<String> gateCalls(String src) {
    const needle = 'adminCapabilityGate(';
    final out = <String>[];
    var from = 0;
    while (true) {
      final i = src.indexOf(needle, from);
      if (i < 0) break;
      var depth = 0;
      var j = i + needle.length - 1;
      for (; j < src.length; j++) {
        if (src[j] == '(') depth++;
        if (src[j] == ')') {
          depth--;
          if (depth == 0) break;
        }
      }
      out.add(src.substring(i, j < src.length ? j + 1 : src.length));
      from = j + 1;
    }
    return out;
  }

  test('SEC-G9 · the paren matcher finds EVERY gate call (self-consistency, not a count)',
      () {
    // A HARDCODED FLOOR WOULD HAVE BEEN THE WRONG INSTRUMENT. The first version of this
    // guard required "at least four" gate calls, and the §189 fix legitimately reduced
    // them to one — a floor would then have failed for the right code and been lowered to
    // whatever the code happened to do, which is not a check. Self-consistency cannot
    // drift: the brace matcher must find exactly as many calls as a plain substring scan
    // does. If it ever finds fewer, the ban below is silently judging a subset. This is
    // the shape that caught ERR-G1 reading 65 substrings against 64 regex matches.
    var substrings = 0;
    var matched = 0;
    for (final f in dir.listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      substrings += RegExp('adminCapabilityGate\\(').allMatches(src).length;
      matched += gateCalls(src).length;
    }
    expect(matched, substrings,
        reason: 'the matcher found $matched of $substrings calls; the ban below would be '
            'judging only part of the code');
    expect(substrings, greaterThan(0),
        reason: 'no gate calls found at all — the scan, or the directory, is wrong');
  });

  test('SEC-G9 · no capability gate encloses a list of rows', () {
    final offences = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      for (final call in gateCalls(f.readAsStringSync())) {
        if (RegExp(r'for\s*\(').hasMatch(call)) {
          offences.add('${f.path}: ${call.split('\n').first.trim()}');
        }
      }
    }
    expect(offences, isEmpty,
        reason: 'a gate branch iterates rows, so a pending or failed capability check will '
            'hide data the operator is already authorized to see:\n${offences.join('\n')}');
  });

  test('SEC-G9 · the control — the pre-fix shape IS caught', () {
    // The literal §188 moderation-queue shape. If the matcher stopped working, this fails
    // and the guard above is revealed as passing for want of a detector.
    const prefix = '''
      return adminCapabilityGate(
        canModerate,
        allowed: () => Column(children: [
          for (final r in reports.take(10)) _ReportRow(report: r),
        ]),
        denied: const AdminFootnote('Read-only.'),
      );
    ''';
    expect(gateCalls(prefix).length, 1, reason: 'the matcher must find the call');
    expect(RegExp(r'for\s*\(').hasMatch(gateCalls(prefix).single), isTrue,
        reason: 'the detector must flag a gate branch that iterates rows');
  });

  test('SEC-G9 · no admin surface decides an action by collapsing a capability read', () {
    // THE THIRD SHAPE §189 TRIED, and the one EC-G8 rejected on its own stated grounds.
    // `admin_can` is an RPC, so it does I/O, and `capability.valueOrNull == true` turns
    // "could not ask" into "no" at the call site. EC-G8's note refuses the escape hatch in
    // terms — the indistinguishability "is the argument for a typed error state, not a
    // bigger allowlist" — so the admin layer reads a capability through
    // `adminGatedList`/`adminCapabilityGate`, both of which branch on all four states, and
    // never through `.valueOrNull`.
    final offences = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      for (final raw in src.split('\n')) {
        final line = raw.trim();
        // COMMENTS ARE NOT CODE, and this guard flagged its own documentation before the
        // skip existed — the same mistake three prose assertions in this run made, where
        // "must not mention X" fired on the sentence explaining that X is absent. A guard
        // that judges the explanation of a defect instead of the defect makes the defect
        // harder to document, which is the opposite of its job.
        if (line.startsWith('///') || line.startsWith('//')) continue;
        if (!line.contains('.valueOrNull')) continue;
        if (capabilityName.hasMatch(line)) {
          offences.add('${f.path}: $line');
        }
      }
    }
    expect(offences, isEmpty,
        reason: 'a capability is read with `.valueOrNull`, which collapses a FAILED check '
            'into a denial at the read site:\n${offences.join('\n')}');
  });

  test('SEC-G9 · the control — a collapsed capability read IS caught', () {
    // Proves the detector, so the assertion above cannot pass for want of one.
    bool offends(String raw) {
      final line = raw.trim();
      if (line.startsWith('///') || line.startsWith('//')) return false;
      if (!line.contains('.valueOrNull')) return false;
      return capabilityName.hasMatch(line);
    }

    expect(
        offends(
            '  final writable = ref.watch(adminCanUpdateUsersProvider).valueOrNull == true;'),
        isTrue,
        reason: 'the detector must flag a collapsed capability read');
    // And must NOT flag the sentence that documents it — the skip is load-bearing, not
    // cosmetic, so it is asserted rather than assumed.
    expect(offends('  /// `capability.valueOrNull == true` was rejected by EC-G8.'), isFalse,
        reason: 'a comment explaining the defect is not the defect');
  });

  test('SEC-G9 · every surface that renders a gated row list routes it through '
      'adminGatedList', () {
    // The two bans above can both be satisfied by deleting the explanation along with the
    // wrapper, leaving an operator with a bare area and no reason. `adminGatedList` is the
    // one shape that renders rows in all four states AND states a failed check, so a
    // surface whose rows carry a capability-dependent action has to use it.
    final missing = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      // A row widget that takes a capability-shaped bool is the signature of a gated list.
      final gatedRows =
          RegExp(r'(canEdit|canModerate|canUpdate|canAct):\s*canAct').hasMatch(src);
      if (gatedRows && !src.contains('adminGatedList(')) missing.add(f.path);
    }
    expect(missing, isEmpty,
        reason: 'these surfaces hand a capability bool to their rows without the one '
            'wrapper that states a failed check:\n${missing.join('\n')}');
  });

  test('SEC-G9 · adminGatedList itself keeps the four states apart', () {
    // The guard above only proves the helper is USED. This proves the helper is still the
    // thing worth using: its error arm must render the rows AND say the check failed, which
    // is the whole difference from the gate it replaced.
    final src = File('lib/features/admin/presentation/admin_chrome.dart').readAsStringSync();
    final i = src.indexOf('Widget adminGatedList(');
    expect(i, greaterThan(-1), reason: 'adminGatedList is gone; this guard judges nothing');
    final body = src.substring(i);
    final errorArm = body.substring(body.indexOf('error:'), body.indexOf('data:'));
    expect(errorArm.contains('rows(false)'), isTrue,
        reason: 'the error arm must still RENDER THE ROWS, not replace them');
    expect(errorArm.contains('not a denial'), isTrue,
        reason: 'the error arm must still SAY the check failed and that it is not a denial');
  });
}
