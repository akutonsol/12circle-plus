import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/features/coach/presentation/coach_business_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/pump_until.dart';

// P0-FL-54 · the coach Business Profile belongs to the coach signed in NOW.
//
// The screen kept coach A's whole `user_profiles` row, team and reviews in
// State and never followed the session. After A signed out and B signed in
// (the screen still open), B saw A's bio, price, certifications, team and
// reviews, and every write — Save, a certification, a transformation photo
// (which COPIES the shown list and appends), a team invite — went out with
// `.eq('id', <B's id>)` / `coach_id: <B's id>` carrying A's state: A's data in
// B's row. A late A read could also land after B signed in.
//
// Every transition here goes through the REAL Supabase auth stream: the
// session is signed out and another one recovered, exactly as a sign-in does;
// the screen hears it on `onAuthStateChange`.
//
// FL-55 (same file) · Add Photo had no in-flight guard: a double tap started
// two uploads that each copied the same list, so one photo was lost.
//
// HOW TO SEE IT FAIL: `git checkout b7ec6ef -- \
//   apps/mobile/lib/features/coach/presentation/coach_business_screen.dart`.

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

/// B with genuinely nothing yet: no price, certifications, photos, team or
/// reviews. A real empty answer — it must render as empty, not as a failure.
Map<String, Object?> _rowBEmpty() => {
      'id': _b,
      'bio': null,
      'tagline': null,
      'pricing_monthly': null,
      'years_experience': null,
      'specialties': <String>[],
      'certifications': <String>[],
      'transformation_photo_urls': <String>[],
      'rating_avg': null,
    };

/// What is A's and must never appear while B (or nobody) is signed in.
const _aValues = ['Alpha bio', 'Alpha tagline', '175', 'NASM-CPT'];
const _aTeam = 'Ann Assist';
const _aReview = 'Alpha review';

enum _Mode { ok, fails, pending }

class _Server extends http.BaseClient {
  final rows = <String, Map<String, Object?>>{};
  final modes = <String, _Mode>{};

  /// Holds a coach's reads of `<table>` until completed: key `table:uid`.
  final gates = <String, Completer<void>>{};

  /// Holds only the NEXT read of `table:uid`, answering with the row as it
  /// was when that read arrived (an older answer landing late).
  final holdOnce = <String, Completer<void>>{};

  /// Holds the answer to a write (PATCH/POST) on `<table>` (recorded first).
  final writeGates = <String, Completer<void>>{};
  Completer<void>? storageGate;

  /// Writes (PATCH/POST) on these tables answer 500 (after any write gate).
  final failWrites = <String>{};
  final writes = <String>[];
  final calls = <String>[];

