import 'dart:async' show unawaited;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
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
  ref.watch(currentUserProvider.select((u) => u?.id));
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

  /// P0-FL-59e · whose feed this is: the member signed in when it was made (a
  /// new one is made for each member).
  final String? _owner = _signedIn;

  static String? get _signedIn =>
      Supabase.instance.client.auth.currentUser?.id;

  bool get _live => mounted && _signedIn == _owner;

  /// Before a write: the post, comment or reaction was made in THIS member's
  /// feed, so nothing is sent as anyone else. Throws, so it is never taken for
  /// saved; the feed shown goes away.
  void _requireOwner(String what) {
    if (_signedIn == _owner) return;
    final error = StateError('$what: the signed-in account changed');
    reportError('PostNotifier.identity', error);
    if (mounted) state = const AsyncValue.loading();
    throw error;
  }

  Future<void> _load() async {
    if (!_live) return; // replaced, or not this member's to read any more
    state = const AsyncValue.loading();
    try {
      final live = await _svc.getPosts();
      if (_live) state = AsyncValue.data(live);
    } catch (e, st) {
      if (_live) state = AsyncValue.error(e, st);
    }
  }

  Future<void> reload() => _load();

  /// Kept for callers that only ever meant the heart.
  Future<void> toggleLike(String postId) => toggleReaction(postId, ReactionType.like);

  /// FIT-065/066. The provider used to hardcode `'like'`, so four of the five
  /// reaction types could be READ by this app and never written by it.
  Future<void> toggleReaction(String postId, ReactionType type) async {
    // Mine is the row with my user id: what getPosts loads, and what the
    // write above stores. A placeholder id matched nothing that was loaded, so
    // taking back a reaction left before the feed loaded counted it again.
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return; // the service writes nothing signed out
    _requireOwner('reaction');
    await _svc.toggleReaction(postId, reactionWire(type));
    if (!_live) return;
    final posts = state.valueOrNull ?? [];
    state = AsyncValue.data(posts.map((p) {
      if (p.id != postId) return p;
      // Same one again takes it back, a different one switches.
      final mine = p.reactions.where((r) => r.userId == me).toList();
      final had = mine.isEmpty ? null : mine.first.type;
      final others = p.reactions.where((r) => r.userId != me).toList();
      final newReactions = had == type
          ? others
          : [...others, PostReaction(userId: me, type: type)];
      final newIsLiked =
          newReactions.any((r) => r.userId == me && r.type == ReactionType.like);
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
    _requireOwner('comment');
    await _svc.addComment(postId, content);
    await _load();
  }

  Future<void> addPost(String content, {String postType = 'general'}) async {
    _requireOwner('post');
    final post = await _svc.createPost(content, postType: postType);
    // The post is this member's, and so are its points; a feed replaced by
    // another member's is left alone.
    if (_signedIn != _owner) {
      reportError('PostNotifier.identity',
          StateError('post points: the signed-in account changed'));
      return;
    }
    unawaited(ScoreEngine(forUid: _owner).communityPost()); // +5, once/day
    if (!mounted) {
      // Replaced meanwhile: the new feed reads the post itself.
    } else if (state.hasError && !state.hasValue) {
      // P0-FL-8 · the feed never arrived: `valueOrNull ?? []` made that failure
      // a feed holding only the new post. Read it again instead — the post is
      // in it, or the failure is still shown as one.
      await _load();
    } else {
      state = AsyncValue.data([post, ...(state.valueOrNull ?? [])]);
    }
    // Award community points for posting. Best-effort: the post is saved, and
    // a failed award must not read as a post that was not.
    try {
      await _score.addCommunityPoints();
    } catch (e, st) {
      reportError('PostNotifier.addPost.points', e, st);
    }
  }
}

final postNotifierProvider = StateNotifierProvider<PostNotifier, AsyncValue<List<CommunityPost>>>((ref) {
  // The feed as one account sees it — which posts that account liked
  // (`isLiked`), its own new posts — so a new one for each account. The
  // QAX-SES-01 guard sees user reads in a provider's own body, not in the
  // notifier it constructs, which is how this one was missed.
  // By the id alone: a token refresh does not throw the feed away.
  final uid = ref.watch(currentUserProvider.select((u) => u?.id));
  return PostNotifier(
    ref.watch(liveCommunityServiceProvider),
    ref.watch(communityServiceProvider),
    ScoreService(forUid: uid),
  );
});

// ── Live members from Supabase ────────────────────────────────────────────────
// P0-FL-8 · a failed read PROPAGATES. It was caught and answered `[]`, so the
// Members tab said "No members yet." for a read that never arrived and its own
// error state could not be reached.
final liveMembersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
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
});

