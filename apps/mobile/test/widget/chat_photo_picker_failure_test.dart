import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/messaging/data/messaging_service.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_image_picker.dart';
import '../support/pump_until.dart';
import '../support/row_checking_postgrest.dart';
import '../support/session_switch.dart';

// P0-FL-56a · Attach (chat photo): the pick, the read, the upload, the message
// row, and the cleanup of a photo whose row never landed.
//
// At f191d48 the picker was unguarded (uncaught error, Attach did nothing, two
// taps opened two); Attach before the conversation resolved returned without a
// word; every later failure said "Failed to send photo" with no next step; and
// the cleanup trusted `remove`, which does NOT throw for an object it could
// not delete — a private photo left in storage was recorded nowhere.
//
// HOW TO SEE IT FAIL: run against f191d48's chat_screen.dart.

const _uid = '00000000-0000-4000-8000-00000000c56a';
const _uidB = '00000000-0000-4000-8000-00000000c56b';
const _conv = 'conv-fl56a';
const _sendFailed = "Couldn't send your photo — $tryAgainHint";

enum _Remove {
  removed,
  emptyGone,
  emptyStillThere,
  emptyNearNameThere,
  throws,
  listThrows,
}

class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);
  bool uploadFails = false;
  _Remove remove = _Remove.removed;
  final storage = <String>[];

  /// Held (after being counted in [storage]) until completed.
  Completer<void>? uploadGate, deleteGate, listGate;

  /// The folder and the search the cleanup listed with.
  String? listedPrefix, listedSearch;
  String _uploaded = '';

  @override
  void reset() {
    super.reset();
    uploadFails = false;
    remove = _Remove.removed;
    uploadGate = deleteGate = listGate = null;
    listedPrefix = listedSearch = null;
    storage.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (!path.startsWith('/storage/v1/')) return super.send(request);
    if (path.startsWith('/storage/v1/object/list/')) {
      storage.add('LIST');
      final body = jsonDecode((request as http.Request).body) as Map;
      listedPrefix = body['prefix'] as String;
      listedSearch = body['search'] as String;
      await listGate?.future;
      if (remove == _Remove.listThrows) {
        return json({'message': 'SECRET', 'error': 'x', 'statusCode': '500'},
            500, request);
      }
      return json([
        if (remove == _Remove.emptyStillThere) {'name': _uploaded},
        if (remove == _Remove.emptyNearNameThere) {'name': '$_uploaded.bak'},
      ], 200, request);
    }
    storage.add(request.method);
    switch (request.method) {
      case 'DELETE':
        await deleteGate?.future;
        if (remove == _Remove.throws) {
          return json({'message': 'SECRET', 'error': 'x', 'statusCode': '500'},
              500, request);
        }
        final prefixes = (jsonDecode((request as http.Request).body)
            as Map)['prefixes'] as List;
        return json([
          if (remove == _Remove.removed) {'name': prefixes.single}
        ], 200, request);
      case 'HEAD': // `exists`: a 400 is what "may not see it" looks like.
        return http.StreamedResponse(const Stream.empty(), 400,
            request: request);
      default:
        _uploaded = path.split('/').last;
        await uploadGate?.future;
        return uploadFails
            ? json({'message': 'SECRET', 'error': 'x', 'statusCode': '403'},
                403, request)
            : json({'Key': 'k'}, 200, request);
    }
  }

  http.StreamedResponse json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// The real `sendMessage`; only opening the thread is answered here.
class _Thread extends MessagingService {
  _Thread({this.resolves});
  final Completer<String?>? resolves;
  final _stream = StreamController<List<Map<String, dynamic>>>();

  @override
  Future<String?> getOrCreateClientCoachConversation() async =>
      resolves == null ? _conv : await resolves!.future;
  @override
  Future<List<Map<String, dynamic>>> getMessages(String id) async => const [];
  @override
  Future<void> markAsRead(String id) async {}
  @override
  Stream<List<Map<String, dynamic>>> messagesStream(String id) =>
      _stream.stream;
  void dispose() => unawaited(_stream.close());
}

