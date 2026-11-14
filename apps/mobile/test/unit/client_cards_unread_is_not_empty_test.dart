import 'dart:io';

import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The coach's client page showed a failed read as the client's answer.
//
// The Training Schedule and 12 Circle Score cards read `valueOrNull`, which is
// null while loading, when the read failed, and when there is truly nothing.
// So a failed `client_schedules` read said "Client hasn't set a schedule
// yet.", and a failed `user_scores` read showed "0 · 0 · Lvl 1 Bronze" — a
// client's real standing replaced by a beginner's.

void main() {
  test('a failed read is said to have failed', () {
    expect(unreadNote(AsyncValue<Object?>.error('down', StackTrace.empty), failed: 'X'), 'X',
        reason: 'THE defect: a failure was shown as "no schedule" / "0 · Lvl 1 Bronze"');
  });

  test('a read in flight is not an answer yet', () {
    expect(unreadNote(const AsyncValue<Object?>.loading(), failed: 'X'), '…');
  });

  test('an answer — even "nothing" — is shown as the answer', () {
    expect(unreadNote(const AsyncValue<Object?>.data(null), failed: 'X'), isNull);
    expect(unreadNote(const AsyncValue<Object?>.data({'level': 3}), failed: 'X'), isNull);
  });

  test('guard: neither card reads its provider through valueOrNull alone', () {
    // Source guard: the cards now branch on `unreadNote` before using the value.
    final src = File('lib/features/dashboard/presentation/client_detail_screen.dart').readAsStringSync();
    expect(src.contains("ref.watch(clientScoreProvider(clientId)).valueOrNull"), isFalse);
    expect(src.contains("unreadNote(schedAsync"), isTrue);
  });
}
