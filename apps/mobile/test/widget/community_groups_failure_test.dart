import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/activity/presentation/activity_screen.dart';
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

// P0-FL-10 · a failed groups read is never "no groups".
//
// At 8d2eb09 `groupNotifierProvider` was a bare List that started `const []`
// and copied only the DATA of `liveGroupsProvider` (`next.whenData(...)`). A
// failed read therefore stayed `[]`:
//   * Community › Groups showed only the Pods card — as if there were none;
//   * Activity › Community said "No communities joined yet" (also while the
//     groups were still loading).
// And `toggleJoin` dropped the join/leave result, so a failed join was a dead
// tap with no word said.
//
// The groups read is faked at the `liveGroupsProvider` seam (its own read is
// covered by community_groups_are_real_test.dart); join/leave at the service
// seam. Everything else talks to a fake PostgREST that answers `[]` — nothing
// leaves the process.

class _Rest extends http.BaseClient {
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

/// The groups read: fails with [error], hangs on [gate], else [rows].
class _Groups {
  Object? error;
  Completer<void>? gate;
  List<CommunityGroup> rows = const [];
  int reads = 0;
}

/// Join/leave without the network; answers [ok].
class _Svc extends LiveCommunityService {
  bool ok = true;
  final calls = <String>[];
  @override
  Future<List<CommunityPost>> getPosts({int limit = 30}) async => const [];
  @override
  Future<bool> joinGroup(String groupId) async {
    calls.add('join:$groupId');
    return ok;
  }

  @override
  Future<bool> leaveGroup(String groupId) async {
    calls.add('leave:$groupId');
    return ok;
  }
}

CommunityGroup _group(String id, String name, {bool joined = false}) =>
    CommunityGroup(
      id: id,
      name: name,
      description: 'About $name',
      emoji: '💪',
      memberCount: 3,
      isJoined: joined,
    );

late _Groups _g;
late _Svc _svc;

List<Override> _overrides() => [
      currentUserProvider.overrideWithValue(null),
      liveCommunityServiceProvider.overrideWithValue(_svc),
      liveMembersProvider.overrideWith((ref) async => const []),
      liveGroupsProvider.overrideWith((ref) async {
        _g.reads++;
        final gate = _g.gate;
        if (gate != null) await gate.future;
        final e = _g.error;
        if (e != null) throw e;
        return _g.rows;
      }),
    ];

Widget _community() => ProviderScope(
      overrides: _overrides(),
      child: const MaterialApp(home: CommunityScreen()),
    );

Widget _activity() => ProviderScope(
      overrides: _overrides(),
      child: const MaterialApp(home: ActivityScreen()),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 2)); // entrance animations
}

Future<void> _openGroups(WidgetTester tester, {Widget? app}) async {
  await tester.pumpWidget(app ?? _community());
  await _settle(tester);
  await tester.tap(find.text('Groups'));
  await _settle(tester);
}

/// Activity runs looping animations (the bell); unmount and drain them.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _showActivitySection(WidgetTester tester) async {
  await tester.pumpWidget(_activity());
  await _settle(tester);
  await tester.scrollUntilVisible(find.text('Explore'), 300,
      scrollable: find.byType(Scrollable).first);
  await _settle(tester);
}

