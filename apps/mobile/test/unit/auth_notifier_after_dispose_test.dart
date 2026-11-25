import 'dart:async';

import 'package:circle_fitness/features/auth/data/auth_service.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_app.dart';

// P0-FL-59a round 2, item 10 — AccountScope disposes an account's container
// while a sign-out or a second sign-in of its is still out. AuthNotifier set its
// state then ("Tried to use AuthNotifier after `dispose` was called").

class _Service extends AuthService {
  final answers = <Completer<void>>[];

  Future<void> _answer() {
    final c = Completer<void>();
    answers.add(c);
    return c.future;
  }

  @override
  Future<void> signOut() => _answer();
  @override
  Future<void> resetPassword(String email) => _answer();
  @override
  Future<void> signInWithGoogle() => _answer();
  @override
  Future<void> signInWithApple() => _answer();
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _server = AccountServer();

void main() {
  late _Service service;
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initAccountSupabase(_server, FakeRealtime(), MemoryStore());
  });

  setUp(() {
    _server.reset();
    service = _Service();
    container = ProviderContainer(
        overrides: [authServiceProvider.overrideWithValue(service)]);
  });

  final calls = <String, Future<void> Function(AuthNotifier)>{
    'signOut': (n) => n.signOut(),
    'resetPassword': (n) => n.resetPassword('a@b.c'),
    'signInWithGoogle': (n) => n.signInWithGoogle(),
    'signInWithApple': (n) => n.signInWithApple(),
  };

  for (final MapEntry(key: name, value: call) in calls.entries) {
    for (final fails in [false, true]) {
      test('$name ${fails ? 'failing' : 'answering'} after its container is gone',
          () async {
        final done = call(container.read(authNotifierProvider.notifier));
        container.dispose();
        fails
            ? service.answers.single.completeError(StateError('refused'))
            : service.answers.single.complete();
        await done; // threw
      });
    }

    test('control: $name — loading, then its answer', () async {
      final n = container.read(authNotifierProvider.notifier);
      final done = call(n);
      expect(container.read(authNotifierProvider).isLoading, isTrue);
      service.answers.single.completeError(StateError('refused'));
      await done;
      expect(container.read(authNotifierProvider).hasError, isTrue);
      container.dispose();
    });
  }

  for (final (name, call) in [
    ('signIn', (AuthNotifier n) => n.signIn(acctA, 'secret-1')),
    (
      'signUp',
      (AuthNotifier n) => n.signUp(
          email: acctA,
          password: 'secret-1',
          firstName: 'A',
          lastName: 'B',
          role: 'client')
    ),
  ]) {
    test('two ${name}s racing on a container that goes', () async {
      final real = ProviderContainer();
      final hold = _server.holds['POST ${name == 'signIn' ? 'token' : 'signup'}'] =
          Completer<void>();
      final n = real.read(authNotifierProvider.notifier);
      final both = [call(n), call(n)];
      real.dispose();
      hold.complete();
      await Future.wait(both); // threw
      await signOut();
    });
  }
}
