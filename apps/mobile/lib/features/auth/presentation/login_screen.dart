import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/auth_provider.dart';
import '../../../core/errors/auth_error_text.dart';
import '../../../core/observability/app_failure.dart';
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
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handlePostAuthNavigation() async {
    if (!mounted) return;
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
    } catch (_) {
      if (mounted) context.go('/home');
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
        AuthButton(label: 'Sign in', loading: isLoading, onTap: _signIn),
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
