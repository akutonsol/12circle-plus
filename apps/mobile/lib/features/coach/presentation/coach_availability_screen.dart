import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _bg    = Color(0xFF030303);
const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _tert  = Color(0xFF6FFBBE);
const _wht   = Colors.white;
const _mut   = Color(0xFFCFC2D6);

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

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _db.auth.currentUser?.id;
      final data = await _db
          .from('coach_availability')
          .select()
          .eq('coach_id', uid!)
          .gte('slot_time', DateTime.now().toIso8601String())
          .order('slot_time');

      // Upcoming booked sessions, with the client who booked.
      final calls = await _db
          .from('coaching_calls')
          .select('id, scheduled_at, duration_minutes, call_type, status, '
              'availability_slot_id, client_id, '
              'client:client_id(first_name, last_name, avatar_url)')
          .eq('coach_id', uid)
          .eq('status', 'scheduled')
          .gte('scheduled_at', DateTime.now().toIso8601String())
          .order('scheduled_at');

      if (!mounted) return;
      setState(() {
        _slots = List<Map<String, dynamic>>.from(data);
        _sessions = List<Map<String, dynamic>>.from(calls);
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _delete(String id) async {
    await _db.from('coach_availability').delete().eq('id', id);
    _load();
  }

  Future<void> _cancelSession(Map<String, dynamic> call) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: _card,
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
    try {
      await _db.from('coaching_calls').update({'status': 'cancelled'}).eq('id', call['id']);
      if (call['availability_slot_id'] != null) {
        await _db.from('coach_availability')
            .update({'is_booked': false}).eq('id', call['availability_slot_id']);
      }
      await _db.from('notifications').insert({
        'recipient_id': call['client_id'],
        'type': 'session_cancelled',
        'title': 'Session cancelled',
        'body': 'Your coach had to cancel a scheduled session. You can rebook any time.',
        'read': false,
      });
      messenger.showSnackBar(const SnackBar(content: Text('Session cancelled — client notified.')));
      _load();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not cancel. Try again.')));
    }
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
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: _tert, size: 24),
            onPressed: _showAddSheet),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : ListView(
              padding: const EdgeInsets.all(16),
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
                    ...entry.value.map((s) => _SlotTile(slot: s, onDelete: () => _delete(s['id'] as String))),
                  ]);
                }),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        backgroundColor: _brand,
        icon: const Icon(Icons.add, color: _wht),
        label: const Text('Add Slot', style: TextStyle(color: _wht, fontWeight: FontWeight.w700)),
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
  const _SessionTile({required this.call, required this.onCancel});

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
        ])),
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: const Text('Cancel',
            style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final Map<String, dynamic> slot;
  final VoidCallback onDelete;
  const _SlotTile({required this.slot, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.parse(slot['slot_time'] as String).toLocal();
    final isBooked = slot['is_booked'] == true;
    final type = slot['type'] as String? ?? 'check_in';
    final mins = slot['duration_minutes'] as int? ?? 30;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isBooked ? _tert.withValues(alpha: 0.4) : _brd),
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: (isBooked ? _tert : _brand).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}',
              style: TextStyle(color: isBooked ? _tert : _brand, fontSize: 14, fontWeight: FontWeight.w800)),
          ])),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_typeLabel(type),
            style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w600)),
          Text('$mins min${isBooked ? ' • Booked' : ' • Available'}',
            style: TextStyle(color: isBooked ? _tert : _mut, fontSize: 12)),
        ])),
        if (!isBooked)
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: _mut, size: 20),
            onPressed: onDelete)
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _tert.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Text('Booked', style: TextStyle(color: _tert, fontSize: 11, fontWeight: FontWeight.w600))),
      ]),
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

  static const _types = [
    ('check_in',         'Weekly Check-In'),
    ('consultation',     'Strategy Consultation'),
    ('nutrition_review', 'Nutrition Review'),
  ];
  static const _hours = [7,8,9,10,11,12,13,14,15,16,17,18,19,20];
  static const _minutes = [0, 15, 30, 45];
  static const _durations = [30, 45, 60];

  Future<void> _save() async {
    setState(() => _saving = true);
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
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        // ERR-2: see coach_video_response_screen.
        const SnackBar(content: Text('Failed to save availability. Try again.'),
            backgroundColor: Colors.red));
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

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Add Availability Slot',
            style: TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton(icon: const Icon(Icons.close, color: _mut), onPressed: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 20),

        // Date
        const Text('Date', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _brd)),
            child: Row(children: [
              const Icon(Icons.calendar_today_rounded, color: _brand, size: 18),
              const SizedBox(width: 10),
              Text('${days[_date.weekday - 1]}, ${_date.day} ${months[_date.month - 1]} ${_date.year}',
                style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded, color: _mut, size: 18),
            ]),
          ),
        ),
        const SizedBox(height: 16),

        // Time
        const Text('Time', style: TextStyle(color: _mut, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _DropdownField<int>(
            value: _hour,
            items: _hours.map((h) => DropdownMenuItem(value: h,
              child: Text('${h.toString().padLeft(2,'0')}h', style: const TextStyle(color: _wht)))).toList(),
            onChanged: (v) => setState(() => _hour = v!),
          )),
          const SizedBox(width: 10),
          Expanded(child: _DropdownField<int>(
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
        Wrap(spacing: 8, children: _types.map(((String, String) t) => GestureDetector(
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
        Row(children: _durations.map((d) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
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
          ),
        )).toList()),
        const SizedBox(height: 24),

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

class _DropdownField<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _DropdownField({required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _brd)),
    child: DropdownButton<T>(
      value: value, items: items, onChanged: onChanged,
      dropdownColor: _card, isExpanded: true, underline: const SizedBox(),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _mut)),
  );
}
