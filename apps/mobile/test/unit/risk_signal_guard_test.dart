import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// EC-04 · SEC-G6 — an ABSENT risk assessment must never render as the SAFEST one.
///
/// The defect this ratchets was `d['risk_level'] as String? ?? 'low'` at four call
/// sites, feeding two badge renderers whose `switch` ended in
/// `default: green / 'LOW RISK'`. So a client whose PAR-Q was never saved — and a
/// client whose profile read merely FAILED, since the provider returns null for the
/// whole profile on any error — was affirmatively presented to their coach as low
/// risk. "The read failed" and "this person is low risk" were the same pixel.
///
/// It is guarded statically rather than by rendering the screen, because the screen
/// needs a live profile provider and an initialised client, and the property worth
/// protecting is textual: the coercion must not exist, `low` must be matched
/// explicitly, and the fallback must not be the reassuring branch.
///
/// THE POLICY HALF IS `CON-04` AND IS NOT TOUCHED HERE. Whether an unassessed client
/// may be programmed at all is a product decision; this is the display half, which
/// the registry records as independent and safe.
void main() {
  const dir = 'lib/features/dashboard/presentation';
  late Map<String, String> sources;

  setUpAll(() {
    sources = {
      for (final f in Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        f.path: f.readAsStringSync(),
    };
    // POSITIVE CONTROL. A scan that reads nothing reports every rule satisfied.
    expect(sources.length, greaterThanOrEqualTo(2),
        reason: 'SEC-G6 scanned ${sources.length} files under $dir — too few');
    final detail = sources.entries
        .where((e) => e.key.endsWith('client_detail_screen.dart'))
        .toList();
    expect(detail, hasLength(1),
        reason: 'client_detail_screen.dart is the file this guard exists for');
    expect(detail.single.value.contains('risk_level'), isTrue,
        reason: 'the scan cannot see risk_level, so it is broken, not the code');
  });

  String codeOnly(String src) =>
      src.split('\n').map((l) => l.split('//').first).join('\n');

  test('no file coerces an absent risk level into an assessed one', () {
    final offenders = <String>[];
    for (final e in sources.entries) {
      final lines = codeOnly(e.value).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r"""\?\?\s*['"](low|moderate|high)['"]""").hasMatch(lines[i])) {
          offenders.add('${e.key}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'an absent assessment is not an assessment:\n${offenders.join('\n')}');
  });

  test('no file coerces an absent risk SCORE to zero — "0 / 8" is a measurement, and '
      'the most reassuring one available', () {
    final offenders = <String>[];
    for (final e in sources.entries) {
      final lines = codeOnly(e.value).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r"risk_score.*\?\?\s*0\b").hasMatch(lines[i])) {
          offenders.add('${e.key}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  group('every risk switch matches `low` explicitly and falls back to UNASSESSED', () {
    // Each risk switch is located by its 'high' arm, then the whole switch body is
    // read to the closing brace.
    List<String> riskSwitches(String src) {
      final code = codeOnly(src);
      final out = <String>[];
      // LOCATED BY CONTENT, NOT BY VARIABLE NAME. The first draft matched
      // `switch (risk…)` and so found ONE of the two switches — `_riskBadge` takes
      // its parameter as `level`. A guard that can be dodged by renaming a local is
      // not a guard, and under-detecting while reporting success is the failure this
      // programme keeps rediscovering (§139.3, §165, §166.2). Any switch whose body
      // carries a `case 'high'` arm AND mentions a risk label is a risk switch,
      // whatever its subject happens to be called.
      for (final m in RegExp(r'switch\s*\([^)]*\)\s*\{').allMatches(code)) {
        var depth = 0;
        var i = m.end - 1;
        final start = i;
        do {
          if (code[i] == '{') depth++;
          if (code[i] == '}') depth--;
          i++;
        } while (depth > 0 && i < code.length);
        final body = code.substring(start, i);
        final isRisk = RegExp(r"case\s+'high'").hasMatch(body) &&
            RegExp(r'[Rr][Ii][Ss][Kk]').hasMatch(body);
        if (isRisk) out.add(body);
      }
      return out;
    }

    test('the switches exist at all, so the assertions below are not vacuous', () {
      final all = sources.values.expand(riskSwitches).toList();
      expect(all, hasLength(2),
          reason: 'client_detail_screen carries two risk switches — the compact badge '
              'and the detail panel. Found ${all.length}.');
    });

    test("`low` is an EXPLICIT case, never reached through `default`", () {
      for (final sw in sources.values.expand(riskSwitches)) {
        expect(RegExp(r"""case\s+['"]low['"]""").hasMatch(sw), isTrue,
            reason: 'an implicit low is how an unassessed client became a low-risk '
                'one:\n$sw');
      }
    });

    test('the `default` arm renders neither the green colour nor a LOW label', () {
      for (final sw in sources.values.expand(riskSwitches)) {
        final def = sw.substring(sw.indexOf('default:'));
        expect(def.contains('_green'), isFalse,
            reason: 'the fallback must not be the reassuring colour:\n$def');
        // caseSensitive: false, rather than hand-built character classes. The first
        // draft wrote `[Nn]ot\s*[Aa]ssessed`, which is case-insensitive only on the
        // FIRST letter of each word and therefore did not match the actual label
        // `NOT ASSESSED` — the guard failed against correct code.
        expect(RegExp(r'low\s*risk', caseSensitive: false).hasMatch(def), isFalse,
            reason: 'the fallback must not claim a low assessment:\n$def');
        expect(RegExp(r'not\s*assessed', caseSensitive: false).hasMatch(def), isTrue,
            reason: 'the fallback must say the assessment is absent:\n$def');
      }
    });

    test('the scan can actually see a violating switch', () {
      const bad = '''
        switch (riskLevel) {
          case 'high': color = _red; label = 'HIGH RISK'; break;
          default: color = _green; label = 'LOW RISK'; break;
        }''';
      expect(riskSwitches(bad), hasLength(1));
      expect(RegExp(r"""case\s+['"]low['"]""").hasMatch(riskSwitches(bad).single),
          isFalse);
    });
  });
}
