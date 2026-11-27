// P0-FL-62c · a coach's view of a client's action items, and its completion,
// is marked with the coach it was read for.
//
// `clientActionItemsProvider(clientId)` and `actionCompletionProvider
// (clientId)` are keyed by the client only. They re-read when another coach
// signs in (P0-FL-59e), but Riverpod keeps coach A's answer through coach B's
// read of the same client (a shared client, or A -> B with the family alive),
// and nothing said whose it was: a screen drawing it could not tell A's items
// from B's. LATENT: nothing in lib draws either today (the assign sheet only
// invalidates them). Now each answer is marked ([readForMember]) and drawn
// through `ownRead`, which gives B nothing of A's.
//
// HOW TO SEE IT FAIL:
//   git checkout a446926 -- lib/features/action_items/domain/action_item_provider.dart
// Every test fails there: no answer carries its coach, so `ownRead` can tell
// nobody's from anybody's (items: "Expected ['Walk'] Actual <null>"), and the
// completion stats were a record, which cannot carry the mark at all
// ("Invalid argument (object): Cannot be a … record").
import 'dart:async';

import 'package:circle_fitness/features/action_items/data/models/action_item.dart';
import 'package:circle_fitness/features/action_items/domain/action_item_provider.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart'
    show ownRead;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

const _client = 'client-x';
const _read = 'GET action_items';

void main() {
  final server = MemberSwitchServer();
  late ProviderContainer c;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  Map<String, Object?> item(String title, String status) => {
        'id': 'i-$title', 'client_id': _client, 'title': title,
        'status': status, 'created_at': '2026-11-20T08:00:00Z',
      };

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    // What RLS shows coach A, and coach B, for the same client.
    server.rows['action_items'] = {
      memberA: [item('Walk', 'pending')],
      memberB: [item('Swim', 'completed'), item('Row', 'pending')],
    };
    c = ProviderContainer();
  });
  tearDown(() {
    for (final h in server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    c.dispose();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  final items = clientActionItemsProvider(_client);
  final stats = actionCompletionProvider(_client);

  List<String>? drawnItems() =>
      ownRead(c.read(items)).value?.map((ActionItem i) => i.title).toList();
  (int, int)? drawnStats() {
    final s = ownRead(c.read(stats)).value;
    return s == null ? null : (s.assigned, s.completed);
  }

  Future<void> loadA() async {
    c.listen(items, (_, __) {});
    c.listen(stats, (_, __) {});
    await c.read(items.future);
    await c.read(stats.future);
    server.seen.clear();
  }

  testWidgets("A's own answer is A's (items and completion)", (t) async {
    await t.runAsync(() async {
      await loadA();
      expect(drawnItems(), ['Walk']);
      expect(drawnStats(), (1, 0));
    });
  });

  testWidgets(
      "coach A -> coach B, B's read pending: A's held answer is nothing of "
      "B's; then B's own", (t) async {
    await t.runAsync(() async {
      await loadA();
      final holdB = server.holds['$_read:$memberB'] = Completer<void>();
      await signInAs(memberB);
      await settle();
      expect(c.read(items).valueOrNull?.single.title, 'Walk',
          reason: "premise: Riverpod still holds A's answer");
      expect(drawnItems(), isNull, reason: "THE defect: A's items for B");
      expect(drawnStats(), isNull, reason: "A's completion for B");
      expect(server.reads('action_items', memberB), isNotEmpty);
      expect(server.reads('action_items', memberA), isEmpty,
          reason: 'nothing is asked as A after A left');
      holdB.complete();
      await settle();
      expect(drawnItems(), ['Swim', 'Row']);
      expect(drawnStats(), (2, 1));
    });
  });

  testWidgets("A's delayed answer landing after B's lands on nobody",
      (t) async {
    await t.runAsync(() async {
      await loadA();
      final lateA = server.holds['$_read:$memberA'] = Completer<void>();
      c.invalidate(items); // the assign sheet's refresh, as A
      c.invalidate(stats);
      await settle();
      expect(server.reads('action_items', memberA), hasLength(2),
          reason: "A's re-reads went out, as A");
      await signInAs(memberB);
      await settle();
      expect(drawnItems(), ['Swim', 'Row']);
      lateA.complete();
      await settle();
      expect(drawnItems(), ['Swim', 'Row'],
          reason: "A's late answer is not drawn for B");
      expect(drawnStats(), (2, 1));
    });
  });

  testWidgets(
      "coach A -> coach B, B's read failed: nothing of A's is drawn for B",
      (t) async {
    await t.runAsync(() async {
      await loadA();
      server.fails.add('$_read:$memberB');
      await signInAs(memberB);
      await settle();
      expect(drawnItems(), isNot(contains('Walk')));
      expect(drawnStats(), isNot((1, 0)));
      // (The service turns a failed read into no items — a false empty in
      // action_item_service.dart, outside this package: reported.)
    });
  });

  testWidgets('sign-out -> sign-in as B: nothing of A while out; then B',
      (t) async {
    await t.runAsync(() async {
      await loadA();
      await signOut();
      await settle();
      expect(drawnItems(), isNot(contains('Walk')));
      await signInAs(memberB);
      await settle();
      expect(drawnItems(), ['Swim', 'Row']);
    });
  });

  testWidgets(
      "CONTROL: the assign sheet's invalidate re-reads once, as A, and A's "
      'new item is drawn', (t) async {
    await t.runAsync(() async {
      await loadA();
      server.rows['action_items']![memberA] = [
        item('Walk', 'pending'),
        item('Stretch', 'completed'),
      ];
      c.invalidate(items);
      c.invalidate(stats);
      await settle();
      expect(server.reads('action_items', memberA), hasLength(2));
      expect(server.reads('action_items', memberB), isEmpty);
      expect(drawnItems(), ['Walk', 'Stretch']);
      expect(drawnStats(), (2, 1));
    });
  });

  testWidgets('CONTROL: a refreshed token keeps the answer, reads nothing',
      (t) async {
    await t.runAsync(() async {
      await loadA();
      await refreshSession();
      await settle();
      expect(server.reads('action_items'), isEmpty);
      expect(drawnItems(), ['Walk']);
      expect(drawnStats(), (1, 0));
    });
  });

  testWidgets('CONTROL: the same coach out and back in: their own again',
      (t) async {
    await t.runAsync(() async {
      await loadA();
      await signOut();
      await settle();
      await signInAs(memberA);
      await settle();
      expect(drawnItems(), ['Walk']);
      expect(drawnStats(), (1, 0));
    });
  });
}
