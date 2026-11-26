import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/messaging/data/messaging_service.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_image_picker.dart';
import '../support/owned_writes_postgrest.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59c · a conversation belongs to the account it was opened as.
//
// At a82f993 the selected conversation outlived a switch, ChatScreen held no
// owner, and `messages` INSERT (migration 003) accepts any `sender_id =
// auth.uid()` into any conversation: B's words (or A's unsent draft) went into
// A's thread, read by A and A's coach. The preview, the read-mark, the award
// and the conversation RPC each ran as whoever was signed in after an await.
//
// The REAL service and the REAL auth client: every test asserts what was asked
// of the server and by whom. Only the realtime stream is a fake. AccountScope
// is deliberately absent: the screen stays mounted across the switch.
//
// HOW TO SEE IT FAIL: run against a82f993's messaging files.

const _conv = 'conv-A';
const _draft = 'A: my knee is worse, do not tell anyone';

class _Service extends MessagingService {
  final stream = StreamController<List<Map<String, dynamic>>>.broadcast();
  @override
  Stream<List<Map<String, dynamic>>> messagesStream(String conversationId) =>
      stream.stream;
}

Map<String, Object?> _msg(String id, String text) => {
      'id': id,
      'conversation_id': _conv,
      'sender_id': 'coach-1',
      'content': text,
      'is_read': false,
      'sent_at': '2026-11-01T10:00:00Z',
    };

