import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/ai_nutrition_service.dart';
import 'ai_text.dart';
import 'chat_turn.dart';
import 'grocery_list.dart' show parseGroceryList;

/// Who the client says is signed in now.
String? _signedInUid() {
  try {
    return Supabase.instance.client.auth.currentUser?.id;
  } on AssertionError {
    return null; // a unit test with no client: nobody can sign in or out
  }
}

/// What a failure is recorded as: what went wrong, not the sentence shown.
Object _causeOf(Object e) =>
    e is AiNutritionException ? e.cause ?? e : e;

/// P0-FL-60b · one member's notifier: the one signed in when it was made. Its
/// provider makes another when the uid changes (and this one is unmounted);
/// until then nothing of theirs is sent under the next member's login, and an
/// answer to them is not kept.
mixin _OneMember<T> on StateNotifier<T> {
  final String? _owner = _signedInUid();

  bool get _stillOwner => mounted && _signedInUid() == _owner;

  /// Nothing held for a member who is no longer the one signed in.
  T get _nothing;

  /// True (recorded, and cleared) when [what] must not go out.
  bool _refuse(String what) {
    if (_stillOwner) return false;
    reportError('aiNutrition.identity',
        StateError('$what: the signed-in account changed'));
    if (mounted) state = _nothing;
    return true;
  }

  /// True when an answer landed for somebody who left.
  bool _tooLate() {
    if (_stillOwner) return false;
    if (mounted) state = _nothing;
    return true;
  }
}

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

class AiNutritionNotifier extends StateNotifier<List<ChatMessage>>
    with _OneMember<List<ChatMessage>> {
  final AiNutritionService _service;

  AiNutritionNotifier(this._service) : super(_greeting());

  static List<ChatMessage> _greeting() => [
    ChatMessage(
      content: 'Hi! I\'m your AI Nutrition Coach. I can help you with meal planning, analyze meal photos, generate grocery lists, and answer any nutrition questions. What would you like help with today?',
      isUser: false,
      timestamp: DateTime.now(),
    ),
  ];

  @override
  List<ChatMessage> get _nothing => _greeting();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Build API-ready history from current messages (excludes the pending user
  // turn, and every failed turn — a transport failure is not something the
  // assistant said).
  List<Map<String, dynamic>> _buildHistory() => apiHistory(state);

  Future<void> sendMessage(String message, {File? image}) async {
    if (_refuse('send a chat turn')) return;
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

      // Signed out (or switched account) while this was in flight.
      if (_tooLate()) return;
      state = [...state, ChatMessage(content: response, isUser: false, timestamp: DateTime.now())];
    } catch (e, st) {
      reportError(
          image == null ? 'aiNutrition.chat.send' : 'aiNutrition.photo.analyze',
          _causeOf(e), st);
      if (_tooLate()) return;
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
    if (_refuse('send a chat turn again')) return;
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

// The chat, the plan and the list are the signed-in user's: what they eat,
// weigh and asked about. Signing out only navigates to /login, so each one is
// rebuilt for whoever signs in next (QAX-SES-01) instead of being shown to
// them — and the chat's turns sent to the AI as their history. By uid only
// (P0-FL-60b): an edit to the same member's sign-up details wiped the chat.
final aiNutritionNotifierProvider = StateNotifierProvider<AiNutritionNotifier, List<ChatMessage>>(
  (ref) {
    ref.watch(currentUserProvider.select((u) => u?.id));
    return AiNutritionNotifier(ref.watch(aiNutritionServiceProvider));
  },
);

class MealPlanNotifier extends StateNotifier<AiText> with _OneMember<AiText> {
  final AiNutritionService _service;
  MealPlanNotifier(this._service) : super(const AiText.idle());

  bool isLoading = false;

  /// P0-FL-60b · why the last rebuild failed, while the plan built before it
  /// is kept (`state` stays ready). Null once a build succeeds.
  Object? get rebuildError => _rebuildError;
  Object? _rebuildError;

  @override
  AiText get _nothing => const AiText.idle();

  Future<void> generateMealPlan({
    required int calories,
    required int protein,
    required int carbs,
    required int fat,
    required List<String> restrictions,
    required int days,
  }) async {
    if (_refuse('build a meal plan')) return;
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
      // Blank is not a plan (`mealPlanOutcome`), and must not replace one.
      if (plan.trim().isEmpty) throw StateError('the plan came back blank');
      if (_tooLate()) return;
      _rebuildError = null;
      state = AiText.ready(plan);
    } catch (e, st) {
      reportError('aiNutrition.mealPlan.build', _causeOf(e), st);
      if (_tooLate()) return;
      final kept = state.content;
      if (kept == null) {
        // NOT written into the content slot. FIT-093 is a screen of its own.
        state = const AiText.failed();
      } else {
        // A plan was built before: it is still theirs.
        _rebuildError = _causeOf(e);
        state = AiText.ready(kept);
      }
    } finally {
      isLoading = false;
    }
  }
}

final mealPlanNotifierProvider = StateNotifierProvider<MealPlanNotifier, AiText>(
  (ref) {
    ref.watch(currentUserProvider.select((u) => u?.id));
    return MealPlanNotifier(ref.watch(aiNutritionServiceProvider));
  },
);

class GroceryListNotifier extends StateNotifier<AiText>
    with _OneMember<AiText> {
  final AiNutritionService _service;
  GroceryListNotifier(this._service) : super(const AiText.idle());

  bool isLoading = false;

  /// As [MealPlanNotifier.rebuildError].
  Object? get rebuildError => _rebuildError;
  Object? _rebuildError;

  @override
  AiText get _nothing => const AiText.idle();

  /// The list on screen, if there is a readable one to keep.
  String? get _readable {
    final kept = state.content;
    return kept == null || parseGroceryList(kept).isEmpty ? null : kept;
  }

  Future<void> generateGroceryList(String mealPlan) async {
    if (_refuse('build a grocery list')) return;
    isLoading = true;
    try {
      final list = await _service.generateGroceryList(mealPlan: mealPlan);
      if (_tooLate()) return;
      if (parseGroceryList(list).isEmpty) {
        // `groceryOutcome` shows this as a failure; it must not replace a list
        // that can be read.
        final unreadable = StateError('the grocery list could not be read');
        reportError('aiNutrition.groceryList.build', unreadable);
        final kept = _readable;
        if (kept != null) {
          _rebuildError = unreadable;
          state = AiText.ready(kept);
          return;
        }
      }
      _rebuildError = null;
      state = AiText.ready(list);
    } catch (e, st) {
      reportError('aiNutrition.groceryList.build', _causeOf(e), st);
      if (_tooLate()) return;
      final kept = _readable;
      if (kept == null) {
        state = const AiText.failed();
      } else {
        _rebuildError = _causeOf(e);
        state = AiText.ready(kept);
      }
    } finally {
      isLoading = false;
    }
  }
}

final groceryListNotifierProvider = StateNotifierProvider<GroceryListNotifier, AiText>(
  (ref) {
    ref.watch(currentUserProvider.select((u) => u?.id));
    return GroceryListNotifier(ref.watch(aiNutritionServiceProvider));
  },
);
