import 'dart:async';
import 'dart:io';

import 'package:circle_fitness/features/ai_nutrition/data/ai_nutrition_service.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/ai_nutrition_provider.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// The AI Nutrition chat, meal plan and grocery list were kept for whoever
// signed in next.
//
// On mobile, signing out only navigates to /login: the root ProviderScope
// lives on, and a provider is reset only if it watches the signed-in user or
// is autoDispose. These three are neither. So client B, signing in on A's
// device, opened /ai-nutrition onto A's conversation — what A eats, weighs and
// asked about — and /meal-plan onto A's plan. Worse, B's next message went to
// the AI with A's turns attached as B's own history.

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );

/// Who is signed in, changeable mid-test, standing in for the auth stream.
final _signedIn = StateProvider<User?>((ref) => _user('account-a'));

/// Answers every request, and records the history each chat turn carried.
class _FakeAi extends AiNutritionService {
  _FakeAi() : super(accessToken: () => 'token');

  final histories = <List<Map<String, dynamic>>>[];
  Completer<String>? hold;

  @override
  Future<String> sendMessage({
    required String message,
    required List<Map<String, dynamic>> history,
    File? imageFile,
  }) async {
    histories.add(history);
    if (hold != null) return hold!.future;
    return 'reply to $message';
  }

  @override
  Future<String> generateMealPlan({
    required int calories,
    required int protein,
    required int carbs,
    required int fat,
    required List<String> dietaryRestrictions,
    required int days,
  }) async =>
      'A plan for $calories kcal';

  @override
  Future<String> generateGroceryList({required String mealPlan}) async =>
      'Oats, eggs';
}

void main() {
  late _FakeAi ai;

  ProviderContainer signedIn() {
    ai = _FakeAi();
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
      aiNutritionServiceProvider.overrideWithValue(ai),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  void signInAs(ProviderContainer c, String id) =>
      c.read(_signedIn.notifier).state = _user(id);

  test("the next account does not open onto the last one's chat", () async {
    final c = signedIn();
    c.listen(aiNutritionNotifierProvider, (_, __) {});
    await c.read(aiNutritionNotifierProvider.notifier)
        .sendMessage('I am 92 kg and diabetic');

    signInAs(c, 'account-b');

    final shown = c.read(aiNutritionNotifierProvider).map((m) => m.content);
    expect(shown.where((t) => t.contains('92 kg')), isEmpty,
        reason: "account A's message must not be shown to account B");
    expect(shown, hasLength(1), reason: 'B starts at the greeting');
  });

  test("the next account's first message carries none of the last one's turns",
      () async {
    final c = signedIn();
    c.listen(aiNutritionNotifierProvider, (_, __) {});
    await c.read(aiNutritionNotifierProvider.notifier)
        .sendMessage('I am 92 kg and diabetic');

    signInAs(c, 'account-b');
    await c.read(aiNutritionNotifierProvider.notifier).sendMessage('Hello');

    final sent = ai.histories.last.map((h) => '${h['content']}');
    expect(sent.where((t) => t.contains('92 kg')), isEmpty,
        reason: "account A's turn must not reach the AI as account B's history");
  });

  test("the next account does not see the last one's meal plan", () async {
    final c = signedIn();
    c.listen(mealPlanNotifierProvider, (_, __) {});
    await c.read(mealPlanNotifierProvider.notifier).generateMealPlan(
        calories: 1800, protein: 140, carbs: 150, fat: 60,
        restrictions: const ['gluten-free'], days: 7);
    expect(c.read(mealPlanNotifierProvider).content, isNotNull,
        reason: 'guard the premise');

    signInAs(c, 'account-b');
    expect(c.read(mealPlanNotifierProvider).content, isNull);
  });

  test("the next account does not see the last one's grocery list", () async {
    final c = signedIn();
    c.listen(groceryListNotifierProvider, (_, __) {});
    await c.read(groceryListNotifierProvider.notifier)
        .generateGroceryList('A plan');
    expect(c.read(groceryListNotifierProvider).content, isNotNull,
        reason: 'guard the premise');

    signInAs(c, 'account-b');
    expect(c.read(groceryListNotifierProvider).content, isNull);
  });

  test('a reply that lands after sign-out is dropped, not thrown', () async {
    // Resetting per account means the notifier a request started on can be
    // disposed before its reply arrives.
    final c = signedIn();
    c.listen(aiNutritionNotifierProvider, (_, __) {});
    ai.hold = Completer<String>();
    final pending =
        c.read(aiNutritionNotifierProvider.notifier).sendMessage('Hi');

    c.read(_signedIn.notifier).state = null;
    ai.hold!.complete('late reply');
    await expectLater(pending, completes);
    expect(c.read(aiNutritionNotifierProvider).map((m) => m.content),
        isNot(contains('late reply')));
  });

  test('the same account keeps its chat', () async {
    // A token refresh is not a new account. `User` compares by value, so the
    // providers only reset when the user really changes.
    final c = signedIn();
    c.listen(aiNutritionNotifierProvider, (_, __) {});
    await c.read(aiNutritionNotifierProvider.notifier).sendMessage('Hi');

    signInAs(c, 'account-a');
    expect(c.read(aiNutritionNotifierProvider), hasLength(3));
  });
}
