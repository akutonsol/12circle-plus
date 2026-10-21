import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:circle_fitness/features/onboarding/presentation/intake_flow_screen.dart';

/// **EC-03's END-TO-END RUNG**, and the arm the original fix left open.
///
/// WHY THIS RUNG WAS OUTSTANDING. §177.6 recorded it as *"remaining authorized frontier
/// rather than claimed"*: the failed-save banner *"needs a driver that makes the save
/// genuinely fail — a harder fixture than overriding one provider"*, and §16611 added that
/// forcing it *"would mean widening production API for a test on the onboarding path"*.
/// That second objection turns out not to apply. `Supabase.initialize` accepts an
/// `httpClient`, which is a seam the SDK publishes — so the real screen, the real
/// `_finish()`, the real `Supabase.instance.client` and the real failure path all run, and
/// only the network is substituted. **No production API is widened.**
///
/// WHAT IT PROVES, AND WHY A UNIT ASSERTION WOULD NOT. The `QA_CLOSURE_STANDARD` requires
/// an error-contract defect with a *user-facing success state* to be VERIFIED END-TO-END.
/// The success state here is `IntakeCompletePage` — *"That's everything we needed."* — so
/// the only evidence that counts is driving the flow the way a person drives it and showing
/// that page is **not** reached when nothing was saved.
///
/// THE DEFECT THIS FOUND. `_finish()` read `currentUser?.id` and wrapped the entire save in
/// `if (uid != null)`, with the completion state set unconditionally after it. EC-03 fixed
/// *"not saved because the save failed"* and left *"not saved because it was never
/// attempted"* — the same false success over a weaker premise. It needs no session expiry to
/// reach: `/intake` is listed in the router's `isAuthRoute` set (`app_router.dart:203`), so
/// an unauthenticated caller is **not** redirected to `/login`, and `_loadProgress` already
/// treats a null uid as "nothing to restore" and carries on. A person could answer all 26
/// steps and be told they were done while their PAR-Q answers, injuries, allergies, dietary
/// restrictions, goal, experience and **consent** were discarded.

/// Records every request and refuses to let one through.
///
/// A REFUSING CLIENT, NOT AN EMPTY ONE. Returning `200 []` to everything would let a save
/// look successful; returning `500` to everything makes any attempted write fail, which is
/// what the failed-save arm needs. The recorded bodies then support the strongest assertion
/// in this file: that **no request was ever made that sets `onboarding_complete: true`**.
class _RecordingClient extends http.BaseClient {
  final List<String> seen = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var body = '';
    if (request is http.Request) body = request.body;
    seen.add('${request.method} ${request.url.path}${request.url.query} $body');
    // Auth endpoints answer plausibly so the SDK does not throw on boot; everything else
    // fails, because a save that cannot reach the server is the condition under test.
    // LOGOUT IS ANSWERED; every other auth call is not. `signOut` reaches
    // `GoTrueAdminApi.signOut` even with `SignOutScope.local`, so refusing it throws an
    // `AuthApiException` out of the test rather than clearing the session — and clearing
    // the session is the precondition the second arm is built on, not the thing under test.
    if (request.url.path.contains('/auth/v1/logout')) {
      return http.StreamedResponse(const Stream.empty(), 204, request: request);
    }
    if (request.url.path.contains('/auth/v1/')) {
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":"offline"}')), 400,
          request: request, headers: {'content-type': 'application/json'});
    }
    // THE PROFILE READ SUCCEEDS; EVERY WRITE FAILS. `_loadProgress` restores `_step` from
    // `onboarding_step`, so answering this GET with 26 puts the flow on its final step —
    // which is what makes one tap reach `_finish()` instead of 26 input-gated pages.
    if (request.method == 'GET' && request.url.path.contains('user_profiles')) {
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode([
            {'id': _uid, 'onboarding_step': 26, 'onboarding_complete': false},
          ]))),
          200,
          request: request, headers: {'content-type': 'application/json'});
    }
    return http.StreamedResponse(
        Stream.value(utf8.encode('{"message":"QA EC-03 forced failure"}')), 500,
        request: request, headers: {'content-type': 'application/json'});
  }
}

