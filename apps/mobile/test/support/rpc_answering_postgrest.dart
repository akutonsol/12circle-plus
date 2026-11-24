import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'failing_reads_postgrest.dart';

/// [FailingReadsPostgrest] that also answers `/rest/v1/rpc/<fn>` from
/// [rpcAnswers] (or fails it per [rpcFailures]).
class RpcAnsweringPostgrest extends FailingReadsPostgrest {
  RpcAnsweringPostgrest(super.uid);
  final Map<String, Object?> rpcAnswers = {};
  final Map<String, ReadFailure> rpcFailures = {};

  @override
  void reset() {
    super.reset();
    rpcAnswers.clear();
    rpcFailures.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.contains('/rest/v1/rpc/')) {
      final fn = path.split('/').last;
      switch (rpcFailures[fn]) {
        case ReadFailure.network:
          throw http.ClientException('Connection refused', request.url);
        case ReadFailure.server:
          return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
        case null:
          return _json(rpcAnswers[fn], 200, request);
      }
    }
    return super.send(request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}
