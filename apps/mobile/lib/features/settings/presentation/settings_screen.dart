import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../core/router/app_router.dart' show kQaToolingEnabled;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/web_logout.dart';
import '../../auth/domain/auth_provider.dart';
import '../../coaching_mode/domain/coaching_mode_provider.dart';
import '../../coach/domain/coach_provider.dart';
import '../../coach/data/coach_relationship_service.dart';
import '../../payments/domain/entitlements.dart';

class _C {
  static const bg                  = Color(0xFF0A0A0B);
  static const surfaceContainer    = Color(0xFF201F20);
  static const glassCard           = Color(0x99201F20);
  static const primary             = Color(0xFFDDB7FF);
  static const primaryContainer    = Color(0xFFB76DFF);
  static const deepPurple          = Color(0xFF842BD2);
  static const onSurface           = Color(0xFFE5E2E3);
  static const onSurfaceVar        = Color(0xFFCDC3D0);
  static const onSurfaceMuted      = Color(0xFFCFC2D6);
  static const error               = Color(0xFFFFB4AB);
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _soundEffects = true;
  String _selectedUnit = 'KG';
  bool _unitLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_unitLoaded) {
      final profile = ref.read(currentUserProfileProvider).valueOrNull;
      if (profile != null) {
        final pref = profile['unit_preference'] as String? ?? 'imperial';
        _selectedUnit = pref == 'metric' ? 'KG' : 'LB';
        _unitLoaded = true;
      }
    }
  }

  /// CORR-2. Returns whether the preference was actually stored.
  ///
  /// This was `Future<void>` with `if (uid == null) return;` and a bare
  /// `catch (_) {}`, called unawaited after an optimistic `setState`. The
  /// toggle moved, nothing persisted, and nothing said so — the member's unit
  /// preference silently reverted on the next load.
  ///
  /// `_saveToggle` in `notification_preferences_screen` and
  /// `WeeklyCheckinService.submitWeeklyCheckin` already report failure; this
  /// matches them rather than inventing a convention.
  Future<bool> _persistUnit(String unit) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await Supabase.instance.client.from('user_profiles').update({
        'unit_preference': unit == 'KG' ? 'metric' : 'imperial',
      }).eq('id', uid);
      ref.invalidate(currentUserProfileProvider);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile     = ref.watch(currentUserProfileProvider).valueOrNull;
    final isCoach     = (profile?['role'] as String?) == 'coach';
    final firstName   = profile?['first_name'] as String? ?? '';
    final lastName    = profile?['last_name']  as String? ?? '';
    final displayName = '$firstName $lastName'.trim().isEmpty
        ? 'Member' : '$firstName $lastName'.trim();
    final email       = profile?['email']      as String?
        ?? Supabase.instance.client.auth.currentUser?.email ?? '';
    final avatarUrl   = profile?['avatar_url'] as String?;
    // Subscription = the client's effective plan (Free/Self-Guided/AI-Guided/
    // Coach-Guided), not the legacy membership_tier column (which read "basic").
    final planLabel   = (ref.watch(clientPlanProvider).valueOrNull ?? ClientPlan.free).label;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
    ));

    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [

          // ── App Bar ──
          Container(
            padding: EdgeInsets.only(left: 8, right: 20, top: top, bottom: 0),
            decoration: BoxDecoration(
              color: _C.glassCard,
              border: const Border(
                bottom: BorderSide(color: Color(0x1A4B444F), width: 1),
              ),
            ),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: _C.primary, size: 20),
                    tooltip: 'Back',
                    onPressed: () => context.go('/profile'),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('SETTINGS',
                        style: TextStyle(
                          color: _C.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        )),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),

          // ── Scrollable content ──
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 24, 20, bottom + 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Account ──
                  _SectionLabel(label: 'Account'),
                  const SizedBox(height: 10),
                  _GlassSection(children: [
                    // Profile row
                    _SettingsRow(
                      leading: Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _C.primary.withValues(alpha: 0.2))),
                        child: ClipOval(child: avatarUrl != null
                          ? Image.network(avatarUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: _C.surfaceContainer,
                                child: const Icon(Icons.person, color: _C.primary, size: 24)))
                          : Container(
                              color: _C.surfaceContainer,
                              child: const Icon(Icons.person, color: _C.primary, size: 24))),
                      ),
                      title: displayName,
                      subtitle: email,
                      trailing: const Icon(Icons.chevron_right, color: _C.onSurfaceVar, size: 20),
                      hasBorder: true,
                      onTap: () => context.push('/personal-info'),
                    ),

                    // Subscription (client membership only)
                    if (!isCoach) _SettingsRow(
                      icon: Icons.workspace_premium_outlined,
                      iconColor: _C.primary,
                      title: 'Subscription',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _C.primaryContainer.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _C.primaryContainer.withValues(alpha: 0.4))),
                        child: Text(planLabel.toUpperCase(),
                          style: const TextStyle(color: _C.primaryContainer,
                            fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                      ),
                      hasBorder: true,
                      onTap: () => context.push('/subscription'),
                    ),

                    // Connected Apps
                    _SettingsRow(
                      icon: Icons.hub_outlined,
                      iconColor: _C.onSurfaceVar,
                      title: 'Connected Apps',
                      trailing: const Icon(Icons.chevron_right, color: _C.onSurfaceVar, size: 20),
                      hasBorder: true,
                      onTap: () => context.push('/integrations'),
                    ),

                    // Coaching Mode (client preference only)
                    if (!isCoach) _CoachingModeRow(),
                  ]),
                  const SizedBox(height: 28),

                  // ── Training & Performance ──
                  _SectionLabel(label: 'Training & Performance'),
                  const SizedBox(height: 10),
                  _GlassSection(children: [
                    // Default Units
                    _SettingsRow(
                      icon: Icons.monitor_weight_outlined,
                      iconColor: _C.onSurfaceVar,
                      title: 'Default Units',
                      trailing: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: _C.surfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: ['KG', 'LB'].map((u) => GestureDetector(
                            onTap: () async {
                              // Optimistic, but REVERTED on failure: an
                              // un-reverted toggle shows a preference that was
                              // never stored.
                              final previous = _selectedUnit;
                              setState(() => _selectedUnit = u);
                              final ok = await _persistUnit(u);
                              if (!ok && context.mounted) {
                                setState(() => _selectedUnit = previous);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Failed to save.')),
                                );
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: _selectedUnit == u
                                    ? _C.primary.withValues(alpha: 0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(u,
                                style: TextStyle(
                                  color: _selectedUnit == u ? _C.primary : _C.onSurfaceMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                )),
                            ),
                          )).toList(),
                        ),
                      ),
                      hasBorder: true,
                    ),

                    // Heart Rate Zones
                    _SettingsRow(
                      icon: Icons.monitor_heart_outlined,
                      iconColor: _C.onSurfaceVar,
                      title: 'Heart Rate Zones',
                      trailing: const Icon(Icons.chevron_right, color: _C.onSurfaceVar, size: 20),
                      hasBorder: true,
                      onTap: () => _showHrZonesSheet(context),
                    ),

                    // Activity Notifications
                    _SettingsRow(
                      icon: Icons.notifications_active_outlined,
                      iconColor: _C.onSurfaceVar,
                      title: 'Notification Preferences',
                      trailing: const Icon(Icons.chevron_right, color: _C.onSurfaceVar, size: 20),
                      hasBorder: false,
                      onTap: () => context.push('/notification-preferences'),
                    ),
                  ]),
                  const SizedBox(height: 28),

                  // ── App Preferences ──
                  _SectionLabel(label: 'App Preferences'),
                  const SizedBox(height: 10),
                  _GlassSection(children: [
                    // Dark Mode
                    _SettingsRow(
                      icon: Icons.dark_mode_outlined,
                      iconColor: _C.onSurfaceVar,
                      title: 'Dark Mode',
                      trailing: const Text('ACTIVE',
                        style: TextStyle(
                          color: _C.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        )),
                      hasBorder: true,
                    ),

                    // Sound Effects
                    _SettingsRow(
                      icon: Icons.volume_up_outlined,
                      iconColor: _C.onSurfaceVar,
                      title: 'Sound Effects',
                      trailing: _PurpleToggle(
                        value: _soundEffects,
                        onChanged: (v) => setState(() => _soundEffects = v),
                      ),
                      hasBorder: true,
                    ),

                    // Language
                    _SettingsRow(
                      icon: Icons.language_outlined,
                      iconColor: _C.onSurfaceVar,
                      title: 'Language',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text('English (US)',
                            style: TextStyle(color: _C.onSurfaceMuted, fontSize: 14)),
                          SizedBox(width: 4),
                          Icon(Icons.chevron_right, color: _C.onSurfaceVar, size: 20),
                        ],
                      ),
                      hasBorder: false,
                    ),
                  ]),
                  const SizedBox(height: 28),

                  // ── Legal & Support ──
                  _SectionLabel(label: 'Legal & Support'),
                  const SizedBox(height: 10),
                  // FIT-030's wording. Three of these differ from what shipped
                  // only in spelling or case — "Help centre", "Privacy policy",
                  // "Sign out" against "Help Center", "Privacy Policy",
                  // "Logout" — and the locked screen wins. The package is
                  // consistently UK English (it also prices in £), and the app
                  // shipped US spellings; see OD-18, which is the same
                  // divergence with money attached.
                  _GlassSection(children: [
                    // FIT-030 declares "Change password". It routes to the
                    // reset flow this app already has — `/forgot-password`
                    // sends the email that `reset_password_screen.dart`
                    // completes. No new auth path is introduced.
                    _SettingsRow(
                      title: 'Change password',
                      trailing: const Icon(Icons.chevron_right, color: _C.onSurfaceVar, size: 20),
                      hasBorder: true,
                      onTap: () => context.push('/forgot-password'),
                    ),
                    _SettingsRow(
                      title: 'Help centre',
                      trailing: const Icon(Icons.open_in_new, color: _C.onSurfaceVar, size: 18),
                      hasBorder: true,
                      onTap: () => context.push('/help-center'),
                    ),
                    _SettingsRow(
                      title: 'Privacy policy',
                      trailing: const Icon(Icons.chevron_right, color: _C.onSurfaceVar, size: 20),
                      hasBorder: true,
                      onTap: () => context.push('/privacy-policy'),
                    ),
                    _SettingsRow(
                      title: 'Sign out',
                      titleColor: _C.error,
                      trailing: const Icon(Icons.logout, color: _C.error, size: 20),
                      hasBorder: false,
                      onTap: () => _showLogoutDialog(context),
                    ),
                  ]),
                  // Developer tools — debug/profile builds only. Gated on the
                  // same flag as the route itself (REL-3), so the affordance and
                  // the destination can never disagree about who may see it.
                  if (kQaToolingEnabled) ...[
                    const SizedBox(height: 12),
                    _GlassSection(children: [
                      _SettingsRow(
                        title: '🧪 QA Center',
                        trailing: const Icon(Icons.chevron_right, color: _C.onSurfaceVar, size: 20),
                        hasBorder: false,
                        onTap: () => context.push('/qa-center'),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 24),

                  // Version
                  const Center(
                    child: Text('12 CIRCLE FITNESS v1.0.0 (BUILD 001)',
                      style: TextStyle(
                        color: _C.onSurfaceMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      )),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showHrZonesSheet(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
        decoration: const BoxDecoration(
          color: Color(0xFF1C1B1C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: _C.onSurfaceVar.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2))),
          Row(children: [
            const Icon(Icons.monitor_heart_outlined, color: _C.primary, size: 22),
            const SizedBox(width: 10),
            const Text('Heart Rate Zones',
              style: TextStyle(color: _C.onSurface, fontSize: 20, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          const Text('Train smarter by staying in the right zone for your goal.',
            style: TextStyle(color: _C.onSurfaceVar, fontSize: 13, height: 1.4)),
          const SizedBox(height: 20),
          ...[
            ('Zone 1', '50–60% Max HR', 'Warm-up / Recovery', const Color(0xFF6FFBBE)),
            ('Zone 2', '60–70% Max HR', 'Fat-burning / Base fitness', const Color(0xFF60A5FA)),
            ('Zone 3', '70–80% Max HR', 'Aerobic / Cardio endurance', _C.primary),
            ('Zone 4', '80–90% Max HR', 'Anaerobic / High intensity', const Color(0xFFFFD580)),
            ('Zone 5', '90–100% Max HR', 'Max effort / Sprint intervals', const Color(0xFFFF6B6B)),
          ].map((z) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: z.$4.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: z.$4.withValues(alpha: 0.2))),
            child: Row(children: [
              Container(width: 4, height: 36,
                decoration: BoxDecoration(
                  color: z.$4, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(z.$1, style: TextStyle(color: z.$4, fontSize: 12,
                  fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                Text(z.$3, style: const TextStyle(color: _C.onSurface, fontSize: 14,
                  fontWeight: FontWeight.w500)),
              ])),
              Text(z.$2, style: const TextStyle(color: _C.onSurfaceVar, fontSize: 12)),
            ]))),
          const SizedBox(height: 4),
          const Text('Calculate max HR: 220 − your age',
            style: TextStyle(color: _C.onSurfaceVar, fontSize: 11, fontStyle: FontStyle.italic)),
        ]),
      ),
    );
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: _C.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        // The row says "Sign out"; the dialog confirming it must say the same
        // thing, or the client is asked to confirm an action they did not
        // press.
        title: const Text('Sign out', style: TextStyle(color: _C.onSurface, fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to logout?',
          style: TextStyle(color: _C.onSurfaceVar)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _C.onSurfaceVar)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(true),
            child: const Text('Sign out', style: TextStyle(color: _C.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(authNotifierProvider.notifier).signOut();
      if (kIsWeb) {
        reloadForLogout();
      } else if (context.mounted) {
        context.go('/login');
      }
    }
  }
}

// ── Coaching Mode Row ─────────────────────────────────────────────────────────
class _CoachingModeRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(coachingModeProvider);

    final modeColor = switch (mode) {
      CoachingMode.selfGuided  => _C.primary,
      CoachingMode.aiGuided    => const Color(0xFF6FFBBE),
      CoachingMode.coachGuided => const Color(0xFFF8ACFF),
    };

    return _SettingsRow(
      icon: switch (mode) {
        CoachingMode.selfGuided  => Icons.self_improvement_outlined,
        CoachingMode.aiGuided    => Icons.auto_awesome_outlined,
        CoachingMode.coachGuided => Icons.emoji_people_outlined,
      },
      iconColor: modeColor,
      title: 'Coaching Mode',
      trailing: GestureDetector(
        onTap: () => _showCoachingModeSheet(context, ref, mode),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: modeColor.withValues(alpha: 0.3)),
            ),
            child: Text(mode.displayName,
              style: TextStyle(color: modeColor, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: _C.onSurfaceVar, size: 20),
        ]),
      ),
      hasBorder: false,
    );
  }

  void _showCoachingModeSheet(
      BuildContext context, WidgetRef ref, CoachingMode current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CoachingModeSheet(current: current, ref: ref),
    );
  }
}

