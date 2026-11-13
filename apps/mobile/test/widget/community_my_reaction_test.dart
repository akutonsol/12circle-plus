import 'dart:convert';

import 'package:circle_fitness/features/community/data/models/post_model.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/community/presentation/widgets/reaction_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// /community: "my reaction" was looked for under the id 'me'.
//
// The feed loads each reaction with the real `user_id` of whoever left it
// (`LiveCommunityService.getPosts`). After a tap, `PostNotifier.toggleReaction`
// rebuilt the post looking for MY reaction as `userId == 'me'`, which matched
// nothing that was loaded. So, for a reaction I left before the feed loaded:
//
//   * tapping the heart again took the Like away on the server, and the
//     screen added a second one — "Liked", with the count up by one;
//   * switching Like → Fire changed the row on the server, and the screen
//     showed both.
//
// And the picker was told `uid: 'me'`, so after any load it never marked the
// reaction I had left as mine.

const _uid = '00000000-0000-4000-8000-0000000ce4c7';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// The token is read, never verified client-side.
String _jwt() {
  final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': _uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
      'not-verified-client-side';
}

class _SeededSession extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => jsonEncode({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 315360000,
        'refresh_token': 'test-refresh',
        'user': {
          'id': _uid,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
  @override
  Future<bool> hasAccessToken() async => true;
  @override
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async {}
}

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

/// One post by someone else, and `post_reactions` as the server keeps it.
class _Server extends http.BaseClient {
  final reactions = <Map<String, Object?>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final q = request.url.queryParameters;
    if (path.endsWith('/community_posts')) {
      return _json([
        {
          'id': 'p1',
          'user_id': 'someone-else',
          'content': 'Hit a new deadlift PR today',
          'post_type': 'general',
          'image_urls': [],
          'created_at': '2026-11-12T09:00:00Z',
          'public_profiles': {'first_name': 'Sam', 'last_name': 'Rae', 'role': 'client'},
        },
      ], 200, request);
    }
    if (path.endsWith('/post_comments')) return _json([], 200, request);
    if (path.endsWith('/post_reactions')) {
      switch (request.method) {
        case 'GET':
          final single =
              request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
          final mine = q['user_id'] == 'eq.$_uid';
          final rows = mine
              ? reactions.where((r) => r['user_id'] == _uid).toList()
              : reactions;
          if (single) return _json(rows.isEmpty ? null : rows.first, 200, request);
          return _json(rows, 200, request);
        case 'DELETE':
          reactions.removeWhere((r) => 'eq.${r['id']}' == q['id']);
          return _json(null, 204, request);
        case 'PATCH':
          final body = jsonDecode((request as http.Request).body) as Map;
          for (final r in reactions) {
            if ('eq.${r['id']}' == q['id']) r['reaction_type'] = body['reaction_type'];
          }
          return _json(null, 204, request);
        case 'POST':
          final body = jsonDecode((request as http.Request).body) as Map;
          reactions.add({...body.cast<String, Object?>(), 'id': 'r${reactions.length + 9}'});
          return _json(null, 201, request);
      }
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  setUp(() => server.reactions.clear());

  /// The feed as loaded, with whatever reactions are on the server.
  Future<ProviderContainer> loadFeed() async {
    final app = ProviderContainer();
    addTearDown(app.dispose);
    app.listen(postNotifierProvider, (_, __) {});
    await pumpEventQueue();
    expect(app.read(postNotifierProvider).valueOrNull, hasLength(1),
        reason: 'guard the premise: the feed loaded');
    return app;
  }

  CommunityPost post(ProviderContainer app) =>
      app.read(postNotifierProvider).value!.single;

  int count(CommunityPost p, ReactionType t) =>
      p.reactions.where((r) => r.type == t).length;

  test('taking back a Like left before the feed loaded takes it away',
      () async {
    server.reactions.add({'id': 'r1', 'post_id': 'p1', 'user_id': _uid, 'reaction_type': 'like'});
    final app = await loadFeed();
    expect(post(app).isLiked, isTrue);

    await app.read(postNotifierProvider.notifier).toggleLike('p1');

    expect(server.reactions, isEmpty, reason: 'the server removed the Like');
    expect(post(app).isLiked, isFalse,
        reason: 'THE defect: the screen showed "Liked" with a second Like');
    expect(count(post(app), ReactionType.like), 0);
  });

  test('switching Like to Fire shows one reaction, the Fire', () async {
    server.reactions.add({'id': 'r1', 'post_id': 'p1', 'user_id': _uid, 'reaction_type': 'like'});
    final app = await loadFeed();

    await app.read(postNotifierProvider.notifier)
        .toggleReaction('p1', ReactionType.fire);

    expect(server.reactions.single['reaction_type'], 'fire');
    expect(post(app).reactions.map((r) => r.type), [ReactionType.fire],
        reason: 'THE defect: the loaded Like stayed beside the new Fire');
    expect(post(app).isLiked, isFalse);
  });

  test('a first reaction is counted once (control)', () async {
    final app = await loadFeed();
    await app.read(postNotifierProvider.notifier).toggleLike('p1');

    expect(server.reactions, hasLength(1));
    expect(post(app).isLiked, isTrue);
    expect(count(post(app), ReactionType.like), 1);
  });

  testWidgets('the picker marks the reaction I left as mine', (tester) async {
    final p = CommunityPost(
      id: 'p1', userId: 'someone-else', userName: 'Sam Rae', userRole: 'client',
      content: 'Hit a new deadlift PR today', type: PostType.text,
      imageUrls: const [], comments: const [],
      reactions: [
        PostReaction(userId: _uid, type: ReactionType.love),
        PostReaction(userId: 'someone-else', type: ReactionType.fire),
      ],
      createdAt: DateTime.utc(2026, 11, 12), isLiked: false,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReactionBar(
          post: p, onLike: () {}, onReact: (_) {}, onComment: () {}, onShare: () {},
        ),
      ),
    ));

    bool selected(ReactionType t) => tester
        .widget<Semantics>(find
            .ancestor(
                of: find.byKey(ValueKey('reaction-${t.name}')),
                matching: find.byType(Semantics))
            .first)
        .properties
        .selected ==
        true;

    expect(selected(ReactionType.love), isTrue,
        reason: 'THE defect: told uid "me", it found none of mine');
    expect(selected(ReactionType.fire), isFalse,
        reason: "someone else's Fire is not mine");
  });
}
