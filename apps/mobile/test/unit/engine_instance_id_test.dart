import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/coach/domain/engine_instance_id.dart';

// The pattern migration 192's _is_uuid_text accepts.
final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

void main() {
  test('is a version-4 UUID the database recognises as engine-selected', () {
    for (var i = 0; i < 200; i++) {
      final id = newEngineInstanceId();
      expect(id, matches(_uuid));
      expect(id[14], '4', reason: 'version nibble');
      expect('89ab'.contains(id[19]), isTrue, reason: 'RFC 4122 variant');
    }
  });

  test('is unique across many draws', () {
    final ids = {for (var i = 0; i < 5000; i++) newEngineInstanceId()};
    expect(ids.length, 5000);
  });

  test('never looks like a hand-built editor id', () {
    expect(newEngineInstanceId(Random(1)), isNot(startsWith('ex-')));
  });
}
