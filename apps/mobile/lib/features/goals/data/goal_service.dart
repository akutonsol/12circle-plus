import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import 'models/goal.dart';

class GoalService {
  final _db = Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  /// Throws on a failed read: /goals states "Could not load goals", and the
  /// `[]` this returned instead read as "No goals yet" to a client who had set
  /// them.
  Future<List<Goal>> getMyGoals() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final data = await _db
          .from('goals')
          .select()
          .eq('client_id', uid)
          .order('status')
          .order('created_at', ascending: false);
      return (data as List)
          .map((m) => Goal.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      reportError('GoalService.getMyGoals', e);
      rethrow;
    }
  }

  /// Creates the goal for [owner], the account the form was opened for. Throws
  /// when it was not saved (P0-FL-60c): recorded, and nothing is sent once
  /// another account — or nobody — is signed in, so a goal one member typed is
  /// never another member's.
  Future<bool> createGoal({
    required String? owner,
    required String title,
    required String type,
    double? startValue,
    double? targetValue,
    String unit = '',
    DateTime? targetDate,
  }) async {
    try {
      if (owner == null || _uid != owner) {
        throw StateError('creating a goal: the signed-in account changed');
      }
      await _db.from('goals').insert({
        'client_id': owner,
        'title': title,
        'type': type,
        'start_value': startValue,
        'current_value': startValue,
        'target_value': targetValue,
        'unit': unit,
        'target_date': targetDate?.toIso8601String().split('T').first,
        'status': 'active',
      });
      return true;
    } catch (e, st) {
      reportError('GoalService.createGoal', e, st);
      rethrow;
    }
  }

  /// Throws when the progress was not saved, and records it (P0-FL-60c): an
  /// update that changed no row (the goal is gone, or is not this account's)
  /// used to be reported as saved.
  Future<bool> updateProgress(String id, double currentValue) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      _mustChange(
          await _db
              .from('goals')
              .update({'current_value': currentValue})
              .eq('id', id)
              .eq('client_id', uid)
              .select('id'),
          'updated');
      return true;
    } catch (e, st) {
      reportError('GoalService.updateProgress', e, st);
      rethrow;
    }
  }

  /// No error is raised for a write that matched no row.
  static void _mustChange(List<dynamic> rows, String what) {
    if (rows.isEmpty) throw StateError('the goal was not $what: no row matched');
  }

  Future<void> complete(String id) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in — the goal was not updated.');
    _mustChange(
        await _db.from('goals').update({
          'status': 'completed',
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id).eq('client_id', uid).select('id'),
        'updated');
  }

  Future<void> deleteGoal(String id) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in — the goal was not deleted.');
    _mustChange(
        await _db
            .from('goals')
            .delete()
            .eq('id', id)
            .eq('client_id', uid)
            .select('id'),
        'deleted');
  }
}
