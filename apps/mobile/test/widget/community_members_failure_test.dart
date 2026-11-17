import 'dart:async';
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

// P0-FL-8 · a failed community member list is never an empty community.
//
// At 87cda02 `liveMembersProvider` caught every failure and answered `[]`, so
// the Members tab said "No members yet." for a read that never arrived; its
// own error branch was unreachable. The real provider runs here against a fake
// PostgREST (nothing leaves the process); the feed and groups are faked at the
// provider/service seam because they are not under test.
//
// Also: `PostNotifier.addPost` merged into `state.valueOrNull ?? []`, so a
// post written while the feed had failed turned the failure into a feed of one.

enum _Mode { serverError, noNetwork, throws, rows, empty, hang }

const _rows = [
  {
    'id': 'u1',
    'first_name': 'Ana',
    'last_name': 'Lee',
    'role': 'client',
    'avatar_url': null,
    'created_at': '2026-11-16T09:00:00Z',
  },
  {
    'id': 'u2',
    'first_name': 'Sam',
    'last_name': 'Cole',
    'role': 'coach',
    'avatar_url': null,
    'created_at': '2026-11-15T09:00:00Z',
  },
];

/// Fake PostgREST. `public_profiles` answers by [mode]; everything else `[]`.
class _Rest extends http.BaseClient {
  _Mode mode = _Mode.serverError;
  final requests = <Uri>[];
  Completer<void>? gate;
  Object thrown = const SocketException('unset');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/public_profiles')) {
      requests.add(request.url);
      switch (mode) {
        case _Mode.noNetwork:
          throw const SocketException('Connection refused');
        case _Mode.throws:
          throw thrown;
        case _Mode.serverError:
          return _json(request, 500, {
            'code': 'XX000',
            'message': 'SECRET_TABLE_X exploded',
            'details': null,
            'hint': null,
          });
        case _Mode.hang:
          await gate!.future;
          return _json(request, 200, _rows);
        case _Mode.rows:
          return _json(request, 200, _rows);
        case _Mode.empty:
          return _json(request, 200, const []);
      }
    }
    return _json(request, 200, const []);
  }

  http.StreamedResponse _json(http.BaseRequest r, int status, Object body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        request: r,
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

/// Feed service: the feed read and the post write, without the network.
class _Feed extends LiveCommunityService {
  bool fails = false;
  int reads = 0;
  final written = <String>[];
  @override
  Future<List<CommunityPost>> getPosts({int limit = 30}) async {
    reads++;
    if (fails) throw Exception('feed read failed');
    return written.map(_post).toList();
  }

  @override
  Future<CommunityPost> createPost(String content,
      {String postType = 'general', List<String> imageUrls = const []}) async {
    written.add(content);
    return _post(content);
  }
}

CommunityPost _post(String content) => CommunityPost(
      id: 'p-$content',
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

final _rest = _Rest();

Widget _screen() => ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        liveCommunityServiceProvider.overrideWithValue(_Feed()),
        liveGroupsProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: CommunityScreen()),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 2)); // entrance animations
}

Future<void> _openMembers(WidgetTester tester) async {
  await tester.pumpWidget(_screen());
  await _settle(tester);
  await tester.tap(find.text('Members'));
  await _settle(tester);
}

