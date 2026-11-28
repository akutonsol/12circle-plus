import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/domain/auth_provider.dart';
import '../../features/notifications/domain/notification_provider.dart';

// ── Palette (matches the new Home design) ──────────────────────────────────────
const _kMuted = Color(0xFF9A9AA0);
const _kIconFg = Color(0xFFC9A6FF);
const _kPink = Color(0xFFFF4D8D);
const _kDotRing = Color(0xFF0C0911);

String greetingForNow() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String initialsFrom(String first, String last) {
  final f = first.trim();
  final l = last.trim();
  if (f.isEmpty && l.isEmpty) return 'U';
  final a = f.isNotEmpty ? f[0] : '';
  final b = l.isNotEmpty ? l[0] : '';
  final s = '$a$b';
  return (s.isEmpty ? f.substring(0, 1) : s).toUpperCase();
}

/// The unread count a header's bell shows and says (P0-FL-61).
///
/// `unreadCountProvider` carries the previous account's number through the
/// next one's read, and through its failure. So a number is kept here under
/// the uid it was read for, dropped as soon as another uid (or nobody) is
/// signed in, and replaced only by a settled read: the uid and the read are
/// watched in the same build, and an account change restarts the read, so what
/// is settled then is that uid's.
mixin SignedInUnread<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  int? _count;
  String? _countUid;

  /// Null while the signed-in account's count is not known, so it is never
  /// said as "none" and never drawn: nobody has read it yet, or its last read
  /// FAILED (P0-FL-63c). A failed re-count is unknown, not the number before
  /// it — after a confirmed 0 it was said as "none unread". A re-count still
  /// running for the same account keeps the last confirmed one (no flicker on
  /// each live event); one that follows a failure stays unknown until it
  /// answers. Call it in `build`.
  int? watchUnread() {
    final uid = ref.watch(currentUserProvider.select((u) => u?.id));
    final read = ref.watch(unreadCountProvider);
    if (uid == null || uid != _countUid || read.hasError) _count = null;
    _countUid = uid;
    if (uid != null && !read.isLoading && !read.hasError) _count = read.value;
    return _count;
  }
}

/// What a bell says about [count] after its name; null = nothing is known.
String? unreadDetail(int? count) => switch (count) {
      null => null,
      0 => 'none unread',
      _ => '$count unread',
    };

/// The shared top nav content (avatar + greeting/name on the left, chat + bell
/// on the right). Used both by the app shell (wrapped in [AppTopNav]) and the
/// Home screen header, so the design stays consistent platform-wide.
class AppTopNavRow extends ConsumerWidget {
  const AppTopNavRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // P0-FL-45b: only a row read for the member signed in now; the previous
    // member's name/avatar were held through the new member's read.
    final profile = ref.watch(confirmedCurrentProfileProvider);
    // The profile row can be momentarily null (e.g. right after a hot reload),
    // which used to drop the header to "there"/"U". Fall back to the auth user's
    // metadata + email — the same chain the Profile screen uses — so a signed-in
    // user always sees their real name/avatar. Also covers OAuth metadata keys.
    final authUser = ref.watch(currentUserProvider);
    final meta = authUser?.userMetadata ?? const <String, dynamic>{};
    String pick(String? a, List<String?> fallbacks) {
      if (a != null && a.trim().isNotEmpty) return a.trim();
      for (final f in fallbacks) {
        if (f != null && f.trim().isNotEmpty) return f.trim();
      }
      return '';
    }

    final fullName = meta['full_name'] as String? ?? meta['name'] as String?;
    final first = pick(profile?['first_name'] as String?, [
      meta['first_name'] as String?,
      meta['given_name'] as String?,
      fullName?.split(' ').first,
    ]);
    final last = pick(profile?['last_name'] as String?, [
      meta['last_name'] as String?,
      meta['family_name'] as String?,
    ]);
    final email = pick(profile?['email'] as String?, [authUser?.email]);
    final name = first.isNotEmpty
        ? first
        : (email.isNotEmpty ? email.split('@').first : 'there');
    final avatarUrl = pick(profile?['avatar_url'] as String?, [
      meta['avatar_url'] as String?,
      meta['picture'] as String?,
    ]);

