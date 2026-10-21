import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/admin/domain/admin_metrics.dart';
import 'package:circle_fitness/features/admin/domain/admin_provider.dart';
import 'package:circle_fitness/features/admin/presentation/admin_attention_queue.dart';
import 'package:circle_fitness/features/admin/presentation/admin_tokens.dart';

/// `DESIGN-01` §1 — the `critical-incident` state.
Future<void> _pump(WidgetTester t, List<AdminIncident>? items,
    {Future<List<AdminIncident>?>? pending}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      adminIncidentsProvider
          .overrideWith((_) => pending ?? Future.value(items)),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: AdminAttentionQueue()),
      ),
    ),
  ));
  await t.pump();
}

AdminIncident _incident({
  String severity = 'Critical',
  String? cause = 'credential stuffing',
}) =>
    AdminIncident.fromRow({
      'id': 'i1',
      'summary': '38 failed sign-ins on one coach account from 3 countries',
      'occurred_at': '2026-10-07T03:00:00Z',
      'scope': 'Security',
      'severity': severity,
      'suspected_cause': cause,
      'recommended_action': 'lock the account',
    });

TextStyle _styleOf(WidgetTester t, String text) =>
    t.widget<Text>(find.text(text)).style!;

void main() {
  group('the three population states are distinct', () {
    testWidgets('NOT AUTHORIZED is distinguishable from an incident-free platform — '
        'the service asks admin_can rather than inferring a permission from an '
        'empty list', (t) async {
      await _pump(t, null);
      expect(find.text('Not available to your role'), findsOneWidget);
      expect(find.text(AdminAttentionQueue.zeroCopy), findsNothing);
    });

    testWidgets('the ZERO state uses the design\'s literal copy and is NOT an empty '
        'panel — STATE-SPECS-A11 §1 records "none raised" on three pages', (t) async {
      await _pump(t, const []);
      expect(find.text('none raised'), findsOneWidget);
      expect(find.text('Not available to your role'), findsNothing);
    });

    testWidgets('LOADING is its own state', (t) async {
      final never = Completer<List<AdminIncident>?>();
      addTearDown(() => never.complete(const []));
      await _pump(t, null, pending: never.future);
      expect(find.text('Loading…'), findsOneWidget);
      expect(find.text('none raised'), findsNothing);
    });
  });

  group('a populated queue', () {
    testWidgets('renders the severity in TITLE CASE — METRIC-12 established that an '
        'uppercase CRITICAL appears nowhere in the shipped enum', (t) async {
      await _pump(t, [_incident()]);
      expect(find.text('Critical'), findsOneWidget);
      expect(find.text('CRITICAL'), findsNothing);
    });

    testWidgets('the Critical badge uses the token with a published 7.4:1 contrast '
        'measurement, not the untokenised #f08a9b', (t) async {
      await _pump(t, [_incident()]);
      expect(_styleOf(t, 'Critical').color, AdminColors.colorStatusDangerText);
      expect(_styleOf(t, 'Critical').fontWeight, FontWeight.w600);
    });

    testWidgets('an unrecognised severity renders NEUTRALLY rather than being guessed '
        'into a danger colour', (t) async {
      await _pump(t, [_incident(severity: 'Informational')]);
      expect(_styleOf(t, 'Informational').color, AdminColors.colorTextMuted);
    });

    testWidgets('exactly ONE primary action per item, and no bulk control anywhere — '
        'the specification says "never bulk"', (t) async {
      await _pump(t, [_incident(), _incident()]);
      expect(find.text('Investigate'), findsNWidgets(2));
      expect(find.byType(Checkbox), findsNothing);
      expect(find.textContaining('Select all'), findsNothing);
      expect(find.textContaining('Resolve all'), findsNothing);
    });

    testWidgets('the read-only footer is present verbatim, so the surface states its '
        'own limits', (t) async {
      await _pump(t, [_incident()]);
      expect(find.text(AdminAttentionQueue.readOnlyFooter), findsOneWidget);
      expect(
          find.text('Actions open the item. Nothing is changed from this screen.'),
          findsOneWidget);
    });

    testWidgets('the primary action OPENS the item and changes nothing — there is no '
        'write path on this widget', (t) async {
      await _pump(t, [_incident()]);
      expect(find.textContaining('credential stuffing'), findsNothing);
      await t.tap(find.text('Investigate'));
      await t.pumpAndSettle();
      expect(find.textContaining('credential stuffing'), findsOneWidget);
      expect(find.textContaining('lock the account'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('an item with nothing recorded offers NO action, rather than one that '
        'opens an empty drawer', (t) async {
      await _pump(t, [
        AdminIncident.fromRow({
          'id': 'i2', 'summary': 'bare', 'severity': 'Critical', 'scope': 'Security',
        })
      ]);
      expect(find.text('Investigate'), findsNothing);
      expect(find.text('Critical'), findsOneWidget);
    });

    testWidgets('the action meets the 44px touch target RESPONSIVE.md requires',
        (t) async {
      await _pump(t, [_incident()]);
      final box = t.getSize(find.ancestor(
          of: find.text('Investigate'), matching: find.byType(SizedBox)).first);
      expect(box.height, AdminDims.sizeControl);
    });

    testWidgets('B-4 holds: no withheld field can reach the screen, because the model '
        'has no field for evidence or actor_identity', (t) async {
      await _pump(t, [_incident()]);
      final text = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' | ');
      expect(text.toLowerCase().contains('evidence'), isFalse);
      expect(text.toLowerCase().contains('actor_identity'), isFalse);
    });
  });
}
