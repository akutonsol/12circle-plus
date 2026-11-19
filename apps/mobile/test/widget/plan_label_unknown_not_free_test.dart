import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:circle_fitness/features/payments/presentation/manage_subscription_screen.dart';
import 'package:circle_fitness/features/payments/presentation/upgrade_screen.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:circle_fitness/features/profile/presentation/subscription_screen.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/profile_read_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-17 · the plan label never says "Free" for a plan it could not read.
//
// clientPlanProvider (client_plan()) was read as `.valueOrNull ??
// ClientPlan.free` on Profile, Settings, Subscription, Manage subscription and
// Plans (Upgrade). While the read FAILED — or was still in flight — a coached
// client was shown "Free", and Plans marked Free as "Current" and offered the
// Coach-Guided plan they already had (and every membership) as purchasable.
//
// Each screen is pumped over a controllable plan read: failed (network or
// server), pending, or answered. HOW TO SEE THEM FAIL: check out the base
// commit's five screens (c9dd151); the failure/loading tests find "Free" /
// "FREE" / "Current" / enabled plan buttons, and no "Couldn't load your plan".

const _uid = '00000000-0000-4000-8000-0000000f1717';
const _offline = "Couldn't load your plan — check your connection and try again.";
const _failed = "Couldn't load your plan — try again in a moment. "
    'If it keeps happening, contact support.';

enum _Read { ok, network, server, pending }

/// The client_plan() read, controllable per test.
class _PlanSource {
  _Read mode = _Read.ok;
  ClientPlan plan = ClientPlan.free;
  int reads = 0;

  /// When set, a read is counted at once but answered only when it completes.
  Completer<void>? gate;

  void reset() {
    mode = _Read.ok;
    plan = ClientPlan.free;
    reads = 0;
    gate = null;
  }

  Future<ClientPlan> read() async {
    reads++;
    if (gate != null) await gate!.future;
    switch (mode) {
      case _Read.network:
        throw http.ClientException('Connection refused');
      case _Read.server:
        throw const PostgrestException(message: 'refused', code: 'XX000');
      case _Read.pending:
        return Completer<ClientPlan>().future; // never answers
      case _Read.ok:
        return plan;
    }
  }
}

