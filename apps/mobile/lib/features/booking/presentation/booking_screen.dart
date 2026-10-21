import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../scoring/data/score_engine.dart';

const _bg    = Color(0xFF030303);
const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _pri   = Color(0xFFDDB7FF);
const _tert  = Color(0xFF6FFBBE);
const _wht   = Colors.white;
const _mut   = Color(0xFFCFC2D6);

// ── State ─────────────────────────────────────────────────────────────────────
enum _BookingState { loading, noCoach, pending, noSlots, ready, booked, error }

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key});
  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  final _db = Supabase.instance.client;

  _BookingState _state = _BookingState.loading;
  String?  _coachId;
  String?  _coachName;
  String?  _coachAvatar;
  String?  _coachTitle;
  String?  _coachBio;
  String?  _coachSpecialties;
  String?  _pendingAt;
  // All coaches the client has an ACTIVE relationship with (request accepted).
  List<Map<String, dynamic>> _coaches = [];
  List<Map<String, dynamic>> _slots    = [];
  List<Map<String, dynamic>> _booked   = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _BookingState.loading);
    final uid = _db.auth.currentUser?.id;
    if (uid == null) { setState(() => _state = _BookingState.noCoach); return; }

    try {
      // UIX-1 / M-03. This query used to embed the coach profile as
      // `coach:coach_id(...)`. `coach_client_relationships.coach_id` is a
      // foreign key to `auth.users` (000_baseline_preexisting_tables.sql:237),
      // not to any relation in the `public` schema, so PostgREST answered
      // PGRST200 "no matches were found" and the whole screen was dead for
      // every client. PD-A23 option (b), owner ruling 2026-08-28: drop the
      // embed and read the profiles in a second query against
      // `public_profiles` — the pattern coach_relationship_service.dart
      // already uses. No migration.
      final rels = await _db
          .from('coach_client_relationships')
          .select('coach_id, status, pending_at, activated_at')
          .eq('client_id', uid)
          // Most recently activated first → default matches the "assigned coach"
          // shown on the home screen (assignedCoachProvider uses activated_at).
          .order('activated_at', ascending: false, nullsFirst: false);
      final list = List<Map<String, dynamic>>.from(rels as List);

      // Second query. `public_profiles` (migration 110) is the sanctioned
      // non-sensitive projection and carries every field this screen renders.
      final coachIds = list
          .map((r) => r['coach_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final profileMap = <String, Map<String, dynamic>>{};
      if (coachIds.isNotEmpty) {
        final profiles = await _db
            .from('public_profiles')
            .select('id, first_name, last_name, avatar_url, '
                'coach_title, coach_bio, specialties')
            .inFilter('id', coachIds);
        for (final row in (profiles as List)) {
          final m = Map<String, dynamic>.from(row as Map);
          final id = m['id'] as String?;
          if (id != null) profileMap[id] = m;
        }
      }

      Map<String, dynamic> coachOf(Map<String, dynamic> r) {
        final c = profileMap[r['coach_id']] ?? const <String, dynamic>{};
        final fn = c['first_name'] as String? ?? '';
        final ln = c['last_name'] as String? ?? '';
        return {
          'id': r['coach_id'],
          'name': 'Coach ${('$fn $ln').trim()}',
          'avatar': c['avatar_url'],
          'title': c['coach_title'],
          'bio': c['coach_bio'],
          // `user_profiles.specialties` is `text[]` (001:42), and this screen
          // renders it as a comma-separated string it splits itself. The embed
          // never returned, so the old `as String?` cast was never exercised;
          // it would throw now that the read works. Normalise at the join.
          'specialties': _specialtiesLabel(c['specialties']),
          'pending_at': r['pending_at'],
        };
      }

      final active = list.where((r) => r['status'] == 'active').toList();
      if (active.isEmpty) {
        // No accepted coach yet — surface a pending request if there is one.
        final pending = list.where((r) => r['status'] == 'pending').toList();
        if (pending.isNotEmpty) {
          final c = coachOf(pending.first);
          _coachName        = c['name'] as String?;
          _coachAvatar      = c['avatar'] as String?;
          _coachTitle       = c['title'] as String?;
          _coachBio         = c['bio'] as String?;
          _coachSpecialties = c['specialties'] as String?;
          _pendingAt        = c['pending_at'] as String?;
          if (!mounted) return;
          setState(() => _state = _BookingState.pending);
          return;
        }
        if (!mounted) return;
        setState(() => _state = _BookingState.noCoach);
        return;
      }

      _coaches = active.map(coachOf).toList();
      // Keep the current selection if it's still active, else pick the first.
      final selId = _coaches.any((c) => c['id'] == _coachId)
          ? _coachId! : _coaches.first['id'] as String;
      await _applyCoach(selId);
    } catch (_) {
      // UIX-1 / invariants I-1 and I-5: the authoritative data could not be
      // obtained, so the screen must not present the confident "no slots"
      // answer. An empty value is an answer; this is not one.
      if (!mounted) return;
      setState(() {
        _slots  = [];
        _booked = [];
        _state  = _BookingState.error;
      });
    }
  }

  /// `specialties` is `text[]` in the schema and a comma-separated string in
  /// this screen's widgets. One place converts.
  static String? _specialtiesLabel(Object? raw) {
    if (raw == null) return null;
    if (raw is String) return raw.trim().isEmpty ? null : raw;
    if (raw is List) {
      final parts = raw
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      return parts.isEmpty ? null : parts.join(', ');
    }
    return null;
  }

  /// Loads the chosen coach's open slots + the client's booked calls with them.
  Future<void> _applyCoach(String coachId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    final c = _coaches.firstWhere((x) => x['id'] == coachId,
        orElse: () => _coaches.first);
    _coachId          = coachId;
    _coachName        = c['name'] as String?;
    _coachAvatar      = c['avatar'] as String?;
    _coachTitle       = c['title'] as String?;
    _coachBio         = c['bio'] as String?;
    _coachSpecialties = c['specialties'] as String?;

    final now         = DateTime.now();
    final twoWeeksOut = now.add(const Duration(days: 14));
    final slotsData = await _db
        .from('coach_availability').select()
        .eq('coach_id', coachId).eq('is_booked', false)
        .gte('slot_time', now.toIso8601String())
        .lt('slot_time', twoWeeksOut.toIso8601String())
        .order('slot_time');
    final bookedData = await _db
        .from('coaching_calls').select()
        .eq('client_id', uid).eq('coach_id', coachId).eq('status', 'scheduled')
        .gte('scheduled_at', now.toIso8601String())
        .order('scheduled_at');
    if (!mounted) return;
    setState(() {
      _slots  = List<Map<String, dynamic>>.from(slotsData as List);
      _booked = List<Map<String, dynamic>>.from(bookedData as List);
      _state  = _slots.isEmpty ? _BookingState.noSlots : _BookingState.ready;
    });
  }

  void _selectCoach(String coachId) {
    if (coachId == _coachId) return;
    setState(() => _state = _BookingState.loading);
    _applyCoach(coachId);
  }

  Future<void> _cancelBooking(Map<String, dynamic> call) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Cancel session?', style: TextStyle(color: _wht, fontWeight: FontWeight.w800)),
        content: const Text('Your coach will be notified and the time slot reopened.',
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
      if (_coachId != null) {
        await _db.from('notifications').insert({
          'recipient_id': _coachId,
          'type': 'session_cancelled',
          'title': 'Session cancelled',
          'body': 'A client cancelled their scheduled session.',
          'read': false,
        });
      }
      messenger.showSnackBar(const SnackBar(content: Text('Session cancelled.')));
      _load();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not cancel. Try again.')));
    }
  }

  Future<void> _book(Map<String, dynamic> slot) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || _coachId == null) return;
    try {
      await _db.from('coaching_calls').insert({
        'client_id'          : uid,
        'coach_id'           : _coachId,
        'availability_slot_id': slot['id'],
        'scheduled_at'       : slot['slot_time'],
        'duration_minutes'   : slot['duration_minutes'] ?? 30,
        'call_type'          : slot['type'] ?? 'check_in',
        'status'             : 'scheduled',
      });
      await _db.from('coach_availability')
          .update({'is_booked': true}).eq('id', slot['id']);

      // Notify the coach about the new booking.
      final me = await _db.from('user_profiles')
          .select('first_name, last_name').eq('id', uid).maybeSingle();
      final clientName = '${me?['first_name'] ?? ''} ${me?['last_name'] ?? ''}'.trim();
      await _db.from('notifications').insert({
        'recipient_id': _coachId,
        'type'        : 'session_booked',
        'title'       : 'New session booked',
        'body'        : '${clientName.isEmpty ? 'A client' : clientName} booked a '
            '${(slot['type'] ?? 'check_in').toString().replaceAll('_', ' ')} session.',
        'data'        : {'client_id': uid},
        'read'        : false,
      });

      ScoreEngine().bookSession('${slot['id']}'); // +15
      if (!mounted) return;
      _showSnack('Call booked! Your coach has been notified.', _tert);
      _load();
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not book — please try again.', Colors.redAccent);
    }
  }

  void _showSnack(String msg, Color color) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: _wht)),
        backgroundColor: color, behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _wht, size: 20),
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: const Text('Book a Call',
          style: TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          if (_state != _BookingState.loading && _state != _BookingState.noCoach)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: _mut, size: 20),
              onPressed: _load),
        ]),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final content = switch (_state) {
      _BookingState.loading  => const Center(child: CircularProgressIndicator(color: _brand)),
      _BookingState.noCoach  => _NoCoachState(),
      _BookingState.pending  => _PendingCoachState(
        coachName:    _coachName    ?? 'Your Coach',
        coachAvatar:  _coachAvatar,
        coachTitle:   _coachTitle,
        coachBio:     _coachBio,
        specialties:  _coachSpecialties,
        pendingAt:    _pendingAt,
        onRefresh:    _load,
      ),
      _BookingState.noSlots  => _NoSlotsState(coachName: _coachName),
      _BookingState.error    => _LoadFailedState(onRetry: _load),
      _BookingState.ready || _BookingState.booked => _ReadyState(
        coachName: _coachName ?? 'Your Coach',
        coachAvatar: _coachAvatar,
        slots: _slots,
        booked: _booked,
        onBook: _book,
        onCancel: _cancelBooking,
      ),
    };

    // When the client has multiple accepted coaches, let them switch between
    // them to book a call with whichever one they want.
    final showPicker = _coaches.length > 1 &&
        (_state == _BookingState.ready ||
         _state == _BookingState.noSlots ||
         _state == _BookingState.booked ||
         _state == _BookingState.loading);
    if (showPicker) {
      return Column(children: [
        _coachSelector(),
        Expanded(child: content),
      ]);
    }
    return content;
  }

  Widget _coachSelector() => Container(
    height: 96,
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      color: _card, border: Border(bottom: BorderSide(color: _brd))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Text('YOUR COACHES', style: TextStyle(color: _mut, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1)),
      ),
      Expanded(child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _coaches.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = _coaches[i];
          final selected = c['id'] == _coachId;
          final avatar = c['avatar'] as String?;
          return GestureDetector(
            onTap: () => _selectCoach(c['id'] as String),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? _brand.withValues(alpha: 0.18) : const Color(0xFF08050F),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: selected ? _brand : _brd)),
              child: Row(children: [
                CircleAvatar(
                  radius: 14, backgroundColor: const Color(0xFF2A1A4E),
                  backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                  child: (avatar == null || avatar.isEmpty)
                      ? const Icon(Icons.person, color: _pri, size: 16) : null),
                const SizedBox(width: 8),
                Text((c['name'] as String? ?? 'Coach').replaceFirst('Coach ', ''),
                    style: TextStyle(color: selected ? _wht : _mut,
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
              ]),
            ),
          );
        },
      )),
    ]),
  );
}

