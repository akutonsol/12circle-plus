import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/observability/network_failure.dart';
import 'package:circle_fitness/features/messaging/data/messaging_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-13 · the failure KIND of a send that did not land reaches the caller
// (`onNotSent`), so the chat can show the connection hint only for a
// connection failure. Kept apart from messaging_inbox_and_send_truth_test.dart
// because this is new API: on 2ecd6e2 this file does not compile, whereas that
// file's tests fail on 2ecd6e2 for their stated behavioural reasons.

const _uid = '00000000-0000-4000-8000-0000000f1014';

bool _isMessageInsert(String line) => line.startsWith('POST /rest/v1/messages');
bool _isPreviewWrite(String line) =>
    line.startsWith('PATCH /rest/v1/conversations');

void main() {
  late RowCheckingPostgrest server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RowCheckingPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<(bool, List<Object>)> send() async {
    final errors = <Object>[];
    final ok = await MessagingService().sendMessage(
        conversationId: 'c', content: 'hi', onNotSent: errors.add);
    return (ok, errors);
  }

  test('connection failure: onNotSent gets an error isNetworkFailure accepts',
      () async {
    server
      ..mode = WriteMode.network
      ..modeAppliesTo = _isMessageInsert;
    final (ok, errors) = await send();
    expect(ok, isFalse);
    expect(errors, hasLength(1));
    expect(isNetworkFailure(errors.single), isTrue);
  });

  test('server refusal: onNotSent gets an error that is NOT a network failure',
      () async {
    server
      ..mode = WriteMode.serverError
      ..modeAppliesTo = _isMessageInsert;
    final (ok, errors) = await send();
    expect(ok, isFalse);
    expect(errors.single, isA<PostgrestException>());
    expect(isNetworkFailure(errors.single), isFalse);
  });

  test('preview failure after a saved insert: onNotSent is NOT called',
      () async {
    server
      ..mode = WriteMode.network
      ..modeAppliesTo = _isPreviewWrite;
    final (ok, errors) = await send();
    expect(ok, isTrue);
    expect(errors, isEmpty, reason: 'the message is sent; nothing invites a resend');
    expect(reported.map((f) => f.origin),
        contains('MessagingService.sendMessage.preview'));
    expect(reported.single.error, isA<http.ClientException>());
  });
}
