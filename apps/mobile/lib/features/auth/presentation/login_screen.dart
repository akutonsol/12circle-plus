import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/auth_provider.dart';
import '../../../core/errors/auth_error_text.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/observability/network_failure.dart';
import '../../../core/router/app_router.dart' show authErrorNotifier;
import 'widgets/auth_design.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // If an OAuth redirect came back with an error, main() stashed a message.
    // Show it once now that the login screen is up, then clear it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final msg = authErrorNotifier.value;
      if (msg != null && mounted) {
        authErrorNotifier.value = null;
        _showError(msg);
      }
      // The router only leaves a signed-in user on /login when it could not
      // read their account (it no longer guesses '/home'). Run the read here
      // so the user gets the failure notice and Try again, not a bare form.
      if (mounted && Supabase.instance.client.auth.currentSession != null) {
        _handlePostAuthNavigation();
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// The account read that chooses where a signed-in user lands failed. Null
  /// when there is no failure. The user IS signed in, but we do not know who
  /// they are to the app (client, coach, admin, vendor), so we do not guess:
  /// they stay here with a message, Try again and Sign out (P0-FL-15).
  Object? _accountReadError;

  /// A role read is in flight: Try again is disabled and a second trigger
  /// (the auth-state listener, a double tap) does nothing.
  bool _routing = false;

  /// Email sign-in is in flight; it routes itself once it finishes, so the
  /// auth-state listener must not start a second role read meanwhile.
  bool _signingIn = false;

  bool _signingOut = false;

  Future<void> _handlePostAuthNavigation() async {
    if (!mounted || _routing) return;
    // A failure notice stays up while Try again runs (the button shows
    // progress); success navigates away, another failure replaces it.
    setState(() => _routing = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final profile = await Supabase.instance.client
            .from('user_profiles')
            .select('role, onboarding_complete')
            .eq('id', userId)
            .maybeSingle();
        final role = profile?['role'] as String? ?? 'client';
        final needsOnboarding = profile?['onboarding_complete'] == false;
        if (!mounted) return;
        if (role == 'coach') {
          context.go('/coach-dashboard');
        } else if (role == 'admin') {
          context.go('/admin-dashboard');
        } else if (role == 'vendor') {
          context.go('/vendor-portal');
        } else if (needsOnboarding) {
          context.go('/intake');
        } else {
          context.go('/home');
        }
      } else {
        if (mounted) context.go('/home');
      }
    } catch (e, st) {
      // Was `catch (_) { context.go('/home'); }`: a coach, admin or vendor
      // whose role read failed was dropped into the client app.
      reportError('LoginScreen._handlePostAuthNavigation', e, st);
      if (mounted) setState(() => _accountReadError = e);
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  /// Leaves the signed-in-but-unknown state. Confirmed only when the session
  /// is actually gone.
  Future<void> _signOutAfterFailure() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    await ref.read(authNotifierProvider.notifier).signOut();
    if (!mounted) return;
    final result = ref.read(authNotifierProvider);
    final stillSignedIn = Supabase.instance.client.auth.currentSession != null;
    if (result.hasError) {
      reportError('LoginScreen._signOutAfterFailure', result.error!, result.stackTrace);
    }
    setState(() {
      _signingOut = false;
      if (!stillSignedIn) _accountReadError = null;
    });
    if (stillSignedIn) {
      _showError(isNetworkFailure(result.error)
          ? "Couldn't sign you out — check your connection and try again."
          : "Couldn't sign you out — try again in a moment. If it keeps happening, contact support.");
    }
  }

  // OAuth uses Supabase's redirect flow: the page navigates to the provider and
  // back, then the auth-state listener + router handle navigation. We only
  // surface a launch error here.
  Future<void> _signInWithGoogle() async {
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    if (mounted && ref.read(authNotifierProvider).hasError) {
      _showError('Could not start Google sign-in. Please try again.');
    }
  }

  Future<void> _signInWithApple() async {
    await ref.read(authNotifierProvider.notifier).signInWithApple();
    if (mounted && ref.read(authNotifierProvider).hasError) {
      _showError('Could not start Apple sign-in. Please try again.');
    }
  }

  Future<void> _signIn() async {
    if (_emailCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      _showError('Please enter your email and password');
      return;
    }

    _signingIn = true;
    try {
      await ref.read(authNotifierProvider.notifier).signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
      if (!mounted) return;

      final authState = ref.read(authNotifierProvider);
      if (authState.hasError) {
        // The raw object goes to the sink (status code, error code, type); the
        // user gets the provider's human-readable message. Showing
        // `error.toString()` here put `AuthApiException(message: …,
        // statusCode: 400, code: invalid_credentials)` on screen.
        reportError('LoginScreen._signIn', authState.error!, authState.stackTrace);
        _showError(authErrorText(authState.error));
        return;
      }
      await _handlePostAuthNavigation();
    } finally {
      _signingIn = false;
    }
  }

  /// The notice shown while signed in but the account read failed. One voice;
  /// connection wording only for a connection failure; never exception text.
  Widget _accountReadFailure() {
    final message = isNetworkFailure(_accountReadError)
        ? "Couldn't load your account — check your connection and try again."
        : "Couldn't load your account — try again in a moment. If it keeps happening, contact support.";
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('login-account-read-failure'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x26FF6B6B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x66FF6B6B)),
        ),
        child: Text(message,
            style: const TextStyle(color: AuthColors.text, fontSize: 14, height: 1.45)),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: AuthColors.purple,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent));
    final isLoading = ref.watch(authNotifierProvider).isLoading;

    // A session that arrives while this screen is up (OAuth returning by deep
    // link) is routed by the router's redirect — which, when the account read
    // fails, now leaves the user here. Run the read so they see why.
    ref.listen<AsyncValue<AuthState>>(authStateProvider, (prev, next) {
      if (next is! AsyncData<AuthState>) return;
      if (next.value.event != AuthChangeEvent.signedIn) return;
      if (next.value.session == null || _signingIn) return;
      _handlePostAuthNavigation();
    });

    if (_accountReadError != null) {
      return AuthScaffold(
        title: 'Welcome back',
        notice: _accountReadFailure(),
        children: [
          // AuthButton is 52pt, a Semantics button named by its label, and
          // takes no tap while [loading] — so a read in flight cannot be
          // fired twice (and _handlePostAuthNavigation guards on _routing).
          AuthButton(
            label: 'Try again',
            showArrow: false,
            loading: _routing,
            onTap: _handlePostAuthNavigation,
          ),
          const SizedBox(height: 12),
          // 48pt; TextButton is a Semantics button named by its text, and is
          // disabled while the sign-out is in flight.
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              key: const Key('login-account-read-sign-out'),
              onPressed: _signingOut ? null : _signOutAfterFailure,
              child: Text(_signingOut ? 'Signing out…' : 'Sign out',
                  style: const TextStyle(color: AuthColors.purpleLight, fontSize: 15, fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      );
    }

    // FIT-007 (locked). Structure, copy and order come from the design board:
    // logo, "Welcome back", labelled fields, right-aligned forgot link, primary
    // CTA, "or" divider, then Apple ABOVE Google as full-width secondary
    // buttons, and the "New here?" footer.
    return AuthScaffold(
      title: 'Welcome back',
      footer: AuthFooterLink(prefix: 'New here?', action: 'Create an account', onTap: () => context.go('/signup')),
      children: [
        AuthField(controller: _emailCtrl, label: 'Email', hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 16),
        AuthField(controller: _passwordCtrl, label: 'Password', hint: 'Your password', isPassword: true),
        const SizedBox(height: 14),
        Align(alignment: Alignment.centerRight, child: GestureDetector(
          onTap: () => context.go('/forgot-password'),
          child: const Text('Forgot password?',
            style: TextStyle(color: AuthColors.purpleLight, fontSize: 13, fontWeight: FontWeight.w500)))),
        const SizedBox(height: 22),
        AuthButton(label: 'Sign in', loading: isLoading || _routing, onTap: _signIn),
        const SizedBox(height: 22),
        const AuthDivider(),
        const SizedBox(height: 22),
        AuthSocialButton(label: 'Continue with Apple',
          icon: const Icon(Icons.apple, color: AuthColors.text, size: 18),
          onTap: isLoading ? () {} : _signInWithApple),
        const SizedBox(height: 10),
        AuthSocialButton(label: 'Continue with Google', icon: const GoogleGlyph(),
          onTap: isLoading ? () {} : _signInWithGoogle),
      ],
    );
  }
}