// ── No Coach ─────────────────────────────────────────────────────────────────
class _NoCoachState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: 0.1),
            shape: BoxShape.circle),
          child: const Icon(Icons.person_search_rounded, color: _brand, size: 36)),
        const SizedBox(height: 20),
        const Text('No Coach Selected Yet',
          style: TextStyle(color: _wht, fontSize: 20, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center),
        const SizedBox(height: 10),
        const Text(
          'To book a coaching call you need to first select\n'
          'a coach and wait for them to accept your request.',
          style: TextStyle(color: _mut, fontSize: 14, height: 1.55),
          textAlign: TextAlign.center),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: () => context.push('/coach-marketplace'),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text('Browse Coaches', style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _brand, foregroundColor: _wht,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      ]),
    ),
  );
}

// ── Pending Coach ─────────────────────────────────────────────────────────────
class _PendingCoachState extends StatelessWidget {
  final String  coachName;
  final String? coachAvatar;
  final String? coachTitle;
  final String? coachBio;
  final String? specialties;
  final String? pendingAt;
  final VoidCallback onRefresh;

  const _PendingCoachState({
    required this.coachName,
    this.coachAvatar,
    this.coachTitle,
    this.coachBio,
    this.specialties,
    this.pendingAt,
    required this.onRefresh,
  });

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final sentDate = _formatDate(pendingAt);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        const SizedBox(height: 16),

        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD060).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFFFD060).withValues(alpha: 0.4))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.hourglass_top_rounded,
              color: Color(0xFFFFD060), size: 14),
            const SizedBox(width: 6),
            const Text('Request Pending',
              style: TextStyle(color: Color(0xFFFFD060),
                fontSize: 12, fontWeight: FontWeight.w700)),
          ])),
        const SizedBox(height: 24),

        // Coach avatar
        CircleAvatar(
          radius: 44,
          backgroundColor: _brd,
          backgroundImage: coachAvatar != null ? NetworkImage(coachAvatar!) : null,
          child: coachAvatar == null
              ? Text(coachName.isNotEmpty ? coachName[0] : 'C',
                  style: const TextStyle(color: _pri, fontSize: 28,
                    fontWeight: FontWeight.w700))
              : null),
        const SizedBox(height: 16),

        // Coach name
        Text(coachName,
          style: const TextStyle(color: _wht, fontSize: 22,
            fontWeight: FontWeight.w800),
          textAlign: TextAlign.center),

        if (coachTitle != null && coachTitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(coachTitle!,
            style: const TextStyle(color: _pri, fontSize: 14),
            textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),

        // Status message card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD060).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFD060).withValues(alpha: 0.25))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.schedule_rounded,
                color: Color(0xFFFFD060), size: 16),
              const SizedBox(width: 8),
              const Text('Awaiting Acceptance',
                style: TextStyle(color: Color(0xFFFFD060),
                  fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(
              '$coachName has received your coaching request'
              '${sentDate.isNotEmpty ? ' sent on $sentDate' : ''}. '
              'Once they accept, you will be able to book sessions and '
              'access your personalised coaching plan.',
              style: const TextStyle(color: _mut, fontSize: 13, height: 1.5)),
          ])),
        const SizedBox(height: 16),

        // Coach details card
        if ((coachBio != null && coachBio!.isNotEmpty) ||
            (specialties != null && specialties!.isNotEmpty))
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _brd)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('About Your Coach',
                style: TextStyle(color: _mut, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1)),
              if (coachBio != null && coachBio!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(coachBio!,
                  style: const TextStyle(color: _wht, fontSize: 13, height: 1.5)),
              ],
              if (specialties != null && specialties!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Specialties',
                  style: TextStyle(color: _mut, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 1)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6,
                  children: specialties!.split(',').map((s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _brand.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _brand.withValues(alpha: 0.3))),
                    child: Text(s.trim(),
                      style: const TextStyle(color: _pri, fontSize: 11,
                        fontWeight: FontWeight.w600)))).toList()),
              ],
            ])),
        const SizedBox(height: 24),

        // Refresh / check status
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Check Status'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _pri,
              side: BorderSide(color: _pri.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))))),
        const SizedBox(height: 12),

        // Browse other coaches
        TextButton(
          onPressed: () => context.push('/coach-marketplace'),
          style: TextButton.styleFrom(foregroundColor: _mut),
          child: const Text('Browse other coaches',
            style: TextStyle(fontSize: 13,
              decoration: TextDecoration.underline))),
      ]),
    );
  }
}

