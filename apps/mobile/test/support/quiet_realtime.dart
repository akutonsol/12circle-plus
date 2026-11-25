import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// `initTwoMemberSupabase` with a realtime socket that connects and says
/// nothing (P0-FL-60c round 2): a live feed reads its rows once and then holds
/// still, instead of failing to connect — and being read again — while a test
/// counts reads.
Future<void> initTwoMemberSupabaseQuietly(http.BaseClient server) =>
    Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      realtimeClientOptions:
          RealtimeClientOptions(transport: (_, __) => _QuietSocket()),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

/// Only what the realtime client uses; anything else fails loudly.
class _QuietSocket implements WebSocketChannel {
  final _toClient = StreamController<String>();
  @override
  Stream<dynamic> get stream => _toClient.stream;
  @override
  late final WebSocketSink sink = _QuietSink(_toClient);
  @override
  Future<void> get ready => Future.value();
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietSink implements WebSocketSink {
  _QuietSink(this._toClient);
  final StreamController<String> _toClient;
  @override
  void add(dynamic data) {}
  @override
  Future<void> close([int? closeCode, String? closeReason]) => _toClient.close();
  @override
  Future<void> get done => Completer<void>().future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
