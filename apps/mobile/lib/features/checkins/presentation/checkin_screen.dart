import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../domain/checkin_hub.dart';
import 'checkin_hub_sections.dart';

class _C {
  static const surfaceContainerHigh= Color(0xFF2A2A2B);
  static const glassCard           = Color(0x99201F20);
  static const primary             = Color(0xFFDDB7FF);
  static const primaryContainer    = Color(0xFFB76DFF);
  static const inversePrimary      = Color(0xFF842BD2);
  static const onSurface           = Color(0xFFE5E2E3);
  static const onSurfaceVar        = Color(0xFFCDC3D0);
  static const outline             = Color(0xFF968E99);
  static const outlineVar          = Color(0xFF4B444F);
  static const tertiary            = Color(0xFF6FFBBE);
}

class _Appt {
  final String type;
  final Color typeColor;
  final String title;
  final String time;
  final String duration;
  final String coach;
  final String action;
  final bool isPending;
  const _Appt({
    required this.type, required this.typeColor, required this.title,
    required this.time, required this.duration, required this.coach,
    required this.action, this.isPending = false,
  });

  static _Appt fromCall(Map<String, dynamic> call) {
    final dt = DateTime.tryParse(call['scheduled_at'] as String? ?? '')?.toLocal()
        ?? DateTime.now();
    final callType = call['call_type'] as String? ?? 'check_in';
    final status   = call['status']    as String? ?? 'scheduled';
    final coachFn  = call['coach_first_name'] as String? ?? '';
    final coachLn  = call['coach_last_name']  as String? ?? '';
    final coachName= 'Coach ${('$coachFn $coachLn').trim()}';
    final mins     = call['duration_minutes'] as int? ?? 30;

    final hour = dt.hour;
    final ampm = hour < 12 ? 'AM' : 'PM';
    final h12  = hour % 12 == 0 ? 12 : hour % 12;
    final timeStr = '${h12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $ampm';

    final (typeLabel, typeColor) = switch (callType) {
      'check_in'         => ('WEEKLY CHECK-IN', _C.primary),
      'consultation'     => ('STRATEGY CALL',  _C.tertiary),
      'nutrition_review' => ('NUTRITION',      const Color(0xFFF8ACFF)),
      _                  => ('COACHING CALL',  _C.primaryContainer),
    };
    final title = switch (callType) {
      'check_in'         => 'Weekly Check-In',
      'consultation'     => 'Strategy Session',
      'nutrition_review' => 'Nutrition Review',
      _                  => 'Coaching Call',
    };
    final isPending = status == 'scheduled' &&
        dt.isAfter(DateTime.now().add(const Duration(hours: 1)));

    return _Appt(
      type: typeLabel, typeColor: typeColor,
      title: title, time: timeStr, duration: '${mins}m',
      coach: coachName,
      action: isPending ? 'UPCOMING' : 'JOIN',
      isPending: status != 'scheduled',
    );
  }
}

class CheckinScreen extends ConsumerStatefulWidget {
  const CheckinScreen({super.key});

