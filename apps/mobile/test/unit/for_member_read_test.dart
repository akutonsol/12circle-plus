import 'dart:async';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/dashboard_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/two_member_postgrest.dart';

// P0-FL-60b round 3 · `forMember` is auto-disposed, so a read can end while it
// is not there to see whose it was. What it tells is only what it saw END for
// the member it tells: never the value or the failure the read carries.
//
// HOW TO SEE IT FAIL: in `forMember`, answer `read.error` for `owner.error`.

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(TwoMemberPostgrest());
  });
  setUp(() => signInAs(memberA));

  Future<void> turn() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  for (final aFails in [true, false]) {
    test(
        "A's ${aFails ? 'failure' : 'answer'}, landed while no screen was "
        "reading, is not B's; B's own is", () async {
      Completer<void>? hold;
      final read = FutureProvider<String>((ref) async {
        final uid = ref.watch(currentUserProvider.select((u) => u?.id));
        final h = hold;
        if (h != null) await h.future;
        if (uid == memberA && aFails) throw StateError("A's failure");
        return uid == memberA ? "A's" : "B's";
      });
      final mine = forMember(read);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(read, (_, __) {}); // another screen's
      await turn();

      await signInAs(memberB);
      await turn();
      final sub = c.listen(mine, (_, __) {});
      expect(c.read(mine).value, "B's", reason: 'premise: B was told');
      sub.close();
      await turn();

      await signInAs(memberA);
      await turn();
      expect(c.read(read).hasError, aFails, reason: 'premise: it ended, unseen');

      hold = Completer<void>();
      c.invalidate(read);
      await signInAs(memberB);
      c.listen(mine, (_, __) {});
      final raw = c.read(read);
      expect(raw.isLoading, isTrue);
      expect(aFails ? raw.error : raw.value, isNotNull,
          reason: "premise: A's, carried");
      expect(c.read(mine).error, isNull, reason: "A's failure told to B");
      expect(c.read(mine).value, "B's", reason: 'what B was last given');
      hold.complete();
      await turn();
      expect(c.read(mine).value, "B's");
    });
  }
}
