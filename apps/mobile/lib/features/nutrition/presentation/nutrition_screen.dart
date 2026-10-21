import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/nutrition_service.dart';
import '../data/models/food_model.dart';
import '../domain/nutrition_provider.dart';
import 'widgets/coach_insight_card.dart';
import 'widgets/food_added_dialog.dart';
import '../../../core/widgets/named_icon_button.dart';

const _bg       = Color(0xFF030303);
const _card     = Color(0xFF0E0B16);
const _border   = Color(0xFF1A1020);
const _brand    = Color(0xFFA855F7);
const _white    = Colors.white;
const _muted    = Color(0xFFCFC2D6);
const _tertiary = Color(0xFF6FFBBE);
const _error    = Color(0xFFFFB4AB);

final _svcProvider = Provider<NutritionService>((ref) => NutritionService());
final _totalsProvider = FutureProvider<Map<String, double>>((ref) async =>
  ref.watch(_svcProvider).getTodayTotals());
final _logsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async =>
  ref.watch(_svcProvider).getTodayLogs());

class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});
  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  int _water = 3;

  @override
  Widget build(BuildContext context) {
    final totals  = ref.watch(_totalsProvider);
    final logs    = ref.watch(_logsProvider);
    final goals   = ref.watch(nutritionGoalsProvider);
    final cal     = totals.valueOrNull?['calories'] ?? 0.0;
    final protein = totals.valueOrNull?['protein']  ?? 0.0;
    final carbs   = totals.valueOrNull?['carbs']    ?? 0.0;
    final fat     = totals.valueOrNull?['fat']      ?? 0.0;
    final calGoal     = goals.valueOrNull?['calories'] ?? 2000.0;
    final proteinGoal = goals.valueOrNull?['protein']  ?? 120.0;
    final carbGoal    = goals.valueOrNull?['carbs']    ?? 220.0;
    final fatGoal     = goals.valueOrNull?['fat']      ?? 65.0;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: const BoxDecoration(
            color: _card,
            border: Border(bottom: BorderSide(color: _border))),
          child: Row(children: [
            const Text("Nutrition",
              style: TextStyle(color: _white, fontSize: 19, fontWeight: FontWeight.w700)),
            const Spacer(),
            GestureDetector(
              onTap: () => _showAddMealSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _brand,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [BoxShadow(color: _brand.withValues(alpha: 0.4), blurRadius: 10)]),
                child: const Row(children: [
                  Icon(Icons.add, color: _white, size: 16),
                  SizedBox(width: 4),
                  Text("Log Meal", style: TextStyle(color: _white, fontSize: 12,
                    fontWeight: FontWeight.w700)),
                ]))),
          ])),
        Expanded(
          child: RefreshIndicator(
            color: _brand,
            backgroundColor: _card,
            onRefresh: () async {
              ref.invalidate(_totalsProvider);
              ref.invalidate(_logsProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(children: [
                // Calorie card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1C0D30), Color(0xFF0A0612)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _brand.withValues(alpha: 0.2))),
                  child: Row(children: [
                    SizedBox(width: 100, height: 100,
                      child: Stack(alignment: Alignment.center, children: [
                        CustomPaint(size: const Size(100, 100),
                          painter: _RingPainter(
                            progress: calGoal == 0 ? 0 : (cal / calGoal).clamp(0, 1))),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(cal.toInt().toString(),
                            style: const TextStyle(color: _white, fontSize: 24,
                              fontWeight: FontWeight.w800, height: 1)),
                          Text("kcal",
                            style: TextStyle(color: _muted.withValues(alpha: 0.5),
                              fontSize: 10)),
                        ]),
                      ])),
                    const SizedBox(width: 20),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${cal.toInt()} / ${calGoal.toInt()} kcal",
                          style: const TextStyle(color: _white, fontSize: 15,
                            fontWeight: FontWeight.w700)),
                        Text("${(calGoal - cal).clamp(0, calGoal).toInt()} remaining",
                          style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 12)),
                        const SizedBox(height: 14),
                        _MacroBar(label: "Protein", value: protein,
                          goal: proteinGoal, color: _brand, unit: "g"),
                        const SizedBox(height: 8),
                        _MacroBar(label: "Carbs", value: carbs,
                          goal: carbGoal, color: _tertiary, unit: "g"),
                        const SizedBox(height: 8),
                        _MacroBar(label: "Fat", value: fat,
                          goal: fatGoal, color: _error, unit: "g"),
                      ])),
                  ])),
                const SizedBox(height: 16),
                // Coach Insight
                CoachInsightCard(
                  protein: protein,
                  proteinGoal: proteinGoal,
                  calories: cal,
                  calorieGoal: calGoal,
                ),
                const SizedBox(height: 16),
                // Water tracker
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _border)),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Row(children: [
                        Icon(Icons.water_drop_outlined,
                          color: Color(0xFFADC6FF), size: 18),
                        SizedBox(width: 8),
                        Text("Water", style: TextStyle(color: _white,
                          fontSize: 15, fontWeight: FontWeight.w600)),
                      ]),
                      Text("$_water / 8 glasses",
                        style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 12)),
                    ]),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(8, (i) =>
                        GestureDetector(
                          onTap: () => setState(() =>
                            _water = i + 1 == _water ? i : i + 1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 28, height: 36,
                            decoration: BoxDecoration(
                              color: i < _water
                                ? const Color(0xFFADC6FF).withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: i < _water
                                  ? const Color(0xFFADC6FF).withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.06))),
                            child: Icon(Icons.water_drop,
                              color: i < _water
                                ? const Color(0xFFADC6FF)
                                : Colors.white.withValues(alpha: 0.1),
                              size: 16)))),
                    ),
                  ])),
                const SizedBox(height: 16),
                // Today's meals
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("Today's Meals",
                    style: TextStyle(color: _white, fontSize: 16,
                      fontWeight: FontWeight.w700)),
                  GestureDetector(
                    onTap: () => _showAddMealSheet(context),
                    child: Text("+ Add", style: TextStyle(color: _brand,
                      fontSize: 13, fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 12),
                logs.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: _brand)),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (meals) => meals.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _border)),
                        child: Column(children: [
                          Icon(Icons.restaurant_outlined,
                            color: _brand.withValues(alpha: 0.3), size: 40),
                          const SizedBox(height: 12),
                          Text("No meals logged yet",
                            style: TextStyle(color: _muted.withValues(alpha: 0.5))),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => _showAddMealSheet(context),
                            child: Text("Log your first meal →",
                              style: TextStyle(color: _brand, fontSize: 13,
                                fontWeight: FontWeight.w600))),
                        ]))
                    : Column(children: meals.map((m) => _MealTile(meal: m)).toList()),
                ),
              ])))),
      ])));
  }

  void _showAddMealSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMealSheet(onLogged: () async {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          ref.invalidate(_totalsProvider);
          ref.invalidate(_logsProvider);
        }
      }));
  }
}

