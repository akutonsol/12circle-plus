import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/payments/presentation/manage_subscription_screen.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-62b / FL-62d part 1 · "Stop coach" on a PAID plan, with ONE coaching
// subscription each, across an account switch.
//
// Members A and B both pay coach c-1 (one active `coach` subscription each).
// The REAL Stop flows — Manage Subscription's "Stop" and Profile's "Cancel
// Coach" — run the REAL CoachRelationshipService against a fake PostgREST /
// functions server that answers by the bearer token, so the request log says
// who asked for which row. Nothing mounts an account scope, and each screen
// STAYS mounted across the switch.
//
// The matrix (each for both screens):
//  (1) control, the same account: one subscriptions read for A, one
//      cancel-subscription for A's row, A is told the ends-at sentence;
//      through a token refresh too, and after A signs out and back in;
//  (2) B signs in after the dialog opened, before confirming: nothing is
//      sent, B's subscription is untouched, B is told nothing;
//  (3) B signs in (or A signs out) while A's subscriptions read is in flight:
//      no cancel-subscription at all, B told nothing, and the stop is
//      recorded ONCE;
//  (4) B signs in while A's cancel-subscription is in flight: no relationship
//      update, no notification, nothing said to B, recorded once.

const _a = memberA;
const _b = memberB;
const _coach = 'c-1';
// Midday UTC: the same calendar day wherever the test runs (it is shown local).
const _endsAt = '2027-03-03T12:00:00Z';
const _endsSaid = 'Your coaching continues until Mar 3, the end of the period '
    'you have paid for, then ends. Your coach has been notified.';

Map<String, Object?> _paid(String who) => {
      'id': 'sub-$who',
      'user_id': who,
      'coach_id': _coach,
      'kind': 'coach',
      'status': 'active',
      'current_period_end': _endsAt,
    };

/// One request as the server saw it.
typedef _Req = ({String who, String method, String name, Map<String, String> q, String body});

class _Server extends TwoMemberPostgrest {
  /// Every non-auth request.
  final log = <_Req>[];

  /// Held until completed, keyed `METHOD name:<who>`; cancelCoach's own
  /// subscriptions read (it filters by `coach_id`) is `GET subscriptions/coach:<who>`.
  final gates = <String, Completer<void>>{};

  @override
  void reset() {
    super.reset();
    log.clear();
    gates.clear();
  }

  Iterable<_Req> named(String name, {String? method}) =>
      log.where((r) => r.name == name && (method == null || r.method == method));

  Iterable<_Req> get restWrites =>
      log.where((r) => r.method != 'GET' && r.name != 'cancel-subscription' &&
          !r.name.startsWith('rpc/'));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    if (u.path.startsWith('/auth/v1/')) return super.send(request);
    final who = TwoMemberPostgrest.who(request);
    final name = u.path.contains('/rpc/')
        ? 'rpc/${u.path.split('/').last}'
        : u.path.split('/').last;
    final body = request is http.Request ? request.body : '';
    final r = (who: who, method: request.method, name: name, q: u.queryParameters, body: body);
    log.add(r);
    final gateKey = name == 'subscriptions' && u.queryParameters.containsKey('coach_id')
        ? '${request.method} subscriptions/coach:$who'
        : '${request.method} $name:$who';
    final (status, answer) = _answer(r, request);
    final gate = gates[gateKey];
    if (gate != null) await gate.future;
    if (status == 204) {
      return http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(answer))), status,
        request: request, headers: {'content-type': 'application/json'});
  }

  /// What is true when the request ARRIVES (RLS: each member sees their own).
  (int, Object?) _answer(_Req r, http.BaseRequest request) {
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    if (r.name == 'cancel-subscription') {
      return (200, {'ok': true, 'endsAt': _endsAt});
    }
    if (r.name == 'rpc/client_plan') return (200, 'coach_guided');
    if (r.name.startsWith('rpc/')) return (200, null);
    if (r.method != 'GET') {
      return r.q.containsKey('select')
          ? (200, single ? {'id': 'row-1'} : [{'id': 'row-1'}])
          : (204, null);
    }
    final rows = switch (r.name) {
      'subscriptions' => [_paid(r.who)],
      'coach_client_relationships' => [
          {'id': 'rel-${r.who}', 'coach_id': _coach, 'client_id': r.who, 'status': 'active'}
        ],
      'public_profiles' => [
          {'id': _coach, 'first_name': 'Anna', 'last_name': 'Coach'}
        ],
      _ => const <Map<String, Object?>>[],
    };
    final found = [
      for (final row in rows)
        if (r.q.entries.every((f) => _matches(row, f.key, f.value))) row
    ];
    return (200, single ? (found.isEmpty ? null : found.first) : found);
  }

  static bool _matches(Map<String, Object?> row, String col, String v) {
    if (!row.containsKey(col)) return true;
    if (v.startsWith('eq.')) return '${row[col]}' == v.substring(3);
    if (v.startsWith('in.(') && v.endsWith(')')) {
      return v.substring(4, v.length - 1).split(',')
          .map((x) => x.replaceAll('"', '')).contains('${row[col]}');
    }
    return true;
  }
}