class _CoachingModeSheet extends StatefulWidget {
  final CoachingMode current;
  final WidgetRef ref;
  const _CoachingModeSheet({required this.current, required this.ref});
  @override
  State<_CoachingModeSheet> createState() => _CoachingModeSheetState();
}

class _CoachingModeSheetState extends State<_CoachingModeSheet> {
  late CoachingMode _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  Future<void> _apply() async {
    final messenger = ScaffoldMessenger.of(context);

    // Self/AI-Guided means no coach. If the client is leaving an active-coach
    // state for self/AI, they must end coaching first. (No prompt for a plain
    // self<->AI switch, where there's no coach involved.)
    if (_selected != CoachingMode.coachGuided) {
      List<Map<String, dynamic>> coaches = const [];
      try {
        coaches = await widget.ref.read(myCoachesProvider.future);
      } catch (_) {}
      if (!mounted) return;
      if (coaches.isNotEmpty) {
        final confirmed = await _confirmEndCoaching(coaches);
        if (confirmed != true) return; // kept their coach → abort the switch
        if (!mounted) return;
        setState(() => _saving = true);
        final svc = CoachRelationshipService();
        for (final c in coaches) {
          final coachId = c['coach_id'] as String?;
          if (coachId != null) {
            await svc.cancelCoach(coachId, 'switched_to_self_serve', null);
          }
        }
        widget.ref.invalidate(myCoachesProvider);
        widget.ref.invalidate(assignedCoachProvider);
        widget.ref.invalidate(clientRelationshipProvider);
      }
    }

    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await widget.ref
          .read(coachingModeNotifierProvider.notifier)
          .setMode(_selected);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        content: Text('Could not save coaching mode.')));
      return; // keep the sheet open so the change isn't silently lost
    }
    if (!mounted) return;
    // Refresh coach-dependent views so a mode change is reflected immediately
    // (e.g. the profile's My Coach section), even if the prompt path didn't run.
    widget.ref.invalidate(assignedCoachProvider);
    widget.ref.invalidate(clientRelationshipProvider);
    widget.ref.invalidate(myCoachesProvider);
    Navigator.pop(context);
    if (_selected == CoachingMode.coachGuided) {
      context.push('/coach-marketplace');
    }
  }

  Future<bool?> _confirmEndCoaching(List<Map<String, dynamic>> coaches) {
    final c = coaches.first['coach'] as Map<String, dynamic>? ?? {};
    final coachName = 'Coach ${('${c['first_name'] ?? ''} ${c['last_name'] ?? ''}').trim()}'.trim();
    final who = coaches.length > 1
        ? 'your ${coaches.length} coaches'
        : (coachName == 'Coach' ? 'your coach' : coachName);
    final modeName = _selected == CoachingMode.aiGuided ? 'AI-Guided' : 'Self-Guided';
    return showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1B1C),
        title: Text('End coaching with $who?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        content: Text(
          '$modeName doesn\'t include a personal coach. Switching will end your '
          'current coaching and notify $who. You can choose a new coach any time.',
          style: const TextStyle(color: Color(0xFFCFC2D6), height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Keep my coach', style: TextStyle(color: Color(0xFFCFC2D6)))),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('End & switch',
              style: TextStyle(color: Color(0xFFFFB4AB), fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1B1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 20),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: _C.onSurfaceVar.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2))),
        const Text('Coaching Mode',
          style: TextStyle(color: _C.onSurface, fontSize: 20,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('You can switch modes at any time.',
          style: TextStyle(color: _C.onSurfaceVar, fontSize: 13)),
        const SizedBox(height: 20),
        ...CoachingMode.values.map((m) {
          final active = _selected == m;
          final color = switch (m) {
            CoachingMode.selfGuided  => _C.primary,
            CoachingMode.aiGuided    => const Color(0xFF6FFBBE),
            CoachingMode.coachGuided => const Color(0xFFF8ACFF),
          };
          return GestureDetector(
            onTap: () => setState(() => _selected = m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: active ? color.withValues(alpha: 0.08) : _C.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active ? color : Colors.white.withValues(alpha: 0.06),
                  width: active ? 1.5 : 1)),
              child: Row(children: [
                Icon(switch (m) {
                  CoachingMode.selfGuided  => Icons.self_improvement_outlined,
                  CoachingMode.aiGuided    => Icons.auto_awesome_outlined,
                  CoachingMode.coachGuided => Icons.emoji_people_outlined,
                }, color: active ? color : _C.onSurfaceVar, size: 22),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.displayName, style: TextStyle(
                    color: active ? color : _C.onSurface,
                    fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(m.description,
                    style: const TextStyle(color: _C.onSurfaceVar, fontSize: 11,
                      height: 1.4)),
                ])),
                const SizedBox(width: 10),
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? color : Colors.transparent,
                    border: Border.all(
                      color: active ? color : _C.onSurfaceVar, width: 1.5)),
                  child: active
                    ? const Icon(Icons.check, color: Colors.white, size: 12)
                    : null),
              ]),
            ),
          );
        }),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _saving ? null : _apply,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                colors: [Color(0xFFB76DFF), Color(0xFF7C3AED)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight),
              boxShadow: const [BoxShadow(color: Color(0x557C3AED), blurRadius: 16)],
            ),
            alignment: Alignment.center,
            child: _saving
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Apply',
                  style: TextStyle(color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
        ),
      ]),
    );
  }
}

