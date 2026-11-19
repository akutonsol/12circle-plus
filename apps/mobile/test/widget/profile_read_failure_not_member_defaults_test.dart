import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/profile/presentation/notification_preferences_screen.dart';
import 'package:circle_fitness/features/profile/presentation/personal_info_screen.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/profile_read_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-16 · the signed-in member's profile read passes failures on.
//
// currentUserProfileProvider returned `null` on a failed read. Every screen
// below then treated the failure as "no profile":
//   * Profile showed "Member", the session email, a client's stat cards with
//     "—" and 0 days, "IMPERIAL" — defaults dressed as the member's own data;
//   * Personal Info left the form blank and editable (Save refused, but only
//     after the member had typed into a form holding none of their details);
//   * Notifications showed the default toggles as stored, and every toggle
//     WROTE when tapped;
//   * Settings showed "KG" as the stored unit and the toggle WROTE when tapped.
//
// These tests run the REAL provider over a fake PostgREST whose user_profiles
// read fails. HOW TO SEE THEM FAIL: check out the base commit's lib files
// (auth_provider.dart and the four screens); the failure tests find "Member",
// no "Couldn't load your profile", and writes after a failed read.

const _uid = '00000000-0000-4000-8000-0000000f1616';
const _offline =
    "Couldn't load your profile — check your connection and try again.";
const _failed = "Couldn't load your profile — try again in a moment. "
    'If it keeps happening, contact support.';

final _stored = <String, Object?>{
  'id': _uid,
  'first_name': 'Ana',
  'last_name': 'Lee',
  'email': 'ana@example.com',
  'role': 'client',
  'phone': '555-0100',
  'gender': 'Female',
  'height_cm': 170,
  'weight_kg': 64.5,
  'weight_goal_kg': 60.0,
  'training_days_per_week': 4,
  'unit_preference': 'imperial',
  'notif_workout_reminders': false,
  'notif_checkin_reminders': true,
  'notif_coach_messages': true,
  'notif_progress_updates': true,
  'notif_challenges': false,
  'notif_community': false,
};