/// A seeded session store.
///
/// WHY A SESSION IS NEEDED AT ALL FOR A TEST ABOUT A MISSING ONE. `_loadProgress` returns
/// early when `currentUser` is null, so the flow starts at step 0 — and the first form step
/// gates Continue on first name, last name, gender and date of birth. Driving 26 input-gated
/// pages is the *"harder fixture"* §177.6 described. But `_loadProgress` restores `_step`
/// from the profile's `onboarding_step`, so a session plus a profile read that answers 26
/// puts the flow **on the final step**, where one tap reaches `_finish()`.
///
/// The session is recovered by `recoverSession(accessToken())`, which decodes the JWT body
/// locally — no server round-trip while the token is unexpired — so a crafted,
/// far-future-`exp` token is enough. The signature is never verified client-side.
class _SeededSession extends LocalStorage {
  _SeededSession(this.json);
  String? json;

  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => json;
  @override
  Future<bool> hasAccessToken() async => json != null;
  @override
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async { json = null; }
}

const _uid = '00000000-0000-4000-8000-00000000ec03';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// An unexpired, unsigned JWT. gotrue reads `sub` and `exp` out of the body; the signature
/// is a server-side concern, so a placeholder is correct here rather than lazy.
String _jwt() {
  final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': _uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
      'qa-ec03-signature-not-verified-client-side';
}

String _sessionJson() => jsonEncode({
      'access_token': _jwt(),
      'token_type': 'bearer',
      'expires_in': 315360000,
      'refresh_token': 'qa-ec03-refresh',
      'user': {
        'id': _uid,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    });

/// In-memory PKCE storage. Without this, `Supabase.initialize` falls back to
/// `SharedPreferencesGotrueAsyncStorage` and throws `MissingPluginException` under the test
/// binding — the plugin channel does not exist on the host.
class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _m[key] = value;
  }
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

late final _RecordingClient client;
late final _SeededSession store;