  void reset() {
    rows
      ..clear()
      ..[_a] = _rowA()
      ..[_b] = _rowB();
    modes.clear();
    gates.clear();
    holdOnce.clear();
    writeGates.clear();
    storageGate = null;
    failWrites.clear();
    writes.clear();
    calls.clear();
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
    if (path.startsWith('/storage/v1/')) {
      writes.add('${request.method} $path');
      if (storageGate != null) await storageGate!.future;
      return _json({'Key': 'coach-media/x.jpg'}, 200, request);
    }
    final table = path.split('/').last;
    if (request.method == 'PATCH' || request.method == 'POST') {
      final body = await request.finalize().bytesToString();
      writes.add('${request.method} /$table?${u.query} $body');
      final wg = writeGates[table];
      if (wg != null) await wg.future;
      if (failWrites.contains(table)) {
        return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
      }
      final id = _eq(u, 'id');
      // Like the database: a profile update is what later reads return.
      final row = id == null ? null : rows[id];
      if (table == 'user_profiles' && row != null) {
        rows[id!] = {...row, ...(jsonDecode(body) as Map<String, Object?>)};
      }
      return u.queryParameters.containsKey('select')
          ? _json([
              {'id': id}
            ], 200, request)
          : http.StreamedResponse(const Stream.empty(), 201, request: request);
    }
    final uid = _eq(u, 'id') ?? _eq(u, 'coach_id');
    final gate = gates['$table:$uid'];
    if (gate != null) await gate.future;
    final once = holdOnce.remove('$table:$uid');
    if (once != null) {
      final then = rows[uid];
      await once.future;
      if (table == 'user_profiles') return _json(then, 200, request);
    }
    switch (table) {
      case 'user_profiles':
        switch (modes[uid] ?? _Mode.ok) {
          case _Mode.fails:
            return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
          case _Mode.pending:
            await Completer<void>().future;
          case _Mode.ok:
        }
        return _json(rows[uid], 200, request);
      case 'coach_team_members':
        if (rows[uid]?['bio'] == null) return _json([], 200, request);
        return _json([
          {'coach_id': uid, 'member_id': 'm-$uid', 'role': 'assistant_coach'}
        ], 200, request);
      case 'team_member_profiles':
        final ids = (u.queryParameters['id'] ?? '');
        return _json([
          if (ids.contains('m-$_a'))
            {'id': 'm-$_a', 'first_name': 'Ann', 'last_name': 'Assist'},
          if (ids.contains('m-$_b'))
            {'id': 'm-$_b', 'first_name': 'Bea', 'last_name': 'Backup'},
        ], 200, request);
      case 'coach_reviews':
        if (rows[uid]?['bio'] == null) return _json([], 200, request);
        return _json([
          {
            'id': 'r-$uid',
            'coach_id': uid,
            'rating': 5,
            'review_text': uid == _a ? _aReview : 'Bravo review',
            'created_at': '2026-10-01T00:00:00Z',
            'public_profiles': {'first_name': 'Cal', 'last_name': 'Client'},
          }
        ], 200, request);
    }
    return _json([], 200, request);
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

void main() {
  late _Server server;
  late Directory tmp;
  late File photo;

  /// When set, the gallery picker stays open until it completes.
  Completer<void>? pickerGate;
  var picks = 0;

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
    tmp = Directory.systemTemp.createTempSync('coach_business_signin');
    photo = File('${tmp.path}/after.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (call) async {
      picks++;
      if (pickerGate != null) await pickerGate!.future;
      return photo.path;
    });
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUp(() async {
    server.reset();
    pickerGate = null;
    picks = 0;
    await Supabase.instance.client.auth.recoverSession(_session(_a));
  });

  GoTrueClient auth() => Supabase.instance.client.auth;

  /// A shown transformation photo is a NetworkImage; flutter_test answers
  /// every HTTP request with 400, so its load fails. That (and only that) is
  /// taken here so it does not fail the test — anything else still does.
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

  Future<void> open(WidgetTester tester, {bool wait = true}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CoachBusinessScreen()));
    if (wait) await settle(tester);
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
  }

  /// Nothing of A's on any tab that is reachable.
  Future<void> expectNothingOfA(WidgetTester tester) async {
    for (final v in _aValues) {
      expect(find.text(v), findsNothing, reason: "A's \"$v\" on screen");
    }
    if (find.text('Team').evaluate().isNotEmpty &&
        find.text('Save').evaluate().isNotEmpty) {
      await showTab(tester, 'Team');
      expect(find.text(_aTeam), findsNothing, reason: "A's team");
      await showTab(tester, 'Reviews');
      expect(find.text(_aReview), findsNothing, reason: "A's reviews");
      expect(find.text('4.5'), findsNothing, reason: "A's rating");
      await showTab(tester, 'Profile');
    }
  }

  List<String> profileWrites() =>
      server.writes.where((w) => w.contains('/user_profiles')).toList();

  /// No write of any kind carries A's values into another row.
  void expectNoWriteOfAInto(String uid) {
    for (final w in server.writes) {
      if (!w.contains(uid)) continue;
      for (final v in [..._aValues, 'Alpha']) {
        expect(w, isNot(contains(v)), reason: "A's \"$v\" written into $uid");
      }
    }
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await settle(tester);
  }

  // ── 1. Coach B signs in over coach A's screen ─────────────────────────────
  group('A → B through the auth stream', () {
    for (final observe in [true, false]) {
      final how = observe ? 'sign-out observed' : 'same-frame switch';
      for (final bMode in _Mode.values) {
        testWidgets(
            "($how) B's read ${bMode.name}: A's profile, team and reviews are "
            "gone, and nothing of A's is ever saved into B's row",
            (tester) async {
          server.modes[_b] = bMode;
          await open(tester);
          expect(find.text('Alpha bio'), findsOneWidget, reason: 'premise');

          await switchTo(tester, _b, observeSignOut: observe);
          await expectNothingOfA(tester);
          switch (bMode) {
            case _Mode.ok:
              expect(find.text('Bravo bio'), findsOneWidget,
                  reason: "B's own profile once read");
              await showTab(tester, 'Team');
              expect(find.text('Bea Backup'), findsOneWidget);
              await showTab(tester, 'Reviews');
              expect(find.text('Bravo review'), findsOneWidget);
              await showTab(tester, 'Profile');
              await tapSave(tester);
              final w = profileWrites();
              expect(w, hasLength(1), reason: 'B saves B');
              expect(w.single, contains('id=eq.$_b'));
              expect(w.single, contains('Bravo bio'));
            case _Mode.fails:
              expect(find.text("Couldn't load your business profile"),
                  findsOneWidget);
              expect(find.text('Save'), findsNothing,
                  reason: 'nothing of B was read, so nothing may be saved');
              expect(find.byType(TextField), findsNothing);
            case _Mode.pending:
              expect(find.bySemanticsLabel('Loading your business profile'),
                  findsOneWidget);
              expect(find.text('Save'), findsNothing);
              expect(find.byType(TextField), findsNothing);
          }
          expectNoWriteOfAInto(_b);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  });

  // ── 2. A's read answers late, after B signed in ───────────────────────────
  group('a delayed A read is never applied', () {
    for (final (table, bMode) in const [
      ('user_profiles', _Mode.ok),
      ('user_profiles', _Mode.pending),
      ('coach_reviews', _Mode.ok),
    ]) {
      testWidgets("A's $table read lands after B signed in (B ${bMode.name})",
          (tester) async {
        final gate = server.gates['$table:$_a'] = Completer<void>();
        server.modes[_b] = bMode;
        await open(tester);
        expect(find.text('Alpha bio'), findsNothing, reason: 'premise: held');

        await switchTo(tester, _b);
        gate.complete(); // A's answer arrives now
        await settle(tester);
        await expectNothingOfA(tester);
        if (bMode == _Mode.ok) {
          expect(find.text('Bravo bio'), findsOneWidget);
          await tapSave(tester);
          expect(profileWrites().single, contains('id=eq.$_b'));
        } else {
          expect(find.text('Save'), findsNothing);
          expect(find.byType(TextField), findsNothing);
        }
        expectNoWriteOfAInto(_b);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  // ── 3. Sign-out ───────────────────────────────────────────────────────────
  testWidgets('sign-out leaves no coach profile visible; signing back in '
      "shows that coach's own profile again", (tester) async {
    await open(tester);
    expect(find.text('Alpha bio'), findsOneWidget, reason: 'premise');
    await switchTo(tester, null);
    await expectNothingOfA(tester);
    expect(find.text('Save'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
        find.text(
            "You're signed out — sign in again to see your business profile."),
        findsOneWidget);
    // UX N2: signed out is not a failed load, and a Try again that changes
    // nothing is not offered.
    expect(find.text("You're signed out"), findsOneWidget);
    expect(find.text("Couldn't load your business profile"), findsNothing);
    expect(find.text('Try again'), findsNothing);
    expect(profileWrites(), isEmpty);

    // Positive control: A signs back in → A's own profile, editable again.
    await tester.runAsync(() => auth().recoverSession(_session(_a)));
    await settle(tester);
    expect(find.text('Alpha bio'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  // ── 4. Same coach ─────────────────────────────────────────────────────────
  group('same coach', () {
    testWidgets(
        "the same coach's session event (token refresh) keeps the form and "
        'unsaved edits; Save writes them to that coach', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField).at(1), 'Edited bio');
      final reads = server.calls
          .where((c) => c.startsWith('GET /rest/v1/user_profiles'))
          .length;
      await tester.runAsync(() => auth().recoverSession(_session(_a)));
      await settle(tester);
      expect(find.text('Edited bio'), findsOneWidget);
      expect(
          server.calls
              .where((c) => c.startsWith('GET /rest/v1/user_profiles'))
              .length,
          reads,
          reason: 'same coach: nothing to re-read');
      await tapSave(tester);
      expect(profileWrites().single, contains('id=eq.$_a'));
      expect(profileWrites().single, contains('Edited bio'));
      expect(find.text('Profile updated!'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'a failed refresh (after adding a photo) keeps what was shown, says '
        'the refresh failed, and Save still works', (tester) async {
      await open(tester);
      server.modes[_a] = _Mode.fails; // the refresh after the photo fails
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => find.text('Photo added').evaluate().isNotEmpty,
          what: 'Photo added');
      await settle(tester);
      // The refresh notice is queued behind "Photo added": let that one go.
      // (Before the fix the failed refresh replaced the profile with the
      // load-failure screen instead.)
      await pumpUntil(
          tester,
          () =>
              find
                  .textContaining("Couldn't refresh your business profile")
                  .evaluate()
                  .isNotEmpty ||
              find
                  .text("Couldn't load your business profile")
                  .evaluate()
                  .isNotEmpty,
          what: 'the outcome of the failed refresh',
          step: const Duration(milliseconds: 500));
      await settle(tester);
      expect(
          find.text("Couldn't refresh your business profile — try again in a "
              'moment. If it keeps happening, contact support.'),
          findsOneWidget);
      expect(find.text("Couldn't load your business profile"), findsNothing,
          reason: 'confirmed data is kept, not replaced by a failure');
      expect(find.text('Alpha bio'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'NASM-CPT'), findsOneWidget);
      final patch = profileWrites().single;
      expect(patch, contains('id=eq.$_a'));
      expect(patch, contains('coach-transformations/$_a/'));
      await tapSave(tester);
      expect(profileWrites().last, contains('id=eq.$_a'));
      expect(profileWrites().last, contains('Alpha bio'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('positive control: a successful refresh shows what the '
        'server now holds', (tester) async {
      await open(tester);
      server.rows[_a] = {..._rowA(), 'bio': 'Alpha bio v2'};
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester,
          () => find.text('Alpha bio v2').evaluate().isNotEmpty,
          what: 'the refreshed profile');
      await settle(tester);
      expect(find.textContaining("Couldn't"), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ── 5. Writes started for A refuse once B is signed in ─────────────────────
  group('every write is keyed to the coach shown', () {
    testWidgets('positive control: A saves A, keyed to A', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField).at(0), 'New tagline');
      await tapSave(tester);
      final w = profileWrites().single;
      expect(w, contains('id=eq.$_a'));
      expect(w, contains('New tagline'));
      expect(w, contains('NASM-CPT'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'a certification typed for A and submitted after B signed in is '
        "refused — never written into B's row", (tester) async {
      // P0-FL-57b: the dialog closes when the screen hears of the switch, so
      // the only Add that can still be pressed is the one on A's last frame,
      // in the window before that (a listener registered before the screen's;
      // see 'in the window between …' below).
      VoidCallback? addOnAsFrame;
      final sub = auth().onAuthStateChange.listen((_) {
        final add = addOnAsFrame;
        if (add == null || auth().currentUser?.id != _b) return;
        addOnAsFrame = null;
        add();
      });
      addTearDown(sub.cancel);
      await open(tester);
      await tester.tap(find.text('+ Add').first);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'CSCS');
      await tester.pump();
      addOnAsFrame =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Add'))
              .onPressed;
      await tester.runAsync(() => auth().recoverSession(_session(_b)));
      await settle(tester);
      expect(addOnAsFrame, isNull, reason: 'premise: Add pressed as B');
      expect(find.byType(AlertDialog), findsNothing);
      expect(profileWrites(), isEmpty,
          reason: "A's certification (and A's list) into B's row");
      expect(
          find.text("Couldn't add the certification — you're signed in to a "
              'different account now. Nothing was changed. Check the profile '
              'shown, then try again.'),
          findsOneWidget);
      expect(find.widgetWithText(Chip, 'CSCS'), findsNothing);
      expect(find.widgetWithText(Chip, 'ACE-CPT'), findsOneWidget,
          reason: "B's own list, untouched");
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'a photo picked for A and returned after B signed in is not uploaded '
        "or written into B's row; B's tile is not busy for A's pick and B is "
        "told nothing about a tap B never made (UX N5)", (tester) async {
      await open(tester);
      pickerGate = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await tester.pump();
      expect(picks, 1, reason: 'premise: the picker is open');
      await switchTo(tester, _b);
      expect(find.text('Bravo bio'), findsOneWidget, reason: "B's profile");
      expect(find.text('Adding…'), findsNothing,
          reason: "B's tile busy for A's picker");
      expect(find.text('Add Photo'), findsOneWidget);
      pickerGate!.complete();
      await settle(tester);
      await settle(tester);
      expect(server.writes.where((w) => w.contains('/storage/')), isEmpty,
          reason: "A's photo uploaded under B's folder");
      expect(profileWrites(), isEmpty,
          reason: "A's photo list (plus the new photo) written into B's row");
      expect(find.byType(SnackBar), findsNothing,
          reason: "a late refusal for A's tap shown to B");
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        "an invite typed on A's team and sent after B signed in is refused",
        (tester) async {
      await open(tester);
      await showTab(tester, 'Team');
      await tester.tap(find.text('Invite Assistant Coach'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'assistant@example.com');
      await switchTo(tester, _b);
      await tester.tap(find.text('Invite'));
      await settle(tester);
      expect(server.writes.where((w) => w.contains('coach_team_invites')),
          isEmpty,
          reason: "A's invite joined B's team");
      expect(
          find.text("Couldn't save the invite — you're signed in to a "
              'different account now. Nothing was changed. Check the profile '
              'shown, then try again.'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ── 6. FL-55 · Add Photo in-flight guard ──────────────────────────────────
  group('Add Photo while a photo is on its way', () {
    // UX N6: the label starts with the visible words ("Add Photo" /
    // "Adding…") so Voice Control finds the tile by what it shows.
    Finder tile() => find.bySemanticsLabel(RegExp(
        r'^(Add Photo, transformation photo|Adding… transformation photo)$'));

    testWidgets('a double tap starts one upload (no second copy of the same '
        'list)', (tester) async {
      await open(tester);
      server.storageGate = Completer<void>();
      final spot = tester.getCenter(find.text('Add Photo'));
      await tester.tapAt(spot);
      await pumpUntil(tester,
          () => server.writes.any((w) => w.contains('/storage/')),
          what: 'the first upload');
      await tester.tapAt(spot); // the same tile again
      await settle(tester);
      expect(picks, 1, reason: 'THE defect: a second picker/upload started');
      expect(server.writes.where((w) => w.contains('/storage/')), hasLength(1));
      server.storageGate!.complete();
      await pumpUntil(tester, () => find.text('Photo added').evaluate().isNotEmpty,
          what: 'Photo added');
      await settle(tester);
      expect(profileWrites(), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'the tile is a labelled button, disabled and announced while '
        'uploading, and stays >= 44 px', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(
          tester.getSemantics(tile()),
          matchesSemantics(
              label: 'Add Photo, transformation photo',
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              hasTapAction: true));
      server.storageGate = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester,
          () => server.writes.any((w) => w.contains('/storage/')),
          what: 'the first upload');
      final busy = tester.getSemantics(tile());
      expect(
          busy,
          matchesSemantics(
              label: 'Adding… transformation photo',
              isButton: true,
              hasEnabledState: true,
              isEnabled: false,
              isLiveRegion: true));
      final size = tester.getSize(find.ancestor(
          of: find.text('Adding…'), matching: find.byType(GestureDetector)).first);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));

      server.storageGate!.complete();
      await pumpUntil(tester, () => find.text('Photo added').evaluate().isNotEmpty,
          what: 'Photo added');
      await settle(tester);
      expect(profileWrites(), hasLength(1));
      expect(find.text('Add Photo'), findsOneWidget, reason: 'enabled again');
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('positive control: two photos one after the other are both '
        'kept', (tester) async {
      // The refresh after each photo returns what the server now holds.
      await open(tester);
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => profileWrites().length == 1,
          what: 'the first photo write');
      await settle(tester);
      final first = profileWrites().single;
      final url = RegExp(r'"(http[^"]+)"').firstMatch(first)!.group(1)!;
      await pumpUntil(tester, () => find.text('Add Photo').evaluate().isNotEmpty,
          what: 'the tile enabled again');
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester, () => profileWrites().length == 2,
          what: 'the second photo write');
      await settle(tester);
      final second = profileWrites().last;
      expect(RegExp('http').allMatches(second.split(' ').last), hasLength(2),
          reason: 'both photos in the list');
      expect(second, contains(url));
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ── 7. Negative control: a real empty profile is empty, not a failure ─────
  testWidgets(
      'negative control: a coach with genuinely nothing yet (opened directly) '
      'renders empty states, not a failure', (tester) async {
    server.rows[_a] = {..._rowBEmpty(), 'id': _a};
    await open(tester);
    expect(find.text("Couldn't load your business profile"), findsNothing);
    expect(find.text('No certifications yet — tap “+ Add”.'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    await showTab(tester, 'Team');
    expect(find.text('No team members yet'), findsOneWidget);
    await showTab(tester, 'Reviews');
    expect(find.text('No reviews yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'negative control: B with genuinely nothing yet renders empty states, '
      'not a failure, and nothing of A', (tester) async {
    server.rows[_b] = _rowBEmpty();
    await open(tester);
    await switchTo(tester, _b);
    expect(find.text("Couldn't load your business profile"), findsNothing);
    expect(find.text('No certifications yet — tap “+ Add”.'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    await showTab(tester, 'Team');
    expect(find.text('No team members yet'), findsOneWidget);
    await showTab(tester, 'Reviews');
    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.text('--'), findsOneWidget, reason: 'no rating yet');
    await showTab(tester, 'Profile');
    await expectNothingOfA(tester);
    await tester.pumpWidget(const SizedBox());
  });

  // ── 8. Round 2 (review fixes) ─────────────────────────────────────────────
  group('round 2', () {
    bool emailed() => server.writes.any((w) => w.contains('send-invite-email'));

    Future<void> typeInvite(WidgetTester tester) async {
      await showTab(tester, 'Team');
      await tester.tap(find.text('Invite Assistant Coach'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'assistant@example.com');
    }

    // Security F1: the email names whoever is signed in when it is sent.
    testWidgets(
        'F1: B signs in while A\'s invite insert is in flight → no invite '
        'email under B\'s login, and nothing about it is said to B',
        (tester) async {
      await open(tester);
      await typeInvite(tester);
      final insert = server.writeGates['coach_team_invites'] = Completer<void>();
      await tester.tap(find.text('Invite'));
      await pumpUntil(tester,
          () => server.writes.any((w) => w.contains('coach_team_invites')),
          what: "A's invite insert");
      expect(server.writes.where((w) => w.contains('coach_team_invites')).single,
          contains('"coach_id":"$_a"'),
          reason: "premise: on A's own team");
      await switchTo(tester, _b);
      insert.complete();
      await settle(tester);
      await settle(tester);
      expect(emailed(), isFalse,
          reason: "THE defect: send-invite-email ran with B's login");
      expect(find.textContaining('Invite email sent'), findsNothing);
      expect(find.textContaining('Invite saved'), findsNothing);
      expect(find.textContaining('invite'), findsNothing,
          reason: 'nothing about A\'s invite is announced to B');
      expect(find.text('Bea Backup'), findsOneWidget, reason: "B's own team");
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('F1 positive control: with no switch the saved invite is '
        'emailed and its outcome announced', (tester) async {
      await open(tester);
      await typeInvite(tester);
      await tester.tap(find.text('Invite'));
      await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty,
          what: 'the invite outcome (a SnackBar)');
      expect(emailed(), isTrue);
      // The fake function answers without {sent: true}: said honestly.
      expect(find.textContaining('Invite saved, but the email'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    // Lead mutant M3: _isCurrentLoad without the seq check.
    testWidgets(
        'two loads for the same coach: the OLDER answer landing last is not '
        'applied over the newer one', (tester) async {
      await open(tester);
      await switchTo(tester, null);
      final older = server.holdOnce['user_profiles:$_a'] = Completer<void>();
      await tester.runAsync(() => auth().recoverSession(_session(_a)));
      await settle(tester); // A's first read is held (answers 'Alpha bio')
      server.rows[_a] = {..._rowA(), 'bio': 'Alpha bio v2'};
      await switchTo(tester, _a); // out and in again: a newer read
      expect(find.text('Alpha bio v2'), findsOneWidget, reason: 'premise');
      older.complete();
      await settle(tester);
      await settle(tester);
      expect(find.text('Alpha bio v2'), findsOneWidget,
          reason: 'the older read overwrote the newer one');
      expect(find.text('Alpha bio'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    // QA Gap 1: a save still on its way when B signs in.
    testWidgets(
        'a save in flight when B signs in is not reported on B\'s screen',
        (tester) async {
      await open(tester);
      final patch = server.writeGates['user_profiles'] = Completer<void>();
      await tester.tap(find.text('Save'));
      await pumpUntil(tester, () => profileWrites().isNotEmpty,
          what: "A's save");
      expect(profileWrites().single, contains('id=eq.$_a'),
          reason: "premise: A's own row");
      await switchTo(tester, _b);
      patch.complete();
      await settle(tester);
      await settle(tester);
      expect(find.text('Profile updated!'), findsNothing,
          reason: "A's save announced to B");
      expect(find.textContaining("Couldn't save"), findsNothing);
      expect(find.text('Bravo bio'), findsOneWidget);
      expectNoWriteOfAInto(_b);
      await tester.pumpWidget(const SizedBox());
    });

    // Lead mutants M4 (_requireShownCoach without the uid != _loadedFor
    // refusal) and M6 (build without the "not the signed-in coach's" gate).
    //
    // Between B's sign-in and its auth event reaching this screen, the
    // session is B's while the screen still holds A. A listener registered
    // BEFORE the screen's hears the event first — that is the window. In it,
    // a frame is built (what would be painted) and the Save button rendered
    // on A's last frame is pressed. Why not a plain tap: no frame can be
    // pumped between two listeners of one event.
    testWidgets(
        'in the window between B\'s sign-in and the screen hearing of it, A\'s '
        'data is not shown and a Save pressed then is refused', (tester) async {
      var armed = false;
      bool? aVisibleInWindow;
      VoidCallback? savePressedOnAsFrame;
      final sub = auth().onAuthStateChange.listen((_) {
        if (!armed || auth().currentUser?.id != _b) return;
        armed = false;
        tester.element(find.byType(CoachBusinessScreen)).markNeedsBuild();
        final owner = WidgetsBinding.instance.buildOwner!
          ..buildScope(WidgetsBinding.instance.rootElement!);
        aVisibleInWindow =
            _aValues.any((v) => find.text(v).evaluate().isNotEmpty);
        owner.finalizeTree(); // as a frame does: what left the tree is gone
        savePressedOnAsFrame!();
      });
      addTearDown(sub.cancel);
      await open(tester);
      expect(find.text('Alpha bio'), findsOneWidget, reason: 'premise');
      savePressedOnAsFrame =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
              .onPressed;
      armed = true;
      // B's session replaces A's (no sign-out event first).
      await tester.runAsync(() => auth().recoverSession(_session(_b)));
      await settle(tester);
      expect(aVisibleInWindow, isFalse,
          reason: "A's data rendered while B is signed in (M6)");
      expect(profileWrites(), isEmpty,
          reason: "A's form saved into B's row (M4)");
      expectNoWriteOfAInto(_b);
      expect(
          find.text("Couldn't save your profile — you're signed in to a "
              'different account now. Nothing was changed. Check the profile '
              'shown, then try again.'),
          findsOneWidget,
          reason: 'the Save pressed in the window is refused out loud '
              '(also proves the window was reached)');
      expect(find.text('Bravo bio'), findsOneWidget, reason: "then B's own");
      await tester.pumpWidget(const SizedBox());
    });

    // Lead mutant M9: confirmedProfileRead check removed.
    testWidgets(
        'the server answers the profile read with a row that is not the '
        'signed-in coach\'s → a failure, nothing of that row shown',
        (tester) async {
      server.rows[_a] = _rowB(); // id is B's
      await open(tester);
      expect(find.text("Couldn't load your business profile"), findsOneWidget);
      expect(find.text('Bravo bio'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    // QA Gap 2: the switch happens while the upload itself is running.
    testWidgets(
        'B signs in while A\'s photo is uploading → the photo list write is '
        'skipped and nothing is said to B', (tester) async {
      await open(tester);
      final upload = server.storageGate = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester,
          () => server.writes.any((w) => w.contains('/storage/')),
          what: "A's upload");
      await switchTo(tester, _b);
      upload.complete();
      await settle(tester);
      await settle(tester);
      expect(profileWrites(), isEmpty,
          reason: "a photo list written while B is signed in");
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Bravo bio'), findsOneWidget);
      expect(find.text('Add Photo'), findsOneWidget, reason: "B's tile idle");
      await tester.pumpWidget(const SizedBox());
    });

    // Lead mutant M8 / QA Gap 3: the "+ Add" header during an upload. A tap
    // in the same frame as the first one reaches the handler before the
    // header is rebuilt disabled — only the handler's guard stops it.
    for (final (first, second) in const [('tile', 'header'), ('header', 'header')]) {
      testWidgets(
          '$first then $second in the same frame start one photo, not two',
          (tester) async {
        await open(tester);
        pickerGate = Completer<void>();
        Finder target(String w) =>
            w == 'tile' ? find.text('Add Photo') : find.text('+ Add').last;
        final a = tester.getCenter(target(first));
        final b = tester.getCenter(target(second));
        await tester.tapAt(a);
        await tester.tapAt(b); // no frame in between
        await tester.pump();
        pickerGate!.complete();
        await pumpUntil(tester, () => find.text('Photo added').evaluate().isNotEmpty,
            what: 'Photo added');
        await settle(tester);
        expect(picks, 1, reason: 'a second picker/upload started');
        expect(server.writes.where((w) => w.startsWith('POST /storage/')),
            hasLength(1));
        expect(profileWrites(), hasLength(1));
        await tester.pumpWidget(const SizedBox());
      });
    }

    // UX N1: the "+ Add" headers are labelled, >= 44 px buttons; the photo
    // one is disabled while a photo is on its way.
    testWidgets('the "+ Add" headers are labelled buttons >= 44 px; the photo '
        'one is disabled while uploading', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      for (final label in ['Add certification', 'Add transformation photo']) {
        expect(
            tester.getSemantics(find.bySemanticsLabel(label)),
            matchesSemantics(
                label: label,
                isButton: true,
                hasEnabledState: true,
                isEnabled: true,
                hasTapAction: true),
            reason: label);
      }
      for (final e in find.text('+ Add').evaluate()) {
        final target = find
            .ancestor(
                of: find.byElementPredicate((x) => x == e),
                matching: find.byType(GestureDetector))
            .first;
        expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
        // The pill and its text are unchanged (12 px, not shrunk).
        expect((e.widget as Text).style?.fontSize, 12);
      }
      server.storageGate = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester,
          () => server.writes.any((w) => w.contains('/storage/')),
          what: 'the upload');
      expect(
          tester.getSemantics(find.bySemanticsLabel('Add transformation photo')),
          matchesSemantics(
              label: 'Add transformation photo',
              isButton: true,
              hasEnabledState: true,
              isEnabled: false));
      await tester.tap(find.text('+ Add').last);
      await settle(tester);
      expect(picks, 1, reason: 'the header started a second photo');
      server.storageGate!.complete();
      await pumpUntil(tester, () => find.text('Photo added').evaluate().isNotEmpty,
          what: 'Photo added');
      await settle(tester);
      expect(
          tester.getSemantics(find.bySemanticsLabel('Add transformation photo')),
          matchesSemantics(
              label: 'Add transformation photo',
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              hasTapAction: true),
          reason: 'enabled again');
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    // UX N3: the failed-refresh notice offers Retry.
    testWidgets('a failed refresh offers Retry; Retry shows what the server '
        'now holds', (tester) async {
      await open(tester);
      server.modes[_a] = _Mode.fails;
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(
          tester,
          () => find
              .textContaining("Couldn't refresh your business profile")
              .evaluate()
              .isNotEmpty,
          what: 'the refresh failure notice',
          step: const Duration(milliseconds: 500));
      await settle(tester);
      expect(find.text('Alpha bio'), findsOneWidget, reason: 'kept');
      final retry = find.widgetWithText(SnackBarAction, 'Retry');
      expect(retry, findsOneWidget);
      server.modes[_a] = _Mode.ok;
      server.rows[_a] = {...server.rows[_a]!, 'bio': 'Alpha bio v2'};
      await tester.tap(retry);
      await pumpUntil(tester,
          () => find.text('Alpha bio v2').evaluate().isNotEmpty,
          what: 'the retried refresh');
      expect(find.text("Couldn't load your business profile"), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    // UX N2 (opened while signed out).
    testWidgets('opened signed out: "You\'re signed out", no Try again',
        (tester) async {
      await tester.runAsync(() => auth().signOut());
      await open(tester);
      expect(find.text("You're signed out"), findsOneWidget);
      expect(
          find.text(
              "You're signed out — sign in again to see your business profile."),
          findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text("Couldn't load your business profile"), findsNothing);
      expect(server.calls.where((c) => c.contains('/rest/v1/')), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    // Negative control for N2: a real failed load still offers Try again.
    testWidgets('negative control: a failed load (signed in) keeps its heading '
        'and Try again', (tester) async {
      server.modes[_a] = _Mode.fails;
      await open(tester);
      expect(find.text("Couldn't load your business profile"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text("You're signed out"), findsNothing);
      server.modes[_a] = _Mode.ok;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Alpha bio'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
  // ── round 3 (QA r2: per-coach upload guard; G4, G5; Retry after close) ──
  group('round 3', () {
    bool tileBusy(WidgetTester tester) =>
        find.text('Adding…').evaluate().isNotEmpty &&
        find.text('Add Photo').evaluate().isEmpty;

    Future<void> typeInvite(WidgetTester tester) async {
      await showTab(tester, 'Team');
      await tester.tap(find.text('Invite Assistant Coach'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'assistant@example.com');
    }

    testWidgets(
        "A uploading → B signs in and taps Add Photo → A back: A's photo is "
        'still on its way, so A\'s Add Photo stays busy', (tester) async {
      await open(tester);
      pickerGate = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await tester.pump();
      expect(tileBusy(tester), isTrue, reason: 'premise: A busy');
      await switchTo(tester, _b);
      expect(tileBusy(tester), isFalse, reason: "B is not shown A's pick");
      await tester.tap(find.text('Add Photo'));
      await tester.pump();
      expect(tileBusy(tester), isTrue, reason: "premise: B's own pick");
      await switchTo(tester, _a);
      expect(find.text('Alpha bio'), findsOneWidget, reason: 'premise: A back');
      expect(tileBusy(tester), isTrue,
          reason: "THE r2 defect: B's tap replaced A's guard, so A could "
              'start a second copy of the same list');
      // The single-flight guard still holds for A: a tap starts nothing.
      final before = picks;
      await tester.tap(find.text('Adding…'));
      await tester.pump();
      expect(picks, before, reason: 'a second picker for A');
      pickerGate!.complete();
      await settle(tester);
      await settle(tester);
      expect(tileBusy(tester), isFalse, reason: 'all done: A idle again');
      await tester.pumpWidget(const SizedBox());
    });

    // G5: the finally clears only the finishing coach's own guard.
    testWidgets(
        "A's pick ends while B's upload is running: B's guard is not cleared",
        (tester) async {
      await open(tester);
      pickerGate = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await tester.pump();
      await switchTo(tester, _b);
      await tester.tap(find.text('Add Photo'));
      await tester.pump();
      final bUpload = server.storageGate = Completer<void>();
      pickerGate!.complete(); // A's pick (refused: B shown) and B's pick land
      await pumpUntil(tester,
          () => server.writes.any((w) => w.startsWith('POST /storage/')),
          what: "B's upload");
      await settle(tester);
      expect(server.writes.where((w) => w.startsWith('POST /storage/')),
          hasLength(1), reason: "only B's photo is uploaded");
      expect(tileBusy(tester), isTrue,
          reason: "A's finished pick cleared B's guard while B's upload runs");
      bUpload.complete();
      for (var i = 0; i < 6 && find.text('Photo added').evaluate().isEmpty; i++) {
        await settle(tester); // also takes the shown photo's image-load failure
      }
      expect(find.text('Photo added'), findsOneWidget);
      expect(profileWrites().single, contains('id=eq.$_b'));
      expectNoWriteOfAInto(_b);
      await tester.pumpWidget(const SizedBox());
    });

    // G4: the check AFTER send-invite-email.
    testWidgets(
        'B signs in while A\'s invite email is being sent → its outcome is '
        'not announced to B', (tester) async {
      await open(tester);
      await typeInvite(tester);
      final mail = server.writeGates['send-invite-email'] = Completer<void>();
      await tester.tap(find.text('Invite'));
      await pumpUntil(tester,
          () => server.writes.any((w) => w.contains('send-invite-email')),
          what: "A's invite email (sent while A is signed in)");
      await switchTo(tester, _b);
      mail.complete();
      await settle(tester);
      await settle(tester);
      expect(find.byType(SnackBar), findsNothing,
          reason: "A's invite outcome announced on B's screen");
      expect(find.textContaining('invite'), findsNothing,
          reason: "nothing about A's invite is announced to B");
      expect(find.text('Bea Backup'), findsOneWidget, reason: "B's own team");
      await tester.pumpWidget(const SizedBox());
    });

    // G4: the check in the insert-failure branch.
    testWidgets(
        "B signs in while A's invite insert is failing → \"Couldn't save the "
        'invite" is not said to B', (tester) async {
      await open(tester);
      await typeInvite(tester);
      server.failWrites.add('coach_team_invites');
      final insert = server.writeGates['coach_team_invites'] = Completer<void>();
      await tester.tap(find.text('Invite'));
      await pumpUntil(tester,
          () => server.writes.any((w) => w.contains('coach_team_invites')),
          what: "A's invite insert");
      await switchTo(tester, _b);
      insert.complete();
      await settle(tester);
      await settle(tester);
      expect(find.textContaining("Couldn't save the invite"), findsNothing,
          reason: "A's failure announced on B's screen");
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        "control: with no switch a failing insert IS said, and no email is sent",
        (tester) async {
      await open(tester);
      await typeInvite(tester);
      server.failWrites.add('coach_team_invites');
      await tester.tap(find.text('Invite'));
      await pumpUntil(tester,
          () => find.textContaining("Couldn't save the invite").evaluate().isNotEmpty,
          what: 'the insert failure');
      expect(server.writes.any((w) => w.contains('send-invite-email')), isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    // QA r2 note: Retry on a SnackBar that outlives the screen.
    testWidgets('Retry tapped after the screen closed and the coach signed out '
        'does nothing (no disposed-controller error, no read)', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('home'))));
      nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const CoachBusinessScreen()));
      await settle(tester);
      server.modes[_a] = _Mode.fails;
      await tester.tap(find.text('Add Photo'));
      await pumpUntil(tester,
          () => find.widgetWithText(SnackBarAction, 'Retry').evaluate().isNotEmpty,
          what: 'the Retry notice',
          step: const Duration(milliseconds: 500));
      nav.currentState!.pop();
      await settle(tester);
      expect(find.byType(CoachBusinessScreen), findsNothing, reason: 'premise');
      await switchTo(tester, null);
      final retry = find.widgetWithText(SnackBarAction, 'Retry');
      expect(retry, findsOneWidget, reason: 'premise: the notice outlived it');
      final reads = server.calls.length;
      await tester.tap(retry);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(server.calls.length, reads, reason: 'a load for a closed screen');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
