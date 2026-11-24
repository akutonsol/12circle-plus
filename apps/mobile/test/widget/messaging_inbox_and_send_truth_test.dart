import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/messaging/data/messaging_service.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/chat_screen.dart';
import 'package:circle_fitness/features/messaging/presentation/messaging_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/pump_until.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-13 · messaging inbox and send tell the truth.
//
// 1. `getConversations` answered ANY failure with `[]`, so an inbox that did
//    not load said "No conversations yet" — a member concluded their coach had
//    never written. It now records and rethrows; the inbox states the failure
//    with a busy-aware Try again. A real empty inbox keeps today's copy.
// 2. `sendMessage` wrapped the `messages` insert AND the `conversations`
//    preview update in one catch. When the insert landed and the preview
//    update failed it returned `false`: the chat said the message was not sent
//    although it WAS saved, gave the text back, and a resend stored it twice.
//    The catch also recorded nothing. Now the insert alone decides sent / not
//    sent; a preview failure (0-row included) is recorded and the send counts.
//
// HOW TO SEE IT FAIL: with 2ecd6e2's messaging_service.dart and
// messaging_screen.dart the inbox shows the empty copy for a failed read, a
// preview failure returns `false` (and the chat removes the bubble), and no
// failure is recorded for either send path.

const _uid = '00000000-0000-4000-8000-0000000f1013';
const _conv = 'conv-fl13';

const _emptyCopy = 'No conversations yet';
const _inboxOther = "Couldn't load your messages — try again in a moment. "
    'If it keeps happening, contact support.';
const _inboxNetwork =
    "Couldn't load your messages — check your connection and try again.";

/// What a failed read of `conversations` does, when set.
enum _ReadFailure { none, server, network }

/// The repo's write-faithful fake, plus a switchable failure for the
/// `conversations` READ (the shared fake only fails writes).
class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);

  _ReadFailure conversationsRead = _ReadFailure.none;
  int conversationReads = 0;

  /// When set, the next `conversations` read waits on this — a retry in flight.
  Completer<void>? readGate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/rest/v1/conversations')) {
      conversationReads++;
      if (readGate != null) await readGate!.future;
      switch (conversationsRead) {
        case _ReadFailure.network:
          throw http.ClientException('Connection refused', request.url);
        case _ReadFailure.server:
          return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(
                  {'message': 'refused', 'code': 'XX000'}))),
              500,
              request: request,
              headers: {'content-type': 'application/json'});
        case _ReadFailure.none:
          break;
      }
    }
    return super.send(request);
  }
}

/// The real `sendMessage` (the code under test); only the thread lookup and
/// the message reads are answered here so the chat opens on [_conv].
class _RealSendThread extends MessagingService {
  final _stream = StreamController<List<Map<String, dynamic>>>();

  @override
  Future<String?> getOrCreateClientCoachConversation() async => _conv;

  @override
  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async =>
      const [];

  @override
  Future<void> markAsRead(String conversationId) async {}

  @override
  Stream<List<Map<String, dynamic>>> messagesStream(String conversationId) =>
      _stream.stream;

  void dispose() => unawaited(_stream.close());
}

bool _isPreviewWrite(String line) =>
    line.startsWith('PATCH /rest/v1/conversations');
bool _isMessageInsert(String line) =>
    line.startsWith('POST /rest/v1/messages');

