/// Build-time environment configuration for the 12 Circle Flutter client.
///
/// Nothing here is environment-specific at *runtime*: every value is resolved
/// from `--dart-define` values baked in at compile time, so a QA build can
/// never accidentally talk to the production backend.
///
/// Select an environment with:
///   flutter build web --dart-define-from-file=dart_defines/qa.json
/// or pass the individual defines:
///   flutter run --dart-define=APP_ENV=qa \
///               --dart-define=SUPABASE_URL=https://YOUR_QA_REF.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=YOUR_QA_PUBLISHABLE_KEY \
///               --dart-define=STRIPE_PK=pk_test_... \
///
/// SECURITY: only client-safe values belong in this file. The Supabase
/// publishable/anon key and the Stripe *publishable* key are designed to be
/// shipped to clients (they are protected by RLS and by Stripe's key scoping).
/// Server secrets — the Anthropic API key above all — must never appear here;
/// the AI integration is reached through the NestJS API instead.
///
/// ENV-4: this file carries **no backend defaults for any environment**. It
/// used to bake the production URL, anon key and Stripe key in as the fallback
/// for an unset `APP_ENV`, which meant every `flutter run`, `flutter test` and
/// IDE launch that forgot `--dart-define-from-file` connected to production. An
/// omission, not a mistake, was all it took. Now:
///
///   * an absent `APP_ENV` resolves to **dev**, which can reach nothing;
///   * an absent `APP_ENV` in a **release** build is a hard failure;
///   * every project lives in `dart_defines/<env>.json`, never in the binary.
///
/// The consequence is deliberate: a build that was not told where to point does
/// not start. That is the intended failure mode.
library;

import 'package:flutter/foundation.dart' show kReleaseMode;

/// The environments the client can be built for.
enum AppEnvironment {
  dev,
  qa,
  prod;

  static AppEnvironment? tryParse(String value) {
    switch (value.trim().toLowerCase()) {
      case 'dev':
      case 'development':
        return AppEnvironment.dev;
      case 'qa':
      case 'staging':
        return AppEnvironment.qa;
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
    }
    return null;
  }

  String get label => name;
}

/// Immutable, fully-resolved configuration for one environment.
class EnvConfig {
  final AppEnvironment environment;
  final String supabaseUrl;

  /// Supabase publishable ("anon") key — client-safe, RLS-protected.
  final String supabaseAnonKey;

  /// Stripe *publishable* key — client-safe. Never the secret key.
  final String stripePublishableKey;

  const EnvConfig({
    required this.environment,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.stripePublishableKey,
  });

  bool get isProduction => environment == AppEnvironment.prod;
  bool get isQa => environment == AppEnvironment.qa;
  bool get isDev => environment == AppEnvironment.dev;

  /// True when Stripe.js can be initialised for in-app Embedded Checkout.
  /// When false the app falls back to hosted (redirect) checkout, exactly as
  /// it did before environments were introduced.
  bool get hasStripeKey => stripePublishableKey.isNotEmpty;

  /// Human-readable list of anything a build of this environment is missing.
  /// Empty means the build is fully configured.
  List<String> missingSettings() => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      ];

  /// Supabase can be initialised (Stripe/API are checked at point of use).
  bool get canInitialiseSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  @override
  String toString() =>
      'EnvConfig(${environment.label}, supabaseUrl: $supabaseUrl, '
      'stripe: ${hasStripeKey ? 'configured' : '<unset>'})';
}

// ── Per-environment defaults ─────────────────────────────────────────────────
//
// ENV-4 / K-26: no environment ships a backend default any more. The production
// URL, anon key and Stripe publishable key that used to live here as
// `_prodSupabaseUrl` / `_prodSupabaseAnonKey` / `_prodStripePublishableKey` now
// live in `dart_defines/prod.json` and reach the binary only when that file is
// passed. A build with no defines therefore resolves to an environment it
// cannot connect to, and `main()` refuses to start rather than falling through
// to real user data.
//

