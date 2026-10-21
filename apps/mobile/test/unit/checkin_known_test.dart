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

  // ── [SOURCE] that the service and the screen are wired to the rules ──────
  //
  // `CheckinService` holds `Supabase.instance.client`, so its catch paths
  // cannot be driven in a widget test without a Supabase harness (OD-47).
  // These prove the wiring, not the behaviour, and say so.
  group('[SOURCE] the service no longer answers "no" when it failed', () {
    late String src;
    setUpAll(() {
      src = File('lib/features/checkins/data/checkin_service.dart')
          .readAsStringSync()
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i < 0 ? l : l.substring(0, i);
          })
          .join('\n');
    });

    test('the two reads report unknown on failure', () {
      expect(src, contains('Future<CheckinKnown> hasCheckedInToday()'));
      expect(src, contains('Future<CheckinKnown> hasCheckedInThisWeek()'));
      expect('CheckinKnown.unknown'.allMatches(src).length, greaterThanOrEqualTo(2),
          reason: 'each read must have a failure arm that says unknown');
    });

    test('the streak reports null, not zero', () {
      expect(src, contains('Future<int?> getCheckinStreak()'));
      // The old failure arm.
      expect(
        RegExp(r'catch \(e\) \{\s*return 0;\s*\}').hasMatch(src),
        isFalse,
        reason: 'a failed streak read is reporting 0 again — a number the '
            'screen cannot support (F-15)',
      );
    });

    test('no read still answers a plain false on failure', () {
      expect(
        RegExp(r'catch \(e\) \{\s*return false;\s*\}').hasMatch(src),
        isFalse,
        reason: 'a failed read is claiming "not checked in" again',
      );
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