// ── Section Label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label,
        style: const TextStyle(
          color: _C.onSurfaceMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        )),
    );
  }
}

// ── Glass Section ─────────────────────────────────────────────────────────────
class _GlassSection extends StatelessWidget {
  final List<Widget> children;
  const _GlassSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.glassCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

// ── Settings Row ──────────────────────────────────────────────────────────────
class _SettingsRow extends StatelessWidget {
  final Widget? leading;
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final Widget? trailing;
  final bool hasBorder;
  final VoidCallback? onTap;

  const _SettingsRow({
    this.leading,
    this.icon,
    this.iconColor,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.trailing,
    required this.hasBorder,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: hasBorder
              ? const Border(bottom: BorderSide(color: Color(0x1A4B444F), width: 1))
              : null,
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            if (icon != null) ...[
              Icon(icon, color: iconColor ?? _C.onSurfaceVar, size: 22),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                    style: TextStyle(
                      color: titleColor ?? _C.onSurface,
                      fontSize: 15,
                      fontWeight: titleColor != null ? FontWeight.w700 : FontWeight.w400,
                    )),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                      style: const TextStyle(color: _C.onSurfaceMuted, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

// ── Purple Toggle ─────────────────────────────────────────────────────────────
class _PurpleToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _PurpleToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 48, height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: value ? _C.deepPurple : _C.surfaceContainer,
          boxShadow: value
              ? [const BoxShadow(color: Color(0x55842BD2), blurRadius: 10)]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 20, height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }
}
