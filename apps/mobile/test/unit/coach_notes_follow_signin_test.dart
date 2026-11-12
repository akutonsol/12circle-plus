import 'dart:convert';

import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach_notes/data/coach_note_service.dart';
import 'package:circle_fitness/features/coach_notes/domain/coach_note_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A coach's private notes about a client were kept for the next coach.
//
// `coach_notes` is "visible only to the authoring coach — never the client"
// (coach_note_service.dart), and what makes it so is RLS (018: "coach manages
// own notes"). `getNotes(clientId)` filters on the client only, so the rows
// that come back depend on who is signed in, and nothing in the app says so:
// the QAX-SES-01 guard, which looks for `auth.currentUser`, cannot see it.
//
// `clientNotesProvider` is a non-autoDispose family keyed by the client. A
// coach who read client X's notes and was then signed out without a page
// reload (another tab signing out, admin/vendor/reset-password sign-out, any
// native build) left them cached, and the next coach to open client X on that
// device was shown them: notes on injuries, motivation, adherence, written
// for one coach's eyes. Multi-coach clients are supported (coach_provider.dart).
//
// The provider now watches the signed-in user, so the notes are read again
// for whoever is signed in.

class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('[]')),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
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

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    );

/// What RLS hands back: each coach's own notes, whatever the query asks.
class _RlsNotes extends CoachNoteService {
  String? signedIn;
  final Map<String, List<CoachNote>> byCoach;
  _RlsNotes(this.byCoach);

  @override
  Future<List<CoachNote>> getNotes(String clientId) async =>
      [...?byCoach[signedIn]].where((n) => n.clientId == clientId).toList();
}

CoachNote _note(String id, String body) => CoachNote(
    id: id,
    clientId: 'client-x',
    body: body,
    tag: 'injury',
    createdAt: DateTime.utc(2026, 11, 1));

final _signedIn = StateProvider<User?>((ref) => null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _EmptyClient(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  late _RlsNotes server;
  late ProviderContainer app;

  setUp(() {
    server = _RlsNotes({
      'coach-a': [_note('n1', 'Left knee: no deep squats until cleared')],
      'coach-b': [],
    });
    app = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
      coachNoteServiceProvider.overrideWithValue(server),
    ]);
    addTearDown(app.dispose);
  });

  /// Signs [coach] in, on the app and on the server, the way a sign-in
  /// without a page reload does.
  void signIn(String coach) {
    server.signedIn = coach;
    app.read(_signedIn.notifier).state = _user(coach);
  }

  Future<List<String>> notesOnClientX() async =>
      (await app.read(clientNotesProvider('client-x').future))
          .map((n) => n.body)
          .toList();

  test('the next coach on the device is not shown the previous coach\'s '
      'private notes', () async {
    signIn('coach-a');
    // Coach A has the client's notes open: the sheet watches the provider.
    app.listen(clientNotesProvider('client-x'), (_, __) {});
    expect(await notesOnClientX(), ['Left knee: no deep squats until cleared'],
        reason: 'guard the premise: coach A sees their own note');

    signIn('coach-b');
    expect(await notesOnClientX(), isEmpty,
        reason: "THE defect: coach B was shown coach A's note from the cache");
  });

  test('the same coach still gets their notes back (control)', () async {
    signIn('coach-a');
    expect(await notesOnClientX(), hasLength(1));
    signIn('coach-a');
    expect(await notesOnClientX(), ['Left knee: no deep squats until cleared']);
  });

  test('a coach who signs in after another reads their OWN notes', () async {
    server.byCoach['coach-b'] = [_note('n2', 'Prefers morning check-ins')];
    signIn('coach-a');
    expect(await notesOnClientX(), hasLength(1));
    signIn('coach-b');
    expect(await notesOnClientX(), ['Prefers morning check-ins']);
  });
}
