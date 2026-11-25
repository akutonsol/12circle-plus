import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/messaging/data/messaging_service.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/chat_screen.dart';
import 'package:circle_fitness/features/messaging/presentation/messaging_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_image_picker.dart';
import '../support/owned_writes_postgrest.dart';
import '../support/owner_harness.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59c round 2 · the edges of a conversation's owner: the inbox row, the
// unread count, the picker, the undo history, the notice, the subscription.
//
// HOW TO SEE IT FAIL: run against 6f8c693's messaging files (a82f993's where
// marked).

const _conv = 'conv-A';
const _busy =
    'A photo is already being chosen or sent — wait for it to finish.';
const _closed = 'Open a conversation from Messages.';

class _Service extends MessagingService {
  final stream = StreamController<List<Map<String, dynamic>>>.broadcast();
  @override
  Stream<List<Map<String, dynamic>>> messagesStream(String conversationId) =>
      stream.stream;
}

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

  final convOfA = {
    'id': _conv,
    'participant_1': memberA,
    'participant_2': 'coach-1',
    'last_message': 'private preview of A',
    'last_message_at': '2026-11-01T10:00:00Z',
  };

  setUp(() async {
    await signInAs(memberA);
    server.reset();
    picker.reset();
    server.rows['messages:$memberA'] = [
      {
        'id': 'm1',
        'conversation_id': _conv,
        'sender_id': 'coach-1',
        'content': 'Coach says hello A',
        'is_read': false,
        'sent_at': '2026-11-01T10:00:00Z',
      }
    ];
    server.rows['conversations:$memberA'] = [convOfA];
    server.rows['conversation_participant_profiles:$memberA'] = [
      {'id': 'coach-1', 'first_name': 'Nadia', 'last_name': 'Rahman', 'role': 'coach'}
    ];
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  ProviderContainer newContainer() {
    svc = _Service();
    addTearDown(() => unawaited(svc.stream.close()));
    container = ProviderContainer(overrides: [
      messagingServiceProvider.overrideWithValue(svc),
      tableTickerProvider.overrideWith((ref, table) => Stream.value(0)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> open(WidgetTester t) async {
    tallView(t);
    newContainer();
    container.read(selectedConversationProvider.notifier).state = {
      ...convOfA,
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
    await settleReal(t);
    expect(find.text('Coach says hello A'), findsOneWidget, reason: 'premise');
  }

  TextField field(WidgetTester t) => t.widget<TextField>(find.byType(TextField));
  VoidCallback? tapOf(WidgetTester t, IconData icon) => t
      .widget<GestureDetector>(find
          .ancestor(of: find.byIcon(icon), matching: find.byType(GestureDetector))
          .first)
      .onTap;
  Future<void> attach(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.image_outlined));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  Iterable<Asked> sentMessages() => server.sent('POST', 'messages');
  Iterable<Asked> uploads() => server.sent('POST', 'storage');

  group('opening', () {
    for (final frame in [true, false]) {
      // At a82f993 (and the mutant that removes the check after markAsRead).
      testWidgets(
          'A->B ${frame ? '' : 'with no frame '}while the thread is being marked '
          'read: it is not subscribed to', (t) async {
        final hold =
            server.holds['PATCH messages:$memberA'] = Completer<void>();
        await open(t);
        expect(server.sent('PATCH', 'messages'), hasLength(1), reason: 'premise');
        expect(svc.stream.hasListener, isFalse, reason: 'premise');
        await switchNoFrame(t, memberB);
        if (frame) await settleReal(t);
        hold.complete();
        // No frame: only the answer to the read-mark itself.
        for (var i = 0; i < 5; i++) {
          await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)));
          await t.idle();
        }
        expect(svc.stream.hasListener, isFalse);
        await settleReal(t);
        expect(svc.stream.hasListener, isFalse);
        expect(server.writesAs(memberB), isEmpty);
        await closeApp(t);
      });
    }

    Future<void> openInbox(WidgetTester t) async {
      tallView(t);
      newContainer();
      final router = GoRouter(initialLocation: '/messages', routes: [
        GoRoute(path: '/messages', builder: (_, __) => const MessagingScreen()),
        GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
      ]);
      addTearDown(router.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await settleReal(t);
      expect(find.text('Nadia Rahman'), findsOneWidget, reason: 'premise');
    }

    testWidgets("an inbox row of A tapped with no frame since A->B: the chat "
        "reads, names, opens and sends nothing of A's", (t) async {
      await openInbox(t);
      final tap = t
          .widget<GestureDetector>(find
              .ancestor(
                  of: find.text('Nadia Rahman'),
                  matching: find.byType(GestureDetector))
              .first)
          .onTap!;
      await switchNoFrame(t, memberB);
      server.log.clear();
      tap();
      await settleReal(t);
      expect(find.byType(ChatScreen), findsOneWidget, reason: 'premise');
      expect(find.textContaining('Nadia'), findsNothing);
      expect(server.sent('GET', 'messages'), isEmpty,
          reason: "THE defect: A's thread asked for as B");
      expect(server.writesAs(memberB), isEmpty,
          reason: "THE defect: marked read, and B's words sent into it");
      expect(find.text(_closed), findsOneWidget);
      expect(container.read(selectedConversationProvider), isNull);
      expect(origins(), contains('ChatScreen._init'));
      await closeApp(t);
    });

    testWidgets("Refresh on the inbox with no frame since A->B: B's read pending "
        "shows none of A's threads", (t) async {
      await openInbox(t);
      final hold =
          server.holds['GET conversations:$memberB'] = Completer<void>();
      await switchNoFrame(t, memberB);
      container.invalidate(conversationsProvider);
      container.read(conversationsProvider);
      await t.pump();
      await t.pump();
      expect(find.text('Nadia Rahman'), findsNothing);
      expect(find.text('private preview of A'), findsNothing);
      hold.complete();
      await settleReal(t);
      expect(find.text('No coach yet'), findsOneWidget,
          reason: "NEGATIVE CONTROL: B's empty inbox is empty");
      await closeApp(t);
    });

    testWidgets('CONTROL: the member opens their own row, and a token refresh or '
        'profile edit does not read the inbox again', (t) async {
      await openInbox(t);
      final reads = server.sent('GET', 'conversations').length;
      await refreshToken(t);
      await editUser(t);
      await settleReal(t);
      expect(server.sent('GET', 'conversations'), hasLength(reads),
          reason: 'THE defect: the whole User was watched');
      await t.tap(find.text('Nadia Rahman'));
      await settleReal(t);
      expect(find.text('Coach says hello A'), findsOneWidget);
      expect(reported, isEmpty);
      await closeApp(t);
    });
  });

  group('the unread count', () {
    setUp(() {
      server.rows['messages:$memberA'] = [
        {'id': '1'},
        {'id': '2'}
      ];
      server.rows['conversations:$memberB'] = [
        {'id': 'conv-B'}
      ];
      server.rows['messages:$memberB'] = [
        {'id': '3'}
      ];
    });

    Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));
    AsyncValue<int> count() => container.read(unreadCountProvider);

    Future<void> countOfA() async {
      newContainer().listen(unreadCountProvider, (_, __) {});
      await tick();
      expect(count().valueOrNull, 2, reason: 'premise');
    }

    test("B pending, then B's own: never A's number", () async {
      await countOfA();
      final hold =
          server.holds['GET conversations:$memberB'] = Completer<void>();
      await signInAs(memberB);
      await tick();
      expect(count().valueOrNull, isNull, reason: 'THE defect: 2');
      hold.complete();
      await tick();
      expect(count().valueOrNull, 1);
    });

    test("B failed: no number", () async {
      await countOfA();
      server.fails.add('GET conversations:$memberB');
      await signInAs(memberB);
      await tick();
      expect(count().hasError, isTrue);
      expect(count().valueOrNull, isNull, reason: 'THE defect: 2');
    });

    test('A back in reads their own again, not the count kept from before',
        () async {
      await countOfA();
      final reads = server.sent('GET', 'messages', memberA).length;
      server.rows['messages:$memberA'] = const [];
      await signInAs(memberB);
      await tick();
      await signInAs(memberA);
      await tick();
      expect(count().valueOrNull, 0);
      expect(server.sent('GET', 'messages', memberA).length, greaterThan(reads));
    });

    Future<void> watchIt(WidgetTester t) => t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(builder: (_, ref, __) {
            ref.watch(unreadCountProvider);
            return const SizedBox();
          }),
        ));

    testWidgets('A->B->A with no frame, between its two reads: the second is not '
        "asked as B, and B's number is not kept as A's", (t) async {
      newContainer();
      final hold =
          server.holds['GET conversations:$memberA'] = Completer<void>();
      await watchIt(t);
      await settleReal(t);
      await switchNoFrame(t, memberB);
      hold.complete();
      for (var i = 0; i < 5; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await t.idle();
      }
      expect(server.log.where((a) => a.who == memberB), isEmpty,
          reason: "THE defect: A's threads counted as B");
      await switchNoFrame(t, memberA);
      await settleReal(t);
      expect(count().valueOrNull, isNot(1), reason: "B's number");
      await closeApp(t);
    });

    testWidgets('a tick for A that lands after an unseen switch is not read as B '
        'under A', (t) async {
      final ticks = StreamController<int>.broadcast();
      addTearDown(() => unawaited(ticks.close()));
      svc = _Service();
      addTearDown(() => unawaited(svc.stream.close()));
      container = ProviderContainer(overrides: [
        messagingServiceProvider.overrideWithValue(svc),
        tableTickerProvider.overrideWith((ref, table) => ticks.stream),
      ]);
      addTearDown(container.dispose);
      await watchIt(t);
      ticks.add(0);
      await settleReal(t);
      expect(count().valueOrNull, 2, reason: 'premise');
      await switchNoFrame(t, memberB);
      ticks.add(1);
      await t.idle();
      await settleReal(t);
      expect(count().valueOrNull, 1);
      expect(server.sent('GET', 'conversations', memberB), hasLength(1),
          reason: "only B's own");
      await closeApp(t);
    });

    test('the inbox: A->B between its two reads, the names are not asked as B',
        () async {
      final hold =
          server.holds['GET conversations:$memberA'] = Completer<void>();
      final answer = MessagingService().getConversations();
      final refused = expectLater(answer, throwsA(isA<StateError>()));
      await tick();
      await signInAs(memberB);
      hold.complete();
      await refused;
      expect(server.log.where((a) => a.who == memberB), isEmpty);
      expect(origins(), ['MessagingService.getConversations']);
    });

    test('CONTROLS: a token refresh reads nothing again; a failed refresh keeps '
        'the number; signed out is none', () async {
      await countOfA();
      final reads = server.sent('GET', 'messages').length;
      await refreshSession();
      await tick();
      expect(server.sent('GET', 'messages'), hasLength(reads));
      expect(count().valueOrNull, 2);
      server.fails.add('GET conversations:$memberA');
      container.invalidate(tableTickerProvider('messages'));
      await tick();
      expect(count().hasError, isTrue);
      expect(count().valueOrNull, 2, reason: 'the same member, refresh failed');
      await signOut();
      await tick();
      expect(count().valueOrNull, 0);
    });
  });

  group('a conversation that was dropped', () {
    testWidgets('is announced, and the composer, Attach and Send are off',
        (t) async {
      final handle = t.ensureSemantics();
      await open(t);
      expect(field(t).enabled, isNot(false), reason: 'CONTROL: open');
      expect(tapOf(t, Icons.image_outlined), isNotNull);
      expect(tapOf(t, Icons.send_rounded), isNotNull);
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(liveRegionOver(_closed), findsOneWidget);
      expect(field(t).enabled, isFalse, reason: 'THE defect: a dead input');
      expect(tapOf(t, Icons.image_outlined), isNull);
      expect(tapOf(t, Icons.send_rounded), isNull);
      for (final name in ['Attach', 'Send']) {
        expect(
            t.getSemantics(find.bySemanticsLabel(name)),
            matchesSemantics(
                label: name, isButton: true, hasEnabledState: true,
                isEnabled: false),
            reason: name);
      }
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      handle.dispose();
      await closeApp(t);
    });

    testWidgets("undo does not bring A's draft back", (t) async {
      await open(t);
      await t.tap(find.byType(TextField));
      await t.enterText(find.byType(TextField), 'private to A');
      await t.pump(const Duration(seconds: 1));
      await switchNoFrame(t, memberB);
      await settleReal(t);
      await t.tap(find.byType(TextField), warnIfMissed: false);
      await t.pump();
      await undo(t);
      expect(field(t).controller!.text, isEmpty);
      expect(field(t).key, const ValueKey('composer-1'),
          reason: 'a new field, so its undo history is new');
      await closeApp(t);
    }, variant: const TargetPlatformVariant({TargetPlatform.linux}));

    testWidgets('a notice shown to A goes when A does', (t) async {
      await open(t);
      server.fails.add('POST messages:$memberA');
      await t.enterText(find.byType(TextField), 'hi');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      await settleReal(t);
      expect(find.byType(SnackBar), findsOneWidget, reason: 'premise');
      await switchNoFrame(t, memberB);
      await t.pump();
      await t.pump();
      expect(find.byType(SnackBar), findsNothing);
      await closeApp(t);
    });

    testWidgets('the spinner of a photo A was sending goes with it', (t) async {
      await open(t);
      final hold = server.holds['POST storage:$memberA'] = Completer<void>();
      await attach(t);
      await pumpUntil(t, () => uploads().isNotEmpty, what: 'the upload');
      expect(find.byIcon(Icons.send_rounded), findsNothing, reason: 'premise');
      await switchNoFrame(t, memberB);
      await settleReal(t);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      hold.complete();
      await pumpUntil(t, () => origins().contains('ChatScreen._sendPhoto'),
          what: 'the refusal');
      await settleReal(t);
      expect(sentMessages(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await closeApp(t);
    });
  });

  group('a photo', () {
    testWidgets('POSITIVE CONTROL: across a token refresh in the picker it is '
        'uploaded and sent once', (t) async {
      await open(t);
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await attach(t);
      await refreshToken(t);
      await settleReal(t);
      gate.complete(picker.photoPath);
      await pumpUntil(t, () => sentMessages().isNotEmpty, what: 'the row');
      await settleReal(t);
      expect(uploads().single.who, memberA);
      expect(sentMessages().single.who, memberA);
      expect(reported, isEmpty);
      await closeApp(t);
    });

    testWidgets('A->out->A with the picker open: the dropped conversation gets '
        'no photo', (t) async {
      await open(t);
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await attach(t);
      await signOutNoFrame(t);
      await settleReal(t);
      await switchNoFrame(t, memberA);
      await settleReal(t);
      gate.complete(picker.photoPath);
      await pumpUntil(
          t,
          () =>
              origins().contains('ChatScreen._sendPhoto') ||
              sentMessages().isNotEmpty,
          what: 'the outcome');
      await settleReal(t);
      expect(uploads(), isEmpty, reason: 'THE defect: sent to a closed chat');
      expect(sentMessages(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget,
          reason: 'not left spinning');
      await closeApp(t);
    });

    testWidgets('A->out->A during the upload: no row, said to nobody', (t) async {
      await open(t);
      final hold = server.holds['POST storage:$memberA'] = Completer<void>();
      await attach(t);
      await pumpUntil(t, () => uploads().isNotEmpty, what: 'the upload');
      await signOutNoFrame(t);
      await settleReal(t);
      await switchNoFrame(t, memberA);
      await settleReal(t);
      hold.complete();
      await pumpUntil(
          t,
          () =>
              origins().contains('ChatScreen._sendPhoto') ||
              sentMessages().isNotEmpty,
          what: 'the outcome');
      await settleReal(t);
      expect(sentMessages(), isEmpty, reason: 'THE defect');
      expect(server.sent('DELETE', 'storage').single.who, memberA,
          reason: 'the leftover is the member\'s own, and is removed');
      expect(find.byType(SnackBar), findsNothing);
      await closeApp(t);
    });

    Future<void> outAndBack(WidgetTester t) async {
      await signOutNoFrame(t);
      await settleReal(t);
      await switchNoFrame(t, memberA);
      await settleReal(t);
    }

    testWidgets('A->out->A during a refused row: cleaned up as A, said to nobody',
        (t) async {
      await open(t);
      server.fails.add('POST messages:$memberA');
      final hold = server.holds['POST messages:$memberA'] = Completer<void>();
      await attach(t);
      await pumpUntil(t, () => sentMessages().isNotEmpty, what: 'the row');
      await outAndBack(t);
      hold.complete();
      await pumpUntil(t, () => server.sent('DELETE', 'storage').isNotEmpty,
          what: 'the clean-up');
      await settleReal(t);
      expect(find.byType(SnackBar), findsNothing);
      await closeApp(t);
    });

    testWidgets('A->out->A while an unreadable photo is picked: recorded, said '
        'to nobody', (t) async {
      await open(t);
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await attach(t);
      await outAndBack(t);
      gate.complete(picker.vanishedPath);
      await pumpUntil(t, () => origins().contains('chat.photo.read'),
          what: 'the failed read');
      await settleReal(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(uploads(), isEmpty);
      await closeApp(t);
    });

    testWidgets('A->B with no frame during the upload: the refusal itself empties '
        'the composer', (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), 'private to A');
      await t.pump();
      final controller = field(t).controller!;
      final hold = server.holds['POST storage:$memberA'] = Completer<void>();
      await attach(t);
      await pumpUntil(t, () => uploads().isNotEmpty, what: 'the upload');
      await switchNoFrame(t, memberB);
      hold.complete();
      for (var i = 0; i < 20 && reported.length < 2; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await t.idle();
      }
      expect(origins(), ['ChatScreen._sendPhoto', 'ChatScreen._sendPhoto.cleanup'],
          reason: 'premise: refused, before any frame');
      await t.idle();
      expect(controller.text, isEmpty);
      await settleReal(t);
      expect(server.writesAs(memberB), isEmpty);
      await closeApp(t);
    });

    testWidgets("A's picker fails after A->B with no frame: recorded, B is told "
        'nothing', (t) async {
      await open(t);
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await attach(t);
      await switchNoFrame(t, memberB);
      gate.completeError(Exception('SECRET'));
      await settleReal(t);
      expect(origins(), contains('chat.photo.pick.gallery'));
      expect(find.byType(SnackBar), findsNothing,
          reason: 'THE defect: "Couldn\'t open your photos" about A\'s tap');
      await closeApp(t);
    });

    testWidgets('Attach while one is being chosen says so', (t) async {
      await open(t);
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await attach(t);
      expect(find.byType(SnackBar), findsNothing);
      await attach(t);
      expect(find.text(_busy), findsOneWidget,
          reason: 'THE defect: nothing, without a word');
      expect(picker.calls, hasLength(1));
      gate.complete(null);
      await settleReal(t);
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 1));
      picker.cancels();
      await attach(t);
      expect(picker.calls, hasLength(2), reason: 'CONTROL: free again');
      await closeApp(t);
    });

    testWidgets('Attach built for A, tapped after the drop: no picker',
        (t) async {
      await open(t);
      picker.cancels();
      final tap = tapOf(t, Icons.image_outlined)!;
      await switchNoFrame(t, memberB);
      await settleReal(t);
      await switchNoFrame(t, memberA);
      await settleReal(t);
      tap();
      await settleReal(t);
      expect(picker.calls, isEmpty);
      expect(find.byType(SnackBar), findsNothing,
          reason: 'not "not ready yet" either: it was dropped');
      expect(origins(), ['ChatScreen._sendPhoto']);
      await closeApp(t);
    });
  });

  testWidgets("Try again built for A's failed thread, tapped after the drop: no "
      'conversation is opened as B', (t) async {
    tallView(t);
    newContainer();
    server.fails.add('GET messages:$memberA');
    container.read(selectedConversationProvider.notifier).state = {...convOfA};
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChatScreen()),
    ));
    await settleReal(t);
    final again = t.widget<TextButton>(find.byType(TextButton)).onPressed!;
    await switchNoFrame(t, memberB);
    await settleReal(t);
    server.log.clear();
    again();
    await settleReal(t);
    expect(server.log, isEmpty,
        reason: "THE defect: B's own coach thread looked up, or created");
    expect(find.text(_closed), findsOneWidget);
    await closeApp(t);
  });

  group('sending', () {
    testWidgets('Send built for A, taken after the drop: nothing is sent',
        (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), 'draft');
      await t.pump();
      final controller = field(t).controller!;
      final submit = field(t).onSubmitted!;
      await switchNoFrame(t, memberB);
      await settleReal(t);
      controller.text = 'typed by B';
      submit('');
      await settleReal(t);
      expect(server.writesAs(memberB), isEmpty);
      expect(origins(), ['ChatScreen._send']);
      await closeApp(t);
    });

    testWidgets('sign-out during the insert: no preview, no points, nothing said',
        (t) async {
      await open(t);
      final hold = server.holds['POST messages:$memberA'] = Completer<void>();
      await t.enterText(find.byType(TextField), 'hi');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      await pumpUntil(t, () => sentMessages().isNotEmpty, what: 'the insert');
      await signOutNoFrame(t);
      hold.complete();
      await settleReal(t);
      expect(server.sent('PATCH', 'conversations'), isEmpty);
      expect(server.sent('POST', 'award_points'), isEmpty);
      expect(origins(), [
        'MessagingService.sendMessage.preview',
        'ChatScreen._send.award',
      ]);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('hi'), findsNothing);
      await closeApp(t);
    });

    testWidgets('CONTROL: a profile edit (userUpdated) keeps the thread, the '
        'draft and the subscription; it sends once', (t) async {
      await open(t);
      await t.enterText(find.byType(TextField), 'half');
      await t.pump();
      await editUser(t);
      await settleReal(t);
      expect(field(t).controller!.text, 'half');
      expect(svc.stream.hasListener, isTrue);
      await t.tap(find.byIcon(Icons.send_rounded));
      await settleReal(t);
      expect(sentMessages().single.json['content'], 'half');
      await closeApp(t);
    });

    testWidgets('a failing subscription is recorded, and the thread stays',
        (t) async {
      await open(t);
      svc.stream.addError(Exception('SECRET'));
      await settleReal(t);
      expect(t.takeException(), isNull, reason: 'THE defect: uncaught');
      expect(origins(), ['ChatScreen.messagesStream']);
      expect(find.text('Coach says hello A'), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      await closeApp(t);
    });
  });
}
