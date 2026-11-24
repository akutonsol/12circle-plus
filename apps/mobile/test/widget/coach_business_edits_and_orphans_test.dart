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

import '../support/pump_until.dart';

// P0-FL-57b · Business Profile (follow-ups to FL-54; same harness).
//
//  (a) the certification dialog stayed open — with coach A's typed text — after
//      B signed in;
//  (b) a refresh of the same coach (Retry, the reload after a photo) overwrote
//      what the coach had typed and not yet saved;
//  (c) a transformation photo is uploaded first: when the profile update then
//      failed, matched 0 rows, or the coach switched, the file stayed in the
//      public coach-media bucket; and a picker failure had no next step.
//
// HOW TO SEE IT FAIL: `git checkout f191d48 -- \
//   apps/mobile/lib/features/coach/presentation/coach_business_screen.dart`.
//
// Round 2 (review of 9607c80; check that commit's screen out to see it fail):
//   S1    text or a specialty tap in the frame after A→B became B's "edit";
//   S2    a coded connection failure counted as a refusal, and after no answer
//         the list was read and the file deleted — the update could have
//         landed, or land later: a photo on the profile with no file;
//   S4/S5 the removal went out under B's login, `exists` read a 400 as "not
//         there", and a percent-encoded URL as "not listed";
//   the invite dialog stayed open over B; a dialog opened but not yet built
//   was not closed with its coach.

const _a = 'c0ac0000-0000-4000-8000-00000000000a';
const _b = 'c0ac0000-0000-4000-8000-00000000000b';

Map<String, Object?> _rowA() => {
      'id': _a,
      'bio': 'Alpha bio',
      'tagline': 'Alpha tagline',
      'pricing_monthly': 175,
      'years_experience': 5,
      'specialties': ['HIIT'],
      'certifications': ['NASM-CPT'],
      'transformation_photo_urls': <String>[],
      'rating_avg': 4.5,
    };

Map<String, Object?> _rowB() => {
      'id': _b,
      'bio': 'Bravo bio',
      'tagline': 'Bravo tagline',
      'pricing_monthly': 99,
      'years_experience': 12,
      'specialties': ['Yoga'],
      'certifications': ['ACE-CPT'],
      'transformation_photo_urls': <String>[],
      'rating_avg': 3.0,
    };

enum _Patch {
  ok,

  /// RLS filtered it: 0 rows, no error.
  zeroRows,

  /// The database refused it (an SQLSTATE): nothing was written.
  refused,

  /// A bare 5xx (a gateway): says nothing about the write.
  gateway,

  /// No answer, and the write did not land.
  networkLost,

  /// No answer, but the write DID land.
  networkLanded,

  /// No answer; the write lands right after the next profile read answered.
  landsAfterRead,

  /// Answers [_Server.patchCode], but the write DID land.
  codedLanded,
}

enum _Remove {
  removed,

  /// Removed nothing, and the listing does not have it.
  absent,

  /// Removed nothing, and the listing still has it.
  stillThere,
  thrown,

  /// Removed nothing, and the existence check fails: a 500, or a 400 (which
  /// `exists()` reads as "not there").
  checkThrown,
  check400,
}

class _Server extends http.BaseClient {
  final rows = <String, Map<String, Object?>>{};
  _Patch patchMode = _Patch.ok;
  _Remove remove = _Remove.removed;

  /// Every `user_profiles` read answers 500 while set.
  bool readsFail = false;

  /// The NEXT full profile read of `uid` is held, and answers with the row as
  /// it was when the read arrived.
  final holdOnce = <String, Completer<void>>{};

  /// Runs after a held read was taken (so a test can wait for it).
  final held = <String>{};

  Completer<void>? uploadGate;
  Completer<void>? patchGate;
  Completer<void>? removeGate;
  bool uploadFails = false;

  /// The error `code` of [_Patch.codedLanded].
  String patchCode = '';

  /// Lands the pending [_Patch.landsAfterRead] write.
  VoidCallback? _lateLand;

  final calls = <String>[];
  final patches = <String>[];
  final uploads = <String>[];
  final removes = <List<String>>[];

  /// Whose login (JWT `sub`) each removal was sent under.
  final removedAs = <Object?>[];

  /// Every existence check, whichever way it is made.
  final checks = <String>[];

  void reset() {
    rows
      ..clear()
      ..[_a] = _rowA()
      ..[_b] = _rowB();
    patchMode = _Patch.ok;
    remove = _Remove.removed;
    readsFail = uploadFails = false;
    holdOnce.clear();
    held.clear();
    uploadGate = patchGate = removeGate = null;
    patchCode = '';
    _lateLand = null;
    for (final l in [calls, patches, uploads, removes, removedAs, checks]) {
      l.clear();
    }
  }

