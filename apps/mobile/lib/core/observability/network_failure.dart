import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthRetryableFetchException;

/// True only when [error] is the request not reaching the server: no socket,
/// a timeout, or the http client giving up (postgrest-dart lets the http
/// client's exception through untouched; gotrue wraps it as
/// [AuthRetryableFetchException]).
///
/// A `PostgrestException` always carries the server's answer, so it is never
/// a connection problem — telling the user to check their connection would
/// send them the wrong way. Connection wording is only for failures that ARE
/// the connection.
///
/// The one shared rule (P0-FL-11); it replaced eight identical private copies
/// (activity, coach business, coach pricing, community, client detail, create
/// exercise, home, settings).
bool isNetworkFailure(Object? error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is http.ClientException ||
    error is AuthRetryableFetchException;