/// Per-environment defaults, overridable by the matching `--dart-define`.
const Map<AppEnvironment, EnvConfig> kEnvironmentDefaults = {
  AppEnvironment.dev: EnvConfig(
    environment: AppEnvironment.dev,
    supabaseUrl: '',
    supabaseAnonKey: '',
    stripePublishableKey: '',
  ),
  AppEnvironment.qa: EnvConfig(
    environment: AppEnvironment.qa,
    supabaseUrl: '',
    supabaseAnonKey: '',
    stripePublishableKey: '',
  ),
  AppEnvironment.prod: EnvConfig(
    environment: AppEnvironment.prod,
    supabaseUrl: '',
    supabaseAnonKey: '',
    stripePublishableKey: '',
  ),
};

// ── Compile-time defines ─────────────────────────────────────────────────────

/// Raw `APP_ENV` define. **Empty means "nobody said"** — deliberately not
/// defaulted here, so [resolveEnvConfig] can tell an absent value apart from an
/// explicit one and apply the release-build rule to the former.
const String kAppEnvDefine = String.fromEnvironment('APP_ENV');
const String kSupabaseUrlDefine = String.fromEnvironment('SUPABASE_URL');
const String kSupabaseAnonKeyDefine =
    String.fromEnvironment('SUPABASE_ANON_KEY');
const String kStripePkDefine = String.fromEnvironment('STRIPE_PK');

/// The environment an absent `APP_ENV` resolves to.
///
/// ENV-4: this used to be `prod`. It is `dev` because dev is the environment
/// that can reach nothing — the safe answer to "you didn't tell me".
const AppEnvironment kDefaultEnvironment = AppEnvironment.dev;

/// Resolves an [EnvConfig] from raw define values.
///
/// Pure and side-effect free so it can be exercised directly in tests with
/// arbitrary inputs — `--dart-define` values cannot be varied within a test
/// run. Precedence: an explicit define wins; otherwise the environment default.
///
/// Throws [ArgumentError] when [appEnv] is a non-empty value that is not one of
/// dev/qa/prod, so a typo in a build command fails the build rather than
/// silently selecting an environment nobody asked for.
///
/// Throws [StateError] when [appEnv] is **absent** and [isReleaseBuild] is
/// true. A debug or test run may omit `APP_ENV` and get [kDefaultEnvironment];
/// a shipping binary may not, because "which backend does this app talk to" is
/// not a question a release build is allowed to answer by default.
EnvConfig resolveEnvConfig({
  String appEnv = kAppEnvDefine,
  String supabaseUrl = kSupabaseUrlDefine,
  String supabaseAnonKey = kSupabaseAnonKeyDefine,
  String stripePublishableKey = kStripePkDefine,
  bool isReleaseBuild = kReleaseMode,
}) {
  final AppEnvironment environment;
  if (appEnv.trim().isEmpty) {
    if (isReleaseBuild) {
      throw StateError(
        'APP_ENV is not set. A release build must name its environment '
        'explicitly: build with --dart-define-from-file=dart_defines/'
        '<dev|qa|prod>.json (see dart_defines/README.md).',
      );
    }
    environment = kDefaultEnvironment;
  } else {
    final parsed = AppEnvironment.tryParse(appEnv);
    if (parsed == null) {
      throw ArgumentError.value(
        appEnv,
        'APP_ENV',
        'Unknown environment. Expected one of: dev, qa, prod',
      );
    }
    environment = parsed;
  }

  final defaults = kEnvironmentDefaults[environment]!;
  String pick(String override, String fallback) =>
      override.isNotEmpty ? override : fallback;

  return EnvConfig(
    environment: environment,
    supabaseUrl: pick(supabaseUrl, defaults.supabaseUrl),
    supabaseAnonKey: pick(supabaseAnonKey, defaults.supabaseAnonKey),
    stripePublishableKey:
        pick(stripePublishableKey, defaults.stripePublishableKey),
  );
}

/// The environment this binary was built for.
class AppEnv {
  AppEnv._();

  static final EnvConfig current = resolveEnvConfig();
}