// ── Load failed ───────────────────────────────────────────────────────────────
//
// UIX-1 / M-03. Distinct from `_NoSlotsState` on purpose: "no slots" is an
// answer about the coach's availability, and this is the absence of an answer.
// Collapsing the two is the false-success condition Workstream M recorded.
class _LoadFailedState extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadFailedState({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.cloud_off_rounded, color: _brand, size: 36)),
        const SizedBox(height: 20),
        const Text("Couldn't load your bookings",
          style: TextStyle(color: _wht, fontSize: 20, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center),
        const SizedBox(height: 10),
        const Text(
          'We could not reach your coach and availability data just now. '
          'This is a connection problem, not an empty schedule.',
          style: TextStyle(color: _mut, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, color: _pri, size: 18),
          label: const Text('Try again',
            style: TextStyle(color: _pri, fontSize: 14, fontWeight: FontWeight.w600))),
      ])));
}

// ── No Slots ──────────────────────────────────────────────────────────────────
class _NoSlotsState extends StatelessWidget {
  final String? coachName;
  const _NoSlotsState({this.coachName});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: _tert.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.event_busy_rounded, color: _tert, size: 36)),
        const SizedBox(height: 20),
        Text(coachName != null ? 'No Slots from $coachName' : 'No Slots Available',
          style: const TextStyle(color: _wht, fontSize: 20, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(
          coachName != null
            ? '$coachName hasn\'t published any availability yet. '
              'They will notify you when slots open up.'
            : 'No availability slots are published yet.\n'
              'Check back soon or message your coach.',
          style: const TextStyle(color: _mut, fontSize: 14, height: 1.55),
          textAlign: TextAlign.center),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: () => context.push('/messages'),
          icon: const Icon(Icons.message_outlined, size: 18),
          label: const Text('Message Coach'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _pri,
            side: BorderSide(color: _pri.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      ]),
    ),
  );
}

