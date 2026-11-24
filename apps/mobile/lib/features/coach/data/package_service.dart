import 'package:supabase_flutter/supabase_flutter.dart';

/// A package write that matched no row (P0-FL-56b): RLS filtered it, or the
/// package is no longer there. PostgREST answers that without an error, so it
/// read as saved / deleted.
class PackageNotChanged implements Exception {
  const PackageNotChanged(this.write);
  final String write;
  @override
  String toString() => 'PackageNotChanged: $write matched no row';
}

/// [PackageService.saveSessionTiers] changed some tiers and then failed. The
/// tiers are separate writes (no transaction without a backend change), so the
/// coach is told which ones were saved and which were not.
class SessionTiersPartlySaved implements Exception {
  const SessionTiersPartlySaved(
      {required this.saved, required this.notSaved, required this.cause});

  /// Tiers (session counts) whose change the server confirmed.
  final List<int> saved;

  /// Tiers whose change was not confirmed: the one that failed, and the ones
  /// after it, which were not attempted.
  final List<int> notSaved;
  final Object cause;
  @override
  String toString() =>
      'SessionTiersPartlySaved(saved: $saved, notSaved: $notSaved): $cause';
}

/// Coach packages (per-session / bulk / monthly) + client workout schedules.
class PackageService {
  final _db = Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  // ── Coach packages ────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getMyPackages() async {
    final uid = _uid;
    if (uid == null) return [];
    final data = await _db
        .from('coach_packages')
        .select()
        .eq('coach_id', uid);
    final list = List<Map<String, dynamic>>.from(data);
    sortForDisplay(list);
    return list;
  }

  Future<List<Map<String, dynamic>>> getCoachPackages(String coachId) async {
    final data = await _db
        .from('coach_packages')
        .select()
        .eq('coach_id', coachId)
        .eq('active', true);
    final list = List<Map<String, dynamic>>.from(data);
    sortForDisplay(list);
    return list;
  }

  /// Groups packages by type so they sit together under each other:
  /// Monthly plans (Basic→Premium→VIP) → Session packages (larger first, so a
  /// Signature 4-pack falls under a Performance 8-pack) → Per-session.
  static void sortForDisplay(List<Map<String, dynamic>> list) {
    int groupRank(String t) => switch (t) { 'monthly' => 0, 'bulk' => 1, _ => 2 };
    list.sort((a, b) {
      final ta = a['type'] as String? ?? '';
      final tb = b['type'] as String? ?? '';
      final g = groupRank(ta).compareTo(groupRank(tb));
      if (g != 0) return g;
      final pa = (a['price'] as num?)?.toDouble() ?? 0;
      final pb = (b['price'] as num?)?.toDouble() ?? 0;
      if (ta == 'bulk') {
        // Larger packs first (by sessions, then price) so smaller fall under them.
        final sa = (a['sessions'] as num?)?.toInt() ?? 0;
        final sb = (b['sessions'] as num?)?.toInt() ?? 0;
        if (sa != sb) return sb.compareTo(sa);
        return pb.compareTo(pa);
      }
      // Monthly + per-session: cheapest first (natural upgrade path).
      return pa.compareTo(pb);
    });
  }

  /// The signed-in user's id. Signed out a write writes nothing, and returning
  /// normally read as saved (P0-FL-56b).
  String _requireSignedIn() {
    final uid = _uid;
    if (uid == null) throw StateError('Signed out — nothing was changed.');
    return uid;
  }

  /// Throws if signed out, refused, or (an edit) no row was changed.
  Future<void> savePackage({
    String? id,
    required String type,
    required String name,
    required int sessions,
    required double price,
    String? description,
    String? cancellationPolicy,
  }) async {
    final uid = _requireSignedIn();
    final payload = {
      'coach_id': uid,
      'type': type,
      'name': name,
      'sessions': sessions,
      'price': price,
      'description': description,
      'cancellation_policy': cancellationPolicy,
    };
    if (id == null) {
      await _db.from('coach_packages').insert(payload);
    } else {
      final rows = await _db
          .from('coach_packages')
          .update(payload)
          .eq('id', id)
          .select('id');
      if ((rows as List).isEmpty) throw const PackageNotChanged('savePackage');
    }
  }

  /// Deletes the package, or hides it from clients (`active: false`) when a
  /// client schedule still references it. Throws if neither was confirmed.
  ///
  /// P0-FL-56b: ANY failure of the delete (a refusal, a dropped connection)
  /// was taken for "a schedule references it" and, unrecorded, turned into a
  /// deactivation; and a delete or deactivation that matched no row read as
  /// done. Only the foreign-key refusal (23503) means "deactivate instead".
  Future<void> deletePackage(String id) async {
    final List<dynamic> deleted;
    try {
      deleted =
          await _db.from('coach_packages').delete().eq('id', id).select('id');
    } on PostgrestException catch (e) {
      if (e.code != '23503') rethrow;
      // A client schedule references it (FK) — deactivate instead.
      final hidden = await _db
          .from('coach_packages')
          .update({'active': false})
          .eq('id', id)
          .select('id');
      if ((hidden as List).isEmpty) {
        throw const PackageNotChanged('deletePackage.deactivate');
      }
      return;
    }
    if (deleted.isEmpty) throw const PackageNotChanged('deletePackage');
  }

  static const sessionTiers = [4, 8, 12, 16];

  /// The coach's current session-package tiers, keyed by session count, each
  /// with its OWN name / price / description.
  Future<Map<int, ({String name, double price, String description})>> getSessionTiers() async {
    final uid = _uid;
    if (uid == null) return {};
    final rows = await _db
        .from('coach_packages')
        .select('sessions, price, name, description')
        .eq('coach_id', uid)
        .eq('type', 'bulk');
    return {
      for (final r in rows as List)
        (r['sessions'] as num).toInt(): (
          name: r['name'] as String? ?? '',
          price: (r['price'] as num?)?.toDouble() ?? 0,
          description: r['description'] as String? ?? '',
        ),
    };
  }

  /// Saves the four session-package tiers (4/8/12/16) — each with its own
  /// name + price + description. A tier with price <= 0 is removed/deactivated.
  ///
  /// Four separate writes: stops at the first that fails. If earlier tiers were
  /// already changed it throws [SessionTiersPartlySaved] (which ones are saved,
  /// which are not); if nothing was, the failure itself. Saving again is safe:
  /// it re-reads which tiers exist.
  Future<void> saveSessionTiers(
      Map<int, ({String name, double price, String description})> tiers) async {
    final uid = _requireSignedIn();
    final existing = await _db
        .from('coach_packages')
        .select('id, sessions')
        .eq('coach_id', uid)
        .eq('type', 'bulk');
    final byTier = {
      for (final r in existing as List) (r['sessions'] as num).toInt(): r['id'] as String,
    };
    // Only the tiers that have something to write: a tier neither offered now
    // nor before is not "saved" and not "not saved".
    final todo = [
      for (final t in sessionTiers)
        if ((tiers[t]?.price ?? 0) > 0 || byTier[t] != null) t,
    ];
    final saved = <int>[];
    for (final tier in todo) {
      try {
        await _saveTier(uid, tier, tiers[tier], byTier[tier]);
      } catch (e, st) {
        if (saved.isEmpty) rethrow;
        Error.throwWithStackTrace(
            SessionTiersPartlySaved(
                saved: saved,
                notSaved: todo.sublist(saved.length),
                cause: e),
            st);
      }
      saved.add(tier);
    }
  }

  Future<void> _saveTier(
      String uid,
      int tier,
      ({String name, double price, String description})? data,
      String? id) async {
    if (data == null || data.price <= 0) {
      if (id != null) await deletePackage(id);
      return;
    }
    final payload = {
      'coach_id': uid, 'type': 'bulk', 'sessions': tier,
      'price': data.price, 'active': true,
      'name': data.name.trim().isEmpty ? '$tier-Session Pack' : data.name.trim(),
      'description': data.description.trim().isEmpty ? null : data.description.trim(),
    };
    if (id != null) {
      final rows = await _db
          .from('coach_packages')
          .update(payload)
          .eq('id', id)
          .select('id');
      if ((rows as List).isEmpty) {
        throw const PackageNotChanged('saveSessionTiers');
      }
    } else {
      await _db.from('coach_packages').insert(payload);
    }
  }

  // ── Client schedule ───────────────────────────────────────
  Future<Map<String, dynamic>?> getMySchedule() async {
    final uid = _uid;
    if (uid == null) return null;
    return await _db
        .from('client_schedules')
        .select()
        .eq('client_id', uid)
        .maybeSingle();
  }

  /// Client's onboarding-chosen training days/week (to seed the schedule).
  Future<int> getOnboardingTrainingDays() async {
    final uid = _uid;
    if (uid == null) return 0;
    final row = await _db
        .from('user_profiles')
        .select('training_days_per_week')
        .eq('id', uid)
        .maybeSingle();
    return (row?['training_days_per_week'] as num?)?.toInt() ?? 0;
  }

  /// Throws if signed out, refused, or no row came back (P0-FL-56b): the caller
  /// goes on to booking or payment, so "returned" must mean saved.
  Future<void> saveSchedule({
    required String coachId,
    String? packageId,
    required List<String> days,
    required String sessionTime,
    Map<String, String>? dayTimes,
  }) async {
    final uid = _requireSignedIn();
    final rows = await _db.from('client_schedules').upsert({
      'client_id': uid,
      'coach_id': coachId,
      'package_id': packageId,
      'days': days,
      'session_time': sessionTime,
      'day_times': dayTimes ?? {},
    }, onConflict: 'client_id').select('id');
    if ((rows as List).isEmpty) throw const PackageNotChanged('saveSchedule');
  }

  /// Coach: a specific client's schedule.
  Future<Map<String, dynamic>?> getClientSchedule(String clientId) async {
    return await _db
        .from('client_schedules')
        .select()
        .eq('client_id', clientId)
        .maybeSingle();
  }
}
