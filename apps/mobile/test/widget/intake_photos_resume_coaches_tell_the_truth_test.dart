import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/onboarding/presentation/intake_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-19 · Intake: baseline photos, resume and the coach list tell the truth.
//
// 1. Progress photos: `_uploadAndContinue` wrapped every upload in one
//    `catch (_) {}` ("Upload errors don't block onboarding") and moved on as
//    if the photos were saved. Now each slot is uploaded on its own; any
//    failure keeps the person on the step with "Couldn't upload your photos —
//    …", what DID save, Try again (failed slots only) and an explicit
//    "Continue without photos".
// 2. Resume: a failed read of the stored answers dropped the person into a
//    BLANK flow, and the next save (a step, or backgrounding the app) wrote the
//    blanks over the stored answers. Now: "Couldn't load your answers — …"
//    with Try again, and no save of any kind until a read succeeds.
// 3. Coach list: a failed read returned [] and the coach step said "No coaches
//    available right now". Now the provider rethrows (after reportError) and
//    the step shows a failure with Try again.
//
// HOW TO SEE IT FAIL: run against 2ecd6e2's intake_flow_screen.dart and
// coach_provider.dart — the photo step moves on after failed uploads, the
// resume failure shows the blank flow and its lifecycle save PATCHes
// user_profiles, and the coach step says "No coaches available right now".

const _uid = '00000000-0000-4000-8000-0000000f1019';

const _photosPage = 21; // PageView index of the Progress Photos step
const _coachPage = 23; // PageView index of Choose Coach

const _generic = 'try again in a moment. If it keeps happening, contact support.';
const _connection = 'check your connection and try again.';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
          1000;
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

enum _Fail { none, server, network }

/// PostgREST + Storage, failing on request.
class _Server extends http.BaseClient {
  /// The stored profile (null = a successful read that finds no row).
  Map<String, Object?>? profile;
  _Fail profileRead = _Fail.none;

  /// When set, profile reads wait for it — a read "in flight".
  Completer<void>? profileGate;

  /// Upload slots ('front' / 'side' / 'back') that fail, and how.
  Set<String> failingSlots = {};
  _Fail uploadFailure = _Fail.server;

  _Fail coachesRead = _Fail.none;

  final profileReads = <String>[];
  final profilePatches = <String>[];
  final uploads = <String>[];

