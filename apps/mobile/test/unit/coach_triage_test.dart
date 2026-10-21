import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/dashboard/domain/coach_triage.dart';

/// FIT-032 · the triage rules.
///
/// The board's four rows are sample clients — no test can conjure Amara Osei.
/// What IS testable is the shape each row takes, which of them fires, and the
/// three places a rule must refuse to speak: an unknown name, an unknown day
/// count, and a threshold nobody has chosen.

ClientSignals _c({
  String id = 'c1',
  String? name = 'Amara Osei',
  int? week,
  String? note,
  int? days,
  int? churn,
  int? until,
  String? on,
  bool hasNext = false,
  String? asked,
}) =>
    ClientSignals(
      clientId: id,
      clientName: name,
      unrepliedCheckinWeek: week,
      unrepliedCheckinNote: note,
      daysSinceLastSession: days,
      churnRisk: churn,
      daysUntilBlockEnds: until,
      blockEndsOn: on,
      hasNextBlock: hasNext,
      unansweredMessage: asked,
    );

List<TriageItem> _t(ClientSignals c, {int inactivity = 7, int horizon = 7}) =>
    triageFor(c, inactivityDays: inactivity, blockEndHorizonDays: horizon);

void main() {
  group('the four rows take the shape the board draws', () {
    test('Review — a check-in awaiting a reply, with what they wrote', () {
      final r = _t(_c(week: 14, note: 'travel next week')).single;
      expect(r.kind, TriageKind.review);
      expect(r.action, 'Review');
      expect(r.detail, 'Week 14 check-in · travel next week');
      expect(r.label, 'Amara Osei Week 14 check-in · travel next week Review');
    });

    test('At risk — the silence, counted', () {
      final r = _t(_c(name: 'Tomas Vidal', days: 9)).single;
      expect(r.kind, TriageKind.atRisk);
      expect(r.action, 'At risk');
      expect(r.label, 'Tomas Vidal No sessions logged in 9 days At risk');
    });

    test('Assign — a block ending with nothing after it', () {
      final r = _t(_c(name: 'Priya Raman', until: 5, on: 'Sunday')).single;
      expect(r.kind, TriageKind.assign);
      expect(r.label, 'Priya Raman Block ends Sunday · needs next Assign');
    });

    test('Reply — the question itself is the reason', () {
      final r = _t(_c(name: 'Lena Fischer', asked: 'Asked about the split squat'))
          .single;
      expect(r.kind, TriageKind.reply);
      expect(r.label, 'Lena Fischer Asked about the split squat Reply');
    });
  });

  group('where a rule must refuse to speak', () {
    // "Client needs you today" is not triage.
    test('no name, no row — and a blank name is no name', () {
      expect(_t(_c(name: null, week: 14)), isEmpty);
      expect(_t(_c(name: '   ', week: 14)), isEmpty);
    });

    // A client who has never trained has no sessions either. Treating that as
    // a silence would put every new client on the coach's triage list on day
    // one, which is the opposite of what the board asks for.
    test('no sessions at all is not a silence', () {
      expect(_t(_c(days: null)), isEmpty);
    });

    // When the only trigger is the risk score there may be no day count, and
    // the row must not invent one.
    test('a risk score with no day count states the risk, not a number', () {
      final r = _t(_c(days: null, churn: 72)).single;
      expect(r.kind, TriageKind.atRisk);
      expect(r.detail, 'Flagged at risk of dropping off');
      expect(r.detail, isNot(contains('days')));
    });

    test('an empty check-in note leaves the line at the check-in', () {
      expect(_t(_c(week: 14, note: '  ')).single.detail, 'Week 14 check-in');
    });

    test('a block with no known end day still says what is needed', () {
      expect(_t(_c(until: 0, on: null)).single.detail, 'Block ended · needs next');
    });
  });

  group('the thresholds are the caller\'s, not this file\'s', () {
    // The board shows "9 days", a value. How long a silence must last before a
    // coach is told is a product judgement (OD-21), so it is a required
    // parameter — these two tests exist to prove the number actually bites.
    test('the inactivity threshold decides, and the day count only reports',
        () {
      expect(_t(_c(days: 8), inactivity: 9), isEmpty);
      expect(_t(_c(days: 9), inactivity: 9).single.detail,
          'No sessions logged in 9 days');
      expect(_t(_c(days: 30), inactivity: 9).single.detail,
          'No sessions logged in 30 days');
    });

    test('the block horizon decides', () {
      expect(_t(_c(until: 8), horizon: 7), isEmpty);
      expect(_t(_c(until: 7), horizon: 7), hasLength(1));
      // Already over, and still nothing after it.
      expect(_t(_c(until: -3), horizon: 7), hasLength(1));
    });

    // Reused from the screen that already ships it, so it is not a new
    // decision and is deliberately NOT a parameter.
    test('the churn threshold is the one already shipped', () {
      expect(churnRiskThreshold, 50);
      expect(_t(_c(churn: 49)), isEmpty);
      expect(_t(_c(churn: 50)), hasLength(1));
    });

    test('a block with a successor needs nothing, however close it ends', () {
      expect(_t(_c(until: 0, on: 'Sunday', hasNext: true)), isEmpty);
    });
  });

  group('ordering and the cap', () {
    // The board's order, and nothing more — no priority between a silent
    // client and an unanswered question is stated anywhere in the package.
    test('rows come back in the order the board lists them', () {
      final rows = _t(_c(
        week: 14,
        days: 9,
        until: 2,
        on: 'Sunday',
        asked: 'Asked about the split squat',
      ));
      expect(rows.map((r) => r.action).toList(),
          ['Review', 'At risk', 'Assign', 'Reply']);
    });

    test('one client can need more than one thing', () {
      expect(_t(_c(week: 14, asked: 'Asked about the split squat')), hasLength(2));
    });

    test('across clients, still the board\'s order', () {
      final all = needsYouToday([
        _c(id: 'a', name: 'Lena Fischer', asked: 'Asked about the split squat'),
        _c(id: 'b', name: 'Amara Osei', week: 14),
      ], inactivityDays: 9, blockEndHorizonDays: 7);
      expect(all.map((r) => r.clientName).toList(),
          ['Amara Osei', 'Lena Fischer']);
    });

    test('four are drawn and the rest are counted', () {
      final all = needsYouToday([
        for (var i = 0; i < 6; i++) _c(id: 'c$i', name: 'Client $i', week: 14),
      ], inactivityDays: 9, blockEndHorizonDays: 7);

      expect(all, hasLength(6));
      expect(visibleTriage(all), hasLength(4));
      // The board writes the word, not the numeral.
      expect(triageOverflowLine(all), 'and two more');
    });

    test('nothing hidden means no overflow line at all', () {
      final all = needsYouToday([
        for (var i = 0; i < 4; i++) _c(id: 'c$i', name: 'Client $i', week: 14),
      ], inactivityDays: 9, blockEndHorizonDays: 7);
      expect(visibleTriage(all), hasLength(4));
      expect(triageOverflowLine(all), isNull);
    });

    test('one hidden reads "and one more"; past ten it reads as a numeral', () {
      List<TriageItem> n(int count) => needsYouToday([
            for (var i = 0; i < count; i++)
              _c(id: 'c$i', name: 'Client $i', week: 1),
          ], inactivityDays: 9, blockEndHorizonDays: 7);
      expect(triageOverflowLine(n(5)), 'and one more');
      expect(triageOverflowLine(n(14)), 'and ten more');
      expect(triageOverflowLine(n(15)), 'and 11 more');
    });
  });

  group('allClientsLabel', () {
    test('carries the real roster size', () {
      expect(allClientsLabel(24), 'All 24 clients');
    });

    test('a single client is not "1 clients"', () {
      expect(allClientsLabel(1), 'All 1 client');
    });

    // A roster of nobody is not a destination.
    test('no clients means no control', () {
      expect(allClientsLabel(0), isNull);
      expect(allClientsLabel(-1), isNull);
    });
  });
}
