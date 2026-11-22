import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:circle_fitness/core/router/app_shell.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';

// P0-FL-44 · a failed role read is never shown as a role fact — the app shell.
//
// `_PersistentNav` chose its bar from
// `currentUserProfileProvider.valueOrNull?['role']`. Since P0-FL-16 that
// provider rethrows, so a COACH whose profile read FAILED (or was still
// LOADING) was null → the CLIENT bottom nav: Home · Workouts · Nutrition ·
// Check-In · Connect, presented to a coach as their own destinations.
//
// Now: read failed (and no earlier successful read) → a compact, non-blocking
// "Couldn't load your account — <next step>" bar with a busy-aware Try again,
// in place of either role's nav; first read still in flight → a neutral bar of
// the same height with no destinations. A successful read is unchanged.
//
// HOW TO SEE IT FAIL: `git checkout df35d5f -- lib/core/router/app_shell.dart`
// — the failed/loading tests find the client destinations.

const _clientTabs = ['Home', 'Workouts', 'Nutrition', 'Check-In', 'Connect'];
const _coachTabs = ['Clients', 'Compliance', 'Programs', 'Check-ins'];

enum _P { ok, network, server, pending }

class _Profile {
  _Profile(this.role);
  String role;
  _P mode = _P.ok;
  int reads = 0;
  Completer<void>? gate;

  Future<Map<String, dynamic>?> read() async {
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
        return <String, dynamic>{'role': role};
    }
  }
}

/// Signed out at the Supabase level, so NotificationWatcher subscribes to
/// nothing; the role comes from the overridden profile provider.
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

  // `/coach-dashboard` keeps the coach top bar out (the dashboard draws its
  // own), so only the bottom nav is under test.
  Future<void> pumpShell(WidgetTester tester, _Profile p,
      {String location = '/coach-dashboard'}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProfileProvider.overrideWith((ref) => p.read()),
      ],
      child: MaterialApp(
        home: AppShell(
          currentLocation: location,
          child: const Text('SCREEN', key: Key('screen')),
        ),
      ),
    ));
    // The coach FAB animates forever: pump, never settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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
    expect(
        find.text("Couldn't load your account — try again in a moment. "
            'If it keeps happening, contact support.'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // Non-blocking: the screen itself is still there.
    expect(find.byKey(const Key('screen')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a network failure gets the connection hint', (tester) async {
    final p = _Profile('coach')..mode = _P.network;
    await pumpShell(tester, p, location: '/home');

    expectNoRoleNav();
    expect(
        find.text(
            "Couldn't load your account — check your connection and try again."),
        findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the failure message is a live region; Try again is ≥44px and '
      'labelled', (tester) async {
    final p = _Profile('coach')..mode = _P.server;
    await pumpShell(tester, p);

    final handle = tester.ensureSemantics();
    final msg = find.text("Couldn't load your account — try again in a moment. "
        'If it keeps happening, contact support.');
    final live = find.ancestor(
        of: msg,
        matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true));
    expect(live, findsWidgets);
    expect(find.bySemanticsLabel('Try again, load your account'),
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
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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
}
