import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:circle_fitness/core/router/app_shell.dart';
import 'package:circle_fitness/core/widgets/app_top_nav.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';

// P0-FL-44 · a failed role read is never shown as a role fact — the app shell.
//
// `_PersistentNav` chose its bar from
// `currentUserProfileProvider.valueOrNull?['role']`. Since P0-FL-16 that
// provider rethrows, so a COACH whose profile read FAILED (or was still
// LOADING) was null → the CLIENT bottom nav: Home · Workouts · Nutrition ·
// Check-In · Connect, presented to a coach as their own destinations.
//
// Now: read failed (and no earlier successful read of THIS member) → a
// compact, non-blocking "Couldn't load your profile — <next step>" bar (the
// shared notice's wording) with a busy-aware Try again and ONE role-neutral
// destination, Profile; first read still in flight → a neutral bar of the same
// height with a small progress indicator and no destinations. A successful
// read is unchanged.
//
// Review round (SEC-F1/F2): Riverpod keeps the previous value through a
// re-read, so after member A (coach) signs out and member B signs in, a FAILED
// read for B still `hasValue` — A's role. A value now counts only when it was
// read for the member signed in now (`id` == current user id).
//
// HOW TO SEE IT FAIL: `git checkout df35d5f -- lib/core/router/app_shell.dart`
// (the original defect) or `git checkout HEAD~1 -- lib/core/router/app_shell.dart`
// (the review-round items).

const _clientTabs = ['Home', 'Workouts', 'Nutrition', 'Check-In', 'Connect'];
const _coachTabs = ['Clients', 'Compliance', 'Programs', 'Check-ins'];

const _failedMsg = "Couldn't load your profile — try again in a moment. "
    'If it keeps happening, contact support.';
const _offlineMsg =
    "Couldn't load your profile — check your connection and try again.";

enum _P { ok, network, server, pending }

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    );

final _signedIn = StateProvider<User?>((ref) => _user('user-a'));

/// The profile read, controllable per test; each member has their own role.
class _Profile {
  _Profile(String role) : roles = {'user-a': role};
  final Map<String, String> roles;
  _P mode = _P.ok;
  int reads = 0;
  Completer<void>? gate;

  Future<Map<String, dynamic>?> read(String uid) async {
    reads++;
    if (gate != null) await gate!.future;
    switch (mode) {
      case _P.network:
        throw http.ClientException('Connection refused');
      case _P.server:
        throw const PostgrestException(message: 'refused', code: 'XX000');
      case _P.pending:
        return Completer<Map<String, dynamic>?>().future;
      case _P.ok:
        return <String, dynamic>{'id': uid, 'role': roles[uid]};
    }
  }
}

