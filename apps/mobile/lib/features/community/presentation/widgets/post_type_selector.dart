import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/post_model.dart';
import '../../domain/post_type_choice.dart';

/// FIT-067 · the five post types, as the mutually exclusive choice the board
/// draws.
///
/// What it replaces:
///
/// ```dart
/// _buildPostTypeChip('📸 Photo', () {}),
/// _buildPostTypeChip('🏆 Achievement', () {}),
/// _buildPostTypeChip('💪 Workout', () {}),
/// ```
///
/// Three of the five, each with an empty callback — controls that looked
/// selectable, highlighted nothing, and were read by nothing. To a screen
/// reader they were three unrelated buttons, not a choice.
class PostTypeSelector extends StatelessWidget {
  final PostType selected;
  final ValueChanged<PostType> onSelect;

  const PostTypeSelector({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: postTypeChoices.map((t) {
          final isSelected = t == selected;
          return Semantics(
            // `role="radio"` on the board: one of a set, not a button that
            // happens to be next to others.
            inMutuallyExclusiveGroup: true,
            selected: isSelected,
            label: postTypeLabel(t),
            excludeSemantics: true,
            onTap: () => onSelect(t),
            child: GestureDetector(
              onTap: () => onSelect(t),
              behavior: HitTestBehavior.opaque,
              child: Container(
                key: ValueKey('post-type-${t.name}'),
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.purple.withValues(alpha: 0.18)
                      : AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.purple
                        : AppColors.surfaceDarkElevated,
                  ),
                ),
                child: Text(
                  postTypeLabel(t),
                  style: TextStyle(
                    color:
                        isSelected ? AppColors.white : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
}
