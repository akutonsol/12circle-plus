// ENV-010 … ENV-012 — QA/production Supabase isolation.
//
// Guards the boundary between the two Supabase projects:
//   production  12Circle Fitness  nxdbooufqzkpslkcogxc
//   QA          12Circle QA       eyqtldjqpgpljlqvpowh
//
// Two things are checked. First, the committed `dart_defines/*.json` files name
// the project they claim to. Second, whatever this binary was actually compiled
// with is internally consistent — so running
//   flutter test --dart-define-from-file=dart_defines/qa.json
// proves the real --dart-define pipeline resolves to QA, and the default run
// (no defines) proves it resolves to DEV and can reach no project at all.
//
// ENV-4 — INVERTED 2026-08-24. That last clause used to read "and the default
// run (no defines) proves it resolves to production", and ENV-012 below
// asserted it. The guard was pointed at the defect: it would have failed if
// anyone had made the default safe. The default is now dev, no environment
// carries a baked-in project, and ENV-012 asserts the inversion.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/core/config/app_env.dart';

const prodRef = 'nxdbooufqzkpslkcogxc';
const qaRef = 'eyqtldjqpgpljlqvpowh';

/// Project ref each environment must resolve to. dev has no project yet.
const refForEnvironment = <AppEnvironment, String?>{
  AppEnvironment.prod: prodRef,
  AppEnvironment.qa: qaRef,
  AppEnvironment.dev: null,
};

Directory _mobileRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) fail('Could not locate the Flutter package root');
    dir = parent;
  }
  return dir;
}

Map<String, String> _defines(String env) {
  final file = File('${_mobileRoot().path}/dart_defines/$env.json');
  expect(file.existsSync(), isTrue, reason: 'dart_defines/$env.json should exist');
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return raw.map((k, v) => MapEntry(k, v?.toString() ?? ''));
}

/// Reads the `ref` claim out of a Supabase anon/publishable JWT.
String? _refFromKey(String key) {
  final parts = key.split('.');
  if (parts.length != 3) return null;
  var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
  payload = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
  try {
    final claims = jsonDecode(utf8.decode(base64.decode(payload))) as Map;
    return claims['ref']?.toString();
  } catch (_) {
    return null;
  }
}

