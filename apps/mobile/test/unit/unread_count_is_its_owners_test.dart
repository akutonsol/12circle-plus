import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/owned_rows_postgrest.dart';
import '../support/quiet_realtime.dart';
import '../support/settled.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60c round 2 (B3) · The bell badge reads `unreadCountProvider` with
// `.valueOrNull`, and riverpod carries the last value through loading and error:
// member A's unread count stayed up while member B's was read, and when that
// read failed (unrecorded). `notificationsStreamProvider` kept A's rows the same
// way, after sign-out too.
//
// The REAL providers, over real auth transitions. HOW TO SEE IT FAIL:
// `git checkout fd5d076 --` notification_provider.dart, notification_service.dart,
// notifications_screen.dart.

const _t = 'notifications';

Map<String, Object?> _n(String id, String uid) => {
      'id': id, 'recipient_id': uid, 'type': 'general', 'title': id,
      'body': 'Body', 'read': false,
      'created_at': '2026-11-20T10:00:00Z',
    };

void main() {
  final server = OwnedRowsPostgrest();
  final reported = <AppFailure>[];
  late ProviderContainer c;

  /// What listeners of the count were told, with who was signed in as they were.
  late List<(String?, int?)> told;

  String? signedIn() => Supabase.instance.client.auth.currentUser?.id;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabaseQuietly(server);
  });

  Future<void> settle() => settled(server);

  setUp(() async {
    server.reset();
    server.rows[_t] = [
      _n('a-1', memberA), _n('a-2', memberA), _n('b-1', memberB),
    ];
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
    c = ProviderContainer();
    told = [];
    c.listen(unreadCountProvider, (_, AsyncValue<int?> v) {
      told.add((signedIn(), v.hasValue ? v.requireValue : null));
    }, fireImmediately: true);
    await settle();
  });

  tearDown(() {
    c.dispose();
    resetFailureSink();
  });

  AsyncValue<int?> state() => c.read(unreadCountProvider);
  int? count() {
    final s = state();
    return s.hasValue ? s.requireValue : null;
  }

  List<String> rows() {
    final s = c.read(notificationsStreamProvider);
    return s.hasValue ? [for (final n in s.requireValue) n.id] : const [];
  }

  Iterable<Asked> counts(String uid) => server.log.where((a) =>
      a.table == _t && a.method == 'GET' && a.who == uid && a.query['select'] == 'id');

  void expectNothingOfAsTold(int from) {
    expect(
        told.skip(from).where((t) => t.$1 != memberA && t.$2 == 2), isEmpty,
        reason: "THE defect: a listener was told A's count after A had gone");
  }

  test('control: each member is told their own', () async {
    await eventually(count, 2);
    await eventually(rows, containsAll(['a-1', 'a-2']));
    await signInAs(memberB);
    await eventually(count, 1);
    await eventually(rows, ['b-1']);
    await eventually(() => told.last.$2, 1);
    await settle();
    expect(reported, isEmpty);
  });

  test('control: none unread is 0, not unknown', () async {
    server.rows[_t] = [];
    c.invalidate(unreadCountProvider);
    await settle();
    await eventually(count, 0);
    expect(state(), isA<AsyncData<int?>>());
  });

  test("B's read pending: nothing of A's, and the badge is told", () async {
    server.holds['GET $_t:$memberB'] = Completer<void>();
    final from = told.length;
    await signInAs(memberB);
    await settle();
    expect(count(), isNull, reason: "THE defect: A's count was B's");
    expect(rows(), isEmpty, reason: "THE defect: A's rows were kept for B");
    expect(told.length, greaterThan(from));
    expect(told.last.$2, isNull);
    expectNothingOfAsTold(from);
    server.holds['GET $_t:$memberB']!.complete();
    await eventually(count, 1);
  });

  test("A's refresh pending when B signs in: the badge is told all the same",
      () async {
    final holdA = server.holds['GET $_t:$memberA'] = Completer<void>();
    server.holds['GET $_t:$memberB'] = Completer<void>();
    c.invalidate(unreadCountProvider);
    await settle();
    await eventually(() => state().isLoading, isTrue, reason: 'premise');
    final from = told.length;
    await signInAs(memberB);
    await settle();
    await eventually(() => told.length, greaterThan(from),
        reason: 'loading -> loading is not announced by riverpod');
    expect(told.last.$2, isNull);
    holdA.complete();
    server.holds['GET $_t:$memberB']!.complete();
    await eventually(count, 1);
  });

  test("B's read failed: an error, recorded, and nothing of A's", () async {
    server.fails.add('GET $_t:$memberB');
    final from = told.length;
    await signInAs(memberB);
    await settle();
    await eventually(() => state().hasError, isTrue);
    expect(count(), isNull, reason: "THE defect: AsyncError carried A's count");
    expect(rows(), isEmpty);
    expect(reported.map((f) => f.origin), contains('unreadCountProvider'),
        reason: 'THE defect: unrecorded');
    expectNothingOfAsTold(from);
  });

  test('sign-out: nothing; A again: their own, read again', () async {
    final from = told.length;
    await signOut();
    await settle();
    expect(count() ?? 0, 0);
    expect(rows(), isEmpty, reason: "THE defect: A's rows outlived sign-out");
    expectNothingOfAsTold(from);
    server.rows[_t]!.add(_n('a-3', memberA));
    await signInAs(memberA);
    await settle();
    await eventually(count, 3);
    await eventually(rows, hasLength(3));
  });

  for (final afterB in [false, true]) {
    test("A's late answer ${afterB ? 'after' : 'before'} B's is dropped",
        () async {
      final holdA = server.holds['GET $_t:$memberA'] = Completer<void>();
      final holdB = server.holds['GET $_t:$memberB'] = Completer<void>();
      c.invalidate(unreadCountProvider);
      await settle();
      final from = told.length;
      await signInAs(memberB);
      await settle();
      if (afterB) {
        holdB.complete();
        await eventually(count, 1);
      }
      holdA.complete();
      await settle();
      expect(count(), afterB ? 1 : isNull);
      expect(rows(), afterB ? ['b-1'] : isEmpty);
      if (!afterB) holdB.complete();
      await eventually(count, 1);
      await settle();
      expect(count(), 1);
      expectNothingOfAsTold(from);
    });
  }

  test('invalidated before the account change is flushed: still nothing of A',
      () async {
    server.holds['GET $_t:$memberB'] = Completer<void>();
    final from = told.length;
    await signInAs(memberB);
    // In the same turn: riverpod has the change queued, not flushed, and takes
    // what follows for a refresh of the same value.
    c.invalidate(unreadCountProvider);
    c.invalidate(notificationsStreamProvider);
    expect(count(), isNull,
        reason: "THE defect: AsyncData(isLoading: true, value: A's)");
    expect(rows(), isEmpty);
    await settle();
    expect(count(), isNull);
    expectNothingOfAsTold(from);
    server.holds['GET $_t:$memberB']!.complete();
    await eventually(count, 1);
  });

  test("A's count landing in the turn the client changes is told to nobody",
      () async {
    final hold = server.holds['GET $_t:$memberA'] = Completer<void>();
    c.invalidate(unreadCountProvider);
    await settle();
    final from = told.length;
    hold.complete();
    unawaited(signInAs(memberB)); // the client has B; nobody was told
    expect(signedIn(), memberB, reason: 'premise');
    await eventually(count, 1);
    await settle();
    expectNothingOfAsTold(from);
    expect(count(), 1);
    expect(
        reported.where((f) =>
            f.origin == 'unreadCountProvider' &&
            '${f.error}'.contains('the signed-in account changed')),
        hasLength(1));
  });

  test("a feed read that lands with B signed in is not A's badge's news",
      () async {
    // Nothing of the container is flushed between the switch and the answer.
    final hold = server.holds['GET $_t:$memberA'] = Completer<void>();
    final own = ProviderContainer();
    addTearDown(own.dispose);
    final emitted = <List<String>>[];
    own.listen(notificationsStreamProvider, (_, v) {
      if (v.hasValue) emitted.add([for (final n in v.requireValue) n.id]);
    });
    await settle();
    unawaited(signInAs(memberB)); // the client has B at once
    expect(signedIn(), memberB, reason: 'premise');
    hold.complete();
    await settle();
    expect(emitted.where((l) => l.contains('a-1')), isEmpty);
  });

  test('control: a failed refresh keeps the same member\'s count, recorded',
      () async {
    server.fails.add('GET $_t:$memberA');
    c.invalidate(unreadCountProvider);
    await settle();
    await eventually(() => counts(memberA).length, greaterThan(1),
        reason: 'it was read again');
    await eventually(() => state().hasError, isTrue);
    expect(count(), 2);
    expect(reported.map((f) => f.origin), contains('unreadCountProvider'));
    server.fails.clear();
    c.invalidate(unreadCountProvider);
    await settle();
    await eventually(() => state().hasError, isFalse);
    expect(count(), 2);
  });

  test('control: a token refresh reads nothing again', () async {
    final before = c.read(currentUserProvider);
    final asked = server.log.length;
    final from = told.length;
    await refreshSession();
    await eventually(
        () => identical(c.read(currentUserProvider), before), isFalse,
        reason: 'premise: the event arrived');
    await settle();
    expect(server.log.length, asked,
        reason: 'the feed was opened, or the count read, again');
    expect(told.length, from);
    expect(count(), 2);
    expect(rows(), hasLength(2));
  });
}
