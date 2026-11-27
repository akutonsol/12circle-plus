// P0-FL-59e round 5 · a coach's view of a client's action items follows the
// signed-in coach (the same lines as P0-FL-59f, so the two merge cleanly).
//
// What RLS returns for `action_items?client_id=eq.X` depends on WHO asks, so
// the coach-side reads (`clientActionItemsProvider`, `actionCompletionProvider`)
// must be read again when another account signs in. At a82f993 / 3b95d22 they
// watched nothing about the account: coach B was handed coach A's answer.
//
// HOW TO SEE IT FAIL: `git checkout 3b95d22 -- <action_item_provider.dart>`:
// the two "coach A -> coach B" tests fail (no read as B; A's answer kept). The
// token-refresh control passes on both (no event re-reads anything).
//
// Real auth transitions (signInAs / refreshSession), no provider overrides.
// The fake server answers each member with that member's rows, which is how
// RLS answers the same query for two coaches.
import 'package:circle_fitness/features/action_items/data/models/action_item.dart';
import 'package:circle_fitness/features/action_items/domain/action_item_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

const _client = 'client-x';

void main() {
  final server = MemberSwitchServer();
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    Map<String, Object?> item(String title, String status) => {
          'id': 'i-$title', 'client_id': _client, 'title': title,
          'status': status, 'created_at': '2026-11-20T08:00:00Z',
        };
    // What RLS shows coach A, and coach B, for the same client id.
    server.rows['action_items'] = {
      memberA: [item('Walk', 'pending')],
      memberB: [item('Swim', 'completed'), item('Row', 'pending')],
    };
    container = ProviderContainer();
  });
  tearDown(() => container.dispose());

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  Future<List<String>> titles() async =>
      (await container.read(clientActionItemsProvider(_client).future))
          .map((ActionItem i) => i.title)
          .toList();

  testWidgets("coach A -> coach B: the client's items are read again, as B",
      (t) async {
    await t.runAsync(() async {
      container.listen(clientActionItemsProvider(_client), (_, __) {});
      expect(await titles(), ['Walk'], reason: 'premise');
      server.seen.clear();
      await signInAs(memberB);
      await settle();
      expect(server.reads('action_items', memberB), isNotEmpty);
      expect(await titles(), ['Swim', 'Row']);
    });
  });

  testWidgets("coach A -> coach B: the completion stats are B's", (t) async {
    await t.runAsync(() async {
      container.listen(actionCompletionProvider(_client), (_, __) {});
      final a = await container.read(actionCompletionProvider(_client).future);
      expect((a.assigned, a.completed), (1, 0), reason: 'premise');
      await signInAs(memberB);
      await settle();
      final b = await container.read(actionCompletionProvider(_client).future);
      expect((b.assigned, b.completed), (2, 1));
    });
  });

  testWidgets('CONTROL: a token refresh for the same coach reads nothing again '
      'and keeps the answer', (t) async {
    await t.runAsync(() async {
      container.listen(clientActionItemsProvider(_client), (_, __) {});
      container.listen(actionCompletionProvider(_client), (_, __) {});
      expect(await titles(), ['Walk'], reason: 'premise');
      await container.read(actionCompletionProvider(_client).future);
      server.seen.clear();
      await refreshSession(); // throws unless tokenRefreshed was heard
      await settle();
      expect(server.reads('action_items'), isEmpty);
      expect(await titles(), ['Walk']);
      final s = await container.read(actionCompletionProvider(_client).future);
      expect(s.assigned, 1);
    });
  });
}
