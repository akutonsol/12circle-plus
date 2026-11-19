import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/profile_read_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-16 · currentUserProfileProvider ended `catch (e) { return null; }`, so
// a failed read was the same `null` as "this member has no profile row".
// Profile showed "Member" defaults, Settings showed "KG" as the stored unit and
// the edit forms pre-filled with nothing.
//
// HOW TO SEE IT FAIL: with the base commit's auth_provider.dart the two failure
// tests get `null` (no error) and nothing is reported.

const _uid = '00000000-0000-4000-8000-0000000f1016';

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

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      currentUserProvider
          .overrideWithValue(Supabase.instance.client.auth.currentUser),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('a network failure is an error, not "no profile", and is recorded',
      () async {
    server.profileRead = ProfileRead.network;
    final c = container();
    await expectLater(c.read(currentUserProfileProvider.future),
        throwsA(isA<http.ClientException>()));
    expect(c.read(currentUserProfileProvider), isA<AsyncError>(),
        reason: 'THE defect: a failed read arrived as AsyncData(null)');
    expect(reported.map((f) => f.origin), ['currentUserProfileProvider']);
  });

  test('a server error is an error too, and is recorded', () async {
    server.profileRead = ProfileRead.serverError;
    final c = container();
    await expectLater(c.read(currentUserProfileProvider.future),
        throwsA(isA<PostgrestException>()));
    expect(reported.map((f) => f.origin), ['currentUserProfileProvider']);
  });

  test('control: no profile row is still null, and nothing is reported',
      () async {
    server.profile = null;
    final c = container();
    expect(await c.read(currentUserProfileProvider.future), isNull);
    expect(server.profileReads, 1, reason: 'premise: the read happened');
    expect(reported, isEmpty);
  });

  test('control: a stored row is returned as before', () async {
    server.profile = {'id': _uid, 'first_name': 'Ana', 'role': 'client'};
    final c = container();
    final p = await c.read(currentUserProfileProvider.future);
    expect(p?['first_name'], 'Ana');
    expect(reported, isEmpty);
  });

  test('control: signed out is null without a read', () async {
    final c = ProviderContainer(
        overrides: [currentUserProvider.overrideWithValue(null)]);
    addTearDown(c.dispose);
    expect(await c.read(currentUserProfileProvider.future), isNull);
    expect(server.profileReads, 0);
  });
}
