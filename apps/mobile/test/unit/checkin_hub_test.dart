import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/checkins/data/models/checkin_model.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_hub.dart';

/// FIT-023 · Check-in hub — "`/checkins` · status and history".
///
/// ── THE RULE ───────────────────────────────────────────────────────────────
/// Same class as `/profile`, `/home`, `/train` and FIT-027: **a failed history
/// read must never be drawn as "no history".** Under a heading that says
/// history, an absence is an answer — it tells a client who has checked in for
/// thirteen weeks that they never have. `WeeklyCheckinService` ended
/// `catch (e) { return []; }`, so that is what it would have said.
///
/// ── AND THE ONE THING THE ANCHOR ASKS FOR THAT IS NOT BUILT ────────────────
/// The design draws `Week 13 · Energy steady · Nadia replied`. Two of those
/// three come straight from the data. **"Energy steady" does not.** The stored
/// value is 1–5, and turning it into Low / Steady / Strong means choosing
/// thresholds on a number a coach reads — the same decision FIT-004's
/// difficulty mapping is blocked on. The row states `Energy 3 of 5` instead.
/// Stating a value and interpreting it are different acts, and only one of
/// them is this programme's to perform.
void main() {
  WeeklyCheckin week({
    int number = 13,
    CheckinStatus status = CheckinStatus.submitted,
    CoachFeedback? feedback,
    List<CheckinResponse> responses = const [],
  }) =>
      WeeklyCheckin(
        id: 'w$number',
        weekNumber: number,
        weekStartDate: DateTime(2026, 9, 7),
        status: status,
        responses: responses,
        feedback: feedback,
        overallScore: 0.8,
        submittedAt: DateTime(2026, 9, 13),
      );

  CoachFeedback reply({String coach = 'Nadia'}) => CoachFeedback(
        message: 'Good week.',
        recommendations: const [],
        reviewedAt: DateTime(2026, 9, 14),
        coachName: coach,
      );

  CheckinResponse energy(Object? value) =>
      CheckinResponse(questionId: 'energy_level', answer: value);

  group('FIT-023 a failed history read is never "no history"', () {
    test('a failure is `failed`, not `empty`', () {
      final r = historyFrom(
          AsyncError<List<WeeklyCheckin>>(Exception('x'), StackTrace.empty));
      expect(r.state, CheckinHistoryState.failed);
      expect(r.weeks, isEmpty);
    });

    test('a failure carrying stale weeks contributes none of them', () {
      final stale =
          AsyncError<List<WeeklyCheckin>>(Exception('x'), StackTrace.empty)
              .copyWithPrevious(AsyncData([week()]));
      expect(stale.valueOrNull, isNotNull, reason: 'guard the premise');
      expect(historyFrom(stale).weeks, isEmpty);
    });

    test('a genuinely empty history is `empty`, which is a real answer', () {
      // A client who has never checked in should not be shown a failure.
      expect(historyFrom(const AsyncData<List<WeeklyCheckin>>([])).state,
          CheckinHistoryState.empty);
    });

    test('loading is neither, and a refresh keeps what it has', () {
      expect(historyFrom(const AsyncLoading<List<WeeklyCheckin>>()).state,
          CheckinHistoryState.loading);
      final refreshing = const AsyncLoading<List<WeeklyCheckin>>()
          .copyWithPrevious(AsyncData([week()]));
      expect(historyFrom(refreshing).state, CheckinHistoryState.data);
    });

    test('the list is capped', () {
      final r = historyFrom(
          AsyncData([for (var i = 1; i <= 20; i++) week(number: i)]));
      expect(r.weeks, hasLength(checkinHistoryLimit));
      expect(r.weeks.first.weekNumber, 1, reason: 'order is preserved');
    });
  });

  group('FIT-023 the row', () {
    test('reads "Week 13 · Energy 3 of 5 · Nadia replied"', () {
      expect(
          historyLine(week(responses: [energy(3)], feedback: reply())),
          'Week 13 · Energy 3 of 5 · Nadia replied');
    });

    test('a week awaiting a reply says so, in the package\'s own words', () {
      // "Awaiting reply" is FIT-025's screen name — not invented here.
      expect(historyLine(week(responses: [energy(4)])),
          'Week 13 · Energy 4 of 5 · Awaiting reply');
    });

    test('a PENDING week is not awaiting anything — nothing was sent', () {
      // A check-in that has not been submitted and one whose coach has not yet
      // answered are different things, and the row must not merge them.
      expect(replyLabel(week(status: CheckinStatus.pending)), isNull);
      expect(historyLine(week(status: CheckinStatus.pending)), 'Week 13');
    });

    test('feedback with no coach name still reports a reply', () {
      expect(replyLabel(week(feedback: reply(coach: '  '))), 'Replied');
    });

    test('a week with no energy answer omits that part rather than guessing',
        () {
      // "Energy 0 of 5" would be reporting a value nobody gave.
      expect(energyLabel(week()), isNull);
      expect(historyLine(week(feedback: reply())), 'Week 13 · Nadia replied');
    });

    test('an out-of-range or unparseable energy value is omitted', () {
      for (final bad in <Object?>[0, 6, -1, 'steady', null, {'a': 1}]) {
        expect(energyLabel(week(responses: [energy(bad)])), isNull,
            reason: 'energy=$bad must not be rendered');
      }
    });

    test('a stored double is reported as a whole number', () {
      expect(energyLabel(week(responses: [energy(3.4)])), 'Energy 3 of 5');
      expect(energyLabel(week(responses: [energy(3.6)])), 'Energy 4 of 5');
    });

    test('a numeric string is accepted — PostgREST types drift', () {
      expect(energyLabel(week(responses: [energy('5')])), 'Energy 5 of 5');
    });

    test('the row NEVER interprets energy into Low / Steady / Strong', () {
      // The anchor draws "Energy steady". Producing it means choosing
      // thresholds on a coach-facing number, which is OD-16. If this assertion
      // ever fails, that decision was made silently.
      for (var v = 1; v <= 5; v++) {
        final line = historyLine(week(responses: [energy(v)]));
        for (final word in ['Low', 'Steady', 'Strong', 'steady']) {
          expect(line, isNot(contains(word)), reason: 'energy=$v produced "$line"');
        }
      }
    });
  });

  test('FIT-023 the failure lines follow the shipped pattern', () {
    expect(checkinHistoryFailure, 'Could not load check-ins');
    expect(checkinSessionsFailure, 'Could not load sessions');
    for (final l in [checkinHistoryFailure, checkinSessionsFailure]) {
      expect(l, startsWith('Could not load'));
      expect(l, isNot(contains('Exception')));
    }
  });

  group('FIT-004 the submit button carries the coach\'s name, or nothing', () {
    // The anchor draws "Send to Nadia". The name is real data, so using it
    // invents nothing — but the two failure modes either side of it are the
    // ones this repository has already been bitten by.
    const fallback = 'Submit Check-In';

    test('a loaded coach is addressed by name', () {
      expect(
          checkinSubmitLabel(
              const AsyncData<Map<String, dynamic>?>({'first_name': 'Nadia'})),
          'Send to Nadia');
    });

    test('a FAILED lookup does not address a coach', () {
      // This is /profile's "No coach assigned yet" collapse turned inside out:
      // there a failure claimed the client had no coach, here it would claim
      // they have one. Both are the screen answering a question it cannot.
      expect(
          checkinSubmitLabel(AsyncError<Map<String, dynamic>?>(
              Exception('offline'), StackTrace.empty)),
          fallback);
    });

    test('a failure carrying a stale coach does not use it', () {
      final stale = AsyncError<Map<String, dynamic>?>(
              Exception('x'), StackTrace.empty)
          .copyWithPrevious(
              const AsyncData<Map<String, dynamic>?>({'first_name': 'Nadia'}));
      expect(stale.valueOrNull, isNotNull, reason: 'guard the premise');
      expect(checkinSubmitLabel(stale), fallback);
    });

    test('no coach falls back to the label this screen already ships', () {
      // A client with no coach must not be shown a button addressed to nobody.
      expect(checkinSubmitLabel(const AsyncData<Map<String, dynamic>?>(null)),
          fallback);
    });

    test('a coach with a blank or missing first name falls back too', () {
      expect(
          checkinSubmitLabel(
              const AsyncData<Map<String, dynamic>?>({'first_name': '   '})),
          fallback);
      expect(checkinSubmitLabel(const AsyncData<Map<String, dynamic>?>({})),
          fallback);
    });

    test('while loading, the fallback — not a flash of a name', () {
      expect(checkinSubmitLabel(const AsyncLoading<Map<String, dynamic>?>()),
          fallback);
    });

    test('the name is trimmed, not padded into the sentence', () {
      expect(
          checkinSubmitLabel(
              const AsyncData<Map<String, dynamic>?>({'first_name': ' Nadia '})),
          'Send to Nadia');
    });
  });

  test('there is exactly ONE selectedCheckinProvider', () {
    // A second one was briefly declared in `checkin_hub.dart` while building
    // FIT-024, next to the one that already existed in `checkin_provider.dart`.
    // Nothing failed to compile: `CheckinCard` set one and the detail screen
    // read the other, so tapping a check-in card would have opened an empty
    // screen. Parallel state with the same name is invisible to the analyzer
    // and to every test that only exercises one path.
    final defs = Directory('lib/features/checkins')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) =>
            f.readAsStringSync().contains('selectedCheckinProvider = '))
        .map((f) => f.path)
        .toList();

    expect(defs, hasLength(1),
        reason: 'two providers of the same name split the state between the '
            'screens that write it and the screens that read it. Found: $defs');
    expect(defs.single, endsWith('domain/checkin_provider.dart'));
  });
}
