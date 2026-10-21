import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../../../core/utils/web_logout.dart';
import '../../auth/domain/auth_provider.dart';
import '../../coach/domain/coach_provider.dart';
import '../../coaching_mode/domain/coaching_mode_provider.dart';
import '../../payments/domain/entitlements.dart';
import '../domain/connected_apps.dart';

class _C {
  static const bg                  = Color(0xFF0A0A0B);
  static const surfaceContainer    = Color(0xFF201F20);
  static const surfaceContainerHigh= Color(0xFF2A2A2B);
  static const surfaceContainerMax = Color(0xFF353436);
  static const glassCard           = Color(0x99201F20);
  static const primary             = Color(0xFFDDB7FF);
  static const inversePrimary      = Color(0xFF842BD2);
  static const onSurface           = Color(0xFFE5E2E3);
  static const onSurfaceVar        = Color(0xFFCDC3D0);
  static const outline             = Color(0xFF968E99);
  static const outlineVar          = Color(0xFF4B444F);
  static const tertiary            = Color(0xFF6FFBBE);
  static const secondary           = Color(0xFFADC6FF);
  static const error               = Color(0xFFFFB4AB);
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final currentUser  = ref.watch(currentUserProvider);
    final profile      = profileAsync.valueOrNull;

    final firstName = profile?['first_name'] as String?
        ?? currentUser?.userMetadata?['first_name'] as String?
        ?? currentUser?.email?.split('@').first
        ?? '';
    final lastName  = profile?['last_name'] as String? ?? '';
    final displayName = '$firstName $lastName'.trim().isEmpty ? 'Member' : '$firstName $lastName'.trim();
    final email = profile?['email'] as String? ?? currentUser?.email ?? '';
    final role = profile?['role'] as String?
        ?? currentUser?.userMetadata?['role'] as String?
        ?? 'client';
    final isCoach     = role == 'coach';
    final avatarUrl   = profile?['avatar_url']      as String?;
    // Real effective plan (Coach-Guided / AI / Self / Free) — not the raw column.
    final memberTier  = (ref.watch(clientPlanProvider).valueOrNull ?? ClientPlan.free).label;
    final unitPref    = profile?['unit_preference'] as String? ?? 'imperial';
    final coachingMode= ref.watch(coachingModeProvider);

    // Real fitness data
    final weightKg     = (profile?['weight_kg']      as num?)?.toDouble();
    final goalKg       = (profile?['weight_goal_kg']  as num?)?.toDouble();
    final heightCm     = (profile?['height_cm']       as num?)?.toDouble();
    final trainingDays = (profile?['training_days_per_week'] as num?)?.toInt() ?? 0;
    final fitnessGoal  = profile?['fitness_goal']     as String?;
    final activityLevel= profile?['activity_level']   as String?;

    // Weight progress % toward goal
    double weightProgress = 0;
    if (weightKg != null && goalKg != null && weightKg > 0 && goalKg > 0) {
      weightProgress = (weightKg / goalKg).clamp(0.0, 1.0);
    }

