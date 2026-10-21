import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'coach_triage.dart';
import '../../auth/domain/auth_provider.dart';

/// FIT-032 · assembling `ClientSignals` from the sources a coach may read.
///
/// `coach_triage.dart` holds the rules and explains which sources are
/// authorized and why `workout_logs` is not one of them. This file is only the
/// reads.
///
/// ── TWO DISCIPLINES THIS FILE IS HELD TO ───────────────────────────────────
/// **Errors propagate.** Not one `catch { return []; }`. F-15 is the record of
/// what that costs on this exact screen: a failed read reached the coach as
/// "no clients", "no check-ins", "no workouts" — their whole roster, gone. A
/// throw here becomes an `AsyncError` the surface can state.
///
/// **No `workout_logs`.** SEC-G3 forbids it and `QA_EVIDENCE §3ah` explains
/// why: RLS denies a coach's read and PostgREST answers `200` with `[]`, so an
/// `At risk` row built on it would fire for every client, always.
///
/// ── AND ONE THING IT CANNOT PROVE ──────────────────────────────────────────
/// The `Assign` signal reads `workout_program_assignments`, one of SEC-G2's
/// four two-party tables. The rows can be read; their **authenticity** is what
/// F-21/OD-14 leaves open. Same standing as `/workout-detail`: the surface may
/// be built, and it must not claim the assignment behind it is genuine.
final _db = Supabase.instance.client;

/// The signed-in coach's active client ids.
Future<List<String>> _activeClientIds() async {
  final coachId = _db.auth.currentUser?.id;
  if (coachId == null) return const [];
  final rels = await _db
      .from('coach_client_relationships')
      .select('client_id')
      .eq('coach_id', coachId)
      .eq('status', 'active');
  return (rels as List).map((r) => r['client_id'] as String).toList();
}

int? _wholeDaysSince(String? iso) {
  if (iso == null) return null;
  final at = DateTime.tryParse(iso);
  if (at == null) return null;
  final now = DateTime.now();
  final a = DateTime(at.toLocal().year, at.toLocal().month, at.toLocal().day);
  final b = DateTime(now.year, now.month, now.day);
  return b.difference(a).inDays;
}

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

/// Trims a client's own words to something that fits one row without changing
/// them. Cut at a word boundary, with an ellipsis, never mid-word.
String? excerpt(String? text, {int max = 48}) {
  final t = text?.trim();
  if (t == null || t.isEmpty) return null;
  final flat = t.replaceAll(RegExp(r'\s+'), ' ');
  if (flat.length <= max) return flat;
  final cut = flat.substring(0, max);
  final space = cut.lastIndexOf(' ');
  return '${(space > max ~/ 2 ? cut.substring(0, space) : cut).trimRight()}…';
}

