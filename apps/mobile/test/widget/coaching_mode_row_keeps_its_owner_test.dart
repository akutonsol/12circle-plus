// P0-FL-59e round 3 · the coaching-mode sheet belongs to the member whose ROW
// was tapped, and what it re-reads does not need the page under it.
//
// The sheet took "who is signed in?" when it was first built, but the mode of
// the row: A's undrawn row tapped once B was signed in opened A's mode, ticked,
// as B's — and Apply wrote it to B and rebuilt or deactivated B's plan, with
// every guard passing, because B was the sheet's owner.
//
// The real SettingsScreen and row; real auth transitions; no AccountScope.
//
// HOW TO SEE IT FAIL: put back 3a90049's settings_screen and
// coaching_mode_provider; every test but the POSITIVE CONTROL and "invalidated
// before" fails. (Round 4's "its container disposed" pins what riverpod 2.6.1
// does: invalidate is a no-op there. Its paid coach fails on e0736a6: the
// message was shown through a messenger that is gone, and the throw recorded as
// a coaching that could not be ended.)
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/coaching_mode/domain/coaching_mode_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];
  late ProviderContainer container;
  var planReads = 0;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    watchAuthChanges();
  });

  /// A is coach-guided, B is AI-guided; both have coach Avery.
  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    planReads = 0;
    setFailureSink(reported.add);
    Map<String, Object?> me(String id, String name, String mode) => {
          'id': id, 'role': 'client', 'first_name': name, 'last_name': 'Lee',
          'coaching_mode': mode,
        };
    server.rows.addAll({
      'user_profiles': {
        memberA: [me(memberA, 'Ana', 'coach_guided')],
        memberB: [me(memberB, 'Ben', 'ai_guided')],
      },
      'coach_client_relationships': {
        for (final m in [memberA, memberB])
          m: [{'id': 'rel', 'coach_id': 'coach-a', 'status': 'active'}],
      },
      'public_profiles': {
        for (final m in [memberA, memberB])
          m: [{'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone'}],
      },
    });
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> noFrame(WidgetTester t) => t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)));

  Future<void> switchTo(WidgetTester t, String uid) =>
      t.runAsync(() => signInAs(uid));

  /// A page that lists the coaches (Profile, in the app), then Settings on it.
  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    container = ProviderContainer(overrides: [
      clientPlanProvider.overrideWith((ref) async {
        planReads++;
        return ClientPlan.coachGuided;
      }),
    ]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(builder: (ctx, ref, __) {
          ref.watch(myCoachesProvider);
          ref.watch(clientPlanProvider);
          return TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen())),
            child: const Text('the page before'),
          );
        }),
      ),
    ));
    await settle(t);
    await t.tap(find.text('the page before'));
    await settle(t);
    expect(find.text('Coach Guided'), findsOneWidget, reason: 'premise');
    server.seen.clear();
    reported.clear();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  const inSheet = 'You can switch modes at any time.';

  for (final state in ['just signed in', 'with their own mode loaded', 'out']) {
    final who = state == 'out' ? 'A signed out' : 'B $state';
    testWidgets("A's row tapped, undrawn, once $who: no sheet, nothing of A's "
        'mode, recorded', (t) async {
      await open(t);
      await t.runAsync(() => state == 'out' ? signOut() : signInAs(memberB));
      if (state == 'with their own mode loaded') {
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          container.read(coachingModeProvider);
          await Future<void>.delayed(const Duration(milliseconds: 60));
        });
        expect(container.read(coachingModeProvider), CoachingMode.aiGuided,
            reason: 'premise');
      }
      await t.tap(find.text('Coach Guided'));
      await settle(t);
      expect(find.text(inSheet), findsNothing,
          reason: "A's mode is ticked as someone else's");
      expect(origins(), contains('CoachingModeRow.identity'));
      expect(server.writes(), isEmpty);
      await close(t);
    });
  }

  testWidgets('tapped the instant the account changes: no sheet, recorded',
      (t) async {
    await open(t);
    final tap = t
        .widget<GestureDetector>(find
            .ancestor(
                of: find.text('Coach Guided'),
                matching: find.byType(GestureDetector))
            .first)
        .onTap!;
    await t.runAsync(() => switchAnd(memberB, tap));
    await settle(t);
    expect(find.text(inSheet), findsNothing);
    expect(origins(), contains('CoachingModeRow.identity'));
    await close(t);
  });

  testWidgets("opened, then B signs in before its first frame: A's mode is "
      'never drawn for B, and the sheet goes', (t) async {
    await open(t);
    await t.tap(find.text('Coach Guided'));
    await switchTo(t, memberB);
    await t.pump();
    expect(find.text(inSheet), findsNothing);
    await settle(t);
    expect(find.text(inSheet), findsNothing);
    expect(
        Navigator.of(t.element(find.byType(SettingsScreen)))
            .overlay!
            .context
            .mounted,
        isTrue);
    // Nothing is left over the page: its row opens B's own.
    await t.tap(find.text('AI Guided'));
    await settle(t);
    expect(find.text(inSheet), findsOneWidget);
    await close(t);
  });

  testWidgets('POSITIVE CONTROL: after a token refresh the row opens its '
      "member's sheet, and Apply saves theirs", (t) async {
    await open(t);
    await t.runAsync(refreshSession);
    await settle(t);
    await t.tap(find.text('Coach Guided'));
    await settle(t);
    expect(find.text(inSheet), findsOneWidget);
    await t.tap(find.text('Self Guided'));
    await settle(t);
    await t.tap(find.text('Apply'));
    await settle(t);
    await t.tap(find.text('End & switch'));
    await settle(t);
    final mode = server
        .writes('user_profiles')
        .where((w) => '${w.body}'.contains('coaching_mode'))
        .single;
    expect((mode.who, mode.query['id'], mode.row['coaching_mode']),
        (memberA, 'eq.$memberA', 'self_guided'));
    expect(reported, isEmpty);
    await close(t);
  });

  testWidgets("invalidated before the account change is flushed: A's mode is "
      "not drawn while B's is read", (t) async {
    await open(t);
    final hold = server.holds['GET user_profiles:$memberB'] = Completer();
    await switchTo(t, memberB);
    container.invalidate(coachingModeNotifierProvider);
    await settle(t);
    expect(find.text('Coach Guided'), findsNothing);
    expect(container.read(coachingModeNotifierProvider).hasValue, isFalse);
    hold.complete();
    await settle(t);
    expect(container.read(coachingModeProvider), CoachingMode.aiGuided);
    await close(t);
  });

  for (final fails in [false, true]) {
    testWidgets(
        'same member, the sheet and Settings both left while the coaching is '
        'ended${fails ? ' (and it fails)' : ''}: nothing is thrown, the page '
        'before lists the coaches afresh', (t) async {
      await open(t);
      await t.tap(find.text('Coach Guided'));
      await settle(t);
      await t.tap(find.text('Self Guided'));
      await settle(t);
      const key = 'PATCH coach_client_relationships:$memberA';
      final hold = server.holds[key] = Completer();
      if (fails) server.fails.add(key);
      await t.tap(find.text('Apply'));
      await settle(t);
      await t.tap(find.text('End & switch'));
      await settle(t, 4);
      expect(server.writes('coach_client_relationships'), hasLength(1),
          reason: 'premise');
      final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pop(); // the sheet, swiped away
      await settle(t);
      navigator.pop(); // Settings
      await settle(t);
      expect(find.byType(SettingsScreen), findsNothing, reason: 'premise');
      server.seen.clear();
      hold.complete();
      await settle(t);
      expect(t.takeException(), isNull);
      expect(
          server.reads('coach_client_relationships', memberA).where(
              (r) => '${r.query['select']}'.contains('monthly_price')),
          hasLength(1),
          reason: 'the ended coach is still listed');
      expect(find.byType(SnackBar), findsNothing);
      await close(t);
    });
  }

  for (final (fails, paid) in [(false, false), (true, false), (false, true)]) {
    testWidgets(
        'the same member signed out and in again while the coaching is ended'
        '${fails ? ' (and it fails)' : paid ? ' (paid: later)' : ''}, its '
        'container disposed: nothing is thrown, or recorded that is not so',
        (t) async {
      if (paid) {
        server.rows['subscriptions'] = {
          memberA: [{'id': 'sub-a', 'current_period_end': '2026-12-20T00:00:00Z'}],
        };
        server.functions['cancel-subscription'] = {
          'ok': true, 'endsAt': '2026-12-20T00:00:00Z',
        };
      }
      await open(t);
      await t.tap(find.text('Coach Guided'));
      await settle(t);
      await t.tap(find.text('Self Guided'));
      await settle(t);
      final target =
          paid ? 'cancel-subscription' : 'coach_client_relationships';
      final key = '${paid ? 'POST' : 'PATCH'} $target:$memberA';
      final hold = server.holds[key] = Completer();
      if (fails) server.fails.add(key);
      await t.tap(find.text('Apply'));
      await settle(t);
      await t.tap(find.text('End & switch'));
      await settle(t, 4);
      expect(server.writes(target), hasLength(1), reason: 'premise');
      await t.runAsync(signOut);
      await switchTo(t, memberA);
      await t.pumpWidget(const SizedBox()); // as AccountScope replaces it
      container.dispose();
      server.seen.clear();
      hold.complete();
      await settle(t);
      expect(t.takeException(), isNull);
      expect(server.writes('user_profiles'), isEmpty,
          reason: 'the sheet is gone: the mode is not changed');
      expect(origins(),
          fails ? ['CoachingModeSheet.apply.cancelCoach'] : isEmpty);
      await close(t);
    });
  }

  testWidgets("B signs in while A's plan is being synced, no frame: nothing is "
      're-read for the change that was A\'s; recorded', (t) async {
    await open(t);
    final hold =
        server.holds['POST generate_client_plan:$memberA'] = Completer();
    final n = container.read(coachingModeNotifierProvider.notifier);
    unawaited(n.setMode(CoachingMode.selfGuided));
    await noFrame(t);
    expect(server.writes('generate_client_plan'), hasLength(1),
        reason: 'premise');
    final before = planReads;
    await t.runAsync(() => switchAnd(memberB, hold.complete));
    await noFrame(t);
    await settle(t);
    expect(planReads, before,
        reason: "A's mode change re-read B's plan before B was known");
    expect(origins(), contains('CoachingModeNotifier.setMode.identity'));
    await close(t);
  });

  testWidgets('POSITIVE CONTROL: the same member, token refreshed meanwhile: '
      're-read once', (t) async {
    await open(t);
    final hold =
        server.holds['POST generate_client_plan:$memberA'] = Completer();
    final n = container.read(coachingModeNotifierProvider.notifier);
    unawaited(n.setMode(CoachingMode.selfGuided));
    await noFrame(t);
    await t.runAsync(refreshSession);
    final before = planReads;
    hold.complete();
    await settle(t);
    expect(planReads, before + 1);
    expect(reported, isEmpty);
    await close(t);
  });
}
