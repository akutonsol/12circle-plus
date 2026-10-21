import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/app_env.dart';

/// Thrown when the AI nutrition coach can't be reached or refuses the request.
class AiNutritionException implements Exception {
  final String message;
  const AiNutritionException(this.message);
  @override
  String toString() => message;
}

/// Client for the AI Nutrition Coach.
///
/// The Anthropic integration lives behind the `ai-nutrition` Supabase Edge
/// Function — this class holds no AI credential of any kind. It forwards the
/// user's turn together with their Supabase access token; the function verifies
/// that session and calls Claude with the server-held key.
///
/// PD-A17 = A, resolved as A2 (V5 §46). This used to POST to
/// `{API_BASE_URL}/ai/nutrition/message` on a NestJS API that was never
/// deployed anywhere — `API_BASE_URL` was empty in every environment, so the
/// feature could not work in any build. It now targets the Edge Function, which
/// is deployed alongside the other nineteen. The transport is still Dio and the
/// request/response contract is unchanged.
class AiNutritionService {
  static const String functionName = 'ai-nutrition';

  final Dio _dio;
  final EnvConfig _env;
  final String? Function() _accessToken;

  AiNutritionService({
    Dio? dio,
    EnvConfig? env,
    String? Function()? accessToken,
  })  : _dio = dio ?? Dio(),
        _env = env ?? AppEnv.current,
        _accessToken = accessToken ?? _currentSupabaseAccessToken;

  static String? _currentSupabaseAccessToken() =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  /// Absolute URL of the AI nutrition endpoint for this build's environment.
  String get endpointUrl {
    final base = _env.supabaseUrl.endsWith('/')
        ? _env.supabaseUrl.substring(0, _env.supabaseUrl.length - 1)
        : _env.supabaseUrl;
    return '$base/functions/v1/$functionName';
  }

  Future<String> sendMessage({
    required String message,
    required List<Map<String, dynamic>> history,
    File? imageFile,
  }) async {
    if (_env.supabaseUrl.isEmpty) {
      throw const AiNutritionException(
        'AI coach is unavailable: this build has no SUPABASE_URL configured.',
      );
    }

    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const AiNutritionException(
        'Please sign in again to use the AI coach.',
      );
    }

    final body = <String, dynamic>{
      'message': message,
      'history': history,
      if (imageFile != null) 'image': await _encodeImage(imageFile),
    };

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        endpointUrl,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          // The Edge gateway requires an apikey alongside the user's token; it
          // is the publishable anon key, never a service credential.
          'apikey': _env.supabaseAnonKey,
        }),
        data: body,
      );
      final text = response.data?['text'];
      if (text is! String || text.isEmpty) {
        throw const AiNutritionException('AI coach returned an empty reply.');
      }
      return text;
    } on DioException catch (e) {
      throw AiNutritionException(_messageForStatus(e.response?.statusCode));
    }
  }

  static Future<Map<String, dynamic>> _encodeImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final ext = imageFile.path.split('.').last.toLowerCase();
    return {
      'mediaType': ext == 'png' ? 'image/png' : 'image/jpeg',
      'data': base64Encode(bytes),
    };
  }

  static String _messageForStatus(int? status) {
    switch (status) {
      case 401:
        return 'Your session expired. Please sign in again.';
      case 403:
        return 'Your account does not have access to the AI coach.';
      case 413:
        return 'That photo is too large. Try a smaller image.';
      case 429:
        return 'The AI coach is busy right now. Please try again shortly.';
      case 503:
        return 'The AI coach is temporarily unavailable. Please try again.';
      default:
        return 'Could not reach the AI coach. Please try again.';
    }
  }

  Future<String> generateMealPlan({
    required int calories,
    required int protein,
    required int carbs,
    required int fat,
    required List<String> dietaryRestrictions,
    required int days,
  }) async {
    final prompt = '''Generate a $days-day meal plan with the following targets:
- Daily Calories: $calories kcal
- Protein: ${protein}g
- Carbs: ${carbs}g
- Fat: ${fat}g
Dietary restrictions: ${dietaryRestrictions.isEmpty ? 'None' : dietaryRestrictions.join(', ')}

Format each day as:
DAY X:
Breakfast: [meal name] - [calories] kcal | P:[protein]g C:[carbs]g F:[fat]g
Lunch: [meal name] - [calories] kcal | P:[protein]g C:[carbs]g F:[fat]g
Dinner: [meal name] - [calories] kcal | P:[protein]g C:[carbs]g F:[fat]g
Snack: [meal name] - [calories] kcal | P:[protein]g C:[carbs]g F:[fat]g''';

    return sendMessage(message: prompt, history: []);
  }

  Future<String> generateGroceryList({required String mealPlan}) async {
    final prompt = '''Based on this meal plan, generate a comprehensive grocery list organized by category:
$mealPlan

Format as:
PRODUCE:
- item (quantity)

PROTEINS:
- item (quantity)

GRAINS & CARBS:
- item (quantity)

DAIRY & EGGS:
- item (quantity)

PANTRY:
- item (quantity)''';

    return sendMessage(message: prompt, history: []);
  }

  Future<String> analyzeMealPhoto(File imageFile) async {
    return sendMessage(
      message: '''Please analyze this meal photo and provide:
1. Estimated calories
2. Macronutrients (protein, carbs, fat in grams)
3. Main ingredients identified
4. Health assessment (1-10)
5. One suggestion to improve the nutritional balance''',
      history: [],
      imageFile: imageFile,
    );
  }
}
