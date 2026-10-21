import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/auth_provider.dart';
import '../../../core/errors/auth_error_text.dart';
import '../../../core/observability/app_failure.dart';
import 'widgets/auth_design.dart';

enum _Role { client, coach, vendor }

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _firstCtrl    = TextEditingController();
  final _lastCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _agreedToTerms = false;
  _Role _selectedRole = _Role.client;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (_firstCtrl.text.trim().isEmpty || _lastCtrl.text.trim().isEmpty) {
      _showError('Please enter your first and last name');
      return;
    }
    if (_emailCtrl.text.trim().isEmpty) {
      _showError('Please enter your email address');
      return;
    }
    if (_passwordCtrl.text.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }
    if (!_agreedToTerms) {
      _showError('Please agree to the Terms of Service');
      return;
    }

    await ref.read(authNotifierProvider.notifier).signUp(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      firstName: _firstCtrl.text.trim(),
      lastName: _lastCtrl.text.trim(),
      role: _selectedRole.name,
    );

    final state = ref.read(authNotifierProvider);
    state.whenOrNull(
      error: (e, st) {
        reportError('SignupScreen._signUp', e, st);
        _showError(authErrorText(e));
      },
      data: (_) async {
        if (!mounted) return;
        final role = _selectedRole.name;
        if (role == 'coach') {
          context.go('/coach-dashboard');
        } else if (role == 'vendor') {
          context.go('/vendor-portal');
        } else {
          context.go('/intake');
        }
      },
    );
  }

  // OAuth uses Supabase's redirect flow: the page navigates to the provider and
  // back, then the auth-state listener routes the signed-in user (new users →
  // /intake via the router guard). We only surface a launch error here.
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

    return AuthScaffold(
      title: "Let's get Started",
      subtitle: 'Create your account and start your personalized fitness journey.',
      footer: AuthFooterLink(prefix: 'Already have an account?', action: 'Sign In', onTap: () => context.go('/login')),
      children: [
        Row(children: [
          Expanded(child: AuthField(controller: _firstCtrl, hint: 'First name')),
          const SizedBox(width: 12),
          Expanded(child: AuthField(controller: _lastCtrl, hint: 'Last name')),
        ]),
        const SizedBox(height: 12),
        AuthField(controller: _emailCtrl, hint: 'Email address', keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        AuthField(controller: _passwordCtrl, hint: 'Password', isPassword: true),
        const SizedBox(height: 22),

        // Role
        const Text('I AM A:', style: TextStyle(color: AuthColors.purpleLight, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 2)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(children: [
            _RoleChip(label: 'Client', selected: _selectedRole == _Role.client,
              onTap: () => setState(() => _selectedRole = _Role.client)),
            const SizedBox(width: 10),
            _RoleChip(label: 'Coach', selected: _selectedRole == _Role.coach,
              onTap: () => setState(() => _selectedRole = _Role.coach)),
            const SizedBox(width: 10),
            _RoleChip(label: 'Wellness Partner', selected: _selectedRole == _Role.vendor,
              onTap: () => setState(() => _selectedRole = _Role.vendor)),
          ]),
        ),
        const SizedBox(height: 18),

        // Terms
        GestureDetector(
          onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22, height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: _agreedToTerms ? AuthColors.purple : Colors.transparent,
                border: Border.all(color: _agreedToTerms ? AuthColors.purple : AuthColors.fieldBorder, width: 1.5)),
              child: _agreedToTerms ? const Icon(Icons.check, color: Colors.white, size: 14) : null),
            const SizedBox(width: 12),
            const Text('I agree to the ', style: TextStyle(color: AuthColors.sub, fontSize: 14)),
            const Text('Terms of Service', style: TextStyle(color: AuthColors.purpleLight, fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 24),

        AuthButton(label: 'Create Account', loading: isLoading, onTap: _createAccount),
        const SizedBox(height: 22),
        const AuthDivider(),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: AuthSocialButton(label: 'Google', icon: const GoogleGlyph(),
            onTap: isLoading ? () {} : _signInWithGoogle)),
          const SizedBox(width: 12),
          Expanded(child: AuthSocialButton(label: 'Apple', icon: const Icon(Icons.apple, color: Colors.white, size: 22),
            onTap: isLoading ? () {} : _signInWithApple)),
        ]),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RoleChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: selected ? const LinearGradient(colors: [AuthColors.purpleLight, AuthColors.purple],
            begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          color: selected ? null : AuthColors.field,
          border: Border.all(color: selected ? Colors.transparent : AuthColors.fieldBorder, width: 1),
          boxShadow: selected ? [BoxShadow(color: AuthColors.purple.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))] : null,
        ),
        child: Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: selected ? Colors.white : AuthColors.sub, fontSize: 13.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
