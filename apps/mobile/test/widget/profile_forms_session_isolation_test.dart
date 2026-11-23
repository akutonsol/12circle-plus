import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/profile/presentation/notification_preferences_screen.dart';
import 'package:circle_fitness/features/profile/presentation/personal_info_screen.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-45b · SESSION ISOLATION of the profile edit forms: a value read for
// the previous member is never shown as, or saved into, the new member's
// profile.
//
// Personal Info, Notifications and Settings' unit toggle keep what they read
// in State, and every write is `.update(…).eq('id', <signed-in id>)`. The
// State outlived a sign-out/sign-in: `_loaded`/`_unitLoaded` stayed true, so
//   * Personal Info kept member A's name, date of birth and weights in the
//     form — and Save wrote them into member B's row;
//   * Notifications kept A's toggles; a tap stored the opposite of A's value
//     in B's row;
//   * Settings kept A's unit selected for B.
// Now each form belongs to the member it was read for: another member signed
// in → cleared and locked until THEIR read lands; every write refuses unless
// the session's id is that member's.
//
// The switch here changes BOTH the app's member (`currentUserProvider`) and
// the Supabase session the write is filtered by, as a real sign-in does.
//
// HOW TO SEE IT FAIL: `git checkout 185261e -- <the three screens>`.

enum _P { ok, server, pending }

const _rows = <String, Map<String, Object?>>{
  'user-a': {
    'id': 'user-a',
    'role': 'client',
    'first_name': 'Alice',
    'last_name': 'Ames',
    'phone': '555-0101',
    'gender': 'Female',
    'date_of_birth': '1990-01-02',
    'height_cm': 165,
    'weight_kg': 82.5,
    'weight_goal_kg': 70.0,
    'training_days_per_week': 5,
    'unit_preference': 'imperial',
    'notif_workout_reminders': false,
  },
  'user-b': {
    'id': 'user-b',
    'role': 'client',
    'first_name': 'Bruno',
    'last_name': 'Berg',
    'phone': '555-0202',
    'gender': 'Male',
    'date_of_birth': '1985-03-04',
    'height_cm': 180,
    'weight_kg': 91.0,
    'weight_goal_kg': 85.0,
    'training_days_per_week': 2,
    'unit_preference': 'metric',
    'notif_workout_reminders': true,
  },
};

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    );

final _signedIn = StateProvider<User?>((ref) => _user('user-a'));

class _Profile {
  _Profile({Map<String, String> roles = const {}}) {
    for (final e in roles.entries) {
      rows[e.key] = {...rows[e.key]!, 'role': e.value};
    }
  }
  final rows = <String, Map<String, Object?>>{
    for (final e in _rows.entries) e.key: Map.of(e.value)
  };
  final Map<String, _P> modes = {};
  final Map<String, Duration> delays = {};
  final List<String> answered = [];
  _P mode = _P.ok;

