import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/community/data/live_community_service.dart';
import 'package:circle_fitness/features/community/data/models/post_model.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/community/presentation/community_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-5 · B · the community feed never shows the raw exception.
//
// At 918c8dc a failed feed read printed `e.toString()` under "Could not load
// posts" — e.g. a PostgREST message naming a table and its RLS policy. The
// feed service is faked; Supabase is initialised signed out only because the
// real services resolve the client when constructed. Nothing is sent.

const _later = 'Try again in a moment. If it keeps happening, contact support.';
const _connection = 'Check your connection and try again.';

const _secret =
    'PostgrestException(message: new row violates row-level security policy '
    'SECRET_TABLE_X, code: 42501)';

class _NoNetwork extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('[]')),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
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

/// The feed read, which fails until told otherwise.
class _Feed extends LiveCommunityService {
  bool fails = true;
  Object? error; // what a failing read throws; the secret-bearing one by default
  int calls = 0;
  List<CommunityPost> posts = const [];
  @override
  Future<List<CommunityPost>> getPosts({int limit = 30}) async {
    calls++;
    if (fails) throw error ?? Exception(_secret);
    return posts;
  }
}

CommunityPost _post(String content) => CommunityPost(
      id: 'p1',
      userId: 'u1',
      userName: 'Ana Lee',
      userRole: 'client',
      content: content,
      type: PostType.text,
      imageUrls: const [],
      reactions: const [],
      comments: const [],
      createdAt: DateTime.utc(2026, 11, 16, 9),
    );

Widget _screen(_Feed feed) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        liveCommunityServiceProvider.overrideWithValue(feed),
        liveGroupsProvider.overrideWith((ref) async => const []),
        liveMembersProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: CommunityScreen()),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 2)); // entrance animations
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _NoNetwork(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  testWidgets(
      'a failed feed read says so in plain words, with no exception '
      'text, and is recorded once', (tester) async {
    final reported = <AppFailure>[];
    setFailureSink(reported.add);
    addTearDown(resetFailureSink);
    final feed = _Feed();

    await tester.pumpWidget(_screen(feed));
    await _settle(tester);

    // The defect first: the raw exception text was on screen.
    expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
    expect(find.textContaining('row-level security'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.text("Couldn't load posts"), findsOneWidget);
    // F1: not a network failure, so no connection hint.
    expect(find.text(_later), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('No posts yet. Be the first to share!'), findsNothing,
        reason: 'a failure is not an empty feed');

    // A rebuild that re-shows the same failure is not a second record.
    await tester.tap(find.text('Groups'));
    await _settle(tester);
    await tester.tap(find.text('Feed'));
    await _settle(tester);

    expect(reported.map((f) => f.origin), ['CommunityScreen.posts']);
    expect(reported.single.error.toString(), contains('SECRET_TABLE_X'),
        reason: 'the raw error is recorded, not shown');

    // Try again re-reads; a second failure is recorded once more and still not shown.
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(feed.calls, 2);
    expect(find.text("Couldn't load posts"), findsOneWidget);
    expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
    expect(reported.length, 2);
  });

  testWidgets('Try again then shows the arrived posts', (tester) async {
    final feed = _Feed()..posts = [_post('Leg day done')];
    await tester.pumpWidget(_screen(feed));
    await _settle(tester);
    expect(find.text("Couldn't load posts"), findsOneWidget);

    feed.fails = false;
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(find.text("Couldn't load posts"), findsNothing);
    expect(find.textContaining('Leg day done'), findsOneWidget);
  });

  // Review U3: the failure block scrolls rather than overflowing at large
  // text on a narrow phone, and is a live region so it is announced.
  testWidgets('U3 the feed failure does not overflow at 2x text, 320 wide, '
      'and is announced', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
        size: Size(320, 900),
        textScaler: TextScaler.linear(2.0),
      ),
      child: _screen(_Feed()),
    ));
    await _settle(tester);

    expect(find.text("Couldn't load posts"), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    final live = find.ancestor(
      of: find.text("Couldn't load posts"),
      matching: find.byWidgetPredicate((w) =>
          w is Semantics &&
          w.properties.liveRegion == true &&
          w.container),
    );
    expect(live, findsOneWidget);
    expect(
      find.ancestor(of: live, matching: find.byType(SingleChildScrollView)),
      findsWidgets,
    );
    final helper = tester.widget<Text>(find.text(_later));
    expect(helper.style?.fontSize, 13);
    semantics.dispose();
  });

  testWidgets('arrived data is unchanged: the empty copy', (tester) async {
    final feed = _Feed()..fails = false;
    await tester.pumpWidget(_screen(feed));
    await _settle(tester);
    expect(find.text('No posts yet. Be the first to share!'), findsOneWidget);
    expect(find.textContaining("Couldn't load"), findsNothing);
  });
  // F1 · the feed follows the Members rule: the connection hint is only for a
  // request that never reached the server. A server answer (PostgREST error)
  // is not a connection problem, and the old copy said it was.
  testWidgets('F1 a server error does not blame the connection', (tester) async {
    final feed = _Feed()
      ..error = const PostgrestException(
          message: 'permission denied for table SECRET_TABLE_X', code: '42501');
    await tester.pumpWidget(_screen(feed));
    await _settle(tester);

    expect(find.text("Couldn't load posts"), findsOneWidget);
    expect(find.text(_later), findsOneWidget);
    expect(find.text(_connection), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
  });

  testWidgets('F1 a network failure keeps the connection hint', (tester) async {
    final feed = _Feed()..error = const SocketException('Failed host lookup');
    await tester.pumpWidget(_screen(feed));
    await _settle(tester);

    expect(find.text("Couldn't load posts"), findsOneWidget);
    expect(find.text(_connection), findsOneWidget);
    expect(find.text(_later), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}
