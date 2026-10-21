import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../classes/domain/whats_on.dart';
import '../../classes/domain/whats_on_provider.dart';
import '../../community/domain/community_provider.dart';
import '../domain/connect_sections.dart';

/// FIT-005 · the relationship layer under `/messages`' conversations.
///
/// Three teasers — **Feed**, **Groups**, **What's on** — all three titles being
/// labels the design package declares. Each defers to the screen that owns it.
///
/// Visible for testing: `messaging_screen.dart` reaches Supabase through four
/// providers, so the sections are mounted here where they can be driven.
class ConnectSectionsView extends ConsumerWidget {
  const ConnectSectionsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = teaserFrom(ref.watch(livePostsProvider));
    final groups = teaserFrom(ref.watch(liveGroupsProvider));
    final whatsOn = whatsOnTeaser(ref.watch(whatsOnProvider));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Section(
        title: 'Feed',
        state: feed.state,
        failure: connectFeedFailure,
        onOpen: () => context.go('/community'),
        rows: [for (final p in feed.items) postLine(p)],
      ),
      _Section(
        title: 'Groups',
        state: groups.state,
        failure: connectGroupsFailure,
        onOpen: () => context.go('/community'),
        rows: [for (final g in groups.items) groupLine(g)],
      ),
      _Section(
        // FIT-027's screen name, reused so the two never disagree about what
        // "what's on" means.
        // FIT-028 declares this section "What's on this week" — the window
        // is part of the label, not decoration. FIT-027's own screen is
        // "What's on"; this row says which slice of it is being teased.
        title: "What's on this week",
        state: whatsOn.state,
        // The merged list already knows which of its three sources failed; a
        // teaser cannot say which without repeating that logic, so it borrows
        // the classes line — the section's own screen names the rest.
        failure: failureLine(WhatsOnKind.classes),
        onOpen: () => context.go('/classes'),
        rows: [
          for (final i in whatsOn.items) '${dayLabel(i.when)} · ${i.title}'
        ],
      ),
    ]);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final ConnectSectionState state;
  final String failure;
  final VoidCallback onOpen;
  final List<String> rows;

  const _Section({
    required this.title,
    required this.state,
    required this.failure,
    required this.onOpen,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    // A section still loading shows nothing rather than a spinner per section —
    // three spinners stacked under a conversation list is noise, and a section
    // that has not resolved is not making a claim either way.
    if (state == ConnectSectionState.loading) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          header: true,
          container: true,
          child: Text(title,
            style: const TextStyle(
              color: _white, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 10),
        if (state == ConnectSectionState.failed)
          // NOT an empty section. A relationship layer that quietly omits your
          // groups when the read fails is telling you that you have none.
          Row(children: [
            const Icon(Icons.cloud_off_rounded, color: _error, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(failure,
                style: const TextStyle(color: _error, fontSize: 13)),
            ),
          ])
        else if (state == ConnectSectionState.empty)
          // Deliberately quiet: FIT-005 declares no empty copy for these
          // teasers, and writing three sentences would be OD-8. The section's
          // own screen has an empty state; this one just offers the way there.
          const SizedBox.shrink()
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border)),
                child: Text(row,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 13)),
              ),
            ),
        const SizedBox(height: 4),
        Semantics(
          button: true,
          // "Open" plus the section's own title, so a screen reader hears which
          // of the three it is. Both halves are already on screen.
          label: 'Open $title',
          excludeSemantics: true,
          onTap: onOpen,
          child: GestureDetector(
            onTap: onOpen,
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.centerLeft,
              child: Text('Open $title',
                style: const TextStyle(
                  color: _primary, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ]),
    );
  }
}

const _card    = Color(0xFF0E0B16);
const _border  = Color(0xFF1A1020);
const _white   = Colors.white;
const _muted   = Color(0xFFCFC2D6);
const _primary = Color(0xFFDDB7FF);
const _error   = Color(0xFFFFB4AB);