// ── Ready State ───────────────────────────────────────────────────────────────
class _ReadyState extends StatelessWidget {
  final String coachName;
  final String? coachAvatar;
  final List<Map<String, dynamic>> slots;
  final List<Map<String, dynamic>> booked;
  final Future<void> Function(Map<String, dynamic>) onBook;
  final Future<void> Function(Map<String, dynamic>) onCancel;

  const _ReadyState({
    required this.coachName, this.coachAvatar,
    required this.slots, required this.booked, required this.onBook,
    required this.onCancel});

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      // Coach header
      SliverToBoxAdapter(child: _CoachHeader(name: coachName, avatarUrl: coachAvatar)),

      // Upcoming booked calls
      if (booked.isNotEmpty) ...[
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, color: _tert, size: 16),
            const SizedBox(width: 6),
            const Text('Your Upcoming Calls',
              style: TextStyle(color: _tert, fontSize: 14, fontWeight: FontWeight.w700)),
          ]))),
        SliverList(delegate: SliverChildBuilderDelegate(
          (_, i) => _BookedCard(call: booked[i], onCancel: () => onCancel(booked[i])),
          childCount: booked.length)),
        SliverToBoxAdapter(child: const Divider(color: Color(0xFF1A1020), height: 32)),
      ],

      // Available slots
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Available Slots',
            style: TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700)),
          Text('${slots.length} open',
            style: const TextStyle(color: _mut, fontSize: 12)),
        ]))),

      SliverList(delegate: SliverChildBuilderDelegate(
        (_, i) => _SlotCard(slot: slots[i], onBook: () => onBook(slots[i])),
        childCount: slots.length)),

      const SliverToBoxAdapter(child: SizedBox(height: 40)),
    ],
  );
}

