import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/domain/auth_provider.dart';
import '../notifications/notification_watcher.dart';
import '../widgets/app_top_nav.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _surfC   = Color(0xFF171F33);
const _primary = Color(0xFFDDB7FF);
const _brand   = Color(0xFFA855F7);
const _onSurfV = Color(0xFFCFC2D6);

// ── App Shell ─────────────────────────────────────────────────────────────────
// Wraps every authenticated screen with the persistent bottom nav.
class AppShell extends StatelessWidget {
  final Widget child;
  final String currentLocation;
  const AppShell({required this.child, required this.currentLocation, super.key});

  @override
  Widget build(BuildContext context) => NotificationWatcher(
    child: Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      body: Column(children: [
        _CoachTopBar(location: currentLocation),
        Expanded(child: child),
        _PersistentNav(location: currentLocation),
      ]),
    ),
  );
}

// ── Dynamic top nav (shared design) ───────────────────────────────────────────
// The unified top nav (avatar + greeting/name + chat + bell). Shown on coach
// screens except the dashboard (which renders its own header). The client Home
// screen renders the same AppTopNavRow design inside its own header (so it can
// keep the pull-down Wellness Pulse panel).
class _CoachTopBar extends ConsumerWidget {
  final String location;
  const _CoachTopBar({required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProfileProvider).valueOrNull?['role'] as String?;
    if (role != 'coach' || location.startsWith('/coach-dashboard')) {
      return const SizedBox.shrink();
    }
    return const AppTopNav();
  }
}

// ── Persistent Bottom Nav ─────────────────────────────────────────────────────
class _PersistentNav extends ConsumerWidget {
  final String location;
  const _PersistentNav({required this.location});

  /// Which of FIT-001's five destinations the current location belongs to.
  ///
  /// `/activity` maps to **Home**, because the design folds it in there —
  /// FIT-001's own sub-title is "Activity folded in · Directory moved to the
  /// top bar". The route still exists and is still reachable; it is no longer
  /// a destination of its own in the bar.
  int get _activeIndex {
    if (location.startsWith('/train') ||
        location.startsWith('/workout') ||
        location.startsWith('/active-workout') ||
        location.startsWith('/exercise')) {
      return 1;
    }
    if (location.startsWith('/meals-dashboard') ||
        location.startsWith('/nutrition') ||
        location.startsWith('/log-meal')) {
      return 2;
    }
    if (location.startsWith('/daily-checkin') ||
        location.startsWith('/checkin') ||
        location.startsWith('/appointments')) {
      return 3;
    }
    if (location.startsWith('/messages') || location.startsWith('/chat')) {
      return 4;
    }
    return 0;
  }

  bool _coachActive(String prefix) => location.startsWith(prefix);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final role = ref.watch(currentUserProfileProvider).valueOrNull?['role'] as String?;

    // ── Coach-specific bottom nav (coach-practical destinations) ──
    if (role == 'coach') {
      return Container(
        padding: EdgeInsets.only(left: 16, right: 16, top: 10, bottom: bottom + 8),
        decoration: BoxDecoration(
          color: _surfC,
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _NavItem(icon: Icons.people_alt_outlined, label: 'Clients',
                active: _coachActive('/coach-dashboard'), onTap: () => context.go('/coach-dashboard')),
            _NavItem(icon: Icons.fact_check_outlined, label: 'Compliance',
                active: _coachActive('/compliance'), onTap: () => context.go('/compliance')),
            _AnimatedFab(onTap: () => context.go('/coach-directory')),
            _NavItem(icon: Icons.library_books_outlined, label: 'Programs',
                active: _coachActive('/program-builder'), onTap: () => context.go('/program-builder')),
            _NavItem(icon: Icons.rate_review_outlined, label: 'Check-ins',
                active: _coachActive('/coach-checkin'), onTap: () => context.go('/coach-checkin-review')),
          ],
        ),
      );
    }

    final idx = _activeIndex;

    // ── FIT-001's five destinations ──────────────────────────────────────
    //
    // The package declares ONE client bottom nav, and declares it in **ten of
    // the eleven** frames that carry one:
    //
    //     Home · Workouts · Nutrition · Check-In · Connect
    //
    // (The eleventh is FIT-001 itself, which prepends `Directory` — its top
    // bar control, not a tab. Its sub-title says so: "Activity folded in ·
    // Directory moved to the top bar".)
    //
    // What shipped was `Home · Train · [FAB] · Activity · Check-In`, and the
    // package resolves every difference itself:
    //
    //   * **the FAB** — FIT-001's annotation: *"Directory, chat and
    //     notifications sit in the top bar; the animated FAB is gone."*
    //     `Directory` is already in `app_top_nav.dart`, so removing the FAB
    //     takes nothing away;
    //   * **Activity** — "folded in". Its content is already on Home
    //     (`weeklyActivityProvider`, the week-progress panel, the score and
    //     streak). `/activity` keeps its route and gains an entry from that
    //     panel, because the tab was its ONLY door and orphaning a screen is
    //     not what "folded in" means (OD-15's lesson);
    //   * **Train → Workouts** — FIT-014's ruling, verbatim: *"the destination
    //     is always `/train`, always labelled Workouts. `coachingModeProvider`
    //     changes what renders here — AI-generated, coach-assigned, or the
    //     self-guided library — **not where the tab goes**."* So the label no
    //     longer varies by mode and AI mode no longer diverts to `/ai-coach`.
    //
    // The two freed slots are `Nutrition` and `Connect`, which is what the
    // package asked for and what **F-14** has been recorded as blocking.
    return Container(
      padding: EdgeInsets.only(left: 16, right: 16, top: 10, bottom: bottom + 8),
      decoration: BoxDecoration(
        color: _surfC,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha:0.07))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _NavItem(icon: Icons.home_outlined,           label: 'Home',      active: idx == 0, onTap: () => context.go('/home')),
          _NavItem(icon: Icons.fitness_center_outlined, label: 'Workouts',  active: idx == 1, onTap: () => context.go('/train')),
          _NavItem(icon: Icons.restaurant_menu_outlined, label: 'Nutrition', active: idx == 2, onTap: () => context.go('/meals-dashboard')),
          _NavItem(icon: Icons.check_circle_outline,    label: 'Check-In',  active: idx == 3, onTap: () => context.go('/daily-checkin')),
          _NavItem(icon: Icons.chat_bubble_outline,     label: 'Connect',   active: idx == 4, onTap: () => context.go('/messages')),
        ],
      ),
    );
  }
}

