import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/goal.dart';

class GoalService {
  final _db = Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

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
    } catch (_) {
      return [];
    }
  }

  Future<bool> createGoal({
    required String title,
    required String type,
    double? startValue,
    double? targetValue,
    String unit = '',
    DateTime? targetDate,
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _db.from('goals').insert({
        'client_id': uid,
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
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateProgress(String id, double currentValue) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _db
          .from('goals')
          .update({'current_value': currentValue})
          .eq('id', id)
          .eq('client_id', uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> complete(String id) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in — the goal was not updated.');
    await _db.from('goals').update({
      'status': 'completed',
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('id', id).eq('client_id', uid);
  }

  Future<void> deleteGoal(String id) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in — the goal was not deleted.');
    await _db.from('goals').delete().eq('id', id).eq('client_id', uid);
  }
}
