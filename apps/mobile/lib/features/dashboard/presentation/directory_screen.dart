import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/domain/auth_provider.dart';
import '../../coach/domain/coach_provider.dart';
import '../../dashboard/domain/dashboard_provider.dart';
import '../../workout/domain/workout_provider.dart';

// ── Colors (matches Stitch design system) ────────────────────────────────────
class _C {
  static const bg           = Color(0xFF0A0A0B);
  static const surfContHigh = Color(0xFF222A3D);
  static const surfContMax  = Color(0xFF2D3449);
  static const primary      = Color(0xFFDDB7FF);
  static const brand        = Color(0xFFA855F7);
  static const onSurface    = Color(0xFFDAE2FD);
  static const onSurfVar    = Color(0xFFCFC2D6);
  static const green        = Color(0xFF4ADE80);
  static const error        = Color(0xFFFFB4AB);
  static const teal         = Color(0xFF6FFBBE);
}

// ── Module data ───────────────────────────────────────────────────────────────
class _Module {
  final String title, description, route;
  final IconData icon;
  final Color iconColor, iconBg;
  final bool isPro;
  final double? progress;
  final String? badge;
  const _Module({
    required this.title, required this.description, required this.route,
    required this.icon, required this.iconColor, required this.iconBg,
    this.isPro = false, this.progress, this.badge,
  });
}

const _featured = _Module(
  title: 'Workouts', route: '/train',
  description: 'Access your personalized training plans and intensity-driven routines.',
  icon: Icons.fitness_center_rounded,
  iconColor: Color(0xFFDDB7FF), iconBg: Color(0x33842BD2),
  badge: 'Active', progress: 0.65,
);

const _gridModules = [
  _Module(title: 'Insights',    route: '/insights',          description: 'Deep biometric analytics and performance data.',  icon: Icons.analytics_rounded,       iconColor: Color(0xFF00E5FF), iconBg: Color(0x2200E5FF), isPro: true),
  _Module(title: 'Nutrition',   route: '/nutrition',         description: 'Meal plans and macro-nutrient tracking.',         icon: Icons.restaurant_rounded,      iconColor: Color(0xFF6FFBBE), iconBg: Color(0x2200A572)),
  _Module(title: 'Tracking',    route: '/progress',          description: 'Visualize your gains with deep analytics.',       icon: Icons.show_chart_rounded,      iconColor: Color(0xFFDDB7FF), iconBg: Color(0x33842BD2)),
  _Module(title: 'Action Items',route: '/action-items',      description: 'Tasks your coach assigned — complete to progress.',icon: Icons.checklist_rounded,      iconColor: Color(0xFFA855F7), iconBg: Color(0x33842BD2)),
  _Module(title: 'Goals',       route: '/goals',             description: 'Set targets and track your progress to them.',    icon: Icons.flag_rounded,            iconColor: Color(0xFF6FFBBE), iconBg: Color(0x2200A572)),
  _Module(title: '12 Circle Score', route: '/score',         description: 'Points, level, badges & the leaderboard.',        icon: Icons.military_tech_rounded,   iconColor: Color(0xFFFFD479), iconBg: Color(0x22FFD479)),
  _Module(title: 'Challenges',  route: '/challenges',        description: 'Join community goals and win badges.',            icon: Icons.emoji_events_rounded,    iconColor: Color(0xFFDDB7FF), iconBg: Color(0x33842BD2)),
  _Module(title: 'Classes',     route: '/classes',           description: 'Browse and book live fitness classes.',           icon: Icons.fitness_center_rounded,  iconColor: Color(0xFFDDB7FF), iconBg: Color(0x33842BD2)),
  _Module(title: 'Events',      route: '/events',            description: 'Upcoming community events and workshops.',        icon: Icons.event_rounded,           iconColor: Color(0xFF6FFBBE), iconBg: Color(0x2200A572)),
  _Module(title: 'Library',     route: '/exercise-library',  description: '500+ exercise guides with HD video.',            icon: Icons.menu_book_rounded,       iconColor: Color(0xFFDDB7FF), iconBg: Color(0x33842BD2)),
  _Module(title: 'Coaches',     route: '/coach-marketplace', description: 'Browse coaches, compare plans and get matched.', icon: Icons.person_search_rounded,   iconColor: Color(0xFFA855F7), iconBg: Color(0x33842BD2)),
  _Module(title: 'Social',      route: '/community',         description: 'Connect with trainers and peers.',               icon: Icons.group_rounded,           iconColor: Color(0xFFADC6FF), iconBg: Color(0x220566D9), isPro: true),
  _Module(title: 'Bookings',    route: '/appointments',      description: 'Schedule 1-on-1 sessions with pros.',            icon: Icons.calendar_month_rounded,  iconColor: Color(0xFFFFB4AB), iconBg: Color(0x2293000A), isPro: true),
];

