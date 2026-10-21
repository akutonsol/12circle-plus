import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/coach_triage.dart';

/// FIT-032 · "Needs you today".
///
/// The rules are in `domain/coach_triage.dart`, with the board's annotation
/// and the authorization for each source. This is the surface.
///
/// ── THE THRESHOLDS ARE PASSED IN, AND THAT IS DELIBERATE ───────────────────
/// `inactivityDays` and `blockEndHorizonDays` have no defaults anywhere. The
/// board shows `9 days` and `Sunday` as sample **values**, not rules, and
/// choosing them is a judgement about what a coach is told — **OD-21**. The
/// call site states them so the choice is visible in the diff rather than
/// buried in a domain file.
class NeedsYouToday extends ConsumerWidget {
  final List<ClientSignals> clients;
  final int totalClients;
  final int inactivityDays;
  final int blockEndHorizonDays;

  const NeedsYouToday({
    super.key,
    required this.clients,
    required this.totalClients,
    required this.inactivityDays,
    required this.blockEndHorizonDays,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = needsYouToday(
      clients,
      inactivityDays: inactivityDays,
      blockEndHorizonDays: blockEndHorizonDays,
    );
    final visible = visibleTriage(all);
    final overflow = triageOverflowLine(all);
    final roster = allClientsLabel(totalClients);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        header: true,
        container: true,
        child: const Text('Needs you today',
            style: TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2)),
      ),
      const SizedBox(height: 10),

      // Nothing needing attention is a RESULT, not an empty list. A coach who
      // is on top of their roster should be told so, not shown a blank.
      if (all.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Text('Nothing needs you right now.',
              style: TextStyle(color: _grey, fontSize: 14, height: 1.5)),
        )
      else
        for (final item in visible) _TriageRow(item: item),

      if (overflow != null) ...[
        const SizedBox(height: 10),
        Text(overflow, style: const TextStyle(color: _dim, fontSize: 12.5)),
      ],

      if (roster != null) ...[
        const SizedBox(height: 14),
        Semantics(
          button: true,
          label: roster,
          excludeSemantics: true,
          onTap: () => context.go('/coach-dashboard'),
          child: GestureDetector(
            onTap: () => context.go('/coach-dashboard'),
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(roster,
                    style: const TextStyle(
                        color: _violetTxt,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward, color: _violetTxt, size: 15),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// One client, one reason, one action — `<button class="tap row">` on the
/// board, so a real button here.
class _TriageRow extends ConsumerWidget {
  final TriageItem item;
  const _TriageRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Each action word goes where that action is performed, and every route
    // below is one the app already registers AND that the coach nav in
    // `app_shell.dart:95-103` already uses for that purpose — `Check-ins` →
    // `/coach-checkin-review`, `Programs` → `/program-builder`, `Clients` →
    // `/coach-dashboard`.
    //
    // An earlier draft of this file routed to `/clients` and
    // `/coach-programs`. Neither exists. They read plausibly, which is exactly
    // what makes an invented destination dangerous: nothing fails at compile
    // time and go_router lands the coach on an error page. Checked against the
    // router rather than assumed, and a test below holds every one of them.
    void open() {
      switch (item.kind) {
        case TriageKind.review:
          context.go('/coach-checkin-review');
        case TriageKind.reply:
          context.go('/messages');
        case TriageKind.assign:
          context.go('/program-builder');
        case TriageKind.atRisk:
          // "At risk" is a state, not an action, and the board words it that
          // way, so this goes where a coach looks rather than where they act.
          context.go('/coach-client-workouts');
      }
    }

    return Semantics(
      button: true,
      label: item.label,
      excludeSemantics: true,
      // `excludeSemantics` drops the child's ACTIONS with its labels (F-20).
      onTap: open,
      child: GestureDetector(
        onTap: open,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44), // `tap` floor
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line)),
          ),
          child: Row(children: [
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.clientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _ink, fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(item.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _grey, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 12),
            _ActionChip(kind: item.kind, label: item.action),
          ]),
        ),
      ),
    );
  }
}

/// `.pill` — 11px, w500, radius 6, and NO `text-transform`, so the board's
/// words read as written: `Review`, `At risk`, `Assign`, `Reply`.
class _ActionChip extends StatelessWidget {
  final TriageKind kind;
  final String label;
  const _ActionChip({required this.kind, required this.label});

  @override
  Widget build(BuildContext context) {
    // `At risk` is the one that is not something to go and do, and the board
    // colours it apart from the three actions.
    final risk = kind == TriageKind.atRisk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (risk ? _amber : _violet).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: risk ? _amber : _violetTxt,
              fontSize: 11,
              fontWeight: FontWeight.w500)),
    );
  }
}

const _ink       = Color(0xFFF4F3F6);
const _grey      = Color(0xFF9B96A3);
const _dim       = Color(0xFF8B8595);
const _line      = Color(0x14FFFFFF);
const _violet    = Color(0xFF7C3AED);
const _violetTxt = Color(0xFFA78BFA);
const _amber     = Color(0xFFFFD580);
