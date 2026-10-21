import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/animations/app_animations.dart';
import '../../data/models/post_model.dart';
import '../../domain/community_provider.dart';
import 'reaction_bar.dart';

class PostCard extends ConsumerStatefulWidget {
  final CommunityPost post;
  final int index;

  const PostCard({super.key, required this.post, required this.index});

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _showComments = false;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Color get _postTypeColor {
    switch (widget.post.type) {
      case PostType.achievement: return const Color(0xFFFFD700);
      case PostType.progress: return AppColors.success;
      case PostType.workout: return AppColors.purple;
      case PostType.photo: return const Color(0xFF60A5FA);
      default: return AppColors.textTertiary;
    }
  }

  String get _postTypeLabel {
    switch (widget.post.type) {
      case PostType.achievement: return '🏆 Achievement';
      case PostType.progress: return '📈 Progress Update';
      case PostType.workout: return '💪 Workout';
      case PostType.photo: return '📸 Photo';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceDarkElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.purple.withValues(alpha:0.2),
                      child: Text(widget.post.userName[0],
                          style: const TextStyle(color: AppColors.purple, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(widget.post.userName,
                                  style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              if (widget.post.userRole == 'Coach') ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.purple.withValues(alpha:0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('Coach', style: TextStyle(color: AppColors.purple, fontSize: 10, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ],
                          ),
                          Row(
                            children: [
                              Text(_formatTime(widget.post.createdAt),
                                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                              if (widget.post.groupName != null) ...[
                                const Text(' · ', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                                Text(widget.post.groupName!,
                                    style: const TextStyle(color: AppColors.purple, fontSize: 12)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_horiz, color: AppColors.textTertiary),
                      onPressed: () {},
                    ),
                  ],
                ),
                if (widget.post.type != PostType.text) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _postTypeColor.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_postTypeLabel,
                        style: TextStyle(color: _postTypeColor, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
                const SizedBox(height: 12),
                Text(widget.post.content,
                    style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.6)),
              ],
            ),
          ),
          ReactionBar(
            post: widget.post,
            onLike: () {
              AppAnimations.hapticLight();
              ref.read(postNotifierProvider.notifier).toggleLike(widget.post.id);
            },
            onReact: (type) {
              AppAnimations.hapticLight();
              ref
                  .read(postNotifierProvider.notifier)
                  .toggleReaction(widget.post.id, type);
            },
            onComment: () => setState(() => _showComments = !_showComments),
            onShare: () => AppAnimations.hapticLight(),
          ),
          if (_showComments) ...[
            const Divider(color: AppColors.surfaceDarkElevated, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ...widget.post.comments.map((comment) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.purple.withValues(alpha:0.2),
                          child: Text(comment.userName[0],
                              style: const TextStyle(color: AppColors.purple, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceDarkElevated,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(comment.userName,
                                    style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(comment.content,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.purple,
                        child: Icon(Icons.person, color: AppColors.white, size: 14),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          style: const TextStyle(color: AppColors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Write a comment...',
                            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                            filled: true,
                            fillColor: AppColors.surfaceDarkElevated,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.send, color: AppColors.purple, size: 18),
                              onPressed: () {
                                if (_commentController.text.trim().isEmpty) return;
                                ref.read(postNotifierProvider.notifier).addComment(widget.post.id, _commentController.text.trim());
                                _commentController.clear();
                                AppAnimations.hapticLight();
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate(delay: Duration(milliseconds: widget.index * 100))
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.2, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
