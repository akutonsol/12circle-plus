import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/auth_error_text.dart';
import '../../../core/identity/account_scope.dart'
    show
        accountNoticeNotifier,
        isMixedSession,
        putBackOwnUser,
        signOutFailedText,
        signOutOfDevice,
        signedInUid;
import '../../../core/observability/app_failure.dart';
import '../../../core/router/app_router.dart'
    show endPasswordRecovery, passwordRecoveryNotifier;
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

  /// The device kept [_owner]'s stored session: the next press of Back to Sign
  /// In tries again, though nobody is signed in by then.
  bool _signOutFailed = false;

  /// The account this form sets the password of (P0-FL-59a, W2): the one the
  /// reset link was for, else the one signed in when the form opened.
  String? _owner;
  late final StreamSubscription<AuthState> _auth;

  String? get _signedIn => signedInUid();

  @override
  void initState() {
    super.initState();
    _owner = passwordRecoveryNotifier.value ?? _signedIn;
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session?.user.id != _owner && _signedIn != _owner) {
        _accountChanged();
      }
    }, onError: (Object _, StackTrace __) {});
  }

  /// The account signed in is not [_owner]: what was typed here is not for it.
  /// Nothing is sent, and the form is left — unless the form is now this
  /// account's own (its reset link), which starts it again empty.
  void _accountChanged() {
    if (!mounted) return;
    final now = _signedIn;
    _pwCtrl.clear();
    _confirmCtrl.clear();
    setState(() {
      _loading = false;
      _done = false;
    });
    if (now != null && now == passwordRecoveryNotifier.value) {
      _owner = now;
      return;
    }
    if (passwordRecoveryNotifier.value != null) endPasswordRecovery();
    GoRouter.maybeOf(context)?.go('/login');
  }

  void _reportChanged() => reportError('ResetPasswordScreen._submit',
      StateError('set new password: the signed-in account changed'));

  /// A press that sent nothing is said, or the password typed just disappears.
  /// Where the member lands: on the form when it stays (now their own), else on
  /// the page this goes to, or the first of the next account's generation
  /// (which this one's messenger does not outlive).
  void _sayNothingWasSet() {
    if (!mounted) return;
    final now = _signedIn;
    final text = now == null ? _notSetSignedOut : _notSet;
    accountNoticeNotifier.value = (uid: now, text: text);
    _snack(text);
  }

  static const _notSet = "Couldn't set the new password — the account signed in "
      'here changed. Ask for a new reset link.';

  /// Nobody is signed in here.
  static const _notSetSignedOut = "Couldn't set the new password — the account "
      'changed. Ask for a new reset link.';

  @override
  void dispose() {
    _auth.cancel();
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final owner = _owner;
    if (_signedIn != owner) {
      _reportChanged();
      _sayNothingWasSet();
      _accountChanged();
      return;
    }
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
    final auth = Supabase.instance.client.auth;
    // Another account arriving while the update is out. The user signed in
    // cannot say so afterwards: gotrue's updateUser copies the ANSWERED one
    // (owner) onto whatever session is current by then. Put right as soon as
    // that is heard of, before anything else runs.
    var changed = false;
    Session? arrived;
    Future<void>? puttingBack;
    final watch = auth.onAuthStateChange.listen((state) {
      final session = state.session;
      if (isMixedSession(session)) {
        changed = true;
        puttingBack =
            putBackOwnUser(arrived, fromBroadcast: state.fromBroadcast);
      } else if (session?.user.id != owner) {
        changed = true;
        arrived = session;
      }
    }, onError: (Object _, StackTrace __) {});
    try {
      await auth.updateUser(UserAttributes(password: pw));
      await Future<void>.delayed(Duration.zero); // let the last event land
      if (changed) {
        _reportChanged();
        await puttingBack;
        // Already the next account's own form: theirs, with what they typed.
        if (_owner == owner) _accountChanged();
        return;
      }
      endPasswordRecovery();
      if (mounted) setState(() { _loading = false; _done = true; });
    } catch (e, st) {
      reportError('ResetPasswordScreen._submit', e, st);
      if (mounted && !changed && _signedIn == owner) {
        setState(() => _loading = false);
        _snack(authErrorText(e));
      }
    } finally {
      unawaited(watch.cancel());
    }
  }

  /// Signs out the account whose password was set, and only that one.
  Future<void> _backToSignIn() async {
    final router = GoRouter.maybeOf(context);
    final owner = _owner;
    if (_signedIn == owner || (_signOutFailed && _signedIn == null)) {
      final error = await signOutOfDevice('ResetPasswordScreen._backToSignIn',
          Supabase.instance.client.auth.signOut);
      if (!mounted) return;
      final now = _signedIn;
      if (error != null && (now == null || now == owner)) {
        // Still on the device: not /login as if signed out.
        _signOutFailed = true;
        _snack(signOutFailedText(error));
        return;
      }
    }
    if (mounted) router?.go('/login');
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
          AuthButton(label: 'Back to Sign In', onTap: _backToSignIn),
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
