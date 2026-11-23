import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/coach/presentation/coach_marketplace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-47 — a coach's reviews that could not be read were shown as "no
// reviews".
//
// coachReviewsProvider ended `catch (_) { return []; }`, so a failed read of
// `coach_reviews` (or of the reviewers' public profiles) reached the reviews
// sheet on the marketplace coach profile as an empty list, and a member was
// told "No reviews yet. Be the first after you work together!" about a coach
// who may have dozens. The provider now records the failure and rethrows; the
// sheet says "Couldn't load reviews — <next step>" with a busy-aware Try again.
// A real empty list keeps its copy.
//
// HOW TO SEE IT FAIL: `git checkout 185261e -- lib/features/coach/domain/
// coach_provider.dart lib/features/coach/presentation/
// coach_marketplace_screen.dart` — the failure, network, retry and busy tests
// fail; the empty and success tests pass.

const _uid = '00000000-0000-4000-8000-0000000f1047';
const _coach = '00000000-0000-4000-8000-00000000c047';
const _ana = '00000000-0000-4000-8000-00000000a047';

const _emptyCopy = 'No reviews yet. Be the first after you work together!';
const _other = "Couldn't load reviews — try again in a moment. "
    'If it keeps happening, contact support.';
const _network = "Couldn't load reviews — check your connection and try again.";
const _reviewText = 'Changed how I train.';

enum _Fail { none, server, network }

class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);

  _Fail reviewsRead = _Fail.none;
  int reviewReads = 0;
  Completer<void>? readGate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' &&
        request.url.path.endsWith('/rest/v1/coach_reviews')) {
      reviewReads++;
      if (readGate != null) await readGate!.future;
      switch (reviewsRead) {
        case _Fail.network:
          throw http.ClientException('Connection refused', request.url);
        case _Fail.server:
          return http.StreamedResponse(
              Stream.value('{"message":"refused","code":"XX000"}'.codeUnits),
              500,
              request: request,
              headers: {'content-type': 'application/json'});
        case _Fail.none:
          break;
      }
    }
    return super.send(request);
  }
}

void main() {
  late _Server server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    server.reviewsRead = _Fail.none;
    server.reviewReads = 0;
    server.readGate = null;
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  void seedOneReview() {
    server.reads['coach_reviews'] = [
      {
        'rating': 5,
        'review_text': _reviewText,
        'created_at': '2026-11-01T10:00:00Z',
        'client_id': _ana,
      }
    ];
    server.reads['public_profiles'] = [
      {'id': _ana, 'first_name': 'Ana', 'last_name': 'Ruiz', 'avatar_url': null}
    ];
  }

  group('coachReviewsProvider', () {
    test('a failed read is an error, recorded — not an empty list', () async {
      server.reviewsRead = _Fail.server;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(coachReviewsProvider(_coach), (_, __) {});

      await expectLater(c.read(coachReviewsProvider(_coach).future),
          throwsA(isA<PostgrestException>()),
          reason: 'THE defect: [] made a failure read as "no reviews"');
      expect(origins(), contains('coachReviewsProvider'));
    });

    test('a coach with no reviews is still an empty list', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(await c.read(coachReviewsProvider(_coach).future), isEmpty);
      expect(reported, isEmpty);
    });
  });

  group('reviews sheet', () {
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> openSheet(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showCoachReviewsSheet(context, _coach, 'Coach Kim'),
                child: const Text('Open reviews'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('Open reviews'));
      await settle(t);
    }

    testWidgets('a failed load says so, never "No reviews yet"', (t) async {
      final semantics = t.ensureSemantics();
      server.reviewsRead = _Fail.server;
      await openSheet(t);

      expect(find.text(_emptyCopy), findsNothing,
          reason: 'a failure shown as empty says the coach has no reviews');
      expect(find.text(_other), findsOneWidget,
          reason: 'the server answered: try again later, not "check connection"');
      expect(find.text(_network), findsNothing);
      expect(find.textContaining('refused'), findsNothing,
          reason: 'exception text is never shown');
      expect(find.bySemanticsLabel('Try again, load reviews'), findsOneWidget);
      expect(origins(), contains('coachReviewsProvider'));

      // The message is a live region.
      final live = t.getSemantics(find.text(_other));
      expect(live.flagsCollection.isLiveRegion, isTrue);

      final button = find.ancestor(
          of: find.text('Try again'), matching: find.byType(TextButton));
      expect(t.getSize(button).height, greaterThanOrEqualTo(44));
      expect(t.getSize(button).width, greaterThanOrEqualTo(44));
      semantics.dispose();
    });

    testWidgets('a connection failure gets the connection hint', (t) async {
      server.reviewsRead = _Fail.network;
      await openSheet(t);
      // postgrest-dart retries a GET that throws (1 s + 2 s + 4 s on the fake
      // clock); advance past it.
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(seconds: 1));
      }

      expect(find.text(_network), findsOneWidget);
      expect(find.text(_other), findsNothing);
      expect(find.text(_emptyCopy), findsNothing);
    });

    testWidgets('Try again re-reads once while busy, then shows the reviews',
        (t) async {
      final semantics = t.ensureSemantics();
      server.reviewsRead = _Fail.server;
      await openSheet(t);
      expect(find.text(_other), findsOneWidget);

      server.reviewsRead = _Fail.none;
      seedOneReview();
      server.readGate = Completer<void>();
      final before = server.reviewReads;
      await t.tap(find.text('Try again'));
      await t.pump(const Duration(milliseconds: 50));
      expect(server.reviewReads, before + 1);

      // In flight: the notice stays and the control cannot fire again.
      expect(find.text(_other), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.bySemanticsLabel('Loading reviews'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Loading reviews'),
          warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 50));
      expect(server.reviewReads, before + 1, reason: 'no double fire');

      server.readGate!.complete();
      await settle(t);
      expect(find.text(_reviewText), findsOneWidget,
          reason: 'the re-read succeeded: the review is shown');
      expect(find.text(_other), findsNothing);
      semantics.dispose();
    });

    testWidgets('a coach with no reviews keeps the empty copy', (t) async {
      await openSheet(t);
      expect(find.text(_emptyCopy), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });
  });
}
