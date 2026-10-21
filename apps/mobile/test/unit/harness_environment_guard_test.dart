// ENV-020 … ENV-022 — production-contact hygiene in the TEST HARNESSES
// (Workstream N).
//
// `qa_environment_isolation_test.dart` proves that a BUILD of the app resolves
// to exactly one project, and since ENV-4 that an un-configured build resolves
// to none. That guard is sound and this file does not duplicate it.
//
// It covers the other way the tree can reach a Supabase project: the
// write-capable harnesses under `tool/` and `integration_test/`, which are run
// by hand, are named for QA, and do not go through `AppEnv` at all.
//
// ── CLOSED 2026-08-24 (ENV-5 / ENV-4) ────────────────────────────────────────
//
// Every one of them used to resolve to PRODUCTION:
//
//   tool/live_integration_test.dart   hardcoded the prod ref; POST/PATCH/DELETE
//                                     on workout_sessions, nutrition_logs,
//                                     daily_scores, weekly_checkins, posts
//   tool/qa_self_guided.dart          hardcoded the prod ref; PATCHed
//                                     user_profiles, called generate_client_plan
//   tool/qa_entitlements.dart         hardcoded the prod ref; service-role
//                                     DELETEs on subscriptions and
//                                     coach_client_relationships
//   integration_test/service_logic_test.dart
//                                     resolved through AppConstants -> AppEnv,
//                                     which DEFAULTED TO PROD, and its own run
//                                     instructions pass no --dart-define-from-file
//
// The three `tool/` harnesses now resolve through `tool/qa_target.dart`, which
// takes QA_URL/QA_ANON with no default and positively identifies the QA project
// before returning. `service_logic_test.dart` still inherits `AppEnv`, but
// `AppEnv` no longer has a production default to inherit — an un-configured run
// resolves to dev, reaches nothing, and fails closed at `Supabase.initialize`.
//
// These guards now assert the ABSENCE of the contamination rather than
// recording it. The allowlist is empty and must stay empty: a NEW write-capable
// harness aimed at production fails immediately, and so does an old one that
// regresses.
//
// Nothing in this file contacts any Supabase project. It reads committed source.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const prodRef = 'nxdbooufqzkpslkcogxc';
const qaRef = 'eyqtldjqpgpljlqvpowh';

Directory _mobileRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate the Flutter package root');
    }
    dir = parent;
  }
  return dir;
}

