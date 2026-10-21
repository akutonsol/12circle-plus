import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/auth_error_text.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/router/app_router.dart' show passwordRecoveryNotifier;
import 'widgets/auth_design.dart';

/// Reached after the user taps the password-reset link in their email. Supabase
/// establishes a short-lived recovery session and fires AuthChangeEvent
/// .passwordRecovery; the router sends them here to set a new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _done = false;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _pwCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pw.length < 6) {
      _snack('Password must be at least 6 characters');
      return;
    }
    if (pw != confirm) {
      _snack('Passwords do not match');
      return;
    }
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: pw));
      passwordRecoveryNotifier.value = false;
      if (mounted) setState(() { _loading = false; _done = true; });
    } catch (e, st) {
      reportError('ResetPasswordScreen._submit', e, st);
      if (mounted) {
        setState(() => _loading = false);
        _snack(authErrorText(e));
      }
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent));

    if (_done) {
      return AuthScaffold(
        title: 'Password updated',
        subtitle: 'Your password has been changed. Sign in with your new password.',
        children: [
          const SizedBox(height: 12),
          Center(child: Container(
            width: 84, height: 84,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AuthColors.purple.withValues(alpha: 0.18),
              border: Border.all(color: AuthColors.purpleLight.withValues(alpha: 0.4), width: 1.5)),
            child: const Icon(Icons.check_rounded, color: AuthColors.purpleLight, size: 44))),
          const SizedBox(height: 32),
          AuthButton(label: 'Back to Sign In', onTap: () async {
            await Supabase.instance.client.auth.signOut();
            if (context.mounted) context.go('/login');
          }),
        ],
      );
    }

    return AuthScaffold(
      title: 'Set a new password',
      subtitle: 'Choose a new password for your account.',
      children: [
        AuthField(controller: _pwCtrl, hint: 'New password', isPassword: true),
        const SizedBox(height: 12),
        AuthField(controller: _confirmCtrl, hint: 'Confirm new password', isPassword: true),
        const SizedBox(height: 24),
        AuthButton(label: 'Update Password', loading: _loading, onTap: _submit),
      ],
    );
  }
}
