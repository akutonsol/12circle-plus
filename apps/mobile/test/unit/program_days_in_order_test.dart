import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/workout/data/program_schedule.dart';
import 'package:circle_fitness/features/workout/domain/week_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A program's training days came back in reverse.
//
// `getProgramWorkouts` read `.order('week_number').order('sort_order')`, and
// postgrest-dart's `order()` defaults to `ascending: false` — the opposite of
// the JS client (WKT-111 met the same default in `workout_service.dart`). So
// every program was read last week first and, within a week, Sunday first:
//
//   * the client's Train "This week" (`thisWeeksSessions`, which keeps the
//     order it is given) listed the week Sunday → Monday;
//   * the coach's program builder, which sorts its week headings but not the
//     days under them, listed each week's days Sunday → Monday.
//
// The builder writes `sort_order` as the day's index, Monday = 0
// (`program_builder_screen.dart`), so ascending is the week's own order.

const _uid = '00000000-0000-4000-8000-0000000001d0';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// The token is read, never verified client-side.
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

/// Answers like PostgREST, including `order=`: rows come back sorted by the
/// columns and directions the request names, as the real server sorts them.
class _Server extends http.BaseClient {
  late List<Map<String, Object?>> rows;
  late String startDate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/workout_program_assignments')) {
      return _json({
        'id': 'asg-1',
        'client_id': _uid,
        'coach_id': 'coach-a',
        'program_id': 'prog-1',
        'status': 'active',
        'start_date': startDate,
        'assigned_at': '2026-01-01T00:00:00Z',
        'workout_programs': {'duration_weeks': 2},
      }, 200, request);
    }
    if (path.endsWith('/program_workouts')) {
      return _json(_ordered(rows, request.url.queryParameters['order']), 200, request);
    }
    return _json([], 200, request);
  }

  static List<Map<String, Object?>> _ordered(
      List<Map<String, Object?>> rows, String? order) {
    final keys = [
      for (final part in (order ?? '').split(',').where((p) => p.isNotEmpty))
        (column: part.split('.')[0], asc: part.split('.')[1] == 'asc'),
    ];
    return [...rows]..sort((a, b) {
        for (final k in keys) {
          final c = (a[k.column] as Comparable).compareTo(b[k.column]);
          if (c != 0) return k.asc ? c : -c;
        }
        return 0;
      });
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

Map<String, Object?> _day(int week, String day) => {
      'id': 'w$week-$day',
      'program_id': 'prog-1',
      'title': 'Week $week $day',
      'week_number': week,
      'day_of_week': day,
      'sort_order': _days.indexOf(day),
      'exercises': [],
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
    // Stored in no particular order; the read decides the order.
    server.rows = [
      _day(2, 'Wednesday'), _day(1, 'Friday'), _day(1, 'Monday'),
      _day(2, 'Monday'), _day(1, 'Wednesday'), _day(1, 'Sunday'),
    ];
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    server.startDate =
        '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  });

  test('a program is read week by week, each week Monday first', () async {
    final rows = await CoachProgramService().getProgramWorkouts('prog-1');
    expect(rows.map((r) => r['title']), [
      'Week 1 Monday', 'Week 1 Wednesday', 'Week 1 Friday', 'Week 1 Sunday',
      'Week 2 Monday', 'Week 2 Wednesday',
    ], reason: 'THE defect: postgrest-dart orders descending when `ascending` '
        'is omitted, so this read week 2 Wednesday first and Week 1 Sunday '
        'before Week 1 Monday');
  });

  test("the client's This week runs Monday to Sunday", () async {
    final program = await CoachProgramService().getMyAssignedProgram();
    final week = thisWeeksSessions(assignedProgramToWorkouts(program!));
    expect(week.map((w) => w.title), [
      'Week 1 Monday', 'Week 1 Wednesday', 'Week 1 Friday', 'Week 1 Sunday',
    ]);
  });

  test('control: this week holds only this week, whatever the order', () async {
    final program = await CoachProgramService().getMyAssignedProgram();
    final week = thisWeeksSessions(assignedProgramToWorkouts(program!));
    expect(week.map((w) => w.title).toSet(), {
      'Week 1 Monday', 'Week 1 Wednesday', 'Week 1 Friday', 'Week 1 Sunday',
    });
  });
}