  static String? _eq(Uri u, String col) {
    final v = u.queryParameters[col];
    return v != null && v.startsWith('eq.') ? v.substring(3) : null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    final path = u.path;
    calls.add('${request.method} $path?${u.query}');
    if (path.startsWith('/auth/v1/')) {
      return http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    const object = '/storage/v1/object/coach-media';
    if (path.startsWith('/storage/v1/')) {
      switch (request.method) {
        case 'DELETE':
          final body = await request.finalize().bytesToString();
          final prefixes =
              List<String>.from((jsonDecode(body) as Map)['prefixes'] as List);
          removes.add(prefixes);
          final jwt = request.headers['Authorization']!.split('.');
          removedAs.add(jwt.length < 2
              ? null // not a session: the publishable key
              : (jsonDecode(utf8.decode(base64Url
                  .decode(base64Url.normalize(jwt[1])))) as Map)['sub']);
          if (removeGate != null) await removeGate!.future;
          return switch (remove) {
            _Remove.removed => _json([
                {'name': prefixes.single, 'bucket_id': 'coach-media'}
              ], 200, request),
            _Remove.thrown => _json({'message': 'boom'}, 500, request),
            _ => _json([], 200, request),
          };
        case 'HEAD':
          checks.add(path.substring(object.length + 1));
          final status = switch (remove) {
            _Remove.stillThere => 200,
            _Remove.checkThrown => 500,
            _Remove.check400 => 400,
            _ => 404,
          };
          return http.StreamedResponse(const Stream.empty(), status,
              request: request);
        default:
          if (path == '/storage/v1/object/list/coach-media') {
            return _list(
                jsonDecode(await request.finalize().bytesToString()) as Map,
                request);
          }
          // Stored under the decoded name, as storage does.
          uploads.add(Uri.decodeComponent(path.substring(object.length + 1)));
          if (uploadGate != null) await uploadGate!.future;
          return uploadFails
              ? _json({'message': 'boom'}, 500, request)
              : _json({'Key': 'coach-media/x.jpg'}, 200, request);
      }
    }
    final table = path.split('/').last;
    final id = _eq(u, 'id');
    if (request.method == 'PATCH') {
      final body = await request.finalize().bytesToString();
      patches.add('$table ${u.query} $body');
      if (patchGate != null) await patchGate!.future;
      void land() => rows[id!] = {
            ...rows[id]!,
            ...(jsonDecode(body) as Map<String, Object?>)
          };
      switch (patchMode) {
        case _Patch.zeroRows:
          return _json([], 200, request);
        case _Patch.refused:
          return _json({'message': 'no', 'code': '42501'}, 403, request);
        case _Patch.gateway:
          return _json({'message': 'upstream timed out'}, 504, request);
        case _Patch.networkLost:
          throw http.ClientException('offline', u);
        case _Patch.networkLanded:
          land();
          throw http.ClientException('offline', u);
        case _Patch.landsAfterRead:
          _lateLand = land;
          throw http.ClientException('offline', u);
        case _Patch.codedLanded:
          land();
          return _json({'message': 'lost', 'code': patchCode}, 503, request);
        case _Patch.ok:
          land();
      }
      return u.queryParameters.containsKey('select')
          ? _json([
              {'id': id}
            ], 200, request)
          : http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    if (table == 'user_profiles') {
      final then = rows[id];
      _lateLand?.call(); // after this read took its answer
      _lateLand = null;
      if (u.queryParameters['select'] == 'transformation_photo_urls') {
        return _json(then, 200, request);
      }
      final hold = holdOnce.remove(id);
      if (hold != null) {
        held.add(id!);
        await hold.future;
      }
      if (readsFail) {
        return _json({'message': 'boom', 'code': 'XX000'}, 500, request);
      }
      return _json(then, 200, request);
    }
    return _json([], 200, request);
  }

  /// Like storage: names that start with `search`, at most `limit` of them, in
  /// name order. The folder has 120 older photos and one whose name starts
  /// with the uploaded one's.
  http.StreamedResponse _list(Map body, http.BaseRequest request) {
    final search = body['search'] as String? ?? '';
    checks.add('${body['prefix']}/$search');
    if (remove == _Remove.checkThrown || remove == _Remove.check400) {
      final status = remove == _Remove.check400 ? 400 : 500;
      return _json({'statusCode': '$status', 'message': 'boom'}, status,
          request);
    }
    final name = uploads.last.split('/').last;
    final names = [
      for (var i = 0; i < 120; i++) '${1000000000000 + i}.jpg',
      if (remove == _Remove.stillThere) name,
      '$name.copy',
    ].where((n) => n.startsWith(search)).take(body['limit'] as int);
    return _json([
      for (final n in names) {'name': n, 'id': n}
    ], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// A Supabase session for [uid] (the JWT is not verified client-side).
String _session(String uid) {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
          1000;
  final jwt = '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
      'not-verified-client-side';
  return jsonEncode({
    'access_token': jwt,
    'token_type': 'bearer',
    'expires_in': 315360000,
    'expires_at': exp,
    'refresh_token': 'test-refresh-$uid',
    'user': {
      'id': uid,
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  });
}

class _SeededSession extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => _session(_a);
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

class _OnRemove extends NavigatorObserver {
  final VoidCallback onRemove;
  _OnRemove(this.onRemove);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onRemove();
}

const _later =
    'try again in a moment. If it keeps happening, contact support.';
const _fileLeft = 'A copy may remain in storage — mention it to support.';
const _unconfirmed =
    "Couldn't confirm the photo was added — look for it here before adding "
    'it again.';

void main() {
  late _Server server;
  late Directory tmp;
  late File photo;
  final failures = <AppFailure>[];

  /// What the gallery picker answers: the file, null (cancelled), or throws.
  late Future<Object?> Function() picker;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server()..reset();
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
    tmp = Directory.systemTemp.createTempSync('coach_business_orphans');
    photo = File('${tmp.path}/after.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (call) => picker());
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUp(() async {
    server.reset();
    picker = () async => photo.path;
    failures.clear();
    setFailureSink(failures.add);
    await Supabase.instance.client.auth.recoverSession(_session(_a));
  });

  tearDown(resetFailureSink);

  GoTrueClient auth() => Supabase.instance.client.auth;

  /// A shown transformation photo is a NetworkImage; flutter_test answers
  /// every HTTP request with 400, so its load fails. That (and only that) is
  /// taken here so it does not fail the test.
  void takeImageLoadFailure(WidgetTester tester) {
    final e = tester.takeException();
    if (e != null && e is! NetworkImageLoadException) throw e;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
      takeImageLoadFailure(tester);
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CoachBusinessScreen()));
    await settle(tester);
    expect(find.text('Alpha bio'), findsOneWidget, reason: 'premise: A shown');
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  /// A signs out, then [uid] signs in — through the real auth stream.
  /// [observeSignOut] false: both happen before the screen gets a frame.
  Future<void> switchTo(WidgetTester tester, String? uid,
      {bool observeSignOut = true}) async {
    await tester.runAsync(() => auth().signOut());
    if (observeSignOut) await settle(tester);
    if (uid != null) {
      await tester.runAsync(() => auth().recoverSession(_session(uid)));
    }
    await settle(tester);
  }

  Future<void> showTab(WidgetTester tester, String tab) async {
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
    takeImageLoadFailure(tester);
  }

  // The four Profile fields, in order.
  Finder tagline() => find.byType(TextField).at(0);
  Finder bio() => find.byType(TextField).at(1);
  Finder price() => find.byType(TextField).at(2);
  Finder years() => find.byType(TextField).at(3);
  String textOf(WidgetTester tester, Finder f) =>
      tester.widget<TextField>(f).controller!.text;

  Finder dialogField() => find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(TextField));

  Future<void> typeCert(WidgetTester tester, String name) async {
    await tester.tap(find.text('+ Add').first);
    await settle(tester); // not pumpAndSettle: the photo tile may be busy
    await tester.enterText(dialogField(), name);
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await settle(tester);
  }

  Map<String, Object?> lastPatch() {
    final w = server.patches.last;
    return jsonDecode(w.substring(w.indexOf('{'))) as Map<String, Object?>;
  }

  Set<String> origins() => failures.map((f) => f.origin).toSet();

  /// [pumpUntil], taking the shown photo's image-load failure meanwhile.
  Future<void> waitFor(WidgetTester tester, bool Function() done, String what) =>
      pumpUntil(tester, () {
        takeImageLoadFailure(tester);
        return done();
      }, what: what);

  /// Adds a photo and waits until the reload after it has landed (the tile is
  /// busy until then).
  Future<void> addPhotoAndRefresh(WidgetTester tester) async {
    final before = server.patches.length;
    await tester.tap(find.text('Add Photo'));
    await waitFor(tester, () => server.patches.length > before,
        'the photo update');
    await waitFor(tester, () => find.text('Add Photo').evaluate().isNotEmpty,
        'the reload after the photo');
    await settle(tester);
  }

  // ── (a) the certification dialog ──────────────────────────────────────────
  group('(a) the certification dialog closes with its coach', () {
    for (final observe in [true, false]) {
      testWidgets(
          'A → B (${observe ? 'sign-out observed' : 'same-frame switch'}): the '
          "dialog and A's typed text are gone, nothing is written or said, "
          "and B's own list shows", (tester) async {
        await open(tester);
        await typeCert(tester, 'CSCS');
        final add =
            tester.widget<TextButton>(find.widgetWithText(TextButton, 'Add'));
        final cancel = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'));
        await switchTo(tester, _b, observeSignOut: observe);
        expect(find.byType(AlertDialog), findsNothing,
            reason: "THE defect: A's dialog open on B's screen");
        expect(find.text('CSCS'), findsNothing);
        expect(find.widgetWithText(Chip, 'NASM-CPT'), findsNothing);
        expect(find.widgetWithText(Chip, 'ACE-CPT'), findsOneWidget,
            reason: "B's own list");
        // A press that still reaches the closed dialog's buttons neither
        // writes nor pops the screen under it.
        add.onPressed!();
        cancel.onPressed!();
        await settle(tester);
        expect(find.byType(CoachBusinessScreen), findsOneWidget);
        expect(server.patches, isEmpty);
        expect(server.rows[_b]!['certifications'], ['ACE-CPT']);
        expect(find.byType(SnackBar), findsNothing,
            reason: 'B did not open the dialog');
        await close(tester);
      });
    }

    for (final button in ['Add', 'Invite']) {
      testWidgets('a press on $button between the close and the next frame '
          'does not pop the screen', (tester) async {
      VoidCallback? add;
      AlertDialog? stillMounted;
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          navigatorObservers: [
            _OnRemove(() => scheduleMicrotask(() {
                  stillMounted =
                      tester.widgetList<AlertDialog>(find.byType(AlertDialog)).firstOrNull;
                  add?.call();
                }))
          ],
          home: const CoachBusinessScreen()));
      await settle(tester);
      if (button == 'Invite') {
        await showTab(tester, 'Team');
        await tester.tap(find.text('Invite Assistant Coach'));
        await tester.pumpAndSettle();
        await tester.enterText(dialogField(), 'invitee-of-a@example.com');
      } else {
        await typeCert(tester, 'CSCS');
      }
      add = tester
          .widget<TextButton>(find.widgetWithText(TextButton, button))
          .onPressed;
      await tester.runAsync(() => auth().recoverSession(_session(_b)));
      await settle(tester);
      expect(stillMounted, isNotNull,
          reason: 'premise: closed, its widgets not yet gone');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CoachBusinessScreen), findsOneWidget);
      if (button == 'Invite') await showTab(tester, 'Profile');
      expect(find.text('Bravo bio'), findsOneWidget);
      expect(server.patches, isEmpty);
      expect(server.calls.where((c) => c.contains('coach_team_invites')),
          isEmpty);
      await close(tester);
      });
    }

    testWidgets('sign-out closes it; nothing is written when A is back',
        (tester) async {
      await open(tester);
      await typeCert(tester, 'CSCS');
      await switchTo(tester, null);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('CSCS'), findsNothing);
      await switchTo(tester, _a);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.widgetWithText(Chip, 'NASM-CPT'), findsOneWidget);
      expect(server.patches, isEmpty);
      await close(tester);
    });

    testWidgets(
        "negative control: the same coach's session event keeps the dialog "
        'and what was typed; Add then writes to that coach', (tester) async {
      await open(tester);
      await typeCert(tester, 'CSCS');
      await tester.runAsync(() => auth().recoverSession(_session(_a)));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(textOf(tester, dialogField()), 'CSCS');
      await tester.tap(find.text('Add'));
      await settle(tester);
      expect(server.patches.single, contains('id=eq.$_a'));
      expect(lastPatch()['certifications'], ['NASM-CPT', 'CSCS']);
      expect(find.widgetWithText(Chip, 'CSCS'), findsOneWidget);
      expect(find.byType(CoachBusinessScreen), findsOneWidget);
      await close(tester);
    });

    testWidgets('positive control: Cancel closes the dialog only, and a '
        'removal writes the rest of the list', (tester) async {
      await open(tester);
      await typeCert(tester, 'CSCS');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CoachBusinessScreen), findsOneWidget);
      expect(server.patches, isEmpty);
      await tester.tap(find.byIcon(Icons.close));
      await settle(tester);
      expect(lastPatch()['certifications'], isEmpty);
      expect(find.text('No certifications yet — tap “+ Add”.'), findsOneWidget);
      await close(tester);
    });

    // Security S3 / UX #2 (round 2): the invite dialog goes the same way.
    Future<void> typeInvite(WidgetTester tester) async {
      await showTab(tester, 'Team');
      await tester.tap(find.text('Invite Assistant Coach'));
      await tester.pumpAndSettle();
      await tester.enterText(dialogField(), 'invitee-of-a@example.com');
      await tester.pump(const Duration(seconds: 1)); // into the undo history
    }

    bool invited() => server.calls.any((c) =>
        c.contains('coach_team_invites') || c.contains('send-invite-email'));

    for (final to in [_b, null]) {
      testWidgets(
          "${to == null ? 'sign-out' : 'A → B'}: the invite dialog and A's "
          'typed email are gone, undo does not bring it back, nothing is '
          'written, sent or said', (tester) async {
        await open(tester);
        await typeInvite(tester);
        final invite = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Invite'));
        final cancel = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'));
        await switchTo(tester, to);
        expect(find.byType(AlertDialog), findsNothing,
            reason: "THE defect: A's dialog open on B's screen");
        Future<void> undo() async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump(const Duration(seconds: 1));
        }

        await undo();
        expect(find.text('invitee-of-a@example.com'), findsNothing);
        // A press that still reaches the closed dialog's buttons does nothing.
        invite.onPressed!();
        cancel.onPressed!();
        await settle(tester);
        expect(find.byType(CoachBusinessScreen), findsOneWidget);
        expect(invited(), isFalse);
        expect(find.byType(SnackBar), findsNothing);
        if (to == _b) {
          // B's own dialog starts empty, with nothing of A's to undo.
          await tester.tap(find.text('Invite Assistant Coach'));
          await tester.pumpAndSettle();
          await tester.tap(dialogField());
          await tester.pump();
          await undo();
          expect(textOf(tester, dialogField()), '');
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        }
        await close(tester);
      });
    }

    testWidgets('negative control: the same coach\'s session event keeps the '
        "invite dialog; Invite then joins that coach's team", (tester) async {
      await open(tester);
      await typeInvite(tester);
      await tester.runAsync(() => auth().recoverSession(_session(_a)));
      await settle(tester);
      expect(textOf(tester, dialogField()), 'invitee-of-a@example.com');
      await tester.tap(find.text('Invite'));
      await waitFor(tester, invited, 'the invite');
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CoachBusinessScreen), findsOneWidget);
      await close(tester);
    });

    testWidgets('negative control: Cancel, or Invite with no email, only '
        'closes the invite dialog', (tester) async {
      await open(tester);
      await showTab(tester, 'Team');
      for (final button in ['Cancel', 'Invite']) {
        await tester.tap(find.text('Invite Assistant Coach'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(CoachBusinessScreen), findsOneWidget);
      }
      expect(invited(), isFalse);
      expect(find.byType(SnackBar), findsNothing);
      await close(tester);
    });

    /// What activating [button] calls.
    VoidCallback handlerOf(WidgetTester tester, String button) => button ==
            '+ Add'
        ? tester
            .widget<GestureDetector>(find
                .ancestor(
                    of: find.text(button).first,
                    matching: find.byType(GestureDetector))
                .first)
            .onTap!
        : tester
            .widget<OutlinedButton>(find.ancestor(
                of: find.text(button),
                matching: find.bySubtype<OutlinedButton>()))
            .onPressed!;

    // QA point 4 (round 2): the route is known before its first frame.
    for (final (tab, button) in const [
      ('Profile', '+ Add'),
      ('Team', 'Invite Assistant Coach'),
    ]) {
      testWidgets('$button tapped, B signs in before its first frame: no '
          'dialog opens over B', (tester) async {
        await open(tester);
        await showTab(tester, tab);
        await tester.tap(find.text(button).first); // no frame
        await tester.runAsync(() => auth().recoverSession(_session(_b)));
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing,
            reason: "THE defect: A's dialog opened over B's screen");
        expect(find.byType(CoachBusinessScreen), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        await showTab(tester, 'Profile');
        expect(textOf(tester, bio()), 'Bravo bio');
        await close(tester);
      });

      // Not a second pointer tap: the navigator absorbs those until the next
      // frame. An activation from assistive technology is not absorbed.
      testWidgets('$button activated twice in one frame opens one dialog, and '
          'a switch leaves none', (tester) async {
        await open(tester);
        await showTab(tester, tab);
        final activate = handlerOf(tester, button);
        activate();
        activate();
        await settle(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        await switchTo(tester, _b);
        expect(find.byType(AlertDialog), findsNothing,
            reason: 'a second, untracked dialog stayed over B');
        await close(tester);
      });

      testWidgets('$button tapped on A\'s last frame after the screen heard of '
          'the switch is refused out loud: no dialog', (tester) async {
        await open(tester);
        await showTab(tester, tab);
        await tester.runAsync(() => auth().recoverSession(_session(_b)));
        await tester.tap(find.text(button).first); // still A's frame
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
            find.textContaining("you're signed in to a different account now"),
            findsOneWidget);
        await close(tester);
      });
    }

    // QA mutant M2 (round 2). The dialog answered for A, and the answer is
    // delivered only after B is signed in AND B's profile is shown: then the
    // screen's own "is this the coach shown?" passes, and only "is this the
    // coach the dialog was opened for?" refuses. The delivery is a microtask,
    // so it is held by running the opening tap in a zone that holds them.
    for (final toB in [true, false]) {
      for (final (tab, button, action) in const [
        ('Profile', '+ Add', 'Add'),
        ('Team', 'Invite Assistant Coach', 'Invite'),
      ]) {
        testWidgets(
            "A's $action delivered late, "
            '${toB ? 'once B is shown: refused, nothing written' : 'A still shown (control): written for A'}',
            (tester) async {
          var holding = false;
          final held = <void Function()>[];
          final zone = Zone.current.fork(
              specification: ZoneSpecification(
                  scheduleMicrotask: (_, parent, z, f) => holding
                      ? held.add(f)
                      : parent.scheduleMicrotask(z, f)));
          await open(tester);
          await showTab(tester, tab);
          zone.run(handlerOf(tester, button));
          await settle(tester);
          await tester.enterText(dialogField(), 'late-from-a');
          await tester.pump();
          holding = true;
          await tester.tap(find.widgetWithText(TextButton, action));
          await settle(tester);
          expect(held, isNotEmpty, reason: 'premise: the answer is held');
          if (toB) {
            await switchTo(tester, _b);
            await showTab(tester, 'Profile');
            expect(textOf(tester, bio()), 'Bravo bio', reason: 'premise');
          }
          holding = false;
          held.forEach(zone.run);
          await settle(tester);
          await settle(tester);
          if (toB) {
            expect(server.patches, isEmpty,
                reason: "A's certification into B's row");
            expect(invited(), isFalse, reason: "A's invite into B's team");
            expect(
                find.textContaining(
                    "you're signed in to a different account now"),
                findsOneWidget);
          } else if (action == 'Add') {
            expect(server.patches.single, contains('id=eq.$_a'));
            expect(lastPatch()['certifications'], ['NASM-CPT', 'late-from-a']);
          } else {
            expect(invited(), isTrue);
          }
          await close(tester);
        });
      }
    }
  });

  // ── (b) unsaved edits ─────────────────────────────────────────────────────
  group('(b) a same-coach refresh keeps what was typed', () {
    /// The server changes every field meanwhile (another device).
    void changeOnServer() => server.rows[_a] = {
          ...server.rows[_a]!,
          'bio': 'Alpha bio v2',
          'tagline': 'Alpha tagline v2',
          'pricing_monthly': 200,
          'years_experience': 6,
          'specialties': ['Mobility'],
        };

    testWidgets(
        'the reload after a photo: touched fields keep the typed value, '
        'untouched ones take the fresh value; Save writes exactly that',
        (tester) async {
      await open(tester);
      await tester.enterText(bio(), 'Typed bio');
      await tester.enterText(price(), '149');
      changeOnServer();
      await addPhotoAndRefresh(tester);
      expect(textOf(tester, bio()), 'Typed bio',
          reason: 'THE defect: the refresh discarded unsaved text');
      expect(textOf(tester, price()), '149');
      expect(textOf(tester, tagline()), 'Alpha tagline v2',
          reason: 'untouched: the fresh value');
      expect(textOf(tester, years()), '6');
      await tapSave(tester);
      expect(lastPatch(), {
        'bio': 'Typed bio',
        'pricing_monthly': 149,
        'years_experience': 6,
        'tagline': 'Alpha tagline v2',
        'specialties': ['Mobility'],
        'certifications': ['NASM-CPT'],
      });
      await close(tester);
    });

    testWidgets('Retry after a failed refresh: typed before and after the '
        'failure is kept, untouched fields take the fresh value',
        (tester) async {
      await open(tester);
      await tester.enterText(bio(), 'Typed bio');
      server.readsFail = true;
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(
          tester,
          () => find
              .widgetWithText(SnackBarAction, 'Retry')
              .evaluate()
              .isNotEmpty,
          what: 'the Retry notice',
          step: const Duration(milliseconds: 500));
      await settle(tester);
      expect(textOf(tester, bio()), 'Typed bio');
      await tester.enterText(years(), '7');
      server.readsFail = false;
      changeOnServer();
      await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
      await pumpUntil(
          tester, () => textOf(tester, tagline()) == 'Alpha tagline v2',
          what: 'the retried refresh');
      expect(textOf(tester, bio()), 'Typed bio');
      expect(textOf(tester, years()), '7');
      expect(textOf(tester, price()), '200');
      await close(tester);
    });

    testWidgets('typed while the refresh is on its way is kept',
        (tester) async {
      await open(tester);
      changeOnServer();
      final read = server.holdOnce[_a] = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => server.held.contains(_a),
          what: 'the refresh read');
      await tester.enterText(tagline(), 'Typed tagline');
      read.complete();
      await settle(tester);
      expect(textOf(tester, tagline()), 'Typed tagline');
      expect(textOf(tester, bio()), 'Alpha bio v2');
      await close(tester);
    });

    testWidgets('a field the coach emptied stays empty', (tester) async {
      await open(tester);
      await tester.enterText(tagline(), '');
      changeOnServer();
      await addPhotoAndRefresh(tester);
      expect(textOf(tester, tagline()), '');
      expect(textOf(tester, bio()), 'Alpha bio v2');
      await close(tester);
    });

    testWidgets('specialties chosen and not saved are kept; Save writes them',
        (tester) async {
      await open(tester);
      await showTab(tester, 'Specialties');
      await tester.tap(find.text('Yoga'));
      await tester.pump();
      await showTab(tester, 'Profile');
      changeOnServer();
      await addPhotoAndRefresh(tester);
      await tapSave(tester);
      expect(lastPatch()['specialties'], ['HIIT', 'Yoga']);
      await close(tester);
    });

    testWidgets('a saved field is no longer "typed": the next refresh takes '
        'the fresh value (saved untrimmed text and 150.0 included)',
        (tester) async {
      await open(tester);
      await tester.enterText(bio(), 'Typed bio ');
      await tester.enterText(price(), '150.0');
      await tapSave(tester);
      expect(find.text('Profile updated!'), findsOneWidget);
      expect(lastPatch()['bio'], 'Typed bio');
      await addPhotoAndRefresh(tester);
      expect(textOf(tester, bio()), 'Typed bio');
      expect(textOf(tester, price()), '150');
      changeOnServer();
      await addPhotoAndRefresh(tester);
      expect(textOf(tester, bio()), 'Alpha bio v2');
      expect(textOf(tester, price()), '200');
      await close(tester);
    });

    testWidgets('text typed while a Save is on its way is kept by a refresh',
        (tester) async {
      await open(tester);
      await tester.enterText(bio(), 'Saved bio');
      final patch = server.patchGate = Completer<void>();
      await tester.tap(find.text('Save'));
      await pumpUntil(tester, () => server.patches.isNotEmpty, what: 'the save');
      await tester.enterText(bio(), 'Saved bio and more');
      patch.complete();
      server.patchGate = null;
      await settle(tester);
      await addPhotoAndRefresh(tester);
      expect(textOf(tester, bio()), 'Saved bio and more');
      await close(tester);
    });

    testWidgets('a refresh read that began BEFORE a Save does not put the old '
        'text back after it', (tester) async {
      await open(tester);
      final read = server.holdOnce[_a] = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => server.held.contains(_a),
          what: 'the refresh read (answers with the row as it was)');
      await tester.enterText(bio(), 'Saved bio');
      await tapSave(tester);
      expect(server.rows[_a]!['bio'], 'Saved bio', reason: 'premise: saved');
      read.complete();
      await settle(tester);
      expect(textOf(tester, bio()), 'Saved bio',
          reason: 'the older read overwrote the saved text');
      await close(tester);
    });

    testWidgets('a certification being written is not taken off the list by a '
        'refresh', (tester) async {
      await open(tester);
      final read = server.holdOnce[_a] = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => server.held.contains(_a),
          what: 'the refresh read');
      final patch = server.patchGate = Completer<void>();
      await typeCert(tester, 'CSCS');
      await tester.tap(find.text('Add'));
      await pumpUntil(tester, () => server.patches.length == 2,
          what: 'the certification write');
      read.complete();
      await settle(tester);
      expect(find.widgetWithText(Chip, 'CSCS'), findsOneWidget);
      patch.complete();
      await settle(tester);
      expect(find.widgetWithText(Chip, 'CSCS'), findsOneWidget);
      await tapSave(tester);
      expect(lastPatch()['certifications'], ['NASM-CPT', 'CSCS']);
      await close(tester);
    });

    testWidgets('a certification that then fails goes back to the list the '
        'refresh read', (tester) async {
      await open(tester);
      final read = server.holdOnce[_a] = Completer<void>();
      server.rows[_a] = {
        ...server.rows[_a]!,
        'certifications': ['NASM-CPT', 'ACE-CPT'],
      };
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => server.held.contains(_a),
          what: 'the refresh read');
      final patch = server.patchGate = Completer<void>();
      await typeCert(tester, 'CSCS');
      await tester.tap(find.text('Add'));
      await pumpUntil(tester, () => server.patches.length == 2,
          what: 'the certification write');
      server.patchMode = _Patch.zeroRows;
      read.complete();
      await settle(tester);
      patch.complete();
      await settle(tester);
      expect(find.widgetWithText(Chip, 'CSCS'), findsNothing);
      expect(find.widgetWithText(Chip, 'ACE-CPT'), findsOneWidget);
      await close(tester);
    });

    testWidgets("a different coach: A's typed text is cleared, B's own values "
        "show and are what B saves; A's typed text does not come back",
        (tester) async {
      await open(tester);
      await tester.enterText(bio(), 'Typed by A');
      await tester.enterText(price(), '149');
      await switchTo(tester, _b);
      expect(find.text('Typed by A'), findsNothing);
      expect(textOf(tester, bio()), 'Bravo bio');
      expect(textOf(tester, price()), '99');
      await tapSave(tester);
      expect(server.patches.single, contains('id=eq.$_b'));
      expect(lastPatch()['bio'], 'Bravo bio');
      expect(lastPatch()['pricing_monthly'], 99);
      await switchTo(tester, _a);
      expect(textOf(tester, bio()), 'Alpha bio');
      expect(textOf(tester, price()), '175');
      await close(tester);
    });

    // Security S1 (round 2): text or a tap that still reaches A's fields after
    // they were dropped, before the form is rebuilt, is not B's edit.
    for (final to in [_b, _a]) {
      testWidgets(
          '${to == _b ? 'A → B' : 'A signs out and in again'}: text arriving '
          'in the frame before the form rebuilds is not kept or saved',
          (tester) async {
        await open(tester);
        await tester.enterText(bio(), 'Typed by A');
        if (to == _a) await tester.runAsync(() => auth().signOut());
        await tester.runAsync(() => auth().recoverSession(_session(to)));
        // The platform's text still reaches the field on A's last frame.
        expect(bio().evaluate(), isNotEmpty, reason: 'premise: no frame yet');
        tester.testTextInput
            .updateEditingValue(const TextEditingValue(text: 'Typed by A!'));
        expect(textOf(tester, bio()), 'Typed by A!', reason: 'premise');
        await settle(tester);
        expect(textOf(tester, bio()), to == _b ? 'Bravo bio' : 'Alpha bio',
            reason: "THE defect: A's text kept as an unsaved edit");
        await tapSave(tester);
        expect(server.patches.single, contains('id=eq.$to'));
        expect(lastPatch()['bio'], to == _b ? 'Bravo bio' : 'Alpha bio');
        await close(tester);
      });
    }

    testWidgets('A → B: a specialty tapped in the frame before the form '
        "rebuilds is not saved into B's row", (tester) async {
      await open(tester);
      await showTab(tester, 'Specialties');
      await tester.runAsync(() => auth().recoverSession(_session(_b)));
      await tester.tap(find.text('Powerlifting')); // A's last frame
      await settle(tester);
      await tapSave(tester);
      expect(server.patches.single, contains('id=eq.$_b'));
      expect(lastPatch()['specialties'], ['Yoga'],
          reason: "THE defect: A's late tap replaced B's specialties");
      await close(tester);
    });

    testWidgets("a same-frame switch, then B's read fails: nothing A typed is "
        'shown; once B is read, B takes B\'s values', (tester) async {
      await open(tester);
      await tester.enterText(bio(), 'Typed by A');
      server.readsFail = true;
      await switchTo(tester, _b, observeSignOut: false);
      expect(find.text('Typed by A'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      server.readsFail = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(textOf(tester, bio()), 'Bravo bio');
      await close(tester);
    });

    testWidgets('sign-out and back in: the typed text is gone, the saved '
        'profile shows', (tester) async {
      await open(tester);
      await tester.enterText(bio(), 'Typed by A');
      await switchTo(tester, null);
      expect(find.text('Typed by A'), findsNothing);
      await switchTo(tester, _a);
      expect(textOf(tester, bio()), 'Alpha bio');
      await close(tester);
    });

    testWidgets("A's save confirmed only after A signed out and in again: the "
        'profile is read again, so the form shows what was saved',
        (tester) async {
      await open(tester);
      await tester.enterText(bio(), 'Saved bio');
      final patch = server.patchGate = Completer<void>();
      await tester.tap(find.text('Save'));
      await pumpUntil(tester, () => server.patches.isNotEmpty, what: 'the save');
      await switchTo(tester, _a);
      expect(textOf(tester, bio()), 'Alpha bio',
          reason: 'premise: read before the save landed');
      patch.complete();
      await settle(tester);
      expect(textOf(tester, bio()), 'Saved bio');
      await close(tester);
    });

    testWidgets('negative control: a refresh to genuinely empty values empties '
        'untouched fields, and is not a failure', (tester) async {
      await open(tester);
      server.rows[_a] = {
        ..._rowA(),
        'bio': null,
        'tagline': null,
        'pricing_monthly': null,
        'years_experience': null,
        'specialties': <String>[],
        'certifications': <String>[],
      };
      await addPhotoAndRefresh(tester);
      for (final f in [bio(), tagline(), price(), years()]) {
        expect(textOf(tester, f), '');
      }
      expect(find.text('No certifications yet — tap “+ Add”.'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      await close(tester);
    });

    testWidgets('positive control: a normal Save writes the form',
        (tester) async {
      await open(tester);
      await tester.enterText(tagline(), 'New tagline');
      await tapSave(tester);
      expect(server.patches.single, contains('id=eq.$_a'));
      expect(lastPatch()['tagline'], 'New tagline');
      expect(find.text('Profile updated!'), findsOneWidget);
      await close(tester);
    });
  });

  // ── (c) the uploaded file ─────────────────────────────────────────────────
  group('(c) a photo that is not added leaves no file behind', () {
    /// Exactly one removal, of exactly the object this tap uploaded.
    void expectOneRemoveOfTheUpload() {
      expect(server.uploads, hasLength(1), reason: 'premise');
      expect(
          server.uploads.single, startsWith('coach-transformations/$_a/'));
      expect(server.removes, [
        [server.uploads.single]
      ], reason: 'THE defect: the uploaded file was left in coach-media');
    }

    Future<void> addPhoto(WidgetTester tester) async {
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty,
          what: 'the Add Photo outcome');
      await settle(tester);
    }

    Set<String> removalFailures() =>
        origins().where((o) => o.endsWith('_removeUploaded')).toSet();

    for (final (patch, said) in const [
      (_Patch.refused, "Couldn't add the photo — $_later"),
      (
        _Patch.zeroRows,
        "Couldn't add the photo — nothing was changed. Try again in a moment. "
            'If it keeps happening, contact support.'
      ),
    ]) {
      testWidgets('update ${patch.name}: the file is removed, the failure is '
          'said, the tile is ready again', (tester) async {
        server.patchMode = patch;
        await open(tester);
        await addPhoto(tester);
        expect(find.text(said), findsOneWidget);
        expectOneRemoveOfTheUpload();
        expect(server.removedAs, [_a]);
        expect(find.text('Photo added'), findsNothing);
        expect(server.rows[_a]!['transformation_photo_urls'], isEmpty);
        expect(removalFailures(), isEmpty, reason: 'the cleanup worked');
        expect(find.text('Add Photo'), findsOneWidget);
        await close(tester);
      });
    }

    // Security S4 (round 2): nothing is removed under another account's login
    // (it could not be anyway): the file is kept, and that is recorded.
    for (final to in [_b, null]) {
      testWidgets(
          '${to == null ? 'sign-out' : 'A → B'} while the photo uploads: no '
          'removal is sent, the kept file is recorded, no profile write, '
          'nothing said', (tester) async {
        await open(tester);
        final upload = server.uploadGate = Completer<void>();
        await tester.tap(find.text('Add Photo'));
        await pumpUntil(tester, () => server.uploads.isNotEmpty,
            what: "A's upload");
        await switchTo(tester, to);
        upload.complete();
        await settle(tester);
        await settle(tester);
        expect(server.removes, isEmpty,
            reason: "THE defect: a DELETE of A's file under $to's login");
        expect(server.checks, isEmpty);
        expect(removalFailures(), hasLength(1));
        expect(server.patches, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
        if (to == _b) expect(textOf(tester, bio()), 'Bravo bio');
        await close(tester);
      });
    }

    for (final patch in [_Patch.zeroRows, _Patch.refused]) {
      testWidgets('A → B while the update is on its way, then it is '
          '${patch.name}: no removal under B, recorded, nothing said to B',
          (tester) async {
        await open(tester);
        final gate = server.patchGate = Completer<void>();
        await tester.tap(find.text('Add Photo'));
        await pumpUntil(tester, () => server.patches.isNotEmpty,
            what: "A's photo update");
        await switchTo(tester, _b);
        server.patchMode = patch;
        gate.complete();
        await settle(tester);
        await settle(tester);
        expect(server.removes, isEmpty);
        expect(removalFailures(), hasLength(1));
        expect(find.byType(SnackBar), findsNothing);
        expect(textOf(tester, bio()), 'Bravo bio');
        await close(tester);
      });
    }

    testWidgets('A → B while the removal is on its way (it removes nothing): '
        'not checked under B, recorded, nothing said to B', (tester) async {
      server
        ..patchMode = _Patch.refused
        ..remove = _Remove.absent;
      final gate = server.removeGate = Completer<void>();
      await open(tester);
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => server.removes.isNotEmpty,
          what: 'the removal');
      await switchTo(tester, _b);
      gate.complete();
      await settle(tester);
      await settle(tester);
      expect(server.removedAs, [_a]);
      expect(server.checks, isEmpty);
      expect(removalFailures(), hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      await close(tester);
    });

    testWidgets('positive control: A signs out and in again while the photo '
        "uploads: the file is removed, under A's own login", (tester) async {
      await open(tester);
      final upload = server.uploadGate = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => server.uploads.isNotEmpty,
          what: "A's upload");
      // Back, but not read yet: the upload is for a form no longer shown.
      final read = server.holdOnce[_a] = Completer<void>();
      await switchTo(tester, _a);
      upload.complete();
      await settle(tester);
      expectOneRemoveOfTheUpload();
      expect(server.removedAs, [_a]);
      expect(server.patches, isEmpty);
      expect(removalFailures(), isEmpty);
      read.complete();
      await settle(tester);
      await close(tester);
    });

    testWidgets("A → B while the update is on its way and it IS saved: A's "
        'photo is kept (no removal)', (tester) async {
      await open(tester);
      final gate = server.patchGate = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => server.patches.isNotEmpty,
          what: "A's photo update");
      await switchTo(tester, _b);
      gate.complete();
      await settle(tester);
      await settle(tester);
      expect(server.removes, isEmpty);
      expect(server.rows[_a]!['transformation_photo_urls'], hasLength(1));
      expect(server.rows[_b]!['transformation_photo_urls'], isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await close(tester);
    });

    for (final (patch, refusal) in const [
      (_Patch.zeroRows, "Couldn't add the photo — nothing was changed. Try "
          'again in a moment. If it keeps happening, contact support.'),
      (_Patch.refused, "Couldn't add the photo — $_later"),
    ]) {
      for (final remove in _Remove.values) {
        final gone = remove == _Remove.removed || remove == _Remove.absent;
        testWidgets(
            'update ${patch.name}, removal ${remove.name}: '
            '${gone ? 'the failure only' : 'recorded and said; still a failure'}',
            (tester) async {
          server
            ..patchMode = patch
            ..remove = remove;
          await open(tester);
          await addPhoto(tester);
          expectOneRemoveOfTheUpload();
          expect(
              origins().contains('CoachBusinessScreen._removeUploaded'), !gone,
              reason: 'recorded unless it is known to be gone');
          expect(
              find.text(gone ? refusal : "Couldn't add the photo — $_later $_fileLeft"),
              findsOneWidget);
          expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration,
              Duration(seconds: gone ? 4 : 10),
              reason: 'the longer text stays longer (UX #4)');
          // An empty answer is checked — that object, once; nothing else is.
          expect(
              server.checks,
              remove == _Remove.removed || remove == _Remove.thrown
                  ? isEmpty
                  : [server.uploads.single]);
          expect(find.text('Photo added'), findsNothing);
          expect(find.textContaining('boom'), findsNothing);
          await close(tester);
        });
      }
    }

    // Security S2 (round 2): no answer, or one that says nothing about the
    // write. Whatever the profile says when read, the file is never deleted.
    void expectKeptAndUnconfirmed() {
      expect(server.uploads, hasLength(1), reason: 'premise');
      expect(server.removes, isEmpty,
          reason: 'THE defect: a photo that is (or will be) on the profile '
              'has no file');
      expect(find.text(_unconfirmed), findsOneWidget);
      expect(find.text('Photo added'), findsNothing);
      expect(find.textContaining('lost'), findsNothing);
      expect(
          origins(),
          contains(
              'CoachBusinessScreen._uploadTransformationPhoto.unconfirmed'));
      expect(find.text('Add Photo'), findsOneWidget, reason: 'ready again');
    }

    for (final code in [
      'PGRST000', 'PGRST001', 'PGRST002', 'PGRST003', //
      '08000', '08006', '08P01', '57P01', '57P05', '58000', '58030', '40003',
    ]) {
      testWidgets('answered $code, but the update landed: the file is kept, '
          'the photo is listed', (tester) async {
        server
          ..patchMode = _Patch.codedLanded
          ..patchCode = code;
        await open(tester);
        await addPhoto(tester);
        expectKeptAndUnconfirmed();
        expect(server.rows[_a]!['transformation_photo_urls'], hasLength(1));
        await close(tester);
      });
    }

    // Not those classes: the database did refuse (rolled back).
    for (final code in ['57014', '40001', '42501', '23514', 'PGRST204']) {
      testWidgets('negative control: refused with $code → the file is removed',
          (tester) async {
        server
          ..patchMode = _Patch.codedLanded
          ..patchCode = code;
        await open(tester);
        await addPhoto(tester);
        expectOneRemoveOfTheUpload();
        expect(
            find.text("Couldn't add the photo — $_later"), findsOneWidget);
        await close(tester);
      });
    }

    for (final patch in [_Patch.gateway, _Patch.networkLost]) {
      testWidgets('update ${patch.name}, not landed: the file is kept (an '
          'accepted orphan), recorded, and nothing is called added',
          (tester) async {
        server.patchMode = patch;
        await open(tester);
        final reads = server.calls
            .where((c) => c.startsWith('GET /rest/v1/user_profiles'))
            .length;
        await addPhoto(tester);
        expectKeptAndUnconfirmed();
        expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration,
            const Duration(seconds: 10),
            reason: 'the longer text stays longer (UX #4)');
        expect(
            server.calls
                .where((c) => c.startsWith('GET /rest/v1/user_profiles'))
                .length,
            reads + 1,
            reason: 'the profile is read again');
        expect(server.rows[_a]!['transformation_photo_urls'], isEmpty);
        await close(tester);
      });
    }

    testWidgets('no answer, and the update lands AFTER the profile was read '
        'again: the file is kept', (tester) async {
      server.patchMode = _Patch.landsAfterRead;
      await open(tester);
      await addPhoto(tester);
      expectKeptAndUnconfirmed();
      expect(server.rows[_a]!['transformation_photo_urls'], hasLength(1),
          reason: 'premise: landed after the read');
      await close(tester);
    });

    testWidgets('no answer, landed, and the stored URL is percent-encoded: '
        'the file is kept (S5)', (tester) async {
      final odd = File('${tmp.path}/after.j^g')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      picker = () async => odd.path;
      server.patchMode = _Patch.networkLanded;
      await open(tester);
      await addPhoto(tester);
      expect(
          '${(server.rows[_a]!['transformation_photo_urls'] as List).single}',
          contains('%5E'),
          reason: 'premise: not the raw path');
      expectKeptAndUnconfirmed();
      await close(tester);
    });

    testWidgets('a raw-named file that is still there is found in the listing '
        '(not taken for gone because its URL is percent-encoded)',
        (tester) async {
      final odd = File('${tmp.path}/after.j^g')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      picker = () async => odd.path;
      server
        ..patchMode = _Patch.refused
        ..remove = _Remove.stillThere;
      await open(tester);
      await addPhoto(tester);
      expect(find.text("Couldn't add the photo — $_later $_fileLeft"),
          findsOneWidget);
      expect(removalFailures(), hasLength(1));
      await close(tester);
    });

    testWidgets('no answer, but the update landed: the photo shows after the '
        're-read; the next photo keeps it', (tester) async {
      server.patchMode = _Patch.networkLanded;
      await open(tester);
      await addPhoto(tester);
      expectKeptAndUnconfirmed();
      server.patchMode = _Patch.ok;
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => server.patches.length == 2,
          what: 'the second photo');
      await settle(tester);
      expect(lastPatch()['transformation_photo_urls'], hasLength(2));
      await close(tester);
    });

    testWidgets('no answer and the profile cannot be read again: the file is '
        'kept, the profile shown stays, the failed refresh is recorded',
        (tester) async {
      server.patchMode = _Patch.networkLost;
      await open(tester);
      server.readsFail = true;
      await addPhoto(tester);
      expectKeptAndUnconfirmed();
      expect(textOf(tester, bio()), 'Alpha bio');
      expect(origins(), contains('CoachBusinessScreen._load'));
      await close(tester);
    });

    testWidgets('A → B while the update is on its way and it gets no answer: '
        'kept and recorded, nothing said to B', (tester) async {
      server.patchMode = _Patch.networkLanded;
      await open(tester);
      final gate = server.patchGate = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => server.patches.isNotEmpty,
          what: "A's photo update");
      await switchTo(tester, _b);
      gate.complete();
      await settle(tester);
      await settle(tester);
      expect(server.removes, isEmpty);
      expect(
          origins(),
          {'CoachBusinessScreen._uploadTransformationPhoto.unconfirmed'});
      expect(find.byType(SnackBar), findsNothing);
      expect(server.rows[_b]!['transformation_photo_urls'], isEmpty);
      await close(tester);
    });

    testWidgets('negative control: an upload that fails uploaded nothing to '
        'remove', (tester) async {
      server.uploadFails = true;
      await open(tester);
      await addPhoto(tester);
      expect(find.text("Couldn't add the photo — $_later"), findsOneWidget);
      expect(server.removes, isEmpty);
      expect(server.patches, isEmpty);
      await close(tester);
    });

    testWidgets('positive control: a photo that is added is listed, and '
        'nothing is removed', (tester) async {
      await open(tester);
      await addPhotoAndRefresh(tester);
      expect(server.removes, isEmpty);
      expect(
          '${(lastPatch()['transformation_photo_urls'] as List).single}',
          endsWith(server.uploads.single));
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(failures, isEmpty);
      await close(tester);
    });
  });

  // ── (c) the picker ────────────────────────────────────────────────────────
  group('(c) the photo picker', () {
    Future<void> tapAdd(WidgetTester tester) async {
      await tester.tap(find.text('Add Photo'));
      await settle(tester);
    }

    testWidgets('photo access denied: recorded, and the next step is Settings',
        (tester) async {
      picker = () async => throw PlatformException(
          code: 'photo_access_denied', message: 'secret platform text');
      await open(tester);
      await tapAdd(tester);
      expect(
          find.text("Couldn't open your photos — allow photo access in "
              'Settings, then try again.'),
          findsOneWidget);
      expect(find.textContaining('secret'), findsNothing);
      expect(origins(), {'CoachBusinessScreen._pickPhoto'});
      expect(server.uploads, isEmpty);
      expect(find.text('Add Photo'), findsOneWidget, reason: 'ready again');
      await close(tester);
    });

    testWidgets('any other picker failure: recorded and said', (tester) async {
      picker = () async => throw PlatformException(code: 'invalid_image');
      await open(tester);
      await tapAdd(tester);
      expect(
          find.text("Couldn't open your photos — $_later"), findsOneWidget);
      expect(origins(), {'CoachBusinessScreen._pickPhoto'});
      expect(server.uploads, isEmpty);
      await close(tester);
    });

    testWidgets('an unreadable file: recorded and said', (tester) async {
      picker = () async => '${tmp.path}/missing.jpg';
      await open(tester);
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty,
          what: 'the outcome');
      await settle(tester);
      expect(
          find.text("Couldn't use that photo — $_later"), findsOneWidget);
      expect(origins(), {'CoachBusinessScreen._pickPhoto.read'});
      expect(server.uploads, isEmpty);
      await close(tester);
    });

    testWidgets("the picker fails after B signed in: recorded, nothing said "
        'to B', (tester) async {
      final gate = Completer<Object?>();
      picker = () => gate.future;
      await open(tester);
      await tester.tap(find.text('Add Photo'));
      await tester.pump();
      await switchTo(tester, _b);
      gate.completeError(PlatformException(code: 'photo_access_denied'));
      await settle(tester);
      expect(origins(), {'CoachBusinessScreen._pickPhoto'});
      expect(find.byType(SnackBar), findsNothing);
      expect(server.uploads, isEmpty);
      await close(tester);
    });

    testWidgets('negative control: a cancel stays silent', (tester) async {
      picker = () async => null;
      await open(tester);
      await tapAdd(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(failures, isEmpty);
      expect(server.uploads, isEmpty);
      expect(server.removes, isEmpty);
      expect(find.text('Add Photo'), findsOneWidget);
      await close(tester);
    });
  });
}
