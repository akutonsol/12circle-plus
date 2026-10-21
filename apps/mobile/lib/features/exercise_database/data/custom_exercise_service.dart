import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/exercise_detail_model.dart';
import '../../workout/data/models/video_variant_model.dart';

class CustomExerciseService {
  // Resolved on use, not in the constructor — the same rule WorkoutService
  // states for itself. An eager field meant merely CONSTRUCTING this service
  // required an initialised Supabase instance, which put every screen that
  // holds one out of reach of widget tests.
  SupabaseClient get _db => Supabase.instance.client;

  String? get _uid => _db.auth.currentUser?.id;

  /// Last error from a create/upload, surfaced to the UI for diagnostics.
  Object? lastError;

  /// "Barbell Squat" -> "barbell-squat".
  static String slugify(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<List<ExerciseDetail>> getMyExercises() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _db
          .from('custom_exercises')
          .select()
          .eq('coach_id', uid)
          .order('created_at', ascending: false);
      return (rows as List).map((r) => ExerciseDetail.fromJson(r)).toList();
    } catch (_) { return []; }
  }

  /// Tracking flags for an exercise matching [name] in the global library.
  /// Defaults to supporting both when there's no matching record.
  Future<({bool rpe, bool pr})> metaForName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return (rpe: true, pr: true);
    try {
      final rows = await _db
          .from('custom_exercises')
          .select('supports_rpe_tracking, supports_pr_tracking')
          .eq('visibility', 'global')
          .eq('submission_status', 'approved')
          .ilike('name', '%$n%')
          .limit(1);
      if ((rows as List).isNotEmpty) {
        final r = rows.first as Map;
        return (
          rpe: r['supports_rpe_tracking'] != false,
          pr: r['supports_pr_tracking'] != false,
        );
      }
    } catch (_) {}
    return (rpe: true, pr: true);
  }

  /// First video URL for an exercise matching [name] in the global library
  /// (coach/admin uploaded), or null. Used by the in-workout Exercise Guide.
  Future<String?> findVideoForName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    try {
      final rows = await _db
          .from('custom_exercises')
          .select('name, video_variants')
          .eq('visibility', 'global')
          .eq('submission_status', 'approved')
          .ilike('name', '%$n%')
          .limit(5);
      for (final r in (rows as List)) {
        final vv = r['video_variants'];
        if (vv is List && vv.isNotEmpty && vv.first is Map) {
          final url = (vv.first as Map)['url'] as String?;
          if (url != null && url.trim().isNotEmpty) return url.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<ExerciseDetail>> getGlobalApprovedExercises() async {
    try {
      final rows = await _db
          .from('custom_exercises')
          .select()
          .eq('visibility', 'global')
          .eq('submission_status', 'approved')
          .order('name');
      return (rows as List).map((r) => ExerciseDetail.fromJson(r)).toList();
    } catch (_) { return []; }
  }

  // ── Create ────────────────────────────────────────────────────────────────

  Future<String?> createExercise({
    required String name,
    required String category,
    required String muscleGroup,
    required List<String> secondaryMuscles,
    required String equipment,
    required String difficulty,
    required String description,
    required List<String> instructions,
    required List<String> coachingCues,
    required List<String> commonMistakes,
    required List<String> alternatives,
    String? beginnerModification,
    String? advancedProgression,
    required List<String> tags,
    required List<VideoVariant> videoVariants,
    String? imageUrl,
    String visibility = 'private',
    Map<String, dynamic>? extra, // additional columns (metadata)
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    lastError = null;
    final data = <String, dynamic>{
      'coach_id': uid,
      'name': name,
      'category': category,
      'muscle_group': muscleGroup,
      'secondary_muscles': secondaryMuscles,
      'equipment': equipment,
      'difficulty': difficulty,
      'description': description,
      'instructions': instructions,
      'coaching_cues': coachingCues,
      'common_mistakes': commonMistakes,
      'alternatives': alternatives,
      if (beginnerModification != null) 'beginner_modification': beginnerModification,
      if (advancedProgression != null) 'advanced_progression': advancedProgression,
      'tags': tags,
      'video_variants': videoVariants.map((v) => v.toJson()).toList(),
      if (imageUrl != null) 'image_url': imageUrl,
      'visibility': visibility,
      ...?extra,
    };
    // Coach-published global exercises go live for clients immediately.
    if (visibility == 'global') data['submission_status'] = 'approved';
    // Always have a slug (derive from name) so every exercise is enrichable and
    // re-saving the same name updates rather than duplicates.
    data['slug'] ??= slugify(name);
    final slug = data['slug'] as String?;
    try {
      // Upsert by (coach_id, slug): re-importing the same exercise updates the
      // existing row instead of creating a duplicate.
      if (slug != null) {
        final existing = await _db
            .from('custom_exercises')
            .select('id')
            .eq('coach_id', uid)
            .eq('slug', slug)
            .maybeSingle();
        if (existing != null) {
          final eid = existing['id'] as String;
          await _db.from('custom_exercises').update(data).eq('id', eid);
          return eid;
        }
      }
      final row = await _db.from('custom_exercises').insert(data).select().single();
      return row['id'] as String;
    } catch (e) { lastError = e; return null; }
  }

  /// Fan a master-schema exercise JSON out into the normalized child tables
  /// (exercise_muscles/equipment/tags/media/substitutions/progressions/
  /// modifications/analytics). Idempotent server-side. Safe to call after
  /// createExercise; failures don't block the core save.
  Future<bool> syncRelations(String exerciseId, Map<String, dynamic> masterJson) async {
    try {
      await _db.rpc('sync_exercise_relations', params: {
        'p_exercise_id': exerciseId,
        'p': masterJson,
      });
      return true;
    } catch (e) { lastError = e; return false; }
  }

  /// Ask the enrich-exercise edge function to generate + save coaching content
  /// (instructions, cues, mistakes, breathing, AI tips) for [slug].
  Future<({bool ok, String? error})> enrichWithAI(String slug) async {
    try {
      final res = await _db.functions.invoke('enrich-exercise', body: {'slug': slug});
      if (res.status == 200) return (ok: true, error: null);
      final d = res.data;
      final msg = (d is Map && d['error'] != null)
          ? d['error'].toString() : 'Enrichment failed (${res.status})';
      return (ok: false, error: msg);
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = (d is Map && d['error'] != null) ? d['error'].toString() : 'Enrichment failed';
      return (ok: false, error: msg);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Coach/admin: attach media (image + videos) to any exercise, without
  /// touching the admin-managed text content. Privileged via the RPC.
  Future<bool> updateExerciseMedia(String id,
      {String? imageUrl, required List<Map<String, dynamic>> videoVariants}) async {
    try {
      await _db.rpc('update_exercise_media', params: {
        'p_id': id,
        'p_image_url': imageUrl,
        'p_video_variants': videoVariants,
      });
      return true;
    } catch (e) { lastError = e; return false; }
  }

  /// Substitute exercises for a given exercise — same muscle group from the
  /// global library, excluding the exercise itself. For the active-workout swap.
  Future<List<Map<String, dynamic>>> getSubstitutes(String name, String muscleGroup) async {
    final mg = muscleGroup.trim();
    // Never recommend across muscle groups — an unknown group returns nothing
    // rather than a random grab of any approved exercise.
    if (mg.isEmpty) return [];
    try {
      final rows = await _db.from('custom_exercises')
          .select('name, muscle_group, equipment, difficulty')
          .eq('visibility', 'global').eq('submission_status', 'approved')
          .ilike('muscle_group', '%$mg%')
          .neq('name', name).limit(12);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) { return []; }
  }

  /// A YouTube id resolved by the bulk video-enrichment pipeline, keyed by
  /// exercise name — covers the hardcoded library too (which isn't in the DB).
  Future<String?> findEnrichedVideo(String name) async {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    try {
      final row = await _db
          .from('exercise_videos')
          .select('youtube_id')
          .eq('name_key', key)
          .maybeSingle();
      final id = row?['youtube_id'] as String?;
      return (id != null && id.trim().isNotEmpty) ? id : null;
    } catch (_) { return null; }
  }

  /// Coach/admin: run the YouTube video enrichment for a batch of exercise names
  /// (the edge function resolves real embeddable ids and caches them). Returns
  /// the number updated, or null on failure.
  Future<int?> enrichExerciseVideos(List<String> names, {bool force = false}) async {
    try {
      final res = await _db.functions.invoke('enrich-exercise-videos',
          body: {'names': names, 'force': force});
      final data = res.data;
      if (data is Map && data['updated'] is int) return data['updated'] as int;
      return 0;
    } catch (e) { lastError = e; return null; }
  }

  /// Bulk AI content enrichment for the GLOBAL `exercises` table (instructions,
  /// cues, mistakes, beginner/advanced variants, alternatives). Processes one
  /// batch and returns {updated, failed, remaining} so a caller can loop until
  /// remaining hits 0. null = the call failed (see [lastError]).
  Future<({int updated, int failed, int remaining})?> enrichExerciseContent(
      {int limit = 15, bool force = false}) async {
    try {
      final res = await _db.functions.invoke('enrich-exercise-content',
          body: {'limit': limit, 'force': force});
      final d = res.data;
      if (d is Map) {
        return (
          updated: (d['updated'] as int?) ?? 0,
          failed: (d['failed'] as int?) ?? 0,
          remaining: (d['remaining_stubs'] as int?) ?? 0,
        );
      }
      return (updated: 0, failed: 0, remaining: 0);
    } catch (e) { lastError = e; return null; }
  }

  /// Live content-completion metrics across the global `exercises` library.
  /// Returns per-field filled counts + total, for the Content Management Center.
  Future<({int total, Map<String, int> filled})> exerciseContentStats() async {
    const fields = [
      'image_url', 'instructions', 'coaching_cues', 'common_mistakes',
      'beginner_modification', 'advanced_progression', 'alternatives',
    ];
    bool has(dynamic v) {
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      if (v is List) return v.isNotEmpty;
      if (v is Map) return v.isNotEmpty;
      return true;
    }
    final rows = await _db.from('exercises').select(
        '${fields.join(',')},video_variants,video_assets,muscle_group,equipment');
    final list = (rows as List).cast<Map<String, dynamic>>();
    final filled = <String, int>{for (final f in fields) f: 0};
    filled['video'] = 0;
    filled['ai_ready'] = 0;
    for (final r in list) {
      for (final f in fields) { if (has(r[f])) filled[f] = filled[f]! + 1; }
      if (has(r['video_variants']) || has(r['video_assets'])) filled['video'] = filled['video']! + 1;
      if (has(r['instructions']) && has(r['coaching_cues']) &&
          has(r['muscle_group']) && has(r['equipment'])) {
        filled['ai_ready'] = filled['ai_ready']! + 1;
      }
    }
    return (total: list.length, filled: filled);
  }

  /// Content-pipeline lifecycle counts (draft/ai_generated/under_review/…).
  /// Returns null if migration 083 isn't applied yet (RPC absent).
  Future<Map<String, dynamic>?> contentPipelineStats() async {
    try {
      final res = await _db.rpc('exercise_content_stats');
      if (res is List && res.isNotEmpty) return (res.first as Map).cast<String, dynamic>();
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// Exercises awaiting an editor (AI drafts + revisions), newest AI first.
  /// Returns null if the pipeline columns don't exist yet (migration 083).
  Future<List<Map<String, dynamic>>?> reviewQueue({int limit = 50}) async {
    try {
      final rows = await _db.from('exercises').select(
              'id,name,muscle_group,equipment,difficulty,instructions,coaching_cues,'
              'common_mistakes,beginner_modification,advanced_progression,alternatives,'
              'ai_confidence,content_status,content_version')
          .inFilter('content_status', ['ai_generated', 'under_review', 'needs_revision'])
          .order('ai_confidence', ascending: true)
          .limit(limit);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) { lastError = e; return null; }
  }

  /// Move an exercise through the editorial lifecycle (approve/publish/revise…).
  Future<bool> reviewExercise(String id, String status) async {
    try {
      await _db.rpc('review_exercise_content', params: {'p_id': id, 'p_status': status});
      return true;
    } catch (e) { lastError = e; return false; }
  }

  /// Library-wide certification counts (how many exercises each module can
  /// safely consume). Null if migration 084 isn't applied.
  Future<Map<String, dynamic>?> certificationSummary() async {
    try {
      final res = await _db.rpc('certification_summary');
      if (res is List && res.isNotEmpty) return (res.first as Map).cast<String, dynamic>();
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// The certification object for ONE exercise — the single source of truth a
  /// module uses to decide "can I use this?". Null if 084 absent.
  Future<Map<String, dynamic>?> exerciseCertification(String id) async {
    try {
      final res = await _db.rpc('exercise_certification', params: {'p_id': id});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  // ── Movement Intelligence Engine (graph) ──────────────────────────────────
  /// Everything the graph knows about one exercise (relationships + neighbors).
  /// Null if migration 085 isn't applied.
  Future<Map<String, dynamic>?> movementGraph(String exerciseId) async {
    try {
      final res = await _db.rpc('movement_graph', params: {'p_exercise_id': exerciseId});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// Graph shape overview (node/edge counts by type). Null if 085 absent.
  Future<Map<String, dynamic>?> movementGraphStats() async {
    try {
      final res = await _db.rpc('movement_graph_stats');
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// (Re)derive the graph from existing exercise columns. Admin/content-manager.
  /// Returns {nodes, edges} or null on failure.
  Future<Map<String, dynamic>?> rebuildMovementGraph() async {
    try {
      final res = await _db.rpc('rebuild_movement_graph');
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  // ── MIE Phase 2: Programming Intelligence ─────────────────────────────────
  /// Intelligence-layer coverage (how many exercises have a profile). Null if 087 absent.
  Future<Map<String, dynamic>?> intelligenceStats() async {
    try {
      final res = await _db.rpc('intelligence_stats');
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// Derive partial intelligence profiles from existing exercise data. Admin.
  Future<Map<String, dynamic>?> rebuildExerciseIntelligence() async {
    try {
      final res = await _db.rpc('rebuild_exercise_intelligence');
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// AI-enrich full intelligence profiles (Phase 2b). One batch; loop until
  /// remaining hits 0. Profiles land as 'ai_generated' for human review.
  Future<({int updated, int failed, int remaining})?> enrichExerciseIntelligence(
      {int limit = 10}) async {
    try {
      final res = await _db.functions.invoke('enrich-exercise-intelligence',
          body: {'limit': limit});
      final d = res.data;
      if (d is Map) {
        return (
          updated: (d['updated'] as int?) ?? 0,
          failed: (d['failed'] as int?) ?? 0,
          remaining: (d['remaining_drafts'] as int?) ?? 0,
        );
      }
      return (updated: 0, failed: 0, remaining: 0);
    } catch (e) { lastError = e; return null; }
  }

  // ── Per-attribute knowledge review ────────────────────────────────────────
  /// Profiles awaiting attribute-level review (lowest confidence first). Null if 091 absent.
  Future<List<Map<String, dynamic>>?> intelligenceReviewQueue({int limit = 50}) async {
    try {
      final res = await _db.rpc('intelligence_review_queue', params: {'p_limit': limit});
      if (res is List) return res.cast<Map<String, dynamic>>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// Merged per-attribute state (confidence + review status) for one profile.
  Future<Map<String, dynamic>?> attributeReviewState(String exerciseId) async {
    try {
      final res = await _db.rpc('attribute_review_state', params: {'p_exercise_id': exerciseId});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// Approve / reject / flag-for-edit a single attribute.
  Future<bool> reviewAttribute(String exerciseId, String attribute, String status,
      {String? note}) async {
    try {
      await _db.rpc('review_attribute', params: {
        'p_exercise_id': exerciseId, 'p_attribute': attribute, 'p_status': status,
        if (note != null) 'p_note': note,
      });
      return true;
    } catch (e) { lastError = e; return false; }
  }

  /// Finalize a profile — derives status from its attribute reviews. Returns new status.
  Future<String?> finalizeIntelligence(String exerciseId) async {
    try {
      final res = await _db.rpc('finalize_intelligence', params: {'p_exercise_id': exerciseId});
      return res?.toString();
    } catch (e) { lastError = e; return null; }
  }

  /// Move an intelligence profile through the review lifecycle.
  Future<bool> reviewIntelligence(String id, String status) async {
    try {
      await _db.rpc('review_intelligence', params: {'p_id': id, 'p_status': status});
      return true;
    } catch (e) { lastError = e; return false; }
  }

  /// Deterministic MIE decision: rank exercises for a programming context, best
  /// first. context: {goal, equipment[], recovery, experience, injuries[],
  /// recent_patterns[]}. The engine decides; an LLM only explains later.
  Future<List<Map<String, dynamic>>?> rankExercises(
      Map<String, dynamic> context, {int limit = 10}) async {
    try {
      final res = await _db.rpc('rank_exercises',
          params: {'p_context': context, 'p_limit': limit});
      if (res is List) return res.cast<Map<String, dynamic>>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  // ── MIE Phase 3: Rules Engine + Warm-Up Generator ─────────────────────────
  /// Build one rule-constrained, scored workout for a context. Deterministic —
  /// the engine decides. Returns {selected, warmup, volume_factor, rules_applied}.
  Future<Map<String, dynamic>?> buildWorkout(Map<String, dynamic> context) async {
    try {
      final res = await _db.rpc('build_workout', params: {'p_context': context});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// Validate a week plan (list of days, each a list of exercise ids) against the
  /// cross-day rules. Returns {violations, spinal_days, ok}.
  Future<Map<String, dynamic>?> validateWeek(List<List<String>> days) async {
    try {
      final res = await _db.rpc('validate_week', params: {'p_days': days});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// Seed the curated mobility/activation warm-up library into the graph. Admin.
  Future<Map<String, dynamic>?> seedWarmupLibrary() async {
    try {
      final res = await _db.rpc('seed_warmup_library');
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  // ── MIE Phase 4: Decision Intelligence ────────────────────────────────────
  /// Build AND record a workout: returns the plan + decision `trace` + trace_id.
  /// The trace is structured data (coach/client/debugger read it, no AI).
  Future<Map<String, dynamic>?> generateWorkout(Map<String, dynamic> context,
      {String? subjectId}) async {
    try {
      final res = await _db.rpc('generate_workout', params: {
        'p_context': context,
        if (subjectId != null) 'p_subject': subjectId,
      });
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// L4: narrate a recorded decision trace into coach/client language. The LLM
  /// is constrained to the trace only (never invents). Returns the explanation.
  Future<String?> explainDecision(String traceId, {String audience = 'client'}) async {
    try {
      final res = await _db.functions.invoke('explain-decision',
          body: {'trace_id': traceId, 'audience': audience});
      final d = res.data;
      if (d is Map && d['explanation'] is String) return d['explanation'] as String;
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// Coaching-quality observability — a KPI bundle composed from EXISTING data
  /// and analytics RPCs (no new backend). Every piece degrades independently.
  Future<Map<String, dynamic>> platformObservability() async {
    Future<int> cnt(String table, [Map<String, String> eq = const {}]) async {
      try {
        var q = _db.from(table).select('id');
        eq.forEach((k, v) => q = q.eq(k, v));
        final r = await q.limit(10000);
        return (r as List).length;
      } catch (_) { return 0; }
    }
    Future<int?> avgOf(String table, String col) async {
      try {
        final r = await _db.from(table).select(col).limit(5000);
        final v = (r as List).map((e) => e[col]).whereType<num>().toList();
        return v.isEmpty ? null : (v.reduce((a, b) => a + b) / v.length).round();
      } catch (_) { return null; }
    }
    final out = <String, dynamic>{};
    out['programs_generated']  = await cnt('workout_programs', {'engine_generated': 'true'});
    out['decision_traces']     = await cnt('decision_traces');
    out['predictions']         = await cnt('predictions');
    out['weekly_reviews_sent'] = await cnt('communications', {'type': 'weekly_review', 'status': 'sent'});
    out['communications_total']= await cnt('communications');
    out['avg_adherence']       = await avgOf('weekly_feedback', 'completion_pct');
    out['avg_goal_confidence'] = await avgOf('predictions', 'confidence');
    out['analytics']           = await decisionAnalytics();
    out['certification']       = await certificationSummary();
    out['intelligence']        = await intelligenceStats();
    return out;
  }

  /// Aggregate decision analytics across recorded traces. Null if 089 absent.
  Future<Map<String, dynamic>?> decisionAnalytics() async {
    try {
      final res = await _db.rpc('decision_analytics');
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  // ── Layered exercise media (coach overlay) ────────────────────────────────
  /// Resolve the highest-priority coaching overlay for the current viewer
  /// (client → coach → official). Null/`has_coach_overlay:false` if none.
  Future<Map<String, dynamic>?> resolveExerciseMedia(String exerciseId) async {
    try {
      final uid = _db.auth.currentUser?.id;
      final res = await _db.rpc('resolve_exercise_media',
          params: {'p_exercise_id': exerciseId, 'p_viewer_id': uid});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (e) { lastError = e; return null; }
  }

  /// The current coach's own overlay for an exercise (for editing). Null if none.
  Future<Map<String, dynamic>?> getCoachOverlay(String exerciseId) async {
    try {
      final uid = _db.auth.currentUser?.id;
      final r = await _db.from('coach_exercise_media').select()
          .eq('coach_id', uid ?? '').eq('exercise_id', exerciseId).maybeSingle();
      return r?.cast<String, dynamic>();
    } catch (e) { lastError = e; return null; }
  }

  /// Create/replace the coach's overlay (a partial override — any field optional).
  Future<bool> upsertCoachOverlay(String exerciseId,
      {String? note, List<String>? focus, String? videoRef}) async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return false;
      await _db.from('coach_exercise_media').upsert({
        'coach_id': uid, 'exercise_id': exerciseId,
        'note': note, 'focus': focus ?? [], 'video_ref': videoRef,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'coach_id,exercise_id');
      return true;
    } catch (e) { lastError = e; return false; }
  }

  // ── Coaching packs (reusable cue sets) ────────────────────────────────────
  /// The current coach's saved cue packs (name + cues), newest first.
  Future<List<Map<String, dynamic>>> getCoachingPacks() async {
    try {
      final uid = _db.auth.currentUser?.id;
      final r = await _db.from('coach_coaching_packs').select()
          .eq('coach_id', uid ?? '').order('created_at', ascending: false);
      return (r as List).cast<Map<String, dynamic>>();
    } catch (_) { return []; }
  }

  /// Save a named cue set for reuse across exercises.
  Future<bool> createCoachingPack(String name, List<String> cues) async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null || name.trim().isEmpty) return false;
      await _db.from('coach_coaching_packs')
          .insert({'coach_id': uid, 'name': name.trim(), 'cues': cues});
      return true;
    } catch (e) { lastError = e; return false; }
  }

  Future<bool> deleteCoachingPack(String id) async {
    try {
      await _db.from('coach_coaching_packs').delete().eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  // ── Coach audio (voice note on an exercise) ───────────────────────────────
  /// Upload recorded audio bytes to coach-media, return the **object path**.
  ///
  /// SEC-VOICE-2. This returned `getPublicUrl(path)`, and `setCoachVoice`
  /// persisted that into `coach_exercise_media.voice_url` — a permanent,
  /// unauthenticated URL to a recording of a coach's voice, on a bucket
  /// confirmed public by live probe. Render-time signing was added in the
  /// previous wave and the Dart prerequisite recorded DONE, but only the
  /// *display* half had been done: what was **stored** was still a public URL,
  /// so every existing row is a live unauthenticated link.
  ///
  /// The path is what is stored now, matching SEC-VIDEO-1's treatment of the
  /// sibling video path and this repository's own rule for protected media in
  /// `chat_media_path.dart`: *"The bucket is PRIVATE. Nothing in the app may
  /// call `getPublicUrl()` on it"*.
  ///
  /// Both readers normalise either form via `coachVoiceSigningPath`, so legacy
  /// rows keep working and no migration is required to land this.
  Future<String?> uploadCoachVoice(String exerciseId, Uint8List bytes, {String ext = 'm4a'}) async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return null;
      final path = 'voice/$uid/$exerciseId-${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _db.storage.from('coach-media').uploadBinary(path, bytes,
          fileOptions: const FileOptions(contentType: 'audio/mp4', upsert: true));
      return path;
    } catch (e) { lastError = e; return null; }
  }

  /// A short-lived URL for a stored coach voice note.
  ///
  /// SEC-VOICE-1 (prerequisite) / SEC-VOICE-2. `uploadCoachVoice` **used to**
  /// store a `getPublicUrl(...)` value, which is permanent and unauthenticated
  /// — rows written before SEC-VOICE-2 still hold one, which is why this
  /// resolver must keep accepting that form. The
  /// repository's own rule for protected media is the opposite — see
  /// `chat_media_path.dart`: *"The bucket is PRIVATE. Nothing in the app may
  /// call `getPublicUrl()` on it"*, with display going through
  /// `createSignedUrl()` at render time. `progress-photos` and `chat-media`
  /// already do exactly that with a 3600s expiry.
  ///
  /// Signing works on a public bucket too, so this lands safely **now** and is
  /// the change `docs/proposed/SEC_VOICE_1_coach_media_private.sql` says must
  /// accompany the migration — without it, privatising the bucket stops every
  /// existing voice note from loading.
  ///
  /// Accepts either a stored public URL (legacy rows) or a bare object path,
  /// because `coachVoiceObjectPath` normalises both. Returns `null` when the
  /// value is not a `coach-media` reference, so a foreign URL is never signed.
  /// Which object path, if any, a stored value may be signed for.
  ///
  /// Pure and separate so the negative cases can be asserted directly: a
  /// mutation that let ANY value through survived a source-level check,
  /// because the method's `catch` also contains `return null`. A guard that
  /// greps a method body for a token is not checking a branch.
  static String? coachVoiceSigningPath(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    final fromUrl = coachVoiceObjectPath(stored);
    if (fromUrl != null) return fromUrl;
    // A bare object path this code wrote itself. Anything else — another
    // bucket, a foreign host, a relative fragment — is not signable.
    if (stored.startsWith('voice/') && !stored.contains('://')) return stored;
    return null;
  }

  Future<String?> signedCoachVoiceUrl(String stored) async {
    final path = coachVoiceSigningPath(stored);
    if (path == null) return null;
    try {
      return await _db.storage.from('coach-media').createSignedUrl(path, 3600);
    } catch (e) {
      lastError = e;
      return null;
    }
  }

  /// Attach/replace the coach's voice note on their overlay (with expiry).
  Future<bool> setCoachVoice(String exerciseId, String url, int durationMs, DateTime? expiresAt) async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return false;
      await _db.from('coach_exercise_media').upsert({
        'coach_id': uid, 'exercise_id': exerciseId,
        'voice_url': url, 'voice_duration_ms': durationMs,
        'voice_expires_at': expiresAt?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'coach_id,exercise_id');
      return true;
    } catch (e) { lastError = e; return false; }
  }

  /// The object path inside `coach-media` for a stored voice **URL**.
  ///
  /// Parses the public-URL form ONLY — everything after the bucket segment.
  /// Returns null for anything that is not a `coach-media` public URL, so a
  /// malformed or foreign value never turns into a delete against a path this
  /// code did not create.
  ///
  /// SEC-VOICE-2: `uploadCoachVoice` no longer returns a public URL, so this
  /// now handles **legacy rows only**. Callers that resolve a *stored* value
  /// must use `coachVoiceSigningPath`, which accepts both forms — using this
  /// one directly silently skips every row written after SEC-VOICE-2.
  static String? coachVoiceObjectPath(String? publicUrl) {
    if (publicUrl == null) return null;
    const marker = '/object/public/coach-media/';
    final i = publicUrl.indexOf(marker);
    if (i < 0) return null;
    final path = publicUrl.substring(i + marker.length).split('?').first;
    return path.isEmpty ? null : path;
  }

  /// SEC-VOICE-1 (deletion arm). Clearing a voice note used to null the row's
  /// columns and **leave the audio in place**:
  ///
  /// ```dart
  /// await _db.from('coach_exercise_media').update({'voice_url': null, ...});
  /// return true;   // the object is still in the bucket
  /// ```
  ///
  /// `coach-media` is a PUBLIC bucket — verified live: it serves the public
  /// object route unauthenticated, while `progress-photos`, `chat-media` and
  /// `messages` refuse it. So a coach removed a voice note, the app stopped
  /// showing it, and the recording stayed permanently fetchable by anyone who
  /// had ever held the URL. The row even carries `voice_expires_at`, an expiry
  /// the object never honoured.
  ///
  /// The object is now removed first. If that fails the row is left alone, so
  /// the note stays visible and retryable rather than the app claiming a
  /// deletion it did not perform.
  ///
  /// Making the bucket private is the other half and is a migration —
  /// wave-governed, not taken here.
  Future<bool> clearCoachVoice(String exerciseId) async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return false;

      final row = await _db.from('coach_exercise_media')
          .select('voice_url')
          .eq('coach_id', uid)
          .eq('exercise_id', exerciseId)
          .maybeSingle();
      // SEC-VOICE-2. This resolved the delete target with
      // `coachVoiceObjectPath`, which ONLY parses a full public URL. Once
      // `uploadCoachVoice` began storing a bare object path, that returned
      // null, the `remove()` below was skipped, the row was nulled and this
      // method returned `true` — silently restoring the very defect it was
      // written to fix: the app reports the note deleted and the recording
      // stays in the bucket.
      //
      // `coachVoiceSigningPath` normalises BOTH forms, so legacy rows holding
      // a public URL and new rows holding a path both resolve. It is the same
      // normalisation the render path uses, which is the point: one stored
      // value, one resolver.
      final path = coachVoiceSigningPath(row?['voice_url'] as String?);
      if (path != null) {
        // Deliberately NOT swallowed: if the recording cannot be removed, the
        // app must not report the note as deleted.
        await _db.storage.from('coach-media').remove([path]);
      }

      await _db.from('coach_exercise_media').update({
        'voice_url': null, 'voice_duration_ms': null, 'voice_expires_at': null,
      }).eq('coach_id', uid).eq('exercise_id', exerciseId);
      return true;
    } catch (e) { lastError = e; return false; }
  }

  /// Raw exercise row by id (for prefilling the edit form with all columns).
  Future<Map<String, dynamic>?> getRawById(String id) async {
    try {
      final row = await _db.from('custom_exercises').select().eq('id', id).maybeSingle();
      return row;
    } catch (_) { return null; }
  }

  /// Fetch a single exercise by slug (to refresh the detail after enrichment).
  Future<ExerciseDetail?> getExerciseBySlug(String slug) async {
    try {
      final row = await _db.from('custom_exercises').select().eq('slug', slug).maybeSingle();
      return row == null ? null : ExerciseDetail.fromJson(row);
    } catch (_) { return null; }
  }

  // ── Update ────────────────────────────────────────────────────────────────

  Future<bool> updateExercise(String id, Map<String, dynamic> updates) async {
    try {
      // .select() so an RLS-filtered update (0 rows, no error) is detectable.
      final res = await _db.from('custom_exercises').update(updates).eq('id', id).select('id');
      if ((res as List).isEmpty) {
        lastError = "You don't have permission to edit this exercise";
        return false;
      }
      return true;
    } catch (e) { lastError = e; return false; }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<bool> deleteExercise(String id) async {
    try {
      await _db.from('custom_exercises').delete().eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  // ── Submit to Global Library ──────────────────────────────────────────────

  Future<bool> submitForGlobalLibrary(String exerciseId) async {
    try {
      await _db.from('custom_exercises').update({
        // Platform-wide publishing: goes live for all clients immediately.
        'submission_status': 'approved',
        'submitted_at': DateTime.now().toIso8601String(),
        'visibility': 'global',
      }).eq('id', exerciseId);
      return true;
    } catch (e) { lastError = e; return false; }
  }

  // ── Admin: Global Library moderation (EL-005) ─────────────────────────────

  /// Pending global-library submissions awaiting admin review.
  Future<List<ExerciseDetail>> getPendingGlobalSubmissions() async {
    try {
      final rows = await _db
          .from('custom_exercises')
          .select()
          .eq('submission_status', 'pending')
          .order('submitted_at');
      return (rows as List).map((r) => ExerciseDetail.fromJson(r)).toList();
    } catch (_) { return []; }
  }

  /// Admin approves a submission → it becomes globally visible.
  Future<bool> approveGlobalExercise(String exerciseId) async {
    try {
      // I-COM-03(a) / 3A-9: the reviewer column is `last_reviewed_by` (083);
      // `approved_by` never existed, so this update always 400'd.
      await _db.from('custom_exercises').update({
        'submission_status': 'approved',
        'visibility': 'global',
        'last_reviewed_by': _uid,
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', exerciseId);
      return true;
    } catch (_) { return false; }
  }

  /// Admin rejects a submission → reverts to the coach's private library.
  Future<bool> rejectGlobalExercise(String exerciseId) async {
    try {
      await _db.from('custom_exercises').update({
        'submission_status': 'rejected',
        'visibility': 'private',
      }).eq('id', exerciseId);
      return true;
    } catch (_) { return false; }
  }

  // ── Image / Video Upload ──────────────────────────────────────────────────

  Future<String?> uploadImage(Uint8List bytes, String ext, String exerciseId) async {
    try {
      final path = 'exercises/$exerciseId/image.$ext';
      await _db.storage.from('exercise-media').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
      );
      return _db.storage.from('exercise-media').getPublicUrl(path);
    } catch (e) { lastError = e; return null; }
  }

  Future<String?> uploadVideo(Uint8List bytes, String ext, String exerciseId, String label) async {
    try {
      final slug = label.toLowerCase().replaceAll(' ', '_');
      final path = 'exercises/$exerciseId/video_$slug.$ext';
      await _db.storage.from('exercise-media').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: 'video/$ext'),
      );
      return _db.storage.from('exercise-media').getPublicUrl(path);
    } catch (e) { lastError = e; return null; }
  }
}
