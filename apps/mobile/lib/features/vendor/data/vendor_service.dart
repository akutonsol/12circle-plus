import 'package:supabase_flutter/supabase_flutter.dart';

/// Module 15 — Vendor Portal data access.
/// A vendor owns events (vendor_id) and can read / check-in their attendees.
/// RLS (migration 020) enforces ownership; this service just shapes the calls.
class VendorService {
  final _db = Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  /// Events owned by the signed-in vendor, with a live registration count.
  Future<List<Map<String, dynamic>>> getMyEvents() async {
    final uid = _uid;
    if (uid == null) return [];
    final data = await _db
        .from('events')
        .select('*, event_registrations(count)')
        .eq('vendor_id', uid)
        .order('event_date', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> data) async {
    final uid = _uid;
    return await _db.from('events').insert({
      ...data,
      'vendor_id': uid,
    }).select().single();
  }

  Future<void> updateEvent(String eventId, Map<String, dynamic> data) async {
    await _db.from('events').update(data).eq('id', eventId);
  }

  Future<void> deleteEvent(String eventId) async {
    await _db.from('events').delete().eq('id', eventId);
  }

  /// Attendees for one of the vendor's events (joined to their profile).
  ///
  /// P1 (migration 135, QAX-SEC-09): a vendor no longer reads `user_profiles`,
  /// so the embedded resource this method used to carry would now return
  /// nothing. `hosts_event_for()` granted the WHOLE profile row — including
  /// `parq_answers`, weight, transformation photos and billing — and 135 removes
  /// that arm from the `user_profiles` SELECT policy. The minimum-necessary
  /// columns are served by `event_attendee_profiles`, and a PostgREST embed
  /// cannot traverse a view, so this is a two-step read. The rows are re-shaped
  /// under the same `user_profiles` key the attendee list already renders, so
  /// `vendor_portal_screen` is unchanged.
  ///
  /// This narrows COLUMNS only. The event-host access LIFETIME is unchanged —
  /// `hosts_event_for()` still carries no status or expiry condition, and no
  /// owner decision authorizes bounding it (see 135's header, boundary 1).
  /// `email` is likewise preserved: whether a vendor should receive an
  /// attendee's email is an open owner question (boundary 2).
  Future<List<Map<String, dynamic>>> getRegistrations(String eventId) async {
    final registrations = List<Map<String, dynamic>>.from(await _db
        .from('event_registrations')
        // I-COM-01 · `ticket_code` DOES NOT EXIST. The column is `qr_code`
        // (`001:285`), so this read returned PostgREST 400 `42703` and the vendor
        // could not list a single registration for their own event. The member-side
        // ticket screen was corrected to `qr_code`; this site was missed.
        //
        // IT IS DROPPED RATHER THAN RENAMED, and that is the safer fix of the two.
        // Nothing consumes it — the portal reads `checked_in_at` and the attendee
        // profile, and `setCheckedIn` checks in by registration id, never by
        // scanning. Meanwhile `qr_code` is `encode(gen_random_bytes(16),'hex')`: the
        // attendee's ticket credential. Renaming would therefore hand every
        // attendee's ticket secret to a vendor payload that has no use for it — a new
        // disclosure on the one method whose stated job is to NARROW columns.
        .select('id, status, checked_in_at, registered_at, user_id')
        .eq('event_id', eventId)
        .order('registered_at') as List);
    final attendeeIds = registrations
        .map((r) => r['user_id'] as String?)
        .whereType<String>()
        .toList();
    final attendeeProfiles = attendeeIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(await _db
            .from('event_attendee_profiles')
            .select('id, first_name, last_name, email, avatar_url')
            .inFilter('id', attendeeIds) as List);
    final profileById = {
      for (final p in attendeeProfiles) p['id'] as String: p,
    };
    return [
      for (final r in registrations)
        {
          ...r,
          // Explicitly typed: `vendor_portal_screen` casts this to
          // `Map<String, dynamic>?`, and a bare `const {}` infers
          // `Map<dynamic, dynamic>`, which would throw on that cast for any
          // registration whose attendee profile RLS does not return.
          'user_profiles': profileById[r['user_id'] as String?] ??
              const <String, dynamic>{},
        },
    ];
  }

  Future<void> setCheckedIn(String registrationId, bool checkedIn) async {
    await _db.from('event_registrations').update({
      'checked_in_at': checkedIn ? DateTime.now().toIso8601String() : null,
      'status': checkedIn ? 'attended' : 'registered',
    }).eq('id', registrationId);
  }
}