// ── Coach Header ──────────────────────────────────────────────────────────────
class _CoachHeader extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  const _CoachHeader({required this.name, this.avatarUrl});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _brand.withValues(alpha: 0.25))),
    child: Row(children: [
      CircleAvatar(
        radius: 24,
        backgroundColor: _brand.withValues(alpha: 0.15),
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
        child: avatarUrl == null
            ? const Icon(Icons.person_rounded, color: _brand, size: 24)
            : null),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name,
          style: const TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700)),
        const Text('Your assigned coach',
          style: TextStyle(color: _mut, fontSize: 12)),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _tert.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8)),
        child: const Text('Active', style: TextStyle(color: _tert, fontSize: 11,
          fontWeight: FontWeight.w600))),
    ]),
  );
}

// ── Booked Call Card ──────────────────────────────────────────────────────────
class _BookedCard extends StatelessWidget {
  final Map<String, dynamic> call;
  final VoidCallback onCancel;
  const _BookedCard({required this.call, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final dt   = DateTime.tryParse(call['scheduled_at'] as String? ?? '')?.toLocal()
        ?? DateTime.now();
    final type = call['call_type'] as String? ?? 'check_in';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _tert.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _tert.withValues(alpha: 0.25))),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: _tert.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.video_call_rounded, color: _tert, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_typeLabel(type),
            style: const TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w600)),
          Text('${_dayLabel(dt)} · ${_timeLabel(dt)}',
            style: const TextStyle(color: _mut, fontSize: 12)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _tert.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8)),
            child: const Text('Confirmed',
              style: TextStyle(color: _tert, fontSize: 11, fontWeight: FontWeight.w600))),
          GestureDetector(
            onTap: onCancel,
            child: const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Cancel',
                style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 12, fontWeight: FontWeight.w600)))),
        ]),
      ]),
    );
  }

  String _typeLabel(String t) => switch (t) {
    'check_in'         => 'Weekly Check-In',
    'consultation'     => 'Strategy Consultation',
    'nutrition_review' => 'Nutrition Review',
    _                  => 'Coaching Call',
  };
  String _dayLabel(DateTime dt) {
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }
  String _timeLabel(DateTime dt) =>
    '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
}