/// Signed out at the Supabase level, so NotificationWatcher subscribes to
/// nothing; the member comes from the overridden `currentUserProvider` and the
/// role from the overridden profile provider.
class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
          request: request, headers: {'content-type': 'application/json'});
}

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _EmptyClient(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  Future<void> settle(WidgetTester tester) async {
    // The coach FAB and the pending indicator animate forever: pump, never
    // settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // `/coach-dashboard` keeps the coach top bar out (the dashboard draws its
  // own), so only the bottom nav is under test unless a test says otherwise.
  Future<ProviderContainer> pumpShell(WidgetTester tester, _Profile p,
      {String location = '/coach-dashboard'}) async {
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
      currentUserProfileProvider.overrideWith((ref) async {
        final u = ref.watch(currentUserProvider);
        if (u == null) return null;
        return p.read(u.id);
      }),
      // AppTopNav (coach top bar) reads these; keep them off the network.
      unreadCountProvider.overrideWith((ref) async => 0),
    ]);
    addTearDown(container.dispose);
    GoRoute page(String path) => GoRoute(
          path: path,
          builder: (_, state) => AppShell(
            currentLocation: state.uri.path,
            child: Text('SCREEN $path', key: const Key('screen')),
          ),
        );
    final router = GoRouter(initialLocation: location, routes: [
      page('/coach-dashboard'),
      page('/home'),
      page('/compliance'),
      page('/profile'),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle(tester);
    return container;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  void expectNoRoleNav() {
    for (final t in [..._clientTabs, ..._coachTabs]) {
      expect(find.text(t), findsNothing,
          reason: '"$t" is a role destination — the role is not known');
    }
  }

  testWidgets('a FAILED role read shows the failure bar, not the client nav',
      (tester) async {
    final p = _Profile('coach')..mode = _P.server;
    await pumpShell(tester, p);

    expectNoRoleNav();
    expect(find.text(_failedMsg), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // Non-blocking: the screen itself is still there.
    expect(find.byKey(const Key('screen')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a network failure gets the connection hint', (tester) async {
    final p = _Profile('coach')..mode = _P.network;
    await pumpShell(tester, p, location: '/home');

    expectNoRoleNav();
    expect(find.text(_offlineMsg), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('UX-F3 · one noun for one failure: "your profile", as the shared '
      'notice says — never "your account"', (tester) async {
    final p = _Profile('coach')..mode = _P.server;
    await pumpShell(tester, p);
    expect(find.textContaining("Couldn't load your profile"), findsOneWidget);
    expect(find.textContaining("Couldn't load your account"), findsNothing);
    await unmount(tester);
  });

  testWidgets('the failure message is a live region; Try again is ≥44px and '
      'labelled', (tester) async {
    final p = _Profile('coach')..mode = _P.server;
    await pumpShell(tester, p);

    final handle = tester.ensureSemantics();
    final live = find.ancestor(
        of: find.text(_failedMsg),
        matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true));
    expect(live, findsWidgets);
    expect(find.bySemanticsLabel('Try again, load your profile'),
        findsOneWidget);
    final button = find.ancestor(
        of: find.text('Try again'), matching: find.byType(TextButton));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    handle.dispose();
    await unmount(tester);
  });

  testWidgets('Try again re-reads once while busy, then shows the real nav',
      (tester) async {
    final p = _Profile('coach')..mode = _P.server;
    await pumpShell(tester, p);
    expect(p.reads, 1);

    p
      ..mode = _P.ok
      ..gate = Completer<void>();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('Loading…'), findsOneWidget);
    await tester.tap(find.text('Loading…'), warnIfMissed: false);
    await tester.pump();
    expect(p.reads, 2, reason: 'no double fire while busy');
    expectNoRoleNav();

    p.gate!.complete();
    await settle(tester);
    for (final t in _coachTabs) {
      expect(find.text(t), findsOneWidget);
    }
    await unmount(tester);
  });

  testWidgets('while the first read is LOADING no role nav is shown',
      (tester) async {
    final p = _Profile('coach')..mode = _P.pending;
    await pumpShell(tester, p);
    expectNoRoleNav();
    expect(find.text('Try again'), findsNothing,
        reason: 'loading is not a failure');
    await unmount(tester);
  });

  testWidgets('UX-F5 · the pending bar shows a progress indicator and keeps '
      'its label (no blank bar)', (tester) async {
    final p = _Profile('coach')..mode = _P.pending;
    await pumpShell(tester, p);
    final handle = tester.ensureSemantics();
    expect(find.byKey(const Key('nav-pending-progress')), findsOneWidget);
    expect(find.bySemanticsLabel('Loading your account'), findsOneWidget);
    handle.dispose();
    await unmount(tester);
  });

  testWidgets('a successful coach read: the coach nav, unchanged',
      (tester) async {
    await pumpShell(tester, _Profile('coach'));
    for (final t in _coachTabs) {
      expect(find.text(t), findsOneWidget);
    }
    for (final t in _clientTabs) {
      expect(find.text(t), findsNothing);
    }
    expect(find.textContaining("Couldn't load"), findsNothing);
    await unmount(tester);
  });

  testWidgets('a successful client read: the client nav, unchanged',
      (tester) async {
    await pumpShell(tester, _Profile('client'), location: '/home');
    for (final t in _clientTabs) {
      expect(find.text(t), findsOneWidget);
    }
    for (final t in _coachTabs) {
      expect(find.text(t), findsNothing);
    }
    expect(find.textContaining("Couldn't load"), findsNothing);
    await unmount(tester);
  });

  // ── Review round ───────────────────────────────────────────────────────────

  testWidgets(
      'SEC-F1/F2 · coach A signs out, member B signs in and B\'s read FAILS: '
      'no coach nav, no coach top bar — B sees the failure state',
      (tester) async {
    final p = _Profile('coach')..roles['user-b'] = 'client';
    final c = await pumpShell(tester, p, location: '/compliance');
    // A's read succeeded: A's coach nav and coach top bar.
    for (final t in _coachTabs) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.byType(AppTopNav), findsOneWidget);

    c.read(_signedIn.notifier).state = null; // sign out
    await settle(tester);
    p.mode = _P.server;
    c.read(_signedIn.notifier).state = _user('user-b'); // B signs in
    await settle(tester);

    expect(c.read(currentUserProfileProvider).hasValue, isTrue,
        reason: 'precondition: Riverpod kept a previous value through the '
            'failed re-read — the leak the fix closes');
    expectNoRoleNav();
    expect(find.byType(AppTopNav), findsNothing,
        reason: "the coach top bar is A's, not B's");
    expect(find.text(_failedMsg), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
      'SEC-F1/F2 · A\'s value is not B\'s role while B\'s read is in flight',
      (tester) async {
    final p = _Profile('coach')..roles['user-b'] = 'client';
    final c = await pumpShell(tester, p);
    for (final t in _coachTabs) {
      expect(find.text(t), findsOneWidget);
    }
    p.mode = _P.pending;
    c.read(_signedIn.notifier).state = _user('user-b');
    await settle(tester);
    expectNoRoleNav();
    expect(find.byKey(const Key('nav-pending-progress')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
      'QA · a refresh that fails AFTER a successful read of the SAME member '
      'keeps that member\'s coach nav', (tester) async {
    final p = _Profile('coach');
    final c = await pumpShell(tester, p);
    for (final t in _coachTabs) {
      expect(find.text(t), findsOneWidget);
    }
    p.mode = _P.server;
    c.invalidate(currentUserProfileProvider);
    await settle(tester);
    expect(c.read(currentUserProfileProvider).hasError, isTrue,
        reason: 'precondition: the refresh really failed');
    for (final t in _coachTabs) {
      expect(find.text(t), findsOneWidget,
          reason: 'the role came from a real read of this member');
    }
    expect(find.textContaining("Couldn't load"), findsNothing);
    await unmount(tester);
  });

  testWidgets(
      'UX-F1 · the failure bar keeps ONE role-neutral destination: Profile '
      '(≥44px, labelled) — and it goes there', (tester) async {
    final p = _Profile('coach')..mode = _P.server;
    await pumpShell(tester, p, location: '/compliance');
    expectNoRoleNav();
    expect(find.text('Profile'), findsOneWidget);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Go to your profile'), findsOneWidget);
    handle.dispose();
    final button = find.ancestor(
        of: find.text('Profile'), matching: find.byType(TextButton));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));

    await tester.tap(find.text('Profile'));
    await settle(tester);
    expect(find.text('SCREEN /profile'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('UX-F2 · textScale 2.0 on a 320dp phone: the failure bar does '
      'not overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final p = _Profile('coach')..mode = _P.network;
    await pumpShell(tester, p, location: '/home');
    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    expect(find.text(_offlineMsg), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    // Both actions are fully on screen.
    for (final label in ['Try again', 'Profile']) {
      final r = tester.getRect(find.text(label));
      expect(r.right, lessThanOrEqualTo(320));
      expect(r.left, greaterThanOrEqualTo(0));
    }
    await unmount(tester);
  });
}
