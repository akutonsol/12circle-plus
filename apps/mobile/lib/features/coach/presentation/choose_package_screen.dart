import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/observability/app_failure.dart';
import '../../../shared/theme/app_background.dart';
import '../../auth/domain/auth_provider.dart';
import '../../payments/data/payment_service.dart'
    show CheckoutRefused, signedInUid;
import '../../payments/domain/payment_provider.dart';
import '../../payments/presentation/checkout_launcher.dart'
    show recordOutcomeNotShown;
import '../../workout/presentation/widgets/section_load_failure.dart';
import '../data/coach_relationship_service.dart' show AccountChangedError;
import '../domain/package_provider.dart';

const _card   = Color(0xFF0E0B16);
const _border = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _mint   = Color(0xFF6FFBBE);
const _amber  = Color(0xFFFFD479);

const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _dayKeys  = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
// Sensible default day spread for N training days/week.
const _defaultSpread = {
  1: [2], 2: [0, 3], 3: [0, 2, 4], 4: [0, 1, 3, 4],
  5: [0, 1, 2, 3, 4], 6: [0, 1, 2, 3, 4, 5], 7: [0, 1, 2, 3, 4, 5, 6],
};

String _typeLabel(String t) => switch (t) {
      'per_session' => 'Per Session', 'bulk' => 'Session Package', 'monthly' => 'Monthly Plan', _ => t };
Color _typeColor(String t) => switch (t) {
      'per_session' => _mint, 'bulk' => _amber, _ => _brand };

/// Client picks one of the coach's packages, then confirms/modifies the
/// training days + time (seeded from their onboarding choice).
class ChoosePackageScreen extends ConsumerStatefulWidget {
  final String coachId, coachName;
  const ChoosePackageScreen({super.key, required this.coachId, required this.coachName});
  @override
  ConsumerState<ChoosePackageScreen> createState() => _ChoosePackageScreenState();
}

