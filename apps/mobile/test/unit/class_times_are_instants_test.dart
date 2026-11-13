import 'dart:convert';

import 'package:circle_fitness/features/classes/data/live_class_service.dart';
import 'package:circle_fitness/features/classes/data/models/class_model.dart';
import 'package:circle_fitness/features/classes/domain/whats_on_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A class's time was stored as local wall time with no zone, read back without
// converting it, and the "upcoming" read kept the furthest classes.
//
// `classes.scheduled_at` is timestamptz (001). `createClass` wrote the picker's
// local time with no zone, which Postgres reads as UTC: an 18:00 class set in New
// York was stored as the instant 13:00 New York. `_mapRow` then compared that
// instant with `now`, so the class went "Live" (Join Live Class) five hours early
// and "Completed" while it was still to come; What's On, which converts to local,
// printed 13:00 while the card printed 18:00. Home's Upcoming panel (#89) already
// reads the column as an instant.
//
// `getUpcomingClasses` also sent "4h ago" with no zone and a bare
// `.order('scheduled_at')`, which postgrest-dart sends DESCENDING: `limit(40)`
// kept the 40 furthest classes, so with more than 40 scheduled, today's were
// never fetched. What's On's events read had the same order with `limit(30)`.
//
// HOW TO SEE IT FAIL: the wire-format and order tests fail on the old code in any
// zone; the display and status tests need an offset (TZ=America/New_York).

const _uid = '00000000-0000-4000-8000-0000000c1a55';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': _uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
      'not-verified-client-side';
}

class _SeededSession extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => jsonEncode({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 315360000,
        'refresh_token': 'test-refresh',
        'user': {
          'id': _uid,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
  @override
  Future<bool> hasAccessToken() async => true;
  @override
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async {}
}

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}


DateTime _asPostgres(String v) {
  final zoned = v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);
  return DateTime.parse(zoned ? v : '${v}Z').toUtc();
}

String _asReturned(DateTime utc) => '${utc.toIso8601String().replaceAll('Z', '')}+00:00';

bool _zoned(String v) => v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);

