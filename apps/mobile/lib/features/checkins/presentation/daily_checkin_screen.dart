import 'package:flutter/material.dart';
import 'widgets/checkin_pickers.dart';
import '../data/weekly_checkin_service.dart';
import '../domain/checkin_hub.dart';
import '../../coach/domain/coach_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/checkin_known.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg      = Color(0xFF050308);
const _card    = Color(0xFF0E0B14);
const _border  = Color(0xFF1E1628);
const _primary = Color(0xFFDDB7FF);
const _brand   = Color(0xFFA855F7);
const _white   = Colors.white;
const _muted   = Color(0xFFCFC2D6);
const _green   = Color(0xFF4ADE80);
const _error   = Color(0xFFFFB4AB);

// ── Weekly Check-In Screen ────────────────────────────────────────────────────
class DailyCheckinScreen extends ConsumerStatefulWidget {
  const DailyCheckinScreen({super.key});
  @override
  ConsumerState<DailyCheckinScreen> createState() => _WeeklyCheckinState();
}

class _WeeklyCheckinState extends ConsumerState<DailyCheckinScreen> {
  /// CON-01 (live): `public.checkins` does not exist — verified against the QA
  /// database, where it answers PGRST205 exactly as a nonsense table does. The
  /// submission below wrote there, so every weekly check-in this screen took
  /// was lost. `weekly_checkins` DOES exist and already has a working writer.
  final _weekly     = WeeklyCheckinService();
  final _notesCtrl  = TextEditingController();

  int    _mood          = 3;
  int    _energy        = 3;
  int    _stress        = 2;
  double _sleep         = 7.0;
  bool   _workedOut     = false;
  bool   _hitWaterGoal  = false;
  bool   _saving        = false;
  /// CON-01: was `bool _alreadyDone = false`, so a failed read opened the
  /// form to someone who had already checked in and `_submit` wrote a
  /// duplicate. Three states, because the screen needs three.
  CheckinKnown _alreadyDone = CheckinKnown.notDone;
  int?   _streak        = 0;

  static const _moodEmojis  = ['😞', '😐', '😊', '😄', '🤩'];
  static const _moodLabels  = ['Rough', 'Meh', 'Good', 'Great', 'Amazing'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final done = await _weekly.weekStatus();
    final streak = await _weekly.getCheckinStreak();
    if (mounted) setState(() {
      _alreadyDone = done;
      _streak      = streak;
    });
  }

  @override
  void dispose() { _notesCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    setState(() => _saving = true);
    // Writes to `weekly_checkins`, which exists. `workedOut` and
    // `hitWaterGoal` are not passed because that table has no column for them
    // — and the old path did not persist them either, since it wrote to a
    // table that is not there. Nothing that was ever saved is lost; adding
    // columns for them is an owner decision.
    final ok = await _weekly.submitWeeklyCheckin(
      mood: _mood, energy: _energy, stress: _stress,
      sleepHoursAvg: _sleep, notes: _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!mounted) return;
    if (ok) {
      _showSuccess(WeeklyCheckinService.needsCoachAttention(energy: _energy, stress: _stress));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save. Please try again.')));
    }
  }

