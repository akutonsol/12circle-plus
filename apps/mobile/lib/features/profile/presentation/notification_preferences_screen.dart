import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/observability/network_failure.dart';
import '../../auth/domain/auth_provider.dart';
import 'widgets/profile_load_failed_notice.dart';

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
    // A profile already read (the usual case: Profile or Settings read it
    // first) is applied before the first frame, so the screen does not flash
    // a locked "Loading…" state for one frame (UX-F4). A read still in flight
    // is applied by the listener in build when it lands.
    _apply(ref.read(currentUserProfileProvider));
  }

  /// True once the toggles show the member's stored preferences (or the read
  /// answered "no profile row", which keeps the defaults as before).
  bool _loaded = false;

  /// P0-FL-16: only a successful read fills the toggles. A failed read is an
  /// AsyncError now (it used to be `null`, which left the defaults showing as
  /// the member's settings and every toggle live). Returns whether it applied.
  bool _apply(AsyncValue<Map<String, dynamic>?> state) {
    if (_loaded || state is! AsyncData<Map<String, dynamic>?>) return false;
    _loaded = true;
    final p = state.value;
    if (p == null) return true;
    _workoutReminders = p['notif_workout_reminders'] as bool? ?? true;
    _checkinReminders = p['notif_checkin_reminders'] as bool? ?? true;
    _coachMessages    = p['notif_coach_messages']    as bool? ?? true;
    _progressUpdates  = p['notif_progress_updates']  as bool? ?? true;
    _challenges       = p['notif_challenges']        as bool? ?? false;
    _community        = p['notif_community']         as bool? ?? false;
    return true;
  }

  /// The latest save started for each field: only the newest one may put its
  /// toggle back, so a slow failure cannot undo a later tap.
  final Map<String, int> _saveSeq = {};

  /// Stores one toggle; it counts as saved only when the server says the row
  /// changed (P0-FL-39). A 0-row update (RLS filters silently, and answers
  /// exactly like a saved one unless the row is asked back) or a thrown save
  /// is reported, said, and the toggle is put back with [revert] — the screen
  /// shows what is stored, not what was tapped. [savedNote] is said only
  /// after the server confirmed the save.
  Future<void> _saveToggle(String field, bool value,
      {required ValueChanged<bool> revert, String? savedNote}) async {
    // Nothing is written over preferences that have not been read.
    if (!_loaded) return;
    final seq = (_saveSeq[field] ?? 0) + 1;
    _saveSeq[field] = seq;
    final messenger = ScaffoldMessenger.of(context);
    String? failure;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw StateError('signed out');
      final rows = await Supabase.instance.client
          .from('user_profiles')
          .update({field: value})
          .eq('id', uid)
          .select('id');
      if ((rows as List).isEmpty) {
        throw StateError('user_profiles update matched no row');
      }
      ref.invalidate(currentUserProfileProvider);
    } catch (e, st) {
      reportError('NotificationPreferencesScreen._saveToggle', e, st,
          {'field': field});
      failure = "Couldn't save this notification setting — "
          '${isNetworkFailure(e) ? 'check your connection and try again.' : 'try again in a moment. If it keeps happening, contact support.'}';
    }
    if (!mounted) return;
    if (failure == null) {
      if (savedNote != null) {
        messenger.showSnackBar(SnackBar(
          content: Text(savedNote),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3)));
      }
      return;
    }
    if (_saveSeq[field] == seq) setState(() => revert(!value));
    messenger.showSnackBar(SnackBar(
      content: Semantics(liveRegion: true, child: Text(failure)),
      backgroundColor: _err, behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6)));
  }

  @override
  Widget build(BuildContext context) {
    // Fill the toggles when the read lands (first load, or a successful Try
    // again). Before, a profile still loading at the first frame was never
    // applied, so the defaults stayed on screen as if they were stored.
    ref.listen<AsyncValue<Map<String, dynamic>?>>(
      currentUserProfileProvider,
      (_, next) { if (_apply(next)) setState(() {}); },
    );
    final profileAsync = ref.watch(currentUserProfileProvider);
    // Locked until the stored preferences are known: a toggle drawn from a
    // default is not the member's setting, and flipping it would store the
    // opposite of what they think they are choosing.
    final locked = !_loaded;
    final loadError = locked && profileAsync.hasError ? profileAsync.error : null;

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

            if (loadError != null) ...[
              ProfileLoadFailedNotice(
                error: loadError,
                busy: profileAsync.isLoading,
                detail: "Your notification settings can't be changed until "
                    'they load.',
                onRetry: () => ref.invalidate(currentUserProfileProvider),
              ),
              const SizedBox(height: 20),
            ] else if (locked) ...[
              Semantics(
                liveRegion: true,
                child: const Row(children: [
                  SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(color: _pri, strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Loading your notification settings…',
                    style: TextStyle(color: _out, fontSize: 12)),
                ])),
              const SizedBox(height: 20),
            ],

            // Locked for touch AND for a screen reader: blocking the pointer
            // alone left every toggle activatable by TalkBack/VoiceOver, which
            // WROTE a default over the stored setting (UX-F2).
            IgnorePointer(ignoring: locked, child: ExcludeSemantics(
              excluding: locked,
              child: Opacity(
              opacity: locked ? 0.45 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

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
                  _saveToggle('notif_workout_reminders', v,
                    revert: (b) => _workoutReminders = b);
                }),
              _divider(),
              _toggle(
                icon: Icons.assignment_turned_in_outlined,
                title: 'Check-in Reminders',
                subtitle: 'Reminders to log your weekly check-ins',
                value: _checkinReminders,
                onChanged: (v) {
                  setState(() => _checkinReminders = v);
                  _saveToggle('notif_checkin_reminders', v,
                    revert: (b) => _checkinReminders = b);
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
                  _saveToggle('notif_coach_messages', v,
                    revert: (b) => _coachMessages = b);
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
                  _saveToggle('notif_progress_updates', v,
                    revert: (b) => _progressUpdates = b);
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
                  // Said only once the server confirmed the save.
                  _saveToggle('notif_challenges', v,
                    revert: (b) => _challenges = b,
                    savedNote: v
                        ? 'Challenges will now appear in your Activity feed'
                        : null);
                }),
              _divider(),
              _toggle(
                icon: Icons.group_outlined,
                title: 'Community',
                subtitle: 'Activity in your pods and community posts',
                value: _community,
                onChanged: (v) {
                  setState(() => _community = v);
                  // Said only once the server confirmed the save.
                  _saveToggle('notif_community', v,
                    revert: (b) => _community = b,
                    savedNote: v
                        ? 'Community will now appear in your Activity feed'
                        : null);
                }),
            ])),
            ])))),
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
      // Every toggle refuses while locked, whatever reached it (UX-F2).
      _PurpleToggle(value: value, onChanged: (v) {
        if (!_loaded) return;
        onChanged(v);
      }),
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
