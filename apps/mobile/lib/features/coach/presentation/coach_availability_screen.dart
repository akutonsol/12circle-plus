import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import '../../../core/observability/network_failure.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';

const _bg    = Color(0xFF030303);
const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _tert  = Color(0xFF6FFBBE);
const _wht   = Colors.white;
const _mut   = Color(0xFFCFC2D6);

/// Text is scaled past 1.3×: a card's pieces go under one another (P0-FL-58).
bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(12) > 12 * 1.3;

class CoachAvailabilityScreen extends StatefulWidget {
  const CoachAvailabilityScreen({super.key});
  @override
  State<CoachAvailabilityScreen> createState() => _CoachAvailabilityScreenState();
}

class _CoachAvailabilityScreenState extends State<CoachAvailabilityScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _slots = [];
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  /// P0-FL-14 · the last load failed. A failed read is not "no slots" and "no
  /// upcoming sessions": the page says so and offers Try again.
  Object? _loadError;
  /// Slots whose delete is in flight: their button is disabled (no double fire).
  final Set<String> _deleting = {};
  /// Sessions whose cancel is in flight: their Cancel is disabled.
  final Set<String> _cancelling = {};

  /// The next step for a thrown failure; the connection hint only when it IS
  /// the connection.
  static String _nextStep(Object e) => isNetworkFailure(e)
      ? 'check your connection and try again.'
      : 'try again in a moment. If it keeps happening, contact support.';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final uid = _db.auth.currentUser?.id;
      final data = await _db
          .from('coach_availability')
          .select()
          .eq('coach_id', uid!)
          .gte('slot_time', DateTime.now().toUtc().toIso8601String())
          // Soonest first, stated: postgrest-dart orders DESCENDING when
          // `ascending` is omitted, which listed these furthest first.
          .order('slot_time', ascending: true);

      // Upcoming booked sessions, with the client who booked.
      final calls = await _db
          .from('coaching_calls')
          .select('id, scheduled_at, duration_minutes, call_type, status, '
              'availability_slot_id, client_id, '
              'client:client_id(first_name, last_name, avatar_url)')
          .eq('coach_id', uid)
          .eq('status', 'scheduled')
          .gte('scheduled_at', DateTime.now().toUtc().toIso8601String())
          .order('scheduled_at', ascending: true);

      if (!mounted) return;
      setState(() {
        _slots = List<Map<String, dynamic>>.from(data);
        _sessions = List<Map<String, dynamic>>.from(calls);
        _loading = false;
      });
    } catch (e, st) {
      reportError('CoachAvailabilityScreen._load', e, st);
      if (mounted) setState(() { _loading = false; _loadError = e; });
    }
  }

  /// P0-FL-14 · a delete is done only when the server says a row went: a
  /// thrown failure and a 0-row delete (RLS filters silently, or the slot was
  /// already gone or booked) are both said on this page, not swallowed.
  Future<void> _delete(String id) async {
    if (_deleting.contains(id)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting.add(id));
    try {
      final rows = await _db
          .from('coach_availability')
          .delete()
          .eq('id', id)
          .select('id');
      if (!mounted) return;
      setState(() => _deleting.remove(id));
      if ((rows as List).isEmpty) {
        // P0-FL-53b · said, but was never recorded.
        reportError('CoachAvailabilityScreen._delete',
            StateError('coach_availability delete matched no row'));
        messenger.showSnackBar(const SnackBar(content: Text(
            "Couldn't remove this slot — it may already be gone or booked. "
            'Refreshing your list.')));
      }
      _load();
    } catch (e, st) {
      reportError('CoachAvailabilityScreen._delete', e, st);
      if (!mounted) return;
      setState(() => _deleting.remove(id));
      messenger.showSnackBar(SnackBar(content: Text(
          "Couldn't remove this slot — ${_nextStep(e)}")));
    }
  }

  Future<void> _cancelSession(Map<String, dynamic> call) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: _card,
        scrollable: true, // P0-FL-58 · at 3× on a short phone it was cut off
        title: const Text('Cancel session?', style: TextStyle(color: _wht, fontWeight: FontWeight.w800)),
        content: const Text('The client will be notified and the slot reopened.',
            style: TextStyle(color: _mut)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Keep', style: TextStyle(color: _mut))),
          TextButton(onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Cancel session', style: TextStyle(color: Color(0xFFFFB4AB)))),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = call['id'] as String;
    if (_cancelling.contains(id)) return;
    if (mounted) setState(() => _cancelling.add(id));
    // P0-FL-39 · step 1, the call: cancelled only when the server says the
    // row changed. A 0-row update (RLS filters silently, or the call is
    // already gone) answers like a saved one unless the row is asked back.
    // On failure nothing else is written and the client is not notified.
    try {
      // P0-FL-46 · only a still-scheduled call is cancelled (this screen
      // offers Cancel only for scheduled sessions). One the client already
      // cancelled matched the id-only filter, so it was "cancelled" again and
      // the client got a false "your coach cancelled" notice; now it matches
      // no row and takes the 0-row path below.
      final rows = await _db
          .from('coaching_calls')
          .update({'status': 'cancelled'})
          .eq('id', id)
          .eq('status', 'scheduled')
          .select('id');
      if ((rows as List).isEmpty) {
        reportError('CoachAvailabilityScreen._cancelSession',
            StateError('coaching_calls update matched no row'));
        if (!mounted) return;
        setState(() => _cancelling.remove(id));
        // P0-FL-46 review N2 · a failure notice is announced (live region).
        messenger.showSnackBar(SnackBar(
            content: Semantics(liveRegion: true, child: const Text(
                "Couldn't cancel this session — it may already be cancelled. "
                'Refreshing your sessions.'))));
        _load();
        return;
      }
    } catch (e, st) {
      reportError('CoachAvailabilityScreen._cancelSession', e, st);
      if (!mounted) return;
      setState(() => _cancelling.remove(id));
      messenger.showSnackBar(SnackBar(
          content: Semantics(liveRegion: true, child: Text(
              "Couldn't cancel this session — ${_nextStep(e)}"))));
      return;
    }
    // Step 2, the slot. The call IS cancelled from here on, so a slot that
    // fails to reopen is said as exactly that — never as a failed cancel —
    // with a retry that re-sends only the slot update.
    final slotId = call['availability_slot_id'] as String?;
    final slotError = slotId == null ? null : await _reopenSlot(slotId);
    // Best-effort, and reported: the cancel above is saved, and a failed
    // notification thrown from here read as a failed cancel (N3).
    var notified = false;
    try {
      await _db.from('notifications').insert({
        'recipient_id': call['client_id'],
        'type': 'session_cancelled',
        'title': 'Session cancelled',
        'body': 'Your coach had to cancel a scheduled session. You can rebook any time.',
        'read': false,
      });
      notified = true;
    } catch (e) {
      reportError('CoachAvailabilityScreen._cancelSession.notify', e);
    }
    if (mounted) setState(() => _cancelling.remove(id));
    final done =
        notified ? 'Session cancelled — client notified.' : 'Session cancelled.';
    if (slotError == null) {
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } else {
      _sayReopenFailed(messenger, slotId!, slotError,
          lead: '${done.substring(0, done.length - 1)}. ');
    }
    _load();
  }

  /// Sets the slot of a cancelled call back to open. Returns null when the
  /// server confirmed a row changed, otherwise the failure (reported here).
  Future<Object?> _reopenSlot(String slotId) async {
    try {
      final rows = await _db
          .from('coach_availability')
          .update({'is_booked': false})
          .eq('id', slotId)
          .select('id');
      if ((rows as List).isNotEmpty) return null;
      final e = StateError('coach_availability update matched no row');
      reportError('CoachAvailabilityScreen._cancelSession.reopenSlot', e);
      return e;
    } catch (e, st) {
      reportError('CoachAvailabilityScreen._cancelSession.reopenSlot', e, st);
      return e;
    }
  }

  /// "Couldn't reopen its slot" with a Reopen slot retry (a SnackBarAction:
  /// it fires once, then disables itself — no double fire).
  ///
  /// UX-5 · it stays until acted on (retry or close): the slot is still
  /// booked, and a timed toast let that pass unseen.
  void _sayReopenFailed(ScaffoldMessengerState messenger, String slotId,
      Object e, {String lead = ''}) {
    final next = isNetworkFailure(e)
        ? 'check your connection and tap Reopen slot.'
        : 'tap Reopen slot to try again. If it keeps happening, contact '
            'support.';
    messenger.showSnackBar(SnackBar(
      persist: true,
      showCloseIcon: true,
      content: Semantics(liveRegion: true,
          child: Text("${lead}Couldn't reopen its slot — $next")),
      action: SnackBarAction(
        label: 'Reopen slot',
        onPressed: () async {
          final again = await _reopenSlot(slotId);
          if (again == null) {
            messenger.showSnackBar(
                const SnackBar(content: Text('Slot reopened.')));
          } else {
            _sayReopenFailed(messenger, slotId, again);
          }
          if (mounted) _load();
        },
      ),
    ));
  }

  void _showAddSheet() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: _card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _AddSlotSheet(onSaved: _load),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final s in _slots) {
      final dt = DateTime.parse(s['slot_time'] as String).toLocal();
      final key = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
      grouped.putIfAbsent(key, () => []).add(s);
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _wht, size: 20),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context)),
        title: const Text('Manage Availability',
          style: TextStyle(color: _wht, fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          // P0-FL-14 (UX-2) · while the load has failed the coach cannot see
          // the schedule, so adding a slot to it is disabled until it loads.
          IconButton(
            tooltip: 'Add slot',
            icon: const Icon(Icons.add_circle_outline_rounded, color: _tert, size: 24),
            onPressed: _loadError != null ? null : _showAddSheet),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : _loadError != null
          ? _LoadFailed(message: "Couldn't load your availability — "
                '${_nextStep(_loadError!)}', onRetry: _load)
          : ListView(
              // P0-FL-58 · room under the last card: the Add Slot button
              // floats over the list and covered its delete button. (96 at 1×;
              // it grows with that button.)
              padding: EdgeInsets.fromLTRB(16, 16, 16,
                  56 + MediaQuery.textScalerOf(context).scale(40)),
              children: [
                // ── Upcoming booked sessions ──
                if (_sessions.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text('UPCOMING SESSIONS',
                        style: TextStyle(color: _brand, fontSize: 13,
                            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                  ..._sessions.map((c) => _SessionTile(
                        call: c,
                        cancelling: _cancelling.contains(c['id']),
                        onCancel: () => _cancelSession(c),
                      )),
                  const SizedBox(height: 20),
                ],
                // ── Availability slots ──
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('YOUR AVAILABILITY',
                      style: TextStyle(color: _tert, fontSize: 13,
                          fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ),
                if (grouped.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: _EmptyState(onAdd: _showAddSheet),
                  ),
                ...grouped.entries.map((entry) {
                  final dt = DateTime.parse(entry.key);
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(_dateLabel(dt),
                        style: const TextStyle(color: _tert, fontSize: 13, fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                    ),
                    ...entry.value.map((s) => _SlotTile(slot: s,
                        day: _dateLabel(dt),
                        deleting: _deleting.contains(s['id']),
                        onDelete: () => _delete(s['id'] as String))),
                  ]);
                }),
              ],
            ),
      // P0-FL-58 · 56px at least (it was 56px exactly: 3× text was cut), and its
      // label wraps inside the screen: 104 = margins, padding, icon and gap.
      floatingActionButton: Theme(
        data: theme.copyWith(floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
          extendedSizeConstraints: const BoxConstraints(minHeight: 56))),
        child: FloatingActionButton.extended(
          onPressed: _showAddSheet,
          backgroundColor: _brand,
          icon: const Icon(Icons.add, color: _wht),
          label: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 104),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Add Slot', style: TextStyle(color: _wht, fontWeight: FontWeight.w700)))),
        ),
      ),
    );
  }

  String _dateLabel(DateTime dt) {
    final days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}';
  }
}