  void _showSuccess(bool needsAttention) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _brand.withValues(alpha: 0.35), _brand.withValues(alpha: 0.05)]),
                border: Border.all(color: _brand.withValues(alpha: 0.5)),
                boxShadow: [BoxShadow(
                  color: _brand.withValues(alpha: 0.4), blurRadius: 24)]),
              child: Center(child: Text(_moodEmojis[_mood - 1],
                style: const TextStyle(fontSize: 38)))),
            const SizedBox(height: 20),
            const Text('Weekly Check-In Complete!',
              textAlign: TextAlign.center,
              style: TextStyle(color: _white, fontSize: 20,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Great job staying consistent this week!',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 13)),
            if (needsAttention) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _error.withValues(alpha: 0.25))),
                child: Row(children: [
                  Icon(Icons.favorite_outline, color: _error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Your coach has been notified about your levels.',
                    style: TextStyle(color: _error.withValues(alpha: 0.85),
                      fontSize: 11, fontWeight: FontWeight.w500))),
                ])),
            ],
            const SizedBox(height: 24),
            SizedBox(width: double.infinity,
              child: _GradientBtn(
                label: 'Back to Home',
                icon: Icons.home_outlined,
                onTap: () { Navigator.pop(context); context.go('/home'); })),
          ]))));
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd   = weekStart.add(const Duration(days: 6));
    final weekLabel = '${_monthAbbr(weekStart.month)} ${weekStart.day} '
        '– ${_monthAbbr(weekEnd.month)} ${weekEnd.day}';

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(fit: StackFit.expand, children: [
        // ── Purple atmospheric glow ──────────────────────────────────────────
        Positioned(top: -80, left: -60,
          child: Container(width: 280, height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                _brand.withValues(alpha: 0.25), Colors.transparent])))),
        Positioned(bottom: 40, right: -80,
          child: Container(width: 220, height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                _brand.withValues(alpha: 0.15), Colors.transparent])))),

        // ── Content ──────────────────────────────────────────────────────────
        SafeArea(
          child: Column(children: [
            _buildHeader(top),
            Expanded(
              child: mayShowAlreadyDone(_alreadyDone)
                ? _AlreadyDone(onGoHome: () => context.go('/home'))
                : !mayOfferCheckinForm(_alreadyDone)
                // CON-01. The read failed, so whether this week already has a
                // check-in is unknown — and the form is how a duplicate gets
                // written. `Could not load check-ins` is the copy this
                // feature's own domain file carries for exactly this, noting
                // the repository renders it in fifteen places.
                ? _CheckinUnknown(onRetry: _load)
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _WeekCard(weekLabel: weekLabel),
                        const SizedBox(height: 24),
                        _sectionLabel("How's your mood?"),
                        const SizedBox(height: 12),
                        MoodPicker(
                          selected: _mood,
                          emojis: _moodEmojis,
                          labels: _moodLabels,
                          onTap: (i) => setState(() => _mood = i)),
                        const SizedBox(height: 24),
                        _sectionLabel('Energy Level'),
                        const SizedBox(height: 12),
                        NumberPicker(
                          scale: 'Energy Level',
                          value: _energy,
                          onChanged: (v) => setState(() => _energy = v)),
                        const SizedBox(height: 24),
                        _sectionLabel('Stress Level'),
                        const SizedBox(height: 12),
                        NumberPicker(
                          scale: 'Stress Level',
                          value: _stress,
                          onChanged: (v) => setState(() => _stress = v)),
                        if (_stress >= 4) ...[
                          const SizedBox(height: 8),
                          _CoachNotice(),
                        ],
                        const SizedBox(height: 24),
                        _sectionLabel('Sleep Hours'),
                        const SizedBox(height: 12),
                        _SleepSlider(
                          value: _sleep,
                          onChanged: (v) => setState(() => _sleep = v)),
                        const SizedBox(height: 24),
                        _sectionLabel("This Week's Goals"),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: _GoalToggle(
                            label: 'Worked Out',
                            icon: Icons.fitness_center_outlined,
                            value: _workedOut,
                            onTap: () => setState(() =>
                              _workedOut = !_workedOut))),
                          const SizedBox(width: 12),
                          Expanded(child: _GoalToggle(
                            label: 'Hit Water Goal',
                            icon: Icons.water_drop_outlined,
                            value: _hitWaterGoal,
                            onTap: () => setState(() =>
                              _hitWaterGoal = !_hitWaterGoal))),
                        ]),
                        const SizedBox(height: 24),
                        _sectionLabel('Notes for Coach'),
                        const SizedBox(height: 12),
                        _NotesField(controller: _notesCtrl),
                        const SizedBox(height: 32),
                        // FIT-004 draws "Send to Nadia" — the client's coach,
                        // by name. Real data, so nothing is invented; and the
                        // name is used ONLY when the read has settled with one,
                        // so a failed lookup cannot address the button to a
                        // coach the client may not have. See checkinSubmitLabel.
                        _GradientBtn(
                          label: checkinSubmitLabel(ref.watch(assignedCoachProvider)),
                          icon: Icons.check_circle_outline,
                          loading: _saving,
                          onTap: _saving ? null : _submit),
                        const SizedBox(height: 16),
                        // FIT-004's other two declared controls. Both go to the
                        // screens this app already keeps that content on — no
                        // screen is invented to satisfy a label.
                        Row(children: [
                          Expanded(child: _CheckinLink(
                            label: 'Past check-ins',
                            onTap: () => context.go('/checkins'))),
                          const SizedBox(width: 10),
                          Expanded(child: _CheckinLink(
                            label: 'Add a progress photo',
                            onTap: () => context.go('/progress'))),
                        ]),
                      ]))),
          ])),
      ]),
    );
  }

  Widget _buildHeader(double top) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: _bg.withValues(alpha: 0.8),
        border: Border(bottom: BorderSide(
          color: _brand.withValues(alpha: 0.1)))),
      child: Row(children: [
        Semantics(
          button: true,
          label: 'Back',
          child: GestureDetector(
          onTap: () => context.go('/home'),
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            alignment: Alignment.center,
            child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.07),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
            child: const Icon(Icons.arrow_back_ios_new,
              color: _white, size: 16))))),
        const SizedBox(width: 12),
        const Text('Weekly Check-In',
          style: TextStyle(color: _white, fontSize: 18,
            fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const Spacer(),
        GestureDetector(
          onTap: () => context.go('/checkins'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_brand.withValues(alpha: 0.3), _brand.withValues(alpha: 0.1)]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _brand.withValues(alpha: 0.5))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (knownStreak(_streak) != null) ...[
                const Icon(Icons.local_fire_department,
                  color: _brand, size: 13),
                const SizedBox(width: 4),
                Text('${knownStreak(_streak)}', style: const TextStyle(
                  color: _primary, fontSize: 11,
                  fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
              ],
              // Weeks, not days: PD-B01 retired the daily check-in, so a bare
              // "Streak" beside a weekly count would say something untrue.
              const Text('Week streak', style: TextStyle(
                color: _primary, fontSize: 11,
                fontWeight: FontWeight.w600)),
            ]))),
      ]));
  }

  Widget _sectionLabel(String text) => Text(text,
    style: const TextStyle(color: _white, fontSize: 17,
      fontWeight: FontWeight.w700, letterSpacing: -0.2));

  String _monthAbbr(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m];
}

