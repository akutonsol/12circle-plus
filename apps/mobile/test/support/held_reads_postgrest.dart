import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'rpc_answering_postgrest.dart';

/// [RpcAnsweringPostgrest] plus three things the Coach Focus tests need
/// (P0-FL-53a round 2):
///
/// * [readQueue]: per-table answers used one per GET, in order, before
///   falling back to `reads` — so a row can change between two reads.
/// * [holdTable]: every GET on that table waits on its own entry in [held]
///   (complete it with `true` to answer normally, `false` to answer `500`),
///   so two overlapping reads can be landed in either order.
/// * Storage object removal (`DELETE /storage/v1/object/<bucket>`) answers
///   `200 []` — or `500` when [failStorageDelete] is set.
class HeldReadsPostgrest extends RpcAnsweringPostgrest {
  HeldReadsPostgrest(super.uid);

  final Map<String, List<Object?>> readQueue = {};
  String? holdTable;
  final held = <Completer<bool>>[];
  bool failStorageDelete = false;

  @override
  void reset() {
    super.reset();
    readQueue.clear();
    holdTable = null;
    held.clear();
    failStorageDelete = false;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'DELETE' && path.contains('/storage/v1/')) {
      writes.add('DELETE $path');
      return failStorageDelete
          ? _json({'message': 'refused', 'statusCode': '500'}, 500, request)
          : _json([], 200, request);
    }
    if (request.method == 'GET' && path.contains('/rest/v1/')) {
      final table = path.split('/').last;
      if (table == holdTable) {
        readCounts[table] = (readCounts[table] ?? 0) + 1;
        final c = Completer<bool>();
        held.add(c);
        final ok = await c.future;
        if (!ok) return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
        return _answer(table, request);
      }
      final q = readQueue[table];
      if (q != null && q.isNotEmpty && failReads[table] == null) {
        readCounts[table] = (readCounts[table] ?? 0) + 1;
        final next = q.removeAt(0);
        final single =
            request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
        if (next is Map) return _json(single ? next : [next], 200, request);
        return _json(next ?? (single ? null : []), 200, request);
      }
    }
    return super.send(request);
  }

  http.StreamedResponse _answer(String table, http.BaseRequest request) {
    final single =
        request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    final answer = reads[table];
    if (answer is Map) return _json(single ? answer : [answer], 200, request);
    if (answer is List) return _json(answer, 200, request);
    return _json(single ? null : [], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}
