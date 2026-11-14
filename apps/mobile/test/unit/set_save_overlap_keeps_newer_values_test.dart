import 'dart:convert';

import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The active workout screen saves a set on every edit and again on confirm, and
// does not await either (`_persistSet` is fire-and-forget). saveSetLog was an
// update-then-insert on the set's identity (session_id, set_id), so two saves of
// one set overlapped: both UPDATEs found no row, both INSERTed, and the later
// INSERT hit the unique index (uq_workout_set_logs_set_identity, 23505). Its
// values were lost -- usually the confirmation (completed = true) -- and the
// client was told "Could not save set." After a resume the set was unconfirmed,
// and the records, which count confirmed sets only, ignored it.
//
// The fake is the table: a unique (session_id, set_id), PATCH answering the rows
// it changed, POST answering 409/23505 on a duplicate -- with every response
// delayed, so two un-awaited saves interleave as they do on a device.
//
// HOW TO SEE IT FAIL: on main the second save throws 23505 and the stored row
// keeps the first save's values (completed = false).

const _uid = '00000000-0000-4000-8000-0000000005e7';

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

/// workout_set_logs, keyed by its unique (session_id, set_id).
class _Table extends http.BaseClient {
  final Map<String, Map<String, Object?>> rows = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final q = request.url.queryParameters;
    Object? body = [];
    var status = 200;
    if (request.url.path.endsWith('/workout_set_logs')) {
      final text = await request.finalize().bytesToString();
      if (request.method == 'PATCH') {
        final key = '${q['session_id']!.substring(3)}/${q['set_id']!.substring(3)}';
        final row = rows[key];
        if (row != null) row.addAll(Map<String, Object?>.from(jsonDecode(text) as Map));
        body = row == null ? [] : [{'id': row['id']}];
      } else if (request.method == 'POST') {
        final r = Map<String, Object?>.from(jsonDecode(text) as Map);
        final key = '${r['session_id']}/${r['set_id']}';
        if (rows.containsKey(key)) {
          status = 409;
          body = {'code': '23505', 'details': null, 'hint': null,
                  'message': 'duplicate key value violates unique constraint "uq_workout_set_logs_set_identity"'};
        } else {
          rows[key] = {...r, 'id': 'row-${rows.length + 1}'};
          status = 201;
          body = null;
        }
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  final table = _Table();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: table,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(table.rows.clear);

  Future<void> save(WorkoutService svc, {required int reps, required bool completed}) =>
      svc.saveSetLog(
        sessionId: 'session-1', exerciseName: 'Bench Press', exerciseInstanceId: 'ex-1',
        setId: 'set-1', setNumber: 1, reps: reps, weightKg: 60, completed: completed);

  test('an edit and a confirm fired together both land, the confirm last', () async {
    final svc = WorkoutService();
    // Fired as the screen fires them: neither awaited before the other starts.
    final edit = save(svc, reps: 8, completed: false);
    final confirm = save(svc, reps: 10, completed: true);
    await expectLater(Future.wait([edit, confirm]), completes,
        reason: 'THE defect: the second save failed 23505 and the client was told '
            '"Could not save set."');
    expect(table.rows, hasLength(1), reason: 'one row per set identity');
    final row = table.rows.values.single;
    expect(row['completed'], isTrue, reason: 'the confirmation was the save that was lost');
    expect(row['reps'], 10, reason: 'the newer values win');
  });

  test('a row another writer created mid-save is updated, not a failure', () async {
    // Another device (or a restore) inserted the set between this save's update
    // and its insert.
    table.rows['session-1/set-1'] = {
      'id': 'row-x', 'session_id': 'session-1', 'set_id': 'set-1', 'reps': 5, 'completed': false,
    };
    final svc = WorkoutService();
    final late = _LateRow(table);
    await late.run(() => save(svc, reps: 12, completed: true));
    expect(table.rows.values.single['reps'], 12);
    expect(table.rows.values.single['completed'], isTrue);
  });
}

/// Makes the first PATCH miss (as if the row did not exist yet) while the row is
/// already there for the INSERT -- the interleaving of a second writer.
class _LateRow {
  _LateRow(this.table);
  final _Table table;
  Future<void> run(Future<void> Function() body) async {
    final held = Map<String, Map<String, Object?>>.from(table.rows);
    table.rows.clear();
    final f = body();
    await Future<void>.delayed(const Duration(milliseconds: 25)); // after the PATCH
    table.rows.addAll(held);
    await f;
  }
}
