import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/profile/domain/connected_apps.dart';

/// FIT-029 · the `Connected apps` badge.
///
/// The board draws a count. Three different situations share one correct
/// answer — **no badge** — and the third is the one that matters: the screen
/// this row opens ends its own read `catch (_)`, so a failure there shows
/// every provider as disconnected. This row must not repeat it.
void main() {
  test('a real count is shown', () {
    expect(connectedAppsBadge(const AsyncData(2)), '2');
    expect(connectedAppsBadge(const AsyncData(1)), '1');
    expect(connectedAppsBadge(const AsyncData(12)), '12');
  });

  // The board draws a count, not a zero. `Connected apps 0` tells the client
  // something they can already see by opening the row.
  test('nothing connected shows no badge', () {
    expect(connectedAppsBadge(const AsyncData(0)), isNull);
  });

  test('a negative count is refused rather than rendered', () {
    expect(connectedAppsBadge(const AsyncData(-1)), isNull);
  });

  // A number that appears a moment later is worse than one that appears once.
  test('loading shows no badge', () {
    expect(connectedAppsBadge(const AsyncLoading()), isNull);
  });

  // THE one. The client has no idea how many apps are connected, and neither
  // do we. `0` would be a fabricated fact — F-15's shape.
  test('a FAILED read shows no badge, never a zero', () {
    final failed =
        AsyncValue<int>.error(Exception('offline'), StackTrace.empty);
    expect(connectedAppsBadge(failed), isNull);
    expect(connectedAppsBadge(failed), isNot('0'));
  });

  test('a failure carrying a stale value still shows nothing', () {
    // `copyWithPrevious` keeps the last good count on an AsyncError. Showing
    // it would tell the client a number the database did not just confirm.
    final stale = AsyncValue<int>.error(Exception('offline'), StackTrace.empty)
        .copyWithPrevious(const AsyncData(3));
    expect(stale.hasValue, isTrue, reason: 'the stale value is there to show');
    expect(connectedAppsBadge(stale), isNull,
        reason: 'and it is deliberately not shown');
  });
}
