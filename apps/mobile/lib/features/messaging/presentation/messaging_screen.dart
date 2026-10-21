import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/named_icon_button.dart';
import '../../auth/domain/auth_provider.dart';
import '../../coach/domain/coach_provider.dart';
import '../../community/domain/community_provider.dart';
import '../domain/messaging_provider.dart';
import 'connect_sections_view.dart';

const _bg      = Color(0xFF030303);
const _card    = Color(0xFF0E0B16);
const _border  = Color(0xFF1A1020);
const _brand   = Color(0xFFA855F7);
const _white   = Colors.white;
const _muted   = Color(0xFFCFC2D6);
const _primary = Color(0xFFDDB7FF);
const _green   = Color(0xFF22C55E);

class MessagingScreen extends ConsumerWidget {
  const MessagingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: _card,
              border: Border(bottom: BorderSide(color: _border))),
            child: Row(children: [
              // F-22: both of these were icon-only controls reporting no name.
              // "Back" and "Refresh" are the authoritative package's own words
              // — 138 and 8 declarations respectively — so nothing is invented.
              _HeaderAction(
                icon: Icons.arrow_back,
                label: 'Back',
                onTap: () => context.go('/home')),
              const SizedBox(width: 12),
              const Expanded(
                child: Text("Messages",
                  style: TextStyle(color: _white, fontSize: 19, fontWeight: FontWeight.w700))),
              // FIT-005 and FIT-028 both declare `Find a coach`, and the
              // board draws it as an icon-only compass in the header —
              // `<button class="ph ph-compass" aria-label="Find a coach">`.
              // It was not on the screen at all; the coverage tool reported it
              // present because the words appeared in a sentence of body copy.
              _HeaderAction(
                icon: Icons.explore_outlined,
                label: 'Find a coach',
                onTap: () => context.go('/coach-marketplace')),
              const SizedBox(width: 12),
              _HeaderAction(
                icon: Icons.refresh,
                label: 'Refresh',
                onTap: () => ref.invalidate(conversationsProvider)),
            ])),

          // ── Body ──
          //
          // FIT-005 makes this screen a relationship layer, not a conversation
          // list: the coach's threads, then Feed, Groups and What's on. One
          // scroll view holds all four, so a member with two conversations
          // still reaches the rest of their relationships without a second
          // navigation.
          Expanded(
            child: RefreshIndicator(
              color: _brand,
              backgroundColor: _card,
              onRefresh: () async {
                ref.invalidate(conversationsProvider);
                ref.invalidate(livePostsProvider);
                ref.invalidate(liveGroupsProvider);
              },
              child: ListView(children: [
                convsAsync.when(
              // Inside a ListView these states need a bounded height; 320 is
              // roughly a phone's remaining viewport under the header, so they
              // still read as the screen's answer rather than a stray row.
              loading: () => const SizedBox(
                height: 320,
                child: Center(child: CircularProgressIndicator(color: _brand))),
              error: (_, __) => _EmptyState(
                icon: Icons.wifi_off_outlined,
                message: "Couldn't load messages",
                sub: "Tap refresh to try again"),
              data: (convs) {
                if (convs.isEmpty) {
                  // ── FIT-028 · "/messages · the state that sells the plan
                  // honestly" ────────────────────────────────────────────────
                  // A member with no coach has nothing to message and no route
                  // to change that. "No conversations yet" is true but leaves
                  // them stranded.
                  //
                  // THE STATES STAY DISTINCT, AND THE PITCH IS SHOWN ONLY ON
                  // PROOF. Two facts must both be *loaded* before we tell
                  // someone they have no coach: that they are a member rather
                  // than a coach (a coach with no clients is not a sales
                  // prospect), and that their active-coach list really is
                  // empty. If either is still loading or has failed we fall
                  // back to the neutral sentence, which is true in every case.
                  // Collapsing a failed lookup into "you have no coach" is the
                  // error-to-empty defect recorded as F-15, and here it would
                  // also sell a plan to someone who has already bought one.
                  const neutral = _EmptyState(
                    icon: Icons.chat_bubble_outline,
                    message: "No conversations yet",
                    sub: "Your messages with coaches and clients will appear here",
                  );
                  final isMember = ref.watch(currentUserProfileProvider).maybeWhen(
                    data: (p) => p?['role'] != 'coach',
                    orElse: () => false,
                  );
                  if (!isMember) return neutral;
                  return ref.watch(myCoachesProvider).maybeWhen(
                    data: (coaches) => coaches.isEmpty ? const _NoCoachState() : neutral,
                    orElse: () => neutral,
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    for (var i = 0; i < convs.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _ConversationTile(
                        conv: convs[i],
                        onTap: () {
                          ref.read(selectedConversationProvider.notifier).state = convs[i];
                          context.go('/chat');
                        }),
                    ],
                  ]),
                );
              }),
                const ConnectSectionsView(),
                const SizedBox(height: 80),
              ]),
            )),
        ])));
  }
}