// ── Nav Item ──────────────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      width: 60,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: active ? _brand.withValues(alpha:0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: active ? _primary : _onSurfV.withValues(alpha:0.5), size: 22)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(
          color: active ? _primary : _onSurfV.withValues(alpha:0.5),
          fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ── Animated 12-Circle FAB ────────────────────────────────────────────────────
class _AnimatedFab extends StatefulWidget {
  final VoidCallback onTap;
  const _AnimatedFab({required this.onTap});
  @override
  State<_AnimatedFab> createState() => _AnimatedFabState();
}

class _AnimatedFabState extends State<_AnimatedFab> with TickerProviderStateMixin {
  late final AnimationController _pulse1;
  late final AnimationController _pulse2;
  late final AnimationController _spin;
  late final Animation<double> _p1Scale, _p1Opacity;
  late final Animation<double> _p2Scale, _p2Opacity;

  @override
  void initState() {
    super.initState();
    _pulse1 = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
    _p1Scale   = Tween<double>(begin: 1.0, end: 2.1).animate(CurvedAnimation(parent: _pulse1, curve: Curves.easeOut));
    _p1Opacity = Tween<double>(begin: 0.75, end: 0.0).animate(CurvedAnimation(parent: _pulse1, curve: Curves.easeOut));

    _pulse2 = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
    _p2Scale   = Tween<double>(begin: 1.0, end: 2.1).animate(CurvedAnimation(parent: _pulse2, curve: Curves.easeOut));
    _p2Opacity = Tween<double>(begin: 0.45, end: 0.0).animate(CurvedAnimation(parent: _pulse2, curve: Curves.easeOut));
    Future.delayed(const Duration(milliseconds: 550), () { if (mounted) _pulse2.repeat(); });

    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  @override
  void dispose() { _pulse1.dispose(); _pulse2.dispose(); _spin.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    child: Transform.translate(
      offset: const Offset(0, -14),
      child: SizedBox(width: 72, height: 72,
        child: Stack(alignment: Alignment.center, children: [
          // Pulse ring 1
          AnimatedBuilder(animation: _pulse1, builder: (_, __) => Transform.scale(
            scale: _p1Scale.value,
            child: Container(width: 56, height: 56,
              decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFA855F7).withValues(alpha:_p1Opacity.value), width: 2))))),
          // Pulse ring 2
          AnimatedBuilder(animation: _pulse2, builder: (_, __) => Transform.scale(
            scale: _p2Scale.value,
            child: Container(width: 56, height: 56,
              decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFD164E2).withValues(alpha:_p2Opacity.value), width: 1.5))))),
          // Spinning arc
          AnimatedBuilder(animation: _spin, builder: (_, __) => Transform.rotate(
            angle: _spin.value * 2 * math.pi,
            child: CustomPaint(size: const Size(68, 68), painter: const _FabArcPainter()))),
          // Main circle
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF1A0D2E), Color(0xFF0D0B1A)],
                center: Alignment.topLeft, radius: 1.2),
              border: Border.all(color: const Color(0xFFA855F7).withValues(alpha:0.5), width: 1.5),
              boxShadow: [BoxShadow(color: const Color(0xFFA855F7).withValues(alpha:0.45), blurRadius: 20, spreadRadius: 2)]),
            child: Center(
              child: Image.asset(
                'assets/images/12circle-fab.png',
                width: 40, height: 40,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.fitness_center_rounded,
                  color: Colors.white, size: 24)))),
        ])),
    ),
  );
}

class _FabArcPainter extends CustomPainter {
  const _FabArcPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    canvas.drawCircle(center, radius,
      Paint()..color = const Color(0xFFA855F7).withValues(alpha:0.12)
             ..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, 1.55 * math.pi, false,
      Paint()
        ..shader = SweepGradient(startAngle: 0, endAngle: 2 * math.pi,
          colors: const [Color(0xFFA855F7), Color(0xFFD164E2), Color(0xFFA855F7), Colors.transparent],
          stops: const [0.0, 0.4, 0.75, 0.76],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(_FabArcPainter _) => false;
}