const _listModules = [
  _Module(title: 'Daily Habits',    route: '/habits',       description: 'Consistency is key. Track your routine.',              icon: Icons.repeat_rounded,     iconColor: Color(0xFFDDB7FF), iconBg: Color(0x33842BD2)),
  _Module(title: 'Weekly Check-ins', route: '/daily-checkin', description: 'Reflect on your week and get coach feedback.',        icon: Icons.calendar_today_rounded, iconColor: Color(0xFFDDB7FF), iconBg: Color(0x33842BD2)),
];

// ── Directory Screen ──────────────────────────────────────────────────────────
class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key});
  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen> {
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent));
    final topPad = MediaQuery.of(context).padding.top;
    final currentUser = ref.watch(currentUserProvider);
    final metaFirst = currentUser?.userMetadata?['first_name'] as String? ?? '';
    final userName = metaFirst.isNotEmpty ? metaFirst : currentUser?.email?.split('@').first ?? '';

    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(children: [
        // ── Body (blur header overlaid on scroll content) ────────────
        Expanded(
          child: Stack(children: [
            SingleChildScrollView(
              padding: EdgeInsets.only(top: topPad + 64 + 16, left: 20, right: 20, bottom: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _PageTitle(),
                const SizedBox(height: 20),
                _FeaturedCard(module: _featured),
                const SizedBox(height: 24),
                _SectionLabel(label: 'Explore Modules'),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.0,
                  children: _gridModules.map((m) => _GridCard(module: m)).toList(),
                ),
                const SizedBox(height: 24),
                _SectionLabel(label: 'Daily Tools'),
                const SizedBox(height: 12),
                ..._listModules.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ListCard(module: m),
                )),
                const SizedBox(height: 8),
                _CoachMarketplaceBanner(),
                const SizedBox(height: 12),
                _PremiumBanner(),
              ]),
            ),
            // Fixed blur header
            Positioned(
              top: 0, left: 0, right: 0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: topPad + 64,
                    padding: EdgeInsets.only(top: topPad, left: 20, right: 20),
                    decoration: BoxDecoration(
                      color: _C.bg.withValues(alpha: 0.6),
                      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => context.go('/profile'),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _C.primary.withValues(alpha: 0.3), width: 2),
                            boxShadow: [BoxShadow(color: _C.brand.withValues(alpha: 0.25), blurRadius: 12)]),
                          child: ClipOval(child: Image.asset('assets/images/dumbell.png', fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: _C.surfContHigh,
                              child: const Icon(Icons.person_rounded, color: _C.primary, size: 20)))))),
                      const SizedBox(width: 12),
                      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Good Morning', style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                        Text(userName, style: const TextStyle(color: _C.onSurface, fontSize: 20, fontWeight: FontWeight.w700)),
                      ]),
                      const Spacer(),
                      _IconBtn(icon: Icons.chat_bubble_outline_rounded, onTap: () => context.go('/messages')),
                      const SizedBox(width: 8),
                      _BellBtn(),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Header helpers ────────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x08FFFFFF), border: Border.all(color: const Color(0x0DFFFFFF))),
      child: Icon(icon, color: _C.onSurfVar, size: 20)));
}

