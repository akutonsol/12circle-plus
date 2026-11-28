import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/choose_package_screen.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/packages_server.dart';

// P0-RM-1 (C15-63b-04) · Choose Package drops the package checkout's outcome
// after an account change — at the check after the schedule is saved, and at
// the one after the checkout was asked for — and recorded nothing. Now
// (FL-63b treatment): recorded once as `package checkout outcome not shown`,
// nothing said to whoever is signed in now, no amount, name or package in the
// record. No payment behaviour changes: what is asked of the payment service
// is the same, and nothing more is asked after the switch.
//
// The REAL screen and the REAL auth client; no AccountScope; the screen STAYS
// mounted across the switch.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d --
// lib/features/coach/presentation/choose_package_screen.dart`.

class _Payments extends PaymentService {
  int checkouts = 0;
  Completer<void>? hold;
  @override
  Future<bool> startCheckout({required String kind, String? coachId,
      String? eventId, String? packageId, String? tier}) async {
    checkouts++;
    await hold?.future;
    return true;
  }
}

Map<String, Object?> _pkg(String id, String name, {num price = 99}) => {
      'id': id, 'coach_id': 'c1', 'type': 'monthly', 'name': name,
      'price': price, 'sessions': 0, 'description': '', 'active': true,
    };

const _pay = r'Continue to payment · $99/mo';
const _said = 'Schedule saved — complete payment to activate your coaching.';
const _record =
    'Bad state: package checkout outcome not shown: the signed-in account changed';

void main() {
  final server = PackagesServer();
  final reported = <AppFailure>[];
  late _Payments payments;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPackagesSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    payments = _Payments();
    server.packages.add(_pkg('paid', 'Paid Plan'));
    await Supabase.instance.client.auth.recoverSession(sessionFor(userA));
  });
  tearDown(resetFailureSink);

  List<(String, String)> records() =>
      [for (final f in reported) (f.origin, '${f.error}')];

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2600);
    addTearDown(t.view.reset);
    final router = GoRouter(initialLocation: '/choose', routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME')), routes: [
        GoRoute(path: 'choose', builder: (_, __) =>
            const ChoosePackageScreen(coachId: 'c1', coachName: 'Avery')),
      ]),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(ProviderScope(overrides: [
      paymentServiceProvider.overrideWithValue(payments),
    ], child: MaterialApp.router(routerConfig: router)));
    await settle(t);
    await t.tap(find.text('Paid Plan'));
    await settle(t);
  }

  Future<void> tapPay(WidgetTester t) async {
    await t.ensureVisible(find.text(_pay));
    await t.tap(find.text(_pay), warnIfMissed: false);
    await t.pump();
  }

  Future<void> change(WidgetTester t, String? to) async {
    await t.runAsync(() => Supabase.instance.client.auth.signOut());
    if (to != null) {
      await t.runAsync(() =>
          Supabase.instance.client.auth.recoverSession(sessionFor(to)));
    }
  }

  void nothingSaid() {
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(_said), findsNothing);
    expect(find.textContaining('account changed'), findsNothing);
  }

  for (final (what, to) in [('B signs in', userB), ('A signs out', null)]) {
    testWidgets('$what while the schedule save is in flight: no checkout is '
        'asked for anyone, nothing said, the outcome recorded once', (t) async {
      await open(t);
      server.writeGate = Completer();
      await tapPay(t);
      await settle(t);
      expect(server.writes, hasLength(1), reason: 'premise: the save went out');
      await change(t, to);
      server.writeGate!.complete();
      await settle(t);
      expect(payments.checkouts, 0, reason: 'a checkout was asked after the switch');
      nothingSaid();
      expect(records(), [('ChoosePackageScreen._save', _record)],
          reason: 'THE defect: the saved schedule\'s outcome was dropped '
              'without a record');
    });

    testWidgets('$what while the checkout is being opened: nothing said, the '
        'outcome recorded once', (t) async {
      await open(t);
      payments.hold = Completer();
      await tapPay(t);
      await settle(t);
      expect(payments.checkouts, 1, reason: 'premise: asked, once');
      await change(t, to);
      payments.hold!.complete();
      await settle(t);
      expect(payments.checkouts, 1);
      nothingSaid();
      expect(records(), [('ChoosePackageScreen._save', _record)],
          reason: 'THE defect: the checkout\'s outcome was dropped without a '
              'record');
    });
  }

  testWidgets('A -> B -> A while the checkout is being opened: the screen was '
      'reset for the new sign-in, so the old outcome is not said; recorded once',
      (t) async {
    await open(t);
    payments.hold = Completer();
    await tapPay(t);
    await settle(t);
    await change(t, userB);
    await settle(t);
    await change(t, userA);
    await settle(t);
    payments.hold!.complete();
    await settle(t);
    nothingSaid();
    expect(records(), [('ChoosePackageScreen._save', _record)]);
  });

  testWidgets('control, the same account: saved, checkout asked once, said '
      'once, nothing recorded', (t) async {
    await open(t);
    payments.hold = Completer();
    await tapPay(t);
    await settle(t);
    // The same member's session again: not a change of account.
    await t.runAsync(() =>
        Supabase.instance.client.auth.recoverSession(sessionFor(userA)));
    payments.hold!.complete();
    await settle(t);
    expect(payments.checkouts, 1);
    expect(find.text(_said), findsOneWidget);
    expect(reported, isEmpty);
  });
}
