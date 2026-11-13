import 'dart:convert';

import 'package:circle_fitness/features/progress/presentation/progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Body measurements froze on the 24th entry.
//
// Progress read `body_measurements` ordered ascending with `limit(24)` and took
// `.last` as the latest. That is the 24th-OLDEST: from the 25th log on, the
// latest values, "Updated…", the waist chart and the comparison stayed on it and
// a new measurement never appeared. #76 fixed this screen's weight and photo
// reads; this one was missed.

/// Thirty monthly measurements; the waist shrinks by 0.5 cm each time, so the
/// latest (the 30th) is 85.0 cm and the 24th-oldest is 88.0 cm.
final _measures = [
  for (var i = 1; i <= 30; i++)
    {
      'id': 'm$i',
      'user_id': 'u',
      'waist_cm': 100.0 - i * 0.5,
      'chest_cm': 100.0,
      'logged_at': DateTime.utc(2024, i, 10, 12).toIso8601String(),
    },
];


// /progress reads weight logs and progress photos newest first — right for the
// "Recent History" list and the "since last entry" delta — and two places used
// those lists as if they ran oldest first:
//
//   * the Weight History chart plotted entry 0 (the LATEST) at the left edge
//     and put its end dot on the OLDEST weigh-in, with the date labels running
//     newest to oldest. Losing weight drew as gaining it.
//   * Measurements › Visual Comparison, "your first progress photo vs. your
//     latest", showed `_galleryUrls.values.lastOrNull` as the latest: the
//     OLDEST of the photos read.
//
// The fake server sorts as PostgREST does, by the `order=` the screen sends,
// so these follow the real query and not a list the test happened to write
// in the expected order.

const _uid = '00000000-0000-4000-8000-0000000b0d1e';

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

/// Three weigh-ins, falling, and three gallery photos, a month apart.
final _weights = [
  {'id': 'w1', 'weight_kg': 90.0, 'logged_at': '2026-01-15T12:00:00Z'},
  {'id': 'w2', 'weight_kg': 85.0, 'logged_at': '2026-02-15T12:00:00Z'},
  {'id': 'w3', 'weight_kg': 80.0, 'logged_at': '2026-03-15T12:00:00Z'},
];
final _photos = [
  for (final m in ['01', '02', '03'])
    {
      'id': 'p$m',
      'storage_path': '$_uid/gallery_2026$m.jpg',
      'logged_at': '2026-$m-15T12:00:00Z',
    },
];

class _Server extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.contains('/storage/v1/object/sign/')) {
      // Only the gallery uploads exist; the onboarding front/side/back probes
      // find nothing, as for a client who skipped them.
      final object = path.split('/object/sign/').last;
      if (!object.contains('gallery_')) {
        return _json({'statusCode': '404', 'error': 'not_found',
            'message': 'Object not found'}, 400, request);
      }
      return _json({'signedURL': '/object/sign/$object?token=t'}, 200, request);
    }
    if (path.endsWith('/weight_logs')) return _rows(_weights, request);
    if (path.endsWith('/progress_photo_logs')) return _rows(_photos, request);
    if (path.endsWith('/body_measurements')) return _rows(_measures, request);
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    return _json(single ? {'weight_kg': 80.0, 'weight_goal_kg': 75.0} : [],
        200, request);
  }

  /// PostgREST's `order=logged_at.desc.nullslast|asc.nullslast` and `limit=`.
  http.StreamedResponse _rows(
      List<Map<String, Object?>> rows, http.BaseRequest request) {
    final q = request.url.queryParameters;
    final sorted = [...rows]..sort((a, b) =>
        (a['logged_at'] as String).compareTo(b['logged_at'] as String));
    final order = q['order'] ?? '';
    final list = order.contains('.desc') ? sorted.reversed.toList() : sorted;
    final limit = int.tryParse(q['limit'] ?? '');
    return _json(limit == null ? list : list.take(limit).toList(), 200, request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Server(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the latest measurement is the one shown, after more than 24', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ProgressScreen())));
    await settle(tester);
    await tester.tap(find.text('Measurements'));
    await settle(tester);
    expect(find.text('85.0 cm'), findsWidgets,
        reason: 'the 30th (latest) waist is 85.0 cm');
    expect(find.text('88.0 cm'), findsNothing,
        reason: 'THE defect: ascending + limit(24) showed the 24th-oldest (88.0 cm)');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