class _BellBtn extends StatefulWidget {
  @override
  State<_BellBtn> createState() => _BellBtnState();
}
class _BellBtnState extends State<_BellBtn> with SingleTickerProviderStateMixin {
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
    Future.delayed(const Duration(seconds: 1), _loop);
  }
  void _loop() { if (!mounted) return; _ctrl.forward(from: 0).then((_) => Future.delayed(const Duration(seconds: 3), _loop)); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DirectoryNotificationsPanel(),
    ),
    child: AnimatedBuilder(
      animation: _shake,
      builder: (_, child) => Transform.rotate(angle: _shake.value, child: child),
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x08FFFFFF), border: Border.all(color: const Color(0x0DFFFFFF))),
        child: Stack(alignment: Alignment.center, children: [
          Icon(Icons.notifications_outlined, color: _C.onSurfVar, size: 20),
          Positioned(top: 8, right: 8, child: Container(width: 7, height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _C.error,
              boxShadow: [BoxShadow(color: _C.error.withValues(alpha: 0.6), blurRadius: 4)]))),
        ]))));
}

// ── Directory Notifications Panel ─────────────────────────────────────────────
class _DirectoryNotificationsPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(upcomingClassesProvider);
    final eventsAsync  = ref.watch(upcomingEventsProvider);
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0911),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: const Color(0xFF4D4354), borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Text('Notifications', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const Spacer(),
            Semantics(
              button: true,
              label: 'Close',
              child: GestureDetector(
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.opaque,
              child: Container(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                alignment: Alignment.center,
                child: const Icon(Icons.close_rounded, color: Color(0xFF4D4354), size: 22)))),
          ]),
        ),
        const SizedBox(height: 16),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Upcoming classes
              classesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2)),
                error: (_, __) => const SizedBox.shrink(),
                data: (classes) {
                  if (classes.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _NotifSectionLabel(label: 'Upcoming Classes'),
                    const SizedBox(height: 10),
                    ...classes.map((c) => _NotifItem(
                      icon: Icons.fitness_center_rounded,
                      iconColor: _C.primary,
                      title: c['name'] as String? ?? 'Class',
                      subtitle: _fmtDate(c['scheduled_at'] as String?),
                      badge: '${c['capacity'] as int? ?? 0} spots',
                      onTap: () { Navigator.pop(context); context.go('/appointments'); },
                    )),
                  ]);
                },
              ),
              const SizedBox(height: 16),
              // Upcoming events
              eventsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (events) {
                  if (events.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _NotifSectionLabel(label: 'Upcoming Events'),
                    const SizedBox(height: 10),
                    ...events.map((e) => _NotifItem(
                      icon: Icons.event_rounded,
                      iconColor: _C.teal,
                      title: e['name'] as String? ?? 'Event',
                      subtitle: _fmtDate(e['event_date'] as String?),
                      badge: e['location'] as String? ?? '',
                      onTap: () { Navigator.pop(context); context.go('/book-call'); },
                    )),
                  ]);
                },
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final m = d.minute.toString().padLeft(2, '0');
      final ampm = d.hour < 12 ? 'AM' : 'PM';
      return '${months[d.month - 1]} ${d.day} • $h:$m $ampm';
    } catch (_) { return ''; }
  }
}

class _NotifSectionLabel extends StatelessWidget {
  final String label;
  const _NotifSectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 3, height: 14, decoration: BoxDecoration(color: _C.brand, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(label.toUpperCase(), style: TextStyle(color: _C.primary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
  ]);
}

class _NotifItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle, badge;
  final VoidCallback onTap;
  const _NotifItem({required this.icon, required this.iconColor, required this.title,
    required this.subtitle, required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF))),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: iconColor.withValues(alpha: 0.15)),
          child: Icon(icon, color: iconColor, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.6), fontSize: 12)),
        ])),
        if (badge.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: iconColor.withValues(alpha: 0.2))),
            child: Text(badge, style: TextStyle(color: iconColor, fontSize: 10, fontWeight: FontWeight.w600))),
      ]),
    ),
  );
}

// ── Glass Card helper ─────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? border;
  final Color? bg;
  const _GlassCard({required this.child, this.padding, this.border, this.bg});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: bg ?? const Color(0x08FFFFFF),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: border ?? const Color(0x33A855F7))),
    child: child);
}

