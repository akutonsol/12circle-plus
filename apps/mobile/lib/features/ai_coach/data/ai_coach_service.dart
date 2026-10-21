import 'package:supabase_flutter/supabase_flutter.dart';

enum AICoachMode { nutrition, workout, general, checkinAnalysis, riskDetection }

extension AICoachModeExt on AICoachMode {
  String get value => switch (this) {
    AICoachMode.nutrition => 'nutrition',
    AICoachMode.workout => 'workout',
    AICoachMode.general => 'general',
    AICoachMode.checkinAnalysis => 'checkin_analysis',
    AICoachMode.riskDetection => 'risk_detection',
  };
  String get label => switch (this) {
    AICoachMode.nutrition => 'Nutrition',
    AICoachMode.workout => 'Workout',
    AICoachMode.general => 'General',
    AICoachMode.checkinAnalysis => 'Check-In Analysis',
    AICoachMode.riskDetection => 'Risk Detection',
  };
  String get emoji => switch (this) {
    AICoachMode.nutrition => '🥗',
    AICoachMode.workout => '💪',
    AICoachMode.general => '🤖',
    AICoachMode.checkinAnalysis => '📊',
    AICoachMode.riskDetection => '⚠️',
  };
}

class AICoachService {
  final _db = Supabase.instance.client;

  Future<String> chat(String message, AICoachMode mode) async {
    final res = await _db.functions.invoke('ai-coach', body: {
      'message': message,
      'mode': mode.value,
    });
    if (res.status != 200) throw Exception('AI service unavailable');
    final data = res.data as Map<String, dynamic>;
    return data['reply'] as String? ?? 'No response';
  }

  Future<String> analyzeCheckins(String clientId) async {
    final res = await _db.functions.invoke('ai-coach', body: {
      'message': 'Analyze this client\'s recent check-ins and provide a coaching summary.',
      'mode': AICoachMode.checkinAnalysis.value,
      'target_client_id': clientId,
    });
    if (res.status != 200) throw Exception('AI analysis failed');
    final data = res.data as Map<String, dynamic>;
    return data['reply'] as String? ?? '';
  }

  Future<Map<String, dynamic>> detectRisks(String clientId) async {
    final res = await _db.functions.invoke('ai-coach', body: {
      'message': 'Assess this client for risk factors.',
      'mode': AICoachMode.riskDetection.value,
      'target_client_id': clientId,
    });
    if (res.status != 200) return {'risk_level': 'unknown', 'flags': [], 'recommendation': ''};
    final data = res.data as Map<String, dynamic>;
    final reply = data['reply'] as String? ?? '';
    try {
      final jsonStr = reply.contains('{') ? reply.substring(reply.indexOf('{'), reply.lastIndexOf('}') + 1) : '{}';
      return Map<String, dynamic>.from(Uri.splitQueryString(jsonStr));
    } catch (_) {
      return {'risk_level': 'unknown', 'flags': <String>[], 'recommendation': reply};
    }
  }

  // ── Coaching intelligence layer (ai-coaching-engine) ──────────────────────

  /// Generate a coaching artifact: 'daily_insight' | 'weekly_review' |
  /// 'goal_prediction'. Returns the structured result, or null on failure.
  Future<Map<String, dynamic>?> generate(String type) async {
    try {
      final res = await _db.functions.invoke('ai-coaching-engine', body: {'type': type});
      if (res.status != 200) return null;
      final data = res.data as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      // Fold confidence into the result so cards can show it.
      if (result != null && data['confidence'] != null) {
        result['confidence'] = data['confidence'];
        result['confidence_reasons'] = data['confidence_reasons'];
      }
      return result;
    } catch (_) { return null; }
  }

  // ── Coach personality ─────────────────────────────────────────────────────

  /// {name, style, tone}. Defaults to Nova / motivational / supportive.
  Future<Map<String, dynamic>> getPersona() async {
    final uid = _db.auth.currentUser?.id;
    const fallback = {'name': 'Nova', 'style': 'motivational', 'tone': 'supportive'};
    if (uid == null) return Map.of(fallback);
    try {
      final row = await _db.from('ai_profiles').select('coach_persona').eq('user_id', uid).maybeSingle();
      final p = row?['coach_persona'];
      return p is Map ? Map<String, dynamic>.from(p) : Map.of(fallback);
    } catch (_) { return Map.of(fallback); }
  }

  Future<bool> setPersona({required String style, required String tone, String name = 'Nova'}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await _db.from('ai_profiles').upsert({
        'user_id': uid,
        'coach_persona': {'name': name, 'style': style, 'tone': tone},
      });
      return true;
    } catch (_) { return false; }
  }

  /// Today's stored daily insight, if one exists.
  Future<Map<String, dynamic>?> getTodayInsight() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      return await _db.from('ai_insights').select()
          .eq('user_id', uid).eq('type', 'daily_insight').eq('for_date', today)
          .maybeSingle();
    } catch (_) { return null; }
  }

  /// Latest stored ai_insights row of a given type ('risk' | 'progress' | …).
  Future<Map<String, dynamic>?> getLatestInsight(String type) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      return await _db.from('ai_insights').select()
          .eq('user_id', uid).eq('type', type)
          .order('created_at', ascending: false).limit(1).maybeSingle();
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>?> getLatestReview() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      return await _db.from('ai_reviews').select()
          .eq('user_id', uid).order('period_end', ascending: false).limit(1).maybeSingle();
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>?> getLatestPrediction() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      return await _db.from('ai_goal_predictions').select()
          .eq('user_id', uid).order('created_at', ascending: false).limit(1).maybeSingle();
    } catch (_) { return null; }
  }

  // ── Coaching memory (likes / dislikes / injuries the coach remembers) ──────

  /// kind: like | dislike | injury | preference | constraint | note
  Future<bool> addMemory(String kind, String content, {String source = 'user'}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await _db.from('ai_memories').upsert({
        'user_id': uid, 'kind': kind, 'content': content.trim(), 'source': source,
      }, onConflict: 'user_id,kind,content');
      return true;
    } catch (_) { return false; }
  }

  Future<List<Map<String, dynamic>>> getMemories() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final data = await _db.from('ai_memories').select()
          .eq('user_id', uid).order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) { return []; }
  }

  /// Remove one remembered fact. Returns whether it was actually removed.
  ///
  /// This returned `void` and ended in `catch (_) {}`, so a failed delete was
  /// indistinguishable from a successful one. That matters more here than in
  /// most places: these rows are health facts — `kind` includes `injury`, and
  /// `ai-coach` captures them automatically from what the member types — and
  /// this is the only control a member has over them. A silent failure meant
  /// the chip reappeared after the refresh with no explanation, which reads as
  /// a glitch rather than "your deletion did not happen".
  ///
  /// `addMemory` beside it already returns `bool`; this now matches it.
  ///
  /// Authorization is the database's: migration 074 puts `"own ai data"` on
  /// `ai_memories` `FOR ALL ... USING (user_id = auth.uid())`, so the missing
  /// `user_id` predicate here cannot delete another member's row.
  Future<bool> deleteMemory(String id) async {
    try {
      await _db.from('ai_memories').delete().eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  Future<List<Map<String, dynamic>>> getConversationHistory({int limit = 20}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final data = await _db
          .from('ai_conversations')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: true)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }
}
