import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/community_service.dart';
import '../data/live_community_service.dart';
import '../data/models/post_model.dart';
import '../../coach/data/score_service.dart';
import '../../scoring/data/score_engine.dart';
import 'reaction_choice.dart';

final communityServiceProvider = Provider<CommunityService>((ref) => CommunityService());
final liveCommunityServiceProvider = Provider<LiveCommunityService>((ref) => LiveCommunityService());

final selectedCommunityTabProvider = StateProvider<int>((ref) => 0);
final selectedPostProvider = StateProvider<CommunityPost?>((ref) => null);

// ── Live posts from Supabase ──────────────────────────────────────────────────
final livePostsProvider = FutureProvider<List<CommunityPost>>((ref) async {
  final svc = ref.watch(liveCommunityServiceProvider);
  final live = await svc.getPosts();
  // Real posts only — no sample fallback (avoids demo names in production).
  return live;
});

class PostNotifier extends StateNotifier<AsyncValue<List<CommunityPost>>> {
  final LiveCommunityService _svc;
  final ScoreService _score;

  PostNotifier(this._svc, CommunityService _, this._score) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final live = await _svc.getPosts();
      state = AsyncValue.data(live);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> reload() => _load();

  /// Kept for callers that only ever meant the heart.
  Future<void> toggleLike(String postId) => toggleReaction(postId, ReactionType.like);

  /// FIT-065/066. The provider used to hardcode `'like'`, so four of the five
  /// reaction types could be READ by this app and never written by it.
  Future<void> toggleReaction(String postId, ReactionType type) async {
    await _svc.toggleReaction(postId, reactionWire(type));
    final posts = state.valueOrNull ?? [];
    state = AsyncValue.data(posts.map((p) {
      if (p.id != postId) return p;
      // Optimistic: same one again takes it back, a different one switches.
      final mine = p.reactions.where((r) => r.userId == 'me').toList();
      final had = mine.isEmpty ? null : mine.first.type;
      final others = p.reactions.where((r) => r.userId != 'me').toList();
      final newReactions = had == type
          ? others
          : [...others, PostReaction(userId: 'me', type: type)];
      final newIsLiked =
          newReactions.any((r) => r.userId == 'me' && r.type == ReactionType.like);
      return CommunityPost(
        id: p.id, userId: p.userId, userName: p.userName,
        userRole: p.userRole, content: p.content, type: p.type,
        imageUrls: p.imageUrls, reactions: newReactions,
        comments: p.comments, createdAt: p.createdAt,
        groupId: p.groupId, groupName: p.groupName, isLiked: newIsLiked,
      );
    }).toList());
  }

  Future<void> addComment(String postId, String content) async {
    await _svc.addComment(postId, content);
    await _load();
  }

  Future<void> addPost(String content, {String postType = 'general'}) async {
    final post = await _svc.createPost(content, postType: postType);
    ScoreEngine().communityPost(); // +5, once/day
    state = AsyncValue.data([post, ...(state.valueOrNull ?? [])]);
    // Award community points for posting
    await _score.addCommunityPoints();
  }
}

final postNotifierProvider = StateNotifierProvider<PostNotifier, AsyncValue<List<CommunityPost>>>((ref) {
  return PostNotifier(
    ref.watch(liveCommunityServiceProvider),
    ref.watch(communityServiceProvider),
    ScoreService(),
  );
});

// ── Live members from Supabase ────────────────────────────────────────────────
final liveMembersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final db = Supabase.instance.client;
    // public_profiles, not user_profiles: migration 102 restricts the base table
    // to the owner and their coach, and member discovery needs nothing beyond a
    // display name. Demo fixtures are excluded via the explicit is_demo flag
    // (migration 110) — email is never selected or filtered on, and is not in
    // the view at all.
    final data = await db
        .from('public_profiles')
        .select('id, first_name, last_name, role, avatar_url, created_at')
        .eq('is_demo', false)
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(data as List);
  } catch (_) {
    return [];
  }
});

// Shim for screens that watch old provider
final postListProvider = Provider<List<CommunityPost>>((ref) {
  return ref.watch(postNotifierProvider).valueOrNull ?? const [];
});

// ── Live groups from Supabase ─────────────────────────────────────────────────
final liveGroupsProvider = FutureProvider<List<CommunityGroup>>((ref) async {
  final svc = ref.watch(liveCommunityServiceProvider);
  final live = await svc.getGroups();
  if (live.isEmpty) {
    return ref.watch(communityServiceProvider).getSampleGroups()
        .map((g) => CommunityGroup(
              id: g.id, name: g.name, description: g.description,
              emoji: g.emoji, memberCount: g.memberCount, isJoined: false))
        .toList();
  }
  return live;
});

class GroupNotifier extends StateNotifier<List<CommunityGroup>> {
  final LiveCommunityService _svc;
  GroupNotifier(super.state, this._svc);

  void initialize(List<CommunityGroup> groups) {
    state = groups;
  }

  Future<bool> joinGroup(String groupId) async {
    final ok = await _svc.joinGroup(groupId);
    if (ok) {
      state = state.map((g) {
        if (g.id != groupId) return g;
        return CommunityGroup(
          id: g.id, name: g.name, description: g.description,
          emoji: g.emoji, memberCount: g.memberCount + 1, isJoined: true,
        );
      }).toList();
    }
    return ok;
  }

  Future<bool> leaveGroup(String groupId) async {
    final ok = await _svc.leaveGroup(groupId);
    if (ok) {
      state = state.map((g) {
        if (g.id != groupId) return g;
        return CommunityGroup(
          id: g.id, name: g.name, description: g.description,
          emoji: g.emoji, memberCount: (g.memberCount - 1).clamp(0, 99999), isJoined: false,
        );
      }).toList();
    }
    return ok;
  }

  // Legacy toggle kept for compatibility with community_screen.dart
  void toggleJoin(String groupId) {
    final g = state.firstWhere((g) => g.id == groupId, orElse: () => state.first);
    if (g.isJoined) {
      leaveGroup(groupId);
    } else {
      joinGroup(groupId);
    }
  }
}

final groupNotifierProvider = StateNotifierProvider<GroupNotifier, List<CommunityGroup>>((ref) {
  final svc = ref.watch(liveCommunityServiceProvider);
  final sample = ref.watch(communityServiceProvider).getSampleGroups()
      .map((g) => CommunityGroup(
            id: g.id, name: g.name, description: g.description,
            emoji: g.emoji, memberCount: g.memberCount, isJoined: false))
      .toList();
  final notifier = GroupNotifier(sample, svc);
  ref.listen<AsyncValue<List<CommunityGroup>>>(
    liveGroupsProvider,
    (_, next) => next.whenData(notifier.initialize),
    fireImmediately: true,
  );
  return notifier;
});
