import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/exercise_database/data/models/exercise_detail_model.dart';
import 'package:circle_fitness/features/exercise_database/domain/exercise_database_provider.dart';
import 'package:circle_fitness/features/exercise_database/presentation/exercise_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/pump_until.dart';
import '../support/row_checking_postgrest.dart';
import '../support/rpc_answering_postgrest.dart';

// P0-FL-57a round 2 (S-57a-7) · a failed enrichment, or a failed slug
// back-fill, was recorded by the service AND by the screen. Here the screen
// runs on the REAL service: each failure is recorded once, still said, and
// none of the backend's text is shown.
//
// HOW TO SEE IT FAIL: `git checkout 136b745 -- …/exercise_detail_screen.dart`.

const _uid = '00000000-0000-4000-8000-0000000f505a';
const _leak = 'upstream 429: quota exceeded for key SECRET';
const _generic =
    'try again in a moment. If it keeps happening, contact support.';
const _connection = 'check your connection and try again.';

class _Server extends RpcAnsweringPostgrest {
  _Server() : super(_uid);

  /// How the edge function answers: an HTTP status, or null = unreachable.
  int? status = 200;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/functions/v1/enrich-exercise')) {
      final s = status;
      if (s == null) {
        throw http.ClientException('Failed host SECRET', request.url);
      }
      return http.StreamedResponse(
          Stream.value(utf8.encode(
              jsonEncode(s == 200 ? {'ok': true} : {'error': _leak}))),
          s,
          request: request,
          headers: {'content-type': 'application/json'});
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
    server.status = 200;
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  List<String> origins() => reported.map((f) => f.origin).toList();

  Future<void> enrich(WidgetTester tester, {String? slug}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ExerciseDetailScreen()),
      GoRoute(
          path: '/exercise-detail',
          builder: (_, __) => const Scaffold(body: Text('REOPENED DETAIL'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider
            .overrideWithValue(Supabase.instance.client.auth.currentUser),
        currentUserProfileProvider
            .overrideWith((ref) async => {'id': _uid, 'role': 'admin'}),
        selectedExerciseDetailProvider.overrideWith((ref) =>
            ExerciseDetail.fromJson({
              'id': 'ex-1',
              'name': 'Goblet Squat',
              if (slug != null) 'slug': slug,
            })),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(reported, isEmpty, reason: 'premise');
    await tester.tap(find.text('Enrich with AI'));
    await tester.pump();
  }

  Future<void> said(WidgetTester tester, String text) async {
    await pumpUntil(tester, () => find.text(text).evaluate().isNotEmpty,
        what: '"$text"', step: const Duration(milliseconds: 20));
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.text('Coaching content generated ✨'), findsNothing);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('a refused enrichment is said, and recorded once',
      (tester) async {
    server.status = 502;
    await enrich(tester, slug: 'goblet-squat');
    await said(tester, "Couldn't generate coaching content — $_generic");
    expect(origins(), ['CustomExerciseService.enrichWithAI'],
        reason: 'THE defect: recorded twice');
    expect('${(reported.single.error as FunctionException).details}',
        contains(_leak));
    await unmount(tester);
  });

  testWidgets('no connection: the connection hint, recorded once',
      (tester) async {
    server.status = null;
    await enrich(tester, slug: 'goblet-squat');
    await said(tester, "Couldn't generate coaching content — $_connection");
    expect(origins(), ['CustomExerciseService.enrichWithAI']);
    await unmount(tester);
  });

  testWidgets('a refused slug back-fill is said, and recorded once',
      (tester) async {
    server.mode = WriteMode.serverError;
    await enrich(tester);
    await said(
        tester, "Couldn't prepare this exercise for AI enrichment — $_generic");
    expect(origins(), ['CustomExerciseService.updateExercise'],
        reason: 'THE defect: recorded twice');
    await unmount(tester);
  });

  testWidgets('positive control: it works, and nothing is recorded',
      (tester) async {
    server.reads['custom_exercises'] = {'id': 'ex-1', 'name': 'Goblet Squat'};
    await enrich(tester, slug: 'goblet-squat');
    await pumpUntil(
        tester, () => find.text('REOPENED DETAIL').evaluate().isNotEmpty,
        what: 'the refreshed page', step: const Duration(milliseconds: 20));
    expect(reported, isEmpty);
    await unmount(tester);
  });
}
