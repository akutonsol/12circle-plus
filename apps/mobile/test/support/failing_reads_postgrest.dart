import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'row_checking_postgrest.dart';

/// How a read of one table fails.
enum ReadFailure {
  /// The request never reached the server (http.ClientException).
  network,

  /// The server refused it: `500` (a PostgrestException).
  server,
}

/// [RowCheckingPostgrest] plus per-table READ failures and DELETE handling
/// (P0-FL-50a).
///
/// * [failReads]: a GET on `/rest/v1/<table>` fails as configured.
/// * DELETE is a write like PATCH: recorded in [writes]; answered per
///   [deleteMode] — `200 []`/`200 [row]` when `select=` asks for rows back,
///   `204` (no body) otherwise, which is also what a 0-row delete looks like.
/// * [readGate]: when set, every GET is counted at once but answered only when
///   it completes (a read "in flight").
class FailingReadsPostgrest extends RowCheckingPostgrest {
  FailingReadsPostgrest(super.uid);

  final Map<String, ReadFailure> failReads = {};
  final Map<String, int> readCounts = {};
  WriteMode deleteMode = WriteMode.oneRow;
  Completer<void>? readGate;

  @override
  void reset() {
    super.reset();
    failReads.clear();
    readCounts.clear();
    deleteMode = WriteMode.oneRow;
    readGate = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final table = path.split('/').last;
    if (request.method == 'GET' && path.contains('/rest/v1/')) {
      readCounts[table] = (readCounts[table] ?? 0) + 1;
      if (readGate != null) await readGate!.future;
      switch (failReads[table]) {
        case ReadFailure.network:
          throw http.ClientException('Connection refused', request.url);
        case ReadFailure.server:
          return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
        case null:
          break;
      }
    }
    if (request.method == 'DELETE') {
      writes.add('DELETE $path?${request.url.query}');
      final asksForRows = request.url.queryParameters.containsKey('select');
      switch (deleteMode) {
        case WriteMode.network:
          throw http.ClientException('Connection refused', request.url);
        case WriteMode.serverError:
          return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
        case WriteMode.zeroRows:
          return asksForRows
              ? _json([], 200, request)
              : http.StreamedResponse(const Stream.empty(), 204, request: request);
        case WriteMode.oneRow:
          return asksForRows
              ? _json([
                  {'id': 'row-1'}
                ], 200, request)
              : http.StreamedResponse(const Stream.empty(), 204, request: request);
      }
    }
    return super.send(request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}