void main() {
  setUpAll(() async {
    client = _RecordingClient();
    store = _SeededSession(_sessionJson());
    await Supabase.initialize(
      // An unroutable loopback port, so nothing can reach a real service even if the
      // injected client were bypassed. The harness must not be able to touch QA, let
      // alone production.
      url: 'http://127.0.0.1:1',
      publishableKey: 'qa-ec03-not-a-real-key',
      httpClient: client,
      authOptions: FlutterAuthClientOptions(
        localStorage: store,
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  /// Mounts the real screen and lets `_loadProgress` restore the final step.
  Future<void> openAtFinalStep(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: IntakeFlowScreen()),
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// The advance affordance, DISCOVERED rather than guessed — and the final step's is
  /// "Enter 12 Circle", not "Continue" or "Finish". Guessing the label stalled this drive
  /// twice: once on the welcome page's "Get Started" (a capital S) and once here.
  List<String> advanceLabels(WidgetTester t) => t
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .where((d) => RegExp(r'^(continue|finish|done|next|enter 12 circle)$',
              caseSensitive: false)
          .hasMatch(d.trim()))
      .toList();

  String allText(WidgetTester t) => t
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join(' | ');

  /// Writes to `user_profiles`, in order.
  ///
  /// WHY NOT "no request may set onboarding_complete:true" — WHICH IS WHAT I WROTE FIRST,
  /// AND THE TEST REJECTED IT. The *successful* save legitimately carries that flag: it is
  /// part of `_data.toSupabase()`. The original defect was not the flag's presence in the
  /// upsert; it was a **second, separate** write issued from the `catch` arm —
  /// `{'onboarding_complete': true, 'onboarding_step': 0}`, *"so the user isn't looped back
  /// here on next login"* — after the first one had already failed. So the shape to assert
  /// is the COUNT: one attempt, which failed, and nothing after it.
  List<String> profileWrites() => client.seen
      .where((r) => !r.startsWith('GET ') && r.contains('user_profiles'))
      .toList();

  testWidgets('EC-03 END-TO-END · a SAVE THAT FAILS does not present the intake as '
      'complete — the real screen, the real _finish(), a real 500 on the upsert',
      (t) async {
    expect(Supabase.instance.client.auth.currentUser?.id, _uid,
        reason: 'the seeded session must be recovered, or this tests nothing');

    await openAtFinalStep(t);
    client.seen.clear();

    // One tap, because the flow was restored to its final step. `_next()` sees
    // `_step == _totalSteps` and calls `_finish()`.
    final advance = advanceLabels(t);
    expect(advance, isNotEmpty,
        reason: 'no advance affordance on the final step: ${allText(t)}');
    await t.tap(find.text(advance.first).first, warnIfMissed: false);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }

    // THE SUCCESS STATE MUST NOT BE ON SCREEN.
    expect(find.text("That's everything we needed."), findsNothing,
        reason: 'the intake presented itself as COMPLETE over a failed save — EC-03');
    expect(find.text('Go to my home'), findsNothing);
    // And the failure is stated, with a way forward.
    expect(find.textContaining('could not save your answers'), findsWidgets,
        reason: 'the failure must be stated, not swallowed: ${allText(t)}');
    expect(find.text('Retry'), findsWidgets);

    // THE NEGATIVE, READ OFF THE WIRE — not off the widget tree.
    final writes = profileWrites();
    // Non-vacuity first: the tap must actually have tried to save, or the count assertion
    // below is satisfied by an empty log.
    expect(writes, isNotEmpty,
        reason: 'no user_profiles write was attempted, so nothing was under test');
    expect(writes.length, 1,
        reason: 'the failed save was followed by ANOTHER write — the original EC-03 defect '
            'was exactly that second "mark it complete anyway" update:\n'
            '${writes.join('\n\n')}');
  });

  testWidgets('EC-03 END-TO-END · a SESSION LOST MID-FLOW does not present the intake as '
      'complete either — the arm the original fix left open', (t) async {
    // REALISTIC, NOT CONTRIVED. The flow is 26 steps long, and `/intake` is listed in the
    // router's `isAuthRoute` set (app_router.dart:203) so it is reachable unauthenticated.
    // Losing the session between opening the flow and tapping Finish is exactly the state
    // `_finish()`'s `if (uid != null)` wrapper used to treat as success.
    await openAtFinalStep(t);
    expect(Supabase.instance.client.auth.currentUser?.id, _uid,
        reason: 'the flow must open WITH a session, or _loadProgress cannot restore step 26');

    // `SignOutScope.local`: it clears the session on this device WITHOUT a server
    // round-trip, which is both what the fake client can serve and the more accurate
    // simulation — the scenario is a session that stops being valid here, not a
    // deliberate server-side logout.
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(Supabase.instance.client.auth.currentUser, isNull,
        reason: 'the session must be gone before Finish is tapped');
    client.seen.clear();

    final advance = advanceLabels(t);
    expect(advance, isNotEmpty, reason: 'no advance affordance: ${allText(t)}');
    await t.tap(find.text(advance.first).first, warnIfMissed: false);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }

    expect(find.text("That's everything we needed."), findsNothing,
        reason: 'the intake presented itself as COMPLETE with no save ATTEMPTED — the arm '
            'EC-03 left open');
    expect(find.text('Go to my home'), findsNothing);
    expect(find.textContaining('not signed in'), findsWidgets,
        reason: 'the cause differs from a network failure and the copy says so: '
            '${allText(t)}');
    expect(find.text('Retry'), findsWidgets,
        reason: 'a token refresh between taps makes Retry work; withholding it would leave '
            'no way forward');
    // NOTHING WAS EVEN ATTEMPTED, and that is the whole point of this arm: `_finish()`
    // returns before touching the client, so there is no write to inspect — the evidence is
    // that the screen does not claim success.
    expect(profileWrites(), isEmpty,
        reason: 'a write was attempted with no session:\n${profileWrites().join('\n')}');
  });
}