class _SessionTile extends StatelessWidget {
  final Map<String, dynamic> call;
  final VoidCallback onCancel;
  /// The cancel is in flight: the button is disabled (no double fire).
  final bool cancelling;
  const _SessionTile({required this.call, required this.onCancel, this.cancelling = false});

  @override
  Widget build(BuildContext context) {
    final client = call['client'] as Map<String, dynamic>? ?? {};
    final name = '${client['first_name'] ?? ''} ${client['last_name'] ?? ''}'.trim();
    final dt = DateTime.tryParse(call['scheduled_at'] as String? ?? '')?.toLocal();
    final type = (call['call_type'] as String? ?? 'check_in').replaceAll('_', ' ');
    final mins = call['duration_minutes'] ?? 30;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    final h = dt == null ? '' : (dt.hour % 12 == 0 ? 12 : dt.hour % 12);
    final ap = dt == null ? '' : (dt.hour < 12 ? 'AM' : 'PM');
    final when = dt == null ? '' : '${dt.month}/${dt.day} · $h:${dt.minute.toString().padLeft(2, '0')} $ap';
    final who = name.isEmpty ? 'this client' : name;
    final large = _largeText(context);
    // UX-6 · a 44x44 target; while the cancel is in flight a spinner
    // that says so takes its place (no double fire).
    final action = cancelling
        ? Semantics(
            container: true,
            label: 'Cancelling',
            liveRegion: true,
            child: const SizedBox(width: 44, height: 44,
              child: Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFFFB4AB))))))
        // P0-FL-58 · named for the session it cancels.
        : Semantics(
            container: true,
            button: true,
            label: 'Cancel session with $who${when.isEmpty ? '' : ', $when'}',
            onTap: onCancel,
            excludeSemantics: true,
            child: TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 44)),
              child: const Text('Cancel',
                style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 13, fontWeight: FontWeight.w600)),
            ));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF160E26), _card]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brand.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        CircleAvatar(radius: 18, backgroundColor: _brand.withValues(alpha: 0.18),
          child: Text(initial, style: const TextStyle(color: _tert, fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isEmpty ? 'Client' : name,
            style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('$when · $type · $mins min',
            style: const TextStyle(color: _mut, fontSize: 12)),
          if (large) ...[const SizedBox(height: 4), action],
        ])),
        if (!large) action,
      ]),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final Map<String, dynamic> slot;
  final VoidCallback onDelete;
  final bool deleting;
  /// The date heading it is under: part of the delete button's name.
  final String day;
  const _SlotTile({required this.slot, required this.day, required this.onDelete, this.deleting = false});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.parse(slot['slot_time'] as String).toLocal();
    final isBooked = slot['is_booked'] == true;
    final type = slot['type'] as String? ?? 'check_in';
    final mins = slot['duration_minutes'] as int? ?? 30;
    final time = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    final large = _largeText(context);
    // P0-FL-58 · 52px at least: the fixed box cut the time off at large text.
    final timeBox = Container(
      constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: (isBooked ? _tert : _brand).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12)),
      child: Center(widthFactor: 1, heightFactor: 1, child: Text(time,
        style: TextStyle(color: isBooked ? _tert : _brand, fontSize: 14, fontWeight: FontWeight.w800))));
    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_typeLabel(type),
        style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w600)),
      Text('$mins min${isBooked ? ' • Booked' : ' • Available'}',
        style: TextStyle(color: isBooked ? _tert : _mut, fontSize: 12)),
    ]);
    final slotName = '${_typeLabel(type)} slot, $day $time';
    final Widget action = isBooked
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _tert.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Text('Booked', style: TextStyle(color: _tert, fontSize: 11, fontWeight: FontWeight.w600)))
        // Every card's button was announced "Remove slot": which one was not
        // said, nor that a removal was in flight.
        : Semantics(
            container: true,
            button: true,
            enabled: !deleting,
            liveRegion: deleting,
            label: deleting ? 'Deleting $slotName' : 'Delete $slotName',
            onTap: deleting ? null : onDelete,
            excludeSemantics: true,
            child: IconButton(
              tooltip: 'Remove slot',
              icon: deleting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _mut))
                  : const Icon(Icons.delete_outline_rounded, color: _mut, size: 20),
              onPressed: deleting ? null : onDelete));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isBooked ? _tert.withValues(alpha: 0.4) : _brd),
      ),
      // Past 1.3× the pieces go under one another.
      child: large
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              timeBox, const SizedBox(height: 8), details, const SizedBox(height: 8), action])
          : Row(children: [
              timeBox, const SizedBox(width: 14), Expanded(child: details), action]),
    );
  }

  String _typeLabel(String t) => switch (t) {
    'check_in'        => 'Weekly Check-In',
    'consultation'    => 'Strategy Consultation',
    'nutrition_review'=> 'Nutrition Review',
    _                 => 'Coaching Call',
  };
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(color: _brand.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.calendar_month_rounded, color: _brand, size: 36)),
        const SizedBox(height: 16),
        const Text('No availability published', style: TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Add time slots so your clients can book coaching calls with you.',
          style: TextStyle(color: _mut, fontSize: 14, height: 1.5), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add First Slot'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _brand, foregroundColor: _wht,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      ]),
    ),
  );
}