void main() {
  late OwnedWritesPostgrest server;
  late _Service svc;
  late ProviderContainer container;
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = OwnedWritesPostgrest();
    await initTwoMemberSupabase(server);
    picker.install();
  });
  tearDownAll(picker.dispose);

  setUp(() async {
    await signInAs(memberA);
    server.reset();
    picker.reset();
    server.rows['messages:$memberA'] = [_msg('m1', 'Coach says hello A')];
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

  /// The real auth transition, WITHOUT a frame: what a hidden tab does.
  Future<void> switchTo(WidgetTester t, String uid) async {
    await t.runAsync(() => signInAs(uid));
    expect(Supabase.instance.client.auth.currentUser?.id, uid, reason: 'premise');
  }

  Future<void> open(WidgetTester t, {Map<String, dynamic>? selected}) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 2400);
    addTearDown(t.view.reset);
    svc = _Service();
    addTearDown(() => unawaited(svc.stream.close()));
    container = ProviderContainer(
        overrides: [messagingServiceProvider.overrideWithValue(svc)]);
    addTearDown(container.dispose);
    container.read(selectedConversationProvider.notifier).state = selected ??
        {
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

  TextField field(WidgetTester t) => t.widget<TextField>(find.byType(TextField));

  Future<void> type(WidgetTester t, String text) async {
    await t.enterText(find.byType(TextField), text);
    await t.pump();
  }

  Future<void> tapSend(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.send_rounded));
    await settle(t);
  }

  void nothingOfAs(WidgetTester t) {
    expect(find.textContaining('Nadia'), findsNothing);
    expect(find.text('Your coach'), findsNothing);
    expect(find.text('Coach says hello A'), findsNothing);
    expect(field(t).controller!.text, isEmpty);
    expect(field(t).decoration!.hintText, isNot(contains('Nadia')));
  }

  group('the same member (positive controls)', () {
    testWidgets('a message goes once: one row as A, its preview, its award, and '
        'the thread marked read', (t) async {
      await open(t);
      expect(find.text('Nadia Rahman'), findsOneWidget);
      expect(find.text('Coach says hello A'), findsOneWidget);
      final read = server.sent('PATCH', 'messages').single;
      expect(read.who, memberA);
      expect(read.query['conversation_id'], 'eq.$_conv');

      await type(t, 'hi');
      await tapSend(t);
      final row = server.sent('POST', 'messages').single;
      expect(row.who, memberA);
      expect(row.json['sender_id'], memberA);
      expect(row.json['conversation_id'], _conv);
      expect(server.sent('PATCH', 'conversations').single.who, memberA);
      expect(server.sent('POST', 'award_points').single.who, memberA);
      expect(field(t).controller!.text, isEmpty);
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('a token refresh keeps the thread, the draft and the '
        'subscription; the draft then sends once', (t) async {
      await open(t);
      await type(t, 'half a sentence');
      await t.runAsync(refreshSession);
      await settle(t);
      expect(Supabase.instance.client.auth.currentUser?.id, memberA);
      expect(field(t).controller!.text, 'half a sentence');
      expect(find.text('Nadia Rahman'), findsOneWidget);
      expect(find.text('Coach says hello A'), findsOneWidget);
      expect(container.read(selectedConversationProvider)?['id'], _conv);
      svc.stream.add([_msg('m2', 'live after refresh')]);
      await settle(t);
      expect(find.text('live after refresh'), findsOneWidget);
      await tapSend(t);
      expect(server.sent('POST', 'messages').single.json['content'],
          'half a sentence');
      await close(t);
    });

    testWidgets('NEGATIVE CONTROL: an empty thread is still an empty thread',
        (t) async {
      server.rows.clear();
      await open(t);
      expect(find.text('Start the conversation!'), findsOneWidget);
      expect(find.text('Open a conversation from Messages.'), findsNothing);
      await close(t);
    });

    testWidgets('a failed thread is still a failure, and Try again loads it',
        (t) async {
      server.fails.add('GET messages:$memberA');
      await open(t);
      expect(find.text("Couldn't open this conversation"), findsOneWidget);
      server.fails.clear();
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text('Coach says hello A'), findsOneWidget);
      await close(t);
    });

    testWidgets('a refused send gives the text back to the same member',
        (t) async {
      await open(t);
      server.fails.add('POST messages:$memberA');
      await type(t, 'hi');
      await tapSend(t);
      expect(field(t).controller!.text, 'hi');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(server.sent('POST', 'award_points'), isEmpty);
      await close(t);
    });
  });

  group('A leaves, the screen stays mounted', () {
    testWidgets("A->B: the name, thread, draft and subscription are gone, and "
        "nothing B does reaches A's conversation", (t) async {
      await open(t);
      await type(t, _draft);
      await switchTo(t, memberB);
      await settle(t);
      nothingOfAs(t);
      expect(svc.stream.hasListener, isFalse);
      expect(container.read(selectedConversationProvider), isNull);
      expect(find.text('Start the conversation!'), findsNothing,
          reason: 'no thread is open; that is not an empty thread');
      expect(find.text("Couldn't open this conversation"), findsNothing);

      await type(t, 'B writes');
      await tapSend(t);
      expect(server.writesAs(memberB), isEmpty,
          reason: "THE defect: {conversation_id: A's, sender_id: B} was sent "
              'and accepted');
      expect(find.text('Open a conversation from Messages.'), findsWidgets);
      await close(t);
    });

    testWidgets('A->B with no frame in between (a hidden tab): the send is '
        'refused and recorded, and nothing is said', (t) async {
      await open(t);
      await type(t, _draft);
      final submit = field(t).onSubmitted!;
      await switchTo(t, memberB);
      submit('');
      await settle(t);
      expect(server.writesAs(memberB), isEmpty,
          reason: "THE defect: A's draft was inserted into A's thread as B");
      expect(reported.single.origin, 'ChatScreen._send');
      expect('${reported.single.error}', contains('the signed-in account changed'));
      expect(find.byType(SnackBar), findsNothing);
      nothingOfAs(t);
      await close(t);
    });

    testWidgets('Attach after an unseen switch opens no picker as B', (t) async {
      await open(t);
      picker.cancels();
      final attach = t
          .widget<GestureDetector>(find
              .ancestor(
                  of: find.byIcon(Icons.image_outlined),
                  matching: find.byType(GestureDetector))
              .first)
          .onTap!;
      await switchTo(t, memberB);
      attach();
      await settle(t);
      expect(picker.calls, isEmpty);
      expect(origins(), ['ChatScreen._sendPhoto']);
      expect(find.byType(SnackBar), findsNothing);
      await close(t);
    });

    testWidgets('sign-out -> the same member back in: the private content went, '
        'and nothing is sent as a leftover', (t) async {
      await open(t);
      await type(t, _draft);
      await t.runAsync(signOut);
      await settle(t);
      nothingOfAs(t);
      await switchTo(t, memberA);
      await settle(t);
      nothingOfAs(t);
      await type(t, 'again');
      await tapSend(t);
      expect(server.sent('POST', 'messages'), isEmpty);
      await close(t);
    });

    testWidgets('a realtime row that arrives after an unseen switch is not '
        'shown', (t) async {
      await open(t);
      await switchTo(t, memberB);
      svc.stream.add([_msg('m9', 'A private row')]);
      await t.idle();
      expect(svc.stream.hasListener, isFalse,
          reason: 'dropped by the row itself, before any frame');
      await settle(t);
      expect(find.text('A private row'), findsNothing);
      expect(svc.stream.hasListener, isFalse);
      await close(t);
    });
  });

  group('an answer of A that lands after B', () {
    testWidgets("A's thread: not shown, and not marked read as B", (t) async {
      final hold = server.holds['GET messages:$memberA'] = Completer<void>();
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      server.holds.clear();
      hold.complete();
      await settle(t);
      nothingOfAs(t);
      expect(server.writesAs(memberB), isEmpty,
          reason: 'THE defect: PATCH messages (read) as B');
      expect(svc.stream.hasListener, isFalse);
      await close(t);
    });

    testWidgets('the same with no frame in between: refused and recorded',
        (t) async {
      final hold = server.holds['GET messages:$memberA'] = Completer<void>();
      await open(t);
      await switchTo(t, memberB);
      server.holds.clear();
      hold.complete();
      await settle(t);
      expect(server.writesAs(memberB), isEmpty);
      expect(origins(), ['ChatScreen._init.markAsRead']);
      expect(find.text('Coach says hello A'), findsNothing);
      await close(t);
    });

    testWidgets("A's failed thread is not B's failure", (t) async {
      final hold = server.holds['GET messages:$memberA'] = Completer<void>();
      server.fails.add('GET messages:$memberA');
      await open(t);
      await switchTo(t, memberB);
      server.holds.clear();
      hold.complete();
      await settle(t);
      expect(find.text("Couldn't open this conversation"), findsNothing);
      nothingOfAs(t);
      await close(t);
    });

    testWidgets('A->B->A while the thread is in flight: the old open does not '
        'come back to life', (t) async {
      final hold = server.holds['GET messages:$memberA'] = Completer<void>();
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      await switchTo(t, memberA);
      await settle(t);
      server.holds.clear();
      hold.complete();
      await settle(t);
      expect(find.text('Coach says hello A'), findsNothing);
      expect(svc.stream.hasListener, isFalse);
      await close(t);
    });

    testWidgets("A's conversation id: B reads no thread with it", (t) async {
      server.rpcs['get_or_create_conversation'] = _conv;
      final hold = server.holds['POST get_or_create_conversation:$memberA'] =
          Completer<void>();
      await open(t, selected: {
        'id': null,
        'participant': {'id': 'coach-1', 'first_name': 'Nadia'},
      });
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.log.where((a) => a.who == memberB), isEmpty,
          reason: "THE defect: B asked for A's thread and marked it read");
      expect(origins(), ['MessagingService.getOrCreateConversationWith'],
          reason: 'a switch is not "no conversation for participant"');
      expect(find.textContaining('Nadia'), findsNothing);
      await close(t);
    });
  });

  group('a switch while a message is in flight', () {
    testWidgets("saved: no preview as B, no points for B, recorded", (t) async {
      final hold =
          server.holds['POST messages:$memberA'] = Completer<void>();
      await open(t);
      await type(t, 'hi from A');
      await t.tap(find.byIcon(Icons.send_rounded));
      await pumpUntil(t, () => server.sent('POST', 'messages').isNotEmpty,
          what: 'the insert');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.sent('POST', 'messages').single.json['sender_id'], memberA);
      expect(server.writesAs(memberB), isEmpty,
          reason: 'THE defect: the preview PATCH and award_points ran as B');
      expect(origins(), [
        'MessagingService.sendMessage.preview',
        'ChatScreen._send.award',
      ]);
      expect(find.text('hi from A'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await close(t);
    });

    testWidgets("refused: A's words are not handed to B, and B is told nothing",
        (t) async {
      final hold =
          server.holds['POST messages:$memberA'] = Completer<void>();
      server.fails.add('POST messages:$memberA');
      await open(t);
      await type(t, _draft);
      await t.tap(find.byIcon(Icons.send_rounded));
      await pumpUntil(t, () => server.sent('POST', 'messages').isNotEmpty,
          what: 'the insert');
      await switchTo(t, memberB);
      await settle(t);
      hold.complete();
      await settle(t);
      nothingOfAs(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(server.writesAs(memberB), isEmpty);
      await close(t);
    });

    testWidgets('during the preview: no points for B', (t) async {
      final hold =
          server.holds['PATCH conversations:$memberA'] = Completer<void>();
      await open(t);
      await type(t, 'hi');
      await t.tap(find.byIcon(Icons.send_rounded));
      await pumpUntil(t, () => server.sent('PATCH', 'conversations').isNotEmpty,
          what: 'the preview');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writesAs(memberB), isEmpty);
      expect(origins(), ['ChatScreen._send.award']);
      await close(t);
    });
  });

  group('the service', () {
    test("A's coach is read, then B signs in: no conversation is opened between "
        "B and A's coach (W27)", () async {
      server.rows['coach_client_relationships:$memberA'] = [
        {'coach_id': 'coach-of-A'}
      ];
      server.rpcs['get_or_create_conversation'] = 'conv-new';
      final hold =
          server.holds['GET coach_client_relationships:$memberA'] =
              Completer<void>();
      final answer = MessagingService().getOrCreateClientCoachConversation();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await signInAs(memberB);
      hold.complete();
      expect(await answer, isNull);
      expect(server.sent('POST', 'get_or_create_conversation'), isEmpty);
      expect(origins(),
          ['MessagingService.getOrCreateClientCoachConversation']);
    });

    for (final coach in [false, true]) {
      test("an id opened by A is not handed to B (${coach ? 'coach' : 'client'} "
          'side)', () async {
        server.rpcs['get_or_create_conversation'] = _conv;
        final hold = server.holds['POST get_or_create_conversation:$memberA'] =
            Completer<void>();
        final svc = MessagingService();
        final answer = coach
            ? svc.getOrCreateCoachClientConversation('x')
            : svc.getOrCreateConversationWith('x');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await signInAs(memberB);
        hold.complete();
        expect(await answer, isNull);
        expect(origins(), hasLength(1));
      });
    }

    test('POSITIVE CONTROL: the same member, across a token refresh, is given '
        'their conversation', () async {
      server.rows['coach_client_relationships:$memberA'] = [
        {'coach_id': 'coach-of-A'}
      ];
      server.rpcs['get_or_create_conversation'] = 'conv-new';
      final hold =
          server.holds['GET coach_client_relationships:$memberA'] =
              Completer<void>();
      final answer = MessagingService().getOrCreateClientCoachConversation();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await refreshSession();
      hold.complete();
      expect(await answer, 'conv-new');
      expect(reported, isEmpty);
    });

    test('NEGATIVE CONTROL: no coach is still no conversation, not a failure',
        () async {
      expect(await MessagingService().getOrCreateClientCoachConversation(),
          isNull);
      expect(reported, isEmpty);
    });
  });

  group('the selected conversation is keyed by the uid', () {
    Future<ProviderContainer> picked() async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(selectedConversationProvider, (_, __) {});
      c.read(selectedConversationProvider.notifier).state = {'id': _conv};
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return c;
    }

    test('dropped for B', () async {
      final c = await picked();
      await signInAs(memberB);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.read(selectedConversationProvider), isNull);
    });

    test('dropped on sign-out', () async {
      final c = await picked();
      await signOut();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.read(selectedConversationProvider), isNull);
    });

    test('POSITIVE CONTROL: kept through a token refresh', () async {
      final c = await picked();
      await refreshSession();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.read(selectedConversationProvider)?['id'], _conv);
    });
  });
}
