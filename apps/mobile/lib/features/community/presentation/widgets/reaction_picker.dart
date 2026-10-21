import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/post_model.dart';
import '../../domain/reaction_choice.dart';

/// FIT-065 / FIT-066 · the five reactions, each one reachable and each one
/// named.
///
/// What it replaces: a single heart, plus a read-only tally drawn as bare
/// emoji (`👍❤️🔥` and a number) that a screen reader could only read out as
/// emoji characters and a bare integer.
///
/// The board writes the names with the count in them — `Like, 12 so far`,
/// `Love, 4 so far` — and plain `Fire`, `Clap` where nobody has reacted yet.
class ReactionPicker extends StatelessWidget {
  final List<PostReaction> reactions;

  /// The signed-in user, for "which one did I leave". `'me'` is what the
  /// provider's optimistic update writes.
  final String? uid;

  final ValueChanged<ReactionType> onReact;

  const ReactionPicker({
    super.key,
    required this.reactions,
    required this.uid,
    required this.onReact,
  });

  static const _emoji = {
    ReactionType.like: '👍',
    ReactionType.love: '❤️',
    ReactionType.fire: '🔥',
    ReactionType.clap: '👏',
    ReactionType.strong: '💪',
  };

  @override
  Widget build(BuildContext context) {
    final counts = reactionCounts(reactions);
    final mine = myReaction(reactions, uid);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: ReactionType.values.map((t) {
        final count = counts[t] ?? 0;
        final isMine = mine == t;
        return Semantics(
          button: true,
          // Whether I reacted rides on `selected`, not on the name, so a
          // reader announces it in the user's own language.
          selected: isMine,
          label: reactionSemanticLabel(t, count),
          excludeSemantics: true,
          onTap: () => onReact(t),
          child: GestureDetector(
            onTap: () => onReact(t),
            behavior: HitTestBehavior.opaque,
            child: Container(
              key: ValueKey('reaction-${t.name}'),
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isMine
                    ? AppColors.purple.withValues(alpha: 0.18)
                    : AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isMine
                      ? AppColors.purple
                      : AppColors.surfaceDarkElevated,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_emoji[t]!, style: const TextStyle(fontSize: 14)),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Text('$count',
                        style: TextStyle(
                            color: isMine
                                ? AppColors.white
                                : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