final coachTriageSignalsProvider =
    FutureProvider<List<ClientSignals>>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  final coachId = _db.auth.currentUser?.id;
  if (coachId == null) return const [];

  final ids = await _activeClientIds();
  // No clients is a real answer and stays distinguishable from a failed read.
  if (ids.isEmpty) return const [];

  final names = <String, String>{};
  for (final p in (await _db
          .from('user_profiles')
          .select('id, first_name, last_name')
          .inFilter('id', ids)) as List) {
    final n = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    if (n.isNotEmpty) names[p['id'] as String] = n;
  }

  // ── Review · weekly_checkins (114: owner or is_active_coach_of) ──────────
  final week = <String, int>{};
  final note = <String, String?>{};
  for (final c in (await _db
          .from('weekly_checkins')
          .select('user_id, week_number, notes, submitted_at, reviewed_at')
          .inFilter('user_id', ids)
          .not('submitted_at', 'is', null)
          .isFilter('reviewed_at', null)
          .order('submitted_at', ascending: false)) as List) {
    final uid = c['user_id'] as String;
    // Newest first, so the first one seen per client is the one to show.
    if (week.containsKey(uid)) continue;
    week[uid] = (c['week_number'] as num?)?.toInt() ?? 0;
    note[uid] = excerpt(c['notes'] as String?);
  }

  // ── At risk · workout_sessions (100: owner or is_active_coach_of) ────────
  final lastSession = <String, int>{};
  for (final s in (await _db
          .from('workout_sessions')
          .select('user_id, started_at')
          .inFilter('user_id', ids)
          .eq('status', 'completed')
          .order('started_at', ascending: false)) as List) {
    final uid = s['user_id'] as String;
    if (lastSession.containsKey(uid)) continue;
    final d = _wholeDaysSince(s['started_at'] as String?);
    if (d != null) lastSession[uid] = d;
  }

  // ── Reply · the coach's own threads (participant-scoped) ─────────────────
  final asked = <String, String?>{};
  final convos = await _db
      .from('conversations')
      .select('id, participant_1, participant_2')
      .or('participant_1.eq.$coachId,participant_2.eq.$coachId');
  final otherParty = <String, String>{};
  for (final c in convos as List) {
    final p1 = c['participant_1'] as String?;
    final p2 = c['participant_2'] as String?;
    final other = p1 == coachId ? p2 : p1;
    if (other != null && ids.contains(other)) {
      otherParty[c['id'] as String] = other;
    }
  }
  if (otherParty.isNotEmpty) {
    for (final m in (await _db
            .from('messages')
            .select('conversation_id, sender_id, content, is_read, sent_at')
            .inFilter('conversation_id', otherParty.keys.toList())
            .eq('is_read', false)
            .order('sent_at', ascending: false)) as List) {
      final uid = otherParty[m['conversation_id'] as String];
      // Only the CLIENT's unread messages are a reason to reply. The coach's
      // own unread-by-the-client messages are not.
      if (uid == null || m['sender_id'] != uid) continue;
      if (asked.containsKey(uid)) continue;
      asked[uid] = excerpt(m['content'] as String?);
    }
  }

  // ── Assign · assignments + the programme's own duration ──────────────────
  // BLOCKED-BY-F21 for integrity claims. See the file header.
  final until = <String, int>{};
  final endsOn = <String, String>{};
  final hasNext = <String>{};
  final assignments = await _db
      .from('workout_program_assignments')
      .select('client_id, program_id, start_date, status')
      .inFilter('client_id', ids)
      .eq('status', 'active');
  final programIds = (assignments as List)
      .map((a) => a['program_id'])
      .whereType<String>()
      .toSet()
      .toList();
  final durations = <String, int>{};
  if (programIds.isNotEmpty) {
    for (final p in (await _db
            .from('workout_programs')
            .select('id, plan')
            .inFilter('id', programIds)) as List) {
      final weeks = (p['plan'] as Map?)?['duration_weeks'];
      final n = weeks is num ? weeks.toInt() : int.tryParse('$weeks');
      if (n != null && n > 0) durations[p['id'] as String] = n;
    }
  }
  for (final a in assignments) {
    final uid = a['client_id'] as String?;
    final pid = a['program_id'] as String?;
    if (uid == null || pid == null) continue;
    final weeks = durations[pid];
    final start = DateTime.tryParse('${a['start_date']}');
    // No duration means no end date. The row is not produced rather than
    // guessed — a coach told to assign a block that has not ended is noise.
    if (weeks == null || start == null) continue;
    final end = start.add(Duration(days: weeks * 7));
    final now = DateTime.now();
    final days = DateTime(end.year, end.month, end.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    // More than one active assignment for a client means a successor exists.
    if (until.containsKey(uid)) {
      hasNext.add(uid);
      if (days <= until[uid]!) continue;
    }
    until[uid] = days;
    endsOn[uid] = _weekdays[end.weekday - 1];
  }

  return [
    for (final id in ids)
      ClientSignals(
        clientId: id,
        clientName: names[id],
        unrepliedCheckinWeek: week[id],
        unrepliedCheckinNote: note[id],
        daysSinceLastSession: lastSession[id],
        daysUntilBlockEnds: until[id],
        blockEndsOn: endsOn[id],
        hasNextBlock: hasNext.contains(id),
        unansweredMessage: asked[id],
      ),
  ];
});
