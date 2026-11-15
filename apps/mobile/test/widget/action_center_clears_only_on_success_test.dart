// The Coach Action Center's "Approve" opened the assign sheet and cleared the
// recommendation AT ONCE. Closing the sheet without saving -- or a save that
// failed -- still hid it for the rest of the visit, and the coach believed it
// was handled. The sheets now pop `true` only after a successful save, and the
// recommendation is cleared only then.
//
// HOW TO SEE IT FAIL: on main the first test finds one fewer item after the
// sheet is merely closed.

import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The coach's client page reads the nutrition plan and the habits through
// `clientDetailProvider`. The Set Nutrition Targets and Assign Habits sheets saved,
// popped and said "saved" or "assigned", but invalidated nothing, so the page kept
// showing "No nutrition plan assigned yet" and no habits until the coach pulled to
// refresh or left. It is the same gap the Assign Program sheet had.
//
// These drive the real page and both sheets. Only the service and the providers are
// substituted; the fake records what the coach saves, and the page's detail override
// reflects it the way the real provider does.

const _clientId = 'client-1';

class _FakeSvc extends Fake implements CoachProgramService {
  Map<String, dynamic>? nutritionPlan;
  List<Map<String, dynamic>> habits = [];

  @override
  Future<Map<String, dynamic>?> getClientNutritionPlan(String clientId) async =>
      nutritionPlan;

  @override
  Future<void> assignNutritionPlan(
    String clientId, {
    required int calories,
    required int protein,
    required int carbs,
    required int fat,
    int? waterOz,
    String? notes,
  }) async {
    // The real column names. This fake used the names the card wrongly read, so
    // the test passed while the real page showed "—" for every figure.
    nutritionPlan = {
      'calories_target': calories,
      'protein_g': protein,
      'carbs_g': carbs,
      'fat_g': fat,
      'notes': notes,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getClientHabits(String clientId) async =>
      habits;

  @override
  Future<void> assignHabits(
      String clientId, List<Map<String, dynamic>> assigned) async {
    habits = [for (final h in assigned) {...h, 'is_active': true}];
  }
}

class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('[]')),
        200,
        headers: {'content-type': 'application/json'},
      );
}

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

/// Client detail runs repeating animations, so `pumpAndSettle` would not return.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpPage(WidgetTester t, _FakeSvc svc) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1200, 4000);
  addTearDown(t.view.reset);

  final router = GoRouter(
    initialLocation: '/client',
    routes: [
      GoRoute(
        path: '/client',
        builder: (_, __) =>
            const ClientDetailScreen(clientId: _clientId, clientName: 'Jordan'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await t.pumpWidget(ProviderScope(
    overrides: [
      coachProgramServiceProvider.overrideWithValue(svc),
      clientDetailProvider(_clientId).overrideWith((ref) async => {
            'id': _clientId,
            'first_name': 'Jordan',
            'last_name': 'Test',
            'role': 'client',
            'nutrition_plan': svc.nutritionPlan,
            'habits': svc.habits,
          }),
      clientHasPaidPlanProvider(_clientId).overrideWith((ref) async => true),
      clientScheduleProvider(_clientId).overrideWith((ref) async => null),
      clientScoreProvider(_clientId).overrideWith((ref) async => null),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await _settle(t);
}

Finder _field(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _EmptyClient(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  const item = 'Set Nutrition Targets';

  /// The Action Center lists Assign Program first, then Set Nutrition Targets:
  /// this is the second Approve.
  Future<void> approveNutrition(WidgetTester t) async {
    final approve = find.text('Approve').at(1);
    await t.ensureVisible(approve);
    await _settle(t);
    await t.tap(approve);
    await _settle(t);
    expect(find.text('Save Nutrition Plan'), findsOneWidget, reason: 'the sheet opened');
  }

  testWidgets('closing the sheet without saving keeps the recommendation', (t) async {
    final svc = _FakeSvc();
    await _pumpPage(t, svc);
    final before = find.text(item).evaluate().length;
    await approveNutrition(t);
    Navigator.of(t.element(find.text('Save Nutrition Plan'))).pop();
    await _settle(t);
    expect(svc.nutritionPlan, isNull, reason: 'nothing was saved');
    expect(find.text(item).evaluate().length, before,
        reason: 'THE defect: the recommendation disappeared although nothing was done');
  });

  testWidgets('a saved plan clears the recommendation (positive control)', (t) async {
    final svc = _FakeSvc();
    await _pumpPage(t, svc);
    final before = find.text(item).evaluate().length;
    await approveNutrition(t);
    await t.enterText(_field('1850'), '2200');
    await t.enterText(_field('140'), '150');
    await t.enterText(_field('170'), '240');
    await t.enterText(_field('60'), '70');
    await t.tap(find.text('Save Nutrition Plan'));
    await _settle(t);
    expect(svc.nutritionPlan?['calories_target'], 2200);
    expect(find.text(item).evaluate().length, lessThan(before),
        reason: 'the action was done, so the recommendation is cleared');
  });
}
