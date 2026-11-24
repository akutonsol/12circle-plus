import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/onboarding/presentation/intake_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/pump_until.dart';

// P0-FL-53c · Intake progress photos: the picker says when it fails.
//
// `_PhotoUploadCardState._pick` wrapped the picker in `catch (_) { … }` (an
// inner `catch (_) {}` on the desktop-web fallback). Permission denied, no
// camera, or a picked file that could not be read: the button silently did
// nothing, and nothing was recorded.
//
// Now each failure is recorded with reportError under its own origin and the
// card says so — "Couldn't open your photos — allow photo access in
// Settings, then try again." for a permission denial, the generic next step
// otherwise — with a busy-aware Try again. A photo the card already had is
// kept. CANCELLING the picker (it returns null) is legitimate absence: no
// message, no report.
//
// The desktop-web camera → gallery fallback is `kIsWeb`-only (a compile-time
// constant) and cannot run in a VM widget test; its origin is
// `intake.photos.pick.webGalleryFallback`.
//
// HOW TO SEE IT FAIL: run against b7ec6ef's intake_flow_screen.dart.

const _uid = '00000000-0000-4000-8000-0000000f1053';

const _photosPage = 21; // PageView index of the Progress Photos step

const _generic = 'try again in a moment. If it keeps happening, contact support.';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
          1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({
        'sub': _uid,
        'role': 'authenticated',
        'exp': exp,
        'aud': 'authenticated'
      })}.'
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

