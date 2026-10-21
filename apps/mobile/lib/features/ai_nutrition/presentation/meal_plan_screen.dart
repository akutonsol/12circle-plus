import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/nutrition/domain/nutrition_provider.dart';
import '../domain/ai_nutrition_provider.dart';
import '../domain/meal_plan.dart';

class MealPlanScreen extends ConsumerStatefulWidget {
  const MealPlanScreen({super.key});

  @override
  ConsumerState<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends ConsumerState<MealPlanScreen> {
  int _calories = 1800;
  int _protein = 140;
  int _carbs = 180;
  int _fat = 60;
  int _days = 7;
  bool _isLoading = false;
  bool _goalsLoaded = false;
  final List<String> _restrictions = [];

  final List<String> _restrictionOptions = [
    'Vegetarian', 'Vegan', 'Gluten-Free', 'Dairy-Free', 'Nut-Free', 'Halal'
  ];

  void _loadGoalsOnce(Map<String, double>? goals) {
    if (_goalsLoaded || goals == null) return;
    _goalsLoaded = true;
    setState(() {
      _calories = goals['calories']?.toInt() ?? _calories;
      _protein  = goals['protein']?.toInt()  ?? _protein;
      _carbs    = goals['carbs']?.toInt()    ?? _carbs;
      _fat      = goals['fat']?.toInt()      ?? _fat;
    });
  }

  Future<void> _generatePlan() async {
    setState(() => _isLoading = true);
    await ref.read(mealPlanNotifierProvider.notifier).generateMealPlan(
      calories: _calories,
      protein: _protein,
      carbs: _carbs,
      fat: _fat,
      restrictions: _restrictions,
      days: _days,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final outcome = mealPlanOutcome(ref.watch(mealPlanNotifierProvider));
    final goals    = ref.watch(nutritionGoalsProvider);
    goals.whenData(_loadGoalsOnce);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: const Text('AI Meal Planner', style: TextStyle(color: AppColors.white)),
        actions: [
          if (canBuildGroceryList(outcome))
            TextButton(
              onPressed: () => context.push('/grocery-list'),
              child: const Text('Grocery List', style: TextStyle(color: AppColors.purple)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Set Your Targets', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceDarkElevated),
              ),
              child: Column(
                children: [
                  _buildSlider('Calories', _calories.toDouble(), 1200, 3000, (v) => setState(() => _calories = v.toInt()), AppColors.purple, 'kcal'),
                  _buildSlider('Protein', _protein.toDouble(), 50, 250, (v) => setState(() => _protein = v.toInt()), const Color(0xFF60A5FA), 'g'),
                  _buildSlider('Carbs', _carbs.toDouble(), 50, 400, (v) => setState(() => _carbs = v.toInt()), const Color(0xFFFBBF24), 'g'),
                  _buildSlider('Fat', _fat.toDouble(), 20, 150, (v) => setState(() => _fat = v.toInt()), const Color(0xFFF87171), 'g'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Plan Duration', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: [1, 3, 5, 7].map((days) {
                final isSelected = _days == days;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _days = days),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.purple : AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? AppColors.purple : AppColors.surfaceDarkElevated),
                        ),
                        child: Text(
                          '$days days',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: isSelected ? AppColors.white : AppColors.textSecondary, fontWeight: FontWeight.w500, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            const Text('Dietary Restrictions', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _restrictionOptions.map((option) {
                final isSelected = _restrictions.contains(option);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (isSelected) _restrictions.remove(option);
                    else _restrictions.add(option);
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.purple.withValues(alpha: 0.2) : AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? AppColors.purple : AppColors.surfaceDarkElevated),
                    ),
                    child: Text(option, style: TextStyle(color: isSelected ? AppColors.purple : AppColors.textSecondary, fontSize: 13)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _generatePlan,
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Generating your meal plan...'),
                      ],
                    )
                  : const Text('Generate Meal Plan'),
            ),
            // FIT-093. This branch did not exist: a failure arrived as the
            // plan's text and was rendered under the heading below.
            if (outcome is MealPlanFailed) ...[
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceDarkElevated),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.textTertiary, size: 40),
                    const SizedBox(height: 12),
                    const Text(mealPlanFailedTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text(mealPlanFailedBody,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 14)),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _isLoading ? null : _generatePlan,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 56),
                        side: const BorderSide(color: AppColors.purple),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(mealPlanTryAgainLabel,
                          style: TextStyle(color: AppColors.purple)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
            if (outcome is MealPlanReady) ...[
              const SizedBox(height: 32),
              const Text('Your Meal Plan', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceDarkElevated),
                ),
                child: Text(outcome.plan, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.6)),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.push('/grocery-list'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  side: const BorderSide(color: AppColors.purple),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                // FIT-092 names this. It said "Generate Grocery List".
                child: const Text(mealPlanToGroceryLabel, style: TextStyle(color: AppColors.purple)),
              ),
              const SizedBox(height: 12),
              // FIT-092's third control, which had no equivalent at all.
              TextButton(
                onPressed: _isLoading ? null : _generatePlan,
                child: const Text(mealPlanRebuildLabel,
                    style: TextStyle(color: AppColors.textTertiary)),
              ),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, Function(double) onChanged, Color color, String unit) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            Text('${value.toInt()} $unit', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: AppColors.surfaceDarkElevated,
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.2),
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}
