import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/community/data/live_community_service.dart';
import 'package:circle_fitness/features/community/data/models/post_model.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// /community's feed is `postNotifierProvider`: a StateNotifier, kept for the
// session, that never watched who is signed in. What it holds is per account
// — `isLiked` is worked out against the signed-in user in `getPosts` — so
// after a sign-out without a page reload (a sign-out in another tab, the
// admin/vendor/reset-password sign-outs, any native build) the next account
// was shown the previous one's hearts, and its taps toggled against them.
//
// The QAX-SES-01 guard did not see it: it looks for user reads in a provider's
// own body, and this one hands them to the notifier it constructs.

class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
          request: request, headers: {'content-type': 'application/json'});
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

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    );

/// One post that account A has liked, as `getPosts` answers for whoever is
/// signed in.
class _Feed extends LiveCommunityService {
  String? signedIn;

  @override
  Future<List<CommunityPost>> getPosts({int limit = 30}) async => [
        CommunityPost(
          id: 'p1',
          userId: 'someone-else',
          userName: 'Sam Rae',
          userRole: 'client',
          content: 'Hit a new deadlift PR today',
          type: PostType.text,
          imageUrls: const [],
          reactions: [PostReaction(userId: 'account-a', type: ReactionType.like)],
          comments: const [],
          createdAt: DateTime.utc(2026, 11, 12),
          isLiked: signedIn == 'account-a',
        ),
      ];
}

final _signedIn = StateProvider<User?>((ref) => null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _EmptyClient(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  late _Feed feed;
  late ProviderContainer app;

  setUp(() {
    feed = _Feed();
    app = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
      liveCommunityServiceProvider.overrideWithValue(feed),
    ]);
    addTearDown(app.dispose);
  });

  /// /community is open: the screen watches the feed.
  Future<void> openCommunity() async {
    app.listen(postNotifierProvider, (_, __) {});
    await pumpEventQueue();
  }

  Future<void> signIn(String id) async {
    feed.signedIn = id;
    app.read(_signedIn.notifier).state = _user(id);
    await pumpEventQueue();
  }

  bool liked() => app.read(postNotifierProvider).value!.single.isLiked;

  test('the next account is not shown the previous account\'s likes', () async {
    await signIn('account-a');
    await openCommunity();
    expect(liked(), isTrue, reason: 'guard the premise: A liked the post');

    await signIn('account-b');
    expect(liked(), isFalse,
        reason: "THE defect: B was shown A's heart from the kept feed");
  });

  test('the same account keeps its own likes (control)', () async {
    await signIn('account-a');
    await openCommunity();
    await signIn('account-a');
    expect(liked(), isTrue);
  });
}
