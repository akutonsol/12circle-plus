import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/class_model.dart';

class LiveClassService {
  final _db = Supabase.instance.client;

  /// Upcoming and in-progress classes.
  ///
  /// **F-15/F-16: the error propagates.** This used to end
  /// `catch (_) { return []; }`, so a failed read arrived at the screen as an
  /// empty list and `/classes` said there were none. FIT-027 reports a failed
  /// source separately from an empty one, and it can only do that if the
  /// failure survives the service.
  Future<List<FitnessClass>> getUpcomingClasses() async {
    {
      final uid = _db.auth.currentUser?.id;
      // Include classes that started up to 4h ago so in-progress (live) ones
      // still surface; the mapping derives live/upcoming/completed from time.
      // `scheduled_at` is timestamptz: "4h ago" goes out as a UTC instant (a
      // zoneless local time is read as UTC), and the 40 kept are the SOONEST —
      // postgrest-dart's `order()` is descending unless told otherwise, so the
      // limit kept the 40 furthest and dropped today's classes.
      final from = DateTime.now().subtract(const Duration(hours: 4)).toUtc();
      final data = await _db
          .from('classes')
          .select('*, public_profiles!coach_id(id, first_name, last_name, avatar_url)')
          .eq('status', 'scheduled')
          .gte('scheduled_at', from.toIso8601String())
          .order('scheduled_at', ascending: true)
          .limit(40);

      if ((data as List).isEmpty) return [];

      List<Map<String, dynamic>> myBookings = [];
      if (uid != null) {
        myBookings = List<Map<String, dynamic>>.from(
          await _db.from('class_bookings').select('class_id, status').eq('user_id', uid)
              .inFilter('status', ['confirmed', 'waitlisted']));
      }
      final bookedIds = {
        for (final b in myBookings)
          if (b['status'] == 'confirmed') b['class_id'] as String
      };
      final waitlistedIds = {
        for (final b in myBookings)
          if (b['status'] == 'waitlisted') b['class_id'] as String
      };

      return data.map<FitnessClass>((c) => _mapRow(c, bookedIds, waitlistedIds)).toList();
    }
  }

