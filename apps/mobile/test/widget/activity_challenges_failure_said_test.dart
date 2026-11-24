import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/activity/presentation/activity_screen.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/challenges/data/live_challenge_service.dart';
import 'package:circle_fitness/features/challenges/data/models/challenge_model.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/section_load_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-53b · Activity › Challenges.
//
// (a) At b7ec6ef a failed `liveChallengesProvider` read rendered the error arm
//     as "No active challenges / Check back soon" — a claim about what exists
//     that the app could not make. Now: the shared SectionLoadFailure with a
//     busy-aware retry; a genuine empty list still says "No active
//     challenges"; a failed REFRESH keeps the list this member was shown.
//     A failed join was swallowed unrecorded ("Unable to join").
// (d) "See All" was 13px text with no role, and "Enable" a 28px pill with no
//     role: both < 44px. Now >= 44px buttons named for the action and item,
//     no overflow at 1.0/1.3/2.0 text scale on 320–430dp, text never shrunk.
//
// The challenges read is faked at the `liveChallengesProvider` seam (the
// service's own read rethrows and records: live_challenge_service.dart);
// every other read talks to a fake PostgREST answering `[]`.

class _Rest extends http.BaseClient {
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

class _Reads {
  Object? error;
  Completer<void>? gate;
  List<Challenge> rows = const [];
  int count = 0;
}

class _Svc extends LiveChallengeService {
  Object? joinError;
  @override
  Future<void> joinChallenge(String challengeId) async {
    final e = joinError;
    if (e != null) throw e;
  }
}

Challenge _challenge(String id, String title, {bool joined = false}) => Challenge(
      id: id,
      title: title,
      description: '',
      type: ChallengeType.steps,
      status: ChallengeStatus.active,
      startDate: DateTime.now().subtract(const Duration(days: 1)),
      endDate: DateTime.now().add(const Duration(days: 10)),
      targetValue: 100,
      unit: 'steps',
      myProgress: 0,
      participantCount: 2,
      leaderboard: const [],
      rewards: const [],
      badges: const [],
      isJoined: joined,
      coachName: '',
      emoji: '🏆',
    );

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );

late _Reads _r;
late _Svc _svc;
final _who = StateProvider<User?>((ref) => null);

ProviderContainer _container({Map<String, dynamic>? profile}) => ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(_who)),
        tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
        confirmedCurrentProfileProvider.overrideWithValue(profile),
        liveChallengeServiceProvider.overrideWithValue(_svc),
        liveGroupsProvider.overrideWith((ref) async => const []),
        liveChallengesProvider.overrideWith((ref) async {
          ref.watch(currentUserProvider);
          _r.count++;
          final g = _r.gate;
          if (g != null) await g.future;
          final e = _r.error;
          if (e != null) throw e;
          return _r.rows;
        }),
      ],
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _show(WidgetTester tester, ProviderContainer c,
    {double scale = 1.0, double width = 430}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: MediaQuery.withClampedTextScaling(
        minScaleFactor: scale,
        maxScaleFactor: scale,
        child: const ActivityScreen()),
    ),
  ));
  await _settle(tester);
  await tester.scrollUntilVisible(find.text('See All'), 300,
      scrollable: find.byType(Scrollable).first);
  await _settle(tester);
}

/// Activity runs looping animations (the bell); unmount and drain them.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