  @override
  ConsumerState<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends ConsumerState<CheckinScreen> {
  int _selectedDay = 0;
  late int _currentMonth;
  late int _currentYear;

  late List<int> _dates;
  late List<bool> _hasDot;
  final _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  List<_Appt> _appointments = [];
  bool _loading = true;
  /// F-15: a failed read is not an empty schedule. This used to end
  /// `catch (_) { _loading = false; }`, so a client whose session list failed
  /// to load was told they had no upcoming sessions and should book one.
  bool _callsFailed = false;

  @override
  void initState() {
    super.initState();
    _initWeek();
    _loadCalls();
  }

  void _initWeek() {
    final now = DateTime.now();
    // Start from Monday of current week
    final monday = now.subtract(Duration(days: now.weekday - 1));
    _dates = List.generate(7, (i) => monday.add(Duration(days: i)).day);
    _currentMonth = now.month - 1; // 0-indexed for display
    _currentYear  = now.year;
    // Select today's day index (0 = Mon)
    _selectedDay  = (now.weekday - 1).clamp(0, 6);
    _hasDot = List.filled(7, false);
  }

  Future<void> _loadCalls() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      if (mounted) setState(() => _callsFailed = false);
      final now = DateTime.now();
      final rows = await Supabase.instance.client
          .from('coaching_calls')
          .select('*, coach:coach_id(first_name, last_name)')
          .eq('client_id', uid)
          .eq('status', 'scheduled')
          .gte('scheduled_at', now.toIso8601String())
          .order('scheduled_at')
          .limit(10);

      final appts = <_Appt>[];
      final dotDates = <int>{};
      for (final r in (rows as List)) {
        final flat = Map<String, dynamic>.from(r as Map);
        final coachMap = flat['coach'] as Map<String, dynamic>? ?? {};
        flat['coach_first_name'] = coachMap['first_name'];
        flat['coach_last_name']  = coachMap['last_name'];
        appts.add(_Appt.fromCall(flat));
        final dt = DateTime.tryParse(r['scheduled_at'] as String? ?? '')?.toLocal();
        if (dt != null) dotDates.add(dt.day);
      }
      // Mark week dots for days that have calls
      final now2 = DateTime.now();
      final monday = now2.subtract(Duration(days: now2.weekday - 1));
      if (!mounted) return;
      setState(() {
        _appointments = appts;
        _hasDot = List.generate(7, (i) =>
            dotDates.contains(monday.add(Duration(days: i)).day));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _callsFailed = true; });
    }
  }

  String get _monthYear {
    const months = ['January','February','March','April','May','June',
      'July','August','September','October','November','December'];
    return '${months[_currentMonth]} $_currentYear';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Month + nav
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_monthYear,
                      style: const TextStyle(
                        color: _C.onSurface, fontSize: 24,
                        fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    Row(children: [
                      _NavBtn(icon: Icons.chevron_left,
                        onTap: () => setState(() {
                          if (_currentMonth == 0) { _currentMonth = 11; _currentYear--; }
                          else { _currentMonth--; }
                        })),
                      const SizedBox(width: 8),
                      _NavBtn(icon: Icons.chevron_right,
                        onTap: () => setState(() {
                          if (_currentMonth == 11) { _currentMonth = 0; _currentYear++; }
                          else { _currentMonth++; }
                        })),
                    ]),
                  ],
                ),
                const SizedBox(height: 20),

                // Day headers
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _days.map((d) => Expanded(
                    child: Center(
                      child: Text(d,
                        style: const TextStyle(color: _C.outline, fontSize: 10,
                          fontWeight: FontWeight.w600, letterSpacing: 1)),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 8),

                // Date row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(_dates.length, (i) {
                    final active = i == _selectedDay;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedDay = i),
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: active ? _C.inversePrimary : Colors.transparent,
                                boxShadow: active ? [
                                  const BoxShadow(color: Color(0x55842BD2), blurRadius: 12),
                                ] : null,
                              ),
                              alignment: Alignment.center,
                              child: Text('${_dates[i]}',
                                style: TextStyle(
                                  color: active ? Colors.white : _C.onSurface,
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 5, height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _hasDot[i]
                                    ? _C.primary.withValues(alpha: 0.7)
                                    : Colors.transparent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),

                // FIT-023 · the hub's two declared controls and its history.
                const CheckinHubSections(),

                const SizedBox(height: 28),

                // Upcoming sessions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Upcoming Sessions',
                      style: TextStyle(color: _C.onSurface, fontSize: 22,
                        fontWeight: FontWeight.w700)),
                    if (_appointments.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _C.inversePrimary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _C.inversePrimary.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '${_appointments.length} APPT${_appointments.length == 1 ? '' : 'S'}',
                          style: const TextStyle(color: _C.primary, fontSize: 10,
                            fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_loading)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: _C.primary),
                  ))
                else if (_callsFailed)
                  // NOT "no upcoming sessions". A failed read knows nothing
                  // about this client's schedule, and telling them to book a
                  // call they may already have booked is the F-15 collapse.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    decoration: BoxDecoration(
                      color: _C.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _C.outlineVar.withValues(alpha: 0.3)),
                    ),
                    child: Column(children: [
                      const Icon(Icons.cloud_off_rounded, color: Color(0xFFFFB4AB), size: 32),
                      const SizedBox(height: 10),
                      const Text(checkinSessionsFailure,
                        style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 14,
                          fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Semantics(
                        button: true,
                        child: GestureDetector(
                          onTap: _loadCalls,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
                            // The package's own label, 16 declarations.
                            child: const Text('Try again',
                              style: TextStyle(color: _C.onSurface, fontSize: 13,
                                fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ]),
                  )
                else if (_appointments.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                    decoration: BoxDecoration(
                      color: _C.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _C.outlineVar.withValues(alpha: 0.3)),
                    ),
                    child: Column(children: [
                      Icon(Icons.event_available_rounded, color: _C.outline, size: 40),
                      const SizedBox(height: 12),
                      const Text('No upcoming sessions',
                        style: TextStyle(color: _C.onSurface, fontSize: 16,
                          fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      const Text('Book a call with your coach to get started.',
                        style: TextStyle(color: _C.onSurfaceVar, fontSize: 13),
                        textAlign: TextAlign.center),
                    ]),
                  )
                else
                  ..._appointments.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ApptCard(appt: a),
                  )),
              ],
            ),
          ),

          // Premium FAB
          Positioned(
            bottom: 110, right: 16,
            child: _PremiumFab(onTap: () {}),
          ),
        ],
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: _C.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.outlineVar.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: _C.onSurface, size: 20),
      ),
    );
  }
}

