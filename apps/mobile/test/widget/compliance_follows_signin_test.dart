import 'dart:async';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/compliance/domain/compliance_provider.dart';
import 'package:circle_fitness/features/compliance/presentation/compliance_dashboard_screen.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_until.dart';
import '../support/two_coach_postgrest.dart';

// P0-FL-59f round 4 (R2) · the compliance roster, and the client page it opens.
//
//   * the roster kept coach A's clients through the switch to B;
//   * a card opened the client page with no owner, and the page took whoever
//     was signed in at its first build for its coach: A's client was named to
//     B (or to nobody at all), and read — the logged assessment too — as B.
//
// The screen is mounted WITHOUT the app-root account scope and kept mounted.
//
// HOW TO SEE IT FAIL: git checkout b4b22f6 -- apps/mobile/lib

const _rels = 'GET coach_client_relationships';
const _rpc = 'rpc/get_client_assessment';

void main() {
  late TwoCoachPostgrest server;
  late ProviderContainer c;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoCoachPostgrest();
    await initTwoMemberSupabase(server);
  });

  void roster(String who, String id, String first, String last) => server
    ..seed('coach_client_relationships', who, [
      {'client_id': id, 'status': 'active', 'coach_id': who}
    ])
    ..seed('user_profiles', who, [
      {'id': id, 'first_name': first, 'last_name': last}
    ]);

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    roster(memberA, 'cl-a', 'Alma', 'Stone');
    roster(memberB, 'cl-b', 'Boris', 'Reed');
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Finder alma() => find.text('Alma Stone');
  Finder boris() => find.text('Boris Reed');
  Finder page() => find.byType(ClientDetailScreen);
  bool seen(Finder f) => f.evaluate().isNotEmpty;

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 3000);
    addTearDown(tester.view.reset);
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
    ]);
    c.listen(currentUserProvider, (_, __) {});
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: ComplianceDashboardScreen())));
    await pumpUntil(tester, () => seen(alma()), what: "A's roster");
    await frames(tester);
    server.calls.clear();
  }

  Future<void> unmount(WidgetTester tester) async {
    for (final h in server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> become(WidgetTester tester, String? uid) async {
    await tester.runAsync(() => uid == null ? signOut() : signInAs(uid));
    await pumpUntil(tester, () => c.read(currentUserProvider)?.id == uid,
        what: 'signed in: $uid');
    await frames(tester, 2);
  }

  VoidCallback cardTap(WidgetTester tester, Finder name) => tester
      .widget<InkWell>(
          find.ancestor(of: name, matching: find.byType(InkWell)).first)
      .onTap!;

  /// No read of a client's page: their own roster is the next coach's to read.
  void noClientPageRead(String as) => expect(
      server.calls.where((k) =>
          k.endsWith(':$as') &&
          (k.contains('get_client_assessment') ||
              k.contains('subscriptions') ||
              k.contains('client_schedules') ||
              k.contains('user_scores') ||
              k.contains('progress_photo_logs') ||
              k.contains('weight_logs'))),
      isEmpty,
      reason: "THE defect: A's client was read as $as");

  group('SEC4 a card of A', () {
    for (final next in [memberB, null]) {
      for (final tapFirst in [true, false]) {
        testWidgets(
            '${tapFirst ? 'tapped, then' : 'tapped after'} '
            "${next == null ? 'A signs out' : 'B signs in'}"
            "${tapFirst ? ' before the first frame' : ' and no frame'}: the "
            'client is not named, nothing is read', (tester) async {
          // B coaches this client too: only whose CARD it was decides.
          server.data['user_profiles']![memberB]!
              .addAll(server.data['user_profiles']![memberA]!);
          await show(tester);
          final tap = cardTap(tester, alma());
          if (tapFirst) tap();
          await tester
              .runAsync(() => next == null ? signOut() : signInAs(next));
          if (!tapFirst) tap();
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            expect(find.descendant(of: page(), matching: alma()), findsNothing,
                reason: "THE defect: A's client was named, frame $i");
            expect(find.descendant(of: page(), matching: find.byType(TabBar)),
                findsNothing);
          }
          noClientPageRead(next ?? 'anon');
          if (tapFirst) {
            expect(page(), findsOneWidget);
            expect(find.byIcon(Icons.arrow_back_ios), findsOneWidget,
                reason: 'a way back');
            await tester.tap(find.byIcon(Icons.arrow_back_ios));
            await frames(tester, 10);
          } else {
            expect(reported.map((f) => f.origin),
                contains('ComplianceDashboard.openClient'));
          }
          expect(page(), findsNothing);
          await unmount(tester);
        });
      }
    }

    testWidgets('a card whose coach is not known opens nothing, signed in or '
        'out', (tester) async {
      await show(tester);
      final rows = c.read(complianceRosterProvider).requireValue.toList();
      await unmount(tester);
      await tester.runAsync(signOut);
      c = ProviderContainer(overrides: [
        complianceRosterProvider.overrideWith((ref) async => rows),
      ]);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: ComplianceDashboardScreen())));
      await frames(tester);
      expect(alma(), findsOneWidget, reason: 'premise: unmarked rows');
      final tap = cardTap(tester, alma());
      tap();
      await frames(tester);
      expect(page(), findsNothing, reason: 'signed out');
      await tester.runAsync(() => signInAs(memberB));
      tap();
      await frames(tester);
      expect(page(), findsNothing, reason: 'as B');
      expect(reported.map((f) => f.origin),
          contains('ComplianceDashboard.openClient'));
      await unmount(tester);
    });

    testWidgets("control: A's own tap opens the client, through a token event "
        'that fires', (tester) async {
      await show(tester);
      final before = c.read(currentUserProvider);
      await tester.runAsync(refreshSession);
      await pumpUntil(tester, () => c.read(currentUserProvider) != before,
          what: 'the same coach as a new User');
      await frames(tester);
      expect(server.count('$_rels:$memberA'), 0,
          reason: 'a refreshed token reads the roster no second time');
      await tester.tap(alma());
      await pumpUntil(tester, () => server.count('POST $_rpc:$memberA') == 1,
          what: "A's page reads");
      await frames(tester);
      expect(find.descendant(of: page(), matching: alma()), findsWidgets);
      await unmount(tester);
    });
  });

  group('the roster', () {
    testWidgets("B's read pending: none of A's clients; then B's own",
        (tester) async {
      await show(tester);
      final hold = server.holds['$_rels:$memberB'] = Completer<void>();
      await become(tester, memberB);
      expect(alma(), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('No active clients'), findsNothing);
      hold.complete();
      await pumpUntil(tester, () => seen(boris()), what: "B's own");
      expect(alma(), findsNothing);
      await unmount(tester);
    });

    testWidgets("B's read failed: B's failure, none of A's clients",
        (tester) async {
      await show(tester);
      server.fails.add('$_rels:$memberB');
      await become(tester, memberB);
      await pumpUntil(
          tester, () => seen(find.text('Could not load compliance.')),
          what: "B's failure");
      expect(alma(), findsNothing);
      await unmount(tester);
    });

    testWidgets("pulled to refresh as B signs in, before any frame: A's clients "
        "are not B's while B's read is out", (tester) async {
      await show(tester);
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh;
      final hold = server.holds['$_rels:$memberB'] = Completer<void>();
      await tester.runAsync(() => signInAs(memberB));
      unawaited(refresh());
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(alma(), findsNothing,
            reason: "THE defect: A's clients, invalidated before the switch "
                "was flushed, were drawn as B's (frame $i)");
      }
      hold.complete();
      await pumpUntil(tester, () => seen(boris()), what: "B's own");
      await unmount(tester);
    });

    testWidgets("A's failure is not B's while B's read is out",
        (tester) async {
      await show(tester);
      server.fails.add('$_rels:$memberA');
      c.invalidate(complianceRosterProvider);
      await pumpUntil(
          tester, () => seen(find.text('Could not load compliance.')),
          what: "A's failure");
      server.holds['$_rels:$memberB'] = Completer<void>();
      await tester.runAsync(() => signInAs(memberB));
      c.invalidate(complianceRosterProvider);
      await frames(tester);
      expect(find.text('Could not load compliance.'), findsNothing);
      expect(alma(), findsNothing);
      await unmount(tester);
    });

    testWidgets("A's answer, late, is nobody's", (tester) async {
      await show(tester);
      final hold = server.holds['$_rels:$memberA'] = Completer<void>();
      c.invalidate(complianceRosterProvider);
      await pumpUntil(tester, () => server.count('$_rels:$memberA') == 1,
          what: "A's re-read");
      server.holds['$_rels:$memberB'] = Completer<void>();
      await become(tester, memberB);
      hold.complete();
      await frames(tester, 10);
      expect(alma(), findsNothing);
      await unmount(tester);
    });

    testWidgets('signed out, then B: none of A, and nobody is told "none"',
        (tester) async {
      await show(tester);
      await become(tester, null);
      expect(alma(), findsNothing);
      server.holds['$_rels:$memberB'] = Completer<void>();
      await become(tester, memberB);
      expect(alma(), findsNothing);
      expect(find.textContaining('No active clients'), findsNothing);
      await unmount(tester);
    });

    testWidgets('control: a coach with no clients is told so', (tester) async {
      await show(tester);
      server.data['coach_client_relationships']![memberB] = [];
      await become(tester, memberB);
      await pumpUntil(
          tester, () => seen(find.textContaining('No active clients yet')),
          what: 'a real empty roster');
      await unmount(tester);
    });

    testWidgets('control: the same coach keeps their clients through a pull to '
        'refresh, and after signing out and in', (tester) async {
      await show(tester);
      final hold = server.holds['$_rels:$memberA'] = Completer<void>();
      unawaited(tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh());
      await frames(tester);
      expect(server.count('$_rels:$memberA'), 1, reason: 're-read');
      expect(alma(), findsOneWidget, reason: 'no flicker');
      hold.complete();
      await frames(tester);
      expect(alma(), findsOneWidget);
      await become(tester, null);
      await become(tester, memberA);
      await pumpUntil(tester, () => seen(alma()), what: 'theirs again');
      await unmount(tester);
    });
  });

  group('ClientDetailScreen with no known owner', () {
    for (final as in [memberA, null]) {
      testWidgets('signed in: ${as != null}: only Back, no name, no reads',
          (tester) async {
        if (as == null) await tester.runAsync(signOut);
        c = ProviderContainer(overrides: [
          tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
        ]);
        server.calls.clear();
        await tester.pumpWidget(UncontrolledProviderScope(
            container: c,
            child: const MaterialApp(
                home: ClientDetailScreen(
                    clientId: 'cl-a', clientName: 'Alma Stone', owner: null))));
        await frames(tester, 10);
        expect(alma(), findsNothing,
            reason: 'THE defect: no owner was taken for whoever is signed in');
        expect(find.byType(TabBar), findsNothing);
        expect(find.byIcon(Icons.arrow_back_ios), findsOneWidget);
        noClientPageRead(as ?? 'anon');
        expect(server.calls.where((k) => k.contains('user_profiles')), isEmpty);
        await unmount(tester);
      });
    }
  });

  // Required by the type; null only by writing it. So: no opener writes it.
  test('every opener of the client page in lib says whose it is', () {
    final openers = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r'ClientDetailScreen\(').allMatches(src)) {
        // Its own declaration.
        if (src.startsWith('{super.key', m.end)) continue;
        var depth = 1, i = m.end;
        for (; depth > 0; i++) {
          if (src[i] == '(') depth++;
          if (src[i] == ')') depth--;
        }
        final args = src.substring(m.end, i - 1);
        openers.add(f.path);
        expect(RegExp(r'\bowner:\s*owner\b').hasMatch(args), isTrue,
            reason: '${f.path}: ClientDetailScreen($args)');
        // ... which it was given, and did not just look up at the tap.
        expect(args, isNot(contains('signedInUid')));
      }
    }
    expect(openers.length, 2, reason: '$openers');
  });
}
