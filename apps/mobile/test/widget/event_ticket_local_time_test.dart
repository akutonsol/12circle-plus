import 'dart:convert';

import 'package:circle_fitness/features/classes/presentation/event_ticket_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Events › an event › its ticket. `event_date` is a timestamptz and comes back
// in UTC. The events list shows it with `.toLocal()`; the ticket printed the
// UTC weekday, day and hour, so an 18:00 event in New York (23:00 UTC) read
// 23:00 on the ticket, and an event early in the morning in Tokyo was on the
// ticket the day before.
//
// ── RUN IT WEST AND EAST OF UTC ─────────────────────────────────────────────
// Dart has no injectable local zone, so this reads the process's. Under UTC
// (CI) the two agree and the cases pass either way; the defect shows under
//   TZ=America/New_York flutter test test/widget/event_ticket_local_time_test.dart
//   TZ=Asia/Tokyo       flutter test test/widget/event_ticket_local_time_test.dart

class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
          request: request, headers: {'content-type': 'application/json'});
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

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
               'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// What the person going lives: the local day and time of [utc].
(String, String) _local(String utc) {
  final d = DateTime.parse(utc).toLocal();
  return (
    '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}',
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  Future<void> showTicket(WidgetTester tester, String eventDate) async {
    await tester.pumpWidget(MaterialApp(
      home: EventTicketScreen(event: {
        'id': 'e1',
        'title': 'Sunset Run Club',
        'event_date': eventDate,
        'is_free': true,
      }),
    ));
    await tester.pump();
  }

  testWidgets('an evening event west of UTC shows its local day and time',
      (tester) async {
    // 18:00 in New York on Thursday Nov 12.
    const at = '2026-11-12T23:00:00+00:00';
    await showTicket(tester, at);
    final (day, time) = _local(at);
    expect(find.text(day), findsOneWidget);
    expect(find.text(time), findsOneWidget);
  });

  testWidgets('an early event east of UTC shows its local day and time',
      (tester) async {
    // 07:00 in Tokyo on Friday Nov 13.
    const at = '2026-11-12T22:00:00+00:00';
    await showTicket(tester, at);
    final (day, time) = _local(at);
    expect(find.text(day), findsOneWidget);
    expect(find.text(time), findsOneWidget);
  });
}
