import 'package:supabase_flutter/supabase_flutter.dart';

class CoachNote {
  final String id;
  final String clientId;
  final String body;
  final String tag; // injury | motivation | adherence | program | general
  final DateTime createdAt;

  const CoachNote({
    required this.id,
    required this.clientId,
    required this.body,
    required this.tag,
    required this.createdAt,
  });

  static const tagEmoji = {
    'injury': '🩹',
    'motivation': '🔥',
    'adherence': '📊',
    'program': '🏋️',
    'general': '📝',
  };
  String get emoji => tagEmoji[tag] ?? '📝';

  factory CoachNote.fromMap(Map<String, dynamic> m) => CoachNote(
        id: m['id'] as String,
        clientId: m['client_id'] as String,
        body: m['body'] as String? ?? '',
        tag: m['tag'] as String? ?? 'general',
        createdAt:
            DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// Private coach notes about a client (Module 29). RLS makes these visible
/// only to the authoring coach — never the client.
class CoachNoteService {
  final _db = Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  /// Throws on a failed read: the sheet has a "Could not load notes" state,
  /// and an empty list read as "No notes yet" for a client who has them.
  Future<List<CoachNote>> getNotes(String clientId) async {
    final data = await _db
        .from('coach_notes')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((m) => CoachNote.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<bool> addNote(String clientId, String body, {String tag = 'general'}) async {
    final coachId = _uid;
    if (coachId == null || body.trim().isEmpty) return false;
    try {
      await _db.from('coach_notes').insert({
        'coach_id': coachId,
        'client_id': clientId,
        'body': body.trim(),
        'tag': tag,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteNote(String id) async {
    final coachId = _uid;
    if (coachId == null) return;
    await _db.from('coach_notes').delete().eq('id', id).eq('coach_id', coachId);
  }
}