  Future<Map<String, dynamic>?> read(String uid) async {
    final delay = delays[uid];
    if (delay != null) await Future<void>.delayed(delay);
    switch (modes[uid] ?? mode) {
      case _P.server:
        throw const PostgrestException(message: 'refused', code: 'XX000');
      case _P.pending:
        return Completer<Map<String, dynamic>?>().future;
      case _P.ok:
        answered.add(uid);
        return Map<String, dynamic>.of(rows[uid]!);
    }
  }
}

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// A Supabase session for [uid] (the JWT is not verified client-side).
String _session(String uid) {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
          1000;
  final jwt = '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
      'not-verified-client-side';
  return jsonEncode({
    'access_token': jwt,
    'token_type': 'bearer',
    'expires_in': 315360000,
    'expires_at': exp,
    'refresh_token': 'test-refresh-$uid',
    'user': {
      'id': uid,
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  });
}

void main() {
  late RowCheckingPostgrest server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RowCheckingPostgrest('user-a');
    await initSignedInSupabase(server);
  });

  setUp(() async {
    server.reset();
    await Supabase.instance.client.auth.recoverSession(_session('user-a'));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> open(
      WidgetTester tester, Widget screen, _Profile p) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 3200);
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
      currentUserProfileProvider.overrideWith((ref) async {
        final u = ref.watch(currentUserProvider);
        if (u == null) return null;
        return p.read(u.id);
      }),
      clientPlanProvider.overrideWith((ref) async => ClientPlan.selfGuided),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: screen),
    ));
    await settle(tester);
    return c;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  /// A signs out; B signs in — the app's member AND the Supabase session.
  Future<void> switchTo(WidgetTester tester, ProviderContainer c, String? uid,
      {required bool observeSignOut}) async {
    c.read(_signedIn.notifier).state = null;
    await Supabase.instance.client.auth.signOut();
    if (observeSignOut) await settle(tester);
    if (uid != null) {
      await Supabase.instance.client.auth.recoverSession(_session(uid));
      c.read(_signedIn.notifier).state = _user(uid);
    }
    await settle(tester);
  }

  List<String> profileWrites() =>
      server.writes.where((w) => w.contains('/user_profiles')).toList();

  /// Nothing of A's on screen: names, phone, weights.
  void expectNothingOfA() {
    for (final v in ['Alice', 'Ames', '555-0101', '82.5', '70.0', '165']) {
      expect(find.text(v), findsNothing, reason: "A's value \"$v\"");
    }
  }

  // ── Personal Info ─────────────────────────────────────────────────────────
  group('Personal Info', () {
    Future<void> tapSave(WidgetTester tester) async {
      await tester.tap(find.text('Save').first, warnIfMissed: false);
      await settle(tester);
    }

    for (final observe in [true, false]) {
      final how = observe ? 'sign-out observed' : 'same-frame switch';
      for (final (aRole, bRole) in const [
        ('client', 'client'),
        ('coach', 'client'),
        ('client', 'coach'),
      ]) {
        for (final bMode in _P.values) {
          testWidgets(
              "$aRole A → $bRole B ($how), B's read ${bMode.name}: A's details "
              "are never shown as B's, never saved into B's row",
              (tester) async {
            final p = _Profile(roles: {'user-a': aRole, 'user-b': bRole})
              ..modes['user-b'] = bMode;
            final c = await open(tester, const PersonalInfoScreen(), p);
            expect(find.text('Alice'), findsOneWidget,
                reason: "precondition: A's form");

            await switchTo(tester, c, 'user-b', observeSignOut: observe);
            expectNothingOfA();
            expect(find.text('Bruno'), bMode == _P.ok ? findsOneWidget : findsNothing,
                reason: "B's own details fill the form once read");
            await tapSave(tester);
            final writes = profileWrites();
            for (final w in writes) {
              expect(w, contains('id=eq.user-b'));
              for (final v in ['Alice', 'Ames', '555-0101', '82.5', '1990-01-02']) {
                expect(w, isNot(contains(v)), reason: "A's \"$v\" in B's row");
              }
            }
            if (bMode == _P.ok) {
              expect(writes, hasLength(1), reason: "B saves B's details");
              expect(writes.single, contains('Bruno'));
              if (bRole == 'client') expect(writes.single, contains('91'));
            } else {
              expect(writes, isEmpty,
                  reason: "B's details are not known: nothing is saved");
            }
            await unmount(tester);
          });
        }
      }
    }

    for (final slow in const ['first', 'refresh']) {
      testWidgets("A's slow $slow read lands after B signed in: B's form, "
          "B's save", (tester) async {
        const lag = Duration(seconds: 5);
        final p = _Profile();
        if (slow == 'first') p.delays['user-a'] = lag;
        final c = await open(tester, const PersonalInfoScreen(), p);
        if (slow == 'refresh') {
          expect(find.text('Alice'), findsOneWidget);
          p.delays['user-a'] = lag;
          c.invalidate(currentUserProfileProvider);
          await settle(tester);
        }
        await switchTo(tester, c, 'user-b', observeSignOut: false);
        await tester.pump(lag);
        await settle(tester);
        expect(p.answered.where((u) => u == 'user-a').length,
            slow == 'first' ? 1 : 2,
            reason: "precondition: A's late answer arrived");
        expectNothingOfA();
        expect(find.text('Bruno'), findsOneWidget);
        await tapSave(tester);
        expect(profileWrites(), hasLength(1));
        expect(profileWrites().single, contains('id=eq.user-b'));
        expect(profileWrites().single, isNot(contains('Alice')));
        await unmount(tester);
      });
    }

    testWidgets('A signs out, nobody signs in: the form forgets A and saves '
        'nothing', (tester) async {
      final c = await open(tester, const PersonalInfoScreen(), _Profile());
      expect(find.text('Alice'), findsOneWidget);
      await switchTo(tester, c, null, observeSignOut: true);
      expectNothingOfA();
      await tapSave(tester);
      expect(profileWrites(), isEmpty);
      await unmount(tester);
    });

    testWidgets("the session already belongs to B while the app still shows "
        "A's form: Save refuses — A's details never reach B's row",
        (tester) async {
      final c = await open(tester, const PersonalInfoScreen(), _Profile());
      expect(find.text('Alice'), findsOneWidget);
      // The Supabase session switched; the app's member has not caught up.
      await Supabase.instance.client.auth.recoverSession(_session('user-b'));
      c.invalidate(_signedIn); // a rebuild, same member
      await settle(tester);
      await tapSave(tester);
      expect(profileWrites(), isEmpty,
          reason: "the form is A's; the write would go to B's row");
      await unmount(tester);
    });

    testWidgets('a refresh that FAILS after a good read of the SAME member '
        'keeps the form, and Save still saves it', (tester) async {
      final p = _Profile();
      final c = await open(tester, const PersonalInfoScreen(), p);
      p.mode = _P.server;
      c.invalidate(currentUserProfileProvider);
      await settle(tester);
      expect(c.read(currentUserProfileProvider).hasError, isTrue);
      expect(find.text('Alice'), findsOneWidget);
      await tapSave(tester);
      expect(profileWrites(), hasLength(1));
      expect(profileWrites().single, contains('id=eq.user-a'));
      expect(profileWrites().single, contains('Alice'));
      await unmount(tester);
    });
  });

  // ── Notifications ─────────────────────────────────────────────────────────
  group('Notifications', () {
    /// Taps the first toggle (Workout Reminders): it stores the opposite of
    /// what it shows.
    Future<void> tapWorkoutReminders(WidgetTester tester) async {
      await tester.tap(find.byType(AnimatedAlign).first, warnIfMissed: false);
      await settle(tester);
    }

    for (final observe in [true, false]) {
      final how = observe ? 'sign-out observed' : 'same-frame switch';
      for (final bMode in _P.values) {
        testWidgets("A → B ($how), B's read ${bMode.name}: A's setting is "
            "never shown as B's or stored in B's row", (tester) async {
          final p = _Profile()..modes['user-b'] = bMode;
          final c = await open(tester, const NotificationPreferencesScreen(), p);
          await switchTo(tester, c, 'user-b', observeSignOut: observe);
          await tapWorkoutReminders(tester);
          final writes = profileWrites();
          if (bMode == _P.ok) {
            // B's stored value is ON, so the tap turns it OFF. With A's
            // (OFF) still showing, the tap stored ON — A's setting, flipped.
            expect(writes, hasLength(1));
            expect(writes.single, contains('id=eq.user-b'));
            expect(writes.single, contains('"notif_workout_reminders":false'));
          } else {
            expect(writes, isEmpty, reason: "B's settings are not known");
          }
          await unmount(tester);
        });
      }
    }

    testWidgets('the session belongs to B while A\'s toggles show: a tap '
        'stores nothing', (tester) async {
      final c = await open(tester, const NotificationPreferencesScreen(), _Profile());
      await Supabase.instance.client.auth.recoverSession(_session('user-b'));
      c.invalidate(_signedIn);
      await settle(tester);
      await tapWorkoutReminders(tester);
      expect(profileWrites(), isEmpty);
      await unmount(tester);
    });

    testWidgets('A signs out, nobody signs in: a tap stores nothing',
        (tester) async {
      final c = await open(tester, const NotificationPreferencesScreen(), _Profile());
      await switchTo(tester, c, null, observeSignOut: true);
      await tapWorkoutReminders(tester);
      expect(profileWrites(), isEmpty);
      await unmount(tester);
    });

    testWidgets("A's slow refresh lands after B signed in: B's setting",
        (tester) async {
      final p = _Profile();
      final c = await open(tester, const NotificationPreferencesScreen(), p);
      p.delays['user-a'] = const Duration(seconds: 5);
      c.invalidate(currentUserProfileProvider);
      await settle(tester);
      await switchTo(tester, c, 'user-b', observeSignOut: false);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      expect(p.answered.where((u) => u == 'user-a').length, 2);
      await tapWorkoutReminders(tester);
      expect(profileWrites(), hasLength(1));
      expect(profileWrites().single, contains('id=eq.user-b'));
      expect(profileWrites().single, contains('"notif_workout_reminders":false'));
      await unmount(tester);
    });

    testWidgets('a refresh that FAILS after a good read of the SAME member '
        'keeps the toggles live', (tester) async {
      final p = _Profile();
      final c = await open(tester, const NotificationPreferencesScreen(), p);
      p.mode = _P.server;
      c.invalidate(currentUserProfileProvider);
      await settle(tester);
      await tapWorkoutReminders(tester);
      expect(profileWrites(), hasLength(1));
      expect(profileWrites().single, contains('id=eq.user-a'));
      expect(profileWrites().single, contains('"notif_workout_reminders":true'));
      await unmount(tester);
    });
  });

  // ── Settings · unit ───────────────────────────────────────────────────────
  group('Settings unit', () {
    bool selected(WidgetTester tester, String unit) {
      final s = tester.widget<Semantics>(find
          .ancestor(of: find.text(unit), matching: find.byType(Semantics))
          .first);
      return s.properties.selected ?? false;
    }

    for (final observe in [true, false]) {
      final how = observe ? 'sign-out observed' : 'same-frame switch';
      for (final bMode in _P.values) {
        testWidgets("A (LB) → B (KG) ($how), B's read ${bMode.name}: A's unit "
            "is never shown as B's", (tester) async {
          final p = _Profile()..modes['user-b'] = bMode;
          final c = await open(tester, const SettingsScreen(), p);
          expect(selected(tester, 'LB'), isTrue, reason: "precondition: A's LB");
          await switchTo(tester, c, 'user-b', observeSignOut: observe);
          expect(selected(tester, 'LB'), isFalse, reason: "A's unit");
          if (bMode == _P.ok) {
            expect(selected(tester, 'KG'), isTrue, reason: "B's stored unit");
          } else {
            expect(selected(tester, 'KG'), isFalse,
                reason: "B's unit is not known yet");
            await tester.tap(find.text('KG'), warnIfMissed: false);
            await settle(tester);
            expect(profileWrites(), isEmpty, reason: 'locked until B is read');
          }
          await unmount(tester);
        });
      }
    }

    testWidgets("A signs out, nobody signs in: A's unit is not shown",
        (tester) async {
      final c = await open(tester, const SettingsScreen(), _Profile());
      expect(selected(tester, 'LB'), isTrue);
      await switchTo(tester, c, null, observeSignOut: true);
      expect(selected(tester, 'LB'), isFalse, reason: "A's unit");
      await unmount(tester);
    });

    testWidgets('a refresh that FAILS after a good read of the SAME member '
        'keeps the unit', (tester) async {
      final p = _Profile();
      final c = await open(tester, const SettingsScreen(), p);
      p.mode = _P.server;
      c.invalidate(currentUserProfileProvider);
      await settle(tester);
      expect(c.read(currentUserProfileProvider).hasError, isTrue);
      expect(selected(tester, 'LB'), isTrue);
      await unmount(tester);
    });
  });
}
