import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/data/package_service.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/coach/presentation/coach_availability_screen.dart';
import 'package:circle_fitness/features/coach/presentation/coach_packages_screen.dart';
import 'package:circle_fitness/features/coach/presentation/coach_video_response_screen.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-53b (c) · staff-facing writes that were not told truthfully.
//
// At b7ec6ef:
//  1. Coach Packages › Delete: no catch — a failed delete escaped unhandled;
//     nothing was said, the package simply stayed.
//  2. Coach Packages › Save: no catch — the Save button spun for good.
//  3. Video Response: the client's notification was inside the same try as
//     the saved response, so a failed notification read "Failed to send your
//     response" (and sending again saved it twice); "has been notified" was
//     claimed regardless; and no failure was recorded.
//  4. Availability › Publish Slot: a failed insert was said but never
//     recorded.
//  5. Availability › delete: a 0-row delete was said but never recorded.
//
// Round 2 (fc01f04 → review UX F1/F2/F3):
//  6. Packages editor / Add-slot sheet: the failure was a SnackBar on the
//     Scaffold UNDER the modal sheet (likely invisible). It is now said inside
//     the sheet, above the button, as a live region, cleared on the next try.
//  7. Video Done view, not notified: no next step, muted colour under a green
//     check, and not a live region.

const _uid = '00000000-0000-4000-8000-0000000000c0';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

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

/// Writes fail (500) for the tables in [failing]; a DELETE on
/// coach_availability returns [deletedRows] rows. Every write is logged.
class _Server extends http.BaseClient {
  Set<String> failing = {};
  int deletedRows = 1;
  /// When set, a POST waits for it before answering.
  Completer<void>? gate;
  final writes = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final table = request.url.pathSegments.last;
    Object? body = [];
    var status = 200;
    if (request.method != 'GET') {
      writes.add('${request.method} $table');
      if (request.method == 'POST') await gate?.future;
      if (failing.contains(table)) {
        body = {'message': 'SECRET_TABLE_X exploded', 'code': 'XX000'};
        status = 500;
      } else if (request.method == 'DELETE') {
        body = [for (var i = 0; i < deletedRows; i++) {'id': 'slot-1'}];
      } else {
        status = 201;
        body = [];
      }
    } else if (table == 'coach_availability') {
      body = [
        {'id': 'slot-1', 'coach_id': _uid, 'is_booked': false,
         'slot_time': DateTime.now().toUtc().add(const Duration(days: 2)).toIso8601String(),
         'duration_minutes': 30, 'type': 'check_in'},
      ];
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

final _server = _Server();

class _Packages extends PackageService {
  Object? deleteError;
  Object? saveError;
  Completer<void>? hold;
  int deletes = 0, saves = 0;
  @override
  Future<void> deletePackage(String id) async {
    deletes++;
    final e = deleteError;
    if (e != null) throw e;
  }

  @override
  Future<void> savePackage({String? id, required String type, required String name,
      required int sessions, required double price, String? description,
      String? cancellationPolicy}) async {
    saves++;
    await hold?.future;
    final e = saveError;
    if (e != null) throw e;
  }
}

const _other = 'try again in a moment. If it keeps happening, contact support.';

List<AppFailure> _sink() {
  final reported = <AppFailure>[];
  setFailureSink(reported.add);
  addTearDown(resetFailureSink);
  return reported;
}

/// [f] is inside the open modal bottom sheet (not on the Scaffold under it).
Finder _inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

bool _liveRegion(WidgetTester tester, Finder f) => tester
    .widgetList<Semantics>(find.ancestor(of: f, matching: find.byType(Semantics)))
    .any((s) => s.properties.liveRegion ?? false);

void _tall(WidgetTester tester) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(900, 2400);
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() {
    _server
      ..failing = {}
      ..deletedRows = 1
      ..writes.clear();
  });

