import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/vendor_provider.dart';

const _bg     = Color(0xFF030303);
const _card   = Color(0xFF0E0B16);
const _border = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _lilac  = Color(0xFFDDB7FF);

String _fmtTime(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
}

/// Module 14 — an event's agenda. [canManage] is true for the owning vendor
/// (add/edit/delete sessions); false renders a read-only schedule for clients.
class EventAgendaScreen extends ConsumerWidget {
  final Map<String, dynamic> event;
  final bool canManage;
  const EventAgendaScreen(
      {super.key, required this.event, this.canManage = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventId = event['id'] as String;
    final sessionsAsync = ref.watch(eventSessionsProvider(eventId));

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Agenda',
                style: TextStyle(
                    color: _white, fontSize: 18, fontWeight: FontWeight.w700)),
            Text(event['title'] as String? ?? '',
                style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              backgroundColor: _brand,
              icon: const Icon(Icons.add, color: _white),
              label: const Text('Add Session',
                  style: TextStyle(color: _white)),
              onPressed: () => _editSession(context, ref, eventId),
            )
          : null,
      body: sessionsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _brand)),
        error: (e, _) => Center(
            child: Text('Could not load agenda.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted))),
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  canManage
                      ? 'No sessions yet.\nTap “Add Session” to build the agenda.'
                      : 'The agenda for this event hasn’t been published yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, height: 1.4),
                ),
              ),
            );
          }
          return RefreshIndicator(
            color: _brand,
            backgroundColor: _card,
            onRefresh: () async =>
                ref.invalidate(eventSessionsProvider(eventId)),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: sessions.length,
              itemBuilder: (_, i) => _SessionCard(
                session: sessions[i],
                canManage: canManage,
                onEdit: () => _editSession(context, ref, eventId,
                    existing: sessions[i]),
                onDelete: () async {
                  await ref
                      .read(sessionServiceProvider)
                      .deleteSession(sessions[i]['id'] as String);
                  ref.invalidate(eventSessionsProvider(eventId));
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _editSession(BuildContext context, WidgetRef ref, String eventId,
      {Map<String, dynamic>? existing}) async {
    final eventDate =
        DateTime.tryParse(event['event_date'] as String? ?? '') ??
            DateTime.now();
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SessionEditorSheet(existing: existing, day: eventDate),
    );
    if (result == null) return;
    final svc = ref.read(sessionServiceProvider);
    if (existing == null) {
      await svc.addSession(eventId, result);
    } else {
      await svc.updateSession(existing['id'] as String, result);
    }
    ref.invalidate(eventSessionsProvider(eventId));
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _SessionCard({
    required this.session,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final start = _fmtTime(session['starts_at'] as String?);
    final end = _fmtTime(session['ends_at'] as String?);
    final timeText = start.isEmpty
        ? ''
        : (end.isEmpty ? start : '$start – $end');
    final speaker = session['speaker_name'] as String?;
    final track = session['track'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF160E26), _card]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Time rail
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: _brand,
                borderRadius:
                    BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (timeText.isNotEmpty) ...[
                          const Icon(Icons.schedule, size: 14, color: _lilac),
                          const SizedBox(width: 6),
                          Text(timeText,
                              style: const TextStyle(
                                  color: _lilac,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ],
                        const Spacer(),
                        if (canManage)
                          PopupMenuButton<String>(
                            color: _card,
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.more_horiz,
                                color: _muted, size: 20),
                            onSelected: (v) =>
                                v == 'edit' ? onEdit() : onDelete(),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit',
                                      style: TextStyle(color: _white))),
                              PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete',
                                      style: TextStyle(
                                          color: Color(0xFFFFB4AB)))),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(session['title'] as String? ?? 'Session',
                        style: const TextStyle(
                            color: _white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    if ((session['description'] as String?)?.isNotEmpty ??
                        false) ...[
                      const SizedBox(height: 4),
                      Text(session['description'] as String,
                          style: const TextStyle(
                              color: _muted, fontSize: 13, height: 1.4)),
                    ],
                    if (speaker != null && speaker.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: _brand.withValues(alpha: 0.18),
                            backgroundImage:
                                (session['speaker_avatar_url'] as String?)
                                            ?.isNotEmpty ==
                                        true
                                    ? NetworkImage(
                                        session['speaker_avatar_url'] as String)
                                    : null,
                            child: (session['speaker_avatar_url'] as String?)
                                        ?.isNotEmpty ==
                                    true
                                ? null
                                : Text(speaker[0].toUpperCase(),
                                    style: const TextStyle(
                                        color: _lilac,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(speaker,
                                    style: const TextStyle(
                                        color: _white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                if ((session['speaker_title'] as String?)
                                        ?.isNotEmpty ??
                                    false)
                                  Text(session['speaker_title'] as String,
                                      style: const TextStyle(
                                          color: _muted, fontSize: 11)),
                              ],
                            ),
                          ),
                          if (track != null && track.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _brand.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(track,
                                  style: const TextStyle(
                                      color: _lilac,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Session editor sheet ─────────────────────────────────────────────────────
class _SessionEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final DateTime day;
  const _SessionEditorSheet({this.existing, required this.day});
  @override
  State<_SessionEditorSheet> createState() => _SessionEditorSheetState();
}

class _SessionEditorSheetState extends State<_SessionEditorSheet> {
  late TextEditingController _title;
  late TextEditingController _desc;
  late TextEditingController _speaker;
  late TextEditingController _speakerTitle;
  late TextEditingController _track;
  TimeOfDay? _start;
  TimeOfDay? _end;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?['title'] as String? ?? '');
    _desc = TextEditingController(text: e?['description'] as String? ?? '');
    _speaker = TextEditingController(text: e?['speaker_name'] as String? ?? '');
    _speakerTitle =
        TextEditingController(text: e?['speaker_title'] as String? ?? '');
    _track = TextEditingController(text: e?['track'] as String? ?? '');
    final s = DateTime.tryParse(e?['starts_at'] as String? ?? '');
    final en = DateTime.tryParse(e?['ends_at'] as String? ?? '');
    if (s != null) _start = TimeOfDay.fromDateTime(s);
    if (en != null) _end = TimeOfDay.fromDateTime(en);
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _speaker.dispose();
    _speakerTitle.dispose();
    _track.dispose();
    super.dispose();
  }

  String? _combine(TimeOfDay? t) {
    if (t == null) return null;
    final d = widget.day;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute)
        .toIso8601String();
  }

  Future<void> _pick(bool isStart) async {
    final t = await showTimePicker(
        context: context,
        initialTime:
            (isStart ? _start : _end) ?? const TimeOfDay(hour: 9, minute: 0));
    if (t == null) return;
    if (!mounted) return;
    setState(() => isStart ? _start = t : _end = t);
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
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: _border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(widget.existing == null ? 'New Session' : 'Edit Session',
                  style: const TextStyle(
                      color: _white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              _field('Session title', _title, hint: 'e.g. Opening Keynote'),
              _field('Description', _desc, hint: 'What is it about?', maxLines: 2),
              Row(children: [
                Expanded(child: _timeBtn('Starts', _start, () => _pick(true))),
                const SizedBox(width: 12),
                Expanded(child: _timeBtn('Ends', _end, () => _pick(false))),
              ]),
              const SizedBox(height: 12),
              _field('Speaker name', _speaker, hint: 'e.g. Dr. Jane Doe'),
              _field('Speaker title', _speakerTitle,
                  hint: 'e.g. Sports Nutritionist'),
              _field('Track / room (optional)', _track, hint: 'e.g. Main Stage'),
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
                      'speaker_name': _speaker.text.trim(),
                      'speaker_title': _speakerTitle.text.trim(),
                      'track': _track.text.trim(),
                      'starts_at': _combine(_start),
                      'ends_at': _combine(_end),
                    });
                  },
                  child: Text(
                      widget.existing == null
                          ? 'Add session'
                          : 'Save changes',
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

  Widget _timeBtn(String label, TimeOfDay? t, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Row(children: [
              const Icon(Icons.schedule, color: _brand, size: 16),
              const SizedBox(width: 8),
              Text(t == null ? 'Set time' : t.format(context),
                  style: TextStyle(
                      color: t == null ? _muted : _white, fontSize: 13)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

Widget _field(String label, TextEditingController c,
    {String? hint, int maxLines = 1}) {
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