// ── Slot Card ─────────────────────────────────────────────────────────────────
class _SlotCard extends StatefulWidget {
  final Map<String, dynamic> slot;
  final Future<void> Function() onBook;
  const _SlotCard({required this.slot, required this.onBook});
  @override
  State<_SlotCard> createState() => _SlotCardState();
}

class _SlotCardState extends State<_SlotCard> {
  bool _booking = false;

  @override
  Widget build(BuildContext context) {
    final dt   = DateTime.tryParse(widget.slot['slot_time'] as String? ?? '')?.toLocal()
        ?? DateTime.now();
    final type = widget.slot['type'] as String? ?? 'check_in';
    final mins = widget.slot['duration_minutes'] as int? ?? 30;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brd)),
      child: Row(children: [
        _DateBadge(dt: dt),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_typeLabel(type),
            style: const TextStyle(color: _wht, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('$mins minutes · Video call',
            style: const TextStyle(color: _mut, fontSize: 12)),
        ])),
        _booking
            ? const SizedBox(width: 60, child: Center(
                child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: _brand, strokeWidth: 2))))
            : ElevatedButton(
                onPressed: () async {
                  setState(() => _booking = true);
                  await widget.onBook();
                  if (mounted) setState(() => _booking = false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brand, foregroundColor: _wht,
                  // The app's ElevatedButton theme is the full-width CTA style
                  // (helix_theme_builder.dart:44 — minimumSize
                  // Size(double.infinity, 54)), and an unset property here
                  // falls through to it. In a bounded column that infinite
                  // minWidth clamps harmlessly to the parent's maxWidth; as a
                  // non-flex child of this Row it does not, because RenderFlex
                  // lays inflexible children out with an unbounded main axis —
                  // so the button is asked for BoxConstraints(minWidth:
                  // Infinity) and layout throws "BoxConstraints forces an
                  // infinite width." Overriding only the width component keeps
                  // the themed 54px height and the intended hug-content width,
                  // matching the design system's own non-full-width idiom
                  // (helix_theme_builder.dart:76).
                  minimumSize: const Size(0, 54),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Book', style: TextStyle(fontWeight: FontWeight.w700))),
      ]),
    );
  }

  String _typeLabel(String t) => switch (t) {
    'check_in'         => 'Weekly Check-In',
    'consultation'     => 'Strategy Call',
    'nutrition_review' => 'Nutrition Review',
    _                  => 'Coaching Call',
  };
}

class _DateBadge extends StatelessWidget {
  final DateTime dt;
  const _DateBadge({required this.dt});
  static const _days   = ['MON','TUE','WED','THU','FRI','SAT','SUN'];
  static const _months = ['Jan','Feb','Mar','Apr','May','Jun',
                          'Jul','Aug','Sep','Oct','Nov','Dec'];
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: _brand.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Text(_days[dt.weekday - 1],
        style: const TextStyle(color: _mut, fontSize: 10, fontWeight: FontWeight.w700)),
      Text('${dt.day}',
        style: const TextStyle(color: _wht, fontSize: 22, fontWeight: FontWeight.w800)),
      Text('${_months[dt.month - 1]}',
        style: const TextStyle(color: _brand, fontSize: 10, fontWeight: FontWeight.w600)),
      Text('${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}',
        style: const TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );
}
