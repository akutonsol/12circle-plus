import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-9 · Settings › Default Units.
//
// `_persistUnit` (CORR-2) said it "returns whether the preference was actually
// stored", but its update never asked for the row back. A 0-row update (RLS
// filtered it) comes back from PostgREST exactly like a successful one, so the
// toggle stayed on the new unit and nothing said the preference was not saved.
//
// HOW TO SEE IT FAIL: with the base commit's settings_screen.dart the 0-row
// test keeps "LB" selected and shows no message, and the PATCH has no
// `select=id`.

const _uid = '00000000-0000-4000-8000-0000000f1009';
const _offline =
    "Couldn't save your unit preference — check your connection and try again.";
const _failed = "Couldn't save your unit preference — try again in a moment. "
    'If it keeps happening, contact support.';
const _signedOut = "Couldn't save your unit preference — you're signed out. "
    'Sign in and try again.';

void main() {
  late RowCheckingPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RowCheckingPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> openSettings(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider
            .overrideWithValue(Supabase.instance.client.auth.currentUser),
        currentUserProfileProvider.overrideWith((ref) async => {
              'role': 'client',
              'first_name': 'Ana',
              'last_name': 'Lee',
              'unit_preference': 'metric',
            }),
        clientPlanProvider.overrideWith((ref) async => ClientPlan.selfGuided),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(selected(tester), 'KG', reason: 'premise: a metric member');
  }

  /// Opens Settings with a metric member (KG selected) and taps LB.
  Future<void> tapLb(WidgetTester tester) async {
    await openSettings(tester);
    await tester.tap(find.text('LB').first);
    await tester.pumpAndSettle();
  }

  List<String> unitWrites() =>
      server.writes.where((w) => w.contains('unit_preference')).toList();

  testWidgets('a 0-row save reverts the toggle and says it was not saved',
      (tester) async {
    server.mode = WriteMode.zeroRows;
    await tapLb(tester);

    expect(unitWrites(), hasLength(1), reason: 'premise: the save was tried');
    expect(unitWrites().single, contains('select=id'),
        reason: 'the update must ask for its row back to know it changed one');
    expect(selected(tester), 'KG',
        reason: 'THE defect: the toggle stayed on LB over an unchanged row');
    expect(find.text(_failed), findsOneWidget,
        reason: 'not the connection — the server answered');
    expect(reported, isNotEmpty, reason: 'the failure is reported');
  });

  testWidgets(
      'a server error reverts and uses the support wording, not '
      '"check your connection"', (tester) async {
    server.mode = WriteMode.serverError;
    await tapLb(tester);
    expect(selected(tester), 'KG');
    expect(find.text(_failed), findsOneWidget);
    expect(find.text(_offline), findsNothing);
    expect(reported.map((f) => f.origin), ['settings.persistUnit'],
        reason: 'a thrown (refused) save must be recorded, not just shown');
    expect(reported.single.error, isA<PostgrestException>());
  });

  testWidgets('a network failure reverts and says check your connection',
      (tester) async {
    server.mode = WriteMode.network;
    await tapLb(tester);
    expect(selected(tester), 'KG');
    expect(find.text(_offline), findsOneWidget);
    expect(reported.map((f) => f.origin), ['settings.persistUnit'],
        reason: 'a thrown (network) save must be recorded, not just shown');
    expect(reported.single.error, isA<http.ClientException>());
  });

  // The wording flags belong to ONE save. On the same screen, a network
  // failure followed by a server failure must not keep the first one's
  // "check your connection" wording (and the reverse).
  testWidgets(
      'same screen: network failure, then 0-row failure, then network '
      'again — each shows its own copy', (tester) async {
    Future<void> clearSnackBars() async {
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing, reason: 'premise: cleared');
    }

    server.mode = WriteMode.network;
    await tapLb(tester);
    expect(selected(tester), 'KG');
    expect(find.text(_offline), findsOneWidget, reason: 'premise');
    await clearSnackBars();

    server.mode = WriteMode.zeroRows;
    await tester.tap(find.text('LB').first);
    await tester.pumpAndSettle();
    expect(unitWrites(), hasLength(2), reason: 'premise: a second save');
    expect(selected(tester), 'KG');
    expect(find.text(_failed), findsOneWidget,
        reason: 'the server answered this time');
    expect(find.text(_offline), findsNothing,
        reason: "the earlier network failure's wording leaked into this one");
    await clearSnackBars();

    server.mode = WriteMode.network;
    await tester.tap(find.text('LB').first);
    await tester.pumpAndSettle();
    expect(find.text(_offline), findsOneWidget);
    expect(find.text(_failed), findsNothing);
  });

  testWidgets('control: a 1-row save keeps LB and says nothing',
      (tester) async {
    await tapLb(tester);
    expect(unitWrites().single, contains('"unit_preference":"imperial"'),
        reason: 'what is written is unchanged');
    expect(selected(tester), 'LB');
    expect(find.byType(SnackBar), findsNothing);
    expect(reported, isEmpty);
  });

  // U4. Two overlapping saves each captured their own "previous": tap LB
  // (previous KG), tap KG while LB is in flight (previous LB). If the LB save
  // then failed it reverted to KG over the KG save, or vice versa — the toggle
  // could end on a unit that was never stored. Taps are now ignored while a
  // save is in flight.
  testWidgets('a tap while a unit save is in flight is ignored',
      (tester) async {
    await openSettings(tester);
    server.gate = Completer<void>();
    await tester.tap(find.text('LB').first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(selected(tester), 'LB', reason: 'premise: optimistic');
    await tester.tap(find.text('KG').first);
    await tester.pump(const Duration(milliseconds: 50));

    expect(unitWrites(), hasLength(1),
        reason: 'THE race: a second save started while the first was in '
            'flight:\n${unitWrites().join('\n')}');
    expect(selected(tester), 'LB', reason: 'the second tap did nothing');

    server.gate!.complete();
    await tester.pumpAndSettle();
    expect(selected(tester), 'LB');
    expect(find.byType(SnackBar), findsNothing);

    // Once it lands, the toggle answers again.
    await tester.tap(find.text('KG').first);
    await tester.pumpAndSettle();
    expect(unitWrites(), hasLength(2));
    expect(selected(tester), 'KG');
  });

  // U1. LAST in this file: it signs the shared session out.
  testWidgets(
      'signed out: reverts with the signed-out wording, not the server '
      'failure copy', (tester) async {
    await tester.runAsync(() => Supabase.instance.client.auth.signOut());
    expect(Supabase.instance.client.auth.currentUser, isNull,
        reason: 'premise: signed out');
    server.writes.clear();
    await tapLb(tester);
    expect(unitWrites(), isEmpty, reason: 'nothing to write as nobody');
    expect(selected(tester), 'KG');
    expect(find.text(_signedOut), findsOneWidget,
        reason: 'the server never answered, so not "try again in a moment"');
    expect(find.text(_failed), findsNothing);
    expect(find.text(_offline), findsNothing);
  });
}

/// The highlighted unit: the one whose pill has a non-transparent fill.
String selected(WidgetTester tester) {
  for (final u in ['KG', 'LB']) {
    final box = tester.widget<AnimatedContainer>(find
        .ancestor(
            of: find.text(u).first, matching: find.byType(AnimatedContainer))
        .first);
    final color = (box.decoration as BoxDecoration?)?.color;
    if (color != null && color != Colors.transparent) return u;
  }
  return 'none';
}
