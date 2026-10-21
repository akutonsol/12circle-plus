import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/class_model.dart';
import '../../notifications/data/notification_service.dart';

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
      final from = DateTime.now().subtract(const Duration(hours: 4));
      final data = await _db
          .from('classes')
          .select('*, public_profiles!coach_id(id, first_name, last_name, avatar_url)')
          .eq('status', 'scheduled')
          .gte('scheduled_at', from.toIso8601String())
          .order('scheduled_at')
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
    final start = DateTime.parse(c['scheduled_at'] as String);
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

  /// Books a class, honouring capacity limits. If the class is full the
  /// booking is placed on the waitlist instead of confirmed (Module 13).
  /// Returns the resulting status: 'confirmed' or 'waitlisted'.
  Future<String> bookClass(String classId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return 'confirmed';

    // Determine capacity and current confirmed count.
    final cls = await _db.from('classes')
        .select('max_capacity').eq('id', classId).maybeSingle();
    final maxCapacity = (cls?['max_capacity'] as int?) ?? 20;
    final confirmed = await _confirmedCount(classId);

    final status = confirmed >= maxCapacity ? 'waitlisted' : 'confirmed';
    await _db.from('class_bookings').upsert({
      'class_id': classId,
      'user_id': uid,
      'status': status,
    }, onConflict: 'class_id,user_id');

    await _syncEnrollment(classId);
    return status;
  }

  Future<void> cancelBooking(String classId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    await _db.from('class_bookings')
        .update({'status': 'cancelled'})
        .eq('class_id', classId)
        .eq('user_id', uid);
    // Free seat → promote the earliest waitlisted booking to confirmed.
    await _promoteFromWaitlist(classId);
    await _syncEnrollment(classId);
  }

  Future<int> _confirmedCount(String classId) async {
    final rows = await _db.from('class_bookings')
        .select('user_id').eq('class_id', classId).eq('status', 'confirmed');
    return (rows as List).length;
  }

  /// Recompute current_enrolled for a single class from confirmed bookings.
  Future<void> _syncEnrollment(String classId) async {
    final count = await _confirmedCount(classId);
    await _db.from('classes')
        .update({'current_enrolled': count})
        .eq('id', classId);
  }

  /// Promote the oldest waitlisted booking to confirmed if capacity allows.
  Future<void> _promoteFromWaitlist(String classId) async {
    final cls = await _db.from('classes')
        .select('max_capacity').eq('id', classId).maybeSingle();
    final maxCapacity = (cls?['max_capacity'] as int?) ?? 20;
    if (await _confirmedCount(classId) >= maxCapacity) return;
    final next = await _db.from('class_bookings')
        .select('id, user_id')
        .eq('class_id', classId)
        .eq('status', 'waitlisted')
        .order('booked_at', ascending: true)
        .limit(1)
        .maybeSingle();
    if (next == null) return;
    await _db.from('class_bookings')
        .update({'status': 'confirmed'}).eq('id', next['id']);
    await NotificationService().notifyUser(
      recipientId: next['user_id'] as String,
      type: 'class',
      title: 'You\'re In!',
      body: 'A spot opened up — your class booking is now confirmed.',
    );
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
      'scheduled_at': scheduledAt.toIso8601String(),
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
          .order('scheduled_at');
      return (data as List)
          .map<FitnessClass>((c) => _mapRow(Map<String, dynamic>.from(c), {}, {}))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