bool _isMessageInsert(String line) => line.startsWith('POST /rest/v1/messages');

void main() {
  late _Server server;
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await initSignedInSupabase(server);
    picker.install();
  });
  tearDownAll(picker.dispose);

  setUp(() async {
    await signInAs(_uid);
    server.reset();
    picker.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Future<void> open(WidgetTester t, {Completer<String?>? resolves}) async {
    final svc = _Thread(resolves: resolves);
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
  }

  Future<void> attach(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.image_outlined));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> outcome(WidgetTester t) async {
    await pumpUntil(t, () => find.byType(SnackBar).evaluate().isNotEmpty,
        what: 'the photo send outcome (a SnackBar)');
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 7));
  }

  void nothingRaw() {
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('vanished'), findsNothing);
  }

  group('the pick', () {
    testWidgets('photo access denied: says where to allow it, recorded',
        (t) async {
      await open(t);
      picker.fails('photo_access_denied');
      await attach(t);
      const msg = "Couldn't open your photos — allow photo access in "
          'Settings, then try again.';
      expect(find.text(msg), findsOneWidget,
          reason: 'THE defect: uncaught, and Attach did nothing');
      expect(liveRegionOver(msg), findsWidgets);
      expect(origins(), ['chat.photo.pick.gallery']);
      expect(server.storage, isEmpty);
      nothingRaw();
      await close(t);
    });

    testWidgets('any other picker failure: the generic next step; Attach '
        'works again', (t) async {
      await open(t);
      picker.fails('boom');
      await attach(t);
      expect(find.text("Couldn't open your photos — $tryAgainHint"),
          findsOneWidget);
      nothingRaw();
      picker.cancels();
      // The SnackBar sits over the composer until it times out (4 s).
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 1));
      await attach(t);
      expect(picker.calls, hasLength(2));
      await close(t);
    });

    testWidgets('an unreadable pick: said, recorded, nothing uploaded or sent; '
        'the composer is free again', (t) async {
      await open(t);
      picker.picksUnreadable();
      await attach(t);
      await outcome(t);
      expect(find.text("Couldn't use that photo — $tryAgainHint"),
          findsOneWidget);
      expect(origins(), ['chat.photo.read']);
      expect(server.storage, isEmpty);
      expect(server.writes.where(_isMessageInsert), isEmpty);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget,
          reason: 'not stuck in the sending state');
      nothingRaw();
      await close(t);
    });

    testWidgets('NEGATIVE CONTROL: cancelling is silent', (t) async {
      await open(t);
      picker.cancels();
      await attach(t);
      expect(picker.calls, ['pickImage:1']);
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
      expect(server.storage, isEmpty);
      await close(t);
    });

    testWidgets('a second tap while the picker is open opens no second one',
        (t) async {
      await open(t);
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await attach(t);
      await attach(t);
      expect(picker.calls, hasLength(1));
      gate.complete(null);
      await t.pump();
      await close(t);
    });

    testWidgets('Attach before the conversation is ready says so', (t) async {
      final resolves = Completer<String?>();
      await open(t, resolves: resolves);
      await attach(t);
      expect(
          find.text("This conversation isn't ready yet — try again in a "
              'moment.'),
          findsOneWidget,
          reason: 'it returned without a word');
      expect(picker.calls, isEmpty);
      resolves.complete(_conv);
      await close(t);
    });
  });

  group('after the pick', () {
    testWidgets('POSITIVE CONTROL: uploaded, one message row carrying the '
        'object path, no notice, nothing removed', (t) async {
      await open(t);
      await attach(t);
      await pumpUntil(t, () => server.writes.any(_isMessageInsert),
          what: 'the message row');
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final row = server.writes.singleWhere(_isMessageInsert);
      expect(row, contains('messages/$_conv/$_uid/'));
      expect(server.storage, ['POST']);
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('a refused upload: said with the next step, recorded, no row',
        (t) async {
      await open(t);
      server.uploadFails = true;
      await attach(t);
      await outcome(t);
      expect(find.text(_sendFailed), findsOneWidget);
      expect(find.text('Failed to send photo'), findsNothing,
          reason: 'one voice: the same failure was said twice');
      expect(liveRegionOver(_sendFailed), findsWidgets);
      expect(origins(), ['ChatScreen._sendPhoto']);
      expect(server.writes.where(_isMessageInsert), isEmpty);
      expect(server.storage, ['POST'], reason: 'nothing was stored to remove');
      nothingRaw();
      await close(t);
    });

    testWidgets('a connection failure on the row gets the connection hint',
        (t) async {
      await open(t);
      server
        ..mode = WriteMode.network
        ..modeAppliesTo = _isMessageInsert;
      await attach(t);
      await outcome(t);
      expect(
          find.text("Couldn't send your photo — check your connection and "
              'try again.'),
          findsOneWidget);
      await close(t);
    });
  });

  group('the row did not land: the orphan', () {
    Future<void> sendWithRefusedRow(WidgetTester t, _Remove remove) async {
      await open(t);
      server
        ..remove = remove
        ..mode = WriteMode.serverError
        ..modeAppliesTo = _isMessageInsert;
      await attach(t);
      await outcome(t);
      expect(find.text(_sendFailed), findsOneWidget,
          reason: 'a photo whose row was refused was not sent');
      expect(server.writes.where(_isMessageInsert), hasLength(1));
      nothingRaw();
    }

    testWidgets('removed: cleaned up, nothing more to record', (t) async {
      await sendWithRefusedRow(t, _Remove.removed);
      expect(server.storage, ['POST', 'DELETE']);
      expect(origins(), ['MessagingService.sendMessage']);
      await close(t);
    });

    testWidgets('empty answer and the object is gone: legitimately absent',
        (t) async {
      await sendWithRefusedRow(t, _Remove.emptyGone);
      expect(server.storage, ['POST', 'DELETE', 'LIST'],
          reason: '`exists` (HEAD) reads every 400/404 as gone');
      expect(server.listedPrefix, 'messages/$_conv/$_uid');
      expect(server.listedSearch, matches(RegExp(r'^\d+\.png$')));
      expect(origins(), ['MessagingService.sendMessage']);
      await close(t);
    });

    testWidgets('empty answer and only a near name is listed: the exact object '
        'is gone', (t) async {
      await sendWithRefusedRow(t, _Remove.emptyNearNameThere);
      expect(server.storage, ['POST', 'DELETE', 'LIST']);
      expect(origins(), ['MessagingService.sendMessage']);
      await close(t);
    });

    testWidgets('empty answer and the object is STILL THERE: recorded',
        (t) async {
      await sendWithRefusedRow(t, _Remove.emptyStillThere);
      expect(origins(), [
        'MessagingService.sendMessage',
        'ChatScreen._sendPhoto.cleanup',
      ], reason: 'THE defect: an empty remove read as a clean-up');
      await close(t);
    });

    testWidgets('remove throws: recorded', (t) async {
      await sendWithRefusedRow(t, _Remove.throws);
      expect(origins(), contains('ChatScreen._sendPhoto.cleanup'));
      await close(t);
    });

    testWidgets('empty answer and the check itself fails: unknown is not '
        '"gone" — recorded', (t) async {
      await sendWithRefusedRow(t, _Remove.listThrows);
      expect(origins(), contains('ChatScreen._sendPhoto.cleanup'));
      await close(t);
    });
  });

  group('B signs in after the pick', () {
    Future<void> signInB(WidgetTester t) async {
      await t.runAsync(() => signInAs(_uidB));
      expect(Supabase.instance.client.auth.currentUser?.id, _uidB,
          reason: 'premise');
    }

    Future<void> recorded(WidgetTester t, String origin) async {
      await pumpUntil(t, () => origins().contains(origin), what: origin);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SnackBar), findsNothing,
          reason: 'the notice belonged to the member who left');
    }

    const cleanup = 'ChatScreen._sendPhoto.cleanup';

    testWidgets("during the upload: nothing is sent as B in A's conversation; "
        'the leftover is recorded, not asked about as B', (t) async {
      server.uploadGate = Completer<void>();
      await open(t);
      await attach(t);
      await pumpUntil(t, () => server.storage.isNotEmpty, what: 'the upload');
      await signInB(t);
      server.uploadGate!.complete();
      await pumpUntil(
          t, () => server.writes.isNotEmpty || origins().contains(cleanup),
          what: 'the refusal');
      expect(server.writes, isEmpty,
          reason: 'THE defect: a row as B, plus the preview PATCH');
      await recorded(t, cleanup);
      expect(server.storage, ['POST']);
      expect(origins(), ['ChatScreen._sendPhoto', cleanup]);
      expect((reported.first.error as StateError).message,
          'the member changed during an upload');
      await close(t);
    });

    testWidgets('during a refused upload: recorded, nothing said to B',
        (t) async {
      server
        ..uploadGate = Completer<void>()
        ..uploadFails = true;
      await open(t);
      await attach(t);
      await pumpUntil(t, () => server.storage.isNotEmpty, what: 'the upload');
      await signInB(t);
      server.uploadGate!.complete();
      await recorded(t, 'ChatScreen._sendPhoto');
      expect(server.storage, ['POST']);
      await close(t);
    });

    testWidgets('during a refused row: no clean-up request as B, recorded',
        (t) async {
      server
        ..gate = Completer<void>()
        ..mode = WriteMode.serverError
        ..modeAppliesTo = _isMessageInsert;
      await open(t);
      await attach(t);
      await pumpUntil(t, () => server.writes.any(_isMessageInsert),
          what: 'the row');
      await signInB(t);
      server.gate!.complete();
      await recorded(t, cleanup);
      expect(server.storage, ['POST']);
      expect(origins(), ['MessagingService.sendMessage', cleanup]);
      await close(t);
    });

    testWidgets('during the remove: its empty answer is not "gone", and the '
        'folder is not listed as B', (t) async {
      server
        ..remove = _Remove.emptyGone
        ..deleteGate = Completer<void>()
        ..mode = WriteMode.serverError
        ..modeAppliesTo = _isMessageInsert;
      await open(t);
      await attach(t);
      await pumpUntil(t, () => server.storage.contains('DELETE'),
          what: 'the remove');
      await signInB(t);
      server.deleteGate!.complete();
      await recorded(t, cleanup);
      expect(server.storage, ['POST', 'DELETE']);
      await close(t);
    });

    testWidgets('during the list: an empty folder is not "gone" — recorded',
        (t) async {
      server
        ..remove = _Remove.emptyGone
        ..listGate = Completer<void>()
        ..mode = WriteMode.serverError
        ..modeAppliesTo = _isMessageInsert;
      await open(t);
      await attach(t);
      await pumpUntil(t, () => server.storage.contains('LIST'),
          what: 'the list');
      await signInB(t);
      server.listGate!.complete();
      await recorded(t, cleanup);
      await close(t);
    });

    testWidgets('while an unreadable photo is read: recorded, nothing said',
        (t) async {
      await open(t);
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await attach(t);
      await signInB(t);
      gate.complete(picker.vanishedPath);
      await recorded(t, 'chat.photo.read');
      expect(server.storage, isEmpty);
      await close(t);
    });
  });

  testWidgets("A's pick, B signs in while the picker is open: nothing is "
      'uploaded or sent as B', (t) async {
    await open(t);
    final gate = Completer<Object?>();
    picker.answer = (_) => gate.future;
    await attach(t);
    await t.runAsync(() => signInAs(_uidB));
    gate.complete(picker.photoPath);
    await pumpUntil(t, () => reported.isNotEmpty, what: 'the refusal');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(SnackBar), findsNothing,
        reason: 'the notice belonged to the member who left');
    expect(origins(), ['ChatScreen._sendPhoto']);
    expect(server.storage, isEmpty);
    expect(server.writes.where(_isMessageInsert), isEmpty);
    await close(t);
  });

  testWidgets('Attach while signed out says so', (t) async {
    await open(t);
    await t.runAsync(() =>
        Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    await attach(t);
    expect(find.text("You're signed out — sign in again to send a photo."),
        findsOneWidget);
    expect(picker.calls, isEmpty);
    await close(t);
  });
}
