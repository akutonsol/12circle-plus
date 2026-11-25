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
