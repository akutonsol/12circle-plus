import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/router/app_router.dart';
import 'package:circle_fitness/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-15 — sign-in routing never guesses after a failed account read.
//
// Both the login screen's post-sign-in routing and the router's redirect read
// `user_profiles.role` to choose where a signed-in user lands. Both caught a
// failed read and sent the user to '/home' — so a coach, admin or vendor whose
// read failed was dropped into the CLIENT app. Now a failed read routes to no
// role surface: the user stays on the sign-in screen with "Couldn't load your
// account — …", a busy-aware Try again and Sign out. A successful read
// (including a missing row → 'client', and onboarding_complete == false →
// /intake) routes exactly as before.

const _uid = '00000000-0000-4000-8000-0000000000f1';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': _uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
      'not-verified-client-side';
}

Map<String, Object?> _session() => {
      'access_token': _jwt(),
      'token_type': 'bearer',
      'expires_in': 315360000,
      'refresh_token': 'test-refresh',
      'user': {
        'id': _uid,
        'email': 'member@example.com',
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    };

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

enum _Read { row, missingRow, network, serverError }

/// Fake auth + PostgREST. The profile read is what every test steers.
class _Server extends http.BaseClient {
  _Read profile = _Read.row;
  String role = 'client';
  Object? onboardingComplete = true;
  int profileReads = 0;

  /// When set, profile reads are counted at once but not answered until it
  /// completes — a read "in flight".
  Completer<void>? gate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/auth/v1/token')) return _json(_session(), 200, request);
    if (path.endsWith('/auth/v1/logout')) {
      return http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (path.endsWith('/user_profiles')) {
      profileReads++;
      if (gate != null) await gate!.future;
      switch (profile) {
        case _Read.network:
          throw http.ClientException('Connection refused', request.url);
        case _Read.serverError:
          return _json({'message': 'boom-internal-detail', 'code': 'XX000'}, 500, request);
        case _Read.missingRow:
          return _json(single ? null : [], 200, request);
        case _Read.row:
          final row = {'role': role, 'onboarding_complete': onboardingComplete};
          return _json(single ? row : [row], 200, request);
      }
    }
    return _json(single ? null : [], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

const _connectionMsg = "Couldn't load your account — check your connection and try again.";
const _supportMsg =
    "Couldn't load your account — try again in a moment. If it keeps happening, contact support.";

/// The login screen alone, behind a router that does no redirecting: every
/// other path is a placeholder naming itself, so the screen's own routing is
/// what is observed.
GoRouter _loginOnlyRouter() => GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        for (final p in [
          '/home',
          '/coach-dashboard',
          '/admin-dashboard',
          '/vendor-portal',
          '/intake',
          '/signup',
          '/forgot-password',
        ])
          GoRoute(path: p, builder: (_, __) => Scaffold(body: Text('PAGE $p'))),
      ],
    );

String _path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

/// No redirect loop: once settled, more time brings no more reads, no move and
/// no go_router loop error.
Future<void> _expectNoLoop(WidgetTester tester, _Server server, GoRouter router) async {
  final reads = server.profileReads;
  final path = _path(router);
  await _settle(tester);
  expect(server.profileReads, reads, reason: 'a redirect loop keeps re-reading');
  expect(_path(router), path);
  expect(tester.takeException(), isNull);
}

/// Advances fake time far enough for the client's own back-off on a
/// connection failure to give up (it retries a ClientException before it
/// surfaces), then lets the frames settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  late _Server server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
      debug: false,
    );
  });

  setUp(() {
    server
      ..profile = _Read.row
      ..role = 'client'
      ..onboardingComplete = true
      ..profileReads = 0
      ..gate = null;
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> signIn() async {
    await Supabase.instance.client.auth
        .signInWithPassword(email: 'member@example.com', password: 'pw');
    expect(Supabase.instance.client.auth.currentSession, isNotNull);
  }

  Future<void> signOut() async {
    if (Supabase.instance.client.auth.currentSession != null) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  Future<GoRouter> pumpLogin(WidgetTester tester) async {
    final router = _loginOnlyRouter();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await _settle(tester);
    return router;
  }

  Future<void> emailSignIn(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'member@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.text('Sign in'));
    await _settle(tester);
  }

  group('LoginScreen — post-sign-in routing', () {
    testWidgets('email sign-in whose account read FAILS stays on sign-in with the notice, '
        'not /home', (tester) async {
      await signOut();
      server.profile = _Read.network;
      final router = await pumpLogin(tester);
      await emailSignIn(tester);

      expect(_path(router), '/login',
          reason: 'THE defect: a failed role read routed to /home (the client app)');
      expect(find.text(_connectionMsg), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(reported.map((f) => f.origin),
          contains('LoginScreen._handlePostAuthNavigation'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a signed-in user left on /login gets the read, the notice (server wording, '
        'no exception text) and Try again routes a COACH once the read recovers',
        (tester) async {
      await signIn();
      server.profile = _Read.serverError;
      final router = await pumpLogin(tester);

      expect(_path(router), '/login');
      expect(find.text(_supportMsg), findsOneWidget);
      expect(find.textContaining('boom-internal-detail'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      final live = tester.getSemantics(find.byKey(const Key('login-account-read-failure')));
      expect(live.flagsCollection.isLiveRegion, isTrue,
          reason: 'the failure notice is announced');

      server
        ..profile = _Read.row
        ..role = 'coach';
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(_path(router), '/coach-dashboard');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Try again is busy-aware: one read in flight however many taps, >= 44pt',
        (tester) async {
      await signIn();
      server.profile = _Read.network;
      final router = await pumpLogin(tester);
      expect(find.text(_connectionMsg), findsOneWidget);
      expect(tester.getSize(find.ancestor(of: find.text('Try again'),
              matching: find.byType(Container)).first).height,
          greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(const Key('login-account-read-sign-out'))).height,
          greaterThanOrEqualTo(44));

      server.profileReads = 0;
      server.gate = Completer<void>();
      server.profile = _Read.row;
      server.role = 'admin';
      await tester.tap(find.text('Try again'));
      await tester.pump();
      // In flight: the button shows progress and takes no tap.
      expect(find.text('Try again'), findsNothing);
      expect(find.text(_connectionMsg), findsOneWidget,
          reason: 'the notice stays up while the retry runs');
      await tester.tap(find.byType(CircularProgressIndicator), warnIfMissed: false);
      await tester.pump();
      expect(server.profileReads, 1);

      server.gate!.complete();
      await _settle(tester);
      expect(_path(router), '/admin-dashboard');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a session that ARRIVES while the screen is up (OAuth return) whose read '
        'fails gets the notice, not a bare sign-in form', (tester) async {
      await signOut();
      server.profile = _Read.serverError;
      final router = await pumpLogin(tester);
      expect(find.text('Sign in'), findsOneWidget);
      await tester.runAsync(signIn);
      await _settle(tester);
      expect(_path(router), '/login');
      expect(find.text(_supportMsg), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Sign out from the failure leaves the session and shows the sign-in form',
        (tester) async {
      await signIn();
      server.profile = _Read.network;
      final router = await pumpLogin(tester);
      expect(find.text(_connectionMsg), findsOneWidget);

      await tester.tap(find.text('Sign out'));
      await _settle(tester);
      expect(Supabase.instance.client.auth.currentSession, isNull);
      expect(find.text(_connectionMsg), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);
      expect(_path(router), '/login');
      await tester.pumpWidget(const SizedBox());
    });

    // UNCHANGED: a successful read routes exactly as today.
    final cases = <(String, _Read, String, Object?, String)>[
      ('coach', _Read.row, 'coach', true, '/coach-dashboard'),
      ('admin', _Read.row, 'admin', true, '/admin-dashboard'),
      ('vendor', _Read.row, 'vendor', true, '/vendor-portal'),
      ('client', _Read.row, 'client', true, '/home'),
      ('client mid-onboarding', _Read.row, 'client', false, '/intake'),
      ('client, onboarding never set', _Read.row, 'client', null, '/home'),
      ('missing profile row (client default)', _Read.missingRow, 'client', true, '/home'),
    ];
    for (final (name, read, role, onboarding, expected) in cases) {
      testWidgets('email sign-in, $name → $expected', (tester) async {
        await signOut();
        server
          ..profile = read
          ..role = role
          ..onboardingComplete = onboarding;
        final router = await pumpLogin(tester);
        await emailSignIn(tester);
        expect(_path(router), expected);
        expect(reported, isEmpty);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('router redirect — signed-in user on an auth route', () {
    Future<GoRouter> pumpApp(WidgetTester tester, String location) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      router.go(location);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await _settle(tester);
      return router;
    }

    testWidgets('a failed read on /login does not guess /home: stays, and the screen says why',
        (tester) async {
      await signIn();
      server.profile = _Read.network;
      final router = await pumpApp(tester, '/login');
      expect(_path(router), '/login',
          reason: 'THE defect: the redirect returned /home after a failed read');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text(_connectionMsg), findsOneWidget);
      expect(reported.map((f) => f.origin), contains('appRouter.redirect.roleRead'));
      await _expectNoLoop(tester, server, router);
      await tester.pumpWidget(const SizedBox());
    });

    for (final from in ['/signup', '/onboarding']) {
      testWidgets('a failed read on $from lands on /login with the notice, not /home',
          (tester) async {
        await signIn();
        server.profile = _Read.serverError;
        final router = await pumpApp(tester, from);
        expect(_path(router), '/login');
        expect(find.text(_supportMsg), findsOneWidget);
        await _expectNoLoop(tester, server, router);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('after the read recovers, Try again routes a VENDOR to the vendor portal',
        (tester) async {
      await signIn();
      server.profile = _Read.network;
      final router = await pumpApp(tester, '/login');
      expect(find.text(_connectionMsg), findsOneWidget);
      server
        ..profile = _Read.row
        ..role = 'vendor';
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(_path(router), '/vendor-portal');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('/intake early return is unchanged (the redirect reads nothing)', (tester) async {
      await signIn();
      server.profile = _Read.network;
      final router = await pumpApp(tester, '/intake');
      expect(_path(router), '/intake');
      // The intake screen reads its own profile; the redirect must not.
      expect(reported.map((f) => f.origin), isNot(contains('appRouter.redirect.roleRead')));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('/forgot-password early return is unchanged (no read)', (tester) async {
      await signIn();
      server.profile = _Read.network;
      final router = await pumpApp(tester, '/forgot-password');
      expect(_path(router), '/forgot-password');
      expect(server.profileReads, 0);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
