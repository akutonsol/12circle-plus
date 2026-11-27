import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/identity/account_scope.dart';
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
  // establishes a recovery session before the router exists. The launch URL
  // says what the link was for; the recovery is bound to the account the link
  // signed in, if it signed anyone in. We tag the reset link with our own
  // ?recovery=1 marker (set in resetPassword) so it's distinguishable from an
  // OAuth return — both otherwise come back with ?code= under PKCE.
  final isRecovery = launchUri.queryParameters['recovery'] == '1' ||
      launchUri.fragment.contains('type=recovery');
  if (isRecovery) await bindPasswordRecoveryAtLaunch(launchUri);

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

  runApp(const CircleFitnessRoot());
}

/// The whole app under the account it belongs to (P0-FL-59a).
class CircleFitnessRoot extends StatelessWidget {
  const CircleFitnessRoot(
      {super.key, this.overrides = const [], this.theme});

  /// For tests (the app's theme fetches its fonts over the network).
  final List<Override> overrides;
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) => AccountScope(
        overrides: overrides,
        // The device's habit reminders are the account's that set them.
        onLaunch: HabitReminderService().sweepAtLaunch,
        onOwnerLeft: (_) => HabitReminderService().cancelAll(),
        child: CircleFitnessApp(theme: theme),
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

class CircleFitnessApp extends ConsumerStatefulWidget {
  const CircleFitnessApp({super.key, this.theme});

  /// Null: the app's own.
  final ThemeData? theme;

  @override
  ConsumerState<CircleFitnessApp> createState() => _CircleFitnessAppState();
}

class _CircleFitnessAppState extends ConsumerState<CircleFitnessApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final GoRouter _router;

  /// A generation after the launch's begins with no route: where its account
  /// goes waits for its role to be read (the launch's begins on the splash).
  late final bool _later;

  @override
  void initState() {
    super.initState();
    _router = ref.read(routerProvider);
    _later = !ref.read(accountGenerationProvider).isFirst;
    if (_later) _router.routerDelegate.addListener(_sayNotice);
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_sayNotice);
    super.dispose();
  }

  bool get _hasRoute => _router.routerDelegate.currentConfiguration.isNotEmpty;

  /// Once this generation's first route is up, says the one line left for the
  /// account it began with, and drops one left for any other.
  void _sayNotice() {
    if (!_hasRoute) return;
    _router.routerDelegate.removeListener(_sayNotice);
    final notice = accountNoticeNotifier.value;
    accountNoticeNotifier.value = null;
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || notice.uid != signedInUid()) return;
      _messenger.currentState
          ?.showSnackBar(SnackBar(content: Text(notice.text)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? TwelveCircleTheme.theme;
    return MaterialApp.router(
      title: '12 Circle Fitness',
      debugShowCheckedModeBanner: false,
      // 12 Circle Theme on Helix (three-tier tokens; app is dark-locked).
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      scrollBehavior: _AppScrollBehavior(),
      scaffoldMessengerKey: _messenger,
      builder: _later ? _orPending : null,
      routerConfig: _router,
    );
  }

  /// The app, and over it — while somebody is signed in and no route is up —
  /// that their account is loading. It was an empty window, for as long as a
  /// dropped connection takes to give up.
  Widget _orPending(BuildContext context, Widget? app) => ListenableBuilder(
        listenable: _router.routerDelegate,
        child: app,
        builder: (context, app) => Stack(fit: StackFit.expand, children: [
          app!,
          if (!_hasRoute && signedInUid() != null) const AccountPending(),
        ]),
      );
}

/// The signed-in account is being loaded and there is nothing to show yet.
class AccountPending extends StatelessWidget {
  const AccountPending({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Semantics(
          label: 'Loading your account',
          liveRegion: true,
          container: true,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
}