// ── Week Card ─────────────────────────────────────────────────────────────────
class _WeekCard extends StatelessWidget {
  final String weekLabel;
  const _WeekCard({required this.weekLabel});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [_brand.withValues(alpha: 0.18), _card],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _brand.withValues(alpha: 0.3))),
    child: Row(children: [
      Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _brand.withValues(alpha: 0.15),
          border: Border.all(color: _brand.withValues(alpha: 0.4))),
        child: const Icon(Icons.calendar_month_outlined,
          color: _brand, size: 22)),
      const SizedBox(width: 14),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Weekly Check-In',
            style: TextStyle(color: _white, fontSize: 15,
              fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(weekLabel,
            style: TextStyle(color: _muted.withValues(alpha: 0.55),
              fontSize: 12)),
        ])),
    ]));
}

// ── Sleep Slider ──────────────────────────────────────────────────────────────
class _SleepSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _SleepSlider({required this.value, required this.onChanged});

  String get _label => value >= 8 ? 'Optimal' : value >= 6 ? 'Good' : 'Low';
  Color  get _labelColor => value >= 7 ? _green : _error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${value.toStringAsFixed(1)} hrs',
          style: const TextStyle(color: _white, fontSize: 26,
            fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _labelColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _labelColor.withValues(alpha: 0.3))),
          child: Text(_label,
            style: TextStyle(color: _labelColor, fontSize: 11,
              fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: 8),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 5,
          activeTrackColor: _brand,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
          thumbColor: _white,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
          overlayColor: _brand.withValues(alpha: 0.2)),
        child: Slider(
          value: value, min: 3, max: 12, divisions: 18,
          onChanged: onChanged)),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('3h', style: TextStyle(color: _muted.withValues(alpha: 0.35),
          fontSize: 10, fontWeight: FontWeight.w500)),
        Text('12h', style: TextStyle(color: _muted.withValues(alpha: 0.35),
          fontSize: 10, fontWeight: FontWeight.w500)),
      ]),
    ]));
}