// ── Page Title ────────────────────────────────────────────────────────────────
class _PageTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('App Directory',
      style: const TextStyle(color: _C.onSurface, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1)),
    const SizedBox(height: 6),
    Text('Explore all fitness modules and tracking tools.',
      style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7), fontSize: 14, height: 1.4)),
  ]);
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 3, height: 16, decoration: BoxDecoration(color: _C.brand, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(label.toUpperCase(), style: TextStyle(color: _C.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
  ]);
}

// ── Featured Card ─────────────────────────────────────────────────────────────
class _FeaturedCard extends ConsumerWidget {
  final _Module module;
  const _FeaturedCard({required this.module});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workouts = ref.watch(assignedWorkoutsProvider).valueOrNull ?? const [];
    final statusMap = ref.watch(programSessionStatusProvider).valueOrNull ?? const {};

    // Find an in-progress workout, plus program-level completion.
    dynamic inProgress;
    var loggedSets = 0;
    var totalSetsInProgress = 0;
    var completedCount = 0;
    for (final w in workouts) {
      // By identity — two days of a generated program can share a title, and a
      // title-keyed lookup marked both of them as the one in progress.
      final entry = sessionStatusFor(statusMap, w);
      final st = entry?['status'] as String?;
      if (st == 'completed') completedCount++;
      if (st == 'in_progress' && inProgress == null) {
        inProgress = w;
        loggedSets = (entry?['logged_sets'] as int?) ?? 0;
        totalSetsInProgress = w.exercises.fold<int>(0, (s, e) => s + e.sets.length);
      }
    }
    final hasProgram = workouts.isNotEmpty;

    // Dynamic content.
    final String title;
    final String description;
    final String badgeText;
    final double? progress;
    final String btnLabel;
    if (inProgress != null) {
      title = inProgress.title as String;
      description = 'Resume your session — ${inProgress.exercises.length} exercises · ~${inProgress.estimatedDuration} min.';
      badgeText = 'In Progress';
      progress = totalSetsInProgress > 0 ? (loggedSets / totalSetsInProgress).clamp(0.0, 1.0) : null;
      btnLabel = 'Resume Workout';
    } else if (hasProgram) {
      final next = workouts.first;
      title = next.title;
      description = '${workouts.length} workouts in your plan · ${next.exercises.length} exercises · ~${next.estimatedDuration} min next.';
      badgeText = completedCount >= workouts.length ? 'Complete' : 'Ready';
      progress = workouts.isNotEmpty ? (completedCount / workouts.length).clamp(0.0, 1.0) : null;
      btnLabel = 'Start Workout';
    } else {
      title = 'Workouts';
      description = module.description;
      badgeText = 'Active';
      progress = null;
      btnLabel = 'Start Workout';
    }

    void onAction() {
      if (inProgress != null) {
        ref.read(selectedWorkoutProvider.notifier).state = inProgress;
        context.go('/active-workout');
      } else {
        context.go('/workouts');
      }
    }

    return GestureDetector(
      onTap: () => context.go(module.route),
      child: _GlassCard(
        padding: const EdgeInsets.all(20),
        border: _C.brand.withValues(alpha: 0.4),
        bg: _C.brand.withValues(alpha: 0.05),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: module.iconBg, borderRadius: BorderRadius.circular(16)),
              child: Icon(module.icon, color: module.iconColor, size: 26)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _C.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _C.green.withValues(alpha: 0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: _C.green)),
                const SizedBox(width: 5),
                Text(badgeText, style: const TextStyle(color: _C.green, fontSize: 11, fontWeight: FontWeight.w600)),
              ])),
          ]),
          const SizedBox(height: 16),
          Text(title,
            style: const TextStyle(color: _C.onSurface, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: 6),
          Text(description,
            style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.8), fontSize: 14, height: 1.5)),
          if (progress != null) ...[
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(inProgress != null ? 'Session progress' : 'Plan progress',
                style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.6), fontSize: 12)),
              Text('${(progress * 100).round()}%',
                style: const TextStyle(color: _C.primary, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: _C.surfContMax,
                valueColor: const AlwaysStoppedAnimation<Color>(_C.brand),
                minHeight: 5)),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: onAction,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFDDB7FF), Color(0xFFD164E2)]),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: _C.primary.withValues(alpha: 0.3), blurRadius: 16)]),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(inProgress != null ? Icons.play_circle_outline : Icons.play_arrow_rounded,
                    color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  Text(btnLabel, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ])))),
          ]),
        ]),
      ),
    );
  }
}

