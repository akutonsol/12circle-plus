import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../challenges/domain/challenge_provider.dart';
import '../domain/class_provider.dart';
import '../domain/whats_on.dart';
import '../domain/whats_on_provider.dart';

/// FIT-027 · "What's on" — `/classes · /events · /challenges under one list`.
///
/// Visible for testing: `classes_screen.dart` reaches Supabase through three
/// providers and builds a coach-only FAB from the profile, so the list itself
/// is mounted here where it can be driven with overrides.
class WhatsOnView extends ConsumerWidget {
  const WhatsOnView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segment = ref.watch(whatsOnSegmentProvider);
    final async = ref.watch(whatsOnProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SegmentRow(
        selected: segment,
        onSelect: (i) => ref.read(whatsOnSegmentProvider.notifier).state = i,
      ),
      const SizedBox(height: 12),
      Expanded(
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: _brand, strokeWidth: 2)),
          // The combining provider never throws — a failed source is reported
          // per kind below — so this branch only fires if the combination
          // itself breaks. It still must not read as "nothing on".
          error: (_, __) => _Notices(
            kinds: WhatsOnKind.values.toSet(),
            onRetry: () => _refresh(ref),
          ),
          data: (whatsOn) {
            final failed = failedForSegment(whatsOn.failed, segment);
            final items = itemsForSegment(whatsOn.items, segment);

            // A failed source contributes no rows, so an empty list next to a
            // failure is NOT an empty schedule — and must never be drawn as
            // one. The notice replaces the empty state rather than sitting
            // above it.
            if (items.isEmpty && failed.isNotEmpty) {
              return _Notices(kinds: failed, onRetry: () => _refresh(ref));
            }
            if (items.isEmpty) return _NothingOn(segment: segment);

            final groups = groupByDay(items);
            return RefreshIndicator(
              color: _brand,
              backgroundColor: _card,
              onRefresh: () async => _refresh(ref),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                children: [
                  // Partial failure with rows present: say which source is
                  // missing, above the rows that did load.
                  if (failed.isNotEmpty)
                    _Notices(kinds: failed, onRetry: () => _refresh(ref), inline: true),
                  for (final g in groups) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 18, bottom: 8),
                      child: Text(g.day,
                        style: const TextStyle(
                          color: _muted, fontSize: 12,
                          fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                    ),
                    for (final item in g.items) _Row(item: item),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    ]);
  }

  /// Re-runs all three reads. `refreshClassesProvider` is the tick the classes
  /// feature already uses after a booking or a creation, so this reuses it
  /// rather than adding a second refresh mechanism beside it.
  void _refresh(WidgetRef ref) {
    ref.invalidate(whatsOnEventsProvider);
    ref.invalidate(liveChallengesProvider);
    ref.read(refreshClassesProvider.notifier).state++;
  }
}

/// The design's `fc-seg` row: four segments, one selected.
class _SegmentRow extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _SegmentRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          for (var i = 0; i < whatsOnSegments.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            // These are one choice, not four independent buttons, and a screen
            // reader needs to be told which is active — the defect F-22 found
            // on the check-in pickers. The name is the label already drawn.
            Semantics(
              inMutuallyExclusiveGroup: true,
              selected: i == selected,
              button: true,
              label: whatsOnSegments[i],
              excludeSemantics: true,
              onTap: () => onSelect(i),
              child: GestureDetector(
                onTap: () => onSelect(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: i == selected
                        ? _brand.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: i == selected
                          ? _brand
                          : Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Text(whatsOnSegments[i],
                    style: TextStyle(
                      color: i == selected ? _white : _muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ]),
      );
}

/// One row: title, the design's detail line, and its trailing affordance.
class _Row extends StatelessWidget {
  final WhatsOnItem item;
  const _Row({required this.item});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                  style: const TextStyle(
                    color: _white, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(item.detail,
                  style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
          if (item.action != null) ...[
            const SizedBox(width: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _brand.withValues(alpha: 0.4))),
              child: Text(item.action!,
                style: const TextStyle(
                  color: _primary, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      );
}

/// What a client sees when a source could not be read.
///
/// Every string here is one this repository already renders — see
/// [failureLine]. "Try again" is the design package's own declared label (16
/// declarations). Nothing on this screen is new product copy, which is the only
/// reason it can report a failure at all while OD-8 is outstanding.
class _Notices extends StatelessWidget {
  final Set<WhatsOnKind> kinds;
  final VoidCallback onRetry;
  final bool inline;
  const _Notices({required this.kinds, required this.onRetry, this.inline = false});

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final k in WhatsOnKind.values.where(kinds.contains))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              const Icon(Icons.cloud_off_rounded, color: _error, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(failureLine(k),
                  style: const TextStyle(color: _error, fontSize: 13)),
              ),
            ]),
          ),
        const SizedBox(height: 4),
        Semantics(
          button: true,
          child: GestureDetector(
            onTap: onRetry,
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
              child: const Text('Try again',
                style: TextStyle(
                  color: _white, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, inline ? 12 : 0, 20, inline ? 4 : 0),
      child: inline ? body : Center(child: body),
    );
  }
}

/// Genuinely nothing scheduled. Distinct from a failure, which is the whole
/// point of [WhatsOn.failed].
///
/// The lines come from the three screens this one replaces — see [emptyLine].
/// FIT-027 declares no empty state, so writing one would be new product copy.
class _NothingOn extends StatelessWidget {
  final int segment;
  const _NothingOn({required this.segment});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_available_outlined,
              color: _brand.withValues(alpha: 0.3), size: 44),
            const SizedBox(height: 14),
            for (final line in emptyLinesForSegment(segment))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _white, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      );
}

const _card    = Color(0xFF0E0B16);
const _border  = Color(0xFF1A1020);
const _brand   = Color(0xFFA855F7);
const _white   = Colors.white;
const _muted   = Color(0xFFCFC2D6);
const _primary = Color(0xFFDDB7FF);
const _error   = Color(0xFFFFB4AB);