const _other = 'Try again in a moment. If it keeps happening, contact support.';
const _net = 'Check your connection and try again.';
final _server = PostgrestException(message: 'SECRET_TABLE_X exploded', code: 'XX000');

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Rest(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() {
    _r = _Reads();
    _svc = _Svc();
  });

  group('(a) challenges read', () {
    testWidgets('a failed read is said, with a retry — never "No active challenges"',
        (tester) async {
      _r.error = _server;
      final c = _container();
      addTearDown(c.dispose);
      await _show(tester, c);

      expect(find.text('No active challenges'), findsNothing,
          reason: 'THE defect: the failure was rendered as an empty list');
      expect(find.text("Couldn't load challenges"), findsOneWidget);
      expect(find.text(_other), findsOneWidget);
      expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
      expect(find.text(_net), findsNothing, reason: 'not a connection failure');

      // Retry: busy (disabled) while in flight, then the list.
      final before = _r.count;
      _r
        ..error = null
        ..gate = Completer<void>()
        ..rows = [_challenge('c1', 'Ten K Steps')];
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(_r.count, before + 1);
      expect(find.text("Couldn't load challenges"), findsOneWidget,
          reason: 'the notice stays, busy, while the retry is in flight');
      final busy = tester.widget<TextButton>(find.descendant(
          of: find.byType(SectionLoadFailure), matching: find.byType(TextButton)));
      expect(busy.onPressed, isNull, reason: 'no double fire');
      _r.gate!.complete();
      await _settle(tester);
      expect(find.text('Ten K Steps'), findsOneWidget);
      expect(find.text("Couldn't load challenges"), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a network failure gives the connection hint', (tester) async {
      _r.error = const SocketException('offline');
      final c = _container();
      addTearDown(c.dispose);
      await _show(tester, c);
      expect(find.text(_net), findsOneWidget);
      expect(find.text(_other), findsNothing);
      await _unmount(tester);
    });

    testWidgets('negative control: a genuine empty list still says "No active challenges"',
        (tester) async {
      final c = _container();
      addTearDown(c.dispose);
      await _show(tester, c);
      expect(find.text('No active challenges'), findsOneWidget);
      expect(find.text("Couldn't load challenges"), findsNothing);
      await _unmount(tester);
    });

    testWidgets('positive control: the challenges show as before', (tester) async {
      _r.rows = [_challenge('c1', 'Ten K Steps'), _challenge('c2', 'Push-up Week', joined: true)];
      final c = _container();
      addTearDown(c.dispose);
      await _show(tester, c);
      expect(find.text('Ten K Steps'), findsOneWidget);
      expect(find.text('Push-up Week'), findsOneWidget);
      expect(find.text('JOINED'), findsOneWidget);
      expect(find.text("Couldn't load challenges"), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a failed refresh keeps the list this member was shown', (tester) async {
      _r.rows = [_challenge('c1', 'Ten K Steps')];
      final c = _container();
      addTearDown(c.dispose);
      await _show(tester, c);
      expect(find.text('Ten K Steps'), findsOneWidget);

      _r.error = _server;
      c.invalidate(liveChallengesProvider);
      await _settle(tester);
      expect(find.text("Couldn't load challenges"), findsOneWidget);
      expect(find.text('Ten K Steps'), findsOneWidget, reason: 'kept, under the notice');
      expect(find.textContaining('Showing the challenges loaded earlier.'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets("another member's list is never shown after their read fails",
        (tester) async {
      _r.rows = [_challenge('c1', "Avery's Secret Plan", joined: true)];
      final c = _container();
      addTearDown(c.dispose);
      c.read(_who.notifier).state = _user('00000000-0000-4000-8000-00000000000a');
      await _show(tester, c);
      expect(find.text("Avery's Secret Plan"), findsOneWidget);

      _r.error = _server;
      c.read(_who.notifier).state = _user('00000000-0000-4000-8000-00000000000b');
      await _settle(tester);
      expect(find.text("Couldn't load challenges"), findsOneWidget);
      expect(find.text("Avery's Secret Plan"), findsNothing);
      expect(find.textContaining('loaded earlier'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a failed join is recorded and said in the one voice', (tester) async {
      final reported = <AppFailure>[];
      setFailureSink(reported.add);
      addTearDown(resetFailureSink);
      _r.rows = [_challenge('c1', 'Ten K Steps')];
      _svc.joinError = const SocketException('offline');
      final c = _container();
      addTearDown(c.dispose);
      await _show(tester, c);
      await tester.tap(find.text('Join'));
      await _settle(tester);
      expect(reported.map((f) => f.origin), ['ChallengeNotifier.joinChallenge'],
          reason: 'THE defect: the failed join was swallowed unrecorded');
      expect(find.text("Couldn't join this challenge — check your connection and try again."),
          findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('positive control: a join that succeeds re-reads the list', (tester) async {
      final reported = <AppFailure>[];
      setFailureSink(reported.add);
      addTearDown(resetFailureSink);
      _r.rows = [_challenge('c1', 'Ten K Steps')];
      final c = _container();
      addTearDown(c.dispose);
      await _show(tester, c);
      final before = _r.count;
      _r.rows = [_challenge('c1', 'Ten K Steps', joined: true)];
      await tester.tap(find.text('Join'));
      await _settle(tester);
      expect(_r.count, before + 1);
      expect(find.text('JOINED'), findsOneWidget);
      expect(reported, isEmpty);
      expect(find.textContaining("Couldn't join"), findsNothing);
      await _unmount(tester);
    });
  });

  test('a signed-out join is a failure, not a silent success', () async {
    // Supabase here has no session.
    expect(() => LiveChallengeService().joinChallenge('c1'), throwsA(isA<StateError>()),
        reason: 'THE defect: it returned, and the challenge was shown as joined');
  });

  group('(d) See All and Enable', () {
    testWidgets('both are named buttons with >= 44px targets', (tester) async {
      final handle = tester.ensureSemantics();
      final c = _container(profile: {'notif_challenges': false});
      addTearDown(c.dispose);
      await _show(tester, c);

      for (final label in ['See all challenges', 'Enable challenge alerts']) {
        // The card's title reads "Enable challenge alerts" too: the BUTTON.
        final node = find.byWidgetPredicate((w) =>
            w is Semantics && w.properties.label == label && w.properties.button == true);
        expect(node, findsOneWidget, reason: '$label: no button node named for the item');
        final data = tester.getSemantics(node);
        expect(data.flagsCollection.isButton, isTrue, reason: '$label: no button role');
        final size = tester.getSize(node);
        expect(size.width, greaterThanOrEqualTo(44), reason: '$label width');
        expect(size.height, greaterThanOrEqualTo(44), reason: '$label height');
      }
      handle.dispose();
      await _unmount(tester);
    });

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('no overflow and no shrunk text at ${scale}x, ${width.toInt()}dp',
            (tester) async {
          // Other Activity cards (the Performance ring row) overflow at
          // large text on narrow screens — pre-existing, outside this
          // package. Only an overflow inside the Challenges section fails
          // this test.
          final errors = <FlutterErrorDetails>[];
          final previous = FlutterError.onError;
          FlutterError.onError = errors.add;
          final c = _container(profile: {'notif_challenges': false});
          addTearDown(c.dispose);
          try {
            await _show(tester, c, scale: scale, width: width);
          } finally {
            FlutterError.onError = previous;
          }
          final mine = errors
              .map((e) => e.toString())
              .where((t) => t.contains('_ChallengeSection'))
              .toList();
          expect(mine, isEmpty, reason: mine.join('\n'));
          for (final (text, size) in [('See All', 13.0), ('Enable', 12.0)]) {
            final p = tester.renderObject<RenderParagraph>(find.text(text));
            expect(p.textScaler.scale(size), closeTo(size * scale, 0.01),
                reason: '$text: the text was shrunk');
            expect((p.text as TextSpan).style?.fontSize, size);
          }
          // The whole label is laid out (no clipping / ellipsis).
          for (final text in ['See All', 'Enable']) {
            final p = tester.renderObject<RenderParagraph>(find.text(text));
            expect(p.didExceedMaxLines, isFalse, reason: '$text clipped');
          }
          await _unmount(tester);
        });
      }
    }
  });
}

