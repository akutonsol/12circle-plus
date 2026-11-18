import 'dart:async';
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
//
// Follow-up review (QA/UX on dd9a333), groups F–M below:
//   Q. The fake used to answer EVERY user_profiles PATCH with a row, so
//      dropping `.select('id')` went unnoticed. postgrest only asks for rows
//      back (select= / Prefer: return=representation) when `.select()` is
//      called; the fake now answers 204 with an empty body otherwise, and the
//      controls assert select=id on each PATCH.
//   N1–N9: see each group. Check out dd9a333's coach_business_screen.dart to
//   see them fail (regression guards are marked as such).
//
// Final follow-up (QA/UX on d0a2722), groups R1–R3 at the end. Check out
// d0a2722's coach_business_screen.dart to see them fail.

const _uid = '00000000-0000-4000-8000-0000000b5f04';
const _signedOut = "You're signed out — sign in again to save.";
const _priceError = 'Enter a monthly price in dollars, e.g. 150.';
const _yearsError = 'Enter years of experience as a whole number, e.g. 5.';
const _checkConnection = 'Check your connection and try again.';
const _tryLater =
    'Try again in a moment. If it keeps happening, contact support.';
const _blankKept =
    'Profile updated. A blank price or years field keeps its saved value.';
const _errorRed = Color(0xFFFFB4AB);
const _inviteEmailNotSent =
    "Invite saved, but the email couldn't be sent — ask them to check back, "
    'or send the invite again later.';

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

enum _Read { ok, fails, missing, network }

enum _Patch { oneRow, zeroRows, fails, network }

class _Server extends http.BaseClient {
  _Read readMode = _Read.ok;
  _Patch patchMode = _Patch.oneRow;
  bool insertFails = false;
  bool storageFails = false;
  bool emailSent = true;

  /// Overrides fields of the profile the GET returns (null = the real one).
  Map<String, Object?>? profileOverride;
  Completer<void>? readGate;
  Completer<void>? patchGate;
  final calls = <String>[];
  final patches = <Map<String, Object?>>[];

