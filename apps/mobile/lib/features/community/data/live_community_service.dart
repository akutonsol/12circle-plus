import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/post_model.dart';
import '../domain/post_type_choice.dart';
import '../domain/reaction_choice.dart';
import '../../notifications/data/notification_service.dart';

class LiveCommunityService {
  final _db = Supabase.instance.client;

  Future<List<CommunityPost>> getPosts({int limit = 30}) async {
    final uid = _db.auth.currentUser?.id;
    final data = await _db
        .from('community_posts')
        .select('*, public_profiles!user_id(id, first_name, last_name, role, avatar_url)')
        .order('created_at', ascending: false)
        .limit(limit);

    if ((data as List).isEmpty) return [];

    final postIds = data.map((p) => p['id'] as String).toList();

    final reactions = List<Map<String, dynamic>>.from(
      await _db.from('post_reactions').select().inFilter('post_id', postIds));

    final comments = List<Map<String, dynamic>>.from(
      await _db.from('post_comments')
          .select('*, public_profiles!user_id(first_name, last_name)')
          .inFilter('post_id', postIds)
          .order('created_at'));

    return data.map<CommunityPost>((p) {
      final profile = p['public_profiles'] as Map<String, dynamic>? ?? {};
      final fn = profile['first_name'] as String? ?? '';
      final ln = profile['last_name'] as String? ?? '';
      final postId = p['id'] as String;
      final postReactions = reactions.where((r) => r['post_id'] == postId).toList();
      final postComments = comments.where((c) => c['post_id'] == postId).toList();

      return CommunityPost(
        id: postId,
        userId: p['user_id'] as String,
        userName: '$fn $ln'.trim().isEmpty ? 'Member' : '$fn $ln'.trim(),
        userRole: profile['role'] as String? ?? 'client',
        content: p['content'] as String,
        type: _parseType(p['post_type'] as String? ?? 'general'),
        imageUrls: List<String>.from(p['image_urls'] as List? ?? []),
        isLiked: postReactions.any((r) => r['user_id'] == uid && r['reaction_type'] == 'like'),
        reactions: postReactions.map((r) => PostReaction(
          userId: r['user_id'] as String,
          type: _parseReaction(r['reaction_type'] as String? ?? 'like'),
        )).toList(),
        comments: postComments.map((c) {
          final cp = c['public_profiles'] as Map<String, dynamic>? ?? {};
          return PostComment(
            id: c['id'] as String,
            userId: c['user_id'] as String,
            userName: '${cp['first_name'] ?? ''} ${cp['last_name'] ?? ''}'.trim(),
            content: c['content'] as String,
            createdAt: DateTime.parse(c['created_at'] as String),
            likes: 0,
            isLiked: false,
          );
        }).toList(),
        createdAt: DateTime.parse(p['created_at'] as String),
      );
    }).toList();
  }

  Future<CommunityPost> createPost(String content, {String postType = 'general', List<String> imageUrls = const []}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    final row = await _db.from('community_posts').insert({
      'user_id': uid,
      'content': content,
      'post_type': postType,
      'image_urls': imageUrls,
    }).select('*, public_profiles!user_id(id, first_name, last_name, role)').single();
    final profile = row['public_profiles'] as Map<String, dynamic>? ?? {};
    return CommunityPost(
      id: row['id'] as String,
      userId: uid,
      userName: '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim(),
      userRole: profile['role'] as String? ?? 'client',
      content: content,
      type: _parseType(postType),
      imageUrls: imageUrls,
      isLiked: false,
      reactions: [],
      comments: [],
      createdAt: DateTime.now(),
    );
  }

  Future<void> toggleReaction(String postId, String reactionType) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    final existing = await _db
        .from('post_reactions')
        .select()
        .eq('post_id', postId)
        .eq('user_id', uid)
        .maybeSingle();
    switch (reactionWriteFor(
      existingType: existing?['reaction_type'] as String?,
      chosen: parseReactionType(reactionType),
    )) {
      case ReactionWrite.insert:
        await _db.from('post_reactions').insert({
          'post_id': postId,
          'user_id': uid,
          'reaction_type': reactionType,
        });
      case ReactionWrite.remove:
        await _db.from('post_reactions').delete().eq('id', existing!['id']);
      case ReactionWrite.change:
        // This used to fall into the delete branch, so switching from Like to
        // Fire removed the Like and left nothing — and UNIQUE(post_id,
        // user_id) means an insert could not have replaced it either.
        await _db.from('post_reactions')
            .update({'reaction_type': reactionType})
            .eq('id', existing!['id']);
    }
  }

  Future<void> addComment(String postId, String content) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _db.from('post_comments').insert({
      'post_id': postId,
      'user_id': uid,
      'content': content,
    });
    // Notify the post author of the new comment (COM-002).
    try {
      final post = await _db
          .from('community_posts')
          .select('user_id')
          .eq('id', postId)
          .maybeSingle();
      final authorId = post?['user_id'] as String?;
      if (authorId != null && authorId != uid) {
        await NotificationService().notifyUser(
          recipientId: authorId,
          type: 'community',
          title: 'New Comment',
          body: 'Someone commented on your post.',
        );
      }
    } catch (_) {
      // ignore notification failures
    }
  }

  Future<List<CommunityGroup>> getGroups() async {
    try {
      final uid = _db.auth.currentUser?.id;
      final data = await _db
          .from('community_groups')
          .select()
          .order('name');
      final members = List<Map<String, dynamic>>.from(
          await _db.from('community_group_members').select('group_id, user_id'));
      final myIds = uid == null
          ? <String>{}
          : members.where((m) => m['user_id'] == uid).map((m) => m['group_id'] as String).toSet();
      return (data as List).map<CommunityGroup>((g) {
        final gid = g['id'] as String;
        final count = members.where((m) => m['group_id'] == gid).length;
        return CommunityGroup(
          id: gid,
          name: g['name'] as String,
          description: g['description'] as String? ?? '',
          emoji: g['emoji'] as String? ?? '💪',
          memberCount: count,
          isJoined: myIds.contains(gid),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> joinGroup(String groupId) async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return false;
      try {
        await _db.from('community_group_members')
            .insert({'group_id': groupId, 'user_id': uid});
      } catch (e) {
        final s = e.toString();
        if (s.contains('23505') || s.contains('duplicate') || s.contains('unique')) {
          return true; // already joined
        }
        rethrow;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> leaveGroup(String groupId) async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return false;
      await _db
          .from('community_group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Was a three-arm switch that sent `photo` and `workout` to `text`, so two
  // of the five enum values could not survive a write-and-read. One mapping,
  // shared with the UI — see `post_type_choice.dart`.
  PostType _parseType(String t) => parsePostType(t);

  ReactionType _parseReaction(String r) => switch (r) {
    'fire' => ReactionType.fire,
    'love' => ReactionType.love,
    'clap' => ReactionType.clap,
    'strong' => ReactionType.strong,
    _ => ReactionType.like,
  };
}
