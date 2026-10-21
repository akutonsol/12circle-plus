import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/auth_error_text.dart';
import '../../../core/observability/app_failure.dart';
import 'widgets/auth_design.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your email address')));
      return;
    }
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        // On web, send the user back to the running app origin so supabase_flutter
        // parses the recovery token and fires passwordRecovery (router → /reset-password).
        redirectTo: kIsWeb ? Uri.base.origin : null,
      );
      if (mounted) setState(() { _loading = false; _sent = true; });
    } catch (e, st) {
      reportError('ForgotPasswordScreen._submit', e, st);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authErrorText(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent));

    if (_sent) {
      return AuthScaffold(
        title: 'Check your email',
        subtitle: 'We sent a password reset link to your email address.',
        onBack: () => context.go('/login'),
        children: [
          const SizedBox(height: 12),
          Center(child: Container(
            width: 84, height: 84,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AuthColors.purple.withValues(alpha: 0.18),
              border: Border.all(color: AuthColors.purpleLight.withValues(alpha: 0.4), width: 1.5)),
            child: const Icon(Icons.mark_email_read_outlined, color: AuthColors.purpleLight, size: 40))),
          const SizedBox(height: 32),
          AuthButton(label: 'Back to Sign In', onTap: () => context.go('/login')),
        ],
      );
    }

    return AuthScaffold(
      title: 'Reset password',
      subtitle: 'Enter your email and we will send you a reset link.',
      onBack: () => context.go('/login'),
      footer: AuthFooterLink(prefix: 'Remembered it?', action: 'Sign In', onTap: () => context.go('/login')),
      children: [
        AuthField(controller: _emailController, hint: 'Email address', keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 24),
        AuthButton(label: 'Send Reset Link', loading: _loading, onTap: _send),
      ],
    );
  }
}
