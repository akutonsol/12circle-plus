import 'dart:async' show StreamSubscription;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Supabase;
import '../../../../core/observability/app_failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/animations/app_animations.dart';
import '../../data/models/post_model.dart';
import '../../../workout/presentation/widgets/section_load_failure.dart'
    show couldntMessage;
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
  bool _commenting = false;

  /// P0-FL-59e · whose comment is being written: the notifier read at the tap
  /// is the feed of whoever is signed in THEN. The draft goes with them. Taken
  /// on at a redraw only: what is still up was drawn for the one before.
  String? _owner = _signedIn;
  StreamSubscription<AuthState>? _authSub;

  static String? get _signedIn =>
      Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (_) => _followAccount(),
        onError: (Object e, StackTrace s) =>
            reportError('PostCard.onAuthStateChange', e, s));
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  void _followAccount() {
    if (!mounted || _signedIn == _owner) return;
    setState(_forget);
  }

  void _forget() {
    _commentController.clear();
    _commenting = false;
    _showComments = false;
  }

  /// False (recorded, the draft cleared) once someone else is signed in.
  bool _stillOwner(String? owner, String what) {
    if (owner == _owner && _signedIn == owner) return true;
    reportError('PostCard.identity',
        StateError('$what: the signed-in account changed'));
    _followAccount();
    return false;
  }

  Future<void> _comment() async {
    final text = _commentController.text.trim();
    final owner = _owner;
    if (_commenting || text.isEmpty || !_stillOwner(owner, 'comment')) return;
    setState(() => _commenting = true);
    try {
      await ref
          .read(postNotifierProvider.notifier)
          .addComment(widget.post.id, text);
    } catch (e, st) {
      reportError('PostCard.comment', e, st);
      if (!mounted || !_stillOwner(owner, 'comment')) return;
      setState(() => _commenting = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(couldntMessage('post that comment', e))));
      return;
    }
    if (_signedIn != owner) return; // another member's phone by now
    AppAnimations.hapticLight();
    if (!mounted || _owner != owner) return;
    // What was typed meanwhile is not the comment that was sent.
    if (_commentController.text.trim() == text) _commentController.clear();
    setState(() => _commenting = false);
  }

  Future<void> _react(Future<void> Function(PostNotifier feed) send) async {
    final owner = _owner;
    if (!_stillOwner(owner, 'reaction')) return;
    AppAnimations.hapticLight();
    try {
      await send(ref.read(postNotifierProvider.notifier));
    } catch (e, st) {
      reportError('PostCard.reaction', e, st);
      if (!mounted || !_stillOwner(owner, 'reaction')) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(couldntMessage('save your reaction', e))));
    }
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
    if (_signedIn != _owner) {
      _owner = _signedIn;
      _forget(); // whether or not the change was heard of yet
    }
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
            onLike: () => _react((feed) => feed.toggleLike(widget.post.id)),
            onReact: (type) =>
                _react((feed) => feed.toggleReaction(widget.post.id, type)),
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
                              onPressed: _comment,
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
