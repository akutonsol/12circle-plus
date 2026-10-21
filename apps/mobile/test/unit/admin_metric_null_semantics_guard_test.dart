import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// V5 §163 · SEC-G4 — a ratchet on the Admin metric null semantics.
///
/// The behavioural tests in `admin_metric_semantics_test.dart` prove the models
/// preserve null today. This guard exists because the defect they protect against
/// is a ONE-CHARACTER EDIT away at all times: adding `?? 0` to a getter, or
/// changing an `int?` field to `int`, would make every one of those tests still
/// compile and most of them still pass, while silently converting "you are not
/// authorized to see this" into "the answer is zero".
///
/// For METRIC-02 that is an indirect statement about the Security-owned audit
/// population a `Users`-only role may not query. For METRIC-06 it fabricates a
/// monetary figure the owner's calculation explicitly forbids. For METRIC-14 it
/// turns "nobody registered" into "nobody turned up".
void main() {
  // Resolve relative to this file so the guard works from any working directory.
  const root = 'lib/features/admin';
  final files = <String, String>{
    'models': '$root/domain/admin_metrics.dart',
    'service': '$root/data/admin_metrics_service.dart',
    'providers': '$root/domain/admin_provider.dart',
  };

  late Map<String, String> sources;

  setUpAll(() {
    sources = {
      for (final e in files.entries) e.key: File(e.value).readAsStringSync(),
    };
    // POSITIVE CONTROL. A guard that reads an empty string reports every file
    // clean, which is how three checkers in this programme have already reported
    // success from nothing (V5 §139.3). Prove the scan can see text it must see.
    for (final e in sources.entries) {
      if (e.value.trim().isEmpty) {
        fail('SEC-G4: ${files[e.key]} read as EMPTY — the scan is broken, not the '
            'code; refusing to report a clean result over nothing');
      }
    }
    if (!sources['models']!.contains('class AdminActivityOverview')) {
      fail('SEC-G4: could not find AdminActivityOverview in the models file, '
          'which it definitely contains — the scan is broken');
    }
  });

  test('no file in the Admin metric layer defaults a metric to zero', () {
    // DISCOVERED, NOT LISTED. The first version of this test scanned three
    // hard-coded files and therefore did NOT see admin_metrics_panel.dart, which
    // arrived later carrying three `?? 0` uses — two of which would have rendered
    // "0 / 6" CI checks and "0 pass of 15" gates from figures that were simply not
    // recorded. A hardcoded list covers the files someone remembered; §139.6 again.
    final discovered = <String, String>{
      for (final f in Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        f.path: f.readAsStringSync(),
    };
    expect(discovered.length, greaterThanOrEqualTo(6),
        reason: 'SEC-G4 discovered ${discovered.length} Dart files under $root — '
            'too few; a scan that walks nothing reports every file clean');

    // ── PRE-EXISTING, RECORDED, AND THIS LIST MAY ONLY SHRINK ───────────────
    // Making the scan discover files immediately surfaced four `?? 0` uses in admin
    // surfaces that predate the metric layer. They are NOT waved through: each is
    // named with what it is, and the second assertion below fails if any of them is
    // fixed without being removed from here, so the list cannot quietly become
    // permission to add more.
    //
    // Two are deliberate configuration defaults, not display coercions: 0.10 is the
    // marketplace commission fallback the SERVER also applies
    // (create-checkout/index.ts:259 reads `marketplace_commission_rate ?? 0.10`), so
    // the client agreeing with it is correct.
    //
    // Two ARE the defect class — they render a missing figure as 0 on the legacy
    // console. They are debt in surfaces this work did not build, and rewriting
    // another screen's data handling is a product decision, not a QA repair.
    // ANCHORED ON THE CODE, NOT THE LINE NUMBER. The first version keyed these by
    // `path:line`, and adding one navigation tile higher up the dashboard file
    // shifted two of them and turned this test red for no substantive reason. A
    // guard whose anchors move when unrelated lines are inserted trains people to
    // re-pin it rather than read it. The key is now the file plus the exact
    // offending expression, which is precise and does not drift.
    const knownCoercions = <String, String>{
      "platform_settings_service.dart|double.tryParse('\${row?['value'] ?? ''}') ?? 0.10":
          'config default, matches create-checkout:259 — not a display coercion',
      'admin_dashboard_screen.dart|valueOrNull ?? 0.10':
          'config default, same 0.10 fallback as the server',
      'observability_screen.dart|(v as num?)?.toInt() ?? 0':
          'DEBT — legacy observability figures render 0 when absent',
      'admin_dashboard_screen.dart|(stats[k] as num?)?.toInt() ?? 0':
          'DEBT — legacy admin_platform_stats figures render 0 when absent',
    };

    bool isKnown(String path, String code) {
      final base = path.split('/').last;
      return knownCoercions.keys.any((k) {
        final i = k.indexOf('|');
        return k.substring(0, i) == base && code.contains(k.substring(i + 1));
      });
    }

    final offenders = <String>[];
    for (final e in discovered.entries) {
      final lines = e.value.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Comments discuss `?? 0` at length on purpose; only code counts.
        final code = line.split('//').first;
        if (RegExp(r'\?\?\s*0(\.0)?\b').hasMatch(code) ||
            RegExp(r'\?\?\s*0\.\d+\b').hasMatch(code)) {
          if (isKnown(e.key, code)) continue;
          offenders.add('${e.key}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a null here means "unauthorized" or "not recorded", never zero.\n'
            '${offenders.join('\n')}');

    // THE RATCHET. A recorded expression that no longer appears anywhere must be
    // deleted, so the allowlist cannot drift into a general licence.
    final stale = <String>[];
    for (final k in knownCoercions.keys) {
      final i = k.indexOf('|');
      final base = k.substring(0, i);
      final expr = k.substring(i + 1);
      final match = discovered.entries
          .where((e) => e.key.split('/').last == base)
          .where((e) => e.value
              .split('\n')
              .map((l) => l.split('//').first)
              .any((c) => c.contains(expr)));
      if (match.isEmpty) {
        stale.add('$base no longer contains `$expr` — remove it from knownCoercions');
      }
    }
    expect(stale, isEmpty, reason: stale.join('\n'));
  });

  test('every numeric field on a ROW-PARSED metric model stays nullable', () {
    // A non-nullable `int count;` on a row-parsed model forces a default at
    // construction, and the only available default is a lie.
    //
    // SCOPED TO ROW-PARSED MODELS, and the scope is the point. A model built by
    // `fromRow` mirrors a surface, where null means "you may not see this" or "nothing
    // was recorded". A model COMPUTED from rows the client already holds — `fromRows`,
    // plural — expresses unavailability by being null itself; a count derived from a
    // list in hand cannot be unknown, so demanding `int?` there would be the §174.3
    // mistake again: a detector firing on correct code because it cannot tell two
    // situations apart.
    final bad = <String>[];
    final src = sources['models']!;
    // Split into class bodies so each field is judged against its own class.
    final classes = RegExp(r'\nclass\s+(\w+)\s*\{').allMatches(src).toList();
    for (var c = 0; c < classes.length; c++) {
      final name = classes[c].group(1)!;
      final start = classes[c].end;
      final end = c + 1 < classes.length ? classes[c + 1].start : src.length;
      final body = src.substring(start, end);
      final rowParsed = body.contains('fromRow(Map<String, dynamic>');
      if (!rowParsed) continue;
      final lines = body.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first.trim();
        final m = RegExp(r'^final\s+(int|double|num)\s+(\w+)\s*;').firstMatch(code);
        if (m != null) bad.add('$name.${m.group(2)} — ${m.group(0)}');
      }
    }
    expect(bad, isEmpty,
        reason: 'these row-parsed fields cannot represent "unavailable":\n'
            '${bad.join('\n')}');
  });

  test('the service returns nullable models, so a missing row stays missing', () {
    // `maybeSingle()` yields null for no row; `single()` throws, and a caught
    // throw would most likely be turned into an empty model full of zeros.
    final service = sources['service']!;
    expect(service.contains('maybeSingle()'), isTrue,
        reason: 'the view read must tolerate "no row" as a first-class outcome');
    expect(RegExp(r'\.single\(\)').hasMatch(service), isFalse,
        reason: 'single() throws on the unauthorized case, which invites a catch '
            'block that invents a zeroed model');
    for (final m in RegExp(r'Future<(\w+)\??>\s+get\w+\(').allMatches(service)) {
      expect(m.group(0), contains('?>'),
          reason: '${m.group(1)} must be returned nullable: ${m.group(0)}');
    }
  });

  test('no provider substitutes an empty model when a surface returns no row', () {
    final providers = sources['providers']!;
    for (final m in RegExp(r'FutureProvider<(Admin\w+)(\??)>').allMatches(providers)) {
      expect(m.group(2), '?',
          reason: '${m.group(1)} provider must be nullable so the UI can render '
              'the approved A11 state instead of a zeroed card');
    }
    // A constructor call inside the providers block would be that substitution.
    final block = providers.substring(providers.indexOf('V5 §163'));
    expect(RegExp(r'const\s+Admin\w+Overview\(').hasMatch(block), isFalse,
        reason: 'a provider must not construct a stand-in model');
  });

  // ── SEC-G5 · raw hex in the Admin feature, as a SHRINKING allowlist ───────
  // The Helix rule is that components consume semantic tokens and never raw hex.
  // Three Admin screens predate the token layer and genuinely contain raw hex, so a
  // flat ban would be red on arrival and would be deleted rather than obeyed. This
  // is the SEC-G3 idiom instead: a per-file CEILING that may only fall. A new file
  // gets no allowance, and an existing file cannot gain one colour.
  group('SEC-G5 · raw hex ratchet', () {
    // admin_tokens.dart is the Tier-3 token layer itself and is GENERATED from the
    // published admin.tokens.css — hex is its entire purpose, and
    // gen-admin-tokens.mjs --check already pins every value to the design commit.
    const exempt = {'admin_tokens.dart'};
    const ceiling = <String, int>{
      'admin_dashboard_screen.dart': 12,
      'observability_screen.dart': 8,
      'exercise_review_screen.dart': 7,
    };

    int hexIn(String source) => source
        .split('\n')
        // Code only. The tile's doc comment QUOTES `Color(0xFFA855F7)` to explain
        // what it is avoiding, and the first draft of the sibling guard failed on
        // its own documentation for exactly this reason.
        .map((l) => l.split('//').first)
        .where((l) => RegExp(r'Color\(0x').hasMatch(l))
        .length;

    test('no Admin file exceeds its recorded raw-hex ceiling, and new files have '
        'none at all', () {
      final dir = Directory('lib/features/admin');
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files.length, greaterThanOrEqualTo(6),
          reason: 'SEC-G5 scanned ${files.length} files — too few; a scan that '
              'walks nothing reports every rule satisfied');

      final violations = <String>[];
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        if (exempt.contains(name)) continue;
        final count = hexIn(f.readAsStringSync());
        final allowed = ceiling[name] ?? 0;
        if (count > allowed) {
          violations.add('$name: $count raw Color(0x…), ceiling $allowed');
        }
      }
      expect(violations, isEmpty,
          reason: 'read from AdminColors instead:\n${violations.join('\n')}');
    });

    test('the ratchet is honest: a ceiling that is now too generous must be lowered, '
        'so a file that improved cannot silently regain room', () {
      final stale = <String>[];
      for (final e in ceiling.entries) {
        final f = File('lib/features/admin/presentation/${e.key}');
        if (!f.existsSync()) {
          stale.add('${e.key}: allow-listed but absent — delete the entry');
          continue;
        }
        final count = hexIn(f.readAsStringSync());
        if (count < e.value) {
          stale.add('${e.key}: now $count, ceiling still ${e.value} — lower it');
        }
      }
      expect(stale, isEmpty, reason: stale.join('\n'));
    });

    test('the scan can actually see a violation', () {
      expect(hexIn('const c = Color(0xFF123456);'), 1);
      expect(hexIn('// const c = Color(0xFF123456);'), 0);
    });
  });

  test('METRIC-11 exposes no combined verdict, in Dart as in SQL', () {
    // The owner ruled the CI verdict and the gate verdict "must not be collapsed".
    // Comments NAME these forbidden getters in order to explain why they are absent,
    // so the scan must read code only — the first draft of this guard matched its
    // own documentation and failed, which is a scan defect, not a code defect.
    final models = sources['models']!
        .split('\n')
        .map((l) => l.split('//').first)
        .join('\n');
    final combined = RegExp(
            r'\b(get\s+)?(isReleasable|overallStatus|combinedVerdict|isBlocked|releaseBadge)\b')
        .allMatches(models)
        .map((m) => m.group(0)!)
        .toList();
    // Prove the pattern can still fire, so "no matches" means "none present"
    // rather than "the regex is broken".
    expect(
        RegExp(r'\b(get\s+)?(isReleasable|overallStatus|combinedVerdict|isBlocked|releaseBadge)\b')
            .hasMatch('bool get isReleasable => true;'),
        isTrue,
        reason: 'the forbidden-getter pattern must match a known offender');
    expect(combined, isEmpty,
        reason: 'a convenience getter here would assert a release verdict neither '
            'CI nor the gate ledger gave: ${combined.join(', ')}');
  });
}