/// Answers like PostgREST for `classes` and `events`: applies `gte.`, `order=`
/// and `limit=` on the timestamp column the way the server does.
class _Server extends http.BaseClient {
  List<Map<String, Object?>> classes = [];
  List<Map<String, Object?>> events = [];
  final List<Map<String, Object?>> inserted = [];
  final List<Uri> reads = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/classes') && request.method == 'POST') {
      inserted.add(Map<String, Object?>.from(
          jsonDecode(await request.finalize().bytesToString()) as Map));
      return _json(null, 201, request);
    }
    if (path.endsWith('/classes')) {
      reads.add(request.url);
      return _json(_answer(classes, 'scheduled_at', request.url), 200, request);
    }
    if (path.endsWith('/events')) {
      reads.add(request.url);
      return _json(_answer(events, 'event_date', request.url), 200, request);
    }
    return _json([], 200, request);
  }

  static List<Map<String, Object?>> _answer(
      List<Map<String, Object?>> rows, String col, Uri url) {
    final f = url.queryParametersAll[col] ?? const <String>[];
    final kept = [
      for (final r in rows)
        if (f.every((x) {
          final b = _asPostgres(x.substring(x.indexOf('.') + 1));
          final at = _asPostgres(r[col] as String);
          return x.startsWith('gte.') ? !at.isBefore(b) : true;
        }))
          r,
    ];
    final asc = (url.queryParameters['order'] ?? '').contains('.asc');
    kept.sort((a, b) {
      final c = _asPostgres(a[col] as String).compareTo(_asPostgres(b[col] as String));
      return asc ? c : -c;
    });
    final limit = int.tryParse(url.queryParameters['limit'] ?? '');
    return limit == null ? kept : kept.take(limit).toList();
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// A class stored as Postgres stores the real instant [localStart].
Map<String, Object?> _class(String id, DateTime localStart, {int mins = 60}) => {
      'id': id,
      'coach_id': 'coach-a',
      'title': id,
      'description': '',
      'type': 'hiit',
      'is_online': true,
      'location': 'Online',
      'scheduled_at': _asReturned(localStart.toUtc()),
      'duration_minutes': mins,
      'max_capacity': 20,
      'current_enrolled': 0,
      'status': 'scheduled',
      'public_profiles': {'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone', 'avatar_url': null},
    };

void main() {
  late _Server server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  setUp(() {
    server.classes = [];
    server.events = [];
    server.inserted.clear();
    server.reads.clear();
  });

  test('a new class is stored at the instant the coach picked', () async {
    final picked = DateTime.now().add(const Duration(days: 2));
    final when = DateTime(picked.year, picked.month, picked.day, 18);
    await LiveClassService().createClass(
        title: 'Evening HIIT', description: '', type: 'hiit', scheduledAt: when,
        durationMinutes: 45, isOnline: true);
    final sent = server.inserted.single['scheduled_at'] as String;
    expect(_zoned(sent), isTrue,
        reason: 'THE defect: `$sent` has no zone, so Postgres stores it as UTC');
    expect(_asPostgres(sent), when.toUtc());
  });

  test("a class is shown at its start in the viewer's zone, and is upcoming", () async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + 1, 18);
    server.classes = [_class('tomorrow-18', start)];
    final c = (await LiveClassService().getUpcomingClasses()).single;
    expect(c.startTime.hour, 18, reason: 'the card prints startTime.hour');
    expect(c.startTime.day, start.day);
    expect(c.status, ClassStatus.upcoming);
  });

  test('a class that starts in two hours is not live yet', () async {
    final start = DateTime.now().add(const Duration(hours: 2));
    server.classes = [_class('in-two-hours', start, mins: 30)];
    final c = (await LiveClassService().getUpcomingClasses()).single;
    expect(c.status, ClassStatus.upcoming,
        reason: 'an unconverted instant made it "Live" hours early (west of UTC)');
  });

  test('a class under way is live', () async {
    final start = DateTime.now().subtract(const Duration(minutes: 20));
    server.classes = [_class('under-way', start, mins: 60)];
    final c = (await LiveClassService().getUpcomingClasses()).single;
    expect(c.status, ClassStatus.live);
  });

  test("the 40 kept are the soonest, so today's class is fetched", () async {
    final now = DateTime.now();
    server.classes = [
      _class('today', now.add(const Duration(hours: 1))),
      for (var d = 1; d <= 45; d++) _class('day-$d', now.add(Duration(days: d))),
    ];
    final got = await LiveClassService().getUpcomingClasses();
    expect(got.map((c) => c.id), contains('today'),
        reason: 'a bare order() is descending: limit(40) kept the furthest 40');
    final bound = server.reads.last.queryParametersAll['scheduled_at']!.single;
    expect(_zoned(bound.substring(4)), isTrue, reason: 'zoneless bound `$bound` is read as UTC');
  });

  test("the coach's own classes are listed soonest first", () async {
    final now = DateTime.now();
    server.classes = [
      _class('later', now.add(const Duration(days: 9))),
      _class('sooner', now.add(const Duration(days: 1))),
    ];
    final got = await LiveClassService().getMyCreatedClasses();
    expect(got.map((c) => c.id), ['sooner', 'later']);
  });

  test("What's On keeps the 30 soonest events", () async {
    final now = DateTime.now();
    server.events = [
      for (var d = 1; d <= 35; d++)
        {
          'id': 'e$d', 'title': 'Event $d', 'status': 'upcoming',
          'event_date': _asReturned(now.add(Duration(days: d)).toUtc()),
        },
    ];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final got = await c.read(whatsOnEventsProvider.future);
    expect(got.map((e) => e['id']), contains('e1'),
        reason: 'a bare order() is descending: limit(30) kept the furthest 30');
    final bound = server.reads.last.queryParametersAll['event_date']!.single;
    expect(_zoned(bound.substring(4)), isTrue);
  });
}