void main() {
  late ProfileReadPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = ProfileReadPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> open(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(600, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider
            .overrideWithValue(Supabase.instance.client.auth.currentUser),
        clientPlanProvider.overrideWith((ref) async => ClientPlan.selfGuided),
      ],
      child: MaterialApp(home: screen),
    ));
    await tester.pumpAndSettle();
    // postgrest retries a GET that hit a network failure, on timers. A screen
    // with no animation lets pumpAndSettle return mid-retry, so move fake time
    // past the retries before asserting.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
  }

  /// Fail the read, open [screen], then answer the next read with the stored
  /// row and tap Try again.
  Future<void> failThenRetry(WidgetTester tester, Widget screen) async {
    server.profileRead = ProfileRead.network;
    await open(tester, screen);
    expect(find.text(_offline), findsOneWidget, reason: 'premise: it failed');
    server.profileRead = ProfileRead.ok;
    server.profile = Map.of(_stored);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text(_offline), findsNothing, reason: 'the retry loaded it');
  }

  List<String> profileWrites() =>
      server.writes.where((w) => w.contains('/user_profiles')).toList();

  // ── Profile ──────────────────────────────────────────────────────────────
  group('Profile', () {
    testWidgets('a failed read says so instead of showing "Member" defaults',
        (tester) async {
      server.profileRead = ProfileRead.network;
      await open(tester, const ProfileScreen());
      expect(find.text(_offline), findsOneWidget,
          reason: 'THE defect: the failure was rendered as a profile');
      expect(find.text('Member'), findsNothing);
      expect(find.text('IMPERIAL'), findsNothing);
      expect(find.text('HEIGHT'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget,
          reason: 'signing out does not depend on the profile');
      expect(reported.map((f) => f.origin), contains('currentUserProfileProvider'));
    });

    testWidgets('a server failure uses the support wording, not "connection"',
        (tester) async {
      server.profileRead = ProfileRead.serverError;
      await open(tester, const ProfileScreen());
      expect(find.text(_failed), findsOneWidget);
      expect(find.text(_offline), findsNothing);
    });

    testWidgets('Try again loads the real profile', (tester) async {
      await failThenRetry(tester, const ProfileScreen());
      expect(find.text('Ana Lee'), findsOneWidget);
      expect(find.text('64.5 kg'), findsWidgets);
    });

    testWidgets('Try again is busy-aware: one read per tap while in flight',
        (tester) async {
      server.profileRead = ProfileRead.network;
      await open(tester, const ProfileScreen());
      final before = server.profileReads;
      server.readGate = Completer<void>();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.text('Loading…'), findsOneWidget,
          reason: 'the retry shows it is running');
      await tester.tap(find.text('Loading…'), warnIfMissed: false);
      await tester.pump();
      expect(server.profileReads, before + 1,
          reason: 'a second tap while in flight must not re-read');
      server.profileRead = ProfileRead.ok;
      server.profile = Map.of(_stored);
      server.readGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Ana Lee'), findsOneWidget);
    });

    testWidgets('Try again is at least 44px tall, labelled, in a live region',
        (tester) async {
      server.profileRead = ProfileRead.network;
      await open(tester, const ProfileScreen());
      final button = find.ancestor(
          of: find.text('Try again'), matching: find.byType(TextButton));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('Try again, load your profile'), findsOneWidget);
      final live = find.ancestor(
          of: find.text(_offline),
          matching: find.byWidgetPredicate(
              (w) => w is Semantics && (w.properties.liveRegion ?? false)));
      expect(live, findsWidgets);
    });

    testWidgets('control: no profile row keeps the existing defaults',
        (tester) async {
      server.profile = null;
      await open(tester, const ProfileScreen());
      expect(find.text(_offline), findsNothing);
      expect(find.text(_failed), findsNothing);
      expect(find.text('PROFILE'), findsOneWidget);
      expect(reported, isEmpty);
    });
  });

  // ── Personal Info ────────────────────────────────────────────────────────
  group('Personal Info', () {
    testWidgets('after a failed read nothing can be typed and Save sends nothing',
        (tester) async {
      server.profileRead = ProfileRead.network;
      await open(tester, const PersonalInfoScreen());
      expect(find.text(_offline), findsOneWidget,
          reason: 'THE defect: a blank, editable form and no failure');
      final first = tester.widget<TextField>(find.byType(TextField).first);
      expect(first.enabled, isFalse, reason: 'inputs are locked');
      await tester.tap(find.text('Save'), warnIfMissed: false);
      await tester.tap(find.text('Save Changes'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(profileWrites(), isEmpty);
      expect(find.text('Profile updated successfully'), findsNothing);
    });

    testWidgets('Try again fills the form, unlocks it, and Save writes it',
        (tester) async {
      await failThenRetry(tester, const PersonalInfoScreen());
      final first = tester.widget<TextField>(find.byType(TextField).first);
      expect(first.enabled, isNot(isFalse));
      expect(first.controller!.text, 'Ana');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(profileWrites(), hasLength(1));
      expect(profileWrites().single, contains('"weight_kg":64.5'));
      expect(profileWrites().single, contains('"phone":"555-0100"'));
    });

    testWidgets('control: a successful read saves as before', (tester) async {
      server.profile = Map.of(_stored);
      await open(tester, const PersonalInfoScreen());
      expect(find.text(_offline), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(profileWrites(), hasLength(1));
      expect(profileWrites().single, contains('"first_name":"Ana"'));
    });
  });

  // ── Notifications ────────────────────────────────────────────────────────
  Finder toggles() => find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_PurpleToggle');

  group('Notifications', () {
    testWidgets('after a failed read the toggles are locked and write nothing',
        (tester) async {
      server.profileRead = ProfileRead.network;
      await open(tester, const NotificationPreferencesScreen());
      expect(find.text(_offline), findsOneWidget);
      await tester.tap(toggles().first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(profileWrites(), isEmpty,
          reason: 'THE defect: a default toggle was flipped and stored');
    });

    testWidgets('Try again shows the stored settings and toggles save',
        (tester) async {
      await failThenRetry(tester, const NotificationPreferencesScreen());
      final firstValue =
          (tester.widget(toggles().first) as dynamic).value as bool;
      expect(firstValue, isFalse,
          reason: 'stored notif_workout_reminders=false, not the default');
      await tester.tap(toggles().first);
      await tester.pumpAndSettle();
      expect(profileWrites().single, contains('"notif_workout_reminders":true'));
    });

    testWidgets('control: a successful read is applied and toggles save',
        (tester) async {
      server.profile = Map.of(_stored);
      await open(tester, const NotificationPreferencesScreen());
      expect((tester.widget(toggles().first) as dynamic).value as bool, isFalse);
      await tester.tap(toggles().at(1));
      await tester.pumpAndSettle();
      expect(profileWrites().single, contains('"notif_checkin_reminders":false'));
    });
  });

  // ── Settings › Default Units ─────────────────────────────────────────────
  String selectedUnit(WidgetTester tester) {
    for (final u in ['KG', 'LB']) {
      final box = tester.widget<AnimatedContainer>(find
          .ancestor(of: find.text(u).first, matching: find.byType(AnimatedContainer))
          .first);
      final color = (box.decoration as BoxDecoration?)?.color;
      if (color != null && color != Colors.transparent) return u;
    }
    return 'none';
  }

  group('Settings', () {
    testWidgets('after a failed read no unit is shown as stored and taps write '
        'nothing; no "Member"', (tester) async {
      server.profileRead = ProfileRead.network;
      await open(tester, const SettingsScreen());
      expect(find.text(_offline), findsOneWidget);
      expect(find.text('Member'), findsNothing);
      expect(selectedUnit(tester), 'none',
          reason: 'THE defect: "KG" was shown as the stored preference');
      await tester.tap(find.text('LB').first);
      await tester.tap(find.text('KG').first);
      await tester.pumpAndSettle();
      expect(profileWrites(), isEmpty);
    });

    testWidgets('Try again shows the stored unit and the toggle saves',
        (tester) async {
      await failThenRetry(tester, const SettingsScreen());
      expect(selectedUnit(tester), 'LB', reason: 'stored imperial');
      expect(find.text('Ana Lee'), findsOneWidget);
      await tester.tap(find.text('KG').first);
      await tester.pumpAndSettle();
      expect(profileWrites().single, contains('"unit_preference":"metric"'));
      expect(selectedUnit(tester), 'KG');
    });

    testWidgets('control: no profile row keeps "KG" and a live toggle',
        (tester) async {
      server.profile = null;
      await open(tester, const SettingsScreen());
      expect(find.text(_offline), findsNothing);
      expect(selectedUnit(tester), 'KG');
    });
  });
}
