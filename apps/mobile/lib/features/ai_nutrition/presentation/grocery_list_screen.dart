import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/ai_nutrition_provider.dart';
import '../domain/grocery_list.dart';
import 'widgets/grocery_item_card.dart';

/// FIT-094 · the two blocked states · FIT-095 · the built list.
///
/// The screen used to decide what to show from two nullable strings inline,
/// and got the failing case wrong: the error was written into the same slot as
/// the list, the parser dropped it, and the result was the header over an
/// empty column. `groceryOutcome` makes that decision once, in a place a test
/// can reach.
class GroceryListScreen extends ConsumerStatefulWidget {
  const GroceryListScreen({super.key});

  @override
  ConsumerState<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends ConsumerState<GroceryListScreen> {
  bool _isLoading = false;

  Future<void> _generateList() async {
    final mealPlan = ref.read(mealPlanNotifierProvider).content;
    if (mealPlan == null) return;
    setState(() => _isLoading = true);
    await ref
        .read(groceryListNotifierProvider.notifier)
        .generateGroceryList(mealPlan);
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(groceryListNotifierProvider);
    final outcome = groceryOutcome(
      mealPlan: ref.watch(mealPlanNotifierProvider).content,
      rawList: list.content,
      listFailed: list.failed,
    );

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title:
            const Text('Grocery List', style: TextStyle(color: AppColors.white)),
      ),
      body: switch (outcome) {
        GroceryNeedsMealPlan() => _Blocked(
            icon: Icons.shopping_cart_outlined,
            title: 'No meal plan yet',
            body: 'The list is built from your plan.',
            action: groceryBuildMealPlanLabel,
            onAction: () => context.push('/meal-plan'),
          ),
        // FIT-094's `failure`. This state did not exist: the request's error
        // was parsed as a list, produced nothing, and rendered as a blank.
        GroceryFailed() => _Blocked(
            icon: Icons.warning_amber_rounded,
            title: groceryFailedTitle,
            body: groceryFailedBody,
            action: groceryTryAgainLabel,
            onAction: _isLoading ? null : _generateList,
          ),
        GroceryNotBuilt() => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shopping_basket_outlined,
                    color: AppColors.textTertiary, size: 64),
                const SizedBox(height: 16),
                const Text('Ready to generate your list',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 16)),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _generateList,
                    child: _isLoading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2)),
                              SizedBox(width: 12),
                              Text('Generating...'),
                            ],
                          )
                        : const Text('Generate Grocery List'),
                  ),
                ),
              ],
            ),
          ),
        GroceryReady(categories: final categories) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Your Grocery List',
                      style: TextStyle(
                          color: AppColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    onPressed: _isLoading ? null : _generateList,
                    icon: const Icon(Icons.refresh,
                        color: AppColors.purple, size: 16),
                    // FIT-095 names this control. It said "Refresh".
                    label: const Text(groceryRebuildLabel,
                        style:
                            TextStyle(color: AppColors.purple, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...categories.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: GroceryItemCard(
                      // Without a key this State is reused by POSITION across a
                      // rebuild, which is how ticks migrated between categories.
                      key: ValueKey(c.name),
                      category: c.name,
                      items: c.items,
                    ),
                  )),
              const SizedBox(height: 32),
            ],
          ),
      },
    );
  }
}

/// FIT-094 draws both blocked states the same way: an icon, a sentence, and a
/// single control.
class _Blocked extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback? onAction;

  const _Blocked({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.textTertiary, size: 64),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 16)),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: onAction, child: Text(action)),
            ],
          ),
        ),
      );
}
