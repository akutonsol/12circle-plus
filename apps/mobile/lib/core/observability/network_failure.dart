import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthRetryableFetchException, StorageException;

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
/// P0-FL-60b · the same for a `StorageException`, except the one shape in which
/// storage_client can wrap the http client's own error.
///
/// The one shared rule (P0-FL-11); it replaced eight identical private copies
/// (activity, coach business, coach pricing, community, client detail, create
/// exercise, home, settings).
bool isNetworkFailure(Object? error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is http.ClientException ||
    error is AuthRetryableFetchException ||
    (error is StorageException && _wrapsClientFailure(error));

/// storage_client's `_handleError`, when what failed was not a response:
/// `StorageException(error.toString(), statusCode: '<runtimeType>')`. A
/// response always sets an HTTP status (`404`), so all three must hold: no
/// HTTP status, no server `error` field, and the client error's own text.
/// (A web release minifies type names and so never matches: no hint, rather
/// than a wrong one. storage_client 2.5.6's request paths let the client's
/// error through unwrapped, which needs no help here.)
bool _wrapsClientFailure(StorageException e) =>
    e.error == null &&
    const {
      null,
      'ClientException',
      '_ClientSocketException',
      'SocketException',
      'TimeoutException',
    }.contains(e.statusCode) &&
    RegExp(r'^(ClientException|SocketException|TimeoutException)\b')
        .hasMatch(e.message);
