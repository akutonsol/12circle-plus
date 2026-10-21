import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/auth_provider.dart';

const _bg   = Color(0xFF0E0E0F);
const _pri  = Color(0xFFDDB7FF);
const _deep = Color(0xFF842BD2);
const _tert = Color(0xFF6FFBBE);
const _onS  = Color(0xFFE5E2E3);
const _onSV = Color(0xFFCDC3D0);
const _out  = Color(0xFF968E99);
const _outV = Color(0xFF4B444F);
const _err  = Color(0xFFFFB4AB);

class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});
  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  bool _workoutReminders  = true;
  bool _checkinReminders  = true;
  bool _coachMessages     = true;
  bool _progressUpdates   = true;
  bool _challenges        = false;
  bool _community         = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _loadData() {
    final p = ref.read(currentUserProfileProvider).valueOrNull;
    if (p == null) return;
    setState(() {
      _workoutReminders = p['notif_workout_reminders'] as bool? ?? true;
      _checkinReminders = p['notif_checkin_reminders'] as bool? ?? true;
      _coachMessages    = p['notif_coach_messages']    as bool? ?? true;
      _progressUpdates  = p['notif_progress_updates']  as bool? ?? true;
      _challenges       = p['notif_challenges']        as bool? ?? false;
      _community        = p['notif_community']         as bool? ?? false;
    });
  }

  Future<void> _saveToggle(String field, bool value) async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      await Supabase.instance.client
          .from('user_profiles')
          .update({field: value})
          .eq('id', uid);
      ref.invalidate(currentUserProfileProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save.'),
          backgroundColor: _err, behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header
        Container(
          padding: EdgeInsets.only(left: 8, right: 20, top: top),
          decoration: const BoxDecoration(
            color: Color(0x99201F20),
            border: Border(bottom: BorderSide(color: Color(0x1A4B444F)))),
          child: SizedBox(height: 56, child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: _pri, size: 20),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop()),
            const Expanded(child: Center(child: Text('NOTIFICATIONS',
              style: TextStyle(color: _pri, fontSize: 16,
                fontWeight: FontWeight.w800, letterSpacing: 2)))),
            const SizedBox(width: 40),
          ])),
        ),

        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 24, 20, bottom + 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 16),
              child: Text(
                'Control which notifications you receive. Changes save automatically.',
                style: TextStyle(color: _out, fontSize: 13, height: 1.5))),

            // ── Training ──
            _sectionLabel('TRAINING'),
            const SizedBox(height: 10),
            _card(Column(children: [
              _toggle(
                icon: Icons.fitness_center_outlined,
                title: 'Workout Reminders',
                subtitle: 'Daily reminders to complete your scheduled workouts',
                value: _workoutReminders,
                onChanged: (v) {
                  setState(() => _workoutReminders = v);
                  _saveToggle('notif_workout_reminders', v);
                }),
              _divider(),
              _toggle(
                icon: Icons.assignment_turned_in_outlined,
                title: 'Check-in Reminders',
                subtitle: 'Reminders to log your weekly check-ins',
                value: _checkinReminders,
                onChanged: (v) {
                  setState(() => _checkinReminders = v);
                  _saveToggle('notif_checkin_reminders', v);
                }),
            ])),
            const SizedBox(height: 24),

            // ── Coaching ──
            _sectionLabel('COACHING'),
            const SizedBox(height: 10),
            _card(Column(children: [
              _toggle(
                icon: Icons.record_voice_over_outlined,
                title: 'Coach Messages',
                subtitle: 'Messages and feedback from your coach',
                value: _coachMessages,
                iconColor: const Color(0xFFF8ACFF),
                onChanged: (v) {
                  setState(() => _coachMessages = v);
                  _saveToggle('notif_coach_messages', v);
                }),
              _divider(),
              _toggle(
                icon: Icons.trending_up_outlined,
                title: 'Progress Updates',
                subtitle: 'Weekly summaries and milestone alerts',
                value: _progressUpdates,
                iconColor: _tert,
                onChanged: (v) {
                  setState(() => _progressUpdates = v);
                  _saveToggle('notif_progress_updates', v);
                }),
            ])),
            const SizedBox(height: 24),

            // ── Community ──
            _sectionLabel('COMMUNITY'),
            const SizedBox(height: 10),
            _card(Column(children: [
              _toggle(
                icon: Icons.emoji_events_outlined,
                title: 'Challenges',
                subtitle: 'New challenges and leaderboard updates',
                value: _challenges,
                iconColor: const Color(0xFFFFD700),
                onChanged: (v) {
                  setState(() => _challenges = v);
                  _saveToggle('notif_challenges', v);
                  if (v) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Challenges will now appear in your Activity feed'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 3)));
                  }
                }),
              _divider(),
              _toggle(
                icon: Icons.group_outlined,
                title: 'Community',
                subtitle: 'Activity in your pods and community posts',
                value: _community,
                onChanged: (v) {
                  setState(() => _community = v);
                  _saveToggle('notif_community', v);
                  if (v) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Community will now appear in your Activity feed'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 3)));
                  }
                }),
            ])),
          ]),
        )),
      ]),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(label, style: const TextStyle(
      color: _onSV, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)));

  Widget _card(Widget child) => Container(
    decoration: BoxDecoration(
      color: const Color(0x99201F20),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x0DFFFFFF))),
    clipBehavior: Clip.antiAlias,
    child: child);

  Widget _divider() => const Divider(height: 1, color: Color(0x1A4B444F));

  Widget _toggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? iconColor,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: (iconColor ?? _pri).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor ?? _pri, size: 20)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
          color: _onS, fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(
          color: _out, fontSize: 12, height: 1.3)),
      ])),
      const SizedBox(width: 12),
      _PurpleToggle(value: value, onChanged: onChanged),
    ]));
}

class _PurpleToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _PurpleToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 48, height: 26,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: value ? _deep : _outV,
        boxShadow: value
          ? const [BoxShadow(color: Color(0x55842BD2), blurRadius: 10)]
          : null),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.all(3),
          width: 20, height: 20,
          decoration: const BoxDecoration(
            shape: BoxShape.circle, color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)])))));
}
