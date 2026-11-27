import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `record` and `audioplayers` plugins, answered at their platform
/// channels (P0-FL-59d): a real temp file is "captured", and every call is
/// logged, so the recorder and the player can be driven without a device.
class FakeCoachAudio {
  late Directory _tmp;
  final calls = <String>[];

  /// What the plugins do; null = it works.
  Object? permissionFails;
  bool permission = true;
  Object? startFails;
  Object? stopFails;
  Object? playFails;
  Object? pauseFails;

  /// The recorder stops, and has nothing.
  bool stopsEmpty = false;

  /// When set, `hasPermission` / `start` wait for it.
  Completer<void>? permissionGate;
  Completer<void>? startGate;

  /// When set, the recorder's stop waits for it.
  Completer<void>? stopGate;

  /// When set, the player's source waits for it.
  Completer<void>? playGate;

  /// Where the player says it is, in ms.
  int? position;

  String? _path;
  String? _playerEvents;

  /// Every capture still on the device.
  List<String> get filesLeft =>
      _tmp.existsSync() ? [for (final f in _tmp.listSync()) f.path.split('/').last] : [];

  TestDefaultBinaryMessenger get _m =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _tmp = Directory.systemTemp.createTempSync('fl59d_');
    calls.clear();
    permission = true;
    permissionFails = startFails = stopFails = playFails = pauseFails = null;
    stopsEmpty = false;
    permissionGate = startGate = stopGate = playGate = null;
    position = null;
    const codec = StandardMethodCodec();
    _m.allMessagesHandler = (channel, handler, message) async {
      if (channel == 'plugins.flutter.io/path_provider') {
        return codec.encodeSuccessEnvelope(_tmp.path);
      }
      if (!channel.startsWith('com.llfbandit.record/') &&
          !channel.startsWith('xyz.luan/audioplayers')) {
        return handler?.call(message);
      }
      final call = codec.decodeMethodCall(message);
      if (channel.startsWith('xyz.luan/audioplayers/events/')) {
        _playerEvents = channel;
        return codec.encodeSuccessEnvelope(null);
      }
      calls.add(call.method);
      try {
        return codec.encodeSuccessEnvelope(await _answer(call));
      } catch (e) {
        return codec.encodeErrorEnvelope(code: 'x', message: 'SECRET plugin text');
      }
    };
  }

  /// Call in setUpAll: audioplayers sets itself up once per isolate, with the
  /// first player. Inside a widget test that is on that test's fake clock, and
  /// every later test's player waits for it for ever.
  Future<void> warmUp() async {
    install();
    final p = AudioPlayer();
    await p.creatingCompleter.future;
    await p.dispose();
    uninstall();
  }

  Future<Object?> _answer(MethodCall call) async {
    void failIf(Object? e) {
      if (e != null) throw e;
    }

    switch (call.method) {
      case 'hasPermission':
        await permissionGate?.future;
        failIf(permissionFails);
        return permission;
      case 'start':
        await startGate?.future;
        failIf(startFails);
        _path = (call.arguments as Map)['path'] as String;
        File(_path!).writeAsBytesSync([1, 2, 3]);
        return null;
      case 'stop':
        if ((call.arguments as Map).containsKey('recorderId')) {
          final path = _path, fails = stopFails;
          await stopGate?.future;
          failIf(fails);
          return stopsEmpty ? null : path;
        }
        return null;
      case 'setSourceUrl':
        await playGate?.future;
        failIf(playFails);
        playing.add((call.arguments as Map)['url'] as String);
        // The platform says it is ready to play.
        scheduleMicrotask(() => event({'event': 'audio.onPrepared', 'value': true}));
        return null;
      case 'getCurrentPosition':
        return position;
      case 'pause':
        failIf(pauseFails);
        return null;
      default:
        return null;
    }
  }

  /// URLs handed to the player.
  final playing = <String>[];

  /// The platform tells the player something.
  void event(Map<String, Object?> e) => _m.handlePlatformMessage(
      _playerEvents!, const StandardMethodCodec().encodeSuccessEnvelope(e), (_) {});

  /// The platform's player fails part-way.
  void streamError() => _m.handlePlatformMessage(
      _playerEvents!,
      const StandardMethodCodec()
          .encodeErrorEnvelope(code: 'x', message: 'SECRET plugin text'),
      (_) {});

  void uninstall() {
    _m.allMessagesHandler = null;
    playing.clear();
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  }
}