void main() {
  late _Server server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    server.conversationsRead = _ReadFailure.none;
    server.conversationReads = 0;
    server.readGate = null;
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  // ── 1 · the inbox read ────────────────────────────────────────────────────

  group('getConversations', () {
    test('a failed read is an error, recorded — not an empty inbox', () async {
      server.conversationsRead = _ReadFailure.server;

      await expectLater(MessagingService().getConversations(),
          throwsA(isA<PostgrestException>()),
          reason: 'returning [] is what made a failure read as "no conversations"');
      expect(origins(), contains('MessagingService.getConversations'));
    });

    test('a real empty inbox is still an empty list', () async {
      expect(await MessagingService().getConversations(), isEmpty);
      expect(reported, isEmpty);
    });
  });

  group('inbox screen', () {
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> openInbox(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ProviderScope(
        overrides: [
          tableTickerProvider.overrideWith((ref, table) => Stream.value(0)),
          // A coach: the empty inbox is the neutral sentence, not the
          // no-coach pitch, so "No conversations yet" is today's empty copy.
          currentUserProfileProvider
              .overrideWith((ref) async => {'id': _uid, 'role': 'coach'}),
        ],
        child: const MaterialApp(home: MessagingScreen()),
      ));
      await settle(t);
    }

    testWidgets('a failed load says so, never "No conversations yet"',
        (t) async {
      final semantics = t.ensureSemantics();
      server.conversationsRead = _ReadFailure.server;
      await openInbox(t);

      expect(find.text(_emptyCopy), findsNothing,
          reason: 'a failure shown as empty tells a member nobody wrote');
      expect(find.text(_inboxOther), findsOneWidget,
          reason: 'the server answered: try again later, not "check connection"');
      expect(find.text(_inboxNetwork), findsNothing);
      expect(find.textContaining('refused'), findsNothing,
          reason: 'exception text is never shown');
      expect(find.bySemanticsLabel('Try again'), findsOneWidget);
      expect(origins(), contains('MessagingService.getConversations'));

      final hit = find.ancestor(
          of: find.text('Try again'), matching: find.byType(Container)).first;
      expect(t.getSize(hit).height, greaterThanOrEqualTo(44));
      semantics.dispose();
    });

    testWidgets('a connection failure gets the connection hint', (t) async {
      server.conversationsRead = _ReadFailure.network;
      await openInbox(t);
      // postgrest-dart retries a GET that throws (1 s + 2 s + 4 s on the fake
      // clock); advance past it.
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(seconds: 1));
      }

      expect(find.text(_inboxNetwork), findsOneWidget);
      expect(find.text(_emptyCopy), findsNothing);
    });

    testWidgets('Try again re-reads once while busy, then shows the answer',
        (t) async {
      final semantics = t.ensureSemantics();
      server.conversationsRead = _ReadFailure.server;
      await openInbox(t);
      expect(find.text(_inboxOther), findsOneWidget);

      server.conversationsRead = _ReadFailure.none;
      server.readGate = Completer<void>();
      final before = server.conversationReads;
      await t.tap(find.text('Try again'));
      await t.pump(const Duration(milliseconds: 50));
      expect(server.conversationReads, before + 1);

      // In flight: the notice stays and the control cannot fire again.
      expect(find.text(_inboxOther), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      await t.tap(find.bySemanticsLabel('Retrying'), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 50));
      expect(server.conversationReads, before + 1, reason: 'no double fire');

      server.readGate!.complete();
      await settle(t);
      expect(find.text(_emptyCopy), findsOneWidget,
          reason: 'the re-read succeeded and the inbox really is empty');
      expect(find.text(_inboxOther), findsNothing);
      semantics.dispose();
    });

    // UX-1 · at 2x text on a small phone the fixed 320 px box clipped the
    // notice and pushed Try again outside its own bounds (overflow, untappable).
    testWidgets('2x text on a 320x568 phone: no overflow, Try again reachable',
        (t) async {
      server.conversationsRead = _ReadFailure.server;
      await t.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ProviderScope(
        overrides: [
          tableTickerProvider.overrideWith((ref, table) => Stream.value(0)),
          currentUserProfileProvider
              .overrideWith((ref) async => {'id': _uid, 'role': 'coach'}),
        ],
        child: MaterialApp(
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!),
          home: const MessagingScreen(),
        ),
      ));
      await settle(t);

      expect(t.takeException(), isNull,
          reason: 'the failure notice must grow with the text, not overflow');
      expect(find.text(_inboxOther), findsOneWidget);

      final retry = find.text('Try again');
      await t.scrollUntilVisible(retry, 100,
          scrollable: find.byType(Scrollable).first);
      await t.pump();
      final before = server.conversationReads;
      await t.tap(retry); // warns (and the count stays) if it is not hittable
      await t.pump(const Duration(milliseconds: 50));
      expect(server.conversationReads, before + 1,
          reason: 'Try again must be reachable and tappable at 2x text');
      await settle(t);
    });

    // UX-2 · the live region is the notice only; the button (whose label flips
    // Try again ↔ Retrying) keeps its own, non-live node.
    testWidgets('the live region holds the message, not the button', (t) async {
      final semantics = t.ensureSemantics();
      server.conversationsRead = _ReadFailure.server;
      await openInbox(t);

      bool inLiveRegion(Finder f) {
        SemanticsNode? n = t.getSemantics(f);
        while (n != null) {
          if (n.getSemanticsData().flagsCollection.isLiveRegion) return true;
          n = n.parent;
        }
        return false;
      }

      final message = t.getSemantics(find.text(_inboxOther));
      expect(message.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(message.label, contains("Couldn't load your messages"));
      expect(message.label, isNot(contains('Try again')));
      expect(inLiveRegion(find.bySemanticsLabel('Try again')), isFalse,
          reason: 'a live region around the button re-announces each '
              'Try again ↔ Retrying flip');
      final button = t.getSemantics(find.bySemanticsLabel('Try again'));
      expect(button.getSemanticsData().flagsCollection.isButton, isTrue);
      semantics.dispose();
    });

    testWidgets('an empty inbox keeps today\'s empty copy', (t) async {
      await openInbox(t);

      expect(find.text(_emptyCopy), findsOneWidget);
      expect(find.text(_inboxOther), findsNothing);
      expect(find.text(_inboxNetwork), findsNothing);
    });
  });

  // ── 2 · the send ──────────────────────────────────────────────────────────

  group('sendMessage', () {
    test('insert saved, preview update refused: SENT, the preview failure recorded',
        () async {
      server
        ..mode = WriteMode.serverError
        ..modeAppliesTo = _isPreviewWrite;

      final ok =
          await MessagingService().sendMessage(conversationId: _conv, content: 'hi');

      expect(ok, isTrue,
          reason: 'the message row is saved; "not sent" invites a duplicate');
      expect(server.writes.where(_isMessageInsert), hasLength(1));
      expect(origins(), contains('MessagingService.sendMessage.preview'));
      expect(origins(), isNot(contains('MessagingService.sendMessage')));
    });

    test('insert saved, preview update changed no row: SENT, recorded',
        () async {
      server
        ..mode = WriteMode.zeroRows
        ..modeAppliesTo = _isPreviewWrite;

      final ok =
          await MessagingService().sendMessage(conversationId: _conv, content: 'hi');

      expect(ok, isTrue);
      final patch = server.writes.singleWhere(_isPreviewWrite);
      expect(patch, contains('select=id'),
          reason: 'without asking for the row a 0-row update looks like success');
      expect(origins(), contains('MessagingService.sendMessage.preview'));
    });

    test('preview keys and values are unchanged', () async {
      await MessagingService().sendMessage(conversationId: _conv, content: 'hi');

      final patch = server.writes.singleWhere(_isPreviewWrite);
      final body =
          jsonDecode(patch.substring(patch.indexOf(' {') + 1)) as Map;
      expect(body.keys.toSet(), {'last_message', 'last_message_at'});
      expect(body['last_message'], 'hi');
      expect(reported, isEmpty, reason: 'a clean send records nothing');
    });

    test('insert refused: NOT sent, recorded, no preview write', () async {
      server
        ..mode = WriteMode.serverError
        ..modeAppliesTo = _isMessageInsert;

      final ok =
          await MessagingService().sendMessage(conversationId: _conv, content: 'hi');

      expect(ok, isFalse);
      expect(server.writes.where(_isPreviewWrite), isEmpty);
      expect(origins(), contains('MessagingService.sendMessage'),
          reason: 'this catch used to record nothing');
    });

    test('insert never reached the server: NOT sent, recorded', () async {
      server
        ..mode = WriteMode.network
        ..modeAppliesTo = _isMessageInsert;

      final ok =
          await MessagingService().sendMessage(conversationId: _conv, content: 'hi');

      expect(ok, isFalse);
      final f = reported.singleWhere((f) => f.origin == 'MessagingService.sendMessage');
      expect(f.error, isA<http.ClientException>());
    });
  });

  group('chat screen', () {
    testWidgets(
        'insert saved, preview failed: shown as sent — no failure, no text handed back',
        (t) async {
      server
        ..mode = WriteMode.serverError
        ..modeAppliesTo = _isPreviewWrite;
      final svc = _RealSendThread();
      addTearDown(svc.dispose);

      t.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1200, 2400);
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [messagingServiceProvider.overrideWithValue(svc)],
        child: const MaterialApp(home: ChatScreen()),
      ));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }

      await t.enterText(find.byType(TextField), 'Saved already');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }

      expect(server.writes.where(_isMessageInsert), hasLength(1));
      expect(
          find.descendant(
              of: find.byType(ListView), matching: find.text('Saved already')),
          findsOneWidget,
          reason: 'the message is saved; it stays in the thread as sent');
      expect(find.textContaining("Couldn't send"), findsNothing,
          reason: 'saying "not sent" for a saved message invites a duplicate');
      expect(find.byType(SnackBar), findsNothing);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
          reason: 'the text is not handed back for a resend');

      // Let any SnackBar / scroll timers run out before teardown.
      await t.pump(const Duration(seconds: 5));
    });

    // QA minor · the photo upload's catch used to record nothing.
    testWidgets('a refused photo upload is recorded and reported, not hidden',
        (t) async {
      final dir = await t.runAsync(
          () => Directory.systemTemp.createTemp('fl13_photo'));
      final photo = File('${dir!.path}/p.jpg');
      await t.runAsync(() => photo.writeAsBytes(const [0xFF, 0xD8, 0xFF]));
      addTearDown(() => dir.deleteSync(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/image_picker');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async => call.method == 'pickImage' ? photo.path : null);
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      server
        ..mode = WriteMode.serverError
        ..modeAppliesTo = (line) => line.contains('/storage/v1/object');
      final svc = _RealSendThread();
      addTearDown(svc.dispose);
      t.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1200, 2400);
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [messagingServiceProvider.overrideWithValue(svc)],
        child: const MaterialApp(home: ChatScreen()),
      ));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }

      await t.tap(find.byIcon(Icons.image_outlined));
      // The picked photo is read from disk (real I/O) before the upload; a
      // fixed budget of pumps raced it under load (P0-FL-51). Wait for the
      // outcome — the send settles with a SnackBar either way.
      await pumpUntil(t, () => find.byType(SnackBar).evaluate().isNotEmpty,
          what: 'the photo send outcome (a SnackBar)');
      await t.pump(const Duration(milliseconds: 100));

      expect(server.writes.where((w) => w.contains('/storage/v1/object')),
          isNotEmpty, reason: 'the upload was attempted');
      expect(server.writes.where(_isMessageInsert), isEmpty);
      expect(origins(), contains('ChatScreen._sendPhoto'),
          reason: 'this catch used to swallow the failure unrecorded');
      expect(
          find.text("Couldn't send your photo — try again in a moment. "
              'If it keeps happening, contact support.'),
          findsOneWidget);
      await t.pump(const Duration(seconds: 5));
    });
  });
}