// ── Conversation Tile ─────────────────────────────────────────────────────────
class _ConversationTile extends StatelessWidget {
  final Map<String, dynamic> conv;
  final VoidCallback onTap;
  const _ConversationTile({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final participant = conv['participant'] as Map<String, dynamic>?;
    final fn = participant?['first_name'] as String? ?? '';
    final ln = participant?['last_name'] as String? ?? '';
    final name = '$fn $ln'.trim().isEmpty ? 'Unknown' : '$fn $ln'.trim();
    final role = participant?['role'] as String? ?? 'client';
    final lastMsg = conv['last_message'] as String? ?? 'Start the conversation';
    final lastAt = conv['last_message_at'] as String?;
    final timeStr = lastAt != null ? _formatTime(DateTime.parse(lastAt).toLocal()) : '';

    // FIT-005 declares "Open message" for this row. It is NOT used as the
    // accessible name: the name has to contain the visible label (WCAG 2.5.3),
    // and what is visible here is the participant, the last message and its
    // age — which is also what a client needs to hear in order to choose a
    // thread. So the row keeps its content as its name and the design's phrase
    // becomes the HINT, announced after it: "Priya, Hi there, 2h, button,
    // Open message".
    //
    // The same judgement as FIT-002's "Adjust weight or reps", reached the
    // other way round: there the design's phrase belonged on screen, here it
    // belongs beside it.
    return Semantics(
      button: true,
      hint: 'Open message',
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border)),
        child: Row(children: [
          // Avatar
          Stack(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _brand.withValues(alpha: 0.15),
                border: Border.all(color: _brand.withValues(alpha: 0.4), width: 1.5)),
              alignment: Alignment.center,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(color: _brand, fontSize: 20, fontWeight: FontWeight.w800))),
            Positioned(bottom: 1, right: 1,
              child: Container(
                width: 13, height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _green,
                  border: Border.all(color: _card, width: 2)))),
          ]),
          const SizedBox(width: 12),
          // Content
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(name,
                    style: const TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w700))),
                Text(timeStr,
                  style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 11)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _brand.withValues(alpha: 0.25))),
                  child: Text(
                    role[0].toUpperCase() + role.substring(1),
                    style: const TextStyle(color: _primary, fontSize: 9, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 5),
              Text(lastMsg,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 13)),
            ])),
        ]))));
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }
}

/// A named 36 dp chip in the Messages header with a 44 dp target around it.
class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HeaderAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => NamedIconButton(
        label: label,
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            shape: BoxShape.circle),
          child: Icon(icon, color: _white, size: 18),
        ),
      );
}

// ── Empty state ───────────────────────────────────────────────────────────────
/// FIT-028 · Connect — no coach.
///
/// Copy and destination are both already shipped in this repository, so neither
/// is invented: "Find a coach" is the label used at
/// `manage_subscription_screen.dart:241`, and the description and route come
/// from the Coaches module at `directory_screen.dart:59`.
class _NoCoachState extends StatelessWidget {
  const _NoCoachState();

  @override
  Widget build(BuildContext context) => SizedBox(
        // Bounded because FIT-005 put this inside a scroll view; without it the
        // Center has no height to centre in.
        height: 340,
        child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_search_rounded, color: _brand.withValues(alpha: 0.3), size: 52),
            const SizedBox(height: 16),
            const Text('No coach yet',
                textAlign: TextAlign.center,
                style: TextStyle(color: _white, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            // FIT-028's own words, verbatim. The shipped line —
            // "Browse coaches, compare plans and get matched." — was a sales
            // sentence nobody in the package wrote, on the anchor whose
            // sub-title is "the state that sells the plan honestly".
            //
            // The board's annotation says why the difference matters:
            // *"'Self-guided works' is said plainly before the upgrade, which
            // is the difference between an honest prompt and a nag."* So the
            // client's current choice is validated BEFORE the alternative is
            // offered, and the offer describes what a coach adds rather than
            // what the client lacks.
            Text(
                "You're training self-guided, which works. A coach adds "
                'someone who reads your check-ins and adjusts the plan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted.withValues(alpha: 0.7), fontSize: 13, height: 1.5)),
            const SizedBox(height: 22),
            Semantics(
              button: true,
              label: 'Browse coaches',
              excludeSemantics: true,
              onTap: () => context.go('/coach-marketplace'),
              child: GestureDetector(
                onTap: () => context.go('/coach-marketplace'),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _brand,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  // The board's primary control here is `Browse coaches`
                  // (`fc-btn2`); `Find a coach` is the header compass above.
                  // This button said `Find a coach`, so the screen had one of
                  // the two declared controls twice and the other not at all.
                  child: const Text('Browse coaches',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          ]),
        ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message, sub;
  const _EmptyState({required this.icon, required this.message, required this.sub});

  @override
  Widget build(BuildContext context) => SizedBox(
        // Bounded because FIT-005 put this inside a scroll view.
        height: 320,
        child: Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: _brand.withValues(alpha: 0.3), size: 52),
        const SizedBox(height: 16),
        Text(message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _white, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(sub,
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 13)),
      ]))));
}