// ── Goal Toggle ───────────────────────────────────────────────────────────────
class _GoalToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final VoidCallback onTap;
  const _GoalToggle({required this.label, required this.icon,
    required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: value ? _brand.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value ? _brand.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08))),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 22, height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? _brand : Colors.transparent,
            border: Border.all(
              color: value ? _brand : _muted.withValues(alpha: 0.3), width: 1.5)),
          child: value
            ? const Icon(Icons.check, color: _white, size: 13)
            : null),
        const SizedBox(width: 10),
        Flexible(child: Text(label,
          style: TextStyle(
            color: value ? _white : _muted.withValues(alpha: 0.5),
            fontSize: 13, fontWeight: FontWeight.w600))),
      ])));
}

// ── Notes Field ───────────────────────────────────────────────────────────────
class _NotesField extends StatelessWidget {
  final TextEditingController controller;
  const _NotesField({required this.controller});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border)),
    child: TextField(
      controller: controller,
      maxLines: 4,
      style: const TextStyle(color: _white, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Anything your coach should know today...',
        hintStyle: TextStyle(color: _muted.withValues(alpha: 0.3), fontSize: 13),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.all(16)),
      onTapOutside: (_) => FocusScope.of(context).unfocus()));
}

// ── Coach Notice ──────────────────────────────────────────────────────────────
class _CoachNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _error.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _error.withValues(alpha: 0.2))),
    child: Row(children: [
      Icon(Icons.info_outline, color: _error, size: 14),
      const SizedBox(width: 8),
      Text('Your coach will be notified',
        style: TextStyle(color: _error.withValues(alpha: 0.85),
          fontSize: 11, fontWeight: FontWeight.w500)),
    ]));
}

// ── Gradient Submit Button ────────────────────────────────────────────────────
class _GradientBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onTap;
  const _GradientBtn({required this.label, this.icon,
    this.loading = false, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: double.infinity, height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: onTap == null
            ? [_brand.withValues(alpha: 0.4), const Color(0xFF7C3AED).withValues(alpha: 0.4)]
            : [_brand, const Color(0xFF7C3AED)],
          begin: Alignment.centerLeft, end: Alignment.centerRight),
        boxShadow: onTap != null
          ? [BoxShadow(color: _brand.withValues(alpha: 0.45),
              blurRadius: 20, offset: const Offset(0, 6))]
          : null),
      child: Center(
        child: loading
          ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(
                color: _white, strokeWidth: 2))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, color: _white, size: 20),
                const SizedBox(width: 8),
              ],
              Text(label, style: const TextStyle(
                color: _white, fontSize: 16,
                fontWeight: FontWeight.w800)),
            ]))));
}

// ── Already Done ──────────────────────────────────────────────────────────────
class _AlreadyDone extends StatelessWidget {
  final VoidCallback onGoHome;
  const _AlreadyDone({required this.onGoHome});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 84, height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              _green.withValues(alpha: 0.25), _green.withValues(alpha: 0.05)]),
            border: Border.all(color: _green.withValues(alpha: 0.4)),
            boxShadow: [BoxShadow(
              color: _green.withValues(alpha: 0.3), blurRadius: 20)]),
          child: const Icon(Icons.check_circle, color: _green, size: 44)),
        const SizedBox(height: 24),
        const Text("Already Checked In!",
          style: TextStyle(color: _white, fontSize: 22,
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text("You've completed this week's check-in.\nSee you next week!",
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted.withValues(alpha: 0.6),
            fontSize: 14, height: 1.5)),
        const SizedBox(height: 32),
        _GradientBtn(label: 'Back to Home',
          icon: Icons.home_outlined, onTap: onGoHome),
      ])));
}

/// FIT-004's two secondary controls: "Past check-ins" and "Add a progress
/// photo". Both are the package's own labels.
class _CheckinLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _CheckinLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
            child: Text(label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: _white, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ),
      );
}

/// CON-01 · the week's check-in state could not be read.
///
/// Not an empty form: the form is how a duplicate weekly check-in gets
/// written. Copy comes from `checkin_hub.dart`, which already carries this
/// repository's `Could not load [noun]` pattern.
class _CheckinUnknown extends StatelessWidget {
  final VoidCallback onRetry;
  const _CheckinUnknown({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, color: _muted, size: 40),
            const SizedBox(height: 14),
            const Text(checkinHistoryFailure,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ]),
        ),
      );
}
