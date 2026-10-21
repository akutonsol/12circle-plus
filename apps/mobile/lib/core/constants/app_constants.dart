import '../config/app_env.dart';

/// Client-safe backend constants for the environment this build targets.
///
/// Values live in [AppEnv] / `lib/core/config/app_env.dart` and are selected at
/// build time via `--dart-define=APP_ENV=dev|qa|prod`. Nothing secret belongs
/// here — the Anthropic key in particular is held only by the NestJS API.
class AppConstants {
  const AppConstants._();

  /// Supabase project URL for this build's environment.
  static String get supabaseUrl => AppEnv.current.supabaseUrl;

  /// Supabase publishable ("anon") key — client-safe, RLS-protected.
  static String get supabaseAnonKey => AppEnv.current.supabaseAnonKey;

  /// Base URL of the 12 Circle NestJS API (AI endpoints live behind it).
}
