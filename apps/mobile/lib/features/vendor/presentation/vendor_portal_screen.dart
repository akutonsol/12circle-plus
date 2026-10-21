import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/vendor_provider.dart';
import 'event_agenda_screen.dart';

const _bg     = Color(0xFF030303);
const _card   = Color(0xFF0E0B16);
const _border = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _mint   = Color(0xFF6FFBBE);
const _amber  = Color(0xFFFFD479);

String _fmtDate(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return '—';
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${months[d.month - 1]} ${d.day} · $h:${d.minute.toString().padLeft(2, '0')} $ap';
}

// ════════════════════════════════════════════════════════════════════════════
// Vendor Portal — a vendor's events + attendees (Module 15)
// ════════════════════════════════════════════════════════════════════════════
class VendorPortalScreen extends ConsumerWidget {
  const VendorPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(myEventsProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text('Vendor Portal',
            style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: _muted),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _brand,
        icon: const Icon(Icons.add, color: _white),
        label: const Text('New Event', style: TextStyle(color: _white)),
        onPressed: () => _openEventEditor(context, ref),
      ),
      body: eventsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _brand)),
        error: (e, _) => Center(
            child: Text('Could not load events.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted))),
        data: (events) {
          if (events.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No events yet.\nTap “New Event” to create your first one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.4),
                ),
              ),
            );
          }
          return RefreshIndicator(
            color: _brand,
            backgroundColor: _card,
            onRefresh: () async => ref.invalidate(myEventsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: events.length,
              itemBuilder: (_, i) => _EventCard(event: events[i]),
            ),
          );
        },
      ),
    );
  }

}

Future<void> _openEventEditor(BuildContext context, WidgetRef ref,
    {Map<String, dynamic>? existing}) async {
  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _EventEditorSheet(existing: existing),
  );
  if (result == null) return;
  final svc = ref.read(vendorServiceProvider);
  if (existing == null) {
    await svc.createEvent(result);
  } else {
    await svc.updateEvent(existing['id'] as String, result);
  }
  ref.invalidate(myEventsProvider);
}

class _EventCard extends ConsumerWidget {
  final Map<String, dynamic> event;
  const _EventCard({required this.event});