    String _fmt(double? kg) {
      if (kg == null) return '—';
      return '${kg.toStringAsFixed(1)} kg';
    }
    String _fmtHeight(double? cm) {
      if (cm == null) return '—';
      return '${cm.toStringAsFixed(0)} cm';
    }
    String _goalLabel(String? g) {
      if (g == null) return 'Not set';
      return g.replaceAll('_', ' ').split(' ')
          .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }

    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(children: [
        // ── Top Bar ──
        Container(
          padding: EdgeInsets.only(left: 20, right: 12, top: top),
          decoration: BoxDecoration(
            color: _C.glassCard,
            border: const Border(bottom: BorderSide(color: Color(0x1A4B444F)))),
          child: SizedBox(height: 56, child: Row(children: [
            const Expanded(child: Text('PROFILE',
              style: TextStyle(color: _C.primary, fontSize: 18,
                fontWeight: FontWeight.w800, letterSpacing: 2))),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: _C.primary, size: 22),
              onPressed: () => context.push('/settings')),
          ]))),

        Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Profile Header ──
            Center(
              child: Column(
                children: [
                  // Avatar with gradient ring
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 112, height: 112,
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [_C.primary, _C.inversePrimary, _C.primary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [BoxShadow(color: Color(0x4DDDB7FF), blurRadius: 20)],
                        ),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _C.bg,
                          ),
                          padding: const EdgeInsets.all(3),
                          child: ClipOval(
                            child: avatarUrl != null
                              ? Image.network(avatarUrl, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: _C.surfaceContainer,
                                    child: const Icon(Icons.person, color: _C.primary, size: 40)))
                              : Container(
                                  color: _C.surfaceContainer,
                                  child: const Icon(Icons.person, color: _C.primary, size: 40))),
                        ),
                      ),
                      Positioned(
                        bottom: -2, right: -2,
                        child: Container(
                          width: 32, height: 32,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _C.primary,
                            boxShadow: [BoxShadow(color: Color(0x4DDDB7FF), blurRadius: 10)],
                          ),
                          child: const Icon(Icons.verified, color: Color(0xFF490080), size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(displayName,
                    style: const TextStyle(
                      color: _C.onSurface,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    )),
                  const SizedBox(height: 8),
                  Text(email,
                    style: const TextStyle(color: _C.outline, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Chip(label: isCoach ? 'Coach' : 'Member', color: _C.primary),
                      if (fitnessGoal != null) ...[
                        const SizedBox(width: 8),
                        _Chip(label: _goalLabel(fitnessGoal), color: _C.tertiary),
                      ],
                      const SizedBox(width: 8),
                      _Chip(label: coachingMode.displayName, color: _C.secondary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => context.push('/personal-info'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: _C.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _C.outlineVar)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.edit_outlined, color: _C.onSurfaceVar, size: 14),
                        SizedBox(width: 6),
                        Text('Edit Profile', style: TextStyle(
                          color: _C.onSurfaceVar, fontSize: 13,
                          fontWeight: FontWeight.w500)),
                      ]))),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Stats Grid + Fitness Goals + My Coach (client-only) ──
            if (!isCoach) ...[
            Row(
              children: [
                Expanded(child: _StatCard(value: _fmtHeight(heightCm), label: 'HEIGHT')),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(value: _fmt(weightKg), label: 'CURRENT\nWEIGHT')),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(value: _fmt(goalKg), label: 'GOAL\nWEIGHT')),
              ],
            ),
            const SizedBox(height: 28),

            // ── Fitness Goals ──
            const _SectionLabel(label: 'FITNESS GOALS'),
            const SizedBox(height: 12),

            // Weight goal - full width
            _GlassCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('WEIGHT GOAL',
                        style: TextStyle(color: _C.tertiary, fontSize: 10,
                          fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                      const SizedBox(height: 6),
                      RichText(
                        text: TextSpan(children: [
                          TextSpan(text: _fmt(weightKg),
                            style: const TextStyle(color: _C.onSurface, fontSize: 20,
                              fontWeight: FontWeight.w700)),
                          TextSpan(text: ' / ${_fmt(goalKg)}',
                            style: const TextStyle(color: _C.onSurfaceVar, fontSize: 14)),
                        ]),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 56, height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(56, 56),
                          painter: _MiniRingPainter(progress: weightProgress, color: _C.tertiary),
                        ),
                        Text('${(weightProgress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(color: _C.onSurface, fontSize: 10,
                            fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                // Weekly training target
                Expanded(
                  child: _GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('WEEKLY TARGET',
                          style: TextStyle(color: _C.primary, fontSize: 9,
                            fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(text: '$trainingDays',
                              style: const TextStyle(color: _C.onSurface, fontSize: 20,
                                fontWeight: FontWeight.w800)),
                            const TextSpan(text: ' days / wk',
                              style: TextStyle(color: _C.onSurfaceVar, fontSize: 12)),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: List.generate(7, (i) => Expanded(
                            child: Container(
                              height: 4,
                              margin: EdgeInsets.only(right: i < 6 ? 3 : 0),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: i < trainingDays ? _C.primary : _C.surfaceContainerMax,
                              ),
                            ),
                          )),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Activity level
                Expanded(
                  child: _GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ACTIVITY LEVEL',
                          style: TextStyle(color: _C.secondary, fontSize: 9,
                            fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                        const SizedBox(height: 8),
                        Text(
                          activityLevel != null
                            ? activityLevel.replaceAll('_', ' ').split(' ')
                                .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
                                .join(' ')
                            : 'Not set',
                          style: const TextStyle(color: _C.secondary, fontSize: 16,
                            fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: activityLevel == null ? 0
                              : activityLevel.contains('sedentary') ? 0.2
                              : activityLevel.contains('light') ? 0.4
                              : activityLevel.contains('moderate') ? 0.6
                              : activityLevel.contains('very') ? 0.85
                              : 1.0,
                            backgroundColor: _C.surfaceContainerMax,
                            valueColor: const AlwaysStoppedAnimation<Color>(_C.secondary),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── My Coach (only in Coach-Guided mode; self/AI have no coach) ──
            if (coachingMode == CoachingMode.coachGuided) ...[
              MyCoachSection(onCoachCancelled: () {
                ref.invalidate(assignedCoachProvider);
                ref.invalidate(clientRelationshipProvider);
              }),
              const SizedBox(height: 28),
            ],
            ],

            // ── Account Settings ──
            const _SectionLabel(label: 'ACCOUNT SETTINGS'),
            const SizedBox(height: 12),
            _GlassCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                // FIT-029's wording. "Personal Info" was an abbreviation the
                // locked screen writes out in full.
                _ProfileRow(
                  icon: Icons.person_outline,
                  label: 'Personal information',
                  hasBorder: true,
                  onTap: () => context.push('/personal-info'),
                ),
                // FIT-029's "You" list declares `Goals` and `Connected apps`
                // between `Personal information` and the plan row. Neither was
                // on the screen.
                //
                // `/goals` is REGISTERED and nothing in the app navigated to
                // it — the third orphaned route this cycle has found by asking
                // what a declared control opens, after `/activity` and
                // `/meal-plan`. This row is its door.
                _ProfileRow(
                  icon: Icons.flag_outlined,
                  label: 'Goals',
                  hasBorder: true,
                  onTap: () => context.push('/goals'),
                ),
                // The count is live, from the same `user_integrations` rows
                // the integrations screen reads, so the row and the screen
                // behind it cannot disagree. No badge when nothing is
                // connected, while it loads, or if the read fails — see
                // `connectedAppsBadge`.
                Consumer(builder: (context, ref, _) {
                  final badge =
                      connectedAppsBadge(ref.watch(connectedAppsCountProvider));
                  return _ProfileRow(
                    icon: Icons.watch_outlined,
                    label: 'Connected apps',
                    hasBorder: true,
                    trailing: badge == null
                        ? null
                        : Text(badge,
                            style: const TextStyle(
                                color: _C.onSurfaceVar,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                    onTap: () => context.push('/integrations'),
                  );
                }),
                _ProfileRow(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  hasBorder: true,
                  onTap: () => context.push('/notification-preferences'),
                ),
                if (!isCoach) _ProfileRow(
                  icon: Icons.card_membership_outlined,
                  label: 'Subscription',
                  hasBorder: true,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _C.tertiary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _C.tertiary.withValues(alpha: 0.3)),
                    ),
                    child: Text(memberTier.toUpperCase(),
                      style: const TextStyle(color: _C.tertiary, fontSize: 10,
                        fontWeight: FontWeight.w700)),
                  ),
                  onTap: () => context.push('/subscription'),
                ),
                _ProfileRow(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  hasBorder: false,
                  onTap: () => context.go('/settings'),
                ),
              ]),
            ),
            const SizedBox(height: 28),

            // ── App Preferences ──
            const _SectionLabel(label: 'APP PREFERENCES'),
            const SizedBox(height: 12),
            _GlassCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _ProfileRow(
                  icon: Icons.straighten_outlined,
                  label: 'Units',
                  iconColor: _C.secondary,
                  trailing: Text(unitPref.toUpperCase(),
                    style: const TextStyle(color: _C.onSurfaceVar, fontSize: 11,
                      fontWeight: FontWeight.w600, letterSpacing: 1)),
                  hasBorder: true,
                  onTap: () => context.go('/settings'),
                ),
                _ProfileRow(
                  icon: Icons.dark_mode_outlined,
                  label: 'Dark Mode',
                  iconColor: _C.secondary,
                  trailing: Container(
                    width: 44, height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: _C.primary,
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 3),
                    child: Container(
                      width: 18, height: 18,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.white),
                    ),
                  ),
                  hasBorder: true,
                  onTap: () => context.go('/settings'),
                ),
                // FIT-029 calls this "Connected apps". It draws a count beside
                // it ("Connected apps 2") — that number is NOT added, because
                // nothing in this app knows how many integrations a client has
                // connected. A badge reading 2 for everyone would be a
                // fabricated fact on their own profile.
                _ProfileRow(
                  icon: Icons.integration_instructions_outlined,
                  label: 'Connected apps',
                  iconColor: _C.secondary,
                  hasBorder: true,
                  onTap: () => context.push('/integrations'),
                ),
                // FIT-029 declares "Cycle & wellbeing" on this screen. It is a
                // second entry point to a screen every client can already reach
                // from Home — the tile there is shown to everyone; only its
                // subtitle changes — so no new exposure is introduced.
                _ProfileRow(
                  icon: Icons.favorite_outline,
                  label: 'Cycle & wellbeing',
                  iconColor: _C.secondary,
                  hasBorder: false,
                  onTap: () => context.push('/womens-health'),
                ),
              ]),
            ),
            const SizedBox(height: 28),

            // ── Coach Dashboard (coaches only) ──
            if (isCoach) ...[
              GestureDetector(
                onTap: () => context.go('/coach-dashboard'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFFA855F7).withValues(alpha: 0.08),
                    border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.3))),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.dashboard_outlined, color: Color(0xFFDDB7FF), size: 20),
                      SizedBox(width: 8),
                      Text("Coach Dashboard",
                        style: TextStyle(color: Color(0xFFDDB7FF), fontSize: 15,
                          fontWeight: FontWeight.w600)),
                    ]))),
            ],
            const SizedBox(height: 12),
            // ── Sign Out ──
            GestureDetector(
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  useRootNavigator: true,
                  builder: (dialogCtx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text("Sign Out?",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    content: const Text("Are you sure you want to sign out?",
                      style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(false),
                        child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(true),
                        child: const Text("Sign Out", style: TextStyle(color: Color(0xFFFFB4AB)))),
                    ]));
                if (confirmed == true && context.mounted) {
                  await ref.read(authNotifierProvider.notifier).signOut();
                  if (kIsWeb) {
                    reloadForLogout();
                  } else if (context.mounted) {
                    context.go('/login');
                  }
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: _C.error.withValues(alpha: 0.05),
                  border: Border.all(color: _C.error.withValues(alpha: 0.15)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, color: _C.error, size: 20),
                    SizedBox(width: 8),
                    Text('Sign Out',
                      style: TextStyle(color: _C.error, fontSize: 15,
                        fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      )),
    ]));
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label,
        style: const TextStyle(color: _C.onSurfaceVar, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 2.0)),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
        style: TextStyle(color: color, fontSize: 11,
          fontWeight: FontWeight.w600, letterSpacing: 0.5)),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: _C.glassCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      child: Column(
        children: [
          Text(value,
            style: const TextStyle(color: _C.primary, fontSize: 22,
              fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _C.onSurfaceVar, fontSize: 9,
              fontWeight: FontWeight.w600, letterSpacing: 1, height: 1.4)),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _GlassCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.glassCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      child: child,
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String label;
  final Widget? trailing;
  final bool hasBorder;
  final VoidCallback onTap;

  const _ProfileRow({
    this.icon,
    this.iconColor,
    required this.label,
    this.trailing,
    required this.hasBorder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: hasBorder
              ? const Border(bottom: BorderSide(color: Color(0x1A4B444F)))
              : null,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _C.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor ?? _C.primary, size: 20),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(label,
                style: const TextStyle(color: _C.onSurface, fontSize: 15,
                  fontWeight: FontWeight.w500)),
            ),
            if (trailing != null) trailing!
            else const Icon(Icons.chevron_right, color: _C.onSurfaceVar, size: 20),
          ],
        ),
      ),
    );
  }
}

