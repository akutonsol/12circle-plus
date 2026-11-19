import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'row_checking_postgrest.dart';

/// How the next `user_profiles` READ is answered (P0-FL-16).
enum ProfileRead {
  /// 200 with the row in [ProfileReadPostgrest.profile] (or no row if null).
  ok,

  /// The request never reached the server (http.ClientException).
  network,

  /// The server refused it: 500, a PostgrestException — not a network error.
  serverError,
}

/// [RowCheckingPostgrest] whose `user_profiles` GET can fail, or be held in
/// flight with [readGate], so a test can see what a screen does with a failed
/// or pending profile read. Writes behave exactly as in the parent (a PATCH
/// without `select=` is 204, empty).
class ProfileReadPostgrest extends RowCheckingPostgrest {
  ProfileReadPostgrest(super.uid);

  ProfileRead profileRead = ProfileRead.ok;

  /// The stored row, or null for "no profile row".
  Map<String, Object?>? profile;

  /// When set, a profile read is counted at once but not answered until this
  /// completes.
  Completer<void>? readGate;

  /// Every `user_profiles` GET that reached the server.
  int profileReads = 0;

  @override
  void reset() {
    super.reset();
    profileRead = ProfileRead.ok;
    profile = null;
    readGate = null;
    profileReads = 0;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' &&
        request.url.path.endsWith('/user_profiles')) {
      profileReads++;
      if (readGate != null) await readGate!.future;
      switch (profileRead) {
        case ProfileRead.network:
          throw http.ClientException('Connection refused', request.url);
        case ProfileRead.serverError:
          return _json({'message': 'refused', 'code': 'XX000'}, 500, request);
        case ProfileRead.ok:
          final single =
              request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
          final row = profile;
          return _json(
              single ? row : [if (row != null) row], 200, request);
      }
    }
    return super.send(request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}
