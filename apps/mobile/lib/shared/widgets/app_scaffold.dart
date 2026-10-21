// ── WHY THERE IS NO BOTTOM NAV IN THIS FILE ────────────────────────────────
// `AppBottomNav` lived here and drew a THIRD nav vocabulary —
// `Overview · Appts · [FAB] · Track · Messages` — against `app_shell.dart`'s
// live bar and the dead `home_org.dart`'s. It was never instantiated: nothing
// in `lib` referenced it, and `AppScaffold.build` renders a header and a body
// and nothing else.
//
// It went with `navIndex`, a REQUIRED parameter that nine screens computed and
// passed and that no code ever read — the same defect A-G1 records for
// `_IconBtn`'s `tooltip`, which reached neither a Tooltip nor the semantics
// tree. A required argument that is discarded is worse than an unused one: it
// tells nine authors they are configuring something.
//
// The one client bottom nav is `app_shell.dart`, and it is FIT-001's five.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/domain/auth_provider.dart';
import '../../features/notifications/domain/notification_provider.dart';
import '../theme/app_background.dart';

class _C {
  static const surfaceContainer = Color(0xFF201F20);
  static const surface          = Color(0xFF131314);
  static const primary          = Color(0xFFDDB7FF);
  static const onSurface        = Color(0xFFE5E2E3);
  static const error            = Color(0xFFFFB4AB);
}

class AppScaffold extends ConsumerWidget {
  final Widget body;
  final String? title;
  final bool showBackButton;

  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync  = ref.watch(currentUserProfileProvider);
    final currentUser   = ref.watch(currentUserProvider);
    // Try profile first, then user metadata, then email prefix
    final firstName = (profileAsync.valueOrNull?['first_name'] as String?)?.trim().isNotEmpty == true
        ? profileAsync.valueOrNull!['first_name'] as String
        : (currentUser?.userMetadata?['first_name'] as String?)?.trim().isNotEmpty == true
            ? currentUser!.userMetadata!['first_name'] as String
            : currentUser?.email?.split('@').first ?? '';
    final avatarUrl = (profileAsync.valueOrNull?['avatar_url'] as String?)
        ?? (currentUser?.userMetadata?['avatar_url'] as String?);

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _AppHeader(
              title: title,
              showBackButton: showBackButton,
              firstName: firstName,
              avatarUrl: avatarUrl,
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  final String? title;
  final bool showBackButton;
  final String firstName;
  final String? avatarUrl;
  const _AppHeader({this.title, this.showBackButton = false, required this.firstName, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(left: showBackButton ? 8 : 20, right: 20, top: top),
      height: top + 64,
      decoration: BoxDecoration(
        color: _C.surface.withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF353436).withValues(alpha: 0.2), width: 1),
        ),
      ),
      child: Row(
        children: [
          if (showBackButton)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: _C.primary, size: 20),
              tooltip: 'Back',
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
            )
          else
            GestureDetector(
              onTap: () => context.go('/profile'),
              child: _UserAvatar(avatarUrl: avatarUrl),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: title != null
                ? Text(title!,
                    style: const TextStyle(color: _C.primary, fontSize: 18,
                      fontWeight: FontWeight.w800, letterSpacing: 2))
                : _HomeGreeting(firstName: firstName),
          ),
          const _ShakingBellIcon(),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  const _UserAvatar({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _C.primary, width: 2),
        boxShadow: [BoxShadow(color: _C.primary.withValues(alpha: 0.4), blurRadius: 15)],
      ),
      child: ClipOval(
        child: avatarUrl != null
            ? Image.network(avatarUrl!, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultAvatar())
            : _defaultAvatar(),
      ),
    );
  }

  Widget _defaultAvatar() => Container(
    color: _C.surfaceContainer,
    child: const Icon(Icons.person, color: _C.primary, size: 20));
}

class _HomeGreeting extends StatelessWidget {
  final String firstName;
  const _HomeGreeting({required this.firstName});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'GOOD MORNING'
        : hour < 17 ? 'GOOD AFTERNOON'
        : 'GOOD EVENING';
    final displayName = firstName.isNotEmpty ? firstName
        : Supabase.instance.client.auth.currentUser?.email?.split('@').first ?? 'there';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(greeting,
          style: const TextStyle(color: _C.primary, fontSize: 10,
            fontWeight: FontWeight.w600, letterSpacing: 2)),
        Row(children: [
          Text(displayName,
            style: const TextStyle(color: _C.onSurface, fontSize: 20,
              fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(width: 4),
          Icon(Icons.bolt, color: _C.primary, size: 20),
        ]),
      ],
    );
  }
}

class _ShakingBellIcon extends ConsumerStatefulWidget {
  const _ShakingBellIcon();
  @override
  ConsumerState<_ShakingBellIcon> createState() => _ShakingBellIconState();
}

class _ShakingBellIconState extends ConsumerState<_ShakingBellIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.2), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.2, end: -0.2), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.2, end: 0.15), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: -0.1), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.1, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(const Duration(seconds: 1), _startShake);
  }

  void _startShake() {
    if (!mounted) return;
    _ctrl.forward(from: 0).then((_) {
      Future.delayed(const Duration(seconds: 3), _startShake);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    // Real unread count drives the badge; tap opens the notifications screen.
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    return GestureDetector(
      onTap: () => context.go('/notifications'),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _shake,
        builder: (_, child) => Transform.rotate(
          angle: unread > 0 ? _shake.value : 0, child: child),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications, color: _C.primary, size: 26),
            if (unread > 0)
              Positioned(
                top: -3, right: -3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                  decoration: BoxDecoration(
                    shape: unread > 9 ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: unread > 9 ? BorderRadius.circular(8) : null,
                    color: _C.error,
                    boxShadow: [BoxShadow(color: _C.error.withValues(alpha: 0.6), blurRadius: 6)],
                  ),
                  alignment: Alignment.center,
                  child: Text(unread > 9 ? '9+' : '$unread',
                    style: const TextStyle(color: Color(0xFF3A0A06), fontSize: 9,
                      fontWeight: FontWeight.w800, height: 1)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
