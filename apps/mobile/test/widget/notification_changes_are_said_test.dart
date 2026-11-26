import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/notifications/data/notification_service.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:circle_fitness/features/notifications/presentation/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/owned_rows_postgrest.dart';
import '../support/settled.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60c (d) · Notifications. A failed mark-read / mark-all / delete was
// unrecorded (a failed mark-read was not said at all), one that changed no row
// was a success, a failed refresh replaced the list, a token refresh re-read
// everything, and a notification that could not be sent left no trace.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 --` notification_service.dart,
// notification_provider.dart, notifications_screen.dart.

const _t = 'notifications';
const _support =
    'try again in a moment. If it keeps happening, contact support.';
const _network = 'check your connection and try again.';

Map<String, Object?> _n(String id, String uid, String title) => {
      'id': id, 'recipient_id': uid, 'type': 'general', 'title': title,
      'body': 'Body', 'read': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

void main() {
  final server = OwnedRowsPostgrest();
  final reported = <AppFailure>[];
  late ProviderContainer c;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    server.rows[_t] = [
      _n('a-1', memberA, 'For A one'),
      _n('a-2', memberA, 'For A two'),
      _n('b-1', memberB, 'For B'),
    ];
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
    c = ProviderContainer();
  });

  tearDown(() {
    c.dispose();
    resetFailureSink();
  });

  Finder text(String s) => find.text(s);
  Iterable<String> origins() => reported
      .map((f) => f.origin)
      .where((o) => o != 'NotificationsNotifier.stream');
  bool readOf(String id) =>
      server.rows[_t]!.firstWhere((r) => r['id'] == id)['read']! as bool;

  Future<void> settle(WidgetTester tester) => settledFrames(tester, server,
      step: const Duration(milliseconds: 50));

  /// The notifier is created in real time: its live feed opens a socket.
  Future<void> create(WidgetTester tester) => tester.runAsync(() async {
        if (!c.exists(notificationsProvider)) {
          c.listen(notificationsProvider, (_, __) {});
        }
        c.read(notificationsProvider);
        await settled(server);
      });

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 1800);
    addTearDown(tester.view.reset);
    await create(tester);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: NotificationsScreen())));
    await settle(tester);
  }

  Future<void> become(WidgetTester tester, String? uid) async {
    await tester.runAsync(() async {
      await (uid == null ? signOut() : signInAs(uid));
      await eventually(() => c.read(currentUserProvider)?.id, uid,
          reason: 'premise');
    });
    await create(tester);
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
    await tester.runAsync(() async {
      c.dispose();
      await settled(server);
    });
    await tester.pump(const Duration(minutes: 2));
  }

  Future<void> swipe(WidgetTester tester, String title) async {
    await tester.fling(text(title), const Offset(-700, 0), 2000);
    await settle(tester);
    await settle(tester);
  }

  testWidgets('control: reads, marks one, marks all, deletes', (tester) async {
    await show(tester);
    expect(text('For A one'), findsOneWidget);
    expect(text('For B'), findsNothing);
    await tester.tap(text('For A one'));
    await settle(tester);
    expect(readOf('a-1'), isTrue);
    expect(readOf('a-2'), isFalse);
    await tester.tap(text('Mark all read'));
    await settle(tester);
    expect(readOf('a-2'), isTrue);
    // Nothing left unread: 0 rows changed is not a failure.
    await tester.tap(text('Mark all read'));
    await settle(tester);
    await swipe(tester, 'For A one');
    expect(text('For A one'), findsNothing);
    expect(server.rows[_t], hasLength(2));
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(origins(), isEmpty);
    await done(tester);
  });

  testWidgets('control: none is said as none', (tester) async {
    server.rows[_t] = [];
    await show(tester);
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(text('For A one'), findsNothing);
    await done(tester);
  });

  for (final (how, hint, arrange) in <(String, String, void Function(String))>[
    ('refused', _support, (k) => server.fails.add(k)),
    ('offline', _network, (k) => server.offline.add(k)),
    ('changing NO ROW', _support, (k) => server.filtered.add(k)),
  ]) {
    testWidgets('mark read, $how: recorded, said, still unread', (tester) async {
      arrange('PATCH $_t:$memberA');
      await show(tester);
      await tester.tap(text('For A one'));
      await settle(tester);
      expect(text("Couldn't mark that read — $hint"), findsOneWidget,
          reason: 'THE defect: nothing was said');
      expect(origins(), ['NotificationsNotifier.markRead']);
      expect(find.textContaining('Unread'), findsNWidgets(2));
      expect(find.textContaining('SECRET_TABLE'), findsNothing);
      await done(tester);
    });

    testWidgets('mark all read, $how: recorded, said, still unread',
        (tester) async {
      arrange('PATCH $_t:$memberA');
      await show(tester);
      await tester.tap(text('Mark all read'));
      await settle(tester);
      expect(text("Couldn't mark them read — $hint"), findsOneWidget);
      expect(origins(), ['NotificationsNotifier.markAllRead'],
          reason: 'THE defect: unrecorded / 0 rows was success');
      expect(find.textContaining('Unread'), findsNWidgets(2));
      await done(tester);
    });

    testWidgets('delete, $how: recorded, said, still there', (tester) async {
      arrange('DELETE $_t:$memberA');
      await show(tester);
      await swipe(tester, 'For A one');
      expect(text("Couldn't delete that — $hint"), findsOneWidget);
      expect(origins(), ['NotificationsNotifier.delete']);
      expect(text('For A one'), findsOneWidget,
          reason: 'THE defect: it vanished though the server kept it');
      await done(tester);
    });
  }

  testWidgets('a failed first read is said and recorded; Try again reads it',
      (tester) async {
    server.fails.add('GET $_t:$memberA');
    await show(tester);
    expect(text("Couldn't load your notifications"), findsOneWidget);
    expect(origins(), contains('NotificationsNotifier.load'));
    server.fails.clear();
    await tester.tap(text('Try again'));
    await settle(tester);
    expect(text('For A one'), findsOneWidget);
    expect(find.textContaining("Couldn't"), findsNothing);
    await done(tester);
  });

  testWidgets('a failed refresh keeps the list and says so', (tester) async {
    await show(tester);
    server.fails.add('GET $_t:$memberA');
    await tester.runAsync(() => c.read(notificationsProvider.notifier).refresh());
    await settle(tester);
    expect(text('For A one'), findsOneWidget,
        reason: 'THE defect: the list was replaced by a failure');
    expect(text("Couldn't load your latest notifications"), findsOneWidget);
    // A change made meanwhile still lands on the list that is shown.
    await tester.tap(text('For A one'));
    await settle(tester);
    expect(find.textContaining('Unread'), findsOneWidget);
    await done(tester);
  });

  group('A->B', () {
    testWidgets("B's read pending, then failed: nothing of A", (tester) async {
      await show(tester);
      final hold = server.holds['GET $_t:$memberB'] = Completer<void>();
      server.fails.add('GET $_t:$memberB');
      await become(tester, memberB);
      expect(text('For A one'), findsNothing);
      hold.complete();
      await settle(tester);
      expect(text('For A one'), findsNothing);
      expect(text("Couldn't load your notifications"), findsOneWidget);
      await done(tester);
    });

    testWidgets("a change in flight for A: nothing is said to B", (tester) async {
      final hold = server.holds['PATCH $_t:$memberA'] = Completer<void>();
      server.fails.add('PATCH $_t:$memberA');
      await show(tester);
      await tester.tap(text('For A one'));
      await settle(tester);
      await become(tester, memberB);
      hold.complete();
      await settle(tester);
      expect(find.textContaining("Couldn't"), findsNothing,
          reason: "A's failure is not B's news");
      expect(origins(), contains('NotificationsNotifier.markRead'));
      expect(text('For B'), findsOneWidget);
      await done(tester);
    });

    testWidgets('a change in flight when the providers go with the account',
        (tester) async {
      final hold = server.holds['PATCH $_t:$memberA'] = Completer<void>();
      server.fails.add('PATCH $_t:$memberA');
      await show(tester);
      await tester.tap(text('For A one'));
      await settle(tester);
      await tester.runAsync(() => signInAs(memberB));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async => c.dispose());
      hold.complete();
      await settle(tester);
      expect(tester.takeException(), isNull);
      await done(tester);
    });

    // A's RENDERED controls with B already signed in and no frame since:
    // notification_controls_are_their_owners_test.

    testWidgets('sign-out, then A again', (tester) async {
      await show(tester);
      await become(tester, null);
      expect(text('For A one'), findsNothing);
      await become(tester, memberA);
      expect(text('For A one'), findsOneWidget);
      await done(tester);
    });

    testWidgets('control: a token refresh keeps the list, reads nothing again',
        (tester) async {
      await show(tester);
      final before = c.read(currentUserProvider);
      final notifier = c.read(notificationsProvider.notifier);
      await tester.runAsync(() async {
        await refreshSession();
        await eventually(
            () => identical(c.read(currentUserProvider), before), isFalse,
            reason: 'premise: a new User');
      });
      await create(tester);
      expect(identical(c.read(notificationsProvider.notifier), notifier), isTrue,
          reason: 'THE defect: the list was dropped on a token refresh');
      await settle(tester);
      expect(text('For A one'), findsOneWidget);
      await done(tester);
    });
  });

  group('notifyUser', () {
    Future<void> send() => NotificationService().notifyUser(
        recipientId: memberB, type: 'checkin', title: 'T', body: 'B');

    test('a notification that could not be sent is recorded, and never throws',
        () async {
      server.fails.add('POST $_t:$memberA');
      await send();
      expect(reported.single.origin, 'NotificationService.notifyUser',
          reason: 'THE defect: it left no trace');
      expect(server.rows[_t], hasLength(3));
    });

    test('control: one that was sent records nothing', () async {
      await send();
      expect(server.rows[_t]!.last['recipient_id'], memberB);
      expect(reported, isEmpty);
    });
  });
}