const _other = 'Try again in a moment. If it keeps happening, contact support.';
const _net = 'Check your connection and try again.';

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _rest,
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() {
    _rest
      ..mode = _Mode.serverError
      ..requests.clear()
      ..gate = null
      ..thrown = const SocketException('unset');
  });

  group('liveMembersProvider', () {
    test('a failed read is an error, not an empty list', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(liveMembersProvider, (_, __) {});
      await expectLater(c.read(liveMembersProvider.future),
          throwsA(isA<PostgrestException>()));
      expect(c.read(liveMembersProvider).hasError, isTrue);
    });

    test('positive control: the read is unchanged and rows arrive', () async {
      _rest.mode = _Mode.rows;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final members = await c.read(liveMembersProvider.future);
      expect(members.map((m) => m['first_name']), ['Ana', 'Sam']);
      final q = _rest.requests.single.queryParameters;
      expect(q['select'], 'id,first_name,last_name,role,avatar_url,created_at');
      expect(q['is_demo'], 'eq.false');
      expect(q['order'], 'created_at.desc.nullslast');
      expect(q['limit'], '100');
    });
  });

  testWidgets(
      'a failed members read says so, never "No members yet.", is '
      'recorded once, and Try again is busy while it re-reads', (tester) async {
    final reported = <AppFailure>[];
    setFailureSink(reported.add);
    addTearDown(resetFailureSink);
    final semantics = tester.ensureSemantics();

    await _openMembers(tester);

    expect(find.text('No members yet.'), findsNothing,
        reason: 'a failure is not an empty community');
    expect(find.text("Couldn't load members"), findsOneWidget);
    expect(find.text(_other), findsOneWidget,
        reason: 'a server answer is not a connection problem');
    expect(find.text(_net), findsNothing);
    expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);

    // Re-showing the same failure is not a second record.
    await tester.tap(find.text('Groups'));
    await _settle(tester);
    await tester.tap(find.text('Members'));
    await _settle(tester);
    expect(reported.map((f) => f.origin), ['CommunityScreen.members']);
    expect(reported.single.error, isA<PostgrestException>());

    // Try again: busy while the read is in flight, then the arrived members.
    _rest
      ..mode = _Mode.hang
      ..gate = Completer<void>();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_rest.requests.length, 2, reason: 'Try again re-reads');
    final button = tester.widget<ButtonStyleButton>(find.ancestor(
        of: find.text('Try again'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
    expect(button.onPressed, isNull, reason: 'busy: no second tap');
    // The button merges its children, so the label reads "Retrying…Try again".
    expect(find.bySemanticsLabel(RegExp('Retrying')), findsOneWidget);
    expect(find.text("Couldn't load members"), findsOneWidget,
        reason: 'the failure stays on screen while the re-read is in flight');

    _rest.gate!.complete();
    await _settle(tester);
    expect(find.text("Couldn't load members"), findsNothing);
    expect(find.text('Ana Lee'), findsOneWidget);
    expect(find.text('Sam Cole'), findsOneWidget);
    expect(reported.length, 1, reason: 'a successful re-read records nothing');
    semantics.dispose();
  });

  testWidgets('a second failed read after Try again is recorded once more',
      (tester) async {
    final reported = <AppFailure>[];
    setFailureSink(reported.add);
    addTearDown(resetFailureSink);
    await _openMembers(tester);
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(_rest.requests.length, 2);
    expect(find.text("Couldn't load members"), findsOneWidget);
    expect(reported.length, 2);
  });

  testWidgets('no connection says check your connection', (tester) async {
    _rest.mode = _Mode.noNetwork;
    final reported = <AppFailure>[];
    setFailureSink(reported.add);
    addTearDown(resetFailureSink);
    await _openMembers(tester);
    // postgrest-dart retries a GET that threw, with a back-off, before the
    // failure settles.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
    expect(_rest.requests.length, greaterThan(1),
        reason: 'the client retried before giving up');
    expect(find.text("Couldn't load members"), findsOneWidget);
    expect(find.text(_net), findsOneWidget);
    expect(find.text(_other), findsNothing);
    expect(find.text('No members yet.'), findsNothing);
    expect(reported.single.origin, 'CommunityScreen.members');
  });

  // P0-FL-8 M2 · on a device package:http's IOClient wraps a dropped
  // connection as http.ClientException, not SocketException; a slow network
  // surfaces as TimeoutException and a dropped auth refresh as
  // AuthRetryableFetchException. Each is a connection problem, not a server
  // answer, and must get the connection copy.
  final networkErrors = <String, Object>{
    'http.ClientException': http.ClientException(
        'Connection closed before full header was received'),
    'TimeoutException': TimeoutException('read timed out'),
    'AuthRetryableFetchException': AuthRetryableFetchException(),
  };
  for (final e in networkErrors.entries) {
    testWidgets('M2 a members read that fails with ${e.key} says check your '
        'connection', (tester) async {
      _rest
        ..mode = _Mode.throws
        ..thrown = e.value;
      await _openMembers(tester);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      expect(find.text("Couldn't load members"), findsOneWidget);
      expect(find.text(_net), findsOneWidget,
          reason: '${e.key} is a connection failure');
      expect(find.text(_other), findsNothing);
      expect(find.text('No members yet.'), findsNothing);
    });
  }

  testWidgets(
      'the members failure scrolls at 2x text, 320 wide, and is '
      'announced', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
        size: Size(320, 900),
        textScaler: TextScaler.linear(2.0),
      ),
      child: _screen(),
    ));
    await _settle(tester);
    await tester.tap(find.text('Members'));
    await _settle(tester);

    expect(find.text("Couldn't load members"), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    final live = find.ancestor(
      of: find.text("Couldn't load members"),
      matching: find.byWidgetPredicate((w) =>
          w is Semantics && w.properties.liveRegion == true && w.container),
    );
    expect(live, findsOneWidget);
    expect(
        find.ancestor(of: live, matching: find.byType(SingleChildScrollView)),
        findsWidgets);
    semantics.dispose();
  });

  testWidgets(
      'positive control: an empty community still says "No members '
      'yet."', (tester) async {
    _rest.mode = _Mode.empty;
    await _openMembers(tester);
    expect(find.text('No members yet.'), findsOneWidget);
    expect(find.textContaining("Couldn't load"), findsNothing);
  });

  testWidgets('positive control: members are listed as before', (tester) async {
    _rest.mode = _Mode.rows;
    await _openMembers(tester);
    expect(find.text('Ana Lee'), findsOneWidget);
    expect(find.text('Sam Cole'), findsOneWidget);
    expect(find.text('COACH'), findsOneWidget);
    expect(find.textContaining("Couldn't load"), findsNothing);
  });

  group('PostNotifier.addPost', () {
    ProviderContainer container(_Feed feed) {
      final c = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(null),
        liveCommunityServiceProvider.overrideWithValue(feed),
      ]);
      c.listen(postNotifierProvider, (_, __) {});
      return c;
    }

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test(
        'a post written while the feed had failed keeps the failure, not a '
        'feed of one', () async {
      final feed = _Feed()..fails = true;
      final c = container(feed);
      addTearDown(c.dispose);
      await settle();
      expect(c.read(postNotifierProvider).hasError, isTrue);

      await c.read(postNotifierProvider.notifier).addPost('Leg day');
      expect(feed.written, ['Leg day'],
          reason: 'the write itself is unchanged');
      expect(feed.reads, 2, reason: 'the feed is read again');
      final s = c.read(postNotifierProvider);
      expect(s.hasError, isTrue);
      expect(s.hasValue, isFalse, reason: 'a failure is not a feed of one');
    });

    test('the feed read again after a failure shows the new post', () async {
      final feed = _Feed()..fails = true;
      final c = container(feed);
      addTearDown(c.dispose);
      await settle();
      feed.fails = false;
      await c.read(postNotifierProvider.notifier).addPost('Leg day');
      expect(c.read(postNotifierProvider).value!.map((p) => p.content),
          ['Leg day']);
    });

    test(
        'positive control: a loaded feed gets the new post on top, with no '
        'extra read', () async {
      final feed = _Feed()..written.add('Earlier');
      final c = container(feed);
      addTearDown(c.dispose);
      await settle();
      await c.read(postNotifierProvider.notifier).addPost('Leg day');
      expect(feed.reads, 1);
      expect(c.read(postNotifierProvider).value!.map((p) => p.content),
          ['Leg day', 'Earlier']);
    });
  });
}