class _ChoosePackageScreenState extends ConsumerState<ChoosePackageScreen> {
  Map<String, dynamic>? _selected;
  String? _currentPackageId;   // the package the client is currently on
  final Set<int> _days = {};
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0); // default for new days
  final Map<int, TimeOfDay> _dayTimes = {};             // per-day override
  bool _saving = false;

  /// P0-FL-56b: what is on this screen (the chosen package, days, times)
  /// belongs to [_seedFor], the client signed in now; [_seedSeq] discards a
  /// late answer for an earlier client or an earlier try.
  bool _seedStarted = false;
  String? _seedFor;
  int _seedSeq = 0;

  /// The client's schedule was read (a genuine "none yet" included). Until then
  /// the days are not offered and Save is paused: saving replaces the whole
  /// schedule, so it must not be built on one that was not read.
  bool _seedReady = false;
  bool _seedLoading = false;
  Object? _seedError;

  /// The last save's failure, said above the button.
  String? _saveError;

  TimeOfDay _parseTime(String t) => TimeOfDay(
        hour: int.tryParse(t.split(':')[0]) ?? 7,
        minute: int.tryParse(t.split(':').elementAt(1)) ?? 0);
  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Called from build: the first load, and again for another client.
  void _followClient(String? uid) {
    if (_seedStarted && _seedFor == uid) return;
    _seedStarted = true;
    _seedFor = uid;
    _selected = null;
    _currentPackageId = null;
    _days.clear();
    _dayTimes.clear();
    _time = const TimeOfDay(hour: 7, minute: 0);
    _saving = false;
    _saveError = null;
    _seedReady = false;
    _seedError = null;
    _seedDays();
  }

  Future<void> _seedDays() async {
    final seq = ++_seedSeq;
    _seedLoading = true;
    final svc = ref.read(packageServiceProvider);
    final Map<String, dynamic>? existing;
    var onboardingDays = 0;
    try {
      // Prefer an existing schedule; else seed from onboarding days/week.
      existing = await svc.getMySchedule();
      if ((existing?['days'] as List?)?.isNotEmpty != true) {
        onboardingDays = await svc.getOnboardingTrainingDays();
      }
    } catch (e, st) {
      // P0-FL-56b: this escaped unhandled; the days read as none, the current
      // plan as no plan, and saving replaced a schedule that was never read.
      reportError('ChoosePackageScreen._seedDays', e, st);
      if (!mounted || seq != _seedSeq) return;
      setState(() {
        _seedLoading = false;
        _seedError = e;
      });
      return;
    }
    if (!mounted || seq != _seedSeq) return;
    _currentPackageId = existing?['package_id'] as String?;
    if (existing != null && (existing['days'] as List?)?.isNotEmpty == true) {
      _days.addAll((existing['days'] as List)
          .map((d) => _dayKeys.indexOf('$d'))
          .where((i) => i >= 0));
      final t = existing['session_time'] as String?;
      if (t != null && t.contains(':')) _time = _parseTime(t);
      final dt = existing['day_times'];
      if (dt is Map) {
        for (final e in dt.entries) {
          final i = _dayKeys.indexOf('${e.key}');
          if (i >= 0 && '${e.value}'.contains(':')) _dayTimes[i] = _parseTime('${e.value}');
        }
      }
    } else {
      _days.addAll(_defaultSpread[onboardingDays.clamp(0, 7)] ?? const []);
    }
    // Every selected day needs a time (fall back to the default).
    for (final i in _days) {
      _dayTimes[i] ??= _time;
    }
    setState(() {
      _seedLoading = false;
      _seedError = null;
      _seedReady = true;
    });
  }

  /// True — and recorded once as the package checkout's outcome not shown —
  /// when the account that saved ([client], in sign-in [seq]) is no longer
  /// the one on this screen: another account, nobody, or the same client
  /// signed in again (A → B → A, a new sign-in). Read from the auth client
  /// itself, not a provider that may not have rebuilt yet (P0-RM-1).
  bool _outcomeDropped(String? client, int seq) {
    if (signedInUid() == client && seq == _seedSeq) return false;
    recordOutcomeNotShown('ChoosePackageScreen._save', 'package checkout');
    return true;
  }

  Future<void> _save() async {
    if (_selected == null || _days.isEmpty || _saving || !_seedReady) return;
    final client = _seedFor;
    // The sign-in this save belongs to: after A → B → A the client is A again,
    // but the screen was reset and this save is not the one on it (P0-FL-56b).
    final seq = _seedSeq;
    if (ref.read(currentUserProvider)?.id != client) return;
    // Read now: leaving the screen mid-save must not leave the saved schedule
    // unread elsewhere, and `ref` is unusable after dispose.
    final container = ProviderScope.containerOf(context, listen: false);
    final svc = ref.read(packageServiceProvider);
    final payments = ref.read(paymentServiceProvider);
    final selected = _selected!;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final dayTimes = <String, String>{
      for (final i in _days) _dayKeys[i]: _fmt(_dayTimes[i] ?? _time),
    };
    final sorted = _days.toList()..sort();
    final baseTime = _fmt(_dayTimes[sorted.first] ?? _time);
    // Save the schedule first so the client's choice isn't lost if they bail at
    // the payment step (they can return and pay later).
    try {
      await svc.saveSchedule(
        coachId: widget.coachId,
        packageId: selected['id'] as String?,
        days: _days.map((i) => _dayKeys[i]).toList(),
        sessionTime: baseTime,
        dayTimes: dayTimes,
        // P0-RM-1 (S-2): stamped with the client who tapped, not a fresh read.
        expectedUid: client,
      );
    } catch (e, st) {
      // P0-FL-56b: a failed save escaped unhandled and the button spun for
      // good. Nothing was confirmed saved, so neither booking nor payment
      // follows; what the client chose stays.
      // An AccountChangedError was recorded by the service (once) and is not
      // for whoever is signed in now.
      if (e is AccountChangedError) {
        if (mounted && seq == _seedSeq && signedInUid() == client) {
          setState(() => _saving = false);
        }
        return;
      }
      reportError('ChoosePackageScreen._save', e, st);
      if (!mounted || seq != _seedSeq) return;
      setState(() {
        _saving = false;
        _saveError = couldntMessage('save your schedule', e);
      });
      return;
    }
    container.invalidate(myScheduleProvider);
    // Left, or another client signed in: no booking or payment for them.
    // P0-RM-1 (C15-63b-04): the schedule IS saved; when the account changed
    // that is an outcome nobody was shown, recorded once — nothing of it (no
    // package, no price) is said to whoever is signed in now.
    if (_outcomeDropped(client, seq)) return;
    if (!mounted || ref.read(currentUserProvider)?.id != client) return;

    final price = (selected['price'] as num?)?.toDouble() ?? 0;
    // Free package (price 0) — nothing to charge. Hand off to booking.
    if (price <= 0) {
      setState(() => _saving = false);
      context.go('/booking-handoff');
      return;
    }

    // Paid package → Stripe Checkout. The webhook activates the coaching
    // relationship + grants session credits once payment succeeds.
    var problem = 'Schedule saved, but we couldn’t open checkout. Please try again.';
    var ok = false;
    try {
      ok = await payments.startCheckout(
        kind: 'package',
        packageId: selected['id'] as String?,
      );
    } on CheckoutRefused catch (e) {
      // The server's answer (the client already has this plan): trying again
      // would never work, so the reason is said, as launchCheckout does.
      problem = 'Schedule saved. ${e.message}';
    } catch (e, st) {
      reportError('ChoosePackageScreen._save.checkout', e, st);
    }
    // P0-RM-1 (C15-63b-04): the checkout was asked for; when the account
    // changed meanwhile, its outcome is recorded once as not shown.
    if (_outcomeDropped(client, seq)) return;
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Schedule saved — complete payment to activate your coaching.')));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Semantics(liveRegion: true, child: Text(problem)),
          backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    _followClient(ref.watch(currentUserProvider)?.id);
    final pkgsAsync = ref.watch(coachPackagesProvider(widget.coachId));
    // A coach's published packages are the same for every client, so what was
    // read stays through a failed re-read (P0-FL-56b).
    final pkgs = pkgsAsync.hasValue ? pkgsAsync.value : null;
    final failure = !pkgsAsync.hasError
        ? null
        : SectionLoadFailure(
            what: 'packages',
            error: pkgsAsync.error,
            busy: pkgsAsync.isLoading,
            onRetry: () => ref.invalidate(coachPackagesProvider(widget.coachId)),
            accent: _brand,
            textColor: _white,
            mutedColor: _muted,
            detail: pkgs == null ? null : 'The list below may be out of date.',
          );
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0,
          iconTheme: const IconThemeData(color: _white),
          title: Text('Train with ${widget.coachName}',
              style: const TextStyle(color: _white, fontWeight: FontWeight.w700)),
        ),
        body: Builder(
          builder: (context) {
            if (pkgs == null) {
              return failure == null
                  ? const Center(child: CircularProgressIndicator(color: _brand))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                      children: [failure]);
            }
            if (pkgs.isEmpty && failure == null) {
              return const Center(child: Padding(padding: EdgeInsets.all(32),
                child: Text('This coach hasn’t published any packages yet.',
                    textAlign: TextAlign.center, style: TextStyle(color: _muted))));
            }
            // Pre-select the plan the client is currently on.
            if (_selected == null && _currentPackageId != null) {
              final cur = pkgs.where((p) => p['id'] == _currentPackageId);
              if (cur.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _selected == null) setState(() => _selected = cur.first);
                });
              }
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const Text('Choose a package',
                    style: TextStyle(color: _white, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                if (failure != null) ...[failure, const SizedBox(height: 8)],
                ...pkgs.map((p) => _pkgCard(p)),
                const SizedBox(height: 24),
                const Text('Your training schedule',
                    style: TextStyle(color: _white, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                if (!_seedReady && _seedError != null)
                  SectionLoadFailure(
                    what: 'your training schedule',
                    error: _seedError,
                    busy: _seedLoading,
                    onRetry: () => setState(() { _seedDays(); }),
                    accent: _brand,
                    textColor: _white,
                    mutedColor: _muted,
                    detail: 'Saving is paused until it loads.',
                  )
                else if (!_seedReady)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: _brand, semanticsLabel: 'Loading your training schedule')))
                else ...[
                const Text('We pre-filled this from your onboarding — confirm or change your days, then set a time for each.',
                    style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _brand.withValues(alpha: 0.2)),
                  ),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, color: _brand, size: 16),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'These are your solo training days — the days you’re not training directly with your coach. '
                      'Your coach will assign workouts for you to do on your own at these times.',
                      style: TextStyle(color: _muted, fontSize: 12, height: 1.4))),
                  ]),
                ),
                const SizedBox(height: 14),
                _daysPicker(),
                const SizedBox(height: 16),
                _perDayTimes(),
                ],
                const SizedBox(height: 24),
                if (_saveError != null) ...[
                  Semantics(liveRegion: true, child: Text(_saveError!,
                      style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 13, height: 1.35))),
                  const SizedBox(height: 12),
                ],
                SizedBox(width: double.infinity, child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand, foregroundColor: _white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: (_selected == null || _days.isEmpty || _saving || !_seedReady) ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _white, semanticsLabel: 'Saving'))
                      : Text(_buttonLabel(),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                )),
              ],
            );
          },
        ),
      ),
    );
  }

  String _buttonLabel() {
    if (_selected == null) return 'Select a package';
    final price = (_selected!['price'] as num?)?.toDouble() ?? 0;
    if (price <= 0) return 'Confirm & save schedule';
    final type = _selected!['type'] as String? ?? '';
    final per = type == 'monthly' ? '/mo' : '';
    return 'Continue to payment · \$${price.toStringAsFixed(0)}$per';
  }

  Widget _pkgCard(Map<String, dynamic> p) {
    final type = p['type'] as String? ?? 'monthly';
    final color = _typeColor(type);
    final price = (p['price'] as num?)?.toDouble() ?? 0;
    final sessions = (p['sessions'] as num?)?.toInt() ?? 0;
    final per = type == 'monthly' ? '/mo' : type == 'per_session' ? '/session' : '';
    final selected = _selected?['id'] == p['id'];
    return GestureDetector(
      onTap: () => setState(() => _selected = p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [color.withValues(alpha: selected ? 0.20 : 0.10), _card]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? color : color.withValues(alpha: 0.25), width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: color),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(_typeLabel(type), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              if (p['id'] == _currentPackageId) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.5))),
                  child: Text('CURRENT PLAN', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
            Text(p['name'] as String? ?? '', style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
            if (type == 'bulk') Text('$sessions sessions', style: const TextStyle(color: _muted, fontSize: 12)),
            if ((p['description'] as String?)?.isNotEmpty ?? false)
              Text(p['description'] as String, style: const TextStyle(color: _muted, fontSize: 12)),
          ])),
          Text('\$${price.toStringAsFixed(0)}$per',
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _daysPicker() => Wrap(
        spacing: 8, runSpacing: 8,
        children: List.generate(7, (i) {
          final on = _days.contains(i);
          return GestureDetector(
            onTap: () => setState(() {
              if (on) {
                _days.remove(i);
                _dayTimes.remove(i);
              } else {
                _days.add(i);
                _dayTimes[i] ??= _time;
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: on ? _brand.withValues(alpha: 0.18) : _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: on ? _brand : _border)),
              child: Text(_dayNames[i].substring(0, 3),
                  style: TextStyle(color: on ? _white : _muted, fontWeight: FontWeight.w600)),
            ),
          );
        }),
      );

  // A time picker per selected day, so the client can train at different times
  // on different days.
  Widget _perDayTimes() {
    if (_days.isEmpty) {
      return const Text('Pick your training days above to set times.',
          style: TextStyle(color: _muted, fontSize: 13));
    }
    final sorted = _days.toList()..sort();
    return Column(children: [
      for (final i in sorted) Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () async {
            final seq = _seedSeq;
            final t = await showTimePicker(
                context: context, initialTime: _dayTimes[i] ?? _time);
            if (t != null && mounted && seq == _seedSeq) setState(() { _dayTimes[i] = t; _time = t; });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border)),
            child: Row(children: [
              const Icon(Icons.schedule_rounded, color: _brand, size: 20),
              const SizedBox(width: 12),
              Text(_dayNames[i], style: const TextStyle(color: _white, fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text((_dayTimes[i] ?? _time).format(context),
                  style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              const Icon(Icons.edit, color: _muted, size: 14),
            ]),
          ),
        ),
      ),
    ]);
  }
}