  void reset() {
    profile = null;
    profileRead = _Fail.none;
    profileGate = null;
    failingSlots = {};
    uploadFailure = _Fail.server;
    coachesRead = _Fail.none;
    profileReads.clear();
    profilePatches.clear();
    uploads.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = request is http.Request ? request.body : '';
    if (path.contains('/auth/v1/')) {
      return _json({'error': 'offline'}, 400, request);
    }
    // The photo step probes for earlier uploads: none exist.
    if (path.startsWith('/storage/v1/object/sign/')) {
      return _json({'statusCode': '404', 'error': 'not_found',
          'message': 'Object not found'}, 400, request);
    }
    if (path.startsWith('/storage/v1/object/progress-photos/')) {
      final slot = path.split('/').last.split('.').first;
      uploads.add(slot);
      if (failingSlots.contains(slot)) {
        if (uploadFailure == _Fail.network) {
          throw http.ClientException('Connection refused', request.url);
        }
        return _json({'statusCode': '500', 'error': 'internal',
            'message': 'refused'}, 500, request);
      }
      return _json({'Key': 'progress-photos/$_uid/$slot.png', 'Id': 'obj-$slot'},
          200, request);
    }
    if (path == '/rest/v1/user_profiles') {
      if (request.method == 'GET') {
        profileReads.add(request.url.query);
        if (profileGate != null) await profileGate!.future;
        switch (profileRead) {
          case _Fail.network:
            throw http.ClientException('Connection refused', request.url);
          case _Fail.server:
            return _json({'message': 'boom', 'code': 'XX000'}, 500, request);
          case _Fail.none:
            final single =
                request.headers['Accept']?.contains('vnd.pgrst.object') ??
                    false;
            if (profile == null) {
              return single ? _json(null, 200, request) : _json([], 200, request);
            }
            return _json(single ? profile : [profile], 200, request);
        }
      }
      profilePatches.add('${request.method} ?${request.url.query} $body');
      return request.url.queryParameters.containsKey('select')
          ? _json([{'id': _uid}], 200, request)
          : http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    if (path == '/rest/v1/public_profiles') {
      switch (coachesRead) {
        case _Fail.network:
          throw http.ClientException('Connection refused', request.url);
        case _Fail.server:
          return _json({'message': 'boom', 'code': 'XX000'}, 500, request);
        case _Fail.none:
          return _json([], 200, request);
      }
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;
  late Directory tmp;
  final reported = <AppFailure>[];

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
        detectSessionInUri: false,
      ),
      debug: false,
    );
    tmp = Directory.systemTemp.createTempSync('intake_photos_test');
    // A real 1×1 PNG: the step previews what was picked.
    final photo = File('${tmp.path}/photo.png')
      ..writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhf'
          'DwAChwGA60e6kgAAAABJRU5ErkJggg=='));
    // The gallery picker, answered through its platform channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (call) async => photo.path);
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  /// Lets real I/O (the picked file's bytes) and fake time both advance.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: IntakeFlowScreen()),
    ));
    await settle(tester);
  }

  double page(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!;

  /// One more lifecycle save, as the app losing focus fires it.
  Future<void> background(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Supabase.instance.client.auth.stopAutoRefresh();
    await settle(tester);
  }

  Finder tryAgain() => find.widgetWithText(OutlinedButton, 'Try again');

  // ── 1. Progress photos ────────────────────────────────────────────────────
  group('progress photos', () {
    Future<void> openPhotos(WidgetTester tester) async {
      server.profile = {'id': _uid, 'onboarding_step': _photosPage};
      await open(tester);
      expect(page(tester), _photosPage.toDouble(),
          reason: 'premise: the flow opened on Progress Photos');
      expect(find.text('Continue'), findsOneWidget,
          reason: 'premise: earlier uploads were probed');
    }

    Future<void> pickAll(WidgetTester tester) async {
      for (final label in ['Front Photo', 'Side Photo', 'Back Photo']) {
        await tester.tap(find.text(label));
        await settle(tester);
        await tester.tap(find.text('Choose from Library'));
        await settle(tester);
      }
      expect(find.text('Continue (3/3)'), findsOneWidget,
          reason: 'premise: three photos picked');
    }

    String notice(String nextStep) => "Couldn't upload your photos — $nextStep";

    testWidgets(
        'a partial failure keeps the person on the step, says what saved, '
        'and Try again re-sends ONLY the failed slots', (tester) async {
      await openPhotos(tester);
      await pickAll(tester);
      server.failingSlots = {'side', 'back'};
      await tester.tap(find.text('Continue (3/3)'));
      await settle(tester);

      expect(server.uploads, ['front', 'side', 'back'],
          reason: 'premise: every slot was attempted');
      expect(page(tester), _photosPage.toDouble(),
          reason: 'THE defect: the flow moved on as if the photos were saved');
      expect(find.text(notice(_generic)), findsOneWidget);
      expect(find.text('Saved: Front. Not uploaded: Side, Back.'),
          findsOneWidget, reason: 'partial success is told truthfully');
      expect(find.text('Saved · tap to replace'), findsOneWidget,
          reason: 'the slot that saved is shown as saved');
      expect(find.textContaining('refused'), findsNothing,
          reason: 'no raw error text');
      expect(reported.map((f) => f.origin).toSet(),
          {'intake.photos.upload.side', 'intake.photos.upload.back'});

      // Live region + a 44 px, labelled, busy-aware Try again.
      final live = find.ancestor(
          of: find.text(notice(_generic)),
          matching: find.byWidgetPredicate(
              (w) => w is Semantics && (w.properties.liveRegion ?? false)));
      expect(live, findsWidgets, reason: 'the notice is a live region');
      expect(tester.getSize(tryAgain()).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('Try again'), findsOneWidget);

      server.failingSlots = {};
      server.uploads.clear();
      await tester.tap(tryAgain());
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(server.uploads, ['side', 'back'],
          reason: 'the front photo already saved and is not sent again');
      expect(page(tester), (_photosPage + 1).toDouble(),
          reason: 'everything stored: the flow moves on');
    });

    testWidgets(
        'a network failure gives the connection hint; "Continue without '
        'photos" moves on explicitly without another upload', (tester) async {
      await openPhotos(tester);
      await pickAll(tester);
      server
        ..failingSlots = {'front', 'side', 'back'}
        ..uploadFailure = _Fail.network;
      await tester.tap(find.text('Continue (3/3)'));
      await settle(tester);

      expect(page(tester), _photosPage.toDouble());
      expect(find.text(notice(_connection)), findsOneWidget);
      expect(find.text('Not uploaded: Front, Side, Back.'), findsOneWidget);
      expect(find.text('Saved · tap to replace'), findsNothing);

      server.uploads.clear();
      await tester.tap(find.text('Continue without photos'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(server.uploads, isEmpty);
      expect(page(tester), (_photosPage + 1).toDouble());
    });

    testWidgets('control: uploads that all succeed move on as before',
        (tester) async {
      await openPhotos(tester);
      await pickAll(tester);
      await tester.tap(find.text('Continue (3/3)'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(server.uploads, ['front', 'side', 'back']);
      expect(find.textContaining("Couldn't upload"), findsNothing);
      expect(reported, isEmpty);
      expect(page(tester), (_photosPage + 1).toDouble());
    });
  });

  // ── 2. Resume read ────────────────────────────────────────────────────────
  group('resume read', () {
    List<String> answerSaves() => server.profilePatches
        .where((p) => p.contains('onboarding_step'))
        .toList();

    testWidgets(
        'a failed read shows a failure (not a blank flow), and NO save runs '
        'while it is unresolved — lifecycle save included', (tester) async {
      server
        ..profile = {
          'id': _uid,
          'onboarding_step': 1,
          'first_name': 'Ana',
          'last_name': 'Lee',
        }
        ..profileRead = _Fail.server;
      await open(tester);

      expect(find.text("Couldn't load your answers — $_generic"),
          findsOneWidget);
      expect(find.byType(PageView), findsNothing,
          reason: 'THE defect: the flow was shown blank at step 0');
      expect(reported.map((f) => f.origin), contains('intake.loadProgress.read'));
      expect(find.textContaining('boom'), findsNothing,
          reason: 'no raw error text');

      await background(tester);
      expect(answerSaves(), isEmpty,
          reason: 'THE data loss: a save now writes blank answers over the '
              'stored ones:\n${answerSaves().join('\n')}');

      // Busy-aware Try again: one read in flight, a second tap does nothing.
      server
        ..profileRead = _Fail.none
        ..profileGate = Completer<void>();
      final readsBefore = server.profileReads.length;
      await tester.tap(tryAgain());
      await tester.pump();
      expect(find.text('Trying again…'), findsOneWidget);
      await tester.tap(find.text('Trying again…'), warnIfMissed: false);
      await tester.pump();
      expect(server.profileReads.length, readsBefore + 1,
          reason: 'no double fire');
      server.profileGate!.complete();
      await settle(tester);

      expect(find.byType(PageView), findsOneWidget,
          reason: 'a successful read restores the flow');
      expect(page(tester), 1.0, reason: 'at the stored step');
      expect(answerSaves(), isEmpty,
          reason: 'restoring wrote nothing over the stored answers');

      // Resolved: saves run again, with the restored answers.
      await background(tester);
      expect(answerSaves(), isNotEmpty);
      expect(answerSaves().any((p) => p.contains('"first_name":"Ana"')), isTrue,
          reason: 'what is saved is the stored answers, not blanks');
    });

    testWidgets('a network failure gives the connection hint',
        (tester) async {
      server.profileRead = _Fail.network;
      await open(tester);
      // postgrest-dart retries a GET that never reached the server, with
      // backoff, before giving up.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      await settle(tester);
      expect(find.text("Couldn't load your answers — $_connection"),
          findsOneWidget);
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('control: a read that finds no row starts fresh as today',
        (tester) async {
      await open(tester);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('Get Started'), findsWidgets);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(reported, isEmpty);
    });
  });

  // ── 3. Coach list ─────────────────────────────────────────────────────────
  group('coach list', () {
    testWidgets(
        'a failed read is a failure with Try again — never "No coaches '
        'available"; an empty list after Try again keeps today\'s copy',
        (tester) async {
      server
        ..profile = {'id': _uid, 'onboarding_step': _coachPage}
        ..coachesRead = _Fail.server;
      await open(tester);
      expect(find.text('Choose Your Coach'), findsOneWidget,
          reason: 'premise: the flow opened on Choose Coach');

      expect(find.textContaining('No coaches available'), findsNothing,
          reason: 'THE defect: a failed read was shown as no coaches');
      expect(find.text("Couldn't load coaches — $_generic"), findsOneWidget);
      expect(reported.map((f) => f.origin), contains('coach.availableCoaches'));

      server.coachesRead = _Fail.none;
      await tester.tap(tryAgain());
      await settle(tester);
      expect(find.text('No coaches available right now.\nCheck back soon.'),
          findsOneWidget);
      expect(find.textContaining("Couldn't load coaches"), findsNothing);
    });

    test('the provider rethrows a failed read after reporting it', () async {
      server.coachesRead = _Fail.server;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await expectLater(container.read(availableCoachesProvider.future),
          throwsA(isA<PostgrestException>()));
      expect(reported.map((f) => f.origin), ['coach.availableCoaches']);
    });

    test('control: a successful empty read is an empty list', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(availableCoachesProvider.future), isEmpty);
      expect(reported, isEmpty);
    });
  });
}
