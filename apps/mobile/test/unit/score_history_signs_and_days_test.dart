import 'package:circle_fitness/features/scoring/presentation/score_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// The score history printed penalties as "+-5", on the UTC day.
//
// `penalize_points` (054) stores a penalty negated, and the history row printed
// `'+$pts'` — "+-5", in the award colour. The date was the first ten characters
// of `created_at`, the UTC date: an evening event in New York sat under the next
// day. (Run with TZ=America/New_York to see the day half fail on the old code.)

void main() {
  test('a penalty reads as a minus, an award as a plus', () {
    expect(scoreEventPoints(-5), '−5', reason: 'THE defect: "+-5"');
    expect(scoreEventPoints(10), '+10');
    expect(scoreEventPoints(0), '+0');
  });

  test("an event is listed on the member's own day", () {
    final now = DateTime.now();
    final evening = DateTime(now.year, now.month, now.day, 21, 30);
    final day = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    expect(scoreEventDay(evening.toUtc().toIso8601String()), day);
    expect(scoreEventDay(null), '');
  });
}
