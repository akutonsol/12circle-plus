import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/row_checking_postgrest.dart';

// P0-FL-39 · the coach's Notifications sheet: mark read, mark all read, swipe
// delete and clear all are "done" only when the server says a row changed.
//
// At 6f8918f all four were bare writes with no error handling and no row
// check. A 0-row update/delete (RLS filters silently) answers 204 exactly like
// a done one; a thrown write was an unhandled error that said nothing; and the
// swipe took the row off screen whatever the server answered — the coach saw
// a notification "deleted" that was still stored.
//
// Failure notices are drawn INSIDE the sheet (a page SnackBar sits under the
// modal), as a live region.
//
// HOW TO SEE IT FAIL: with 6f8918f's coach_dashboard_screen.dart the 0-row
// tests find no failure notice, the swiped row gone, and writes without
// `select=id`; the throw tests hit an unhandled exception.

const _uid = '00000000-0000-4000-8000-0000000f1393';
const _later = 'try again in a moment. If it keeps happening, contact support.';
const _offline = 'check your connection and try again.';

typedef _Rows = List<Map<String, dynamic>>;

Map<String, dynamic> _n(String id, {bool read = false}) => {
      'id': id,
      'recipient_id': _uid,
      'title': 'New client $id',
      'body': 'Jo signed up',
      'read': read,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

/// [RowCheckingPostgrest] that treats DELETE as a write too, with the same
/// rules: 204 unless rows are asked for; `200 []` for a 0-row delete.
class _Server extends RowCheckingPostgrest {
  _Server(super.uid);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'DELETE') return super.send(request);
    final line = 'DELETE ${request.url.path}?${request.url.query}';
    writes.add(line);
    final asksForRows = request.url.queryParameters.containsKey('select');
    final applies = modeAppliesTo?.call(line) ?? true;
    switch (applies ? mode : WriteMode.oneRow) {
      case WriteMode.network:
        throw http.ClientException('Connection refused', request.url);
      case WriteMode.serverError:
        return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
      case WriteMode.zeroRows:
        return asksForRows
            ? _json([], 200, request)
            : http.StreamedResponse(const Stream.empty(), 204, request: request);
      case WriteMode.oneRow:
        return asksForRows
            ? _json([
                {'id': 'row-1'}
              ], 200, request)
            : http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  /// The sheet's header row overflows its 600 px cap in the test font when
  /// the list has unread rows — a pre-existing layout issue (see
  /// coach_notifications_sheet_failure_test.dart), not this file's subject.
  /// Only that overflow is tolerated; anything else still fails the test.
  void tolerateHeaderOverflow() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  Future<void> openSheet(WidgetTester tester, _Rows rows) async {
    tolerateHeaderOverflow();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        coachClientsProvider.overrideWith((ref) async => const []),
        clientCheckinsProvider.overrideWith((ref) async => const []),
        clientWorkoutLogsProvider.overrideWith((ref) async => const []),
        // Every subscription (the first, and each refresh after a write)
        // answers with the same stored rows: the server did not change them
        // unless a test says so.
        coachNotificationsProvider.overrideWith((ref) => Stream.value(rows)),
        currentUserProfileProvider.overrideWith((ref) async => null),
        currentUserDisplayNameProvider.overrideWithValue('Coach'),
        pendingRequestsProvider.overrideWith((ref) async => const []),
        sentInvitesProvider.overrideWith((ref) async => const []),
        coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
        coachLeaderboardProvider.overrideWith((ref) async => const []),
        coachTriageSignalsProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: CoachDashboardScreen()),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
  }

  /// The failure notice is in the SHEET, so it is visible over the page.
  Finder inSheet(Finder f) => find.descendant(
      of: find.byType(DraggableScrollableSheet), matching: f);

  Finder notice(String what, String next) =>
      inSheet(find.text("Couldn't $what — $next"));

  List<String> notifWrites() =>
      server.writes.where((w) => w.contains('/rest/v1/notifications')).toList();

  /// The unread dot of the row titled [title]: 8×8, brand-coloured circle.
  bool looksUnread(WidgetTester tester, String title) {
    final text = tester.widget<Text>(find.text(title));
    return text.style?.fontWeight == FontWeight.w700;
  }

  group('swipe delete', () {
    testWidgets('0 rows: the row comes back, the failure is said in the '
        'sheet, reported', (tester) async {
      await openSheet(tester, [_n('n-1', read: true), _n('n-2', read: true)]);
      server.mode = WriteMode.zeroRows;
      await tester.drag(find.text('New client n-1'), const Offset(-700, 0));
      await tester.pumpAndSettle();

      expect(notifWrites().single, startsWith('DELETE'));
      expect(notifWrites().single, contains('select=id'),
          reason: 'the delete must ask for its row back to see 0 rows');
      expect(find.text('New client n-1'), findsOneWidget,
          reason: 'THE defect: the swipe removed the row whatever the '
              'server answered');
      expect(notice('delete this notification', _later), findsOneWidget);
      expect(reported.single.origin, 'CoachNotificationsSheet.delete');
    });

    testWidgets('connection failure: row restored, connection hint',
        (tester) async {
      await openSheet(tester, [_n('n-1', read: true)]);
      server.mode = WriteMode.network;
      await tester.drag(find.text('New client n-1'), const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(find.text('New client n-1'), findsOneWidget);
      expect(notice('delete this notification', _offline), findsOneWidget);
      expect(reported, hasLength(1));
    });

    testWidgets('control: a confirmed delete removes the row, no notice',
        (tester) async {
      await openSheet(tester, [_n('n-1', read: true), _n('n-2', read: true)]);
      await tester.drag(find.text('New client n-1'), const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(notifWrites().single, contains('id=eq.n-1'));
      expect(find.text('New client n-1'), findsNothing);
      expect(find.text('New client n-2'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });
  });

  group('mark read', () {
    testWidgets('0 rows: the row stays unread, the failure is said',
        (tester) async {
      await openSheet(tester, [_n('n-1')]);
      server.mode = WriteMode.zeroRows;
      await tester.tap(find.text('New client n-1'));
      await tester.pumpAndSettle();
      expect(notifWrites().single, contains('select=id'));
      expect(notifWrites().single, contains('"read":true'));
      expect(looksUnread(tester, 'New client n-1'), isTrue);
      expect(notice('mark this notification as read', _later), findsOneWidget);
      expect(reported.single.origin, 'CoachNotificationsSheet.markRead');
    });

    testWidgets('server error: said with the try-again copy, no exception '
        'text', (tester) async {
      await openSheet(tester, [_n('n-1')]);
      server.mode = WriteMode.serverError;
      await tester.tap(find.text('New client n-1'));
      await tester.pumpAndSettle();
      expect(notice('mark this notification as read', _later), findsOneWidget);
      expect(find.textContaining('refused'), findsNothing);
      expect(reported, hasLength(1));
    });
  });

  group('mark all read', () {
    testWidgets('0 rows: said, nothing shown as read', (tester) async {
      await openSheet(tester, [_n('n-1'), _n('n-2', read: true)]);
      server.mode = WriteMode.zeroRows;
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();
      expect(notifWrites().single, contains('select=id'));
      expect(notifWrites().single, contains('"read":true'));
      expect(looksUnread(tester, 'New client n-1'), isTrue);
      expect(notice('mark your notifications as read', _later), findsOneWidget);
      expect(reported.single.origin, 'CoachNotificationsSheet.markAllRead');
    });

    testWidgets('connection failure: the connection hint', (tester) async {
      await openSheet(tester, [_n('n-1')]);
      server.mode = WriteMode.network;
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();
      expect(notice('mark your notifications as read', _offline),
          findsOneWidget);
    });
  });

  group('clear all', () {
    testWidgets('0 rows: said, the list is still shown', (tester) async {
      await openSheet(tester, [_n('n-1', read: true), _n('n-2', read: true)]);
      server.mode = WriteMode.zeroRows;
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(notifWrites().single, startsWith('DELETE'));
      expect(notifWrites().single, contains('select=id'));
      expect(notifWrites().single, contains('recipient_id=eq.$_uid'));
      expect(find.text('New client n-1'), findsOneWidget);
      expect(notice('clear your notifications', _later), findsOneWidget);
      expect(reported.single.origin, 'CoachNotificationsSheet.clearAll');
    });

    testWidgets('server error: said', (tester) async {
      await openSheet(tester, [_n('n-1', read: true)]);
      server.mode = WriteMode.serverError;
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(notice('clear your notifications', _later), findsOneWidget);
      expect(reported, hasLength(1));
    });

    testWidgets('control: a confirmed clear says nothing wrong',
        (tester) async {
      await openSheet(tester, [_n('n-1', read: true)]);
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });
  });

  testWidgets('the failure notice is a live region', (tester) async {
    final semantics = tester.ensureSemantics();
    await openSheet(tester, [_n('n-1', read: true)]);
    server.mode = WriteMode.zeroRows;
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    final node = tester.getSemantics(
        notice('clear your notifications', _later));
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    semantics.dispose();
  });
}