// ── Grid Card ─────────────────────────────────────────────────────────────────
class _GridCard extends StatelessWidget {
  final _Module module;
  const _GridCard({required this.module});

  @override
  Widget build(BuildContext context) {
    final accent = module.iconColor;
    return GestureDetector(
      onTap: () => context.go(module.route),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // Per-module color tint over the dark base — makes the grid pop.
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.14), const Color(0xFF101829)]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.30), blurRadius: 12)]),
              child: Icon(module.icon, color: accent, size: 22)),
            if (module.isPro)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _C.brand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _C.brand.withValues(alpha: 0.3))),
                child: Text('PRO', style: TextStyle(color: _C.primary, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1))),
          ]),
          const Spacer(),
          Text(module.title,
            style: const TextStyle(color: _C.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(module.description,
            style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.6), fontSize: 11, height: 1.4),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

// ── List Card ─────────────────────────────────────────────────────────────────
class _ListCard extends StatelessWidget {
  final _Module module;
  const _ListCard({required this.module});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(module.route),
      child: _GlassCard(
        padding: const EdgeInsets.all(16),
        bg: const Color(0x08FFFFFF),
        border: module.iconColor.withValues(alpha: 0.18),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: module.iconColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: module.iconColor.withValues(alpha: 0.28)),
              boxShadow: [BoxShadow(color: module.iconColor.withValues(alpha: 0.22), blurRadius: 10)]),
            child: Icon(module.icon, color: module.iconColor, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(module.title,
              style: const TextStyle(color: _C.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(module.description,
              style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.6), fontSize: 13, height: 1.3)),
          ])),
          Icon(Icons.chevron_right_rounded, color: _C.onSurfVar.withValues(alpha: 0.4), size: 22),
        ]),
      ),
    );
  }
}

// ── Coach Marketplace Banner ──────────────────────────────────────────────────
class _CoachMarketplaceBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coachAsync = ref.watch(assignedCoachProvider);
    final coach = coachAsync.valueOrNull;
    // Don't show if already has a coach
    if (coach != null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => context.push('/coach-marketplace'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2D1260), Color(0xFF1A0A3D)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _C.brand.withValues(alpha: 0.35)),
          boxShadow: [BoxShadow(color: _C.brand.withValues(alpha: 0.15), blurRadius: 20)]),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.brand.withValues(alpha: 0.2)),
            child: const Icon(Icons.person_search_rounded, color: _C.primary, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Find Your Coach',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Browse coaches, compare prices, and get personalised training.',
              style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7), fontSize: 12, height: 1.3)),
          ])),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_ios_rounded, color: _C.primary.withValues(alpha: 0.7), size: 16),
        ]),
      ),
    );
  }
}

// ── Premium Banner ────────────────────────────────────────────────────────────
class _PremiumBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/upgrade'),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 148,
        child: Stack(fit: StackFit.expand, children: [
          Image.asset('assets/images/directory-premium-bg.jpg', fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A0A35), Color(0xFF0A0A0B)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight)))),
          const DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xCC0B1326), Color(0x660B1326)],
              begin: Alignment.centerLeft, end: Alignment.centerRight))),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _C.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _C.primary.withValues(alpha: 0.3))),
                child: Text('PREMIUM ACCESS',
                  style: TextStyle(color: _C.primary, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5))),
              const SizedBox(height: 8),
              const Text('12 Circle Pro Series',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              const SizedBox(height: 4),
              Text('Unlock elite modules and deep performance data.',
                style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7), fontSize: 13)),
            ])),
        ]))));
  }
}
