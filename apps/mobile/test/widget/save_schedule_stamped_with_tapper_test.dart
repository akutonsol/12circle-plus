import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart'
    show AccountChangedError;
import 'package:circle_fitness/features/coach/data/package_service.dart';
import 'package:circle_fitness/features/coach/presentation/choose_package_screen.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/packages_server.dart';

// P0-RM-1 round 2 (security S-2) · `PackageService.saveSchedule` stamped the
// schedule with whoever was signed in WHEN THE CALL RAN (`_requireSignedIn()`),
// not with the client who tapped. Choose Package checks its client through a
// provider that may not have rebuilt yet, so a switch between the tap and the
// call saved A's chosen package, days and times as B's `client_schedules`
// row. Now the screen passes the client captured at the tap (`expectedUid`)
// and the service refuses for anyone else: nothing sent, AccountChangedError
// (sent: false), recorded once.
//
// The REAL service and the REAL auth client against a fake PostgREST that
// answers a write with rows only when `select=` asks for them. The widget case
// holds `currentUserProvider` at A on purpose: the provider that had not
// rebuilt when B's sign-in reached the auth client.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d -- apps/mobile/lib/features/coach/
// data/package_service.dart apps/mobile/lib/features/coach/presentation/
// choose_package_screen.dart` (the service cases do not compile there: no
// `expectedUid`; the widget case runs and B's row is written).

class _Payments extends PaymentService {
  int checkouts = 0;
  @override
  Future<bool> startCheckout({required String kind, String? coachId,
      String? eventId, String? packageId, String? tier}) async {
    checkouts++;
    return true;
  }
}

const _changed = 'Saving a schedule: the signed-in account changed';

void main() {
  final server = PackagesServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPackagesSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    await Supabase.instance.client.auth.recoverSession(sessionFor(userA));
  });
  tearDown(resetFailureSink);

  List<(String, String)> records() =>
      [for (final f in reported) (f.origin, '${f.error}')];

  Map<String, Object?> body(String line) =>
      jsonDecode(line.substring(line.indexOf(' {') + 1)) as Map<String, Object?>;

  Future<void> save(PackageService svc, String? owner) => svc.saveSchedule(
        coachId: 'c1',
        packageId: 'paid',
        days: const ['mon', 'wed'],
        sessionTime: '07:00',
        dayTimes: const {'mon': '07:00', 'wed': '07:00'},
        expectedUid: owner,
      );

  group('service', () {
    for (final (what, to) in [('B signed in', userB), ('signed out', null)]) {
      test('A tapped, $what before the call: nothing sent, refused, recorded '
          'once', () async {
        await Supabase.instance.client.auth.signOut();
        if (to != null) {
          await Supabase.instance.client.auth.recoverSession(sessionFor(to));
        }
        await expectLater(save(PackageService(), userA),
            throwsA(isA<AccountChangedError>().having((e) => e.sent, 'sent', false)));
        expect(server.writes, isEmpty, reason: "A's schedule was saved as $to");
        expect(server.schedules, isEmpty);
        expect(records(), [('PackageService.saveSchedule', _changed)]);
      });
    }

    test('B signs in while the upsert is in flight: the row is A\'s, it '
        'returns (saved), no record here — the caller records the outcome',
        () async {
      server.writeGate = Completer();
      final done = save(PackageService(), userA);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.writes, hasLength(1), reason: 'premise: it went out');
      await Supabase.instance.client.auth.signOut();
      await Supabase.instance.client.auth.recoverSession(sessionFor(userB));
      server.writeGate!.complete();
      await done;
      expect(body(server.writes.single)['client_id'], userA);
      expect(server.schedules.keys, [userA]);
      expect(reported, isEmpty);
    });

    test('B signs in while the upsert is in flight and it matched no row: '
        'AccountChangedError, sent: false, recorded once', () async {
      server.writeGate = Completer();
      server.writeMode = (_) => Answer.zeroRows;
      final done = save(PackageService(), userA);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await Supabase.instance.client.auth.signOut();
      await Supabase.instance.client.auth.recoverSession(sessionFor(userB));
      server.writeGate!.complete();
      await expectLater(done,
          throwsA(isA<AccountChangedError>().having((e) => e.sent, 'sent', false)));
      expect(server.writes, hasLength(1));
      expect(body(server.writes.single)['client_id'], userA);
      expect(records(), [('PackageService.saveSchedule', _changed)]);
    });

    test('control, the same account: saved once as A, nothing recorded',
        () async {
      await save(PackageService(), userA);
      expect(server.writes, hasLength(1));
      expect(server.writes.single, contains('select=id'));
      expect(body(server.writes.single)['client_id'], userA);
      expect(reported, isEmpty);
    });

    test('control, the same account, token refreshed (session replaced): '
        'saved as A', () async {
      await Supabase.instance.client.auth.recoverSession(sessionFor(userA));
      await save(PackageService(), userA);
      expect(body(server.writes.single)['client_id'], userA);
      expect(reported, isEmpty);
    });

    test('control, the same account, 0 rows: still PackageNotChanged', () async {
      server.writeMode = (_) => Answer.zeroRows;
      await expectLater(save(PackageService(), userA),
          throwsA(isA<PackageNotChanged>()));
      expect(reported, isEmpty);
    });
  });

  group('Choose Package', () {
    late _Payments payments;

    Future<void> open(WidgetTester t) async {
      t.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(900, 2600);
      addTearDown(t.view.reset);
      payments = _Payments();
      server.packages.add({
        'id': 'paid', 'coach_id': 'c1', 'type': 'monthly', 'name': 'Paid Plan',
        'price': 99, 'sessions': 0, 'description': '', 'active': true,
      });
      final userAObj = Supabase.instance.client.auth.currentUser!;
      final router = GoRouter(initialLocation: '/choose', routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME')), routes: [
          GoRoute(path: 'choose', builder: (_, __) =>
              const ChoosePackageScreen(coachId: 'c1', coachName: 'Avery')),
        ]),
      ]);
      addTearDown(router.dispose);
      await t.pumpWidget(ProviderScope(overrides: [
        paymentServiceProvider.overrideWithValue(payments),
        // Held at A: the provider that had not rebuilt (see the header).
        currentUserProvider.overrideWithValue(userAObj),
      ], child: MaterialApp.router(routerConfig: router)));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.tap(find.text('Paid Plan'));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> tapPay(WidgetTester t) async {
      const pay = r'Continue to payment · $99/mo';
      await t.ensureVisible(find.text(pay));
      await t.tap(find.text(pay), warnIfMissed: false);
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('B signed in between the tap and the call: no row for B, no '
        'checkout, nothing said, recorded once', (t) async {
      await open(t);
      await t.runAsync(() async {
        await Supabase.instance.client.auth.signOut();
        await Supabase.instance.client.auth.recoverSession(sessionFor(userB));
      });
      await tapPay(t);
      expect(server.schedules.keys, isNot(contains(userB)),
          reason: "THE defect: A's chosen schedule was saved as B's");
      expect(server.writes, isEmpty);
      expect(payments.checkouts, 0);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('account changed'), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(records(), [('PackageService.saveSchedule', _changed)]);
    });

    testWidgets('control, the same account: saved as A, checkout once',
        (t) async {
      await open(t);
      await tapPay(t);
      expect(server.writes, hasLength(1));
      expect(body(server.writes.single)['client_id'], userA);
      expect(payments.checkouts, 1);
      expect(reported, isEmpty);
    });
  });
}
