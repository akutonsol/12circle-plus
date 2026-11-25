import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/observability/network_failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-60b (b) · which storage failures are the connection.
//
// storage_client's `_handleError` turns a non-response into
// `StorageException(error.toString(), statusCode: '<runtimeType>')`, and a
// response into `StorageException(message, statusCode: '404', error: …)`.
// Only the first is the connection. The second group drives the REAL client.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- lib/core/observability/
// network_failure.dart`; the 'wrapped' cases fail, every control passes.

class _Storage extends http.BaseClient {
  _Storage(this.answer);
  final http.StreamedResponse Function(http.BaseRequest) answer;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      answer(request);
}

Future<Object> _thrown(http.StreamedResponse Function(http.BaseRequest) answer,
    Future<Object?> Function(StorageFileApi) call) async {
  final client = SupabaseClient('http://127.0.0.1:1', 'key',
      httpClient: _Storage(answer),
      authOptions: const AuthClientOptions(autoRefreshToken: false));
  addTearDown(client.dispose);
  try {
    await call(client.storage.from('b'));
  } catch (e) {
    return e;
  }
  fail('premise: the call must fail');
}

final _calls = <String, Future<Object?> Function(StorageFileApi)>{
  'upload': (b) => b.uploadBinary('a/x.jpg', Uint8List.fromList([1])),
  'download': (b) => b.download('a/x.jpg'),
  'list': (b) => b.list(path: 'a'),
  'remove': (b) => b.remove(['a/x.jpg']),
  'sign': (b) => b.createSignedUrl('a/x.jpg', 60),
};

void main() {
  group('wrapped client error (no server answer) → connection', () {
    for (final inner in <Object>[
      http.ClientException('Connection closed'),
      const SocketException('no route to host'),
      TimeoutException('slow', const Duration(seconds: 1)),
    ]) {
      test('${inner.runtimeType}', () {
        expect(
            isNetworkFailure(StorageException(inner.toString(),
                statusCode: inner.runtimeType.toString())),
            isTrue);
      });
      test('${inner.runtimeType}, no status at all', () {
        expect(isNetworkFailure(StorageException(inner.toString())), isTrue);
      });
    }
    test("the io client's own subclass of ClientException", () {
      expect(
          isNetworkFailure(const StorageException(
              'ClientException with SocketException: Failed host lookup, '
              'uri=https://x',
              statusCode: '_ClientSocketException')),
          isTrue);
    });
  });

  group("the server's answer → never the connection", () {
    for (final status in ['400', '401', '403', '404', '413', '500', '503']) {
      test(status, () {
        expect(isNetworkFailure(StorageException('refused', statusCode: status)),
            isFalse);
        // Whatever its text says.
        expect(
            isNetworkFailure(StorageException('ClientException: closed',
                statusCode: status)),
            isFalse);
      });
    }
    test('an answer with the server error field and no status', () {
      expect(
          isNetworkFailure(const StorageException('ClientException: closed',
              error: 'Gateway')),
          isFalse);
    });
    test('no status, not a client error', () {
      expect(isNetworkFailure(const StorageException('boom')), isFalse);
    });
    test('wrapped, but something else failed (bad JSON)', () {
      expect(
          isNetworkFailure(const StorageException(
              'FormatException: Unexpected character',
              statusCode: 'FormatException')),
          isFalse);
    });
    test('a client error only quoted inside the text', () {
      expect(
          isNetworkFailure(const StorageException(
              'upstream said ClientException: closed')),
          isFalse);
    });
  });

  group('the real storage client', () {
    _calls.forEach((name, call) {
      for (final status in [403, 404, 413, 500]) {
        test('$name answered $status → not the connection', () async {
          final e = await _thrown(
              (r) => http.StreamedResponse(
                  Stream.value(utf8.encode(jsonEncode({
                    'statusCode': '$status',
                    'error': 'refused',
                    'message': 'ClientException: not really',
                  }))),
                  status,
                  request: r,
                  headers: {'content-type': 'application/json'}),
              call);
          expect(e, isA<StorageException>());
          expect(isNetworkFailure(e), isFalse);
        });
      }
      test('$name answered a 502 page (no JSON) → not the connection',
          () async {
        final e = await _thrown(
            (r) => http.StreamedResponse(
                Stream.value(utf8.encode('<html>Bad gateway</html>')), 502,
                request: r),
            call);
        expect(e, isA<StorageException>());
        expect(isNetworkFailure(e), isFalse);
      });
      test('$name did not reach the server → the connection', () async {
        final e = await _thrown(
            (r) => throw http.ClientException('Connection refused', r.url),
            call);
        expect(isNetworkFailure(e), isTrue, reason: '${e.runtimeType}: $e');
      });
    });
  });
}
