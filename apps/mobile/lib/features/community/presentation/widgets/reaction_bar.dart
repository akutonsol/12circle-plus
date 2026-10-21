import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/post_model.dart';
import 'reaction_picker.dart';

class ReactionBar extends StatelessWidget {
  final CommunityPost post;
  /// Kept: the heart in the action row below still means `like`.
  final VoidCallback onLike;

  /// FIT-065/066: any of the five.
  final ValueChanged<ReactionType> onReact;
  final VoidCallback onComment;
  final VoidCallback onShare;

  const ReactionBar({
    super.key,
    required this.post,
    required this.onLike,
    required this.onReact,
    required this.onComment,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final commentCount = post.comments.length;

    return Column(
      children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // FIT-065/066. This was `_buildReactionEmoji()` — bare emoji
                // and a bare integer, which a screen reader reads as emoji
                // characters and a number, saying nothing about what they
                // are. The picker names each one and makes all five
                // reachable; only `like` could be written before.
                Expanded(
                    child: ReactionPicker(
                      reactions: post.reactions,
                      uid: 'me',
                      onReact: onReact,
                    ),
                  ),
                if (commentCount > 0)
                  Text('$commentCount comments', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        const Divider(color: AppColors.surfaceDarkElevated, height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: _buildActionButton(
                icon: post.isLiked ? Icons.favorite : Icons.favorite_border,
                label: post.isLiked ? 'Liked' : 'Like',
                color: post.isLiked ? AppColors.error : AppColors.textSecondary,
                onTap: onLike,
              )),
              Expanded(child: _buildActionButton(
                icon: Icons.chat_bubble_outline,
                label: 'Comment',
                color: AppColors.textSecondary,
                onTap: onComment,
              )),
              Expanded(child: _buildActionButton(
                icon: Icons.share_outlined,
                label: 'Share',
                color: AppColors.textSecondary,
                onTap: onShare,
              )),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildActionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
