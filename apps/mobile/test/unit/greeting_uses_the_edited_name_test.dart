import 'dart:io';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// A name corrected in Personal Info never reached the Activity and Directory
// greetings. They read the sign-up metadata only, which nothing updates
// (Personal Info writes `user_profiles`); Profile and the app scaffold read the
// profile first and changed, "Good morning, <signup name>" did not.

User _user(Map<String, dynamic> meta, {String email = 'jo@example.test'}) => User(
    id: 'u1', appMetadata: const {}, userMetadata: meta, aud: 'authenticated',
    email: email, createdAt: '2026-01-01T00:00:00Z');

ProviderContainer _c(User? u, Map<String, dynamic>? profile) {
  final c = ProviderContainer(overrides: [
    currentUserProvider.overrideWithValue(u),
    currentUserProfileProvider.overrideWith((ref) async => profile),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('the name the member edited wins over the sign-up name', () async {
    final c = _c(_user({'first_name': 'Jo'}), {'first_name': 'Joanna'});
    await c.read(currentUserProfileProvider.future);
    expect(c.read(currentFirstNameProvider), 'Joanna',
        reason: 'THE defect: the greeting kept the sign-up name "Jo"');
  });

  test('before the profile is read, the sign-up name, then the email', () {
    expect(_c(_user({'first_name': 'Jo'}), null).read(currentFirstNameProvider), 'Jo');
    expect(_c(_user(const {}), null).read(currentFirstNameProvider), 'jo');
  });

  test('guard: neither greeting reads the sign-up metadata itself', () {
    for (final p in [
      'lib/features/activity/presentation/activity_screen.dart',
      'lib/features/dashboard/presentation/directory_screen.dart',
    ]) {
      expect(File(p).readAsStringSync().contains("userMetadata?['first_name']"), isFalse, reason: p);
    }
  });
}
