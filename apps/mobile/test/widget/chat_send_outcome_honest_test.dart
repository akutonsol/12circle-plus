import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/messaging/data/messaging_service.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/owned_writes_postgrest.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-63b item 2 · a chat message is shown as SENT only once the server took
// its row.
//
// At 7b9ce5c the message was put in the thread the moment Send was tapped,
// drawn exactly as a sent one — with a sent time — while the insert had not
// answered. There is no client timeout, so on a stalled connection it sat
// there as "sent" for as long as the request hung, whatever became of it. Now
// it reads "Sending…" until the insert answers; then its time.
//
// The REAL service and the REAL auth client; only the realtime stream is a
// fake. AccountScope is absent: the screen stays mounted across a switch.
//
// HOW TO SEE IT FAIL: `git checkout 7b9ce5c --
// lib/features/messaging/presentation/chat_screen.dart` — the in-flight test
// finds no "Sending…". The others pin cases FL-13/FL-59c already got right
// (they pass there too) that no test asserted end to end.

const _conv = 'conv-A';
const _sending = 'Sending…';

class _Server extends OwnedWritesPostgrest {
  /// `METHOD table:<who>` whose connection drops: no answer ever arrives.
  final lost = <String>{};

  @override
  void reset() {
    super.reset();
    lost.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    final key = '${request.method} ${u.path.split('/').last}:'
        '${TwoMemberPostgrest.who(request)}';
    if (u.path.startsWith('/rest/v1/') && lost.contains(key)) {
      log.add(Asked(request.method, u.path.split('/').last,
          TwoMemberPostgrest.who(request), u.queryParameters, ''));
      await holds[key]?.future;
      throw http.ClientException('Connection closed while receiving data', u);
    }
    return super.send(request);
  }
}

class _Service extends MessagingService {
  final stream = StreamController<List<Map<String, dynamic>>>.broadcast();
  @override
  Stream<List<Map<String, dynamic>>> messagesStream(String conversationId) =>
      stream.stream;
}

void main() {
  late _Server server;
  late _Service svc;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    await signInAs(memberA);
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 2400);
    addTearDown(t.view.reset);
    svc = _Service();
    addTearDown(() => unawaited(svc.stream.close()));
    final container = ProviderContainer(
        overrides: [messagingServiceProvider.overrideWithValue(svc)]);
    addTearDown(container.dispose);
    container.read(selectedConversationProvider.notifier).state = {
      'id': _conv,
      'participant': {
        'id': 'coach-1',
        'first_name': 'Nadia',
        'last_name': 'Rahman',
        'role': 'coach',
      },
    };
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChatScreen()),
    ));
    await settle(t);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 7));
  }

  String composer(WidgetTester t) =>
      t.widget<TextField>(find.byType(TextField)).controller!.text;

  Finder inThread(String text) =>
      find.descendant(of: find.byType(ListView), matching: find.text(text));

  Future<void> sendFromComposer(WidgetTester t, String text) async {
    await t.enterText(find.byType(TextField), text);
    await t.pump();
    await t.tap(find.byIcon(Icons.send_rounded));
    await pumpUntil(t, () => server.sent('POST', 'messages').isNotEmpty,
        what: 'the insert');
    await t.pump();
  }

  testWidgets('in flight: the message reads "Sending…", not a sent time, until '
      'the server took the row; then it is sent (POSITIVE CONTROL)', (t) async {
    final semantics = t.ensureSemantics();
    final hold = server.holds['POST messages:$memberA'] = Completer<void>();
    await open(t);
    await sendFromComposer(t, 'hi coach');
    await settle(t);
    expect(inThread('hi coach'), findsOneWidget);
    expect(find.text(_sending), findsOneWidget,
        reason: 'THE defect: an unanswered insert was drawn as a sent message');
    expect(find.bySemanticsLabel(RegExp(_sending)), findsOneWidget,
        reason: 'a screen reader hears it too');

    hold.complete();
    await settle(t);
    expect(server.sent('POST', 'messages', memberA), hasLength(1));
    expect(inThread('hi coach'), findsOneWidget);
    expect(find.text(_sending), findsNothing, reason: 'saved: now it is sent');
    expect(server.sent('POST', 'award_points', memberA), hasLength(1));
    expect(reported, isEmpty);
    await close(t);
    semantics.dispose();
  });

  testWidgets('connection dropped mid-insert (outcome unknown): never shown as '
      'sent; recorded; the text is given back', (t) async {
    server.lost.add('POST messages:$memberA');
    await open(t);
    await sendFromComposer(t, 'did it go?');
    await settle(t);
    expect(inThread('did it go?'), findsNothing);
    expect(find.text(_sending), findsNothing);
    expect(composer(t), 'did it go?');
    expect(
        find.text("Couldn't send your message — check your connection and try "
            'again.'),
        findsOneWidget);
    expect(server.sent('POST', 'award_points'), isEmpty);
    expect(server.sent('PATCH', 'conversations'), isEmpty);
    expect(origins(), ['MessagingService.sendMessage', 'ChatScreen._send']);
    await close(t);
  });

  testWidgets('refused while B signs in: A\'s unsent message is recorded, B is '
      'told nothing and gets none of it', (t) async {
    final hold = server.holds['POST messages:$memberA'] = Completer<void>();
    server.fails.add('POST messages:$memberA');
    await open(t);
    await sendFromComposer(t, 'A: private words');
    await t.runAsync(() => signInAs(memberB));
    hold.complete();
    await settle(t);
    expect(find.text('A: private words'), findsNothing);
    expect(find.text(_sending), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(server.writesAs(memberB), isEmpty);
    expect(origins(), ['MessagingService.sendMessage', 'ChatScreen._send']);
    expect('${reported.last.error}', contains('message was not sent'));
    await close(t);
  });

  testWidgets('in flight while B signs in: the "Sending…" bubble goes with A',
      (t) async {
    final hold = server.holds['POST messages:$memberA'] = Completer<void>();
    await open(t);
    await sendFromComposer(t, 'A: on its way');
    await t.runAsync(() => signInAs(memberB));
    await settle(t);
    expect(find.text('A: on its way'), findsNothing);
    expect(find.text(_sending), findsNothing);
    hold.complete();
    await settle(t);
    expect(find.text('A: on its way'), findsNothing);
    expect(server.writesAs(memberB), isEmpty);
    await close(t);
  });
}
