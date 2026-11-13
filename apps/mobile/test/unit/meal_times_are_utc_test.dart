import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/home/presentation/home_screen.dart';
import 'package:circle_fitness/features/nutrition/data/nutrition_service.dart';
import 'package:circle_fitness/features/nutrition/domain/meal_row.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A meal's time was written as local wall time with no zone.
//
// `nutrition_logs.logged_at` is timestamptz (006). `logMeal` sent
// `DateTime.now().toIso8601String()` — local time, no zone — and Postgres reads a
// zoneless time as UTC. So a breakfast logged at 07:20 in New York was stored as
// 07:20 UTC, the moment 02:20 New York. Every reader that turns the stored instant
// back into local time then showed it shifted by the offset:
//
//   * the meal board's `mealTime()` (`Breakfast · 02:20` for a 07:20 breakfast);
//   * Home's 7-day bars and check-in compliance (an early meal on the day before).
//
// The day/week windows were built the same zoneless way, so "today" was midnight
// to midnight UTC, not the user's day. Both now go out as UTC instants.
//
// HOW TO SEE IT FAIL: the wire-format tests fail on the old code in any zone (the
// strings carried no zone). The round-trip tests need an offset: run with
// `TZ=America/New_York` or `TZ=Asia/Tokyo`. Under UTC they agree and pass anyway.

const _uid = '00000000-0000-4000-8000-0000000000e1';

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

/// Postgres's reading of a timestamptz literal: no zone means UTC (the server's
/// TimeZone).
DateTime _asPostgres(String v) {
  final zoned = v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);
  return DateTime.parse(zoned ? v : '${v}Z').toUtc();
}

/// What PostgREST returns for a timestamptz: the UTC instant with `+00:00`.
String _asReturned(DateTime utc) =>
    '${utc.toIso8601String().replaceAll('Z', '')}+00:00';

