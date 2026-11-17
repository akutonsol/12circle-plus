import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_business_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-4: the coach Business Profile said things happened that did not.
//
//   A. Save: a 0-row update said "Profile updated!"; an empty or unparseable
//      price was written as 0 (and a negative one as typed); signed out did
//      nothing and said nothing.
//   B. Load: a failed read rendered the EDITABLE form with blank fields and an
//      enabled Save — one tap overwrote the real bio/price with blanks.
//   C. Certifications: a 0-row update left the chip added/removed.
//   D. Transformation photo: a 0-row profile update said "Photo added".
//   E. Team invite: a failed insert was swallowed, the email still went out
//      and the coach was told "Invite email sent".
//
// HOW TO SEE IT FAIL: check out 8f2c8a0's coach_business_screen.dart and run
// this file. The positive controls pass there too.

const _uid = '00000000-0000-4000-8000-0000000b5f04';
const _signedOut = "You're signed out — sign in again to save.";
const _priceError = 'Enter a monthly price in dollars, e.g. 150.';

final _realProfile = <String, Object?>{
  'id': _uid,
  'bio': 'Real bio',
  'tagline': 'Real tagline',
  'pricing_monthly': 149,
  'years_experience': 5,
  'specialties': ['HIIT'],
  'certifications': ['NASM-CPT'],
  'transformation_photo_urls': <String>[],
  'rating_avg': 0,
};

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

