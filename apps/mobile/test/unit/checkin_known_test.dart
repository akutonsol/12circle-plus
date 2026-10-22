import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/checkins/domain/checkin_known.dart';

// CON-01 (read side) · a failed check-in read answered "no".
//
//   Future<bool> hasCheckedInThisWeek() async {
//     try { … } catch (e) { return false; }   // "you have not checked in"
//   }
//   Future<int> getCheckinStreak() async {
//     try { … } catch (e) { return 0; }       // "your streak is 0"
//   }
//
// `false` and `0` are ANSWERS, and the service gave them when it had none.
//
// The registry's CON-01 is why this is not hypothetical: `public.checkins` is
// created by NO migration — `weekly_checkins` (000:146) is the real table —
// and seven Dart call sites read `checkins`. Whatever the right table turns
// out to be, a failing read must not come back as a confident negative.
//
// It does not stop at the display. `daily_checkin_screen` branches on it:
//
//   child: _alreadyDone ? _AlreadyDone(…) : <the whole check-in form>
//
// so a failed read showed the empty form to someone who had already checked in
// this week, and `_submit` wrote another one.

void main() {
  group('only a real "no" may open the form', () {
    test('unknown must not', () {
      expect(mayOfferCheckinForm(CheckinKnown.unknown), isFalse,
          reason: 'the form is how a duplicate weekly check-in gets written');
    });

    test('done must not', () {
      expect(mayOfferCheckinForm(CheckinKnown.done), isFalse);
    });

    test('notDone is the only one that may', () {
      expect(mayOfferCheckinForm(CheckinKnown.notDone), isTrue);
    });
  });

  group('only a real "yes" may claim it is done', () {
    test('unknown must not claim the week is finished either', () {
      expect(mayShowAlreadyDone(CheckinKnown.unknown), isFalse,
          reason: 'an unknown read must not answer in EITHER direction');
    });

    test('done does, notDone does not', () {
      expect(mayShowAlreadyDone(CheckinKnown.done), isTrue);
      expect(mayShowAlreadyDone(CheckinKnown.notDone), isFalse);
    });
  });

  test('unknown is genuinely a third state, not an alias', () {
    // If either predicate treated `unknown` as one of the other two, the whole
    // point is lost.
    expect(
      mayOfferCheckinForm(CheckinKnown.unknown) ||
          mayShowAlreadyDone(CheckinKnown.unknown),
      isFalse,
    );
    expect(CheckinKnown.values, hasLength(3));
  });

  group('the streak figure', () {
    test('a failed read has no number to show', () {
      // F-15: "a number the screen cannot support", the class of /train's
      // "0 workouts" and /home's "0%".
      expect(knownStreak(null), isNull);
    });

    test('a real zero also shows nothing, which the layout already did', () {
      expect(knownStreak(0), isNull);
    });

    test('a real streak is shown', () {
      expect(knownStreak(12), 12);
      expect(knownStreak(1), 1);
    });

    test('a negative is not a streak', () {
      expect(knownStreak(-3), isNull);
    });
  });

  // ── weeklyStreak — the pure rule that replaced the daily streak (PD-B01) ──
  group('weeklyStreak counts consecutive WEEKS, ending this week', () {
    // Wednesday 2026-03-18. Mondays: 03-16 (this week), 03-09, 03-02, 02-23.
    final now = DateTime(2026, 3, 18);
    DateTime mon(int m, int d) => DateTime(2026, m, d);

    test('no check-ins is a streak of zero', () {
      expect(weeklyStreak(const [], now), 0);
    });

    test('only this week is a streak of one', () {
      expect(weeklyStreak([mon(3, 16)], now), 1);
    });

    test('this week and three before it, unbroken, is four', () {
      expect(weeklyStreak([mon(3, 16), mon(3, 9), mon(3, 2), mon(2, 23)], now), 4);
    });

    test('not having checked in YET this week does not break the streak', () {
      // On a Wednesday, three straight weeks behind you and none yet today.
      expect(weeklyStreak([mon(3, 9), mon(3, 2), mon(2, 23)], now), 3);
    });

    test('a missed week ends it', () {
      // This week, skip 03-09, then two earlier: only this week counts.
      expect(weeklyStreak([mon(3, 16), mon(3, 2), mon(2, 23)], now), 1);
    });

    test('two weeks of silence is zero, however long the history', () {
      expect(weeklyStreak([mon(3, 2), mon(2, 23), mon(2, 16)], now), 0);
    });

    test('a check-in on any day of a week counts for that week', () {
      // Submitted on a Friday and a Sunday, not the Monday that keys the week.
      expect(weeklyStreak([DateTime(2026, 3, 20), DateTime(2026, 3, 15)], now), 2);
    });

    test('order and duplicates do not matter', () {
      // Unordered, with a duplicate: 03-16, 03-09, 03-02 are three straight weeks.
      expect(weeklyStreak([mon(3, 2), mon(3, 16), mon(3, 16), mon(3, 9)], now), 3);
    });

    test('a FUTURE week does not extend the streak', () {
      expect(weeklyStreak([mon(3, 23), mon(3, 9)], now), 1);
    });

    test('it counts straight across both clock changes of the year', () {
      // 2026-03-08 and 2026-11-01 are the US clock changes. A Duration of seven
      // 24-hour days lands at 23:00 the day before across either one, and the
      // set lookup then misses — so this is run under TZ=America/New_York in the
      // mutation check, since CI's UTC has no clock change to expose it.
      final spring = DateTime(2026, 3, 18);
      expect(weeklyStreak([for (var i = 0; i < 4; i++) DateTime(2026, 3, 16 - 7 * i)], spring), 4);
      final fall = DateTime(2026, 11, 4);
      expect(weeklyStreak([for (var i = 0; i < 4; i++) DateTime(2026, 11, 2 - 7 * i)], fall), 4);
    });
  });

  // ── [SOURCE] weeklyStreak must not step by a Duration ────────────────────
  //
  // The behavioural DST test above only bites in a timezone that HAS a clock
  // change, and CI runs UTC, which has none. Measured: replacing the
  // `DateTime(y, m, d - 7)` step with `subtract(Duration(days: 7))` passes every
  // test under TZ=UTC and fails four under TZ=America/New_York. So the
  // property is also asserted on the SOURCE, where it does not depend on where
  // the suite happens to run.
  test('[SOURCE] weeklyStreak steps with the date constructor, never a Duration', () {
    final src = File('lib/features/checkins/domain/checkin_known.dart')
        .readAsStringSync();
    final start = src.indexOf('int weeklyStreak(');
    expect(start, greaterThan(0), reason: 'weeklyStreak has gone');
    final body = src.substring(start).split('\n').takeWhile((l) => l != '}').join('\n');
    final code = body.split('\n').map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    }).join('\n');
    expect(code.contains('Duration('), isFalse,
        reason: 'a 24-hour Duration subtracted across a clock change lands at '
            '23:00 the previous day, the set lookup misses, and the streak '
            'silently resets for any member in a DST timezone');
    expect(code.contains('.subtract('), isFalse);
    expect(code, contains('day - 7'));
  });

  // ── [SOURCE] the live service and the screen are wired to the rules ──────
  //
  // `WeeklyCheckinService` holds `Supabase.instance.client`, so its catch paths
  // cannot be driven in a widget test without a Supabase harness (OD-47). These
  // prove the wiring, not the behaviour, and say so. They previously read the
  // retired CheckinService; the rules they assert were not retired with it.
  group('[SOURCE] the service no longer answers "no" when it failed', () {
    late String src;
    setUpAll(() {
      src = File('lib/features/checkins/data/weekly_checkin_service.dart')
          .readAsStringSync()
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i < 0 ? l : l.substring(0, i);
          })
          .join('\n');
    });

    /// The body of one method, up to the next member declaration.
    String body(String signature, String until) {
      final start = src.indexOf(signature);
      expect(start, greaterThan(0), reason: '$signature has gone');
      return src.substring(start, src.indexOf(until, start + signature.length));
    }

    test('the status read reports unknown on failure', () {
      final b = body('Future<CheckinKnown> weekStatus() async {',
          'Future<bool> submitWeeklyCheckin');
      expect(b, contains('CheckinKnown.unknown'),
          reason: 'the failure arm must say unknown, not "not done"');
    });

    test('the streak reports null, not zero', () {
      final b = body('Future<int?> getCheckinStreak() async {',
          'double _computeScore');
      expect(
        RegExp(r'catch \(e\) \{\s*(?:reportError\([^;]*\);\s*)?return 0;\s*\}')
            .hasMatch(b),
        isFalse,
        reason: 'a failed streak read is reporting 0 again — a number the '
            'screen cannot support (F-15)',
      );
      expect(b, contains('return null'));
    });

    test('no READ answers a plain false/0 on failure', () {
      final status = body('Future<CheckinKnown> weekStatus() async {',
          'Future<bool> submitWeeklyCheckin');
      expect(RegExp(r'catch \([^)]*\) \{\s*return (false|0);\s*\}')
          .hasMatch(status), isFalse,
          reason: 'a failed read is claiming "not checked in" again');
    });

    test('a failed SAVE is reported through the sink (rule O)', () {
      final b = body('Future<bool> submitWeeklyCheckin({', 'static bool needsCoachAttention');
      expect(b, contains("reportError('WeeklyCheckinService.submitWeeklyCheckin'"),
          reason: 'the retired service reported its save failure; that duty '
              'moved here and a silent `return false` loses it');
    });
  });

  group('[SOURCE] the screen does not open the form on an unknown read', () {
    late String src;
    setUpAll(() {
      src = File('lib/features/checkins/presentation/daily_checkin_screen.dart')
          .readAsStringSync()
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i < 0 ? l : l.substring(0, i);
          })
          .join('\n');
    });

    test('it branches through the rules, not a bare bool', () {
      expect(src, contains('mayShowAlreadyDone(_alreadyDone)'));
      expect(src, contains('mayOfferCheckinForm(_alreadyDone)'));
      expect(src, contains('_CheckinUnknown('),
          reason: 'an unknown read needs somewhere to go that is neither the '
              'form nor the done screen');
    });

    test('the streak figure goes through knownStreak', () {
      expect(src, contains('knownStreak(_streak)'));
    });
  });
}