/// Answers like PostgREST for `nutrition_logs` and `coaching_calls`, storing and
/// filtering the timestamp columns the way Postgres does.
class _Server extends http.BaseClient {
  final List<Map<String, Object?>> meals = [];
  final List<Map<String, Object?>> calls = [];
  final List<String> mealFilters = [];
  final List<String> insertedLoggedAt = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/nutrition_logs') && request.method == 'POST') {
      final body = await request.finalize().bytesToString();
      final row = Map<String, Object?>.from(jsonDecode(body) as Map);
      final sent = row['logged_at'] as String;
      insertedLoggedAt.add(sent);
      meals.add({...row, 'logged_at': _asReturned(_asPostgres(sent))});
      return _json(null, 201, request);
    }
    if (path.endsWith('/nutrition_logs')) {
      final f = request.url.queryParametersAll['logged_at'] ?? const [];
      mealFilters.addAll(f);
      return _json(_filter(meals, 'logged_at', f), 200, request);
    }
    if (path.endsWith('/coaching_calls')) {
      return _json(
          _filter(calls, 'scheduled_at',
              request.url.queryParametersAll['scheduled_at'] ?? const []),
          200,
          request);
    }
    if (path.contains('/rpc/')) return _json(null, 200, request);
    return _json([], 200, request);
  }

  static List<Map<String, Object?>> _filter(
      List<Map<String, Object?>> rows, String col, List<String> filters) {
    return [
      for (final r in rows)
        if (filters.every((f) {
          final at = _asPostgres(r[col] as String);
          final dot = f.indexOf('.');
          final op = f.substring(0, dot);
          final bound = _asPostgres(f.substring(dot + 1));
          return switch (op) {
            'gte' => !at.isBefore(bound),
            'lt' => at.isBefore(bound),
            _ => true,
          };
        }))
          r,
    ];
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// A meal stored as Postgres stores the real instant [localAt].
Map<String, Object?> _meal(String name, DateTime localAt) => {
      'id': name,
      'user_id': _uid,
      'food_name': name,
      'meal_type': 'breakfast',
      'calories': 100,
      'protein': 10,
      'carbs': 10,
      'fat': 5,
      'logged_at': _asReturned(localAt.toUtc()),
    };

bool _zoned(String v) => v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);

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
    server.meals.clear();
    server.calls.clear();
    server.mealFilters.clear();
    server.insertedLoggedAt.clear();
  });

  test('a logged meal is sent as a UTC instant, not zoneless local time', () async {
    final before = DateTime.now().toUtc();
    await NutritionService().logMeal(
      mealType: 'breakfast', foodName: 'Oats', calories: 300, protein: 10,
      carbs: 50, fat: 6, servingSize: 80, servingUnit: 'g');
    final sent = server.insertedLoggedAt.single;
    expect(_zoned(sent), isTrue,
        reason: 'THE defect: `$sent` has no zone, so Postgres stores it as UTC '
            'and the meal is recorded at the wrong moment');
    expect(_asPostgres(sent).difference(before).inSeconds.abs(), lessThan(60));
  });

  test('a meal logged now reads back at the local time it was logged', () async {
    final now = DateTime.now();
    await NutritionService().logMeal(
      mealType: 'breakfast', foodName: 'Oats', calories: 300, protein: 10,
      carbs: 50, fat: 6, servingSize: 80, servingUnit: 'g');
    final logs = await NutritionService().getTodayLogs();
    expect(logs, hasLength(1),
        reason: 'the meal just logged is part of today');
    final shown = mealTime(DateTime.tryParse('${logs.single['logged_at']}'));
    final expected = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    // A minute boundary may pass between `now` and the write.
    final later = now.add(const Duration(minutes: 1));
    final alsoOk = '${later.hour.toString().padLeft(2, '0')}:'
        '${later.minute.toString().padLeft(2, '0')}';
    expect(shown, anyOf(expected, alsoOk),
        reason: 'the board showed the time shifted by the UTC offset '
            '(offset here: ${now.timeZoneOffset}, TZ=${Platform.environment['TZ']})');
  });

  test("today's window is the user's own midnight, sent as zoned instants", () async {
    await NutritionService().getTodayLogs();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final gte = server.mealFilters.firstWhere((f) => f.startsWith('gte.'));
    final lt = server.mealFilters.firstWhere((f) => f.startsWith('lt.'));
    expect(_zoned(gte.substring(4)), isTrue, reason: 'zoneless bound `$gte` is read as UTC');
    expect(_zoned(lt.substring(3)), isTrue, reason: 'zoneless bound `$lt` is read as UTC');
    expect(_asPostgres(gte.substring(4)), midnight.toUtc());
    expect(_asPostgres(lt.substring(3)),
        DateTime(now.year, now.month, now.day + 1).toUtc());
  });

  test("today's meals are today's in the user's zone, totals included", () async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    server.meals.addAll([
      _meal('late-last-night', midnight.subtract(const Duration(minutes: 30))),
      _meal('just-after-midnight', midnight.add(const Duration(minutes: 30))),
    ]);
    final logs = await NutritionService().getTodayLogs();
    expect(logs.map((m) => m['food_name']), ['just-after-midnight']);
    final totals = await NutritionService().getTodayTotals();
    expect(totals['calories'], 100);
    final yesterday = await NutritionService()
        .getLogsForDate(midnight.subtract(const Duration(days: 1)));
    expect(yesterday.map((m) => m['food_name']), ['late-last-night']);
  });

  test("Home's week runs Monday to Sunday in the user's zone", () async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    server.meals.addAll([
      // Last Sunday at 21:00 — last week; must not light any bar of this week.
      _meal('last-sunday-evening', DateTime(monday.year, monday.month, monday.day - 1, 21)),
      // This Monday at 08:00 — this week's Monday bar.
      _meal('monday-morning', DateTime(monday.year, monday.month, monday.day, 8)),
    ]);
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(Supabase.instance.client.auth.currentUser),
    ]);
    addTearDown(c.dispose);
    final bars = await c.read(weeklyActivityProvider.future);
    expect(bars[0], 1.0, reason: "Monday's meal lights Monday");
    expect(bars.sublist(1).every((b) => b == 0.05), isTrue,
        reason: "last Sunday's meal leaked into this week's Sunday (west of UTC) — $bars");
  });

  test('guard: no logged_at bound in lib/ goes out zoneless', () {
    final offenders = <String>[];
    final zoneless = RegExp(
        r"\.(gte|gt|lte|lt)\('logged_at',\s*[A-Za-z_.]+\.toIso8601String\(\)");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (zoneless.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'a timestamptz bound needs `.toUtc()` before `.toIso8601String()`');
  });
}
