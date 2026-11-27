import 'package:supabase_flutter/supabase_flutter.dart';

/// Module 14 — Speaker / Session Management.
/// Sessions form an event's agenda. Public-read; only the owning vendor writes
/// (enforced by RLS in migration 021).
///
/// P0-FL-62a2 · every write asks for the row back and throws when none came:
/// RLS filters an update or delete it refuses SILENTLY (no error, 0 rows), and
/// the agenda used to carry on as if the session had been saved or deleted.
/// The keys are written out at the call site, not passed through as a map, so
/// the schema contract guard can see every column.
class SessionService {
  final _db = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getSessions(String eventId) async {
    final data = await _db
        .from('event_sessions')
        .select()
        .eq('event_id', eventId)
        .order('sort_order')
        .order('starts_at', ascending: true, nullsFirst: false);
    return List<Map<String, dynamic>>.from(data);
  }

  /// [data] is the editor sheet's answer.
  Future<void> addSession(String eventId, Map<String, dynamic> data) async {
    final added = await _db.from('event_sessions').insert({
      'event_id': eventId,
      'title': data['title'],
      'description': data['description'],
      'speaker_name': data['speaker_name'],
      'speaker_title': data['speaker_title'],
      'track': data['track'],
      'starts_at': data['starts_at'],
      'ends_at': data['ends_at'],
    }).select('id');
    _changedOne(added, 'addSession');
  }

  /// Throws when no row changed (refused, or gone).
  Future<void> updateSession(String sessionId, Map<String, dynamic> data) async {
    final changed = await _db.from('event_sessions').update({
      'title': data['title'],
      'description': data['description'],
      'speaker_name': data['speaker_name'],
      'speaker_title': data['speaker_title'],
      'track': data['track'],
      'starts_at': data['starts_at'],
      'ends_at': data['ends_at'],
    }).eq('id', sessionId).select('id');
    _changedOne(changed, 'updateSession');
  }

  /// Throws when no row was deleted (refused, or already gone).
  Future<void> deleteSession(String sessionId) async {
    final deleted = await _db
        .from('event_sessions')
        .delete()
        .eq('id', sessionId)
        .select('id');
    _changedOne(deleted, 'deleteSession');
  }

  static void _changedOne(List<dynamic> rows, String what) {
    if (rows.isEmpty) throw StateError('$what: no row was changed');
  }
}