// ── Add Meal Sheet ─────────────────────────────────────────────────────────────
class _AddMealSheet extends ConsumerStatefulWidget {
  final VoidCallback onLogged;
  const _AddMealSheet({required this.onLogged});
  @override
  ConsumerState<_AddMealSheet> createState() => _AddMealSheetState();
}

class _AddMealSheetState extends ConsumerState<_AddMealSheet> {
  final _svc = NutritionService();
  final _searchCtrl = TextEditingController();
  Food? _selected;
  String _mealType = "breakfast";
  double _servings = 1.0;
  bool _saving = false;
  List<Food> _filtered = [];
  final _meals = ["breakfast", "lunch", "dinner", "snack", "protein_shake"];

  @override
  void initState() {
    super.initState();
    _filtered = _svc.getSampleFoods();
    _searchCtrl.addListener(() =>
      setState(() => _filtered = _svc.searchFoods(_searchCtrl.text)));
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  String _mealTypeLabel(String m) {
    switch (m) {
      case "protein_shake": return "Protein Shake";
      default: return m[0].toUpperCase() + m.substring(1);
    }
  }

  Future<void> _log() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    final food = _selected!;
    final servings = _servings;
    try {
      await _svc.logMeal(
        mealType: _mealType,
        foodName: food.name,
        calories: food.calories * servings,
        protein: food.protein * servings,
        carbs: food.carbs * servings,
        fat: food.fat * servings,
        servingSize: food.servingSize * servings,
        servingUnit: food.servingUnit);
      if (!mounted) return;
      setState(() => _saving = false);
      widget.onLogged();
      // The context is captured as the NAVIGATOR's, not this sheet's. Popping
      // deactivates the sheet's element, and `showDialog` against a deactivated
      // context can raise "Looking up a deactivated widget's ancestor" — it
      // usually appears to work only because the ancestor lookup resolves before
      // the pop animation finishes, which is what makes it latent rather than
      // visible. The NavigatorState's own context outlives the route it popped.
      //
      // Safe here specifically because `FoodAddedDialog.show` uses the context
      // for nothing but `showDialog`'s Navigator/Overlay lookup: its builder is
      // `(_) =>`, and the dialog takes plain values, so no inherited widget is
      // read through it and the ancestor change cannot alter what renders.
      final navigator = Navigator.of(context);
      navigator.pop();
      FoodAddedDialog.show(
        navigator.context,
        foodName: food.name,
        protein: (food.protein * servings).toInt(),
        carbs: (food.carbs * servings).toInt(),
        fat: (food.fat * servings).toInt(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not log meal.'),
        backgroundColor: const Color(0xFFFFB4AB),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(children: [
          Container(margin: const EdgeInsets.only(top: 12),
            width: 36, height: 4,
            decoration: BoxDecoration(color: _border,
              borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              const Text("Log Meal", style: TextStyle(color: _white,
                fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              Semantics(
                button: true,
                label: 'Close',
                child: GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  alignment: Alignment.center,
                  child: Icon(Icons.close, color: _muted.withValues(alpha: 0.5), size: 22)))),
            ])),
          const SizedBox(height: 12),
          // Meal type tabs
          SizedBox(height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _meals.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final m = _meals[i];
                final active = m == _mealType;
                return GestureDetector(
                  onTap: () => setState(() => _mealType = m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? _brand : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: active ? _brand : _border)),
                    child: Text(
                      _mealTypeLabel(m),
                      style: TextStyle(
                        color: active ? _white : _muted.withValues(alpha: 0.6),
                        fontSize: 12, fontWeight: FontWeight.w600))));
              })),
          const SizedBox(height: 12),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border)),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: _white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Search foods...",
                  hintStyle: TextStyle(color: _muted.withValues(alpha: 0.35)),
                  prefixIcon: Icon(Icons.search,
                    color: _muted.withValues(alpha: 0.4), size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12)),
                onTapOutside: (_) => FocusScope.of(context).unfocus()))),
          const SizedBox(height: 8),
          Expanded(
            child: _selected != null
              ? _FoodDetail(
                  food: _selected!,
                  servings: _servings,
                  saving: _saving,
                  onChanged: (v) => setState(() => _servings = v),
                  onLog: _log,
                  onBack: () => setState(() => _selected = null))
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final f = _filtered[i];
                    return GestureDetector(
                      onTap: () => setState(() => _selected = f),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border)),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: _brand.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10)),
                            alignment: Alignment.center,
                            child: Text(f.name[0], style: const TextStyle(
                              color: _brand, fontSize: 16, fontWeight: FontWeight.w800))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.name, style: const TextStyle(color: _white,
                                fontSize: 14, fontWeight: FontWeight.w600)),
                              Text("${f.brand} · ${f.servingSize.toInt()}${f.servingUnit}",
                                style: TextStyle(color: _muted.withValues(alpha: 0.5),
                                  fontSize: 11)),
                            ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text("${f.calories.toInt()} kcal",
                              style: const TextStyle(color: _white,
                                fontSize: 13, fontWeight: FontWeight.w700)),
                            Text("P: ${f.protein.toInt()}g",
                              style: TextStyle(color: _brand, fontSize: 11)),
                          ]),
                        ])));
                  })),
        ])));
  }
}