String _sessionJson() => jsonEncode({
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

class _SeededSession extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => _sessionJson();
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

enum _Read { ok, fails, missing }

enum _Patch { oneRow, zeroRows, fails }

class _Server extends http.BaseClient {
  _Read readMode = _Read.ok;
  _Patch patchMode = _Patch.oneRow;
  bool insertFails = false;
  final calls = <String>[];
  final patches = <Map<String, Object?>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (path.startsWith('/auth/v1/')) return _json({}, 200, request);
    if (path.startsWith('/storage/v1/')) {
      return _json({'Key': 'coach-media/x.jpg'}, 200, request);
    }
    if (path == '/functions/v1/send-invite-email') {
      return _json({'sent': true}, 200, request);
    }
    if (path == '/rest/v1/user_profiles' && request.method == 'PATCH') {
      final body = await request.finalize().bytesToString();
      patches.add(Map<String, Object?>.from(jsonDecode(body) as Map));
      return switch (patchMode) {
        _Patch.oneRow => _json([
            {'id': _uid}
          ], 200, request),
        _Patch.zeroRows => _json([], 200, request),
        _Patch.fails => _json({'message': 'offline'}, 500, request),
      };
    }
    if (path == '/rest/v1/user_profiles' && request.method == 'GET') {
      final single =
          request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
      switch (readMode) {
        case _Read.fails:
          return _json({'message': 'offline'}, 500, request);
        case _Read.missing:
          return single
              ? _json({
                  'code': 'PGRST116',
                  'details': 'The result contains 0 rows',
                  'hint': null,
                  'message': 'JSON object requested, multiple (or no) rows '
                      'returned',
                }, 406, request)
              : _json([], 200, request);
        case _Read.ok:
          return single
              ? _json(_realProfile, 200, request)
              : _json([_realProfile], 200, request);
      }
    }
    if (path == '/rest/v1/coach_team_invites' && request.method == 'POST') {
      return insertFails
          ? _json({'message': 'offline'}, 500, request)
          : _json([], 201, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;
  final failures = <AppFailure>[];
  late Directory tmp;

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
    tmp = Directory.systemTemp.createTempSync('coach_business_test');
    final photo = File('${tmp.path}/after.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    // The gallery picker, answered through its platform channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (call) async => photo.path);
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUp(() async {
    server
      ..readMode = _Read.ok
      ..patchMode = _Patch.oneRow
      ..insertFails = false
      ..calls.clear()
      ..patches.clear();
    failures.clear();
    setFailureSink(failures.add);
    if (Supabase.instance.client.auth.currentUser == null) {
      await Supabase.instance.client.auth.recoverSession(_sessionJson());
    }
  });

  tearDown(resetFailureSink);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CoachBusinessScreen()));
    await settle(tester);
  }

  Future<void> signOut(WidgetTester tester) async {
    await tester.runAsync(() => Supabase.instance.client.auth.signOut());
    expect(Supabase.instance.client.auth.currentUser, isNull,
        reason: 'premise');
    server.calls.clear();
  }

  Finder priceField() => find.byType(TextField).at(2);
  Finder yearsField() => find.byType(TextField).at(3);
  String? errorOf(WidgetTester tester, Finder f) =>
      tester.widget<TextField>(f).decoration?.errorText;
  int patchCount() =>
      server.calls.where((c) => c == 'PATCH /rest/v1/user_profiles').length;

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await settle(tester);
  }

  // ── B. Load ────────────────────────────────────────────────────────────────
  group('B. a profile that did not load is not an editable blank form', () {
    testWidgets('failed read: no form, no Save, a retry that loads it',
        (tester) async {
      server.readMode = _Read.fails;
      await open(tester);
      expect(find.text("Couldn't load your business profile"), findsOneWidget);
      expect(find.byType(TextField), findsNothing,
          reason: 'THE defect: blank editable fields over the real profile');
      expect(find.text('Save'), findsNothing,
          reason: 'one tap on Save wrote blanks over the real profile');
      expect(
          failures.map((f) => f.origin), contains('CoachBusinessScreen._load'));

      server.readMode = _Read.ok;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text("Couldn't load your business profile"), findsNothing);
      expect(find.text('Save'), findsOneWidget);
      expect(tester.widget<TextField>(priceField()).controller!.text, '149');
    });

    testWidgets('no profile row (maybeSingle null) is the same failure',
        (tester) async {
      server.readMode = _Read.missing;
      await open(tester);
      expect(find.text("Couldn't load your business profile"), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(failures, isNotEmpty);
    });

    testWidgets('control: a loaded profile shows the form and Save',
        (tester) async {
      await open(tester);
      expect(find.text('Save'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byType(TextField).at(1))
              .controller!
              .text,
          'Real bio');
      expect(find.text("Couldn't load your business profile"), findsNothing);
    });
  });

  // ── A. Save ────────────────────────────────────────────────────────────────
  group('A. Save', () {
    testWidgets('a 0-row update does not say "Profile updated!"',
        (tester) async {
      server.patchMode = _Patch.zeroRows;
      await open(tester);
      await tapSave(tester);
      expect(patchCount(), 1, reason: 'premise');
      expect(find.text('Profile updated!'), findsNothing,
          reason: 'THE defect: RLS filtered the update and it said saved');
      expect(find.text("Your profile couldn't be saved — nothing was changed."),
          findsOneWidget);
    });

    testWidgets('a failed update says so', (tester) async {
      server.patchMode = _Patch.fails;
      await open(tester);
      await tapSave(tester);
      expect(find.text('Profile updated!'), findsNothing);
      expect(
          find.text(
              "Couldn't save your profile — check your connection and try again."),
          findsOneWidget);
    });

    testWidgets('control: a 1-row update says updated and writes the form',
        (tester) async {
      await open(tester);
      await tapSave(tester);
      expect(find.text('Profile updated!'), findsOneWidget);
      final body = server.patches.single;
      expect(body['bio'], 'Real bio');
      expect(body['pricing_monthly'], 149);
      expect(body['years_experience'], 5);
      expect(body['tagline'], 'Real tagline');
      expect(body['specialties'], ['HIIT']);
      expect(body['certifications'], ['NASM-CPT']);
    });

    testWidgets('an EMPTY price is left out of the update, never written as 0',
        (tester) async {
      await open(tester);
      await tester.enterText(priceField(), '');
      await tester.enterText(yearsField(), '');
      await tapSave(tester);
      final body = server.patches.single;
      expect(body.containsKey('pricing_monthly'), isFalse,
          reason: 'THE defect: an empty field wrote pricing_monthly = 0');
      expect(body.containsKey('years_experience'), isFalse);
      expect(body['bio'], 'Real bio');
      expect(find.text('Profile updated!'), findsOneWidget);
    });

    for (final bad in ['abc', '-5']) {
      testWidgets('price "$bad" is an inline error and NO PATCH is sent',
          (tester) async {
        await open(tester);
        await tester.enterText(priceField(), bad);
        await tapSave(tester);
        expect(patchCount(), 0,
            reason: 'THE defect: "$bad" was written (as 0, or as typed)');
        expect(errorOf(tester, priceField()), _priceError);
        expect(find.text('Profile updated!'), findsNothing);
        expect(tester.widget<TextField>(priceField()).controller!.text, bad,
            reason: 'what the coach typed is kept');
      });
    }

    testWidgets('years "x" is an inline error and NO PATCH is sent',
        (tester) async {
      await open(tester);
      await tester.enterText(yearsField(), 'x');
      await tapSave(tester);
      expect(patchCount(), 0);
      expect(errorOf(tester, yearsField()), isNotNull);
      expect(find.text('Profile updated!'), findsNothing);
    });

    testWidgets('an invalid price on another tab brings the Profile tab back',
        (tester) async {
      await open(tester);
      await tester.enterText(priceField(), 'abc');
      await tester.tap(find.text('Specialties'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing, reason: 'premise');
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(patchCount(), 0);
      expect(find.text(_priceError), findsOneWidget,
          reason: 'the inline error is where the coach can see it');
    });

    testWidgets(
        'an explicit "0" is still written as 0 (unchanged, Decision 18)',
        (tester) async {
      await open(tester);
      await tester.enterText(priceField(), '0');
      await tapSave(tester);
      expect(server.patches.single['pricing_monthly'], 0);
      expect(find.text('Profile updated!'), findsOneWidget);
    });

    testWidgets('signed out: says so and writes nothing', (tester) async {
      await open(tester);
      await signOut(tester);
      await tapSave(tester);
      expect(patchCount(), 0);
      expect(find.text(_signedOut), findsOneWidget,
          reason: 'THE defect: Save returned silently');
    });
  });

  // ── C. Certifications ─────────────────────────────────────────────────────
  group('C. certifications', () {
    Future<void> addCert(WidgetTester tester, String name) async {
      await tester.tap(find.text('+ Add').first);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          name);
      await tester.tap(find.text('Add'));
      await settle(tester);
    }

    testWidgets('a 0-row add puts the list back and says nothing changed',
        (tester) async {
      server.patchMode = _Patch.zeroRows;
      await open(tester);
      await addCert(tester, 'ACE-CPT');
      expect(patchCount(), 1, reason: 'premise');
      expect(find.widgetWithText(Chip, 'ACE-CPT'), findsNothing,
          reason: 'THE defect: the chip stayed although nothing was saved');
      expect(find.textContaining('nothing was changed'), findsOneWidget);
    });

    testWidgets('a 0-row remove puts the chip back', (tester) async {
      server.patchMode = _Patch.zeroRows;
      await open(tester);
      await tester.tap(find.byIcon(Icons.close));
      await settle(tester);
      expect(find.widgetWithText(Chip, 'NASM-CPT'), findsOneWidget);
      expect(find.textContaining('nothing was changed'), findsOneWidget);
    });

    testWidgets('signed out: says so, no write, list unchanged',
        (tester) async {
      await open(tester);
      await signOut(tester);
      await addCert(tester, 'ACE-CPT');
      expect(patchCount(), 0);
      expect(find.widgetWithText(Chip, 'ACE-CPT'), findsNothing);
      expect(find.text(_signedOut), findsOneWidget);
    });

    testWidgets('control: a 1-row add keeps the chip', (tester) async {
      await open(tester);
      await addCert(tester, 'ACE-CPT');
      expect(server.patches.single['certifications'], ['NASM-CPT', 'ACE-CPT']);
      expect(find.widgetWithText(Chip, 'ACE-CPT'), findsOneWidget);
      expect(find.textContaining('nothing was changed'), findsNothing);
    });
  });

  // ── D. Transformation photo ────────────────────────────────────────────────
  group('D. transformation photo', () {
    Future<void> addPhoto(WidgetTester tester) async {
      await tester.tap(find.text('Add Photo'));
      await settle(tester);
    }

    testWidgets('a 0-row profile update does not say "Photo added"',
        (tester) async {
      server.patchMode = _Patch.zeroRows;
      await open(tester);
      await addPhoto(tester);
      expect(patchCount(), 1, reason: 'premise');
      expect(find.text('Photo added'), findsNothing,
          reason: 'THE defect: 0 rows and it said added');
      expect(find.text("Couldn't add the photo — nothing was changed."),
          findsOneWidget);
    });

    testWidgets('signed out: says so and uploads nothing', (tester) async {
      await open(tester);
      await signOut(tester);
      await addPhoto(tester);
      expect(server.calls.where((c) => !c.startsWith('POST /auth/')), isEmpty);
      expect(find.text(_signedOut), findsOneWidget);
    });

    testWidgets('control: a 1-row update says added', (tester) async {
      await open(tester);
      await addPhoto(tester);
      expect(
          server.calls.any((c) => c.startsWith('POST /storage/v1/object/'
              'coach-media/coach-transformations/$_uid/')),
          isTrue,
          reason: 'bucket and path unchanged');
      expect(server.patches.single['transformation_photo_urls'], hasLength(1));
      expect(find.text('Photo added'), findsOneWidget);
    });
  });

  // ── E. Team invite ─────────────────────────────────────────────────────────
  group('E. team invite', () {
    Future<void> invite(WidgetTester tester) async {
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite Assistant Coach'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'assistant@example.com');
      await tester.tap(find.text('Invite'));
      await settle(tester);
    }

    bool emailed() =>
        server.calls.contains('POST /functions/v1/send-invite-email');

    testWidgets('a failed insert sends no email and says it was not saved',
        (tester) async {
      server.insertFails = true;
      await open(tester);
      await invite(tester);
      expect(server.calls, contains('POST /rest/v1/coach_team_invites'),
          reason: 'premise');
      expect(emailed(), isFalse,
          reason: 'THE defect: an invite that does not exist was emailed');
      expect(find.textContaining('Invite email sent'), findsNothing);
      expect(find.text('Invite saved, but email could not be sent.'),
          findsNothing);
      expect(
          find.text(
              "Couldn't save the invite — check your connection and try again."),
          findsOneWidget);
    });

    testWidgets('signed out: says so, no insert, no email', (tester) async {
      await open(tester);
      await signOut(tester);
      await invite(tester);
      expect(server.calls, isNot(contains('POST /rest/v1/coach_team_invites')));
      expect(emailed(), isFalse);
      expect(find.text(_signedOut), findsOneWidget);
    });

    testWidgets('control: a saved invite is emailed and says sent',
        (tester) async {
      await open(tester);
      await invite(tester);
      expect(emailed(), isTrue);
      expect(find.text('Invite email sent to assistant@example.com'),
          findsOneWidget);
    });
  });
}
