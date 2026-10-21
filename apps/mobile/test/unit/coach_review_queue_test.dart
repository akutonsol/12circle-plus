import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/checkins/domain/coach_review_queue.dart';

/// FIT-033 · the review queue.
///
/// The board's annotation is unusually direct about what matters: *"Six to
/// review means the **flow matters more than the screen**: paged 1-of-6, and
/// the primary action is send and open next."* So the queue is the feature,
/// and these are its rules.
///
/// Four of them are refusals, and each one is a place the screen would
/// otherwise tell a coach something nobody recorded.

Map<String, dynamic> _c(String id, {int? week, Map<String, dynamic>? extra}) => {
      'id': id,
      if (week != null) 'week_number': week,
      ...?extra,
    };

final _queue = [_c('a'), _c('b'), _c('c'), _c('d'), _c('e'), _c('f')];

void main() {
  group('position in the queue', () {
    test('the board\'s own line', () {
      expect(reviewPosition(_queue, 'a')!.line, '1 of 6');
      expect(reviewPosition(_queue, 'f')!.line, '6 of 6');
      expect(reviewPosition(_queue, 'c')!.line, '3 of 6');
    });

    test('hasNext is false only on the last', () {
      expect(reviewPosition(_queue, 'a')!.hasNext, isTrue);
      expect(reviewPosition(_queue, 'e')!.hasNext, isTrue);
      expect(reviewPosition(_queue, 'f')!.hasNext, isFalse);
    });

    // A check-in reviewed in another tab, or withdrawn, is no longer one of
    // six — and must not be drawn as though it were.
    test('a check-in not in the queue has no position at all', () {
      expect(reviewPosition(_queue, 'zzz'), isNull);
      expect(reviewPosition(_queue, null), isNull);
      expect(reviewPosition(const [], 'a'), isNull);
    });

    test('a queue of one is 1 of 1, with no next', () {
      final p = reviewPosition([_c('a')], 'a')!;
      expect(p.line, '1 of 1');
      expect(p.hasNext, isFalse);
    });
  });

  group('the header line', () {
    test('Week 14 · 1 of 6', () {
      expect(
        reviewHeaderLine(
            weekNumber: 14, position: reviewPosition(_queue, 'a')),
        'Week 14 · 1 of 6',
      );
    });

    test('half a line rather than a fabricated one', () {
      expect(reviewHeaderLine(weekNumber: 14), 'Week 14');
      expect(reviewHeaderLine(position: reviewPosition(_queue, 'b')), '2 of 6');
      expect(reviewHeaderLine(), '');
    });

    test('a zero or absent week number is not written as "Week 0"', () {
      expect(reviewHeaderLine(weekNumber: 0), '');
      expect(reviewHeaderLine(weekNumber: null), '');
    });
  });

  group('next in queue', () {
    test('walks forward', () {
      expect(nextInQueue(_queue, 'a')?['id'], 'b');
      expect(nextInQueue(_queue, 'e')?['id'], 'f');
    });

    test('the last one has no next', () {
      expect(nextInQueue(_queue, 'f'), isNull);
    });

    test('an unqueued check-in has no next', () {
      expect(nextInQueue(_queue, 'zzz'), isNull);
    });
  });

  // The board writes `Send and open next`. On the last check-in there is no
  // next, and a button must not promise one.
  group('the primary action', () {
    test('promises the next one only when there is one', () {
      expect(primaryActionLabel(reviewPosition(_queue, 'a')),
          'Send and open next');
      expect(primaryActionLabel(reviewPosition(_queue, 'f')), 'Send');
      expect(primaryActionLabel(null), 'Send');
    });

    test('the fallback is the package\'s own word, not a new one', () {
      // FIT-026 labels the chat composer's control `Send`.
      expect(primaryActionLabel(null), 'Send');
      expect(primaryActionLabel(null), isNot(contains('Submit')));
    });
  });

  // The board writes "She wrote" because Amara is its example. Applying a
  // pronoun to a real client would misgender them.
  test('the client heading carries no pronoun', () {
    expect(clientWroteHeading, 'They wrote');
    for (final p in const ['She', 'she', 'He', 'he', 'Her', 'His']) {
      expect(clientWroteHeading.split(RegExp(r'\s+')), isNot(contains(p)));
    }
    expect(coachReplyHeading, 'Your reply');
  });

  group('the stats', () {
    test('Nutrition is the one that maps exactly', () {
      final s = reviewStats({'compliance_percent': 92});
      expect(s.single.label, 'Nutrition');
      expect(s.single.value, '92%');
    });

    // OD-16. FIT-004 declares Low/Steady/Strong and FIT-023 draws "Energy
    // steady"; the database stores 1–5 and a coach reads that number.
    // Choosing thresholds is a product decision about what a coach is TOLD.
    test('Energy states its value and does not interpret it', () {
      final s = reviewStats({'energy_level': 3});
      expect(s.single.label, 'Energy');
      expect(s.single.value, '3 of 5');
    });

    test('OD-16 is not resolved silently — the three words never appear', () {
      for (var i = 1; i <= 5; i++) {
        final v = reviewStats({'energy_level': i}).single.value;
        for (final w in const ['Low', 'Steady', 'Strong']) {
          expect(v, isNot(contains(w)));
        }
      }
    });

    // The board counts nights (`5/7`); the schema stores average hours. They
    // are different statistics and one cannot be derived from the other.
    test('Sleep shows hours, labelled for what it is', () {
      expect(reviewStats({'sleep_hours': 7.2}).single.value, '7.2 h avg');
      expect(reviewStats({'sleep_hours': 8}).single.value, '8 h avg');
      expect(reviewStats({'sleep_hours': 7.2}).single.value, isNot(contains('/7')));
    });

    // OD-24: completed-against-prescribed is not on this row in any form.
    test('Sessions is not produced, because nothing records it', () {
      final s = reviewStats({
        'energy_level': 3,
        'sleep_hours': 7,
        'compliance_percent': 92,
      });
      expect(s.map((x) => x.label), ['Energy', 'Sleep', 'Nutrition']);
      expect(s.map((x) => x.label), isNot(contains('Sessions')));
    });

    test('an absent value produces no stat rather than a zero', () {
      expect(reviewStats(const {}), isEmpty);
      expect(reviewStats({'compliance_percent': null}), isEmpty);
      expect(reviewStats({'sleep_hours': 0}), isEmpty);
    });

    test('an out-of-range percentage is refused, not clamped', () {
      // A coach acting on "Nutrition 140%" is acting on a bug.
      expect(reviewStats({'compliance_percent': 140}), isEmpty);
      expect(reviewStats({'compliance_percent': -5}), isEmpty);
      expect(reviewStats({'compliance_percent': 100}).single.value, '100%');
    });

    test('an out-of-range energy is refused too', () {
      expect(reviewStats({'energy_level': 0}), isEmpty);
      expect(reviewStats({'energy_level': 9}), isEmpty);
    });

    test('they come back in the board\'s order', () {
      final s = reviewStats({
        'compliance_percent': 92,
        'sleep_hours': 7,
        'energy_level': 4,
      });
      expect(s.map((x) => x.label).toList(), ['Energy', 'Sleep', 'Nutrition']);
    });
  });

  group('the client', () {
    test('is named from the joined profile', () {
      expect(
        clientName({
          'user_profiles': {'first_name': 'Amara', 'last_name': 'Osei'}
        }),
        'Amara Osei',
      );
    });

    // A review screen that cannot say whose check-in it shows has a worse
    // problem than a missing label — it must not answer "Client".
    test('is null rather than a placeholder', () {
      expect(clientName(const {}), isNull);
      expect(clientName({'user_profiles': null}), isNull);
      expect(
          clientName({
            'user_profiles': {'first_name': '', 'last_name': ''}
          }),
          isNull);
    });

    test('a first name alone is enough', () {
      expect(clientName({'user_profiles': {'first_name': 'Amara'}}), 'Amara');
    });

    test('their note is theirs, or nothing', () {
      expect(clientNote({'notes': 'Travel next week.'}), 'Travel next week.');
      expect(clientNote({'notes': '   '}), isNull);
      expect(clientNote(const {}), isNull);
    });
  });
}
