import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import '../data/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  // Derive from the stream so this rebuilds on sign-in/sign-out,
  // falling back to the raw client snapshot for the initial frame.
  return authState.valueOrNull?.session?.user ??
      Supabase.instance.client.auth.currentUser;
});

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(const AsyncValue.data(null));

  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _authService.signIn(email: email, password: password),
    );
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String role,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _authService.signUp(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        role: role,
      ),
    );
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _authService.signOut());
  }

  Future<void> resetPassword(String email) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _authService.resetPassword(email));
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _authService.signInWithGoogle());
  }

  Future<void> signInWithApple() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _authService.signInWithApple());
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AsyncValue<void>>(
  (ref) => AuthNotifier(ref.watch(authServiceProvider)),
);

final currentUserProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  try {
    final data = await Supabase.instance.client
        .from('user_profiles')
        .select('''
          id, first_name, last_name, email, role, phone, avatar_url,
          gender, date_of_birth,
          height_cm, weight_kg, weight_goal_kg,
          fitness_goal, activity_level, training_days_per_week,
          training_location, nutrition_goal, onboarding_complete,
          coaching_mode, unit_preference, membership_tier,
          notif_workout_reminders, notif_checkin_reminders,
          notif_coach_messages, notif_progress_updates,
          notif_challenges, notif_community,
          coach_title, coach_bio, is_accepting_clients, max_clients,
          tagline, specialties, certifications, years_experience,
          pricing_monthly, rating_avg, review_count,
          experience_level, sleep_hours, stress_level, occupation,
          dietary_restrictions, food_allergies, target_timeline,
          medical_conditions, has_injuries, injury_locations,
          risk_score, risk_level, risk_flags, ai_client_summary
        ''')
        .eq('id', user.id)
        .maybeSingle();
    // `null` here means only one thing: the read SUCCEEDED and there is no row.
    return data;
  } catch (e, st) {
    // P0-FL-16: this was `return null`, so a failed read looked exactly like
    // "no profile" — Profile showed "Member" defaults and the edit forms
    // pre-filled with nothing. The failure is recorded and passed on; consumers
    // that read `.valueOrNull` still see null, the ones that must tell the two
    // apart match on AsyncError.
    reportError('currentUserProfileProvider', e, st);
    rethrow;
  }
});

/// P0-FL-45b · the profile row read for the member signed in NOW, or `null`.
///
/// Riverpod keeps the previous value through a re-read, so after a
/// sign-out/sign-in `currentUserProfileProvider` still holds the PREVIOUS
/// member's row while the new member's read is in flight, and after it fails.
/// A row counts only when its `id` is the signed-in user's; a later failed
/// refresh of the SAME member keeps it (a real answer for this member). `null`
/// means "nothing confirmed for this member" (unread, failed, another
/// member's, or no row) — callers fall back exactly as they do for no row.
/// The role-only twin is `confirmedRoleRead` (paywall_gate.dart).
Map<String, dynamic>? confirmedProfileRead(
    AsyncValue<Map<String, dynamic>?> profile, User? user) {
  if (user == null || !profile.hasValue) return null;
  final value = profile.value;
  if (value == null || value['id'] != user.id) return null;
  return value;
}

/// [confirmedProfileRead] for the signed-in member, as a provider.
final confirmedCurrentProfileProvider = Provider<Map<String, dynamic>?>((ref) =>
    confirmedProfileRead(
        ref.watch(currentUserProfileProvider), ref.watch(currentUserProvider)));

/// The signed-in member's first name: the profile's (the one Personal Info
/// edits), then the sign-up metadata, then the email's local part — the order
/// the app scaffold already uses.
///
/// Activity and Directory greeted the member from the sign-up metadata only,
/// which nothing updates: a name corrected in Personal Info changed in Profile
/// and the scaffold but the greeting kept the sign-up name on those two.
final currentFirstNameProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  // P0-FL-45b: only a row read for this member (never the previous one's).
  final profile = ref.watch(confirmedCurrentProfileProvider);
  final fromProfile = (profile?['first_name'] as String?)?.trim() ?? '';
  if (fromProfile.isNotEmpty) return fromProfile;
  final fromSignup = (user?.userMetadata?['first_name'] as String?)?.trim() ?? '';
  if (fromSignup.isNotEmpty) return fromSignup;
  return user?.email?.split('@').first ?? '';
});

final currentUserDisplayNameProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return 'Coach';
  final meta = user.userMetadata ?? {};
  final fn = meta['first_name'] as String? ?? '';
  final ln = meta['last_name'] as String? ?? '';
  final name = 'Coach $fn $ln'.trim().replaceAll(RegExp(r'\s+'), ' ');
  return name == 'Coach' ? 'Coach' : name;
});