    return Row(children: [
      // Avatar — gradient ring with initials.
      // 42 x 42 — two dp under the floor, on the control that appears in
      // every screen's top bar. The ring keeps its 42 dp look; the hit area
      // is lifted to 44 around it.
      GestureDetector(
        onTap: () => context.go('/profile'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          alignment: Alignment.center,
          child: Container(
            width: 42,
            height: 42,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFB06BFF), Color(0xFFFF4D8D)],
              ),
            ),
            child: ClipOval(
              child: avatarUrl.isNotEmpty
                  ? Image.network(avatarUrl,
                      fit: BoxFit.cover,
                      width: 38,
                      height: 38,
                      errorBuilder: (_, __, ___) =>
                          _initialsAvatar(first, last))
                  : _initialsAvatar(first, last),
            ),
          ),
        ),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(greetingForNow(),
                style: const TextStyle(
                    color: _kMuted, fontSize: 11, fontWeight: FontWeight.w500)),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2)),
          ],
        ),
      ),
      // FIT-001 places three controls in the Home bar: Directory, Messages,
      // Notifications. Directory was absent. The design moves it here from the
      // bottom FAB ("Activity folded in · Directory moved to the top bar"),
      // which is what frees a bottom slot without stranding /events, /classes,
      // /challenges or /community — see F-14 in docs/QA_EVIDENCE.md.
      _NavIconButton(
        icon: Icons.explore_outlined,
        label: 'Directory',
        onTap: () => context.go('/directory'),
      ),
      _NavIconButton(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'Messages',
        onTap: () => context.go('/messages'),
      ),
      const _NavBell(),
    ]);
  }
}

class _NavBell extends ConsumerStatefulWidget {
  const _NavBell();
  @override
  ConsumerState<_NavBell> createState() => _NavBellState();
}

class _NavBellState extends ConsumerState<_NavBell> with SignedInUnread {
  @override
  Widget build(BuildContext context) {
    final unread = watchUnread();
    return _NavIconButton(
      icon: Icons.notifications_none_rounded,
      label: 'Notifications',
      detail: unreadDetail(unread),
      showDot: (unread ?? 0) > 0,
      onTap: () => context.push('/notifications'),
    );
  }
}

Widget _initialsAvatar(String first, String last) => Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF1A1620),
      ),
      alignment: Alignment.center,
      child: Text(initialsFrom(first, last),
          style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
    );

class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final bool showDot;
  final VoidCallback onTap;

  /// Accessible name. These are icon-only controls: without it the tree reports
  /// them unlabelled and a screen reader announces nothing. FIT-001 supplies
  /// the wording for all three ("Directory", "Messages", "Notifications"), so
  /// none of it is invented here.
  final String label;

  /// Said after [label]: what the dot shows, which is drawn only.
  final String? detail;
  const _NavIconButton({
    required this.icon,
    this.detail,
    this.showDot = false,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: detail == null ? label : '$label, $detail',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          // The visual chip stays 38px — the design's `tap` component is a 44x44
          // TARGET, not a 44px box. Constraining the hit area rather than the
          // decoration keeps the bar's appearance and clears the floor.
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            alignment: Alignment.center,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Stack(alignment: Alignment.center, children: [
                Icon(icon, color: _kIconFg, size: 18),
                if (showDot)
                  Positioned(
                    top: 8,
                    right: 9,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _kPink,
                        shape: BoxShape.circle,
                        border: Border.all(color: _kDotRing, width: 1.5),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
}

/// Full top bar for the app shell: safe-area padding + subtle bottom border.
class AppTopNav extends StatelessWidget {
  const AppTopNav({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: top + 8, left: 16, right: 16, bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0B),
        border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: const AppTopNavRow(),
    );
  }
}
