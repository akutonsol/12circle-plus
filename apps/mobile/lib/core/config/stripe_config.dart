import 'app_env.dart';

/// Stripe publishable key (client-safe — NOT the secret key) for the
/// environment this build targets.
///
/// Set it per environment with `--dart-define=STRIPE_PK=pk_test_xxx`, or via
/// the environment's `dart_defines/<env>.json` file.
///
/// When empty, the app falls back to the hosted (redirect) checkout flow.
String get stripePublishableKey => AppEnv.current.stripePublishableKey;
