import 'dart:async';
import 'dart:io';

import 'package:circle_fitness/core/observability/network_failure.dart';
import 'package:circle_fitness/features/exercise_database/presentation/create_exercise_screen.dart'
    as create_exercise;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-11: the one shared network-failure rule (it replaced eight identical
// private copies). Connection wording is only for a request that never reached
// the server; anything the server answered is not a connection problem.
void main() {
  group('isNetworkFailure — the request did not reach the server', () {
    final cases = <String, Object>{
      'SocketException': const SocketException('no route to host'),
      'TimeoutException': TimeoutException('slow', const Duration(seconds: 1)),
      'http.ClientException': http.ClientException('Connection closed'),
      'AuthRetryableFetchException': AuthRetryableFetchException(),
    };
    cases.forEach((name, error) {
      test('$name → true', () => expect(isNetworkFailure(error), isTrue));
    });
  });

  group('isNetworkFailure — anything else is not a connection problem', () {
    for (final code in ['500', '42501', '23505', 'PGRST116', '401']) {
      test('PostgrestException code $code → false', () {
        expect(isNetworkFailure(PostgrestException(message: 'x', code: code)),
            isFalse);
      });
    }
    test('PostgrestException without a code → false', () {
      expect(isNetworkFailure(const PostgrestException(message: 'x')), isFalse);
    });
    test('StateError → false',
        () => expect(isNetworkFailure(StateError('signed out')), isFalse));
    test('FormatException → false',
        () => expect(isNetworkFailure(const FormatException('bad')), isFalse));
    test('null → false', () => expect(isNetworkFailure(null), isFalse));
  });

  test('create_exercise_screen still exports the same function (re-export)',
      () {
    // Its @visibleForTesting `isNetworkFailure` moved here; the screen
    // re-exports it so an importer of the screen keeps the name.
    expect(identical(create_exercise.isNetworkFailure, isNetworkFailure),
        isTrue);
  });
}
