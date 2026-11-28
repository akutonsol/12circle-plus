import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/presentation/coach_marketplace_screen.dart';
import 'package:circle_fitness/features/coach/presentation/coach_pricing_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/coach_tools_server.dart';
import '../support/two_member_postgrest.dart';

// P0-RM-1 round 2 (security S-1 / UX N1) · the coach marketplace's request
// and the Coaching Price sheet's save turned a refusal into words with
// `e is StateError ? e.message`. An AccountChangedError is a StateError, so a
// switch in the middle showed "Not done: the signed-in account changed" — to
// the next account (the marketplace checks the account through a provider
// that may not have rebuilt yet). Both now go through `refusalToSay`, which
// says nothing for it; the service's record is the one record.
//
// The REAL screens and the REAL auth client; no AccountScope; the screen stays
// mounted across the switch. The marketplace's `currentUserProvider` is held
// at A on purpose: it is the provider that had not rebuilt when B's sign-in
// reached the auth client — the raw signed-in uid is B.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d -- apps/mobile/lib/features/coach/
// presentation/coach_marketplace_screen.dart apps/mobile/lib/features/coach/
// presentation/coach_pricing_sheet.dart`.

const _coach = {
  'id': 'coach-c', 'first_name': 'Avery', 'last_name': 'Stone',
  'coach_title': 'Strength Coach', 'specialties': <String>[],
  'rating_avg': 4.8, 'review_count': 3, 'pricing_monthly': 99,
  'years_experience': 5,
};

const _sent = 'Request sent! Your coach will be notified.';

void main() {
  final server = CoachToolsServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  List<(String, String)> records() =>
      [for (final f in reported) (f.origin, '${f.error}')];

  void noAccountText() {
    expect(find.textContaining('account changed'), findsNothing,
        reason: 'THE defect: the AccountChangedError text was shown');
    expect(find.textContaining('Not done'), findsNothing);
  }

  group('marketplace request', () {
    late User userA;

    Future<void> open(WidgetTester t) async {
      t.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(800, 3000);
      addTearDown(t.view.reset);
      await t.runAsync(() => signInAs(memberA));
      userA = Supabase.instance.client.auth.currentUser!;
      await t.pumpWidget(ProviderScope(overrides: [
        // Held at A: the provider that had not rebuilt yet (see the header).
        currentUserProvider.overrideWithValue(userA),
        coachMarketplaceProvider.overrideWith(
            (ref) async => [Map<String, dynamic>.from(_coach)]),
      ], child: const MaterialApp(home: CoachMarketplaceScreen())));
      await settleReal(t);
      expect(find.text('Request to Connect'), findsOneWidget, reason: 'premise');
    }

    for (final (what, to) in [('B signs in', memberB), ('A signs out', null)]) {
      testWidgets('$what while the request reads the status: nothing sent, '
          'nothing said, recorded once', (t) async {
        await open(t);
        final read = server.hold((s) =>
            s.table == 'coach_client_relationships' && s.query.contains('coach_id=eq.coach-c'));
        await t.tap(find.text('Request to Connect'));
        await settleReal(t);
        await t.runAsync(() => to == null ? signOut() : signInAs(to));
        expect(Supabase.instance.client.auth.currentUser?.id, to, reason: 'premise');
        read.complete();
        await settleReal(t);
        expect(server.writes, isEmpty, reason: 'nothing may be sent');
        noAccountText();
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text(_sent), findsNothing);
        expect(records(), [
          ('CoachRelationshipService.requestCoach',
              'Coaching request: the signed-in account changed')
        ]);
        await unmountAll(t);
      });
    }

    testWidgets('control, the same account: one request as A, said once, '
        'nothing recorded', (t) async {
      await open(t);
      await t.tap(find.text('Request to Connect'));
      await settleReal(t);
      final upserts = server.to('coach_client_relationships').where((s) => s.isWrite);
      expect(upserts, hasLength(1));
      expect(upserts.single.who, memberA);
      expect(upserts.single.json['client_id'], memberA);
      expect(find.text(_sent), findsOneWidget);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets('control: a refusal written to be shown is still shown',
        (t) async {
      await open(t);
      server.tables['coach_client_relationships'] = [
        {'client_id': memberA, 'coach_id': 'coach-c', 'status': 'active'}
      ];
      await t.tap(find.text('Request to Connect'));
      await settleReal(t);
      expect(find.text('This coach is already your coach.'), findsOneWidget);
      expect(server.writes, isEmpty);
      await unmountAll(t);
    });
  });

  group('pricing sheet save', () {
    setUp(() {
      server.tables['user_profiles'] = [
        {'id': memberA, 'pricing_monthly': 120},
        {'id': memberB, 'pricing_monthly': 300},
      ];
    });

    Future<void> open(WidgetTester t) async {
      await t.runAsync(() => signInAs(memberA));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) =>
          TextButton(onPressed: () => showCoachPricingSheet(c),
              child: const Text('open'))))));
      await t.tap(find.text('open'));
      await settleReal(t);
    }

    testWidgets("B signs in while A's save matches no row: nothing said, "
        'recorded ONCE (the service\'s)', (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), '150');
      server.zeroRows = (s) => s.isWrite;
      final hold = server.hold((s) => s.isWrite);
      await t.tap(find.text('Save price'));
      await settleReal(t);
      await t.runAsync(() => signInAs(memberB));
      hold.complete();
      await settleReal(t);
      expect(server.writes.single.who, memberA);
      expect(server.writes.single.query, contains('id=eq.$memberA'));
      noAccountText();
      expect(find.byType(SnackBar), findsNothing);
      expect(records(), [
        ('CoachRelationshipService.setGlobalPrice',
            'Coaching price: the signed-in account changed')
      ], reason: 'THE defect: recorded twice (the service and the sheet)');
      await unmountAll(t);
    });

    testWidgets('control, the same account: a 0-row save is still said in the '
        'sheet and recorded once', (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), '150');
      server.zeroRows = (s) => s.isWrite;
      await t.tap(find.text('Save price'));
      await settleReal(t);
      expect(find.text("Your price couldn't be saved. Nothing was changed — try again."),
          findsOneWidget);
      expect(records().map((r) => r.$1), ['CoachPricingSheet._save']);
      await unmountAll(t);
    });
  });
}
