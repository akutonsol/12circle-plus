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
  Completer<void>? storageGate;
  final writes = <String>[];
  final calls = <String>[];

  void reset() {
    rows
      ..clear()
      ..[_a] = _rowA()
      ..[_b] = _rowB();
    modes.clear();
    gates.clear();
    storageGate = null;
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
      await open(tester);
      await tester.tap(find.text('+ Add').first);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'CSCS');
      await tester.pump();
      await switchTo(tester, _b);
      await tester.tap(find.text('Add'));
      await settle(tester);
      expect(profileWrites(), isEmpty,
          reason: "A's certification (and A's list) into B's row");
      expect(
          find.text("Couldn't add the certification — you're signed in to a "
              'different account now. Nothing was changed.'),
          findsOneWidget);
      expect(find.widgetWithText(Chip, 'CSCS'), findsNothing);
      expect(find.widgetWithText(Chip, 'ACE-CPT'), findsOneWidget,
          reason: "B's own list, untouched");
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'a photo picked for A and returned after B signed in is not uploaded '
        "or written into B's row", (tester) async {
      await open(tester);
      pickerGate = Completer<void>();
      await tester.tap(find.text('Add Photo'));
      await tester.pump();
      expect(picks, 1, reason: 'premise: the picker is open');
      await switchTo(tester, _b);
      pickerGate!.complete();
      await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty,
          what: 'the Add Photo outcome (a SnackBar)');
      await settle(tester);
      expect(server.writes.where((w) => w.contains('/storage/')), isEmpty,
          reason: "A's photo uploaded under B's folder");
      expect(profileWrites(), isEmpty,
          reason: "A's photo list (plus the new photo) written into B's row");
      expect(
          find.text("Couldn't add the photo — you're signed in to a different "
              'account now. Nothing was changed.'),
          findsOneWidget);
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
              'different account now. Nothing was changed.'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ── 6. FL-55 · Add Photo in-flight guard ──────────────────────────────────
  group('Add Photo while a photo is on its way', () {
    Finder tile() => find.bySemanticsLabel(
        RegExp(r'^(Add|Adding) transformation photo$'));

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
              label: 'Add transformation photo',
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
              label: 'Adding transformation photo',
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
}
