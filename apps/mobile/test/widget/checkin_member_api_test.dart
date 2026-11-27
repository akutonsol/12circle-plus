import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/checkins/data/models/checkin_model.dart';
import 'package:circle_fitness/features/checkins/data/weekly_checkin_service.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_hub.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_known.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_detail_screen.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_hub_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/owned_writes_postgrest.dart';
import '../support/owner_harness.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59c round 2 · the pieces the owner tests rest on. On their own file
// because the names do not exist at 6f8c693: there this does not compile, and
// the behaviour is shown failing by the *_owner_edges tests.

void main() {
  late OwnedWritesPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = OwnedWritesPostgrest();
    await initTwoMemberSupabase(server);
  });
  setUp(() async {
    await signInAs(memberA);
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  group('a value and its owner', () {
    final held = OwnedRows([1], memberA);
    String? asA() => memberA;
    String? asB() => memberB;
    final error = AsyncError<List<int>>('boom', StackTrace.empty);

    // Every state riverpod can hold A's rows in, refresh or not.
    final states = <String, AsyncValue<List<int>>>{
      'data': AsyncData(held),
      'a refresh': const AsyncLoading<List<int>>().copyWithPrevious(AsyncData(held)),
      'a reload': const AsyncLoading<List<int>>()
          .copyWithPrevious(AsyncData(held), isRefresh: false),
      'a failed refresh': error.copyWithPrevious(AsyncData(held)),
      'a failed reload':
          error.copyWithPrevious(AsyncData(held), isRefresh: false),
    };
    states.forEach((name, state) {
      test('$name: kept for the owner, gone for anyone else', () {
        expect(state.hasValue, isTrue, reason: 'premise');
        expect(heldFor(state, asA), same(state));
        for (final who in [asB, () => null]) {
          final other = heldFor(state, who);
          expect(other.hasValue, isFalse);
          expect(other.hasError, state.hasError,
              reason: 'a failure is still a failure');
          expect(other is AsyncData, isFalse, reason: 'not "empty" either');
        }
      });
    });

    test('nothing held is left alone, and nobody is asked for', () {
      for (final s in <AsyncValue<List<int>>>[const AsyncLoading(), error]) {
        expect(heldFor(s, () => fail('asked')), same(s));
      }
    });

    test('the providers tag what they read', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(coachSubmittedCheckinsProvider, (_, __) {});
      c.listen(checkinHistoryProvider, (_, __) {});
      expect(
          await c.read(coachSubmittedCheckinsProvider.future),
          isA<OwnedRows<Map<String, dynamic>>>()
              .having((r) => r.owner, 'owner', memberA));
      expect(
          await c.read(checkinHistoryProvider.future),
          isA<OwnedRows<WeeklyCheckin>>()
              .having((r) => r.owner, 'owner', memberA));
    });

    test('the owner is taken before the read, not after it', () async {
      final hold = Completer<void>();
      final rows = ownedRead(() async {
        await hold.future;
        return [1];
      });
      await signInAs(memberB);
      hold.complete();
      expect((await rows as OwnedRows).owner, memberA);
    });
  });

  group('the check-in that is open', () {
    MemberCheckin checkin(String member, {String note = 'n'}) => MemberCheckin(
          memberId: member,
          id: 'w41',
          weekNumber: 41,
          weekStartDate: DateTime(2026, 11, 16),
          status: CheckinStatus.submitted,
          responses: [CheckinResponse(questionId: 'notes', answer: note)],
          overallScore: 0,
        );

    testWidgets("another member's selection is not shown", (t) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedCheckinProvider.notifier).state =
          checkin(memberB, note: 'private to B');
      await t.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CheckinDetailScreen())));
      await settleReal(t);
      expect(find.text('private to B'), findsNothing);
      expect(find.text('Open a check-in from your history'), findsOneWidget);
      await closeApp(t);
    });

    test('a held history row stands in only for the same member\'s week', () {
      final selected = checkin(memberA, note: 'mine');
      final other = checkin(memberB, note: 'theirs');
      final newer = checkin(memberA, note: 'newer');
      expect(latestOf(selected, AsyncData([other])), same(selected));
      expect(latestOf(selected, AsyncData([other, newer])), same(newer),
          reason: 'CONTROL: the re-read still reaches the open week');
    });
  });

  group('the service', () {
    Future<bool> submit(StillHolds holds) => WeeklyCheckinService()
        .submitWeeklyCheckin(
            mood: 3, energy: 3, stress: 2, sleepHoursAvg: 7,
            expectedUid: memberA, stillHolds: holds);

    test('the service: a failure is unknown and recorded; the next answer clears '
        'it; a missing row is not done', () async {
      final service = WeeklyCheckinService();
      server.fails.add('GET weekly_checkins:$memberA');
      expect(await service.weekStatus(), CheckinKnown.unknown);
      expect(service.weekStatusError, isA<PostgrestException>());
      expect(origins(), ['WeeklyCheckinService.weekStatus']);
      server.fails.clear();
      expect(await service.weekStatus(), CheckinKnown.notDone);
      expect(service.weekStatusError, isNull);
    });

    test('the form was dropped (A left and came back) during a read: not saved',
        () async {
      var holds = true;
      final hold =
          server.holds['GET weekly_checkins:$memberA'] = Completer<void>();
      final answer = submit( () => holds);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      holds = false;
      hold.complete();
      expect(await answer, isFalse);
      expect(server.log.where((a) => a.method != 'GET'), isEmpty);
      expect(origins(), ['WeeklyCheckinService.submitWeeklyCheckin']);
    });

    test('POSITIVE CONTROL: the form still held: saved once, as the member',
        () async {
      expect(await submit( () => true), isTrue);
      expect(server.sent('POST', 'weekly_checkins').single.who, memberA);
      expect(reported, isEmpty);
    });

  });
}
