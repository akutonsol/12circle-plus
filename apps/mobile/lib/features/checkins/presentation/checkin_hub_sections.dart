import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/observability/app_failure.dart';
import '../data/models/checkin_model.dart';
import '../data/weekly_checkin_service.dart';
import '../domain/checkin_hub.dart';
import '../domain/checkin_provider.dart';

/// The client's weekly check-in history.
///
/// **F-16: the error propagates.** `WeeklyCheckinService.getWeeklyCheckins()`
/// is wrapped here rather than called through a swallowing helper, so a failed
/// read reaches the screen as a failure instead of as "no history".
///
/// **autoDispose, so each visit reads it again.** It was cached for the life of
/// the app, and the coach's reply lands on a row this already held: a client who
/// had looked at their history saw "Awaiting reply" over an answered week until
/// the app restarted. The reply's notification (`checkin`) re-reads it too.
///
/// By the uid only, and the rows carry who read them ([OwnedRows]): riverpod
/// keeps the last member's weeks here through the next one's read (P0-FL-59c).
final checkinHistoryProvider =
    FutureProvider.autoDispose<List<WeeklyCheckin>>((ref) async {
  ref.watch(checkinUidProvider);
  return ownedRead(() async {
    final uid = checkinUidNow();
    final weeks = await WeeklyCheckinService()
        .getWeeklyCheckins(limit: checkinHistoryLimit);
    return [
      for (final w in weeks)
        if (isCheckinOf(w, () => uid)) w
    ];
  });
});

/// FIT-023 · the check-in hub's two declared controls and its history.
///
/// `Measurements` and `Start check-in` are the package's own labels. The
/// history rows are real weeks from `weekly_checkins`; the anchor's
/// `Week 13 Energy steady · Nadia replied` is demo data on the board, and what
/// is built is that row's *shape* over live values.
///
/// Visible for testing: `checkin_screen.dart` reads Supabase directly in
/// `initState`, so the sections are mounted here where they can be driven.
class CheckinHubSections extends ConsumerWidget {
  const CheckinHubSections({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(checkinHistoryProvider);
    final mine = heldFor(historyAsync, () => ref.watch(checkinUidProvider));
    final history = historyFrom(mine);
    // A failed refresh keeps this member's weeks under the failure it states.
    final weeks = history.state == CheckinHistoryState.failed && mine.hasValue
        ? mine.requireValue.take(checkinHistoryLimit).toList()
        : history.weeks;
    // P0-FL-2 follow-up (U1): Riverpod's `when`/state mapping keeps the error
    // on screen while a retry is in flight, so the in-flight read is read off
    // the provider itself — `historyFrom` maps by type and cannot see it.
    final retrying = historyAsync.isLoading;
    // F2: the failure is recorded once per failed read — on the transition
    // into a settled error, not on every rebuild that shows it.
    ref.listen(checkinHistoryProvider, (previous, next) {
      if (_settledFailure(previous, next)) {
        reportError('CheckinHubSections.history', next.error!, next.stackTrace);
      }
    });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Row(children: [
          // FIT-023 declares both. "Start check-in" goes to the form;
          // "Measurements" goes to Progress, which is where this app keeps
          // them — no screen is invented to satisfy a label.
          Expanded(
            child: _HubAction(
              label: 'Start check-in',
              primary: true,
              onTap: () => context.go('/daily-checkin'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _HubAction(
              label: 'Measurements',
              primary: false,
              onTap: () => context.go('/progress'),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Semantics(
          header: true,
          container: true,
          // The anchor's own subtitle for this screen is "status and history".
          child: const Text('History',
            style: TextStyle(
              color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
      // P0-FL-2: loading was rendered as the (silent) empty state, so the
      // History header sat over nothing while the read was in flight.
      if (history.state == CheckinHistoryState.loading)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Semantics(
            label: 'Loading check-in history',
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _brand),
            ),
          ),
        )
      else if (history.state == CheckinHistoryState.failed)
        // P0-FL-2: the failure had no way back short of leaving the screen.
        // A live region so a screen reader hears the failure when it lands.
        Semantics(
          liveRegion: true,
          container: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Icon(Icons.cloud_off_rounded, color: _error, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(checkinHistoryFailure,
                  style: const TextStyle(color: _error, fontSize: 13)),
              ),
              // U4: Flexible, so at a large text scale the button shares the
              // row (its label wraps) instead of overflowing it.
              Flexible(
                child: TextButton.icon(
                  // U1: disabled while the retry is in flight, so a second
                  // failure is visibly a new answer, not a dead tap.
                  onPressed: retrying
                      ? null
                      : () => ref.invalidate(checkinHistoryProvider),
                  icon: retrying
                      ? Semantics(
                          label: 'Retrying',
                          child: const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _brand),
                          ),
                        )
                      : const Icon(Icons.refresh_rounded,
                          color: _brand, size: 18),
                  label: Text('Try again',
                    style: TextStyle(
                      color: retrying ? _brand.withValues(alpha: 0.6) : _brand,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        )
      else if (history.state == CheckinHistoryState.empty)
        // FIT-023 declares no empty copy, so the screen states nothing and
        // leaves "Start check-in" above as the way forward. Writing a sentence
        // here would be OD-8.
        const SizedBox.shrink(),
      for (final week in weeks)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Semantics(
              button: true,
              // The row's content IS its name — the week, the energy and
              // whether the coach replied are what a client needs to hear in
              // order to choose one. The action goes in the hint, the same
              // judgement FIT-005's conversation rows use.
              hint: 'Open check-in',
              child: GestureDetector(
                // Select the week first: `/checkin-detail` used to be a stub,
                // so this row navigated into a dead end of my own making.
                onTap: () {
                  // The row is its member's, not whoever taps it: in a hidden
                  // tab it outlives the switch, and the selection would be
                  // stored under the one who arrived.
                  if (!isCheckinOf(week, checkinUidNow)) {
                    reportError(
                        'CheckinHubSections.open',
                        StateError(
                            'check-in not opened: the signed-in account changed'),
                        StackTrace.current);
                    return;
                  }
                  ref.read(selectedCheckinProvider.notifier).state = week;
                  context.go('/checkin-detail');
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border)),
                  child: Text(historyLine(week),
                    style: const TextStyle(color: _muted, fontSize: 13)),
                ),
              ),
            ),
          ),
    ]);
  }
}

class _HubAction extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _HubAction({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary ? _brand : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: primary ? _brand : Colors.white.withValues(alpha: 0.12)),
            ),
            child: Text(label,
              style: TextStyle(
                color: primary ? Colors.white : _white,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
          ),
        ),
      );
}

/// F2 · a read has just settled into a failure: an error that is no longer
/// loading, arriving from a state that was loading or held no error. A
/// rebuild that merely re-shows the same failure does not qualify.
bool _settledFailure(AsyncValue<Object?>? previous, AsyncValue<Object?> next) =>
    next.hasError &&
    !next.isLoading &&
    (previous == null || previous.isLoading || !previous.hasError);

const _card   = Color(0xFF0E0B16);
const _border = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _error  = Color(0xFFFFB4AB);
