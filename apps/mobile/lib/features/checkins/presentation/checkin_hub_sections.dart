import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/checkin_model.dart';
import '../data/weekly_checkin_service.dart';
import '../domain/checkin_hub.dart';
import '../domain/checkin_provider.dart';

/// The client's weekly check-in history.
///
/// **F-16: the error propagates.** `WeeklyCheckinService.getWeeklyCheckins()`
/// is wrapped here rather than called through a swallowing helper, so a failed
/// read reaches the screen as a failure instead of as "no history".
final checkinHistoryProvider = FutureProvider<List<WeeklyCheckin>>((ref) async {
  return WeeklyCheckinService().getWeeklyCheckins(limit: checkinHistoryLimit);
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
    final history = historyFrom(ref.watch(checkinHistoryProvider));

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
      if (history.state == CheckinHistoryState.failed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.cloud_off_rounded, color: _error, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(checkinHistoryFailure,
                style: const TextStyle(color: _error, fontSize: 13)),
            ),
          ]),
        )
      else if (history.state == CheckinHistoryState.empty)
        // FIT-023 declares no empty copy, so the screen states nothing and
        // leaves "Start check-in" above as the way forward. Writing a sentence
        // here would be OD-8.
        const SizedBox.shrink()
      else
        for (final week in history.weeks)
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

const _card   = Color(0xFF0E0B16);
const _border = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _error  = Color(0xFFFFB4AB);