  group('Video Response', () {
    Future<void> send(WidgetTester tester) async {
      _tall(tester);
      await tester.pumpWidget(const MaterialApp(
          home: CoachVideoResponseScreen(clientId: 'client-1', clientName: 'Jamie')));
      await tester.enterText(find.byType(TextField), 'Great week — keep the tempo.');
      // The Send button is computed at build and the note field does not
      // rebuild the screen (a separate, listed defect): rebuild it here.
      // ignore: avoid_dynamic_calls
      (tester.state(find.byType(CoachVideoResponseScreen)) as dynamic).setState(() {});
      await tester.pump();
      await tester.tap(find.text('Send to Client'));
      await tester.pumpAndSettle();
    }

    testWidgets('a failed notification is not a failed send', (tester) async {
      _server.failing = {'notifications'};
      final reported = _sink();
      await send(tester);
      expect(find.text('Video Sent!'), findsOneWidget,
          reason: 'THE defect: the saved response was reported as not sent');
      const line = "Your response is saved, but Jamie wasn't notified — let them know another way.";
      expect(find.text(line), findsOneWidget, reason: 'r2 F2: a next step');
      expect(_liveRegion(tester, find.text(line)), isTrue, reason: 'r2 F3: announced');
      expect(tester.widget<Text>(find.text(line)).style?.color, const Color(0xFFF59E0B),
          reason: 'r2 F2: the warning colour, not the muted success colour');
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing,
          reason: 'r2 F2: not under a green check');
      expect(find.textContaining('has been notified'), findsNothing,
          reason: 'notified was claimed regardless');
      expect(reported.map((f) => f.origin), ['CoachVideoResponseScreen._send.notify']);
      expect(_server.writes.where((w) => w == 'POST coach_video_responses').length, 1);
    });

    testWidgets('a failed save is recorded and said in the one voice', (tester) async {
      _server.failing = {'coach_video_responses'};
      final reported = _sink();
      await send(tester);
      expect(find.text('Video Sent!'), findsNothing);
      expect(find.text("Couldn't send your response — $_other"), findsOneWidget);
      expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
      expect(reported.map((f) => f.origin), ['CoachVideoResponseScreen._send'],
          reason: 'THE defect: the failure was swallowed unrecorded');
      expect(_server.writes, isNot(contains('POST notifications')),
          reason: 'no notification for a response that was not saved');
    });

    testWidgets('positive control: saved and notified', (tester) async {
      final reported = _sink();
      await send(tester);
      const line = 'Jamie has been notified and can watch your response.';
      expect(find.text(line), findsOneWidget);
      expect(tester.widget<Text>(find.text(line)).style?.color, const Color(0xFFCFC2D6),
          reason: 'notified path unchanged');
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.textContaining("wasn't notified"), findsNothing);
      expect(reported, isEmpty);
    });
  });

  group('Availability', () {
    Future<void> open(WidgetTester tester) async {
      _tall(tester);
      await tester.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('a failed Publish Slot is recorded and said in the one voice',
        (tester) async {
      _server.failing = {'coach_availability'};
      final reported = _sink();
      await open(tester);
      await tester.tap(find.text('Add Slot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish Slot'));
      await tester.pumpAndSettle();
      const msg = "Couldn't save this time slot — $_other";
      expect(_inSheet(find.text(msg)), findsOneWidget,
          reason: 'r2 F1: said inside the sheet, not on the Scaffold under it');
      expect(find.byType(SnackBar), findsNothing);
      expect(_liveRegion(tester, find.text(msg)), isTrue);
      expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
      expect(find.text('Publish Slot'), findsOneWidget, reason: 'the sheet stays open');
      expect(reported.map((f) => f.origin), ['CoachAvailabilityScreen._AddSlotSheet._save'],
          reason: 'THE defect: the failure was swallowed unrecorded');

      // The next attempt clears it while in flight; a success closes the sheet.
      _server
        ..failing = {}
        ..gate = Completer<void>();
      await tester.tap(find.text('Publish Slot'));
      await tester.pump();
      expect(find.text(msg), findsNothing, reason: 'r2 F1: cleared on the next attempt');
      _server.gate!.complete();
      _server.gate = null;
      await tester.pumpAndSettle();
      expect(find.text('Publish Slot'), findsNothing);
      expect(reported, hasLength(1));
    });

    testWidgets('negative control: a fresh Add-slot sheet says no failure', (tester) async {
      final reported = _sink();
      await open(tester);
      await tester.tap(find.text('Add Slot'));
      await tester.pumpAndSettle();
      expect(_inSheet(find.text('Publish Slot')), findsOneWidget);
      expect(_inSheet(find.textContaining("Couldn't")), findsNothing);
      expect(reported, isEmpty);
    });

    testWidgets('positive control: Publish Slot that saves closes the sheet', (tester) async {
      final reported = _sink();
      await open(tester);
      await tester.tap(find.text('Add Slot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish Slot'));
      await tester.pumpAndSettle();
      expect(find.text('Publish Slot'), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });

    testWidgets('a 0-row delete is recorded, not only said', (tester) async {
      _server.deletedRows = 0;
      final reported = _sink();
      await open(tester);
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't remove this slot"), findsOneWidget);
      expect(reported.map((f) => f.origin), ['CoachAvailabilityScreen._delete'],
          reason: 'THE defect: the 0-row delete was not recorded');
    });

    testWidgets('positive control: a delete that removes a row says nothing',
        (tester) async {
      final reported = _sink();
      await open(tester);
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });
  });

  group('Coach Packages', () {
    late _Packages svc;
    late int reads;

    Future<void> open(WidgetTester tester) async {
      _tall(tester);
      svc = _Packages();
      reads = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          packageServiceProvider.overrideWithValue(svc),
          coachConnectStatusProvider.overrideWith((ref) async => const {'connected': true}),
          myPackagesProvider.overrideWith((ref) async {
            reads++;
            return [
              {'id': 'p1', 'type': 'per_session', 'name': 'Solo Session', 'price': 60,
               'sessions': 1, 'description': ''},
            ];
          }),
        ],
        child: const MaterialApp(home: CoachPackagesScreen()),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> delete(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    testWidgets('a failed delete is recorded and said', (tester) async {
      final reported = _sink();
      await open(tester);
      svc.deleteError = PostgrestException(message: 'SECRET_TABLE_X', code: 'XX000');
      await delete(tester);
      expect(tester.takeException(), isNull, reason: 'THE defect: it escaped unhandled');
      expect(find.text("Couldn't delete this package — $_other"), findsOneWidget);
      expect(reported.map((f) => f.origin), ['CoachPackagesScreen.deletePackage']);
      expect(find.text('Solo Session'), findsOneWidget, reason: 'the list stays');
    });

    testWidgets('positive control: a delete that works re-reads, says nothing',
        (tester) async {
      final reported = _sink();
      await open(tester);
      final before = reads;
      await delete(tester);
      expect(svc.deletes, 1);
      expect(reads, before + 1);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });

    Future<void> saveNew(WidgetTester tester) async {
      await tester.tap(find.text('New Package'));
      await tester.pumpAndSettle();
      // The editor's first field is the package name.
      await tester.enterText(find.byType(TextField).first, 'Strength Block');
      await tester.pump();
      final save = find.textContaining(RegExp(r'^Save '));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
    }

    testWidgets('a failed save is recorded, said, and the editor stays usable',
        (tester) async {
      final reported = _sink();
      await open(tester);
      svc.saveError = PostgrestException(message: 'SECRET_TABLE_X', code: 'XX000');
      await saveNew(tester);
      expect(tester.takeException(), isNull, reason: 'THE defect: it escaped unhandled');
      const msg = "Couldn't save this package — $_other";
      expect(_inSheet(find.text(msg)), findsOneWidget,
          reason: 'r2 F1: said inside the sheet, not on the Scaffold under it');
      expect(find.byType(SnackBar), findsNothing);
      expect(_liveRegion(tester, find.text(msg)), isTrue);
      expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
      expect(reported.map((f) => f.origin), ['CoachPackagesScreen._PackageEditor._save']);
      // Still open, not spinning: the Save button is back.
      expect(find.textContaining(RegExp(r'^Save ')), findsOneWidget,
          reason: 'THE defect: the Save button spun for good');
      expect(find.text('Strength Block'), findsOneWidget, reason: 'what was typed stays');

      // The next attempt clears it while in flight; a success closes the sheet.
      svc
        ..saveError = null
        ..hold = Completer<void>();
      final save = find.textContaining(RegExp(r'^Save '));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(find.text(msg), findsNothing, reason: 'r2 F1: cleared on the next attempt');
      svc.hold!.complete();
      await tester.pumpAndSettle();
      expect(svc.saves, 2);
      expect(find.textContaining(RegExp(r'^Save ')), findsNothing);
      expect(reported, hasLength(1));
    });

    testWidgets('negative control: a fresh editor says no failure', (tester) async {
      final reported = _sink();
      await open(tester);
      await tester.tap(find.text('New Package'));
      await tester.pumpAndSettle();
      expect(_inSheet(find.textContaining(RegExp(r'^Save '))), findsOneWidget);
      expect(_inSheet(find.textContaining("Couldn't")), findsNothing);
      expect(reported, isEmpty);
    });

    testWidgets('positive control: a save that works closes the editor', (tester) async {
      final reported = _sink();
      await open(tester);
      await saveNew(tester);
      expect(svc.saves, 1);
      expect(find.textContaining(RegExp(r'^Save ')), findsNothing);
      expect(reported, isEmpty);
    });
  });
  // P0-FL-53b r3 (re-review UX N1 / QA): the failure line added in r2 must
  // still fit. The Add-slot sheet was a plain Column: on a short phone or at
  // large text, the extra line could overflow or push Publish Slot off screen.
  // Matrix: 320/360/390/430dp (each with a phone-like height) x 1.0/1.3/2.0.
  group('Fits after a failure', () {
    const sizes = {320: 568.0, 360: 640.0, 390: 844.0, 430: 932.0};
    const scales = [1.0, 1.3, 2.0];

    // Overflow errors raised anywhere on screen. The screens UNDER the sheet
    // (slot cards, the video form) have their own, older overflows that this
    // package does not touch (listed as follow-ups); only overflows of a Flex
    // inside the surface under test fail these tests.
    List<String> overflows(WidgetTester tester) {
      final seen = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) {
        final text = d.toString();
        if (text.contains('overflowed by')) {
          seen.add(text);
        } else {
          previous?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = previous);
      return seen;
    }

    // The overflow messages that name a RenderFlex inside [surface].
    List<String> overflowsIn(WidgetTester tester, List<String> seen, Finder surface) {
      final ids = tester
          .renderObjectList(find.descendant(of: surface, matching: find.byType(Flex)))
          .map(describeIdentity)
          .toSet();
      return [
        for (final e in seen)
          if (ids.any((id) => e.contains('$id ') || e.contains('$id\n') || e.contains('$id:'))) e
      ];
    }

    void phone(WidgetTester tester, int w, double h, double scale) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = Size(w.toDouble(), h);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    for (final MapEntry(key: w, value: h) in sizes.entries) {
      for (final scale in scales) {
        testWidgets('Add-slot sheet with its failure line, ${w}dp at ${scale}x',
            (tester) async {
          _server.failing = {'coach_availability'};
          _sink();
          final seen = overflows(tester);
          phone(tester, w, h, scale);
          await tester.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Add Slot').first);
          await tester.tap(find.text('Add Slot').first);
          await tester.pumpAndSettle();
          await tester.ensureVisible(_inSheet(find.text('Publish Slot')));
          await tester.pumpAndSettle();
          await tester.tap(_inSheet(find.text('Publish Slot')));
          await tester.pumpAndSettle();
          expect(overflowsIn(tester, seen, find.byType(BottomSheet)), isEmpty,
              reason: 'the Add-slot sheet does not overflow with its failure line');
          const msg = "Couldn't save this time slot — $_other";
          await tester.ensureVisible(_inSheet(find.text(msg)));
          await tester.pumpAndSettle();
          expect(_inSheet(find.text(msg)).hitTestable(), findsOneWidget,
              reason: 'the failure line can be brought on screen');
          await tester.ensureVisible(_inSheet(find.text('Publish Slot')));
          await tester.pumpAndSettle();
          expect(_inSheet(find.text('Publish Slot')).hitTestable(), findsOneWidget,
              reason: 'Publish Slot stays reachable for a retry');
          expect(tester.getSize(find.ancestor(
                  of: find.text('Publish Slot'), matching: find.byType(ElevatedButton))).height,
              greaterThanOrEqualTo(44));
          expect(overflowsIn(tester, seen, find.byType(BottomSheet)), isEmpty);
        });

        testWidgets('Video Done view, not notified, ${w}dp at ${scale}x',
            (tester) async {
          _server.failing = {'notifications'};
          _sink();
          final seen = overflows(tester);
          phone(tester, w, h, scale);
          await tester.pumpWidget(const MaterialApp(
              home: CoachVideoResponseScreen(clientId: 'client-1', clientName: 'Jamie')));
          await tester.enterText(find.byType(TextField), 'Great week — keep the tempo.');
          // ignore: avoid_dynamic_calls
          (tester.state(find.byType(CoachVideoResponseScreen)) as dynamic).setState(() {});
          await tester.pump();
          await tester.ensureVisible(find.text('Send to Client'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Send to Client'));
          await tester.pumpAndSettle();
          final done = find.ancestor(of: find.text('Video Sent!'), matching: find.byType(Scaffold));
          expect(overflowsIn(tester, seen, done), isEmpty,
              reason: 'the Done view does not overflow with the not-notified line');
          const line = "Your response is saved, but Jamie wasn't notified — let them know another way.";
          await tester.ensureVisible(find.text(line));
          await tester.pumpAndSettle();
          expect(find.text(line).hitTestable(), findsOneWidget);
          await tester.ensureVisible(find.text('Done'));
          await tester.pumpAndSettle();
          expect(find.text('Done').hitTestable(), findsOneWidget);
          expect(overflowsIn(tester, seen, done), isEmpty);
        });
      }
    }
  });
}