void main() {
  final server = _Server();
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

  bool seen(Finder f) => f.evaluate().isNotEmpty;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> switchTo(WidgetTester t, String? uid) async {
    await t.runAsync(() => uid == null ? signOut() : signInAs(uid));
    await t.pump();
  }

  Future<void> unmount(WidgetTester t) async {
    for (final g in server.gates.values) {
      if (!g.isCompleted) g.complete();
    }
    await settle(t);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
    await t.runAsync(signOut);
  }

  /// The records of a stop for an account change.
  Iterable<AppFailure> accountChanges() =>
      reported.where((f) => '${f.error}'.contains('the signed-in account changed'));

  /// cancelCoach's own subscriptions reads (it filters by coach).
  Iterable<_Req> coachSubReads() =>
      server.named('subscriptions').where((r) => r.q.containsKey('coach_id'));

  Iterable<_Req> invokes() => server.named('cancel-subscription');

  void nothingSentAfterTheSwitch() {
    expect(invokes(), isEmpty, reason: 'a subscription was cancelled');
    expect(server.restWrites, isEmpty,
        reason: 'a relationship update or notification went out');
    expect(server.log.where((r) => r.body.contains('sub-$_b')), isEmpty,
        reason: "B's subscription was touched");
  }

  void nothingSaidToB() {
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('oaching'), findsNothing);
    expect(find.textContaining('account changed'), findsNothing);
  }

  // Each flow: how to open it as A, how to reach its confirm, the confirm.
  final flows = <({
    String name,
    Future<void> Function(WidgetTester) open,
    Future<void> Function(WidgetTester) toConfirm,
    Finder dialog,
    Finder confirm,
  })>[
    (
      name: 'Manage Subscription "Stop"',
      open: (t) async {
        await t.binding.setSurfaceSize(const Size(700, 3200));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.runAsync(() => signInAs(_a));
        await t.pumpWidget(
            const ProviderScope(child: MaterialApp(home: ManageSubscriptionScreen())));
        await pumpUntil(t, () => seen(find.text('Stop')), what: "A's coach");
        await settle(t);
      },
      toConfirm: (t) async {
        await t.tap(find.text('Stop'));
        await pumpUntil(t, () => seen(find.text('Stop working with Anna Coach?')),
            what: 'the dialog');
        await settle(t);
      },
      dialog: find.text('Stop working with Anna Coach?'),
      confirm: find.text('Yes, stop'),
    ),
    (
      name: 'Profile "Cancel Coach"',
      open: (t) async {
        t.view.physicalSize = const Size(900, 2000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.runAsync(() => signInAs(_a));
        await t.pumpWidget(ProviderScope(
          overrides: [
            assignedCoachProvider.overrideWith((ref) async =>
                {'id': _coach, 'first_name': 'Anna', 'last_name': 'Coach'}),
            clientRelationshipProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: MyCoachSection(onCoachCancelled: () {}))),
          ),
        ));
        await pumpUntil(t, () => seen(find.text('Cancel Coach')), what: "A's coach");
        await settle(t);
      },
      toConfirm: (t) async {
        await t.tap(find.text('Cancel Coach'));
        await pumpUntil(t, () => seen(find.text('Cancel Your Coach')),
            what: 'the sheet');
        await settle(t);
        await t.tap(find.text('Not a good fit'));
        await t.pump();
      },
      dialog: find.text('Cancel Your Coach'),
      confirm: find.text('Cancel Coach').last,
    ),
  ];

  for (final flow in flows) {
    group(flow.name, () {
      Future<void> confirmed(WidgetTester t) async {
        await t.tap(flow.confirm);
        await t.pump();
      }

      // ── (1) controls ──────────────────────────────────────────────────────
      for (final (what, before) in <(String, Future<void> Function(WidgetTester)?)>[
        ('as opened', null),
        ('after A signed out and back in', (t) async {
          await switchTo(t, null);
          await settle(t);
          await switchTo(t, _a);
          await settle(t);
          await pumpUntil(t, () => seen(find.text(flow.name.contains('Stop"') ? 'Stop' : 'Cancel Coach')),
              what: "A's coach again");
        }),
      ]) {
        testWidgets('(1) control, the same account ($what): one cancel-subscription '
            "for A's row, and A is told when it ends", (t) async {
          await flow.open(t);
          if (before != null) await before(t);
          await flow.toConfirm(t);
          server.log.clear();
          await confirmed(t);
          await pumpUntil(t, () => seen(find.text(_endsSaid)), what: 'the outcome');
          await settle(t);
          final read = coachSubReads().single;
          expect(read.who, _a);
          expect(read.q['user_id'], 'eq.$_a');
          expect(read.q['coach_id'], 'eq.$_coach');
          expect(invokes().map((r) => (r.who, jsonDecode(r.body)['subscriptionId'])),
              [(_a, 'sub-$_a')]);
          expect(server.restWrites, isEmpty,
              reason: 'a paid coach is ended by the subscription (decision 2)');
          expect(find.text(_endsSaid), findsOneWidget);
          expect(accountChanges(), isEmpty);
          await unmount(t);
        });
      }

      testWidgets('(1) control, a token refresh during the cancellation: as before',
          (t) async {
        await flow.open(t);
        await flow.toConfirm(t);
        server.log.clear();
        final gate = server.gates['POST cancel-subscription:$_a'] = Completer();
        await confirmed(t);
        await pumpUntil(t, () => invokes().isNotEmpty, what: 'A asked');
        await t.runAsync(refreshSession);
        gate.complete();
        await pumpUntil(t, () => seen(find.text(_endsSaid)), what: 'the outcome');
        await settle(t);
        expect(invokes().map((r) => r.who), [_a]);
        expect(server.restWrites, isEmpty);
        expect(find.text(_endsSaid), findsOneWidget);
        expect(accountChanges(), isEmpty);
        await unmount(t);
      });

      // ── (2) after the dialog opened, before confirming ───────────────────
      testWidgets("(2) B signs in over A's open dialog: it goes, nothing is "
          'sent, nothing said', (t) async {
        await flow.open(t);
        await flow.toConfirm(t);
        server.log.clear();
        await switchTo(t, _b);
        await settle(t);
        expect(flow.dialog, findsNothing,
            reason: "THE defect: A's Stop dialog stayed up for B to confirm");
        nothingSentAfterTheSwitch();
        expect(coachSubReads(), isEmpty);
        nothingSaidToB();
        await unmount(t);
      });

      testWidgets('(2) no frame: B signs in and A\'s confirm lands before any '
          'frame: nothing is sent, nothing said', (t) async {
        await flow.open(t);
        await flow.toConfirm(t);
        server.log.clear();
        final button = t.widget(find
            .ancestor(of: flow.confirm, matching: find.byWidgetPredicate(
                (w) => w is GestureDetector || w is TextButton))
            .first);
        await t.runAsync(() => signInAs(_b));
        if (button is TextButton) {
          button.onPressed!();
        } else {
          (button as GestureDetector).onTap!();
        }
        await settle(t);
        nothingSentAfterTheSwitch();
        expect(coachSubReads(), isEmpty);
        nothingSaidToB();
        expect(accountChanges(), hasLength(1),
            reason: 'the stop is recorded once');
        await unmount(t);
      });

      // ── (3) while A's subscriptions read is in flight ────────────────────
      for (final (what, next) in [('B signs in', _b), ('A signs out', null)]) {
        testWidgets("(3) $what while A's subscriptions read is in flight: no "
            'cancel-subscription at all, nothing said, recorded once', (t) async {
          await flow.open(t);
          await flow.toConfirm(t);
          server.log.clear();
          final gate = server.gates['GET subscriptions/coach:$_a'] = Completer();
          await confirmed(t);
          await pumpUntil(t, () => coachSubReads().isNotEmpty, what: 'A asked');
          expect(coachSubReads().single.q['user_id'], 'eq.$_a', reason: 'premise');
          await switchTo(t, next);
          gate.complete();
          await settle(t);
          nothingSentAfterTheSwitch();
          nothingSaidToB();
          expect(accountChanges(), hasLength(1),
              reason: 'THE defect: the one stop was recorded '
                  '${accountChanges().length} times');
          await unmount(t);
        });
      }

      // ── (4) while A's cancel-subscription is in flight ───────────────────
      testWidgets("(4) B signs in while A's cancel-subscription is in flight: no "
          'relationship update, no notification, nothing said to B', (t) async {
        await flow.open(t);
        await flow.toConfirm(t);
        server.log.clear();
        final gate = server.gates['POST cancel-subscription:$_a'] = Completer();
        await confirmed(t);
        await pumpUntil(t, () => invokes().isNotEmpty, what: 'A asked');
        await switchTo(t, _b);
        gate.complete();
        await settle(t);
        expect(invokes().map((r) => (r.who, jsonDecode(r.body)['subscriptionId'])),
            [(_a, 'sub-$_a')], reason: "only A's, once");
        expect(server.restWrites, isEmpty);
        expect(server.log.where((r) => r.body.contains('sub-$_b')), isEmpty);
        nothingSaidToB();
        expect(accountChanges(), hasLength(1));
        await unmount(t);
      });
    });
  }
}
