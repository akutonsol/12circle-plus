import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// P0-FL-56a · image_picker answered at its platform channel (the FL-53c
/// pattern): [answer] returns a path (picked), null (cancelled) or throws.
class FakeImagePicker {
  late final Directory _tmp;

  /// A readable 1×1 PNG.
  late final String photoPath;

  /// A path whose file does not exist: picked, but it cannot be read.
  late final String vanishedPath;

  /// Every call, `<method>:<source>` (source 0 = camera, 1 = gallery).
  final calls = <String>[];
  late Future<Object?> Function(MethodCall call) answer;

  /// Call in setUpAll.
  void install() {
    _tmp = Directory.systemTemp.createTempSync('fl56a_');
    photoPath = '${_tmp.path}/photo.png';
    vanishedPath = '${_tmp.path}/vanished.png';
    File(photoPath).writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhf'
        'DwAChwGA60e6kgAAAABJRU5ErkJggg=='));
    reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'), (call) {
      calls.add('${call.method}:${(call.arguments as Map)['source']}');
      return answer(call);
    });
  }

  /// Call in setUp: forgets the calls; picks the readable photo.
  void reset() {
    calls.clear();
    answer = (_) async => photoPath;
  }

  /// Call in tearDownAll.
  void dispose() => _tmp.deleteSync(recursive: true);

  void cancels() => answer = (_) async => null;
  void picksUnreadable() => answer = (_) async => vanishedPath;
  void fails(String code) => answer = (_) async =>
      throw PlatformException(code: code, message: 'SECRET platform text');
}

const tryAgainHint =
    'try again in a moment. If it keeps happening, contact support.';

/// A live region wraps [text] (a SnackBar is one on its own).
Finder liveRegionOver(String text) => find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.liveRegion ?? false)));
