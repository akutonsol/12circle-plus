import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/twelve_circle_theme.dart';
import 'core/router/app_router.dart';
import 'core/config/app_env.dart';
import 'core/constants/app_constants.dart';
import 'core/utils/web_logout.dart';
import 'features/habits/data/habit_reminder_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Which backend this binary talks to is fixed at build time
  // (--dart-define=APP_ENV=dev|qa|prod). Fail loudly rather than start up
  // half-configured — a QA build with no Supabase project would otherwise
  // throw deep inside the first query.
  final env = AppEnv.current;
  if (!env.canInitialiseSupabase) {
    throw StateError(
      'Environment "${env.environment.label}" is missing: '
      '${env.missingSettings().join(', ')}. '
      'Build with --dart-define-from-file=dart_defines/${env.environment.label}.json '
      '(see dart_defines/README.md).',
    );
  }

  // Capture the launch URL BEFORE Supabase.initialize() — it strips the
  // recovery token from the URL while establishing the recovery session.
  final launchUri = Uri.base;

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    publishableKey: AppConstants.supabaseAnonKey,
  );

  // Password-reset deep link: Supabase parses the token during initialize() and
  // establishes a recovery session, but the auth-stream event fires before the
  // router subscribes (so it's missed on web). Flag it from the captured launch
  // URL so the router opens /reset-password. We tag the reset link with our own
  // ?recovery=1 marker (set in resetPassword) so it's distinguishable from an
  // OAuth return — both otherwise come back with ?code= under PKCE.
  final isRecovery = launchUri.queryParameters['recovery'] == '1' ||
      launchUri.fragment.contains('type=recovery');
  if (isRecovery) passwordRecoveryNotifier.value = true;

  // OAuth redirect errors come back as ?error=...&error_code=... (and the same
  // in the #fragment). Surface a friendly message on the login screen and strip
  // the params so a used/expired state isn't replayed on reload.
  if (!isRecovery) {
    final authError = _oauthErrorMessage(launchUri);
    if (authError != null) {
      authErrorNotifier.value = authError;
      clearAuthParamsFromUrl();
    }
  }

  await HabitReminderService().initialize();

  runApp(
    const ProviderScope(
      child: CircleFitnessApp(),
    ),
  );
}

/// Reads an OAuth error from a redirect URL (params live in the query and/or
/// the #fragment) and maps it to a user-facing message. Returns null if there's
/// no error.
String? _oauthErrorMessage(Uri uri) {
  final params = <String, String>{
    ...uri.queryParameters,
    if (uri.fragment.isNotEmpty) ...Uri.splitQueryString(uri.fragment),
  };
  final code = params['error_code'];
  final error = params['error'];
  if (code == null && error == null) return null;

  switch (code) {
    case 'flow_state_already_used':
    case 'flow_state_expired':
      return 'That sign-in attempt expired. Please try again.';
    case 'bad_oauth_state':
      return 'Sign-in could not be verified. Please try again.';
  }
  if (error == 'access_denied') return 'Sign-in was cancelled.';

  final desc = params['error_description'];
  if (desc != null && desc.isNotEmpty) return desc; // already URL-decoded
  return 'Sign-in failed. Please try again.';
}

// Allows drag-scrolling with mouse in Chrome device simulation mode.
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class CircleFitnessApp extends ConsumerWidget {
  const CircleFitnessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: '12 Circle Fitness',
      debugShowCheckedModeBanner: false,
      // 12 Circle Theme on Helix (three-tier tokens; app is dark-locked).
      theme: TwelveCircleTheme.theme,
      darkTheme: TwelveCircleTheme.theme,
      themeMode: ThemeMode.dark,
      scrollBehavior: _AppScrollBehavior(),
      routerConfig: router,
    );
  }
}