const _other = 'Try again in a moment. If it keeps happening, contact support.';
const _net = 'Check your connection and try again.';
final _server = PostgrestException(
    message: 'SECRET_TABLE_X exploded', code: 'XX000');

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
    _g = _Groups()..error = _server;
    _svc = _Svc();
  });

  group('groupNotifierProvider', () {
    test('a failed read is a failure, not an empty list', () async {
      final reported = <AppFailure>[];
      setFailureSink(reported.add);
      addTearDown(resetFailureSink);
      final c = ProviderContainer(overrides: _overrides());
      addTearDown(c.dispose);
      c.listen(groupNotifierProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      final s = c.read(groupNotifierProvider) as AsyncValue<Object?>;
      expect(s.hasError, isTrue, reason: 'THE defect: the failure stayed []');
      expect(s.hasValue, isFalse);
      expect(reported.map((f) => f.origin), ['community.groups']);
      expect(reported.single.error, same(_server));
    });

    test('positive control: the groups arrive as before', () async {
      _g
        ..error = null
        ..rows = [_group('a', 'Alpha Lifters')];
      final c = ProviderContainer(overrides: _overrides());
      addTearDown(c.dispose);
      c.listen(groupNotifierProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      final s = c.read(groupNotifierProvider) as AsyncValue<Object?>;
      expect(s.hasError, isFalse);
      expect((s.value! as List<CommunityGroup>).single.name, 'Alpha Lifters');
    });
  });

  group('Community › Groups', () {
    testWidgets(
        'a failed groups read says so, is recorded once, and Try again is '
        'busy while it re-reads', (tester) async {
      final reported = <AppFailure>[];
      setFailureSink(reported.add);
      addTearDown(resetFailureSink);
      final semantics = tester.ensureSemantics();

      await _openGroups(tester);

      expect(find.text('Accountability Pods'), findsOneWidget,
          reason: 'the way in to Pods is not a group read');
      expect(find.text("Couldn't load groups"), findsOneWidget,
          reason: 'THE defect: a failure showed as no groups');
      expect(find.text(_other), findsOneWidget,
          reason: 'a server answer is not a connection problem');
      expect(find.text(_net), findsNothing);
      expect(find.textContaining('SECRET_TABLE_X'), findsNothing);

      // Re-showing the same failure is not a second record.
      await tester.tap(find.text('Members'));
      await _settle(tester);
      await tester.tap(find.text('Groups'));
      await _settle(tester);
      expect(reported.map((f) => f.origin), ['community.groups']);

      // Try again: busy while the read is in flight, then the groups.
      _g
        ..gate = Completer<void>()
        ..error = null
        ..rows = [_group('a', 'Alpha Lifters')];
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_g.reads, 2, reason: 'Try again re-reads');
      final button = tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.text('Try again'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
      expect(button.onPressed, isNull, reason: 'busy: no second tap');
      expect(find.bySemanticsLabel(RegExp('Retrying')), findsOneWidget);
      expect(find.text("Couldn't load groups"), findsOneWidget);

      _g.gate!.complete();
      await _settle(tester);
      expect(find.text("Couldn't load groups"), findsNothing);
      expect(find.text('Alpha Lifters'), findsOneWidget);
      expect(reported.length, 1, reason: 'a successful re-read records nothing');
      semantics.dispose();
    });

    testWidgets('a second failed read after Try again is recorded once more',
        (tester) async {
      final reported = <AppFailure>[];
      setFailureSink(reported.add);
      addTearDown(resetFailureSink);
      await _openGroups(tester);
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(_g.reads, 2);
      expect(find.text("Couldn't load groups"), findsOneWidget);
      expect(reported.length, 2);
    });

    testWidgets('no connection says check your connection', (tester) async {
      _g.error = const SocketException('Connection refused');
      await _openGroups(tester);
      expect(find.text("Couldn't load groups"), findsOneWidget);
      expect(find.text(_net), findsOneWidget);
      expect(find.text(_other), findsNothing);
    });

    testWidgets('the failure scrolls at 2x text, 320 wide, and is announced',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      await _openGroups(tester,
          app: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(2.0),
            ),
            child: _community(),
          ));
      // At 2x it sits below the Pods card: the tab scrolls to it.
      await tester.scrollUntilVisible(find.text('Try again'), 200,
          scrollable: find
              .descendant(
                  of: find.byType(TabBarView),
                  matching: find.byWidgetPredicate((w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down))
              .first);
      await _settle(tester);
      expect(find.text("Couldn't load groups"), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final live = find.ancestor(
        of: find.text("Couldn't load groups"),
        matching: find.byWidgetPredicate((w) =>
            w is Semantics && w.properties.liveRegion == true && w.container),
      );
      expect(live, findsOneWidget);
      expect(find.ancestor(of: live, matching: find.byType(Scrollable)),
          findsWidgets);
      semantics.dispose();
    });

    testWidgets('positive control: no groups is still just the Pods card',
        (tester) async {
      _g.error = null;
      await _openGroups(tester);
      expect(find.text('Accountability Pods'), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('Join'), findsNothing);
    });

    testWidgets('a failed join says so and the group stays not joined',
        (tester) async {
      _g
        ..error = null
        ..rows = [_group('a', 'Alpha Lifters')];
      _svc.ok = false;
      await _openGroups(tester);
      await tester.tap(find.text('Join'));
      await _settle(tester);
      expect(_svc.calls, ['join:a']);
      expect(find.text("Couldn't join Alpha Lifters. Try again."), findsOneWidget,
          reason: 'THE defect: the failed join said nothing');
      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Joined'), findsNothing);
      expect(find.text('3 members'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // SnackBar timer
    });

    testWidgets('a failed leave says so and the group stays joined',
        (tester) async {
      _g
        ..error = null
        ..rows = [_group('a', 'Alpha Lifters', joined: true)];
      _svc.ok = false;
      await _openGroups(tester);
      await tester.tap(find.text('Joined'));
      await _settle(tester);
      expect(_svc.calls, ['leave:a']);
      expect(find.text("Couldn't leave Alpha Lifters. Try again."), findsOneWidget);
      expect(find.text('Joined'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('positive control: a join that works shows Joined, no message',
        (tester) async {
      _g
        ..error = null
        ..rows = [_group('a', 'Alpha Lifters')];
      await _openGroups(tester);
      await tester.tap(find.text('Join'));
      await _settle(tester);
      expect(find.text('Joined'), findsOneWidget);
      expect(find.text('4 members'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('Activity › Community', () {
    testWidgets(
        'a failed groups read is not "No communities joined yet"; it says so '
        'and Try again re-reads', (tester) async {
      final reported = <AppFailure>[];
      setFailureSink(reported.add);
      addTearDown(resetFailureSink);
      final semantics = tester.ensureSemantics();
      await _showActivitySection(tester);

      expect(find.text('No communities joined yet'), findsNothing,
          reason: 'THE defect: a failure read as not joined');
      expect(find.text("Couldn't load your groups"), findsOneWidget);
      expect(find.text(_other), findsOneWidget);
      final live = find.ancestor(
        of: find.text("Couldn't load your groups"),
        matching: find.byWidgetPredicate((w) =>
            w is Semantics && w.properties.liveRegion == true && w.container),
      );
      expect(live, findsOneWidget);
      expect(reported.map((f) => f.origin), ['community.groups']);

      _g
        ..error = null
        ..rows = [_group('a', 'Alpha Lifters', joined: true)];
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(_g.reads, 2);
      expect(find.text("Couldn't load your groups"), findsNothing);
      expect(find.text('Alpha Lifters'), findsOneWidget);
      expect(find.text('JOINED'), findsOneWidget);
      semantics.dispose();
      await _unmount(tester);
    });

    testWidgets('no connection says check your connection', (tester) async {
      _g.error = const SocketException('Connection refused');
      await _showActivitySection(tester);
      expect(find.text(_net), findsOneWidget);
      expect(find.text('No communities joined yet'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('while the groups load, nothing claims "not joined"',
        (tester) async {
      _g
        ..error = null
        ..gate = Completer<void>();
      await _showActivitySection(tester);
      expect(find.text('No communities joined yet'), findsNothing,
          reason: 'THE defect: loading said not joined');
      expect(find.text("Couldn't load your groups"), findsNothing);
      _g.gate!.complete();
      await _settle(tester);
      expect(find.text('No communities joined yet'), findsOneWidget,
          reason: 'positive control: none joined, once loaded');
      await _unmount(tester);
    });

    testWidgets('the failure card fits at 2x text, 320 wide', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Other Activity cards (e.g. _PerformanceCard) already overflow at 2x,
      // 320 wide — not this package's section. Only an overflow inside the
      // groups failure card fails this test; the rest is noted, not asserted.
      final ours = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.toString().contains('_GroupsFailureCard')) ours.add(d);
      };
      var shown = false;
      try {
        await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 900),
            textScaler: TextScaler.linear(2.0),
          ),
          child: _activity(),
        ));
        await _settle(tester);
        final card = find.text("Couldn't load your groups");
        await tester.dragUntilVisible(
            card, find.byType(SingleChildScrollView).first, const Offset(0, -300),
            maxIteration: 30);
        await _settle(tester);
        shown = card.evaluate().length == 1 &&
            find.text('Try again').evaluate().length == 1;
        await _unmount(tester);
      } on StateError {
        shown = false; // the card never appeared
      } finally {
        FlutterError.onError = previous;
      }
      expect(shown, isTrue, reason: 'the failure card is shown with Try again');
      expect(ours, isEmpty, reason: 'the failure card does not overflow');
    });
  });
}