  /// The `select=` each user_profiles PATCH asked for (null = none).
  final patchSelects = <String?>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (path.startsWith('/auth/v1/')) return _json({}, 200, request);
    if (path.startsWith('/storage/v1/')) {
      return storageFails
          ? _json({'statusCode': '500', 'error': 'x', 'message': 'boom'}, 500,
              request)
          : _json({'Key': 'coach-media/x.jpg'}, 200, request);
    }
    if (path == '/functions/v1/send-invite-email') {
      return _json({'sent': emailSent}, 200, request);
    }
    if (path == '/rest/v1/user_profiles' && request.method == 'PATCH') {
      final body = await request.finalize().bytesToString();
      patches.add(Map<String, Object?>.from(jsonDecode(body) as Map));
      patchSelects.add(request.url.queryParameters['select']);
      if (patchGate != null) await patchGate!.future;
      // Like PostgREST: rows come back only when the request asked for them.
      final wantsRows = request.url.queryParameters.containsKey('select') ||
          (request.headers['Prefer'] ?? '').contains('return=representation');
      return switch (patchMode) {
        _Patch.oneRow when wantsRows => _json([
            {'id': _uid}
          ], 200, request),
        _Patch.zeroRows when wantsRows => _json([], 200, request),
        _Patch.oneRow || _Patch.zeroRows => _empty204(request),
        _Patch.fails => _json({'message': 'boom'}, 500, request),
        _Patch.network => throw http.ClientException('offline', request.url),
      };
    }
    if (path == '/rest/v1/user_profiles' && request.method == 'GET') {
      if (readGate != null) await readGate!.future;
      final single =
          request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
      final profile = {..._realProfile, ...?profileOverride};
      switch (readMode) {
        case _Read.fails:
          return _json({'message': 'boom'}, 500, request);
        case _Read.network:
          throw const SocketException('offline');
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
              ? _json(profile, 200, request)
              : _json([profile], 200, request);
      }
    }
    if (path == '/rest/v1/coach_team_invites' && request.method == 'POST') {
      return insertFails
          ? _json({'message': 'offline'}, 500, request)
          : _json([], 201, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _empty204(http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(const <int>[]), 204, request: r);

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
      ..storageFails = false
      ..emailSent = true
      ..profileOverride = null
      ..readGate = null
      ..patchGate = null
      ..calls.clear()
      ..patches.clear()
      ..patchSelects.clear();
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

  Future<void> open(WidgetTester tester,
      {Size size = const Size(1000, 2400), bool wait = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CoachBusinessScreen()));
    if (wait) await settle(tester);
  }

  /// Every user_profiles PATCH asked for the changed row back.
  void expectSelectIdOnEveryPatch() {
    expect(server.patchSelects, isNotEmpty, reason: 'premise');
    expect(server.patchSelects, everyElement('id'),
        reason: 'without .select(\'id\') a 0-row (RLS-refused) update '
            'cannot be told apart from a saved one');
  }

  Color? snackColor(WidgetTester tester) =>
      tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor;

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
      expect(
          find.text("Couldn't save your profile — nothing was changed. "
              '$_tryLater'),
          findsOneWidget);
    });

    testWidgets('a server error says so, and does not blame the connection',
        (tester) async {
      server.patchMode = _Patch.fails;
      await open(tester);
      await tapSave(tester);
      expect(find.text('Profile updated!'), findsNothing);
      expect(
          find.text("Couldn't save your profile — try again in a moment. "
              'If it keeps happening, contact support.'),
          findsOneWidget,
          reason: 'N4: a PostgrestException is not a connection problem');
    });

    testWidgets('a network failure on Save says check your connection',
        (tester) async {
      server.patchMode = _Patch.network;
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
      expectSelectIdOnEveryPatch();
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
      expectSelectIdOnEveryPatch();
      // N1: it does not say a bare "updated" over two blank fields; the saved
      // values come back and the message says why.
      expect(find.text('Profile updated!'), findsNothing);
      expect(find.text(_blankKept), findsOneWidget);
      expect(tester.widget<TextField>(priceField()).controller!.text, '149');
      expect(tester.widget<TextField>(yearsField()).controller!.text, '5');
    });

    testWidgets('N1: a blank field gets back the value saved most recently',
        (tester) async {
      await open(tester);
      await tester.enterText(priceField(), '200');
      await tapSave(tester);
      expect(find.text('Profile updated!'), findsOneWidget);
      // SnackBars queue; clear the first so the second is the one on screen.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .removeCurrentSnackBar();
      await tester.pump();
      await tester.enterText(priceField(), '');
      await tapSave(tester);
      expect(server.patches.last.containsKey('pricing_monthly'), isFalse);
      expect(tester.widget<TextField>(priceField()).controller!.text, '200',
          reason: '200 is what the server holds now, not the 149 first read');
      expect(tester.widget<TextField>(yearsField()).controller!.text, '5');
      expect(find.text(_blankKept), findsOneWidget);
    });

    testWidgets('N1: a blank field on a 0-row save is NOT refilled',
        (tester) async {
      server.patchMode = _Patch.zeroRows;
      await open(tester);
      await tester.enterText(priceField(), '');
      await tapSave(tester);
      expect(find.text(_blankKept), findsNothing);
      expect(tester.widget<TextField>(priceField()).controller!.text, '',
          reason: 'nothing was confirmed, so nothing is claimed');
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
      await tester.pump(); // the dialog enables Add on the next frame
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
      expectSelectIdOnEveryPatch();
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
      expect(
          find.text("Couldn't add the photo — nothing was changed. $_tryLater"),
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
      expectSelectIdOnEveryPatch();
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
      expect(find.text(_inviteEmailNotSent), findsNothing);
      expect(
          find.text(
              "Couldn't save the invite — try again in a moment. "
              'If it keeps happening, contact support.'),
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

  // ── F. N2 — an inline error clears when its field changes ─────────────────
  group('F. inline errors follow the field', () {
    testWidgets('editing the price clears the price error only',
        (tester) async {
      await open(tester);
      await tester.enterText(priceField(), 'abc');
      await tester.enterText(yearsField(), 'x');
      await tapSave(tester);
      expect(errorOf(tester, priceField()), _priceError, reason: 'premise');
      expect(errorOf(tester, yearsField()), _yearsError, reason: 'premise');
      await tester.enterText(priceField(), '150');
      await tester.pump();
      expect(errorOf(tester, priceField()), isNull,
          reason: 'the stale error stayed under a valid price');
      expect(errorOf(tester, yearsField()), _yearsError);
      await tester.enterText(yearsField(), '6');
      await tester.pump();
      expect(errorOf(tester, yearsField()), isNull);
    });
  });

  // ── G. N3 — focus the first invalid field; name both when both are bad ─────
  group('G. validation focus and message', () {
    bool focused(WidgetTester tester, Finder field) => tester
        .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)))
        .focusNode
        .hasFocus;

    testWidgets('both bad: price (first) is focused, the SnackBar names both',
        (tester) async {
      await open(tester);
      await tester.enterText(priceField(), 'abc');
      await tester.enterText(yearsField(), 'x');
      // Move focus away so the assertion is about Save, not about typing.
      await tester.enterText(find.byType(TextField).at(1), 'Real bio');
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(patchCount(), 0);
      expect(focused(tester, priceField()), isTrue);
      expect(
          find.textContaining(RegExp(
              r'monthly price.*years of experience.*Nothing was saved\.$')),
          findsOneWidget);
    });

    testWidgets('only years bad, from another tab: Profile tab, years focused',
        (tester) async {
      await open(tester);
      await tester.enterText(yearsField(), 'x');
      // Focus elsewhere: a focused field keeps its page alive (and its focus)
      // across the tab switch, which would prove nothing about Save.
      await tester.enterText(find.byType(TextField).at(1), 'Real bio');
      await tester.tap(find.text('Specialties'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing, reason: 'premise');
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(patchCount(), 0);
      expect(focused(tester, yearsField()), isTrue);
      expect(find.text('$_yearsError Nothing was saved.'), findsOneWidget);
    });
  });

  // ── H. N4 — load failure copy matches what failed ──────────────────────────
  group('H. load failure copy', () {
    testWidgets('a network failure says check your connection',
        (tester) async {
      // Regression guard: dd9a333 said this for every failure.
      server.readMode = _Read.network;
      await open(tester);
      // postgrest retries a GET that never reached the server (measured: 4
      // attempts over ~16 s of real time); wait it out.
      final sw = Stopwatch()..start();
      while (find.text("Couldn't load your business profile").evaluate().isEmpty &&
          sw.elapsed < const Duration(seconds: 40)) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text("Couldn't load your business profile"), findsOneWidget);
      expect(find.text(_checkConnection), findsOneWidget);
      expect(find.text(_tryLater), findsNothing);
    });

    testWidgets('a server error says try later / contact support',
        (tester) async {
      server.readMode = _Read.fails;
      await open(tester);
      expect(find.text(_tryLater), findsOneWidget);
      expect(find.text(_checkConnection), findsNothing,
          reason: 'a PostgrestException is not a connection problem');
    });

    testWidgets('no profile row says try later / contact support',
        (tester) async {
      server.readMode = _Read.missing;
      await open(tester);
      expect(find.text(_tryLater), findsOneWidget);
      expect(find.text(_checkConnection), findsNothing);
    });
  });

  // ── I. N5 — the load states are readable and announced ─────────────────────
  group('I. load states, accessibility', () {
    testWidgets('the spinner is labelled', (tester) async {
      final gate = Completer<void>();
      server.readGate = gate;
      final handle = tester.ensureSemantics();
      await open(tester, wait: false);
      await tester.pump();
      expect(find.bySemanticsLabel('Loading your business profile'),
          findsOneWidget);
      gate.complete();
      await settle(tester);
      handle.dispose();
    });

    testWidgets('the failure is a live region', (tester) async {
      server.readMode = _Read.fails;
      await open(tester);
      expect(
          find.ancestor(
              of: find.text("Couldn't load your business profile"),
              matching: find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.liveRegion == true)),
          findsOneWidget);
    });

    testWidgets('no overflow at text scale 2.0 on a 320-wide phone',
        (tester) async {
      server.readMode = _Read.fails;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, size: const Size(320, 480));
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Try again'), 50,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('Try again').hitTestable(), findsOneWidget);
    });
  });

  // ── J. N6 — one voice: "Couldn't …" plus what to do next ───────────────────
  group('J. failure messages', () {
    Future<void> addCert(WidgetTester tester, String name) async {
      await tester.tap(find.text('+ Add').first);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          name);
      await tester.pump(); // the dialog enables Add on the next frame
      await tester.tap(find.text('Add'));
      await settle(tester);
    }

    testWidgets('a failed photo upload', (tester) async {
      server.storageFails = true;
      await open(tester);
      await tester.tap(find.text('Add Photo'));
      await settle(tester);
      expect(
          find.text("Couldn't add the photo — try again in a moment. "
              'If it keeps happening, contact support.'),
          findsOneWidget);
      expect(snackColor(tester), _errorRed);
    });

    testWidgets('a failed certification add (server error)', (tester) async {
      server.patchMode = _Patch.fails;
      await open(tester);
      await addCert(tester, 'ACE-CPT');
      expect(
          find.text("Couldn't add the certification — try again in a moment. "
              'If it keeps happening, contact support.'),
          findsOneWidget);
      expect(find.widgetWithText(Chip, 'ACE-CPT'), findsNothing);
    });

    testWidgets('a failed certification remove (network)', (tester) async {
      server.patchMode = _Patch.network;
      await open(tester);
      await tester.tap(find.byIcon(Icons.close));
      await settle(tester);
      expect(
          find.text("Couldn't remove the certification — check your "
              'connection and try again.'),
          findsOneWidget);
      expect(find.widgetWithText(Chip, 'NASM-CPT'), findsOneWidget);
    });

    testWidgets('a 0-row certification add', (tester) async {
      server.patchMode = _Patch.zeroRows;
      await open(tester);
      await addCert(tester, 'ACE-CPT');
      expect(
          find.text("Couldn't add the certification — nothing was changed. "
              '$_tryLater'),
          findsOneWidget);
    });
  });

  // ── K. N7 — invite failures use the error style ────────────────────────────
  group('K. invite SnackBars', () {
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

    testWidgets('a failed insert is shown in the error style',
        (tester) async {
      server.insertFails = true;
      await open(tester);
      await invite(tester);
      expect(find.textContaining("Couldn't save the invite"), findsOneWidget);
      expect(snackColor(tester), _errorRed);
    });

    testWidgets('signed out is shown in the error style', (tester) async {
      await open(tester);
      await signOut(tester);
      await invite(tester);
      expect(find.text(_signedOut), findsOneWidget);
      expect(snackColor(tester), _errorRed);
    });
  });

  // ── L. N8 — the Add Certification dialog ───────────────────────────────────
  group('L. add-certification dialog', () {
    Finder dialogField() => find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    TextButton addButton(WidgetTester tester) =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Add'));

    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.text('+ Add').first);
      await tester.pumpAndSettle();
    }

    testWidgets('Add is disabled while the text is empty or blank',
        (tester) async {
      await open(tester);
      await openDialog(tester);
      expect(addButton(tester).onPressed, isNull);
      await tester.enterText(dialogField(), '   ');
      await tester.pump();
      expect(addButton(tester).onPressed, isNull);
      await tester.enterText(dialogField(), 'ACE-CPT');
      await tester.pump();
      expect(addButton(tester).onPressed, isNotNull);
    });

    testWidgets('keyboard Done submits', (tester) async {
      await open(tester);
      await openDialog(tester);
      await tester.enterText(dialogField(), 'ACE-CPT');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(server.patches.single['certifications'], ['NASM-CPT', 'ACE-CPT']);
      expect(find.widgetWithText(Chip, 'ACE-CPT'), findsOneWidget);
    });

    testWidgets('a duplicate says "Already added" and cannot be added',
        (tester) async {
      await open(tester);
      await openDialog(tester);
      await tester.enterText(dialogField(), 'NASM-CPT');
      await tester.pump();
      expect(find.text('Already added'), findsOneWidget);
      expect(addButton(tester).onPressed, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'Done does not close it silently either');
      expect(patchCount(), 0);
    });
  });

  // ── M. N9 — one certification write at a time ──────────────────────────────
  group('M. certification writes do not overlap', () {
    testWidgets('an add while a remove is in flight is ignored',
        (tester) async {
      final gate = Completer<void>();
      await open(tester);
      server.patchGate = gate;
      await tester.tap(find.byIcon(Icons.close)); // remove NASM-CPT
      await settle(tester);
      expect(patchCount(), 1, reason: 'premise: the remove is in flight');
      await tester.tap(find.text('+ Add').first);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'ACE-CPT');
      await tester.pump(); // the dialog enables Add on the next frame
      await tester.tap(find.text('Add'));
      await settle(tester);
      expect(patchCount(), 1,
          reason: 'a second optimistic write raced the first');
      gate.complete();
      server.patchGate = null;
      await settle(tester);
      expect(server.patches.single['certifications'], isEmpty);
      expect(find.widgetWithText(Chip, 'ACE-CPT'), findsNothing);
      expect(find.widgetWithText(Chip, 'NASM-CPT'), findsNothing);
    });
  });

  // ── R1. Save and certification writes are mutually exclusive ──────────────
  // Save writes the whole certifications list. Sent during a cert write it
  // carried the optimistic list; when that cert write then failed and rolled
  // back, the database kept a list the screen no longer showed.
  group('R1. Save and certification writes never overlap', () {
    TextButton saveButton(WidgetTester tester) =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));

    // Bounded pumps, not pumpAndSettle: the Save spinner animates for as long
    // as Save is in flight, so the tree never settles.
    Future<void> addCert(WidgetTester tester, String name) async {
      await tester.tap(find.text('+ Add').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          name);
      await tester.pump(); // the dialog enables Add on the next frame
      await tester.tap(find.text('Add'));
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
    }

    testWidgets(
        'while a cert write is in flight, Save is disabled and sends nothing; '
        'a failed cert write leaves no stale list in the database',
        (tester) async {
      final gate = Completer<void>();
      await open(tester);
      server
        ..patchGate = gate
        ..patchMode = _Patch.fails;
      await tester.tap(find.byIcon(Icons.close)); // remove NASM-CPT
      await settle(tester);
      expect(patchCount(), 1, reason: 'premise: the remove is in flight');
      expect(saveButton(tester).onPressed, isNull,
          reason: 'Save would send the optimistic (empty) list');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(patchCount(), 1, reason: 'no Save PATCH during a cert write');

      gate.complete();
      server.patchGate = null;
      await settle(tester);
      expect(find.widgetWithText(Chip, 'NASM-CPT'), findsOneWidget,
          reason: 'the failed remove rolled back');
      expect(server.patches.single['certifications'], isEmpty);
      expect(saveButton(tester).onPressed, isNotNull,
          reason: 'Save comes back once the cert write is done');

      // Afterwards Save sends what the screen shows.
      server.patchMode = _Patch.oneRow;
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .removeCurrentSnackBar();
      await tester.pump();
      await tapSave(tester);
      expect(server.patches.last['certifications'], ['NASM-CPT']);
      expect(find.text('Profile updated!'), findsOneWidget);
    });

    testWidgets('while Save is in flight, cert add and remove are ignored',
        (tester) async {
      final gate = Completer<void>();
      await open(tester);
      server.patchGate = gate;
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(patchCount(), 1, reason: 'premise: Save is in flight');

      await tester.tap(find.byIcon(Icons.close)); // remove NASM-CPT
      await settle(tester);
      await addCert(tester, 'ACE-CPT');
      expect(patchCount(), 1, reason: 'a cert write raced the Save');
      expect(find.widgetWithText(Chip, 'NASM-CPT'), findsOneWidget,
          reason: 'an ignored remove leaves the chip');
      expect(find.widgetWithText(Chip, 'ACE-CPT'), findsNothing,
          reason: 'an ignored add shows no chip');

      gate.complete();
      server.patchGate = null;
      await settle(tester);
      expect(server.patches.single['certifications'], ['NASM-CPT']);
      expect(find.text('Profile updated!'), findsOneWidget);
    });
  });

  // ── R2. UX N1a — the "keeps its saved value" note only when it is true ────
  group('R2. blank-field note', () {
    testWidgets('nothing saved before: blank fields stay blank, plain updated',
        (tester) async {
      server.profileOverride = {
        'pricing_monthly': null,
        'years_experience': null,
      };
      await open(tester);
      expect(tester.widget<TextField>(priceField()).controller!.text, '',
          reason: 'premise: no saved price');
      await tapSave(tester);
      expect(server.patches.single.containsKey('pricing_monthly'), isFalse);
      expect(tester.widget<TextField>(priceField()).controller!.text, '');
      expect(tester.widget<TextField>(yearsField()).controller!.text, '');
      expect(find.text(_blankKept), findsNothing,
          reason: 'no field was refilled, so there is nothing to explain');
      expect(find.text('Profile updated!'), findsOneWidget);
    });

    testWidgets('one field refilled with a saved value: the note is shown',
        (tester) async {
      server.profileOverride = {'years_experience': null};
      await open(tester);
      await tester.enterText(priceField(), '');
      await tapSave(tester);
      expect(tester.widget<TextField>(priceField()).controller!.text, '149');
      expect(tester.widget<TextField>(yearsField()).controller!.text, '');
      expect(find.text(_blankKept), findsOneWidget);
    });
  });

  // ── R3. UX N10b — an unsent invite email is an error with a next step ─────
  group('R3. invite email not sent', () {
    testWidgets('error style and what to do next', (tester) async {
      server.emailSent = false;
      await open(tester);
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
      expect(server.calls, contains('POST /functions/v1/send-invite-email'),
          reason: 'premise');
      expect(find.text(_inviteEmailNotSent), findsOneWidget);
      expect(snackColor(tester), _errorRed);
      expect(find.textContaining('Invite email sent'), findsNothing);
    });
  });
}
