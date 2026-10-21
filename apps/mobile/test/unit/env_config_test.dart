// ENV-001 … ENV-006 — build-time environment configuration.
//
// Which backend a build talks to is fixed by `--dart-define` values. Those
// can't be varied inside a single test run, so these tests drive the pure
// resolver (`resolveEnvConfig`) directly with the values a build would supply.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/core/config/app_env.dart';


/// Resolves an environment without inheriting this build's `--dart-define`
/// values, so these assertions describe the baked-in defaults no matter which
/// define file the suite is run with.
EnvConfig resolveDefaults(String appEnv, {bool isReleaseBuild = false}) =>
    resolveEnvConfig(
      appEnv: appEnv,
      supabaseUrl: '',
      supabaseAnonKey: '',
      stripePublishableKey: '',
      // Pinned rather than inherited: the release rule is a behaviour under
      // test below, not an ambient property of whoever ran the suite.
      isReleaseBuild: isReleaseBuild,
    );

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

void main() {
  // ENV-001 — every supported environment is selectable
  group('ENV-001 environment selection', () {
    test('dev, qa and prod are all resolvable', () {
      expect(resolveDefaults('dev').environment, AppEnvironment.dev);
      expect(resolveDefaults('qa').environment, AppEnvironment.qa);
      expect(resolveDefaults('prod').environment, AppEnvironment.prod);
    });

    test('selection is case- and whitespace-insensitive', () {
      expect(resolveDefaults(' QA ').environment, AppEnvironment.qa);
      expect(resolveDefaults('Prod').environment, AppEnvironment.prod);
    });

    test('long-form aliases resolve to the same environments', () {
      expect(resolveDefaults('development').environment,
          AppEnvironment.dev);
      expect(resolveDefaults('staging').environment, AppEnvironment.qa);
      expect(resolveDefaults('production').environment,
          AppEnvironment.prod);
    });

    test('an unknown environment fails the build rather than defaulting', () {
      expect(() => resolveDefaults('prd'), throwsArgumentError);
      expect(() => resolveDefaults('production-qa'), throwsArgumentError);
      // A typo must never be absorbed into the safe default: 'prd' is somebody
      // meaning something, and guessing which is how builds ship wrong.
    });

    // ENV-4 (inverted). This test previously read "APP_ENV defaults to prod
    // when no define file is used" and asserted exactly that. The default was
    // the P0: `flutter run`, `flutter test` and every IDE launch that omitted
    // --dart-define-from-file resolved to the production project. The default
    // is now dev, and this test asserts the inversion.
    test('an absent APP_ENV resolves to dev, never to prod', () {
      expect(kDefaultEnvironment, AppEnvironment.dev);
      expect(resolveDefaults('').environment, AppEnvironment.dev);
      expect(resolveDefaults('   ').environment, AppEnvironment.dev);
      expect(resolveDefaults('').environment, isNot(AppEnvironment.prod));
      // And whatever this build did select must be a valid environment.
      expect(
        kAppEnvDefine.isEmpty ? 'dev' : kAppEnvDefine,
        anyOf('dev', 'qa', 'prod', 'development', 'staging', 'production'),
      );
    });

    test('an absent APP_ENV is a hard failure in a release build', () {
      // A debug run may omit the environment and get dev. A shipping binary may
      // not: "which backend is this?" is not a question a release build gets to
      // answer by default, in either direction.
      expect(() => resolveDefaults('', isReleaseBuild: true),
          throwsA(isA<StateError>()));
      // Naming it explicitly is always fine, release or not.
      expect(resolveDefaults('qa', isReleaseBuild: true).environment,
          AppEnvironment.qa);
      expect(resolveDefaults('prod', isReleaseBuild: true).environment,
          AppEnvironment.prod);
    });
  });

  // ENV-002 — defines override the per-environment defaults
  group('ENV-002 dart-define overrides', () {
    test('every setting can be supplied at build time', () {
      final config = resolveEnvConfig(
        appEnv: 'qa',
        supabaseUrl: 'https://qa-ref.supabase.co',
        supabaseAnonKey: 'qa-anon-key',
        stripePublishableKey: 'pk_test_qa',
      );

      expect(config.environment, AppEnvironment.qa);
      expect(config.supabaseUrl, 'https://qa-ref.supabase.co');
      expect(config.supabaseAnonKey, 'qa-anon-key');
      expect(config.stripePublishableKey, 'pk_test_qa');
      expect(config.missingSettings(), isEmpty);
    });

    test('an override wins over the environment default', () {
      final config = resolveEnvConfig(
        appEnv: 'prod',
        supabaseUrl: 'https://override.supabase.co',
        supabaseAnonKey: '',
        stripePublishableKey: '',
      );
      expect(config.supabaseUrl, 'https://override.supabase.co');
      // Untouched settings still come from the prod defaults.
      expect(config.supabaseAnonKey,
          kEnvironmentDefaults[AppEnvironment.prod]!.supabaseAnonKey);
    });

    test('an empty override falls back to the environment default', () {
      final config = resolveDefaults('prod');
      expect(config.supabaseUrl,
          kEnvironmentDefaults[AppEnvironment.prod]!.supabaseUrl);
    });
  });

  // ENV-003 — QA is isolated from production by construction
  group('ENV-003 environment isolation', () {
    // ENV-4: this is now the whole-table property, not a qa-only one. No
    // environment — prod included — can fall through to a backend, because no
    // environment carries one. `isNot(prod.supabaseUrl)` used to carry this
    // test; it would now pass vacuously, since both sides are empty.
    test('NO environment ships a backend default, so none can fall through',
        () {
      for (final env in AppEnvironment.values) {
        final resolved = resolveDefaults(env.label);
        expect(resolved.supabaseUrl, isEmpty, reason: env.label);
        expect(resolved.supabaseAnonKey, isEmpty, reason: env.label);
        expect(resolved.stripePublishableKey, isEmpty, reason: env.label);
        expect(resolved.canInitialiseSupabase, isFalse, reason: env.label);
      }
    });

    test('the binary contains no project ref of any kind', () {
      // The direct statement of ENV-4: the compiled default table cannot name
      // a project, so an un-configured build has nothing to connect to.
      //
      // Comment lines are stripped first. The doc block legitimately shows a
      // `https://YOUR_QA_REF.supabase.co` / `pk_test_...` usage example, and a
      // scan that cannot tell an example from a constant is a scan that gets
      // silenced the first time it fires.
      final code = File('${_mobileRoot().path}/lib/core/config/app_env.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      expect(code, isNot(contains('nxdbooufqzkpslkcogxc')),
          reason: 'the production ref is back in the binary');
      expect(code, isNot(contains('eyqtldjqpgpljlqvpowh')),
          reason: 'the QA ref is baked into the binary');
      expect(code, isNot(contains('.supabase.co')));
      expect(code, isNot(contains('pk_test_')));
      expect(code, isNot(contains('pk_live_')));
      expect(RegExp(r'eyJ[A-Za-z0-9_-]{20,}').hasMatch(code), isFalse,
          reason: 'a JWT is baked into app_env.dart');
      // The three deleted constants, by name.
      for (final gone in const [
        '_prodSupabaseUrl',
        '_prodSupabaseAnonKey',
        '_prodStripePublishableKey',
      ]) {
        expect(code, isNot(contains(gone)), reason: '$gone is back');
      }
    });

    test('a configured qa build points at its own project', () {
      final qa = resolveEnvConfig(
        appEnv: 'qa',
        supabaseUrl: 'https://qa-ref.supabase.co',
        supabaseAnonKey: 'qa-anon-key',
        isReleaseBuild: false,
      );
      // Compared against the committed production define file rather than the
      // resolver: prod's baked-in values are gone, so `resolveDefaults('prod')`
      // is now empty and any `isNot` against it would pass for free.
      final prodFile = _defines('prod');

      expect(qa.canInitialiseSupabase, isTrue);
      expect(qa.supabaseUrl, isNot(prodFile['SUPABASE_URL']));
      expect(qa.supabaseAnonKey, isNot(prodFile['SUPABASE_ANON_KEY']));
    });

    test('an unconfigured build reports exactly what is missing', () {
      expect(
        resolveDefaults('qa').missingSettings(),
        containsAll(['SUPABASE_URL', 'SUPABASE_ANON_KEY']),
      );
      expect(
        resolveEnvConfig(
          appEnv: 'qa',
          supabaseUrl: 'https://qa-ref.supabase.co',
          supabaseAnonKey: 'qa-anon-key',
          ).missingSettings(),
        isEmpty,
      );
    });
  });

  // ENV-004 (inverted) — the production project moved OUT of the binary.
  //
  // This group used to be "prod defaults are unchanged" and asserted that
  // `resolveDefaults('prod').supabaseUrl` equalled the production URL — i.e. it
  // certified the baked-in constants that made ENV-4 reachable. The production
  // project now lives only in `dart_defines/prod.json`, and these tests assert
  // that it is there, is intact, and is nowhere else.
  group('ENV-004 production configuration lives in prod.json, not the binary',
      () {
    test('prod.json carries the project the app shipped with', () {
      final d = _defines('prod');
      expect(d['APP_ENV'], 'prod');
      expect(d['SUPABASE_URL'], 'https://nxdbooufqzkpslkcogxc.supabase.co');
      expect(d['SUPABASE_ANON_KEY'], startsWith('eyJ'));
    });

    test('resolving prod.json reproduces the pre-ENV-4 configuration exactly',
        () {
      // The behavioural half: the values did not merely move, they still
      // resolve to the same config a production build had before.
      final d = _defines('prod');
      final prod = resolveEnvConfig(
        appEnv: d['APP_ENV']!,
        supabaseUrl: d['SUPABASE_URL']!,
        supabaseAnonKey: d['SUPABASE_ANON_KEY']!,
        stripePublishableKey: d['STRIPE_PK']!,
        isReleaseBuild: true,
      );
      expect(prod.environment, AppEnvironment.prod);
      expect(prod.supabaseUrl, 'https://nxdbooufqzkpslkcogxc.supabase.co');
      expect(prod.canInitialiseSupabase, isTrue);
      expect(prod.hasStripeKey, isTrue);
      expect(prod.stripePublishableKey, startsWith('pk_'));
    });

    test('a prod build with no define file cannot resolve a backend', () {
      // The inversion, stated directly. Before ENV-4 this was the *supported*
      // path and it reached production.
      final bare = resolveDefaults('prod');
      expect(bare.canInitialiseSupabase, isFalse);
      expect(bare.missingSettings(),
          containsAll(['SUPABASE_URL', 'SUPABASE_ANON_KEY']));
    });

    // ── K-26 · recorded, not resolved ────────────────────────────────────────
    // The production slot holds a *test-mode* Stripe key. Either no real money
    // has ever moved through this app, or the value is wrong. Which one is a
    // billing decision (D-1), not something this task may answer, so the fact
    // is pinned here so it cannot drift silently while the decision is open.
    test('K-26 the production Stripe key is still test-mode (decision D-1)',
        () {
      final pk = _defines('prod')['STRIPE_PK']!;
      expect(pk, startsWith('pk_test_'),
          reason: 'K-26/D-1: if this now fails because the key is pk_live_, '
              'the decision has landed — update this test to assert pk_live_ '
              'and close K-26. Do not delete the assertion.');
    });

    test('no environment ships a Stripe secret key', () {
      for (final env in AppEnvironment.values) {
        final d = _defines(env.label);
        for (final entry in d.entries) {
          expect(entry.value, isNot(startsWith('sk_')), reason: entry.key);
          expect(entry.value, isNot(startsWith('rk_')), reason: entry.key);
          expect(entry.value, isNot(startsWith('sb_secret_')), reason: entry.key);
          expect(entry.value, isNot(contains('sk-ant-')), reason: entry.key);
          expect(entry.value, isNot(contains('service_role')), reason: entry.key);
        }
        expect(resolveDefaults(env.label).stripePublishableKey, isEmpty);
      }
    });
  });

  // ENV-005 (API base URL) was REMOVED with apps/api: PD-A17 = A resolved as A2
  // (V5 §46-§55). The AI nutrition capability is a Supabase Edge Function, so there
  // is no second base URL to configure and nothing for this group to assert.

  // ENV-006 — the config surface carries no server secret
  group('ENV-006 no server secrets in client config', () {
    test('no resolved environment exposes an Anthropic key', () {
      for (final env in AppEnvironment.values) {
        final config = resolveDefaults(env.label);
        expect(config.toString(), isNot(contains('sk-ant')));
        for (final value in [
          config.supabaseUrl,
          config.supabaseAnonKey,
          config.stripePublishableKey,
        ]) {
          expect(value, isNot(contains('sk-ant')));
          expect(value, isNot(contains('anthropic')));
        }
      }
    });

    test('toString never prints a raw Stripe key beyond its presence', () {
      // Supplied explicitly: prod no longer carries a baked-in key, so a
      // resolveDefaults('prod') config would report '<unset>' and this test
      // would pass without ever exercising the redaction it exists to check.
      final prod = resolveEnvConfig(
        appEnv: 'prod',
        stripePublishableKey: 'pk_test_redaction_probe_0000',
        isReleaseBuild: false,
      );
      expect(prod.hasStripeKey, isTrue);
      expect(prod.toString(), contains('stripe: configured'));
      expect(prod.toString(), isNot(contains(prod.stripePublishableKey)));

      // And the unconfigured case says so rather than implying a key.
      expect(resolveDefaults('prod').toString(), contains('stripe: <unset>'));
    });
  });
}
