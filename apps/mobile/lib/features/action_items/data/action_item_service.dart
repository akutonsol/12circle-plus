import 'dart:async' show unawaited;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import 'models/action_item.dart';
import '../../scoring/data/score_engine.dart';

/// Client Action Items — the coach-driven task system.
/// Notifications (assigned → client, completed → coach) are handled by DB
/// triggers in migration 017, so this service only owns the data operations.
class ActionItemService {
  final _db = Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  /// Client: their assigned items, newest/most-urgent first.
  ///
  /// Throws on a failed read: /action-items states "Could not load your action
  /// items", and the `[]` this returned instead read as "No action items yet /
  /// Your coach will assign tasks here." to a client with tasks waiting.
  Future<List<ActionItem>> getMyActionItems() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final data = await _db
          .from('action_items')
          .select()
          .eq('client_id', uid)
          .order('status') // pending before completed
          .order('due_date', ascending: true, nullsFirst: false)
          .order('created_at', ascending: false);
      return (data as List)
          .map((m) => ActionItem.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      reportError('ActionItemService.getMyActionItems', e);
      rethrow;
    }
  }

  /// Coach: items assigned to a specific client.
  ///
  /// Throws on a failed read (P0-FL-63d): the `[]` this returned read as "no
  /// action items" for that client, and [completionStats] as "0 of 0 assigned".
  Future<List<ActionItem>> getClientActionItems(String clientId) async {
    try {
      final data = await _db
          .from('action_items')
          .select()
          .eq('client_id', clientId)
          .order('created_at', ascending: false);
      return (data as List)
          .map((m) => ActionItem.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      reportError('ActionItemService.getClientActionItems', e, st);
      rethrow;
    }
  }

  /// Coach: assign a new action item to a client (ACT-001).
  Future<bool> assignActionItem({
    required String clientId,
    required String title,
    String description = '',
    String category = 'daily',
    int points = 10,
    DateTime? dueDate,
  }) async {
    final coachId = _uid;
    if (coachId == null) return false;
    try {
      // RM-2 (C15-63d-03) · the row is asked back: an insert RLS filtered to
      // nothing answers like a saved one, and the coach was told it was sent.
      final rows = await _db.from('action_items').insert({
        'client_id': clientId,
        'coach_id': coachId,
        'title': title,
        'description': description,
        'category': category,
        'points': points,
        'created_by': 'coach',
        'status': 'pending',
        'due_date': dueDate?.toIso8601String().split('T').first,
      }).select('id');
      if (rows.isEmpty) {
        reportError('ActionItemService.assignActionItem',
            StateError('action_items insert changed 0 rows'));
        return false;
      }
      return true;
    } catch (e, st) {
      // Recorded once here; the sheet says it without the exception text.
      reportError('ActionItemService.assignActionItem', e, st);
      return false;
    }
  }

  /// Client: mark an item complete, optionally with proof + notes (ACT-002).
  /// The coach notification fires from the DB trigger.
  Future<bool> completeActionItem(
    String id, {
    String? proofUrl,
    String? notes,
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      // P0-FL-59e · a 0-row update (not this member's item, or already gone)
      // answers like a saved one unless the row is asked back.
      final rows = await _db.from('action_items').update({
        'status': 'completed',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        if (proofUrl != null) 'proof_url': proofUrl,
        if (notes != null) 'client_notes': notes,
      }).eq('id', id).eq('client_id', uid).select('id');
      if (rows.isEmpty) {
        reportError('ActionItemService.completeActionItem',
            StateError('action_items update changed 0 rows'));
        return false;
      }
    } catch (e, st) {
      reportError('ActionItemService.completeActionItem', e, st);
      return false;
    }
    // +10 (automatic, once per item), for the member who completed it.
    unawaited(ScoreEngine(forUid: uid).actionItemComplete(id));
    return true;
  }

  /// Client: reopen a completed item. True only when a row was changed.
  Future<bool> reopen(String id) async {
    final uid = _uid;
    if (uid == null) return false;
    final rows = await _db.from('action_items').update({
      'status': 'pending',
      'completed_at': null,
    }).eq('id', id).eq('client_id', uid).select('id');
    if (rows.isNotEmpty) return true;
    reportError('ActionItemService.reopen',
        StateError('action_items update changed 0 rows'));
    return false;
  }

  /// Coach: completion stats for the dashboard view (assigned / completed / %).
  Future<({int assigned, int completed, double rate})> completionStats(
      String clientId) async {
    final items = await getClientActionItems(clientId);
    final assigned = items.length;
    final completed = items.where((i) => i.isCompleted).length;
    final rate = assigned == 0 ? 0.0 : completed / assigned;
    return (assigned: assigned, completed: completed, rate: rate);
  }
}
