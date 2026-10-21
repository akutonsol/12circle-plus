// QAX-COR-05 — one tap, one meal.
//
// Quick-add (and the scan / barcode accept paths) called _logFood directly;
// `_saving` was set but never checked on those paths, nutrition_logs has no
// unique key, and the app offers no edit or delete for a logged meal — so a
// double tap was a permanent duplicate that keeps counting in the day's totals
// and in scoring.
import 'dart:async';

import 'package:circle_fitness/features/nutrition/data/models/food_model.dart';
import 'package:circle_fitness/features/nutrition/data/nutrition_service.dart';
import 'package:circle_fitness/features/nutrition/presentation/meals_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNutrition implements NutritionService {
  _FakeNutrition(this.pending);
  final Completer<void> pending;
  int logMealCalls = 0;

  static final _food = Food(
    id: 'f1', name: 'QAX Oats', brand: '', calories: 150, protein: 5,
    carbs: 27, fat: 3, fiber: 4, sugar: 1, servingSize: 40, servingUnit: 'g');

  @override
  List<Food> getSampleFoods() => [_food];
  @override
  List<Food> searchFoods(String query) => [_food];

  @override
  Future<void> logMeal({
    required String mealType,
    required String foodName,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required double servingSize,
    required String servingUnit,
  }) {
    logMealCalls++;
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a double tap on quick-add logs the meal once', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final pending = Completer<void>();
    final svc = _FakeNutrition(pending);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: AddMealSheet(onLogged: () {}, service: svc)),
      ),
    ));
    await tester.pumpAndSettle();

    final quickAdd = find.byIcon(Icons.add).first;
    await tester.tap(quickAdd);
    await tester.pump();                       // first save is in flight
    await tester.tap(quickAdd, warnIfMissed: false);
    await tester.pump();

    expect(svc.logMealCalls, 1,
        reason: 'the second tap must not insert a second nutrition_logs row');

    pending.complete();                        // let the first save finish
    await tester.pump();
  });
}