class _MiniRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _MiniRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    canvas.drawCircle(center, radius, Paint()
      ..color = const Color(0xFF353436)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, 2 * math.pi * progress, false,
      Paint()
        ..color = color
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── My Coach Section ──────────────────────────────────────────────────────────
/// What the "MY COACH" section should render, derived from the read's state.
///
/// F-15 · `/profile` told a paying client they had **no coach**, and to go
/// complete onboarding, whenever `assignedCoachProvider` failed. The section
/// read `coachAsync.valueOrNull`, so a failure and "you have no coach" arrived
/// as the same `null`. That is the FIT-028 falsehood in a second place: not a
/// blank where data should be, but a specific false statement about the
/// client's relationship, with an instruction attached to it.
enum CoachSectionState {
  loading,

  /// The read failed. The screen knows nothing about this client's coach, so
  /// it says nothing — the section is not rendered at all.
  ///
  /// **Hidden rather than reworded** because any wording would be new product
  /// copy, and the string already sitting there is the false one. A full error
  /// state with a retry is OD-8, like the other seven collapses. Saying nothing
  /// is not ideal; saying something untrue is worse.
  unavailable,

  /// Genuinely no coach — this is a real answer and keeps its existing card.
  none,

  assigned,
}

/// Matches on the STATE, never on the value.
///
/// Two reasons, and both are the defect restated. Reading `.valueOrNull` is
/// exactly how a failure became "no coach" in the first place — an error's null
/// and an empty result's null are the same null. And `.valueOrNull` is the read
/// EC-G8 ratchets, so reintroducing one here to fix an error→empty collapse
/// would have been self-defeating; the baseline is unchanged at 134.
CoachSectionState coachSectionFor(AsyncValue<Map<String, dynamic>?> coach) =>
    switch (coach) {
      AsyncError() => CoachSectionState.unavailable,
      AsyncData(:final value) => value == null
          ? CoachSectionState.none
          : CoachSectionState.assigned,
      _ => CoachSectionState.loading,
    };

/// Public so the F-15 branch can be mounted in a widget test — the decision
/// function below is testable on its own, but the WIRING (that `unavailable`
/// actually hides the section) is only assertable against the real tree.
class MyCoachSection extends ConsumerWidget {
  final VoidCallback onCoachCancelled;
  const MyCoachSection({super.key, required this.onCoachCancelled});

  static const _cancelReasons = [
    'Not a good fit',
    'Achieved my goals',
    'Financial reasons',
    'Taking a break from training',
    'Found another coach',
  ];

  Future<void> _showCancelDialog(BuildContext context, WidgetRef ref, String relationshipId) async {
    String? selectedReason;
    final customCtrl = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, set) => Container(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).padding.bottom + 20),
        decoration: const BoxDecoration(
          color: Color(0xFF1C1B1C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 14),
            width: 40, height: 4,
            decoration: BoxDecoration(color: const Color(0xFF4B444F),
              borderRadius: BorderRadius.circular(2))),
          const Text('Cancel Your Coach',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('We\'re sorry to see you go. Mind telling us why?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF968E99), fontSize: 13)),
          const SizedBox(height: 20),
          ..._cancelReasons.map((r) => GestureDetector(
            onTap: () => set(() => selectedReason = selectedReason == r ? null : r),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: selectedReason == r
                  ? const Color(0xFFDDB7FF).withValues(alpha: 0.1)
                  : const Color(0xFF201F20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selectedReason == r
                  ? const Color(0xFFDDB7FF).withValues(alpha: 0.4)
                  : Colors.transparent)),
              child: Row(children: [
                Expanded(child: Text(r,
                  style: TextStyle(
                    color: selectedReason == r
                      ? const Color(0xFFDDB7FF) : Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w500))),
                if (selectedReason == r)
                  const Icon(Icons.check_circle, color: Color(0xFFDDB7FF), size: 18),
              ])))),
          TextField(
            controller: customCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Or share your own reason (optional)...',
              hintStyle: const TextStyle(color: Color(0xFF4B444F), fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF201F20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.all(14)),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx, false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF201F20),
                    borderRadius: BorderRadius.circular(999)),
                  alignment: Alignment.center,
                  child: const Text('Keep Coach',
                    style: TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w600))))),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB4AB).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFFFB4AB).withValues(alpha: 0.4))),
                  alignment: Alignment.center,
                  child: const Text('Cancel Coach',
                    style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 15,
                      fontWeight: FontWeight.w700))))),
          ]),
          const SizedBox(height: 8),
          const Text('You can choose a new coach anytime from your profile.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF4B444F), fontSize: 11)),
        ]),
      )));

    if (confirmed == true) {
      await Supabase.instance.client
          .from('coach_client_relationships')
          .update({
            'status':              'cancelled',
            'cancelled_by':        'client',
            'cancel_reason':       selectedReason,
            'cancel_reason_custom': customCtrl.text.trim().isEmpty ? null : customCtrl.text.trim(),
            'cancelled_at':        DateTime.now().toIso8601String(),
          })
          .eq('id', relationshipId);
      onCoachCancelled();
    }
    customCtrl.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coachAsync = ref.watch(assignedCoachProvider);
    final relAsync   = ref.watch(clientRelationshipProvider);
    final coach      = coachAsync.valueOrNull;
    final rel        = relAsync.valueOrNull;
    final section    = coachSectionFor(coachAsync);

    // F-15: a failed read must not become "No coach assigned yet".
    if (section == CoachSectionState.unavailable) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionLabel(label: 'MY COACH'),
      const SizedBox(height: 12),
      if (section == CoachSectionState.loading)
        const Center(child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2))
      else if (coach == null)
        _GlassCard(
          child: Column(children: [
            const Icon(Icons.person_search_outlined, color: _C.outline, size: 36),
            const SizedBox(height: 8),
            const Text('No coach assigned yet',
              style: TextStyle(color: _C.onSurface, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Complete onboarding to choose your coach.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _C.outline, fontSize: 12)),
          ]))
      else
        Container(
          decoration: BoxDecoration(
            color: _C.glassCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x0DFFFFFF))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _C.primary.withValues(alpha: 0.3), width: 1.5)),
                  child: ClipOval(
                    child: coach['avatar_url'] != null
                      ? Image.network(coach['avatar_url'] as String, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: _C.surfaceContainer,
                            child: const Icon(Icons.person, color: _C.primary, size: 28)))
                      : Container(
                          color: _C.surfaceContainer,
                          child: const Icon(Icons.person, color: _C.primary, size: 28)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Coach ${('${coach['first_name'] ?? ''} ${coach['last_name'] ?? ''}').trim()}',
                    style: const TextStyle(color: _C.onSurface, fontSize: 16,
                      fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(coach['coach_title'] as String? ?? 'Personal Health Coach',
                    style: const TextStyle(color: _C.primary, fontSize: 12,
                      fontWeight: FontWeight.w500)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _C.tertiary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _C.tertiary.withValues(alpha: 0.3))),
                  child: const Text('ACTIVE',
                    style: TextStyle(color: _C.tertiary, fontSize: 9,
                      fontWeight: FontWeight.w700, letterSpacing: 1))),
              ])),
            const Divider(color: Color(0x1A4B444F), height: 1),
            GestureDetector(
              onTap: rel == null ? null
                : () => _showCancelDialog(context, ref, rel['id'] as String),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Cancel Coach',
                  style: TextStyle(color: _C.error, fontSize: 14,
                    fontWeight: FontWeight.w600)))),
          ])),
    ]);
  }
}