Iterable<File> _dartFilesUnder(String relative) sync* {
  final dir = Directory('${_mobileRoot().path}/$relative');
  if (!dir.existsSync()) return;
  for (final e in dir.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

String _relative(File f) => f.path.split('/apps/mobile/').last;

/// A harness that can change server state, as opposed to one that only reads.
final _writeVerb = RegExp(
    r"'(POST|PATCH|PUT|DELETE)'|\.insert\(|\.upsert\(|\.update\(|\.delete\(");

void main() {
  // ── ENV-020 · the harnesses that name a project directly ──────────────────
  group('ENV-020 no harness hardcodes the production project', () {
    // ENV-5, closed. This set held all three `tool/` harnesses; each hardcoded
    // the production ref AND wrote. It is now EMPTY and must stay empty.
    // Adding an entry to silence a failure re-opens a P0 — repoint the harness
    // instead.
    const knownProdTargeted = <String>{};

    /// The one file allowed to name production: the shared refusal guard, which
    /// names it in order to reject it.
    const guardFile = 'tool/qa_target.dart';

    test('no harness under tool/ or integration_test/ names production', () {
      final hits = <String>{};
      for (final relative in ['tool', 'integration_test']) {
        for (final f in _dartFilesUnder(relative)) {
          if (_relative(f) == guardFile) continue;
          if (f.readAsStringSync().contains(prodRef)) hits.add(_relative(f));
        }
      }
      printOnFailure(hits.join('\n'));

      expect(hits.difference(knownProdTargeted), isEmpty,
          reason: 'a harness under tool/ or integration_test/ names the '
              'PRODUCTION project. These are run by hand against real accounts '
              'and they write. Resolve the target through '
              'tool/qa_target.dart, which takes QA_URL/QA_ANON with no '
              'default.');

      expect(knownProdTargeted, isEmpty,
          reason: 'the ENV-5 allowlist must stay empty');
    });

    test('the guard names production only in order to refuse it', () {
      final src = File('${_mobileRoot().path}/$guardFile').readAsStringSync();
      // It must know the ref...
      expect(src, contains(prodRef));
      // ...and the only executable thing it does with it is refuse.
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, contains('kProductionRef'));
      expect(code, contains('_refuse'));
      expect(RegExp(r'https://' + prodRef).hasMatch(code), isFalse,
          reason: 'the guard must hold the bare ref, never a usable prod URL');
    });

    test('every write-capable tool/ harness resolves through the guard', () {
      // The property that actually matters: not "does it mention production"
      // but "does it get its target from the one place that verifies it".
      final checked = <String>[];
      for (final f in _dartFilesUnder('tool')) {
        final rel = _relative(f);
        if (rel == guardFile) continue;
        final src = f.readAsStringSync();
        if (!_writeVerb.hasMatch(src)) continue;
        checked.add(rel);

        expect(src, contains("import 'qa_target.dart';"),
            reason: '$rel writes to a Supabase project but does not import '
                'the target guard');
        expect(src, contains('resolveQaTarget()'),
            reason: '$rel imports the guard but never calls it');
        expect(RegExp(r"""const\s+_url\s*=""").hasMatch(src), isFalse,
            reason: '$rel has a compile-time target again');
      }
      expect(checked, containsAll(<String>[
        'tool/live_integration_test.dart',
        'tool/qa_self_guided.dart',
        'tool/qa_entitlements.dart',
      ]), reason: 'the three known write-capable harnesses must be covered; '
          'if one is now read-only, say so here rather than dropping it');
    });

    test('the guard refuses by allowlist, not merely by blocklist', () {
      // "is not production" is a weaker claim than "is QA", and only the
      // second one is safe to write against. A future third project, a typo'd
      // ref, or a colleague's fork must all be refused too.
      final src = File('${_mobileRoot().path}/$guardFile').readAsStringSync();
      expect(src, contains('kQaRef'));
      expect(src, contains(qaRef));
      expect(src, contains('QA_URL'));
      expect(src, contains('QA_ANON'));
      // No default target of any kind.
      expect(RegExp(r"QA_URL'\]\s*\?\?\s*'https").hasMatch(src), isFalse,
          reason: 'the guard supplies a default target');
    });

    test('no harness carries a service_role key in source', () {
      // A hardcoded ref is a contamination risk; a hardcoded service-role key
      // would be an unbounded one. This is the line that must never be crossed.
      for (final relative in ['tool', 'integration_test']) {
        for (final f in _dartFilesUnder(relative)) {
          final src = f.readAsStringSync();
          expect(src.contains('"role":"service_role"'), isFalse,
              reason: '${_relative(f)} embeds a service-role JWT');
          expect(RegExp(r'service_role_key\s*=\s*.[A-Za-z0-9]').hasMatch(src),
              isFalse,
              reason: '${_relative(f)} embeds a service-role key');
        }
      }
    });
  });

  // ── ENV-021 · the harness that inherits the app's default ─────────────────
  group('ENV-021 the in-app integration harness inherits a SAFE default', () {
    late final String src = File(
            '${_mobileRoot().path}/integration_test/service_logic_test.dart')
        .readAsStringSync();

    test('it resolves its project through AppEnv, not a literal', () {
      expect(src, contains('AppConstants.supabaseUrl'));
      expect(src.contains(prodRef), isFalse);
      expect(src.contains(qaRef), isFalse);
    });

    // INVERTED (ENV-4). This test used to read "DEFECT: it writes, and AppEnv
    // defaults to prod, so the documented invocation targets production", and
    // asserted that composition held. Half of it — the prod default — is gone,
    // so the composition cannot occur. What is asserted now is the property
    // that replaced it: this harness writes, so if it is run without being told
    // where to point, it must reach nothing rather than reaching production.
    test('it writes, so its un-configured run must fail closed', () {
      expect(_writeVerb.hasMatch(src), isTrue,
          reason: 'if this is now read-only the finding is closed for a '
              'different reason — say so here');

      // The safety now comes from AppEnv itself, which is what this asserts:
      // no baked-in project for any environment, so AppConstants.supabaseUrl
      // is empty unless a define file supplied one, and Supabase.initialize
      // fails rather than silently connecting.
      final appEnv = File('${_mobileRoot().path}/lib/core/config/app_env.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(appEnv, isNot(contains(prodRef)),
          reason: 'ENV-4 regressed: the production project is baked into '
              'AppEnv again, which re-arms this harness');
      expect(appEnv, isNot(contains('.supabase.co')));
      expect(appEnv, contains('kDefaultEnvironment = AppEnvironment.dev'),
          reason: 'ENV-4 regressed: an omitted APP_ENV no longer resolves to '
              'dev');
    });

    test('it signs in as a shared seeded account, so a failed teardown is '
        'visible to other testers', () {
      expect(src, contains('test@12circle.app'));
    });
  });

  // ── ENV-022 · the QA project is never named by the shipped app ────────────
  group('ENV-022 QA and production stay separated in the committed tree', () {
    test('lib/ names neither project — the app has no baked-in target', () {
      // This used to allow exactly one file, `lib/core/config/app_env.dart`,
      // on the grounds that knowing both refs was its job. ENV-4 removed that
      // job: every project now lives in `dart_defines/*.json` and reaches the
      // binary only through --dart-define. So the allowance is gone and the
      // expected set is empty.
      final naming = <String>[];
      for (final f in _dartFilesUnder('lib')) {
        final src = f.readAsStringSync();
        if (src.contains(prodRef) || src.contains(qaRef)) naming.add(_relative(f));
      }
      printOnFailure(naming.join('\n'));
      expect(naming, isEmpty,
          reason: 'no file under lib/ may name a Supabase project; the target '
              'is a build-time define');
    });

    test('each define file names exactly one project, and the right one', () {
      const expected = <String, String?>{
        'dev': null,
        'qa': qaRef,
        'prod': prodRef,
      };
      expected.forEach((env, ref) {
        final f = File('${_mobileRoot().path}/dart_defines/$env.json');
        expect(f.existsSync(), isTrue, reason: '$env.json is missing');
        final src = f.readAsStringSync();
        for (final other in const [prodRef, qaRef]) {
          if (other == ref) continue;
          expect(src.contains(other), isFalse,
              reason: '$env.json names the wrong project ($other)');
        }
        if (ref != null) {
          expect(src, contains(ref), reason: '$env.json should name $ref');
        }
      });
    });

    test('the keep-alive workflow pings production and writes nothing', () {
      // The only automated job in the repo that touches a real project. It is
      // read-only by construction; that is what makes it safe to run daily.
      var dir = _mobileRoot();
      while (!Directory('${dir.path}/.github').existsSync()) {
        dir = dir.parent;
      }
      final wf = File('${dir.path}/.github/workflows/supabase-keepalive.yml');
      expect(wf.existsSync(), isTrue);
      final src = wf.readAsStringSync();
      expect(src, contains(prodRef));
      expect(RegExp(r'-X\s+(POST|PATCH|PUT|DELETE)').hasMatch(src), isFalse,
          reason: 'the keep-alive must stay a read-only GET');
      expect(src.contains('service_role'), isFalse);
    });
  });
}
