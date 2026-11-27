import 'package:circle_fitness/features/dashboard/domain/still_reading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, Supabase;

import '../support/pump_until.dart';
import '../support/two_coach_postgrest.dart';

// P0-FL-59f round 6 · the shared OwnedText, through the REAL auth client.
//
//   * (sec) a null owner on a signed-out device is nobody's: nothing drawn.
//   * (ux) when it goes blank on a switch it takes ITS OWN SnackBar down, so
//     the next account is not left an empty bar for the rest of its time;
//     another screen's bar is never taken down with it.
//
// HOW TO SEE IT FAIL: `git checkout 5853641 -- lib/features/dashboard/domain`.

void main() {
  late TwoCoachPostgrest server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoCoachPostgrest();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
  });

  bool seen(Finder f) => f.evaluate().isNotEmpty;

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ScaffoldMessengerState> host(WidgetTester tester,
      [Widget body = const Text('THE PAGE')]) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pump();
    return tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  SnackBar owned(String text, String? owner) =>
      SnackBar(content: OwnedText(text, owner: owner));

  group('a null owner (sec)', () {
    testWidgets('on a signed-out device: nothing is drawn', (tester) async {
      await tester.runAsync(signOut);
      await host(tester, const OwnedText('of nobody', owner: null));
      expect(find.text('of nobody'), findsNothing,
          reason: 'THE defect: a null owner matched a signed-out device');
      await unmount(tester);
    });

    testWidgets('control: its own account, signed in, is drawn',
        (tester) async {
      await host(tester, const OwnedText('of A', owner: memberA));
      expect(find.text('of A'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('its own bar (ux)', () {
    for (final next in [memberB, null]) {
      final who = next == null ? 'A signs out' : 'B signs in';

      testWidgets("$who while A's bar is up: the bar goes, not just its text",
          (tester) async {
        final messenger = await host(tester);
        messenger.showSnackBar(owned('Program assigned!', memberA));
        await frames(tester, 3);
        expect(find.text('Program assigned!'), findsOneWidget,
            reason: 'premise');
        await tester.runAsync(() => next == null ? signOut() : signInAs(next));
        await tester.pump();
        expect(find.text('Program assigned!'), findsNothing);
        await frames(tester, 6); // well inside its 4 s
        expect(find.byType(SnackBar), findsNothing,
            reason: 'THE defect: an empty bar was left up for the next account');
        await unmount(tester);
      });

      testWidgets("$who before the first frame of A's bar (no frame): it never "
          'stays up', (tester) async {
        final messenger = await host(tester);
        messenger.showSnackBar(owned('Program assigned!', memberA));
        await tester.runAsync(() => next == null ? signOut() : signInAs(next));
        await tester.pump();
        expect(find.text('Program assigned!'), findsNothing);
        await frames(tester, 6);
        expect(find.byType(SnackBar), findsNothing,
            reason: 'THE defect: an empty bar was left up for the next account');
        await unmount(tester);
      });
    }

    testWidgets("control: another screen's bar queued behind A's comes up and "
        'stays for its time', (tester) async {
      final messenger = await host(tester);
      messenger
        ..showSnackBar(owned('Program assigned!', memberA))
        ..showSnackBar(const SnackBar(
            content: Text("another screen's"), duration: Duration(seconds: 2)));
      await frames(tester, 3);
      await tester.runAsync(() => signInAs(memberB));
      await pumpUntil(tester, () => seen(find.text("another screen's")),
          what: 'the next bar', step: const Duration(milliseconds: 100));
      await frames(tester, 15); // 1.5 s of its 2 s
      expect(find.text("another screen's"), findsOneWidget,
          reason: "another screen's bar was taken down with A's");
      await unmount(tester);
    });

    testWidgets("control: another screen's bar up while A's is queued stays for "
        "its time; A's never shows", (tester) async {
      final messenger = await host(tester);
      messenger
        ..showSnackBar(const SnackBar(
            content: Text("another screen's"), duration: Duration(seconds: 2)))
        ..showSnackBar(owned('Program assigned!', memberA));
      await frames(tester, 3);
      await tester.runAsync(() => signInAs(memberB));
      await frames(tester, 12); // 1.5 s in
      expect(find.text("another screen's"), findsOneWidget,
          reason: "another screen's bar was taken down for A's");
      await pumpUntil(tester, () => !seen(find.text("another screen's")),
          what: 'its time is over', step: const Duration(milliseconds: 100));
      await frames(tester, 8);
      expect(find.text('Program assigned!'), findsNothing);
      expect(find.byType(SnackBar), findsNothing,
          reason: "A's queued bar came up empty for B and stayed");
      await unmount(tester);
    });

    // Round 7 (lead mutant N2): with no frame between the bar and the switch,
    // it is built blank, and goes at the end of THAT frame. (Its listener
    // would hide it too, but a frame later: the auth stream replays its last
    // event to a new listener, after the frame that built it.)
    testWidgets("B signs in before the first frame of A's bar (no frame): it is "
        'on its way out at the end of that first frame', (tester) async {
      final messenger = await host(tester);
      SnackBarClosedReason? closed;
      messenger
          .showSnackBar(owned('Program assigned!', memberA))
          .closed
          .then((r) => closed = r);
      await tester.runAsync(() => signInAs(memberB));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget, reason: 'premise: built');
      expect(find.text('Program assigned!'), findsNothing);
      expect(closed, SnackBarClosedReason.hide,
          reason: 'THE defect: an empty bar was left up for another frame');
      await frames(tester, 6);
      expect(find.byType(SnackBar), findsNothing);
      await unmount(tester);
    });

    // Round 7 (lead mutant N5): drawn on a page, not in a bar, it has no bar
    // of its own to take down — and the bar up is another screen's.
    testWidgets("drawn on a page, not in a bar: when it goes blank, another "
        "screen's bar stays for its time", (tester) async {
      final messenger =
          await host(tester, const OwnedText('of A', owner: memberA));
      messenger.showSnackBar(const SnackBar(
          content: Text("another screen's"), duration: Duration(seconds: 2)));
      await frames(tester, 3);
      await tester.runAsync(() => signInAs(memberB));
      await frames(tester, 3);
      expect(find.text('of A'), findsNothing, reason: 'premise: blank for B');
      await frames(tester, 9); // 1.5 s of its 2 s
      expect(find.text("another screen's"), findsOneWidget,
          reason: "THE defect: another screen's bar was taken down for it");
      await unmount(tester);
    });

    // Round 7 (lead mutant N4): a bar its caller takes down itself on the
    // switch passes takesItsBarDown false. When the caller's removal runs
    // first, the bar up next is another screen's, and it stays.
    testWidgets("takesItsBarDown false: the caller removes its own bar, and "
        "another screen's queued behind it stays for its time", (tester) async {
      final messenger = await host(tester);
      // The caller listens before its bar is up (as the client page does).
      final sub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
        if (s.session?.user.id == memberA) return;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => messenger.removeCurrentSnackBar());
      });
      addTearDown(sub.cancel);
      await frames(tester, 1);
      messenger
        ..showSnackBar(SnackBar(
            content: OwnedText('Marked done: Alma', owner: memberA,
                takesItsBarDown: false)))
        ..showSnackBar(const SnackBar(
            content: Text("another screen's"), duration: Duration(seconds: 2)));
      await frames(tester, 3);
      expect(find.text('Marked done: Alma'), findsOneWidget, reason: 'premise');
      await tester.runAsync(() => signInAs(memberB));
      await pumpUntil(tester, () => seen(find.text("another screen's")),
          what: "the next bar (THE defect if it never shows: it was taken "
              "down with A's as it came up)",
          step: const Duration(milliseconds: 100));
      await frames(tester, 12); // 1.2 s of its 2 s
      expect(find.text("another screen's"), findsOneWidget,
          reason: "THE defect: another screen's bar was taken down with A's");
      expect(find.text('Marked done: Alma'), findsNothing);
      await unmount(tester);
    });

    testWidgets('control: a refreshed token (an event that fires) keeps it up '
        'with its text', (tester) async {
      final messenger = await host(tester);
      messenger.showSnackBar(owned('Program assigned!', memberA));
      await frames(tester, 3);
      final events = <AuthChangeEvent>[];
      await tester.runAsync(() async {
        final sub = Supabase.instance.client.auth.onAuthStateChange
            .listen((s) => events.add(s.event));
        await refreshSession();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
      });
      expect(events, contains(AuthChangeEvent.tokenRefreshed),
          reason: 'premise: the event fired');
      await frames(tester, 6);
      expect(find.text('Program assigned!'), findsOneWidget);
      await unmount(tester);
    });
  });
}
