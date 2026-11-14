import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/coach/presentation/weekly_review_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Weekly Review sent the unedited draft and said "Sent to client ✓".
//
// `_send` awaited `updateCommunication` and ignored its result. When saving the
// coach's edits failed, `sendCommunication` still went out — with the draft the
// coach had just rewritten — and the coach was told it was sent.

class _Svc extends CoachProgramService {
  _Svc({required this.saves});
  final bool saves;
  int sends = 0;
  @override
  Future<bool> updateCommunication(String id, String clientText, String coachText) async => saves;
  @override
  Future<bool> sendCommunication(String id) async {
    sends++;
    return true;
  }
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

class _Offline extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
          request: request, headers: {'content-type': 'application/json'});
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Offline(),
      authOptions: FlutterAuthClientOptions(
          localStorage: const EmptyLocalStorage(),
          pkceAsyncStorage: _MemoryStore(),
          detectSessionInUri: false),
      debug: false,
    );
  });

  test("edits that were not saved are not sent, and the coach is told", () async {
    final svc = _Svc(saves: false);
    final r = await sendReviewedCommunication(svc, 'c1', 'edited', 'note');
    expect(svc.sends, 0, reason: 'THE defect: the unedited draft went to the client');
    expect(r.sent, isFalse);
    expect(r.status, isNot(contains('Sent to client')));
  });

  test('control: saved edits are sent', () async {
    final svc = _Svc(saves: true);
    final r = await sendReviewedCommunication(svc, 'c1', 'edited', 'note');
    expect(svc.sends, 1);
    expect(r.status, 'Sent to client ✓');
  });
}