// ── Live groups from Supabase ─────────────────────────────────────────────────
final liveGroupsProvider = FutureProvider<List<CommunityGroup>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final svc = ref.watch(liveCommunityServiceProvider);
  // No groups is no groups — never the sample ones (see getGroups).
  return svc.getGroups();
});

/// P0-FL-10 · the groups as one of three states — loading, failed, loaded.
/// It was a bare `List` that started `const []` and took only the DATA of
/// [liveGroupsProvider] (`whenData`), so a failed read stayed `[]`: Community's
/// Groups tab showed no groups and Activity said "No communities joined yet"
/// for a read that never arrived.
class GroupNotifier extends StateNotifier<AsyncValue<List<CommunityGroup>>> {
  final LiveCommunityService _svc;

  /// Re-reads the groups. Called when a leave removed no row: the list on
  /// screen is stale (already left elsewhere), so it corrects itself instead
  /// of offering a Leave that can never succeed.
  final void Function() _reread;

  GroupNotifier(this._svc, {void Function()? reread})
      : _reread = reread ?? _noop,
        super(const AsyncValue.loading());

  static void _noop() {}

  /// Follows [liveGroupsProvider]: its loading, its failure and its groups.
  void sync(AsyncValue<List<CommunityGroup>> next) {
    state = next;
  }

  /// Marks [groupId] joined/left in the loaded list. A failed or loading list
  /// is left as it is — a join never turns a failure into a list.
  void _mark(String groupId, {required bool joined}) {
    state = state.whenData((groups) => groups.map((g) {
          if (g.id != groupId) return g;
          return CommunityGroup(
            id: g.id, name: g.name, description: g.description, emoji: g.emoji,
            memberCount: joined
                ? g.memberCount + 1
                : (g.memberCount - 1).clamp(0, 99999),
            isJoined: joined,
          );
        }).toList());
  }

  Future<bool> joinGroup(String groupId) async {
    final ok = await _svc.joinGroup(groupId);
    if (ok) _mark(groupId, joined: true);
    return ok;
  }

  /// True only when a membership row was removed. A leave that removed none
  /// is still reported as a failure, and the groups are re-read so the list
  /// stops showing a membership that is not there (P0-FL-10 U2).
  Future<bool> leaveGroup(String groupId) async {
    final outcome = await _svc.leaveGroupOutcome(groupId);
    switch (outcome) {
      case GroupLeave.left:
        _mark(groupId, joined: false);
        return true;
      case GroupLeave.noRow:
        _reread();
        return false;
      case GroupLeave.failed:
        return false;
    }
  }

  /// Groups whose join/leave is on the wire right now.
  final _inFlight = <String>{};

  /// Joins [group] if it is not joined, leaves it if it is. True only when the
  /// service reports the write taken; on false the list is unchanged and the
  /// caller says so (P0-FL-10: the result was dropped, so a failed join or
  /// leave was a silent dead tap).
  ///
  /// Null when the tap was ignored because this group's join/leave is still in
  /// flight (P0-FL-10 L3: a quick double-tap on Join sent two inserts). The
  /// first tap's result is the one the caller reports.
  Future<bool?> toggleJoin(CommunityGroup group) async {
    if (!_inFlight.add(group.id)) return null;
    try {
      return group.isJoined
          ? await leaveGroup(group.id)
          : await joinGroup(group.id);
    } finally {
      _inFlight.remove(group.id);
    }
  }
}

final groupNotifierProvider = StateNotifierProvider<GroupNotifier,
    AsyncValue<List<CommunityGroup>>>((ref) {
  final svc = ref.watch(liveCommunityServiceProvider);
  // Starts loading — nothing is claimed until the real groups arrive (it
  // started with the five sample groups, then with a `[]` no failure left).
  final notifier =
      GroupNotifier(svc, reread: () => ref.invalidate(liveGroupsProvider));
  ref.listen<AsyncValue<List<CommunityGroup>>>(
    liveGroupsProvider,
    (previous, next) {
      notifier.sync(next);
      // P0-FL-10 · each failed groups read is recorded once, here, when it
      // settles into an error — not once per screen that shows it (Community
      // and Activity both do) and not on every rebuild.
      if (next.hasError &&
          !next.isLoading &&
          (previous == null || previous.isLoading || !previous.hasError)) {
        reportError('community.groups', next.error!, next.stackTrace);
      }
    },
    fireImmediately: true,
  );
  return notifier;
});
