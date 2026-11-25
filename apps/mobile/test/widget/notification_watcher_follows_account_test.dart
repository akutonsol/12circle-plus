import 'dart:async';

import 'package:circle_fitness/core/notifications/notification_watcher.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/account_app.dart';

// P0-FL-59a (e) — NotificationWatcher follows the signed-in account (A-31 / S3).
//
// It looked at the account only in build: a sign-out returned early and kept
// A's subscription open, and the next account got no notifications (and none of
// the refreshes they carry) until something happened to rebuild it. These mount
// it WITHOUT AccountScope and never rebuild it.

final _server = AccountServer();
final _realtime = FakeRealtime();

Map<String, Object?> _note(String id, String to) => {
      'id': id,
      'recipient_id': to,
      'type': 'program_assigned',
      'title': 'assigned',
      'body': '',
      'read': false,
      'created_at': '2026-11-12T10:00:00Z',
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initAccountSupabase(_server, _realtime, MemoryStore());
  });
  setUp(_server.reset);

  Future<int Function()> mount(WidgetTester t, String? as) async {
    await t.runAsync(signOut);
    if (as != null) await t.runAsync(() => signInAs(as));
    var reads = 0;
    await t.pumpWidget(ProviderScope(
      overrides: [
        assignedWorkoutsProvider.overrideWith((ref) async {
          reads++;
          return const <Workout>[];
        }),
      ],
      child: MaterialApp(
        home: NotificationWatcher(
          child: Consumer(builder: (_, ref, __) {
            ref.watch(assignedWorkoutsProvider);
            return const SizedBox();
          }),
        ),
      ),
    ));
    await settleApp(t, 4);
    return () => reads;
  }

  Future<void> change(WidgetTester t, Future<void> Function() f) async {
    await t.runAsync(f);
    // Frames, but nothing that rebuilds the watcher.
    await settleApp(t, 4);
  }

  void watcherTest(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (t) async {
        try {
          await body(t);
        } finally {
          await unmountApp(t, _server);
        }
      });

  for (final (what, f) in [
    ('sign-out', signOut),
    ('remote sign-out', () => expire(_server)),
  ]) {
    watcherTest('$what drops A\'s subscription', (t) async {
      final reads = await mount(t, acctA);
      expect(_realtime.joinedFor(acctA), hasLength(1), reason: 'premise');
      await change(t, f);
      expect(_realtime.joinedFor(acctA), isEmpty);
      final before = reads();
      _realtime.notify(_note('n1', acctA));
      await settleApp(t, 4);
      expect(reads(), before);
      await t.pump(const Duration(minutes: 3));
      expect(_realtime.joinedFor(acctA), isEmpty, reason: 'and no retry of it');
    });
  }

  for (final (what, path) in [
    ('A -> B', [() => signInAs(acctB)]),
    ('A -> signed out -> B', [signOut, () => signInAs(acctB)]),
  ]) {
    watcherTest('$what: B\'s notifications arrive with no rebuild, A\'s never',
        (t) async {
      final reads = await mount(t, acctA);
      for (final f in path) {
        await change(t, f);
      }
      expect(_realtime.joinedFor(acctA), isEmpty);
      expect(_realtime.joinedFor(acctB), hasLength(1));
      final before = reads();
      _realtime.notify(_note('n2', acctB));
      await settleApp(t, 4);
      expect(reads(), before + 1);
    });
  }

  watcherTest("A's rows, still being read when A signs out, refresh nothing",
      (t) async {
    final hold = Completer<void>();
    _server.holds['GET notifications:$acctA'] = hold;
    final reads = await mount(t, acctA);
    expect(_server.of('notifications', by: acctA), hasLength(1));
    await change(t, () => signInAs(acctB));
    final before = reads();
    _server.rows['notifications:$acctA'] = [_note('late', acctA)];
    hold.complete();
    await settleApp(t, 6);
    expect(reads(), before);
    // B is primed by B's own read, not by A's late one.
    _realtime.notify(_note('n3', acctB));
    await settleApp(t, 4);
    expect(reads(), before + 1);
  });

  watcherTest('signed out at first, then A: subscribed', (t) async {
    await mount(t, null);
    expect(_realtime.joinedFor(acctA), isEmpty);
    await change(t, () => signInAs(acctA));
    expect(_realtime.joinedFor(acctA), hasLength(1));
  });

  watcherTest('control: the same account\'s token refresh keeps its channel',
      (t) async {
    final reads = await mount(t, acctA);
    final channel = _realtime.joinedFor(acctA).single;
    final fetched = _server.of('notifications').length;
    await change(t, () async {
      await Supabase.instance.client.auth.refreshSession();
    });
    expect(_realtime.joinedFor(acctA).single, channel);
    expect(_server.of('notifications').length, fetched);
    final before = reads();
    _realtime.notify(_note('n4', acctA));
    await settleApp(t, 4);
    expect(reads(), before + 1);
  });
}
