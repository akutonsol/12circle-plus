import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/observability/app_failure.dart';
import '../../coach/data/coach_relationship_service.dart' show AccountChangedError;

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

  /// P0-FL-62a1 · The member this service acts for, captured when the member's
  /// AI coach screen opened (`boundTo` of their id). Null: whoever is signed in
  /// at each call, as before (the callers outside that screen).
  ///
  /// With an owner, nothing is read, written or invoked unless [owner] is the
  /// account signed in at that moment, and every write is stamped with it: the
  /// screen outlives a sign-in switch until its next frame (a hidden web tab
  /// draws none), and the Edge Functions answer for whoever's token goes out.
  final String? owner;

  AICoachService({this.owner});

  /// The account to act as: [owner] while it is the one signed in; without an
  /// owner, whoever is. Throws [AccountChangedError], having sent nothing,
  /// when [owner] is no longer signed in (signed out included).
  String? _account(String what) {
    final uid = _db.auth.currentUser?.id;
    final o = owner;
    if (o == null) return uid;
    if (uid != o) throw AccountChangedError(what);
    return o;
  }

  /// [_account] for a write or an invoke: the refusal is recorded, and null
  /// (nothing to act as) comes back instead.
  String? _actor(String method, String what) {
    try {
      return _account(what);
    } on AccountChangedError catch (e, st) {
      reportError('AICoachService.$method', e, st);
      return null;
    }
  }

  /// Throws [AccountChangedError] (recorded, nothing sent) when the owner has
  /// left: the reply would be another member's conversation.
  Future<String> chat(String message, AICoachMode mode) async {
    if (owner != null && _actor('chat', 'Asking the AI coach') == null) {
      throw AccountChangedError('Asking the AI coach');
    }
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
  ///
  /// With an owner who has left, nothing is invoked (it would run for the
  /// member signed in now): recorded, and null.
  Future<Map<String, dynamic>?> generate(String type) async {
    if (owner != null && _actor('generate', 'Generating $type') == null) {
      return null;
    }
    try {
      final res = await _db.functions.invoke('ai-coaching-engine', body: {'type': type});
      if (res.status != 200) {
        // RM-2 (C14-62a1-02) · the status only: the body may carry the
        // member's data.
        reportError('AICoachService.generate',
            StateError('ai-coaching-engine $type answered ${res.status}'));
        return null;
      }
      final data = res.data as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) {
        reportError('AICoachService.generate',
            StateError('ai-coaching-engine $type answered no result'));
        return null;
      }
      // Fold confidence into the result so cards can show it.
      if (data['confidence'] != null) {
        result['confidence'] = data['confidence'];
        result['confidence_reasons'] = data['confidence_reasons'];
      }
      return result;
    } catch (e, st) {
      // RM-2 (C14-62a1-02) · recorded once (this caught and dropped it); null
      // stays the failure the callers say.
      reportError('AICoachService.generate', e, st);
      return null;
    }
  }

  // ── Coach personality ─────────────────────────────────────────────────────

  /// {name, style, tone}. Defaults to Nova / motivational / supportive when
  /// the member has never chosen one (no row, or no persona on it).
  ///
  /// A FAILED read is recorded and rethrown, not answered with the default:
  /// the default shown as the member's setting is a claim the app could not
  /// make, and the style card would then save it over their real persona the
  /// moment they touched it (P0-FL-50b).
  Future<Map<String, dynamic>> getPersona() async {
    final uid = _account('Reading the coach style');
    const fallback = {'name': 'Nova', 'style': 'motivational', 'tone': 'supportive'};
    if (uid == null) return Map.of(fallback);
    try {
      final row = await _db.from('ai_profiles').select('coach_persona').eq('user_id', uid).maybeSingle();
      final p = row?['coach_persona'];
      return p is Map ? Map<String, dynamic>.from(p) : Map.of(fallback);
    } catch (e, st) {
      reportError('AICoachService.getPersona', e, st);
      rethrow;
    }
  }

  Future<bool> setPersona({required String style, required String tone, String name = 'Nova'}) async {
    final uid = _actor('setPersona', 'Saving the coach style');
    if (uid == null) return false;
    try {
      // Ask for the row back: a write RLS filtered to nothing is a 204 too.
      final rows = await _db.from('ai_profiles').upsert({
        'user_id': uid,
        'coach_persona': {'name': name, 'style': style, 'tone': tone},
      }).select('user_id');
      if ((rows as List).isEmpty) {
        reportError('AICoachService.setPersona',
            StateError('ai_profiles upsert returned no row'));
        return false;
      }
      return true;
    } catch (e, st) {
      reportError('AICoachService.setPersona', e, st);
      return false;
    }
  }

  // The four "latest stored artifact" reads below answer null only when there
  // is none (or nobody is signed in). A failed read is recorded and rethrown:
  // null here means "none yet", and the cards act on it — the daily brief and
  // the weekly review GENERATE a new one on null — so a failure answered as
  // null was shown as "nothing yet" and spent a generation (P0-FL-50b).

  /// Today's stored daily insight, if one exists.
  Future<Map<String, dynamic>?> getTodayInsight() async {
    final uid = _account("Reading today's brief");
    if (uid == null) return null;
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      return await _db.from('ai_insights').select()
          .eq('user_id', uid).eq('type', 'daily_insight').eq('for_date', today)
          .maybeSingle();
    } catch (e, st) {
      reportError('AICoachService.getTodayInsight', e, st);
      rethrow;
    }
  }

  /// Latest stored ai_insights row of a given type ('risk' | 'progress' | …).
  Future<Map<String, dynamic>?> getLatestInsight(String type) async {
    final uid = _account('Reading the latest $type insight');
    if (uid == null) return null;
    try {
      return await _db.from('ai_insights').select()
          .eq('user_id', uid).eq('type', type)
          .order('created_at', ascending: false).limit(1).maybeSingle();
    } catch (e, st) {
      reportError('AICoachService.getLatestInsight', e, st, {'type': type});
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getLatestReview() async {
    final uid = _account('Reading the weekly review');
    if (uid == null) return null;
    try {
      return await _db.from('ai_reviews').select()
          .eq('user_id', uid).order('period_end', ascending: false).limit(1).maybeSingle();
    } catch (e, st) {
      reportError('AICoachService.getLatestReview', e, st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getLatestPrediction() async {
    final uid = _account('Reading the goal prediction');
    if (uid == null) return null;
    try {
      return await _db.from('ai_goal_predictions').select()
          .eq('user_id', uid).order('created_at', ascending: false).limit(1).maybeSingle();
    } catch (e, st) {
      reportError('AICoachService.getLatestPrediction', e, st);
      rethrow;
    }
  }

  // ── Coaching memory (likes / dislikes / injuries the coach remembers) ──────

  /// kind: like | dislike | injury | preference | constraint | note
  Future<bool> addMemory(String kind, String content, {String source = 'user'}) async {
    final uid = _actor('addMemory', 'Saving a coaching memory');
    if (uid == null) return false;
    try {
      final rows = await _db.from('ai_memories').upsert({
        'user_id': uid, 'kind': kind, 'content': content.trim(), 'source': source,
      }, onConflict: 'user_id,kind,content').select('id');
      if ((rows as List).isEmpty) {
        reportError('AICoachService.addMemory',
            StateError('ai_memories upsert returned no row'));
        return false;
      }
      return true;
    } catch (e, st) {
      reportError('AICoachService.addMemory', e, st);
      return false;
    }
  }

  /// What the coach remembers about the member. [] only when there is nothing
  /// (or nobody is signed in). A failed read is recorded and rethrown: this
  /// list is the member's only view of the health facts the coach keeps, and
  /// a failure shown as "nothing remembered" — e.g. the reload after a delete
  /// — tells them their injuries are gone when they are not (P0-FL-50b).
  Future<List<Map<String, dynamic>>> getMemories() async {
    final uid = _account('Reading the coaching memory');
    if (uid == null) return [];
    try {
      final data = await _db.from('ai_memories').select()
          .eq('user_id', uid).order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (e, st) {
      reportError('AICoachService.getMemories', e, st);
      rethrow;
    }
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
  ///
  /// RLS filtering the delete to nothing answers 204 like a real delete, so
  /// the row is asked back and an empty answer is a failure (P0-FL-50b).
  ///
  /// With an owner who has left, nothing is deleted (it would go out as the
  /// member signed in now): recorded, and false.
  Future<bool> deleteMemory(String id) async {
    if (owner != null && _actor('deleteMemory', 'Removing a coaching memory') == null) {
      return false;
    }
    try {
      final rows = await _db.from('ai_memories').delete().eq('id', id).select('id');
      if ((rows as List).isEmpty) {
        reportError('AICoachService.deleteMemory',
            StateError('ai_memories delete removed no row'));
        return false;
      }
      return true;
    } catch (e, st) {
      reportError('AICoachService.deleteMemory', e, st);
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getConversationHistory({int limit = 20}) async {
    final uid = _account('Reading the conversation');
    if (uid == null) return [];
    try {
      // The LATEST [limit] exchanges, returned oldest first. Ascending with
      // `limit` kept the first ever: after more than ten exchanges, reopening
      // the chat always showed the same opening ten and never the latest.
      final data = await _db
          .from('ai_conversations')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data as List).reversed.toList();
    } catch (e, st) {
      // Rethrown, not []: [] reopens the chat as a fresh conversation with
      // the welcome message, as if the member had never talked to the coach.
      reportError('AICoachService.getConversationHistory', e, st);
      rethrow;
    }
  }
}
