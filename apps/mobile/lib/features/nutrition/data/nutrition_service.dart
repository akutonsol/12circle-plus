import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/food_model.dart';
import '../../coach/data/score_service.dart';
import '../../scoring/data/score_engine.dart';

class NutritionService {
  final _supabase = Supabase.instance.client;
  final _customFoods = <Food>[];
  // OpenFoodFacts is a free, key-less food database (barcodes + search).
  static final _off = Dio(BaseOptions(
    headers: {'User-Agent': '12CircleFitness/1.0 (nutrition)'},
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  void addCustomFood(Food food) => _customFoods.add(food);

  /// AI food analysis (Cal-AI style). Pass a photo's bytes and/or a text
  /// description; returns estimated calories + macros. Throws on failure so the
  /// UI can show a real error instead of silently faking a result.
  Future<Map<String, dynamic>> analyzeFood({
    List<int>? imageBytes,
    String? mediaType,
    String? description,
  }) async {
    final res = await _supabase.functions.invoke('analyze-food-image', body: {
      if (imageBytes != null) 'imageBase64': base64Encode(imageBytes),
      if (imageBytes != null) 'mediaType': mediaType ?? 'image/jpeg',
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
    final data = res.data;
    if (data is Map && data['result'] is Map) {
      return Map<String, dynamic>.from(data['result'] as Map);
    }
    throw Exception((data is Map ? data['error'] : null) ?? 'Analysis failed');
  }

  Future<void> logMeal({
    required String mealType,
    required String foodName,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required double servingSize,
    required String servingUnit,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');
    await _supabase.from('nutrition_logs').insert({
      'user_id': userId,
      'meal_type': mealType,
      'food_name': foodName,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'amount_g': servingSize,
      'serving_unit': servingUnit,
      'logged_at': DateTime.now().toIso8601String(),
    });
    // 12 Circle Score: +5 for the meal log, then re-check goal/day bonuses.
    await ScoreEngine().mealLogged(DateTime.now().microsecondsSinceEpoch.toString());
    // Award 12 Circle Score nutrition points based on adherence to coach goals.
    // Idempotent (ScoreService sets, not increments) so re-logging never double-counts.
    await _awardNutritionScore();
  }

  /// Recomputes today's macro adherence vs the active plan and updates the
  /// nutrition portion of the daily score. Never throws — scoring failures
  /// must not break meal logging.
  Future<void> _awardNutritionScore() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final totals = await getTodayTotals();
      // Pull active coach-assigned goals; fall back to sensible defaults.
      double calTarget = 2000, proTarget = 120;
      final plan = await _supabase
          .from('client_nutrition_plans')
          .select('calories_target, protein_g')
          .eq('client_id', userId)
          .eq('is_active', true)
          .maybeSingle();
      if (plan != null) {
        calTarget = (plan['calories_target'] as num?)?.toDouble() ?? calTarget;
        proTarget = (plan['protein_g'] as num?)?.toDouble() ?? proTarget;
      }
      final calPct = calTarget > 0 ? (totals['calories']! / calTarget).clamp(0.0, 1.0) : 0.0;
      final proPct = proTarget > 0 ? (totals['protein']! / proTarget).clamp(0.0, 1.0) : 0.0;
      final completionPct = (calPct + proPct) / 2;
      await ScoreService().addNutritionPoints(completionPct);
      // 12 Circle Score goal bonuses (each once-per-day via server dedup).
      final engine = ScoreEngine();
      if (proPct >= 1.0) await engine.proteinGoalHit();
      if (calPct >= 0.9) await engine.nutritionDayComplete();
    } catch (_) {
      // ignore scoring errors
    }
  }

  // The three reads below throw when they fail. They returned zeros and `[]`,
  // which is "nothing logged today": FIT-022's failure state on the meals
  // dashboard could never be shown, and a client who had logged three meals
  // saw 0 kcal and "+ Log a meal" — and may well have logged them again.
  Future<Map<String, double>> getTodayTotals() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return {'calories': 0, 'protein': 0, 'carbs': 0, 'fat': 0};
    {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final end = start.add(const Duration(days: 1));
      final data = await _supabase
          .from('nutrition_logs')
          .select()
          .eq('user_id', userId)
          .gte('logged_at', start.toIso8601String())
          .lt('logged_at', end.toIso8601String());
      double calories = 0, protein = 0, carbs = 0, fat = 0;
      for (final row in (data as List)) {
        calories += (row['calories'] as num?)?.toDouble() ?? 0;
        protein  += (row['protein']  as num?)?.toDouble() ?? 0;
        carbs    += (row['carbs']    as num?)?.toDouble() ?? 0;
        fat      += (row['fat']      as num?)?.toDouble() ?? 0;
      }
      return {'calories': calories, 'protein': protein, 'carbs': carbs, 'fat': fat};
    }
  }

  Future<List<Map<String, dynamic>>> getLogsForDate(DateTime date) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    {
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      final data = await _supabase
          .from('nutrition_logs')
          .select()
          .eq('user_id', userId)
          .gte('logged_at', start.toIso8601String())
          .lt('logged_at', end.toIso8601String())
          .order('logged_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    }
  }

  Future<List<Map<String, dynamic>>> getTodayLogs() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final end = start.add(const Duration(days: 1));
      final data = await _supabase
          .from('nutrition_logs')
          .select()
          .eq('user_id', userId)
          .gte('logged_at', start.toIso8601String())
          .lt('logged_at', end.toIso8601String())
          .order('logged_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    }
  }

  List<Food> getSampleFoods() {
    return [..._builtInFoods(), ..._customFoods];
  }

  List<Food> _builtInFoods() {
    return [
      Food(id: '1',  name: 'Chicken Breast',  brand: 'Generic',           calories: 165, protein: 31,  carbs: 0,  fat: 3.6, fiber: 0,   sugar: 0,   servingSize: 100, servingUnit: 'g'),
      Food(id: '2',  name: 'Brown Rice',       brand: 'Generic',           calories: 216, protein: 5,   carbs: 45, fat: 1.8, fiber: 3.5, sugar: 0,   servingSize: 195, servingUnit: 'g'),
      Food(id: '3',  name: 'Broccoli',         brand: 'Generic',           calories: 55,  protein: 3.7, carbs: 11, fat: 0.6, fiber: 5.1, sugar: 2.6, servingSize: 148, servingUnit: 'g'),
      Food(id: '4',  name: 'Whole Eggs',       brand: 'Generic',           calories: 78,  protein: 6,   carbs: 0.6,fat: 5,   fiber: 0,   sugar: 0.6, servingSize: 50,  servingUnit: 'g'),
      Food(id: '5',  name: 'Greek Yogurt',     brand: 'Chobani',           calories: 100, protein: 17,  carbs: 6,  fat: 0.7, fiber: 0,   sugar: 4,   servingSize: 170, servingUnit: 'g'),
      Food(id: '6',  name: 'Oatmeal',          brand: 'Quaker',            calories: 150, protein: 5,   carbs: 27, fat: 2.5, fiber: 4,   sugar: 1,   servingSize: 40,  servingUnit: 'g'),
      Food(id: '7',  name: 'Banana',           brand: 'Generic',           calories: 105, protein: 1.3, carbs: 27, fat: 0.4, fiber: 3.1, sugar: 14,  servingSize: 118, servingUnit: 'g'),
      Food(id: '8',  name: 'Almonds',          brand: 'Generic',           calories: 164, protein: 6,   carbs: 6,  fat: 14,  fiber: 3.5, sugar: 1.2, servingSize: 28,  servingUnit: 'g'),
      Food(id: '9',  name: 'Salmon',           brand: 'Generic',           calories: 208, protein: 20,  carbs: 0,  fat: 13,  fiber: 0,   sugar: 0,   servingSize: 100, servingUnit: 'g'),
      Food(id: '10', name: 'Sweet Potato',     brand: 'Generic',           calories: 103, protein: 2.3, carbs: 24, fat: 0.1, fiber: 3.8, sugar: 7.4, servingSize: 130, servingUnit: 'g'),
      Food(id: '11', name: 'Whey Protein',     brand: 'Optimum Nutrition', calories: 120, protein: 24,  carbs: 3,  fat: 1.5, fiber: 0,   sugar: 2,   servingSize: 32,  servingUnit: 'g'),
      Food(id: '12', name: 'Avocado',          brand: 'Generic',           calories: 234, protein: 2.9, carbs: 12, fat: 21,  fiber: 9.8, sugar: 0.4, servingSize: 150, servingUnit: 'g'),
      Food(id: '13', name: 'Cottage Cheese',   brand: 'Generic',           calories: 110, protein: 14,  carbs: 6,  fat: 3,   fiber: 0,   sugar: 4,   servingSize: 113, servingUnit: 'g'),
      Food(id: '14', name: 'Tuna',             brand: 'Generic',           calories: 109, protein: 25,  carbs: 0,  fat: 0.5, fiber: 0,   sugar: 0,   servingSize: 100, servingUnit: 'g'),
      Food(id: '15', name: 'Protein Bar',      brand: 'Quest',             calories: 190, protein: 21,  carbs: 21, fat: 7,   fiber: 14,  sugar: 1,   servingSize: 60,  servingUnit: 'g'),
    ];
  }

  List<Food> searchFoods(String query) {
    final foods = getSampleFoods(); // includes custom foods
    if (query.isEmpty) return foods;
    return foods.where((f) =>
      f.name.toLowerCase().contains(query.toLowerCase()) ||
      f.brand.toLowerCase().contains(query.toLowerCase())
    ).toList();
  }

  /// Caches an OpenFoodFacts hit into the local `foods` table (dedup by the
  /// UNIQUE barcode) so repeat lookups are instant/offline. Fire-and-forget.
  Future<void> _cacheFoods(List<Map<String, dynamic>> rows) async {
    final withCode = rows.where((r) => (r['barcode'] as String?)?.isNotEmpty == true).toList();
    if (withCode.isEmpty) return;
    try {
      await _supabase.from('foods').upsert(withCode, onConflict: 'barcode');
    } catch (_) {}
  }

  /// Barcode → nutrition. Checks the local `foods` table first, then falls back
  /// to OpenFoodFacts (and caches the hit). Returns {name, calories, protein,
  /// carbs, fat} per 100g, or null if not found anywhere.
  Future<Map<String, dynamic>?> lookupBarcode(String code) async {
    try {
      final row = await _supabase
          .from('foods')
          .select('name, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g')
          .eq('barcode', code)
          .maybeSingle();
      if (row != null) {
        return {
          'name': row['name'],
          'calories': (row['calories_per_100g'] as num?)?.toDouble() ?? 0,
          'protein': (row['protein_per_100g'] as num?)?.toDouble() ?? 0,
          'carbs': (row['carbs_per_100g'] as num?)?.toDouble() ?? 0,
          'fat': (row['fat_per_100g'] as num?)?.toDouble() ?? 0,
        };
      }
    } catch (_) {}
    try {
      final res = await _off.get(
        'https://world.openfoodfacts.org/api/v2/product/$code.json',
        queryParameters: {'fields': 'product_name,brands,nutriments'});
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      if (data is Map && data['status'] == 1 && data['product'] is Map) {
        final p = data['product'] as Map;
        final n = (p['nutriments'] as Map?) ?? {};
        double nv(String k) => (n[k] as num?)?.toDouble() ?? 0;
        final name = (p['product_name'] as String?)?.trim();
        if (name == null || name.isEmpty) return null;
        final cal = nv('energy-kcal_100g');
        final protein = nv('proteins_100g');
        final carbs = nv('carbohydrates_100g');
        final fat = nv('fat_100g');
        // Cache for instant/offline future lookups.
        _cacheFoods([{
          'barcode': code, 'name': name,
          'brand': (p['brands'] as String?)?.split(',').first.trim(),
          'calories_per_100g': cal, 'protein_per_100g': protein,
          'carbs_per_100g': carbs, 'fat_per_100g': fat,
        }]);
        return {'name': name, 'calories': cal, 'protein': protein, 'carbs': carbs, 'fat': fat};
      }
    } catch (_) {}
    return null;
  }

  /// Searches the cached `foods` table (previously-seen OpenFoodFacts hits +
  /// any seeded foods). Fast and works offline.
  Future<List<Food>> searchFoodsCached(String query) async {
    if (query.trim().length < 2) return [];
    try {
      final rows = await _supabase
          .from('foods')
          .select('barcode,name,brand,calories_per_100g,protein_per_100g,carbs_per_100g,fat_per_100g')
          .ilike('name', '%${query.trim()}%')
          .limit(25);
      double v(dynamic x) => (x as num?)?.toDouble() ?? 0;
      return (rows as List).map((r) => Food(
        id: 'db_${r['barcode'] ?? r['name']}',
        name: r['name'] as String? ?? '',
        brand: r['brand'] as String? ?? 'Generic',
        calories: v(r['calories_per_100g']), protein: v(r['protein_per_100g']),
        carbs: v(r['carbs_per_100g']), fat: v(r['fat_per_100g']),
        fiber: 0, sugar: 0, servingSize: 100, servingUnit: 'g',
        barcode: r['barcode'] as String?,
      )).where((f) => f.name.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Searches the OpenFoodFacts database (per-100g values) for `query`.
  Future<List<Food>> searchFoodsOnline(String query) async {
    if (query.trim().length < 2) return [];
    try {
      final res = await _off.get(
        'https://world.openfoodfacts.org/cgi/search.pl',
        queryParameters: {
          'search_terms': query, 'search_simple': 1, 'action': 'process',
          'json': 1, 'page_size': 25,
          'fields': 'code,product_name,brands,nutriments',
        });
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      final products = (data is Map ? data['products'] as List? : null) ?? const [];
      final out = <Food>[];
      for (final p in products) {
        if (p is! Map) continue;
        final name = (p['product_name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        final n = (p['nutriments'] as Map?) ?? {};
        double nv(String k) => (n[k] as num?)?.toDouble() ?? 0;
        final cal = nv('energy-kcal_100g');
        if (cal <= 0) continue;
        out.add(Food(
          id: 'off_${p['code'] ?? name}',
          name: name,
          brand: (p['brands'] as String?)?.split(',').first.trim() ?? 'Generic',
          calories: cal, protein: nv('proteins_100g'),
          carbs: nv('carbohydrates_100g'), fat: nv('fat_100g'),
          fiber: nv('fiber_100g'), sugar: nv('sugars_100g'),
          servingSize: 100, servingUnit: 'g',
          barcode: p['code'] as String?,
        ));
      }
      // Cache the barcoded results for instant future lookups.
      _cacheFoods(out.map((f) => {
        'barcode': f.barcode, 'name': f.name, 'brand': f.brand,
        'calories_per_100g': f.calories, 'protein_per_100g': f.protein,
        'carbs_per_100g': f.carbs, 'fat_per_100g': f.fat,
      }).toList());
      return out;
    } catch (_) {
      return [];
    }
  }
}
