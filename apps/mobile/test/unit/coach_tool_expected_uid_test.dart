import 'dart:typed_data';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:circle_fitness/features/exercise_database/data/custom_exercise_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_tools_server.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59d · the `expectedUid` a coach tool passes — who its form, sheet or
// dialog was opened by — is who the write is for: for anyone else signed in,
// nothing is sent, and that is recorded once (W8, W9, W10, W12).
//
// HOW TO SEE IT FAIL: the parameter is new, so a82f993 does not compile it;
// make `_accountChanged` return false / `_requireAccount` return.

void main() {
  final server = CoachToolsServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Matcher accountChanged() => isA<StateError>().having(
      (e) => e.message, 'message', contains('the signed-in account changed'));
  final accountMessage = contains('the signed-in account changed');

  group('CoachRelationshipService', () {
    late CoachRelationshipService svc;
    setUp(() => svc = CoachRelationshipService());

    test("setGlobalPrice: for anyone but the coach expected, nothing is sent",
        () async {
      await signInAs(memberB);
      await expectLater(svc.setGlobalPrice(150, expectedUid: memberA),
          throwsA(accountChanged()));
      expect(server.log, isEmpty);
    });

    test('setGlobalPrice: the coach expected saves their own row (control)', () async {
      await svc.setGlobalPrice(150, expectedUid: memberA);
      await svc.setGlobalPrice(160);
      expect(server.writes.map((s) => s.query), everyElement(contains('id=eq.$memberA')));
      expect(server.writes, hasLength(2));
    });

    test("cancelCoach: for anyone but the client asked, nothing is sent", () async {
      await signInAs(memberB);
      await expectLater(
          svc.cancelCoach('coach-1', 'client_cancelled', null, expectedUid: memberA),
          throwsA(accountChanged()));
      expect(server.log, isEmpty);
    });

    test('cancelCoach: the client asked, after a token refresh (control)', () async {
      await refreshSession();
      await svc.cancelCoach('coach-1', 'client_cancelled', null, expectedUid: memberA);
      expect(server.writes.map((s) => s.table), ['coach_client_relationships', 'notifications']);
    });
  });

  group('CustomExerciseService', () {
    late CustomExerciseService svc;
    setUp(() => svc = CustomExerciseService());

    final single = <String, Future<Object?> Function(String? owner)>{
      'upsertCoachOverlay': (o) => svc.upsertCoachOverlay('ex-1', note: 'n', expectedUid: o),
      'createCoachingPack': (o) => svc.createCoachingPack('Squat', ['Brace'], expectedUid: o),
      'uploadCoachVoice': (o) => svc.uploadCoachVoice('ex-1', Uint8List(4), expectedUid: o),
      'setCoachVoice': (o) => svc.setCoachVoice('ex-1', 'voice/$memberA/x.m4a', 900, null,
          expectedUid: o),
      'clearCoachVoice': (o) => svc.clearCoachVoice('ex-1', expectedUid: o),
    };
    single.forEach((name, call) {
      test('$name: as B for A — nothing is sent, recorded once', () async {
        await signInAs(memberB);
        final out = await call(memberA);
        expect(out, anyOf(isNull, isFalse));
        expect(server.log, isEmpty);
        expect(reported.map((f) => f.origin), ['CustomExerciseService.$name']);
        expect('${svc.lastError}', accountMessage);
        expect(svc.recordedError, same(svc.lastError));
      });
      test('$name: signed out is a failure too', () async {
        await signOut();
        expect(await call(memberA), anyOf(isNull, isFalse));
        expect(server.log, isEmpty);
        expect(reported, hasLength(1));
      });
      test('$name: the same coach, after a token refresh (control)', () async {
        await refreshSession();
        expect(await call(memberA), anyOf(isTrue, isNotNull));
        expect(await call(null), anyOf(isTrue, isNotNull), reason: 'no owner given');
        expect(server.log.map((s) => s.who).toSet(), {memberA});
        expect(reported, isEmpty);
      });
    });
  });
}