void main() {
  late ProfileReadPostgrest server;
  final src = _PlanSource();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = ProfileReadPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    server.profile = {
      'id': _uid,
      'first_name': 'Ana',
      'last_name': 'Lee',
      'email': 'ana@example.com',
      'role': 'client',
      'unit_preference': 'metric',
    };
    src.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  /// Pumps [screen]. [settle] is false for a pending read (a spinner never
  /// settles).
  Future<void> open(WidgetTester tester, Widget screen,
      {bool settle = true}) async {
    await tester.binding.setSurfaceSize(const Size(600, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider
            .overrideWithValue(Supabase.instance.client.auth.currentUser),
        clientPlanProvider.overrideWith((ref) => src.read()),
        mySubscriptionsProvider.overrideWith((ref) async => const []),
        myCoachesProvider.overrideWith((ref) async => const []),
        membershipTierProvider.overrideWith((ref) async => null),
        assignedCoachProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(home: screen),
    ));
    if (settle) {
      await tester.pumpAndSettle();
      // postgrest retries a GET that hit a network failure, on timers.
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
  }

  Iterable<ElevatedButton> enabledPlanButtons(WidgetTester tester) => tester
      .widgetList<ElevatedButton>(find.byType(ElevatedButton))
      .where((b) => b.onPressed != null);

  // ── Plans (Upgrade) ──────────────────────────────────────────────────────
  group('Plans (Upgrade)', () {
    testWidgets('failed read: no "Current", nothing purchasable, a notice',
        (tester) async {
      src.mode = _Read.network;
      await open(tester, const UpgradeScreen());
      expect(find.text('Current'), findsNothing,
          reason: 'THE defect: Free was marked Current for an unread plan');
      expect(enabledPlanButtons(tester), isEmpty,
          reason: 'THE defect: every plan, incl. the one they have, was '
              'offered as purchasable');
      expect(find.text(_offline), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(reported.map((f) => f.origin), contains('UpgradeScreen.clientPlan'));
    });

    testWidgets('a server failure uses the support wording', (tester) async {
      src.mode = _Read.server;
      await open(tester, const UpgradeScreen());
      expect(find.text(_failed), findsOneWidget);
      expect(find.text(_offline), findsNothing);
    });

    testWidgets('loading: no "Current", nothing purchasable', (tester) async {
      src.mode = _Read.pending;
      await open(tester, const UpgradeScreen(), settle: false);
      expect(find.text('Current'), findsNothing);
      expect(enabledPlanButtons(tester), isEmpty);
      expect(find.text('Loading your plan…'), findsOneWidget);
    });

    testWidgets('Try again is busy-aware, 44px, labelled, live; then loads',
        (tester) async {
      src.mode = _Read.network;
      await open(tester, const UpgradeScreen());
      final button = find.ancestor(
          of: find.text('Try again'), matching: find.byType(TextButton));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('Try again, load your plan'), findsOneWidget);
      expect(
          find.ancestor(
              of: find.text(_offline),
              matching: find.byWidgetPredicate(
                  (w) => w is Semantics && (w.properties.liveRegion ?? false))),
          findsWidgets);

      final before = src.reads;
      src
        ..gate = Completer<void>()
        ..mode = _Read.ok
        ..plan = ClientPlan.coachGuided;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.text('Loading…'), findsOneWidget);
      await tester.tap(find.text('Loading…'), warnIfMissed: false);
      await tester.pump();
      expect(src.reads, before + 1, reason: 'no second read while in flight');
      src.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text(_offline), findsNothing);
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Find a Coach'), findsNothing,
          reason: 'Coach-Guided is current: its CTA is not offered');
    });

    testWidgets('control: success free marks Free current', (tester) async {
      await open(tester, const UpgradeScreen());
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Switch to Free'), findsNothing);
      expect(find.text('Upgrade to Self-Guided'), findsOneWidget);
      expect(enabledPlanButtons(tester), isNotEmpty);
      expect(reported, isEmpty);
    });

    testWidgets('control: success coach_guided marks Coach-Guided current',
        (tester) async {
      src.plan = ClientPlan.coachGuided;
      await open(tester, const UpgradeScreen());
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Find a Coach'), findsNothing);
      expect(find.text('Switch to Free'), findsOneWidget);
    });
  });

  // ── Manage subscription ─────────────────────────────────────────────────
  group('Manage subscription', () {
    testWidgets('failed read: "—", no "Free", a notice', (tester) async {
      src.mode = _Read.network;
      await open(tester, const ManageSubscriptionScreen());
      expect(find.text('Free'), findsNothing,
          reason: 'THE defect: the banner said "Free" for an unread plan');
      expect(find.textContaining('Free plan'), findsNothing);
      expect(find.text('—'), findsOneWidget);
      expect(find.text(_offline), findsOneWidget);
      expect(reported.map((f) => f.origin),
          contains('ManageSubscriptionScreen.clientPlan'));
    });

    testWidgets('loading: no "Free"', (tester) async {
      src.mode = _Read.pending;
      await open(tester, const ManageSubscriptionScreen(), settle: false);
      expect(find.text('Free'), findsNothing);
      expect(find.textContaining('Free plan'), findsNothing);
      expect(find.text('…'), findsOneWidget);
    });

    testWidgets('Try again re-reads and shows the plan', (tester) async {
      src.mode = _Read.server;
      await open(tester, const ManageSubscriptionScreen());
      expect(find.text(_failed), findsOneWidget);
      src
        ..mode = _Read.ok
        ..plan = ClientPlan.coachGuided;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Coach-Guided'), findsOneWidget);
      expect(find.text(_failed), findsNothing);
    });

    testWidgets('control: success free says "Free"', (tester) async {
      await open(tester, const ManageSubscriptionScreen());
      expect(find.text('Free'), findsOneWidget);
      expect(find.textContaining('Free plan'), findsOneWidget);
    });

    testWidgets('control: success coach_guided says "Coach-Guided"',
        (tester) async {
      src.plan = ClientPlan.coachGuided;
      await open(tester, const ManageSubscriptionScreen());
      expect(find.text('Coach-Guided'), findsOneWidget);
      expect(find.text('Free'), findsNothing);
    });
  });

  // ── Subscription (profile) ──────────────────────────────────────────────
  // Free maps to the "Basic" tier on this screen; its price reads "Free".
  group('Subscription', () {
    testWidgets('failed read: no tier is current, "—", a notice',
        (tester) async {
      src.mode = _Read.network;
      await open(tester, const SubscriptionScreen());
      expect(find.text('CURRENT'), findsNothing,
          reason: 'THE defect: Basic (Free) was marked current');
      expect(find.text('Basic'), findsOneWidget,
          reason: 'only the tier card, not the "Current Plan" hero');
      expect(find.text('—'), findsOneWidget);
      expect(find.text(_offline), findsOneWidget);
      expect(reported.map((f) => f.origin),
          contains('SubscriptionScreen.clientPlan'));
    });

    testWidgets('loading: no tier is current', (tester) async {
      src.mode = _Read.pending;
      await open(tester, const SubscriptionScreen(), settle: false);
      expect(find.text('CURRENT'), findsNothing);
      expect(find.text('Basic'), findsOneWidget);
      expect(find.text('…'), findsOneWidget);
    });

    testWidgets('Try again re-reads and shows the plan', (tester) async {
      src.mode = _Read.network;
      await open(tester, const SubscriptionScreen());
      src
        ..mode = _Read.ok
        ..plan = ClientPlan.coachGuided;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Elite'), findsNWidgets(2));
      expect(find.text(_offline), findsNothing);
    });

    testWidgets('control: success free shows Basic as current', (tester) async {
      await open(tester, const SubscriptionScreen());
      expect(find.text('Basic'), findsNWidgets(2));
      expect(find.text('CURRENT'), findsOneWidget);
    });

    testWidgets('control: success coach_guided shows Elite as current',
        (tester) async {
      src.plan = ClientPlan.coachGuided;
      await open(tester, const SubscriptionScreen());
      expect(find.text('Elite'), findsNWidgets(2));
      expect(find.text('CURRENT'), findsOneWidget);
    });
  });

  // ── Profile and Settings rows ───────────────────────────────────────────
  // Profile's stat cards also draw "—" for missing data, so the chip is found
  // by its retry icon and its semantics label, not by "—".
  final retryChip = find.ancestor(
      of: find.byIcon(Icons.refresh_rounded), matching: find.byType(InkWell));
  for (final (name, screen, origin) in [
    ('Profile', const ProfileScreen() as Widget, 'ProfileScreen.clientPlan'),
    ('Settings', const SettingsScreen() as Widget, 'SettingsScreen.clientPlan'),
  ]) {
    group('$name subscription row', () {
      testWidgets('failed read: "—", not "FREE"; reported', (tester) async {
        src.mode = _Read.network;
        await open(tester, screen);
        expect(find.text('FREE'), findsNothing,
            reason: 'THE defect: the row said FREE for an unread plan');
        expect(
            find.descendant(of: retryChip, matching: find.text('—')),
            findsOneWidget);
        expect(find.bySemanticsLabel(RegExp(RegExp.escape('$_offline Try again'))),
            findsOneWidget);
        expect(reported.map((f) => f.origin), contains(origin));
      });

      testWidgets('loading: a neutral placeholder, not "FREE"', (tester) async {
        src.mode = _Read.pending;
        await open(tester, screen, settle: false);
        expect(find.text('FREE'), findsNothing);
        expect(find.text('…'), findsOneWidget);
      });

      testWidgets('tapping "—" re-reads (busy-aware, 44px) and shows the plan',
          (tester) async {
        src.mode = _Read.network;
        await open(tester, screen);
        expect(tester.getSize(retryChip).height, greaterThanOrEqualTo(44));
        final before = src.reads;
        src
          ..gate = Completer<void>()
          ..mode = _Read.ok
          ..plan = ClientPlan.coachGuided;
        final at = tester.getCenter(retryChip);
        await tester.tapAt(at);
        await tester.pump();
        await tester.tapAt(at);
        await tester.pump();
        expect(src.reads, before + 1, reason: 'no second read while in flight');
        src.gate!.complete();
        await tester.pumpAndSettle();
        expect(find.text('COACH-GUIDED'), findsOneWidget);
        expect(retryChip, findsNothing);
      });

      testWidgets('control: success free says "FREE"', (tester) async {
        await open(tester, screen);
        expect(find.text('FREE'), findsOneWidget);
        expect(reported.where((f) => f.origin == origin), isEmpty);
      });

      testWidgets('control: success coach_guided says "COACH-GUIDED"',
          (tester) async {
        src.plan = ClientPlan.coachGuided;
        await open(tester, screen);
        expect(find.text('COACH-GUIDED'), findsOneWidget);
        expect(find.text('FREE'), findsNothing);
      });
    });
  }
}