/// The stored answers park the flow on Progress Photos; no earlier uploads.
class _Server extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.contains('/auth/v1/')) {
      return _json({'error': 'offline'}, 400, request);
    }
    if (path.startsWith('/storage/')) {
      return _json({
        'statusCode': '404',
        'error': 'not_found',
        'message': 'Object not found'
      }, 400, request);
    }
    if (path == '/rest/v1/user_profiles') {
      if (request.method == 'GET') {
        final profile = {'id': _uid, 'onboarding_step': _photosPage};
        final single =
            request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
        return _json(single ? profile : [profile], 200, request);
      }
      return request.url.queryParameters.containsKey('select')
          ? _json([
              {'id': _uid}
            ], 200, request)
          : http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// How the next pickImage call is answered.
typedef _Answer = Future<Object?> Function(MethodCall call);

void main() {
  late Directory tmp;
  late String photoPath;
  final reported = <AppFailure>[];
  final calls = <String>[];
  late _Answer answer;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Server(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
    tmp = Directory.systemTemp.createTempSync('intake_picker_test');
    photoPath = '${tmp.path}/photo.png';
    File(photoPath).writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhf'
        'DwAChwGA60e6kgAAAABJRU5ErkJggg=='));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (call) async {
      final source = (call.arguments as Map)['source'];
      calls.add('${call.method}:$source');
      return answer(call);
    });
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUp(() {
    reported.clear();
    calls.clear();
    answer = (_) async => photoPath;
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  double page(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!;

  Future<void> openPhotos(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: IntakeFlowScreen()),
    ));
    await settle(tester);
    expect(page(tester), _photosPage.toDouble(),
        reason: 'premise: the flow opened on Progress Photos');
    expect(find.text('Continue'), findsOneWidget,
        reason: 'premise: no photo yet');
  }

  /// Opens [label]'s sheet and taps [row]; settles the picker call.
  Future<void> pick(WidgetTester tester, String label,
      {String row = 'Choose from Library'}) async {
    await tester.tap(find.text(label));
    await settle(tester);
    await tester.tap(find.text(row));
    await settle(tester);
  }

  Finder tryAgain() => find.widgetWithText(OutlinedButton, 'Try again');

  Finder liveRegionOver(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false)));

  testWidgets(
      'photo access denied: the card says to allow photo access in Settings, '
      'the failure is recorded, nothing is picked', (tester) async {
    await openPhotos(tester);
    answer = (_) async => throw PlatformException(
        code: 'photo_access_denied',
        message: 'The user did not allow photo access.');
    await pick(tester, 'Front Photo');

    const msg = "Couldn't open your photos — allow photo access in Settings, "
        'then try again.';
    expect(find.text(msg), findsOneWidget,
        reason: 'THE defect: a denied picker did nothing and said nothing');
    expect(liveRegionOver(msg), findsWidgets,
        reason: 'the notice is a live region');
    expect(find.textContaining('did not allow'), findsNothing,
        reason: 'no raw platform text');
    expect(reported.map((f) => f.origin), ['intake.photos.pick.gallery']);
    expect(find.text('Continue'), findsOneWidget,
        reason: 'a failed pick is not a photo');
  });

  testWidgets(
      'camera access denied: the camera wording, its own origin',
      (tester) async {
    await openPhotos(tester);
    answer = (_) async => throw PlatformException(code: 'camera_access_denied');
    await pick(tester, 'Side Photo', row: 'Take Photo');

    expect(
        find.text("Couldn't open your camera — allow camera access in "
            'Settings, then try again.'),
        findsOneWidget);
    expect(reported.map((f) => f.origin), ['intake.photos.pick.camera']);
    expect(calls, ['pickImage:0'],
        reason: 'off the web there is no gallery fallback');
  });

  testWidgets(
      'any other picker failure: the generic next step; a 44px labelled Try '
      'again re-opens the SAME source and the photo then counts; the notice '
      'goes', (tester) async {
    await openPhotos(tester);
    answer = (_) async => throw PlatformException(code: 'no_available_camera');
    await pick(tester, 'Back Photo', row: 'Take Photo');

    final msg = "Couldn't open your camera — $_generic";
    expect(find.text(msg), findsOneWidget);
    expect(reported.map((f) => f.origin), ['intake.photos.pick.camera']);
    expect(tester.getSize(tryAgain()).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('Try again'), findsOneWidget);

    // Positive control on retry: the camera now works.
    answer = (_) async => photoPath;
    calls.clear();
    await tester.tap(tryAgain());
    await pumpUntil(
        tester, () => find.text('Continue (1/3)').evaluate().isNotEmpty,
        what: 'the retried pick to be read and counted');
    expect(calls, ['pickImage:0'], reason: 'Try again re-opens the camera');
    expect(find.text(msg), findsNothing);
    expect(reported, hasLength(1), reason: 'the retry reported nothing new');
  });

  testWidgets(
      'a second pick while one is in flight (Try again, then the card) opens '
      'no second picker', (tester) async {
    await openPhotos(tester);
    answer = (_) async => throw PlatformException(code: 'boom');
    await pick(tester, 'Front Photo');
    expect(tryAgain(), findsOneWidget, reason: 'premise: the pick failed');

    final gate = Completer<Object?>();
    answer = (_) => gate.future;
    calls.clear();
    await tester.tap(tryAgain());
    await tester.pump();
    expect(tryAgain(), findsNothing,
        reason: 'the notice describes the last attempt; a new one is running');
    await pick(tester, 'Front Photo');
    expect(calls, hasLength(1), reason: 'one picker, not two');
    gate.complete(null); // the person cancels
    await settle(tester);
    expect(calls, hasLength(1));
  });

  testWidgets(
      'a picked file that cannot be read: "Couldn\'t use that photo", its own '
      'origin, and the photo the card ALREADY had is kept', (tester) async {
    await openPhotos(tester);
    await pick(tester, 'Front Photo');
    await pumpUntil(
        tester, () => find.text('Continue (1/3)').evaluate().isNotEmpty,
        what: 'the first photo to be read and counted');
    expect(find.text('Tap to change'), findsOneWidget,
        reason: 'premise: the front card shows its preview');

    answer = (_) async => '${tmp.path}/vanished.png';
    await tester.tap(find.text('Front Photo'));
    await settle(tester);
    await tester.tap(find.text('Choose from Library'));
    await pumpUntil(tester,
        () => find.textContaining("Couldn't use that photo").evaluate().isNotEmpty,
        what: 'the unreadable pick to be reported');

    expect(find.text("Couldn't use that photo — $_generic"), findsOneWidget);
    expect(reported.map((f) => f.origin), ['intake.photos.read']);
    expect(find.text('Continue (1/3)'), findsOneWidget,
        reason: 'the earlier photo still counts');
    expect(find.text('Tap to change'), findsOneWidget,
        reason: 'the earlier preview is kept');
    expect(find.textContaining('vanished'), findsNothing,
        reason: 'no raw file-system text');
  });

  testWidgets(
      'NEGATIVE CONTROL: cancelling the picker is not a failure — no message, '
      'no report, nothing changes', (tester) async {
    await openPhotos(tester);
    answer = (_) async => null;
    await pick(tester, 'Front Photo');
    await pick(tester, 'Side Photo', row: 'Take Photo');

    expect(calls, ['pickImage:1', 'pickImage:0']);
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(tryAgain(), findsNothing);
    expect(reported, isEmpty);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets(
      'POSITIVE CONTROL: a successful pick previews and counts, with no '
      'message and no report', (tester) async {
    await openPhotos(tester);
    await pick(tester, 'Front Photo');
    await pumpUntil(
        tester, () => find.text('Continue (1/3)').evaluate().isNotEmpty,
        what: 'the photo to be read and counted');
    expect(find.text('Tap to change'), findsOneWidget);
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(reported, isEmpty);
  });

  // Round 2 (UX 3) · the picker notice drew a cloud_off icon — a network
  // picture for a permission/camera/file failure. It now draws a
  // no-photography icon; the step's UPLOAD failure (a real network write)
  // keeps cloud_off.
  Finder noticeIcon(String message, IconData icon) => find.descendant(
      of: liveRegionOver(message).first,
      matching: find.byWidgetPredicate((w) => w is Icon && w.icon == icon));

  testWidgets(
      'picker failures (permission, picker, unreadable file) show a '
      'no-photography icon, not the network cloud_off', (tester) async {
    await openPhotos(tester);
    answer = (_) async => throw PlatformException(code: 'photo_access_denied');
    await pick(tester, 'Front Photo');
    const denied = "Couldn't open your photos — allow photo access in "
        'Settings, then try again.';
    expect(find.text(denied), findsOneWidget, reason: 'premise');
    expect(noticeIcon(denied, Icons.no_photography_rounded), findsOneWidget);
    expect(noticeIcon(denied, Icons.cloud_off_rounded), findsNothing,
        reason: 'not a network failure');

    answer = (_) async => throw PlatformException(code: 'no_available_camera');
    await pick(tester, 'Side Photo', row: 'Take Photo');
    final noCamera = "Couldn't open your camera — $_generic";
    expect(noticeIcon(noCamera, Icons.no_photography_rounded), findsOneWidget);
    expect(noticeIcon(noCamera, Icons.cloud_off_rounded), findsNothing);

    answer = (_) async => '${tmp.path}/vanished.png';
    await tester.tap(find.text('Back Photo'));
    await settle(tester);
    await tester.tap(find.text('Choose from Library'));
    final unreadable = "Couldn't use that photo — $_generic";
    await pumpUntil(
        tester, () => find.text(unreadable).evaluate().isNotEmpty,
        what: 'the unreadable pick to be reported');
    expect(
        noticeIcon(unreadable, Icons.no_photography_rounded), findsOneWidget);
    expect(noticeIcon(unreadable, Icons.cloud_off_rounded), findsNothing);
  });

  testWidgets(
      'CONTROL: the step\'s upload failure (a network write) keeps the '
      'cloud_off icon', (tester) async {
    await openPhotos(tester);
    await pick(tester, 'Front Photo');
    await pumpUntil(
        tester, () => find.text('Continue (1/3)').evaluate().isNotEmpty,
        what: 'the photo to be read and counted');
    expect(find.byIcon(Icons.no_photography_rounded), findsNothing,
        reason: 'a successful pick shows no picker notice');
    await tester.tap(find.text('Continue (1/3)'));
    await pumpUntil(
        tester,
        () => find
            .textContaining("Couldn't upload your photos")
            .evaluate()
            .isNotEmpty,
        what: 'the storage upload (answered 400) to fail');
    final notice = find.ancestor(
        of: find.textContaining("Couldn't upload your photos"),
        matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.liveRegion ?? false)));
    expect(
        find.descendant(
            of: notice.first,
            matching: find.byWidgetPredicate(
                (w) => w is Icon && w.icon == Icons.cloud_off_rounded)),
        findsOneWidget);
    expect(find.byIcon(Icons.no_photography_rounded), findsNothing);
  });

  testWidgets(
      'a failed pick then a cancel clears the notice (it described the last '
      'attempt) and reports nothing more', (tester) async {
    await openPhotos(tester);
    answer = (_) async => throw PlatformException(code: 'boom');
    await pick(tester, 'Front Photo');
    expect(tryAgain(), findsOneWidget);
    answer = (_) async => null;
    await pick(tester, 'Front Photo');
    expect(tryAgain(), findsNothing);
    expect(reported, hasLength(1));
  });
}