  /// Classes the current user has registered for (confirmed or waitlisted).
  Future<List<FitnessClass>> getMyBookings() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return [];
      final rows = await _db
          .from('class_bookings')
          .select('status, classes!inner(*, public_profiles!coach_id(id, first_name, last_name, avatar_url))')
          .eq('user_id', uid)
          .inFilter('status', ['confirmed', 'waitlisted'])
          .order('booked_at', ascending: false);
      return (rows as List).map<FitnessClass>((r) {
        final c = Map<String, dynamic>.from(r['classes'] as Map);
        final id = c['id'] as String;
        final confirmed = r['status'] == 'confirmed';
        return _mapRow(c, confirmed ? {id} : <String>{}, confirmed ? <String>{} : {id});
      }).toList();
    } catch (_) {
      return [];
    }
  }

  FitnessClass _mapRow(Map<String, dynamic> c, Set<String> bookedIds, Set<String> waitlistedIds) {
    final coach = c['public_profiles'] as Map<String, dynamic>? ?? {};
    final coachName = '${coach['first_name'] ?? ''} ${coach['last_name'] ?? ''}'.trim();
    final enrolled = c['current_enrolled'] as int? ?? 0;
    final max = c['max_capacity'] as int? ?? 20;
    final classId = c['id'] as String;
    // The stored instant, in the viewer's own zone: cards, the detail screen
    // and the coach's list print its hour and day, and live/upcoming compare it
    // with `now`.
    final start = DateTime.parse(c['scheduled_at'] as String).toLocal();
    final mins = c['duration_minutes'] as int? ?? 60;
    final end = start.add(Duration(minutes: mins));
    final now = DateTime.now();
    // Derive live/completed from the schedule so the Live tab is accurate.
    final status = now.isAfter(end) ? ClassStatus.completed
        : (now.isAfter(start) ? ClassStatus.live : ClassStatus.upcoming);
    return FitnessClass(
      id: classId,
      title: c['title'] as String,
      description: c['description'] as String? ?? '',
      category: _parseCategory(c['type'] as String? ?? 'hiit'),
      status: status,
      startTime: start,
      durationMinutes: mins,
      capacity: max,
      bookedCount: enrolled,
      waitlistCount: 0,
      instructor: ClassInstructor(
        id: coach['id'] as String? ?? '',
        name: coachName.isEmpty ? 'Coach' : coachName,
        role: 'Coach',
        rating: 4.9,
      ),
      location: c['location'] as String? ?? (c['is_online'] == true ? 'Online' : 'Studio'),
      isVirtual: c['is_online'] as bool? ?? false,
      streamUrl: c['meeting_link'] as String?,
      isBooked: bookedIds.contains(classId),
      isWaitlisted: waitlistedIds.contains(classId),
      tags: const [],
      price: (c['price'] as num?)?.toDouble(),
    );
  }

  /// Asks for a seat and returns what the server gave: 'confirmed', or
  /// 'waitlisted' when the class is full (Module 13).
  ///
  /// The seat is decided by the database (migration 188), where every booking
  /// is visible. This used to count confirmed bookings itself -- but a client
  /// can read only its OWN bookings, so the count was 0 or 1, never "full":
  /// every booking was confirmed and classes overbooked. It also kept
  /// `classes.current_enrolled` and promoted the waitlist from here, writes RLS
  /// turns into zero-row no-ops (a client may not write the class row or
  /// another user's booking); the database now does both.
  Future<String> bookClass(String classId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return 'confirmed';
    final row = await _db.from('class_bookings').upsert({
      'class_id': classId,
      'user_id': uid,
      'status': 'confirmed',
    }, onConflict: 'class_id,user_id').select('status').single();
    return (row['status'] as String?) ?? 'confirmed';
  }

  /// Gives up the place. A freed confirmed seat is handed to the earliest
  /// waitlisted booking -- and that person told -- by the database
  /// (migration 188); the client can neither see nor write anyone else's booking.
  Future<void> cancelBooking(String classId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _db.from('class_bookings')
        .update({'status': 'cancelled'})
        .eq('class_id', classId)
        .eq('user_id', uid);
  }

  ClassCategory _parseCategory(String t) => switch (t) {
    'yoga' => ClassCategory.yoga,
    'hiit' => ClassCategory.hiit,
    'strength' => ClassCategory.strength,
    'pilates' => ClassCategory.pilates,
    'cardio' => ClassCategory.cardio,
    'boxing' => ClassCategory.boxing,
    'dance' => ClassCategory.dance,
    'meditation' => ClassCategory.meditation,
    _ => ClassCategory.hiit,
  };

  /// Coach: create a group class (online or in-person).
  Future<void> createClass({
    required String title,
    required String description,
    required String type,
    required DateTime scheduledAt,
    required int durationMinutes,
    required bool isOnline,
    String? location,
    String? meetingLink,
    int maxCapacity = 20,
    double? price,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _db.from('classes').insert({
      'coach_id': uid,
      'title': title,
      'description': description,
      'type': type,
      'is_online': isOnline,
      'location': isOnline ? 'Online' : location,
      'meeting_link': isOnline ? meetingLink : null,
      // The instant, stated as UTC: the picker's time is local, and timestamptz
      // reads a zoneless time as UTC — an 18:00 class in New York was stored as
      // 13:00 there, went "Live" five hours early and showed 13:00 in What's On.
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'duration_minutes': durationMinutes,
      'max_capacity': isOnline ? 9999 : maxCapacity,
      'current_enrolled': 0,
      'status': 'scheduled',
      'price': price,
    });
  }

  /// Coach: cancel a class they own (drops it from listings + frees seats).
  Future<void> cancelClass(String classId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _db.from('classes')
        .update({'status': 'cancelled'})
        .eq('id', classId)
        .eq('coach_id', uid);
  }

  /// Coach: classes they have created (upcoming first).
  Future<List<FitnessClass>> getMyCreatedClasses() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return [];
      final data = await _db
          .from('classes')
          .select('*, public_profiles!coach_id(id, first_name, last_name, avatar_url)')
          .eq('coach_id', uid)
          .neq('status', 'cancelled')
          // Upcoming first, stated: a bare `order()` is descending.
          .order('scheduled_at', ascending: true);
      return (data as List)
          .map<FitnessClass>((c) => _mapRow(Map<String, dynamic>.from(c), {}, {}))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
