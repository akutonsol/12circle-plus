import 'dart:async';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/owned_rows_postgrest.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60c (e) · `pendingCoachProvider` and `clientRelationshipProvider`
// answered a failed read with null, which means "no pending request" / "no
// relationship" — the answers that offer "Request a coach". The failure is now
// recorded and thrown.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 --` coach_provider.dart.

const _rel = 'coach_client_relationships';

void main() {
  final server = OwnedRowsPostgrest();
  final reported = <AppFailure>[];
  late ProviderContainer c;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
    c = ProviderContainer();
  });

  tearDown(() {
    c.dispose();
    resetFailureSink();
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

  void linked(String uid) {
    server.rows[_rel] = [
      {'id': 'rel-1', 'client_id': uid, 'coach_id': 'coach-1',
       'status': 'pending', 'pending_at': '2026-11-01T00:00:00Z'},
    ];
    server.rows['public_profiles'] = [
      {'id': 'coach-1', 'first_name': 'Cora'},
    ];
  }

  for (final (name, provider) in [
    ('pendingCoachProvider', pendingCoachProvider),
    ('clientRelationshipProvider', clientRelationshipProvider),
  ]) {
    group(name, () {
      setUp(() => c.listen(provider, (_, __) {}));

      test('a failed read is an error, recorded — not "none"', () async {
        linked(memberA);
        server.fails.add('GET $_rel:$memberA');
        c.invalidate(provider);
        await settle();
        expect(c.read(provider), isA<AsyncError<Map<String, dynamic>?>>(),
            reason: 'THE defect: an unread relationship was "no relationship"');
        expect(reported.map((f) => f.origin), contains(name));
        // …and it can be read again.
        server.fails.clear();
        c.invalidate(provider);
        await settle();
        expect(c.read(provider).requireValue, isNotNull);
      });

      test('control: no row is none; a row is read', () async {
        await settle();
        expect(c.read(provider), isA<AsyncData<Map<String, dynamic>?>>());
        expect(c.read(provider).requireValue, isNull);
        linked(memberA);
        c.invalidate(provider);
        await settle();
        expect(c.read(provider).requireValue, isNotNull);
        expect(reported, isEmpty);
      });

      test("A->B: A's held read never lands for B; sign-out is none", () async {
        linked(memberA);
        final hold = server.holds['GET $_rel:$memberA'] = Completer<void>();
        c.invalidate(provider);
        await settle();
        await signInAs(memberB);
        await settle();
        hold.complete();
        await settle();
        expect(c.read(provider).requireValue, isNull);
        await signOut();
        await settle();
        expect(c.read(provider).requireValue, isNull);
        await signInAs(memberA);
        await settle();
        expect(c.read(provider).requireValue, isNotNull, reason: 'A, back again');
      });

      // Round 2 (fails on fd5d076): riverpod keeps the last value through a
      // reload, a failure and an early invalidate.
      Object? value() {
        final s = c.read(provider);
        return s.hasValue ? s.requireValue : null;
      }

      test("B's read pending, then failed: nothing of A's, and not \"none\"",
          () async {
        linked(memberA);
        c.invalidate(provider);
        await settle();
        expect(value(), isNotNull, reason: 'premise');
        final hold = server.holds['GET $_rel:$memberB'] = Completer<void>();
        server.fails.add('GET $_rel:$memberB');
        await signInAs(memberB);
        await settle();
        expect(value(), isNull, reason: "THE defect: A's link was B's");
        expect(c.read(provider).isLoading, isTrue, reason: 'not read is not none');
        hold.complete();
        await settle();
        expect(c.read(provider), isA<AsyncError<Map<String, dynamic>?>>());
        expect(value(), isNull, reason: "THE defect: AsyncError carried A's link");
        expect(reported.map((f) => f.origin), contains(name));
      });

      for (final afterB in [false, true]) {
        test("A's late read ${afterB ? 'after' : 'before'} B's is dropped",
            () async {
          linked(memberA);
          final holdA = server.holds['GET $_rel:$memberA'] = Completer<void>();
          final holdB = server.holds['GET $_rel:$memberB'] = Completer<void>();
          c.invalidate(provider);
          await settle();
          server.rows[_rel]!.add({
            'id': 'rel-b', 'client_id': memberB, 'coach_id': 'coach-1',
            'status': 'pending', 'pending_at': '2026-11-02T00:00:00Z',
          });
          await signInAs(memberB);
          await settle();
          if (afterB) {
            holdB.complete();
            await settle();
            expect(value(), isNotNull);
          }
          holdA.complete();
          await settle();
          if (!afterB) {
            expect(value(), isNull);
            holdB.complete();
            await settle();
          }
          expect('${value()}', contains(
              name == 'pendingCoachProvider' ? '2026-11-02' : 'rel-b'));
        });
      }

      test("an answer landing in the turn the client changes is not kept",
          () async {
        linked(memberA);
        final hold = server.holds['GET $_rel:$memberA'] = Completer<void>();
        c.invalidate(provider);
        await settle();
        hold.complete();
        unawaited(signInAs(memberB)); // the client has B; nobody was told
        await settle();
        expect(server.log.where((a) =>
            a.table == 'public_profiles' && a.who == memberB), isEmpty,
            reason: "A's coach is not read with B's session");
        expect(value(), isNull);
      });

      test('invalidated before the switch is flushed: nothing of A', () async {
        linked(memberA);
        c.invalidate(provider);
        await settle();
        server.holds['GET $_rel:$memberB'] = Completer<void>();
        await signInAs(memberB);
        c.invalidate(provider); // in the same turn, as the app's callers do
        expect(value(), isNull,
            reason: "THE defect: AsyncData(isLoading: true, value: A's)");
        await settle();
        expect(value(), isNull);
        server.holds['GET $_rel:$memberB']!.complete();
        await settle();
        expect(c.read(provider), isA<AsyncData<Map<String, dynamic>?>>());
      });

      test('control: a failed refresh keeps the same member\'s link', () async {
        linked(memberA);
        c.invalidate(provider);
        await settle();
        server.fails.add('GET $_rel:$memberA');
        c.invalidate(provider);
        await settle();
        expect(c.read(provider).hasError, isTrue);
        expect(value(), isNotNull);
      });

      test('control: a token refresh reads nothing again', () async {
        linked(memberA);
        c.invalidate(provider);
        await settle();
        final before = c.read(currentUserProvider);
        final asked = server.log.length;
        await refreshSession();
        await settle();
        expect(identical(c.read(currentUserProvider), before), isFalse);
        expect(server.log.length, asked);
      });
    });
  }

  // The rethrow is safe because nothing shows either provider today: they are
  // only invalidated. A new reader must handle the error — this fails to say so.
  test('no screen reads them yet', () {
    final readers = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (RegExp(r'(?:watch|read|listen\w*)\(\s*(?:pendingCoachProvider|clientRelationshipProvider)\b')
          .hasMatch(f.readAsStringSync())) {
        readers.add(f.path);
      }
    }
    expect(readers, isEmpty,
        reason: 'a reader must show a failure, never "Request a coach"');
  });
}
