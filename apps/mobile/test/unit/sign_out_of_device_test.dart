import 'dart:async';

import 'package:circle_fitness/core/identity/account_scope.dart';
import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/account_app.dart';

// P0-FL-59a round 2, item 7 — whether a sign-out that failed left the account on
// the device. gotrue forgets the session in memory first and tells nobody until
// its stored PKCE code is removed: only a refusal there leaves the stored
// session behind.

final _server = AccountServer();
final _store = MemoryStore();
final _stored = MemorySession();
final _failures = <AppFailure>[];

GoTrueClient get _auth => Supabase.instance.client.auth;

Future<Object?> _signOut() => signOutOfDevice('test', _auth.signOut);

/// What supabase_flutter stores follows the event, a turn later.
Future<void> _landed() => Future<void>.delayed(Duration.zero);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initAccountSupabase(_server, FakeRealtime(), _store, session: _stored);
  });

  setUp(() async {
    _server.reset();
    _store.refuseRemoval = false;
    _store.onRefused = null;
    _store.holdRemoval = null;
    _failures.clear();
    setFailureSink(_failures.add);
    addTearDown(resetFailureSink);
    await signInAs(acctA);
    await _landed();
    expect(_stored.who, (acctA, acctA));
  });

  tearDown(() async {
    _server.reset();
    _store.refuseRemoval = false;
    await signOut();
  });

  test('control: signed out, nothing recorded', () async {
    expect(await _signOut(), isNull);
    await _landed();
    expect(_stored.stored, isNull);
    expect(_failures, isEmpty);
  });

  test('the server refuses: signed out all the same, recorded', () async {
    _server.fails['POST logout'] = 500;
    expect(await _signOut(), isNull);
    await _landed();
    expect((_auth.currentSession, _stored.stored), (null, null));
    expect(_failures, hasLength(1));
  });

  test('the server refuses after B has signed in: nothing of B\'s is undone',
      () async {
    _server.fails['POST logout'] = 500;
    final hold = _server.holds['POST logout'] = Completer<void>();
    final out = _signOut();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await signInAs(acctB);
    hold.complete();
    expect(await out, isNull);
    await _landed();
    expect(_auth.currentUser?.id, acctB);
    expect(_stored.who, (acctB, acctB));
  });

  test('the device refuses: the stored session is still there, and it is said',
      () async {
    _store.refuseRemoval = true;
    final error = await _signOut();
    expect(error, isA<StateError>());
    expect(_stored.who, (acctA, acctA), reason: 'why it must be said');
    expect(signOutFailedText(error!), isNot(contains('storage')));
    expect(_failures, hasLength(2));
  });

  test('the device refuses once: tried again, signed out', () async {
    _store.refuseRemoval = true;
    _store.onRefused = () => _store.refuseRemoval = false;
    expect(await _signOut(), isNull);
    await _landed();
    expect(_stored.stored, isNull);
  });

  group('B signs in', () {
    /// Holds the next removal and returns what lets it go.
    Completer<void> holdRemoval() => _store.holdRemoval = Completer<void>();

    Future<List<AuthState>> heardFrom(Future<void> Function() f) async {
      final heard = <AuthState>[];
      final sub = _auth.onAuthStateChange.listen(heard.add);
      await _landed();
      heard.clear(); // the replayed one
      await f();
      await _landed();
      await sub.cancel();
      return heard;
    }

    void expectBs() {
      expect(_auth.currentUser?.id, acctB);
      expect(_stored.who, (acctB, acctB));
      expect(AccountServer.sub(Supabase.instance.client.realtime.accessToken!),
          acctB,
          reason: "realtime is B's");
    }

    test('control: before the second try — there is none, and no sign-out is '
        'announced', () async {
      final hold = holdRemoval();
      _store.refuseRemoval = true;
      Object? error = 'unanswered';
      final heard = await heardFrom(() async {
        final out = _signOut();
        await signInAs(acctB);
        hold.complete();
        error = await out;
      });
      expect(error, isNull);
      expect(heard.map((s) => s.event),
          isNot(contains(AuthChangeEvent.signedOut)));
      expect(_failures, hasLength(1));
      expectBs();
    });

    for (final refusedAgain in [false, true]) {
      test('during the second try${refusedAgain ? ', refused as well' : ''}: '
          "B's app stays B's, and nothing is said to B", () async {
        late Completer<void> hold;
        _store.refuseRemoval = true;
        _store.onRefused = () {
          if (_store.holdRemoval != null) return;
          hold = holdRemoval();
          _store.refuseRemoval = refusedAgain;
        };
        Object? error = 'unanswered';
        final heard = await heardFrom(() async {
          final out = _signOut();
          await _landed();
          await signInAs(acctB);
          hold.complete();
          error = await out;
        });
        expect(error, isNull);
        expect(heard.last.session?.user.id, acctB);
        expect(heard.last.event, isNot(AuthChangeEvent.signedOut));
        for (final s in heard) {
          expect(s.session?.user.id, acctB,
              reason: 'nobody is told that B, or nobody, left: ${s.event}');
        }
        expect(_failures, hasLength(refusedAgain ? 2 : 1));
        expectBs();
      });
    }
  });

  test('the sign-out never began: the session is still there, and it is said',
      () async {
    final error =
        await signOutOfDevice('test', () async => throw StateError('no'));
    expect(error, isNotNull);
    expect(_auth.currentUser?.id, acctA);
  });
}
