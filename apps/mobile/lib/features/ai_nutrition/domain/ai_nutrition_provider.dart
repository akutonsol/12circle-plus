import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ai_nutrition_service.dart';
import 'ai_text.dart';
import 'chat_turn.dart';

final aiNutritionServiceProvider = Provider<AiNutritionService>(
  (ref) => AiNutritionService(),
);

class ChatMessage {
  final String content;
  final bool isUser;
  final File? image;
  final DateTime timestamp;

  /// This turn did not get through. It is NOT something the assistant said,
  /// and `apiHistory` leaves it out of the next request — see `chat_turn.dart`.
  final bool failed;

  ChatMessage({
    required this.content,
    required this.isUser,
    this.image,
    required this.timestamp,
    this.failed = false,
  });
}

class AiNutritionNotifier extends StateNotifier<List<ChatMessage>> {
  final AiNutritionService _service;

  AiNutritionNotifier(this._service) : super([
    ChatMessage(
      content: 'Hi! I\'m your AI Nutrition Coach. I can help you with meal planning, analyze meal photos, generate grocery lists, and answer any nutrition questions. What would you like help with today?',
      isUser: false,
      timestamp: DateTime.now(),
    ),
  ]);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Build API-ready history from current messages (excludes the pending user
  // turn, and every failed turn — a transport failure is not something the
  // assistant said).
  List<Map<String, dynamic>> _buildHistory() => apiHistory(state);

  Future<void> sendMessage(String message, {File? image}) async {
    state = [...state, ChatMessage(content: message, isUser: true, image: image, timestamp: DateTime.now())];
    _isLoading = true;

    try {
      final history = _buildHistory();
      // Remove the last entry — it's the message we're about to send
      if (history.isNotEmpty) history.removeLast();

      final response = await _service.sendMessage(
        message: message,
        history: history,
        imageFile: image,
      );

      state = [...state, ChatMessage(content: response, isUser: false, timestamp: DateTime.now())];
    } catch (e) {
      // FIT-090. Marked `failed`, so the bubble draws a notice instead of the
      // coach and `apiHistory` keeps it out of the next request.
      state = [...state, ChatMessage(
        content: e is AiNutritionException ? e.message : turnFailedNotice,
        isUser: false,
        failed: true,
        timestamp: DateTime.now(),
      )];
    } finally {
      _isLoading = false;
    }
  }

  /// FIT-090's `Send it again`.
  ///
  /// Drops the failure notice and the user turn it belongs to, then re-sends
  /// that same turn — so a retry does not leave a duplicate of either behind.
  Future<void> retryLastTurn() async {
    final last = lastUserTurn(state);
    if (last == null) return;
    state = withoutFailedTail(state);
    await sendMessage(last.content, image: last.image);
  }

  Future<void> analyzePhoto(File imageFile) async {
    await sendMessage('Analyze this meal photo for me.', image: imageFile);
  }

  void clearChat() {
    state = [
      ChatMessage(
        content: 'Hi! I\'m your AI Nutrition Coach. How can I help you today?',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    ];
  }
}

final aiNutritionNotifierProvider = StateNotifierProvider<AiNutritionNotifier, List<ChatMessage>>(
  (ref) => AiNutritionNotifier(ref.watch(aiNutritionServiceProvider)),
);

class MealPlanNotifier extends StateNotifier<AiText> {
  final AiNutritionService _service;
  MealPlanNotifier(this._service) : super(const AiText.idle());

  bool isLoading = false;

  Future<void> generateMealPlan({
    required int calories,
    required int protein,
    required int carbs,
    required int fat,
    required List<String> restrictions,
    required int days,
  }) async {
    isLoading = true;
    try {
      final plan = await _service.generateMealPlan(
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        dietaryRestrictions: restrictions,
        days: days,
      );
      state = AiText.ready(plan);
    } catch (e) {
      // NOT written into the content slot. FIT-093 is a screen of its own.
      state = const AiText.failed();
    } finally {
      isLoading = false;
    }
  }
}

final mealPlanNotifierProvider = StateNotifierProvider<MealPlanNotifier, AiText>(
  (ref) => MealPlanNotifier(ref.watch(aiNutritionServiceProvider)),
);

class GroceryListNotifier extends StateNotifier<AiText> {
  final AiNutritionService _service;
  GroceryListNotifier(this._service) : super(const AiText.idle());

  bool isLoading = false;

  Future<void> generateGroceryList(String mealPlan) async {
    isLoading = true;
    try {
      final list = await _service.generateGroceryList(mealPlan: mealPlan);
      state = AiText.ready(list);
    } catch (e) {
      state = const AiText.failed();
    } finally {
      isLoading = false;
    }
  }
}

final groceryListNotifierProvider = StateNotifierProvider<GroceryListNotifier, AiText>(
  (ref) => GroceryListNotifier(ref.watch(aiNutritionServiceProvider)),
);