// ── Add Slot Bottom Sheet ─────────────────────────────────────────────────────
class _AddSlotSheet extends StatefulWidget {
  final VoidCallback onSaved;
  const _AddSlotSheet({required this.onSaved});
  @override
  State<_AddSlotSheet> createState() => _AddSlotSheetState();
}

class _AddSlotSheetState extends State<_AddSlotSheet> {
  final _db = Supabase.instance.client;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  int _hour = 9;
  int _minute = 0;
  String _type = 'check_in';
  int _duration = 30;
  bool _saving = false;
  /// The last publish's failure, said above the button (P0-FL-53b r2).
  String? _error;

  static const _types = [
    ('check_in',         'Weekly Check-In'),
    ('consultation',     'Strategy Consultation'),
    ('nutrition_review', 'Nutrition Review'),
  ];
  static const _hours = [7,8,9,10,11,12,13,14,15,16,17,18,19,20];
  static const _minutes = [0, 15, 30, 45];
  static const _durations = [30, 45, 60];

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final uid = _db.auth.currentUser?.id;
      final slotTime = DateTime(_date.year, _date.month, _date.day, _hour, _minute);
      await _db.from('coach_availability').insert({
        'coach_id': uid,
        'slot_time': slotTime.toUtc().toIso8601String(),
        'duration_minutes': _duration,
        'type': _type,
        'is_booked': false,
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e, st) {
      // ERR-2: see coach_video_response_screen. P0-FL-53b · recorded (it was
      // swallowed unseen), and said in the one voice.
      reportError('CoachAvailabilityScreen._AddSlotSheet._save', e, st);
      // Said inside the sheet: a SnackBar would sit on the Scaffold under it.
      if (mounted) setState(() => _error = couldntMessage('save this time slot', e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _brand, surface: _card)),
        child: child!),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

    // P0-FL-53b r3 · the body scrolls: with the failure line (r2), large
    // text or a short phone, Publish Slot stays reachable instead of being
    // pushed off screen.
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Add Availability Slot',
            style: TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton(tooltip: 'Close Add Availability Slot',
            icon: const Icon(Icons.close, color: _mut), onPressed: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 20),

        // Date
        const Text('Date', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          button: true,
          label: 'Change date, ${days[_date.weekday - 1]}, ${_date.day} ${months[_date.month - 1]} ${_date.year}',
          onTap: _pickDate,
          excludeSemantics: true,
          child: GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _brd)),
            child: Row(children: [
              const Icon(Icons.calendar_today_rounded, color: _brand, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text('${days[_date.weekday - 1]}, ${_date.day} ${months[_date.month - 1]} ${_date.year}',
                style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w600))),
              const Icon(Icons.chevron_right_rounded, color: _mut, size: 18),
            ]),
          ),
        )),
        const SizedBox(height: 16),

        // Time
        const Text('Time', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _DropdownField<int>(
            label: 'Hour',
            value: _hour,
            items: _hours.map((h) => DropdownMenuItem(value: h,
              child: Text('${h.toString().padLeft(2,'0')}h', style: const TextStyle(color: _wht)))).toList(),
            onChanged: (v) => setState(() => _hour = v!),
          )),
          const SizedBox(width: 10),
          Expanded(child: _DropdownField<int>(
            label: 'Minute',
            value: _minute,
            items: _minutes.map((m) => DropdownMenuItem(value: m,
              child: Text(':${m.toString().padLeft(2,'0')}', style: const TextStyle(color: _wht)))).toList(),
            onChanged: (v) => setState(() => _minute = v!),
          )),
        ]),
        const SizedBox(height: 16),

        // Type
        const Text('Type', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: _types.map(((String, String) t) => _ChoiceTarget(
          label: 'Type: ${t.$2}',
          selected: _type == t.$1,
          onTap: () => setState(() => _type = t.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _type == t.$1 ? _brand : _bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _type == t.$1 ? _brand : _brd)),
            child: Text(t.$2, style: TextStyle(
              color: _type == t.$1 ? _wht : _mut, fontSize: 12, fontWeight: FontWeight.w600))),
        )).toList()),
        const SizedBox(height: 16),

        // Duration
        const Text('Duration', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: _durations.map((d) => _ChoiceTarget(
            label: 'Duration: $d min',
            selected: _duration == d,
            onTap: () => setState(() => _duration = d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _duration == d ? _tert.withValues(alpha: 0.15) : _bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _duration == d ? _tert : _brd)),
              child: Text('$d min', style: TextStyle(
                color: _duration == d ? _tert : _mut, fontSize: 13, fontWeight: FontWeight.w600))),
        )).toList()),
        const SizedBox(height: 24),

        if (_error != null) ...[
          Semantics(liveRegion: true, child: Text(_error!,
              style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 13, height: 1.35))),
          const SizedBox(height: 12),
        ],
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _brand, foregroundColor: _wht,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: _wht, strokeWidth: 2))
              : const Text('Publish Slot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        )),
        const SizedBox(height: 8),
      ]),
    );
  }
}

/// A chip that is one of a set of choices: it keeps its look in a >= 44px
/// target that says what it chooses and whether it is the current choice.
class _ChoiceTarget extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  const _ChoiceTarget({required this.label, required this.selected,
    required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    inMutuallyExclusiveGroup: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Center(widthFactor: 1, heightFactor: 1, child: child))));
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _DropdownField({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _brd)),
    child: Semantics(
      label: label,
      child: DropdownButton<T>(
      value: value, items: items, onChanged: onChanged,
      itemHeight: null, // 48px at least, and grows with large text
      dropdownColor: _card, isExpanded: true, underline: const SizedBox(),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _mut))),
  );
}

/// P0-FL-14 · a failed load stated with a way to read it again. Scrolls so
/// large text never overflows; a live region so a screen reader hears it.
class _LoadFailed extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LoadFailed({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, color: _mut, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center,
            style: const TextStyle(color: _wht, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          // A retry swaps this view for the spinner, so it cannot fire twice.
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: _brand, side: const BorderSide(color: _brand)),
            child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w700))),
        ]),
      ),
    ),
  );
}