IconData _apptIcon(String type) => switch (type) {
  'WEEKLY CHECK-IN'  => Icons.check_circle_outline_rounded,
  'STRATEGY CALL'    => Icons.insights_rounded,
  'NUTRITION'        => Icons.restaurant_rounded,
  _                  => Icons.video_call_rounded,
};

class _ApptCard extends StatelessWidget {
  final _Appt appt;
  const _ApptCard({required this.appt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.glassCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: appt.typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: appt.typeColor.withValues(alpha: 0.3)),
            ),
            alignment: Alignment.center,
            child: Icon(_apptIcon(appt.type), color: appt.typeColor, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appt.type,
                  style: TextStyle(color: appt.typeColor, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(appt.title,
                  style: const TextStyle(color: _C.onSurface, fontSize: 17,
                    fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.schedule_outlined, color: _C.onSurfaceVar, size: 14),
                  const SizedBox(width: 4),
                  Text('${appt.time} • ${appt.duration}',
                    style: const TextStyle(color: _C.onSurfaceVar, fontSize: 13)),
                ]),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('with ${appt.coach}',
                      style: const TextStyle(color: _C.onSurfaceVar,
                        fontSize: 13, fontStyle: FontStyle.italic)),
                    appt.isPending
                        ? const Text('PENDING',
                            style: TextStyle(color: _C.outline, fontSize: 11,
                              fontWeight: FontWeight.w600, letterSpacing: 1.5))
                        : GestureDetector(
                            onTap: () {},
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 7),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: appt.action == 'JOIN'
                                    ? _C.inversePrimary : Colors.transparent,
                                border: appt.action == 'JOIN'
                                    ? null
                                    : Border.all(color: _C.outlineVar),
                              ),
                              child: Text(appt.action,
                                style: TextStyle(
                                  color: appt.action == 'JOIN'
                                      ? Colors.white : _C.onSurface,
                                  fontSize: 11, fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5)),
                            ),
                          ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumFab extends StatefulWidget {
  final VoidCallback onTap;
  const _PremiumFab({required this.onTap});

  @override
  State<_PremiumFab> createState() => _PremiumFabState();
}

class _PremiumFabState extends State<_PremiumFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _glowAnim = Tween<double>(begin: 0.3, end: 0.7)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Transform.scale(
          scale: _pulseAnim.value,
          child: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_C.inversePrimary, _C.primaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _C.inversePrimary.withValues(alpha: _glowAnim.value),
                  blurRadius: 24, spreadRadius: 2),
                BoxShadow(
                  color: _C.primary.withValues(alpha: _glowAnim.value * 0.4),
                  blurRadius: 40, spreadRadius: 4),
              ],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}