  int get _regCount {
    final r = event['event_registrations'];
    if (r is List && r.isNotEmpty && r.first is Map) {
      return (r.first['count'] as int?) ?? 0;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = (event['max_capacity'] as int?);
    final isFree = event['is_free'] as bool? ?? true;
    final price = (event['price'] as num?)?.toDouble() ?? 0;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => EventAttendeesScreen(event: event))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF160E26), _card]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(event['title'] ?? 'Untitled event',
                      style: const TextStyle(
                          color: _white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
                PopupMenuButton<String>(
                  color: _card,
                  icon: const Icon(Icons.more_horiz, color: _muted),
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await _openEventEditor(context, ref, existing: event);
                    } else if (v == 'agenda') {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => EventAgendaScreen(
                                  event: event, canManage: true)));
                    } else if (v == 'delete') {
                      await ref
                          .read(vendorServiceProvider)
                          .deleteEvent(event['id'] as String);
                      ref.invalidate(myEventsProvider);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit', style: TextStyle(color: _white))),
                    PopupMenuItem(
                        value: 'agenda',
                        child: Text('Manage Agenda',
                            style: TextStyle(color: _white))),
                    PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete',
                            style: TextStyle(color: Color(0xFFFFB4AB)))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.event, size: 14, color: _muted),
              const SizedBox(width: 6),
              Text(_fmtDate(event['event_date'] as String?),
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ]),
            if (event['location'] != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.place_outlined, size: 14, color: _muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${event['location']}',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                ),
              ]),
            ],
            const SizedBox(height: 12),
            Row(children: [
              _pill(Icons.people_alt_rounded,
                  cap == null ? '$_regCount registered' : '$_regCount / $cap', _brand),
              const SizedBox(width: 8),
              _pill(isFree ? Icons.celebration_rounded : Icons.sell_rounded,
                  isFree ? 'Free' : '\$${price.toStringAsFixed(0)}',
                  isFree ? _mint : _amber),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

// ── Attendees screen ─────────────────────────────────────────────────────────
class EventAttendeesScreen extends ConsumerWidget {
  final Map<String, dynamic> event;
  const EventAttendeesScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventId = event['id'] as String;
    final regsAsync = ref.watch(eventRegistrationsProvider(eventId));

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        title: Text(event['title'] ?? 'Attendees',
            style: const TextStyle(color: _white, fontWeight: FontWeight.w700)),
      ),
      body: regsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _brand)),
        error: (e, _) => Center(
            child: Text('Could not load attendees.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted))),
        data: (regs) {
          final checkedIn =
              regs.where((r) => r['checked_in_at'] != null).length;
          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF160E26), _card]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Registered', '${regs.length}', _brand),
                    _stat('Checked In', '$checkedIn', _mint),
                    _stat('Pending', '${regs.length - checkedIn}', _amber),
                  ],
                ),
              ),
              Expanded(
                child: regs.isEmpty
                    ? const Center(
                        child: Text('No registrations yet.',
                            style: TextStyle(color: _muted)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: regs.length,
                        itemBuilder: (_, i) => _AttendeeRow(
                          reg: regs[i],
                          onToggle: (checked) async {
                            await ref
                                .read(vendorServiceProvider)
                                .setCheckedIn(regs[i]['id'] as String, checked);
                            ref.invalidate(eventRegistrationsProvider(eventId));
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      );
}

class _AttendeeRow extends StatelessWidget {
  final Map<String, dynamic> reg;
  final ValueChanged<bool> onToggle;
  const _AttendeeRow({required this.reg, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final profile = reg['user_profiles'] as Map<String, dynamic>?;
    final name = profile == null
        ? 'Attendee'
        : '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
    final checkedIn = reg['checked_in_at'] != null;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: checkedIn ? _mint.withValues(alpha: 0.4) : _border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _brand.withValues(alpha: 0.18),
            child: Text(initial,
                style: const TextStyle(
                    color: _brand, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'Attendee' : name,
                    style: const TextStyle(
                        color: _white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(profile?['email'] as String? ?? '',
                    style: const TextStyle(color: _muted, fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onToggle(!checkedIn),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: checkedIn
                    ? _mint.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: checkedIn ? _mint : _border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(checkedIn ? Icons.check_circle : Icons.circle_outlined,
                    size: 16, color: checkedIn ? _mint : _muted),
                const SizedBox(width: 6),
                Text(checkedIn ? 'In' : 'Check in',
                    style: TextStyle(
                        color: checkedIn ? _mint : _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Event editor sheet (create / edit) ───────────────────────────────────────
class _EventEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _EventEditorSheet({this.existing});
  @override
  State<_EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends State<_EventEditorSheet> {
  late TextEditingController _title;
  late TextEditingController _desc;
  late TextEditingController _location;
  late TextEditingController _capacity;
  late TextEditingController _price;
  late DateTime _date;
  bool _isFree = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?['title'] as String? ?? '');
    _desc = TextEditingController(text: e?['description'] as String? ?? '');
    _location = TextEditingController(text: e?['location'] as String? ?? '');
    _capacity =
        TextEditingController(text: e?['max_capacity']?.toString() ?? '');
    _price = TextEditingController(
        text: ((e?['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
    _date = DateTime.tryParse(e?['event_date'] as String? ?? '') ??
        DateTime.now().add(const Duration(days: 7));
    _isFree = e?['is_free'] as bool? ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _location.dispose();
    _capacity.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d == null) return;
    if (!mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (!mounted) return;
    setState(() {
      _date = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _border)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: _border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(widget.existing == null ? 'New Event' : 'Edit Event',
                  style: const TextStyle(
                      color: _white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              _field('Title', _title, hint: 'e.g. Saturday Bootcamp'),
              _field('Description', _desc, hint: 'What is it about?', maxLines: 2),
              _field('Location', _location, hint: 'Venue / address'),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.event, color: _brand, size: 18),
                    const SizedBox(width: 10),
                    Text(_fmtDate(_date.toIso8601String()),
                        style: const TextStyle(color: _white)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _field('Capacity (optional)', _capacity,
                  keyboard: TextInputType.number, hint: 'Max attendees'),
              Row(children: [
                const Text('Free event',
                    style: TextStyle(color: _muted, fontSize: 13)),
                const Spacer(),
                Switch(
                  value: _isFree,
                  activeThumbColor: _brand,
                  onChanged: (v) => setState(() => _isFree = v),
                ),
              ]),
              if (!_isFree)
                _field('Price (\$)', _price, keyboard: TextInputType.number),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (_title.text.trim().isEmpty) return;
                    Navigator.pop(context, {
                      'title': _title.text.trim(),
                      'description': _desc.text.trim(),
                      'location': _location.text.trim(),
                      'event_date': _date.toIso8601String(),
                      'max_capacity': int.tryParse(_capacity.text.trim()),
                      'is_free': _isFree,
                      'price': _isFree
                          ? 0
                          : (double.tryParse(_price.text.trim()) ?? 0),
                      'status': 'upcoming',
                    });
                  },
                  child: Text(
                      widget.existing == null ? 'Create event' : 'Save changes',
                      style: const TextStyle(
                          color: _white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _field(String label, TextEditingController c,
    {String? hint, int maxLines = 1, TextInputType? keyboard}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          maxLines: maxLines,
          keyboardType: keyboard,
          style: const TextStyle(color: _white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF6B6478)),
            isDense: true,
            filled: true,
            fillColor: _bg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _brand),
            ),
          ),
        ),
      ],
    ),
  );
}
