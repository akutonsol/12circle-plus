import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/coach/domain/coach_name.dart';

/// The one rule for addressing a client's coach by name.
///
/// The design package does it in several places — "Send to Nadia" (FIT-004),
/// "Message Nadia" (FIT-015), and `/train`'s empty-state copy. The name is real
/// data, so using it invents nothing. The rule exists because the two failure
/// modes either side of it are easy to reintroduce one screen at a time:
///
///   * naming a coach the client does not have, and
///   * naming one when the read FAILED — `/profile`'s "No coach assigned yet"
///     collapse turned inside out. There a failure claimed the client had no
///     coach; here it would claim they have one.
///
/// These tests are the rule. The screens that use it get to be simple.
void main() {
  AsyncValue<Map<String, dynamic>?> data(Map<String, dynamic>? v) =>
      AsyncData<Map<String, dynamic>?>(v);

  group('coachFirstName — only on proof', () {
    test('a settled coach gives the name', () {
      expect(coachFirstName(data({'first_name': 'Nadia'})), 'Nadia');
    });

    test('a FAILED read gives nothing', () {
      expect(
          coachFirstName(AsyncError<Map<String, dynamic>?>(
              Exception('offline'), StackTrace.empty)),
          isNull);
    });

    test('a failure carrying a stale coach gives nothing', () {
      final stale = AsyncError<Map<String, dynamic>?>(
              Exception('x'), StackTrace.empty)
          .copyWithPrevious(data({'first_name': 'Nadia'}));
      expect(stale.valueOrNull, isNotNull, reason: 'guard the premise');
      expect(coachFirstName(stale), isNull);
    });

    test('loading gives nothing — no flash of a name', () {
      expect(coachFirstName(const AsyncLoading<Map<String, dynamic>?>()), isNull);
    });

    test('no coach, a missing name and a blank name all give nothing', () {
      expect(coachFirstName(data(null)), isNull);
      expect(coachFirstName(data({})), isNull);
      expect(coachFirstName(data({'first_name': '   '})), isNull);
      expect(coachFirstName(data({'first_name': null})), isNull);
    });

    test('the name is trimmed', () {
      expect(coachFirstName(data({'first_name': '  Nadia \n'})), 'Nadia');
    });

    test('a refresh in flight keeps the name it already had', () {
      // Riverpod represents this as `AsyncData` with `isLoading: true`, NOT as
      // `AsyncLoading` — measured, not assumed. So the `AsyncData` arm is what
      // handles it, and adding an explicit `AsyncLoading()` arm to the switch
      // is an *equivalent* mutation: the catch-all already returns null for a
      // true loading state. Noted because a surviving mutation and a mutation
      // that changes nothing look identical in a report.
      final refreshing = const AsyncLoading<Map<String, dynamic>?>()
          .copyWithPrevious(data({'first_name': 'Nadia'}));
      expect(refreshing.isLoading, isTrue, reason: 'guard the premise');
      expect(refreshing, isA<AsyncData<Map<String, dynamic>?>>());
      expect(coachFirstName(refreshing), 'Nadia',
          reason: 'the name must not blink out while the screen refreshes');
    });
  });

  group('coachAddressed — the fallback is always true without a coach', () {
    String label(AsyncValue<Map<String, dynamic>?> c) => coachAddressed(c,
        withName: (n) => 'Message $n', fallback: 'Message your coach');

    test('names the coach when known', () {
      expect(label(data({'first_name': 'Nadia'})), 'Message Nadia');
    });

    test('falls back on every uncertain state', () {
      for (final c in <AsyncValue<Map<String, dynamic>?>>[
        AsyncError(Exception('x'), StackTrace.empty),
        const AsyncLoading(),
        AsyncData<Map<String, dynamic>?>(null),
        AsyncData<Map<String, dynamic>?>(const {'first_name': ''}),
      ]) {
        expect(label(c), 'Message your coach');
      }
    });

    test('the fallback is never a sentence addressed to nobody', () {
      // "Message " with an empty name is the bug this guards.
      final out = label(AsyncData<Map<String, dynamic>?>(const {'first_name': ''}));
      expect(out.trim(), out);
      expect(out, isNot(endsWith(' ')));
    });
  });
}
