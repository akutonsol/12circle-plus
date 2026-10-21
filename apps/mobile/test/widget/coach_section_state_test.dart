import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';

/// F-15 · `/profile` told paying clients they had no coach.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// The "MY COACH" section read `assignedCoachProvider.valueOrNull`, so a failed
/// read and "you have no coach" arrived as the same `null`. On any failure the
/// client saw:
///
///   **No coach assigned yet**
///   Complete onboarding to choose your coach.
///
/// Not a blank where data should be — a specific false statement about the
/// client's own relationship, with an instruction attached to it. Someone
/// paying a coach every month, told to go and pick one.
///
/// This is the same falsehood FIT-028 was built to avoid on `/messages`, in a
/// second place. There it was caught before shipping; here it had shipped.
///
/// ── WHY THE SECTION IS HIDDEN AND NOT REWORDED ─────────────────────────────
/// Any replacement wording is new product copy, and the string already sitting
/// there is the false one — so there is nothing shipped to fall back to, which
/// is how FIT-028 avoided inventing anything. A full error state with a retry
/// is OD-8, like the other collapses. Saying nothing is not ideal. Saying
/// something untrue is worse, and it is what shipped.
void main() {
  test('F-15 a FAILED read hides the section instead of denying the coach', () {
    final failed = AsyncError<Map<String, dynamic>?>(
        Exception('offline'), StackTrace.empty);
    expect(coachSectionFor(failed), CoachSectionState.unavailable);
  });

  test('F-15 a failure holding stale data is still a failure', () {
    // AsyncError can carry a previous value. Going by the value rather than the
    // state is how the original defect worked, so it is pinned here.
    final stale = AsyncError<Map<String, dynamic>?>(
            Exception('offline'), StackTrace.empty)
        .copyWithPrevious(const AsyncData<Map<String, dynamic>?>({'id': 'c1'}));
    expect(coachSectionFor(stale), CoachSectionState.unavailable);
  });

  test('F-15 genuinely having no coach is a real answer and keeps its card', () {
    // The fix must not collapse the two in the other direction. A client who
    // really has no coach should still be told, and still be pointed at
    // onboarding.
    expect(coachSectionFor(const AsyncData<Map<String, dynamic>?>(null)),
        CoachSectionState.none);
  });

  test('F-15 an assigned coach renders the coach', () {
    expect(
        coachSectionFor(const AsyncData<Map<String, dynamic>?>({'id': 'c1'})),
        CoachSectionState.assigned);
  });

  test('F-15 loading is loading — not "no coach", and not a failure', () {
    expect(coachSectionFor(const AsyncLoading<Map<String, dynamic>?>()),
        CoachSectionState.loading);
  });

  test('F-15 a RETRY in flight after a failure stays hidden', () {
    // This is the real refresh shape: Riverpod reports isLoading AND hasError
    // together (`AsyncError` with `isLoading: true`). A deliberate choice, and
    // the mutation that checks isLoading first is what this pins — a retry in
    // flight knows no more than the failure that preceded it, and flashing a
    // spinner in and out of a hidden section is worse than leaving it hidden
    // until there is something true to say.
    final retrying = const AsyncLoading<Map<String, dynamic>?>().copyWithPrevious(
        AsyncError<Map<String, dynamic>?>(Exception('offline'), StackTrace.empty));
    expect(retrying.isLoading, isTrue, reason: 'guard the premise of this test');
    expect(retrying.hasError, isTrue);
    expect(coachSectionFor(retrying), CoachSectionState.unavailable);
  });

  // ── The wiring ────────────────────────────────────────────────────────────
  // The function above is the decision; these mount the real section and check
  // the decision is actually acted on. Without them, deleting the early return
  // in `build` is a mutation that survives — which is how it was found.
  group('F-15 the section acts on the decision', () {
    Override pin(
      ProviderBase<AsyncValue<Map<String, dynamic>?>> p,
      AsyncValue<Map<String, dynamic>?> v,
    ) =>
        (p as FutureProvider<Map<String, dynamic>?>).overrideWith((ref) => v.when(
              data: (d) => d,
              error: (e, s) => Future<Map<String, dynamic>?>.error(e, s),
              loading: () => Completer<Map<String, dynamic>?>().future,
            ));

    Future<void> mount(
      WidgetTester t,
      AsyncValue<Map<String, dynamic>?> coach,
    ) async {
      await t.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ProviderScope(
        overrides: [
          pin(assignedCoachProvider, coach),
          pin(clientRelationshipProvider,
              const AsyncData<Map<String, dynamic>?>(null)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MyCoachSection(onCoachCancelled: () {}),
            ),
          ),
        ),
      ));
      await t.pump();
    }

    testWidgets('a failed read renders NOTHING — not the denial', (t) async {
      await mount(
          t,
          AsyncError<Map<String, dynamic>?>(
              Exception('offline'), StackTrace.empty));

      expect(find.text('No coach assigned yet'), findsNothing);
      expect(find.text('Complete onboarding to choose your coach.'), findsNothing);
      // The heading goes too: a "MY COACH" label over an empty space is its own
      // small assertion that there is nothing there.
      expect(find.text('MY COACH'), findsNothing);
    });

    testWidgets('a client who really has no coach is still told', (t) async {
      await mount(t, const AsyncData<Map<String, dynamic>?>(null));

      expect(find.text('MY COACH'), findsOneWidget);
      expect(find.text('No coach assigned yet'), findsOneWidget);
    });
  });
}