void main() {
  // ── ENV-010 — the committed QA define file points at the QA project ────────
  group('ENV-010 dart_defines/qa.json targets 12Circle QA', () {
    test('declares the qa environment', () {
      expect(_defines('qa')['APP_ENV'], 'qa');
    });

    test('URL is the QA project and not production', () {
      final url = _defines('qa')['SUPABASE_URL']!;
      expect(url, 'https://$qaRef.supabase.co');
      expect(url, contains(qaRef));
      expect(url, isNot(contains(prodRef)),
          reason: 'a QA build must never point at production');
    });

    test('anon key is issued for the QA project', () {
      final key = _defines('qa')['SUPABASE_ANON_KEY']!;
      expect(key, isNotEmpty);
      // The key carries its own project ref — a production key pasted here
      // would be caught even though the URL looked right.
      expect(_refFromKey(key), qaRef);
      expect(_refFromKey(key), isNot(prodRef));
    });

    test('carries no secret key of any kind', () {
      final d = _defines('qa');
      for (final entry in d.entries) {
        expect(entry.value, isNot(startsWith('sk_')), reason: entry.key);
        expect(entry.value, isNot(startsWith('sb_secret_')), reason: entry.key);
        expect(entry.value, isNot(contains('service_role')), reason: entry.key);
        expect(entry.value, isNot(contains('sk-ant-')), reason: entry.key);
      }
    });
  });

  // ── ENV-011 — resolving the QA defines yields QA, never production ────────
  group('ENV-011 APP_ENV=qa resolves exclusively to 12Circle QA', () {
    test('resolved config is the QA project', () {
      final d = _defines('qa');
      final config = resolveEnvConfig(
        appEnv: d['APP_ENV']!,
        supabaseUrl: d['SUPABASE_URL']!,
        supabaseAnonKey: d['SUPABASE_ANON_KEY']!,
        stripePublishableKey: d['STRIPE_PK']!,
      );

      expect(config.environment, AppEnvironment.qa);
      expect(config.supabaseUrl, contains(qaRef));
      expect(config.supabaseAnonKey, isNot(contains(prodRef)));
      expect(_refFromKey(config.supabaseAnonKey), qaRef);
      expect(config.canInitialiseSupabase, isTrue);
    });

    test('shares no backend value with the committed production project', () {
      final d = _defines('qa');
      final qa = resolveEnvConfig(
        appEnv: 'qa',
        supabaseUrl: d['SUPABASE_URL']!,
        supabaseAnonKey: d['SUPABASE_ANON_KEY']!,
      );
      // Compared against `dart_defines/prod.json`, not against
      // `kEnvironmentDefaults[prod]`. ENV-4 emptied the baked-in table, so the
      // old comparison — which read the constants — now compares QA against
      // '' and passes for free. The define file is where production lives now,
      // and it is the thing a QA build must share nothing with.
      final prodFile = File('${_mobileRoot().path}/dart_defines/prod.json');
      expect(prodFile.existsSync(), isTrue);
      final prod = (jsonDecode(prodFile.readAsStringSync()) as Map)
          .map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));

      expect(prod['SUPABASE_URL'], contains(prodRef));
      expect(qa.supabaseUrl, isNot(prod['SUPABASE_URL']));
      expect(qa.supabaseAnonKey, isNot(prod['SUPABASE_ANON_KEY']));
      expect(qa.supabaseUrl, isNot(contains(prodRef)));
      expect(_refFromKey(qa.supabaseAnonKey), isNot(prodRef));
    });
  });

  // ── ENV-012 — the compiled binary never mixes projects, and an
  //             un-configured one names no project at all ──────────────────
  //
  // INVERTED (ENV-4). The consistency half below is unchanged and still sound.
  // What is new is the first test: the un-configured build used to be *expected*
  // to resolve to production, and this group documented that as the proof the
  // pipeline worked. It is now the thing that must not happen.
  group('ENV-012 this build resolves to exactly one project', () {
    test('an un-configured build resolves to dev and can reach nothing', () {
      // Drives the resolver with no defines at all, which is what a bare
      // `flutter run` / `flutter test` / IDE launch supplies. Independent of
      // how *this* suite was invoked, so it holds under
      // `--dart-define-from-file=dart_defines/qa.json` too.
      final bare = resolveEnvConfig(
        appEnv: '',
        supabaseUrl: '',
        supabaseAnonKey: '',
        stripePublishableKey: '',
        isReleaseBuild: false,
      );

      expect(bare.environment, AppEnvironment.dev,
          reason: 'ENV-4: an omitted APP_ENV must resolve to dev');
      expect(bare.isProduction, isFalse);
      expect(bare.supabaseUrl, isEmpty);
      expect(bare.supabaseAnonKey, isEmpty);
      expect(bare.canInitialiseSupabase, isFalse,
          reason: 'an un-configured build must not be able to open a session '
              'against any project');
      expect(bare.supabaseUrl, isNot(contains(prodRef)));
      expect(bare.supabaseUrl, isNot(contains(qaRef)));
    });

    test('an un-configured RELEASE build refuses to resolve at all', () {
      expect(
        () => resolveEnvConfig(
          appEnv: '',
          supabaseUrl: '',
          supabaseAnonKey: '',
          stripePublishableKey: '',
            isReleaseBuild: true,
        ),
        throwsA(isA<StateError>()),
        reason: 'a shipping binary must name its environment explicitly',
      );
    });

    test('no environment default names a project, so none can be inherited',
        () {
      for (final env in AppEnvironment.values) {
        final d = kEnvironmentDefaults[env]!;
        expect(d.supabaseUrl, isEmpty, reason: env.label);
        expect(d.supabaseAnonKey, isEmpty, reason: env.label);
        for (final ref in const [prodRef, qaRef]) {
          expect(d.supabaseUrl, isNot(contains(ref)), reason: env.label);
          expect(d.supabaseAnonKey, isNot(contains(ref)), reason: env.label);
        }
      }
    });

    test('AppEnv.current URL and key agree with its declared environment', () {
      final current = AppEnv.current;
      final expectedRef = refForEnvironment[current.environment];

      if (expectedRef == null || current.supabaseUrl.isEmpty) {
        // dev ships no project, and any environment built without its define
        // file now ships none either. Nothing to cross-check — but assert the
        // safe consequence rather than returning silently.
        expect(current.canInitialiseSupabase, isFalse);
        expect(current.supabaseUrl, isNot(contains(prodRef)));
        return;
      }

      expect(current.supabaseUrl, contains(expectedRef),
          reason: 'URL must belong to ${current.environment.label}');
      expect(_refFromKey(current.supabaseAnonKey), expectedRef,
          reason: 'anon key must be issued for ${current.environment.label}');

      // And crucially, nothing from any other environment leaked in.
      for (final entry in refForEnvironment.entries) {
        final otherRef = entry.value;
        if (otherRef == null || otherRef == expectedRef) continue;
        expect(current.supabaseUrl, isNot(contains(otherRef)));
        expect(current.supabaseAnonKey, isNot(contains(otherRef)));
      }
    });
  });
}