class _FoodDetail extends StatelessWidget {
  final Food food;
  final double servings;
  final bool saving;
  final ValueChanged<double> onChanged;
  final VoidCallback onLog, onBack;
  const _FoodDetail({required this.food, required this.servings,
    required this.saving, required this.onChanged,
    required this.onLog, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final cal  = (food.calories * servings).toInt();
    final prot = (food.protein  * servings).toInt();
    final carb = (food.carbs    * servings).toInt();
    final fat  = (food.fat      * servings).toInt();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(children: [
        Row(children: [
          NamedIconButton(
            label: 'Back',
            onTap: onBack,
            child: Icon(Icons.arrow_back, color: _muted.withValues(alpha: 0.6), size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text(food.name, style: const TextStyle(color: _white,
            fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _Chip("Calories", "$cal",  "kcal", _white),
            _Chip("Protein",  "$prot", "g",    _brand),
            _Chip("Carbs",    "$carb", "g",    _tertiary),
            _Chip("Fat",      "$fat",  "g",    _error),
          ])),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("Servings (${food.servingSize.toInt()}${food.servingUnit})",
            style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 13)),
          Text(servings.toStringAsFixed(1),
            style: const TextStyle(color: _white, fontSize: 18,
              fontWeight: FontWeight.w800)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: _brand,
            inactiveTrackColor: _border,
            thumbColor: _brand,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayColor: _brand.withValues(alpha: 0.2)),
          child: Slider(value: servings, min: 0.5, max: 5,
            divisions: 9, onChanged: onChanged)),
        const Spacer(),
        SizedBox(width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: saving ? null : onLog,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brand, foregroundColor: _white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
              elevation: 0),
            child: saving
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: _white, strokeWidth: 2))
              : Text("Log ${food.name}",
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)))),
      ]));
  }
}

