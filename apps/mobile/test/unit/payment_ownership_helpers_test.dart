import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:circle_fitness/features/payments/presentation/checkout_launcher.dart';

import '../support/two_member_postgrest.dart';

// P0-FL-60a, rounds 2 and 3 · the helpers the payment screens share, against the
// real auth client: who a read's value belongs to (ownedReadProvider), what a
// failure says about the outcome (definitelyRefused, CancelOutcome) and the
// owner check of launchCheckout. The screens are in
// test/widget/payment_failures_recorded_and_owned_test.dart.

class _Server extends TwoMemberPostgrest {
  (int, Object?) answer = (200, const {'ok': true});
  final functions = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.startsWith('/functions/')) return super.send(request);
    functions.add(request.url.path.split('/').last);
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(answer.$2))), answer.$1,
        request: request, headers: {'content-type': 'application/json'});
  }
}

const _a = memberA;
const _b = memberB;

void main() {
  final server = _Server();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });
  setUp(() {
    server.reset();
    server.functions.clear();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  group('ownedReadProvider', () {
    test('a settled value keeps the account its read started for, whoever is '
        'signed in when it is looked at', () async {
      await signInAs(_a);
      var reads = 0;
      // A source that is NOT re-read on an account change: it stays settled.
      final source = FutureProvider<String>((ref) async => 'read ${++reads}');
      final owned = ownedReadProvider(source);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(owned, (_, __) {});
      await pumpEventQueue();
      expect(c.read(owned).value, 'read 1');
      await signInAs(_b);
      await pumpEventQueue();
      expect(c.read(source).value, 'read 1', reason: 'premise: still settled');
      expect(c.read(owned).hasValue, isFalse, reason: "A's value became B's");
      c.invalidate(source);
      await pumpEventQueue();
      expect(c.read(owned).value, 'read 2', reason: "B's own read is B's");
      await signInAs(_a);
      await pumpEventQueue();
      expect(c.read(owned).hasValue, isFalse, reason: "B's value became A's");
    });

    test("a read that starts after the auth client changed and before the app "
        'knows counts for nobody', () async {
      await signInAs(_a);
      var reads = 0;
      final source = FutureProvider<String>((ref) async => 'read ${++reads}');
      final owned = ownedReadProvider(source);
      // The app still believes in A while the client is B's.
      final c = ProviderContainer(
          overrides: [paymentAccountProvider.overrideWithValue(_a)]);
      addTearDown(c.dispose);
      c.listen(owned, (_, __) {});
      await pumpEventQueue();
      expect(c.read(owned).value, 'read 1');
      await signInAs(_b);
      c.invalidate(source);
      await pumpEventQueue();
      expect(c.read(source).value, 'read 2', reason: 'premise');
      expect(c.read(owned).hasValue, isFalse,
          reason: "B's answer was taken for A's");
    });


    test('a source first seen settled is its account\'s; a failure is recorded '
        'once', () async {
      await signInAs(_a);
      var fail = false;
      final source = FutureProvider<String>((ref) async {
        ref.watch(paymentAccountProvider);
        if (fail) throw StateError('down');
        return 'value';
      });
      final owned = ownedReadProvider(source, origin: 'here');
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(source, (_, __) {});
      await c.read(source.future);
      c.listen(owned, (_, __) {});
      expect(c.read(owned).value, 'value');
      fail = true;
      c.invalidate(source);
      await pumpEventQueue();
      expect(c.read(owned).error, isNotNull);
      expect(c.read(owned).value, 'value', reason: 'a failed refresh keeps it');
      expect(reported.map((f) => f.origin), ['here']);
      c.invalidate(source);
      await pumpEventQueue();
      expect(reported.map((f) => f.origin), ['here', 'here']);
      fail = false;
      c.invalidate(source);
      await pumpEventQueue();
      expect(c.read(owned).error, isNull);
    });

    test('a read in flight across the change is the new account\'s', () async {
      await signInAs(_a);
      final gates = <Completer<String>>[];
      final source = FutureProvider<String>((ref) {
        ref.watch(paymentAccountProvider);
        gates.add(Completer());
        return gates.last.future;
      });
      final owned = ownedReadProvider(source);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // Nobody watches the owned read but what keeps its owners: as when the
      // screen was opened, left, and comes back after the change.
      c.listen(owned, (_, __) {}).close();
      c.read(owned);
      await signInAs(_b);
      await pumpEventQueue();
      expect(gates, hasLength(2), reason: 'premise: loading → loading');
      gates[0].complete("A's");
      gates[1].complete("B's");
      await pumpEventQueue();
      expect(c.read(owned).value, "B's");
    });
  });

  group('launchCheckout', () {
    testWidgets('no-frame: launchCheckout for another account sends nothing',
        (t) async {
      await t.runAsync(() => signInAs(_b));
      late BuildContext ctx;
      late WidgetRef ref;
      await t.pumpWidget(ProviderScope(
          child: MaterialApp(
              home: Scaffold(body: Consumer(builder: (c, r, __) {
        ctx = c;
        ref = r;
        return const SizedBox();
      })))));
      bool? started;
      await t.runAsync(() async => started = await launchCheckout(ctx, ref,
          kind: 'coach_plan', tier: 'growth', owner: _a));
      await t.pump();
      expect(started, isFalse);
      expect(server.functions, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(reported.single.origin, 'launchCheckout');
    });

  });

  group('OwnedDialog', () {
    Future<void> ask(WidgetTester t, {required String? owner}) async {
      await t.pumpWidget(const ProviderScope(
          child: MaterialApp(home: Scaffold(body: Text('page')))));
      unawaited(showDialog<bool>(
          context: t.element(find.text('page')),
          builder: (_) => OwnedDialog(
              owner: owner, child: const AlertDialog(title: Text("A's")))));
      await t.pump();
    }

    testWidgets('put up for an account already gone: not drawn in its first '
        'frame, and taken away', (t) async {
      await t.runAsync(() => signInAs(_b));
      await ask(t, owner: _a);
      expect(find.text("A's"), findsNothing);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(OwnedDialog), findsNothing, reason: 'its barrier too');
      expect(find.text('page'), findsOneWidget);
    });

    testWidgets('under another route, it still goes with its account', (t) async {
      await t.runAsync(() => signInAs(_a));
      await ask(t, owner: _a);
      await t.pump(const Duration(seconds: 1));
      expect(find.text("A's"), findsOneWidget, reason: 'control: drawn for A');
      unawaited(showDialog<void>(
          context: t.element(find.text("A's")),
          builder: (_) => const AlertDialog(title: Text('on top'))));
      await t.pump(const Duration(seconds: 1));
      await t.runAsync(() => signInAs(_b));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(OwnedDialog, skipOffstage: false), findsNothing);
      expect(find.text('on top'), findsOneWidget);
    });
  });

  group('what a failure says about the outcome', () {
    for (final (e, refused) in <(Object, bool)>[
      (const FunctionException(status: 400), true),
      (const FunctionException(status: 403), true),
      (const FunctionException(status: 408), false),
      (const FunctionException(status: 500), false),
      (const FunctionException(status: 502), false),
      (
        const FunctionException(
            status: 502, details: {'error': 'stripe_cancel_failed'}),
        true
      ),
      (
        const FunctionException(
            status: 503, details: {'error': 'Could not read your membership'}),
        true
      ),
      (const FunctionException(status: 409), true),
      (const FunctionException(status: 429), true),
      // A 503 is "nothing changed" only where the function says so.
      (const FunctionException(status: 503), false),
      (
        const FunctionException(status: 503, details: {'error': 'other'}),
        false
      ),
      for (final s in [504, 520, 522, 524, 546])
        (FunctionException(status: s), false),
      // Round 4: the database's answer, or a 4xx, is a refusal …
      for (final c in [
        '42501', '23505', '57014', 'P0001', 'XX000', // SQLSTATE
        'PGRST116', 'PGRST202', 'PGRST301',
        '400', '401', '403', '404', '406', '409', '429', // no code in the body
      ])
        (PostgrestException(message: 'x', code: c), true),
      // … a status that is not, and a code nobody knows, are not.
      for (final c in [
        '408', '500', '502', '503', '504', '520', '522', '524', '599',
        '200', '302', '600', '', 'null', 'x', 'UNKNOWN', 'GATEWAY_TIMEOUT',
        '4040', 'pgrst116', 'x42501', '425011', 'PGRST', 'ERROR', 'xPGRST116',
      ])
        (PostgrestException(message: 'x', code: c), false),
      (const PostgrestException(message: 'x'), false),
      (http.ClientException('lost'), false),
      (TimeoutException('slow'), false),
      (StateError('unreadable'), false),
    ]) {
      test('$e: ${refused ? 'refused' : 'not known'}', () {
        expect(definitelyRefused(e), refused);
      });
    }

    test('a cancellation: unconfirmed, then refused, then cancelled', () async {
      final svc = PaymentService();
      await signInAs(_a);
      server.answer = (500, {'message': 'x'});
      expect(
          await svc.cancelSubscriptionOutcome('s'), CancelOutcome.unconfirmed);
      server.answer = (403, {'error': 'x'});
      expect(await svc.cancelSubscriptionOutcome('s'), CancelOutcome.refused);
      server.answer = (200, {'ok': true});
      expect(await svc.cancelSubscriptionOutcome('s'), CancelOutcome.cancelled);
    });

    test('a plain cancelSubscription that was unconfirmed does not colour a '
        'later refusal', () async {
      final svc = PaymentService();
      await signInAs(_a);
      server.answer = (500, {'message': 'x'});
      expect(await svc.cancelSubscription('s'), isFalse);
      server.answer = (403, {'error': 'x'});
      expect(await svc.cancelSubscriptionOutcome('s'), CancelOutcome.refused);
    });
  });
}
