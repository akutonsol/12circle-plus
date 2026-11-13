import 'dart:convert';

import 'package:circle_fitness/features/progress/presentation/progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
    if (path.endsWith('/body_measurements')) return _rows(const [], request);
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

  /// The screen keeps an animation running, so it never settles: let the reads
  /// and the tab change finish instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ProgressScreen())));
    await settle(tester);
  }

  /// Unmounts the screen and lets the scaffold's bell-shake timer run out.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  double leftOf(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dx;

  testWidgets('the weight chart reads oldest to latest, left to right',
      (tester) async {
    await open(tester);
    expect(find.text('Weight History'), findsOneWidget,
        reason: 'guard the premise: the chart is on screen');
    // The chart's own date labels, one per weigh-in here.
    for (final l in ['Jan 15', 'Feb 15', 'Mar 15']) {
      expect(find.text(l), findsOneWidget, reason: 'chart label $l');
    }
    expect(leftOf(tester, 'Jan 15'), lessThan(leftOf(tester, 'Feb 15')));
    expect(leftOf(tester, 'Feb 15'), lessThan(leftOf(tester, 'Mar 15')),
        reason: 'the latest weigh-in is the right end of the chart');
    await close(tester);
  });

  testWidgets('the chart is handed the weigh-ins oldest first, so its end dot '
      'is the latest', (tester) async {
    await open(tester);
    final paint = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .firstWhere((p) => p.runtimeType.toString() == '_WeightChartPainter');
    // `points.last` is where the end dot is drawn.
    final logs = (paint as dynamic).logs as List<Map<String, dynamic>>;
    expect(logs.map((l) => l['weight_kg']), [90.0, 85.0, 80.0]);
    await close(tester);
  });

  testWidgets('Recent History still lists the latest first (control)',
      (tester) async {
    await open(tester);
    final kg = tester.widgetList<Text>(find.textContaining(' kg'))
        .map((t) => t.data)
        .where((d) => d != null && RegExp(r'^\d+\.\d kg$').hasMatch(d))
        .toList();
    expect(kg.take(3), ['80.0 kg', '85.0 kg', '90.0 kg']);
    await close(tester);
  });

  testWidgets('Visual Comparison shows the LATEST progress photo as the latest',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Measurements'));
    await settle(tester);
    expect(find.text('Visual Comparison'), findsOneWidget,
        reason: 'guard the premise: the comparison is on screen');
    final urls = tester.widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<NetworkImage>()
        .map((n) => n.url)
        .toList();
    expect(urls.where((u) => u.contains('gallery_202603')), isNotEmpty,
        reason: 'March is the latest photo');
    expect(urls.where((u) => u.contains('gallery_202601')), isEmpty,
        reason: 'January is the oldest, not the latest');
    await close(tester);
  });
}