class _Chip extends StatelessWidget {
  final String label, value, unit;
  final Color color;
  const _Chip(this.label, this.value, this.unit, this.color);

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(color: color, fontSize: 20,
      fontWeight: FontWeight.w800)),
    Text(unit, style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 10)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(color: _muted.withValues(alpha: 0.4), fontSize: 10)),
  ]);
}

class _MealTile extends StatelessWidget {
  final Map<String, dynamic> meal;
  const _MealTile({required this.meal});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border)),
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: _brand.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: Text((meal['food_name'] as String? ?? 'F')[0],
          style: const TextStyle(color: _brand, fontSize: 16,
            fontWeight: FontWeight.w800))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(meal['food_name'] ?? '', style: const TextStyle(color: _white,
          fontSize: 14, fontWeight: FontWeight.w600)),
        Text(meal['meal_type'] ?? '',
          style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 11)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text("${(meal['calories'] as num?)?.toInt() ?? 0} kcal",
          style: const TextStyle(color: _white, fontSize: 13,
            fontWeight: FontWeight.w700)),
        Text("P: ${(meal['protein'] as num?)?.toInt() ?? 0}g",
          style: TextStyle(color: _brand, fontSize: 11)),
      ]),
    ]));
}

class _MacroBar extends StatelessWidget {
  final String label, unit;
  final double value, goal;
  final Color color;
  const _MacroBar({required this.label, required this.value, required this.goal,
    required this.color, required this.unit});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: _muted.withValues(alpha: 0.6),
          fontSize: 11, fontWeight: FontWeight.w500)),
        Text("${value.toInt()} / ${goal.toInt()}$unit",
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: (value / goal).clamp(0.0, 1.0),
          backgroundColor: _border,
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: 6)),
    ]);
}

class _RingPainter extends CustomPainter {
  final double progress;
  const _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 8;
    canvas.drawCircle(c, r, Paint()
      ..color = const Color(0xFF252528)
      ..strokeWidth = 8..style = PaintingStyle.stroke);
    if (progress > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r),
        -3.14159 / 2, 2 * 3.14159 * progress, false,
        Paint()
          ..shader = SweepGradient(
            startAngle: -3.14159 / 2,
            endAngle: -3.14159 / 2 + 2 * 3.14159,
            colors: const [Color(0xFFDDB7FF), Color(0xFFA855F7)],
          ).createShader(Rect.fromCircle(center: c, radius: r))
          ..strokeWidth = 8..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
