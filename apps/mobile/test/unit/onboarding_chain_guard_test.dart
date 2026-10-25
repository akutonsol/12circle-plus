import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ONB-G1 · the first-run chain Splash → Welcome → account reaches the locked
/// FIT-006 Welcome frame.
///
/// Welcome (`/onboarding`) had no way in (OD-31): the splash sent Get Started
/// straight to `/signup`, so the owner-locked frame was unreachable. The router's
/// own comment says the splash "hands off to /onboarding itself". This pins the
/// three links so Welcome cannot be orphaned again without a failing test.
void main() {
  String strip(String s) =>
      s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAll(RegExp(r'//[^\n]*'), '');

  final splash = strip(File('lib/features/home/presentation/splash_screen.dart')
      .readAsStringSync());
  final welcome = strip(File('lib/features/onboarding/presentation/onboarding_screen.dart')
      .readAsStringSync());

  test('the sources are readable and non-trivial', () {
    expect(splash.length, greaterThan(2000));
    expect(welcome.length, greaterThan(2000));
  });

  test('Splash → Get Started opens Welcome, not the signup form', () {
    expect(splash, contains("context.go('/onboarding')"),
        reason: 'Welcome (FIT-006, locked) is orphaned again');
    expect(splash, isNot(contains("_ctaButton(() => context.go('/signup'))")),
        reason: 'Get Started skips the locked Welcome frame');
  });

  test('Welcome still leads on to account creation and sign-in', () {
    expect(welcome, contains("context.go('/signup')"));
    expect(welcome, contains("context.go('/login')"));
  });
}
