// Instance ids for engine-selected exercises written by the app (Copilot).
//
// Migration 192 recognises engine-selected training by UUID-shaped
// `exercise_instance_id`s: the programme engine mints them with gen_random_uuid(),
// and a day that reuses one inside an unmarked programme carries the
// engine_selected mark with it. Hand-built days use the editor's 'ex-…' ids, so
// they never match. Copilot must therefore mint UUIDs too — without them its saved
// days would get the canonicalizer's name-based fallback ids and a verbatim copy
// of them could not be told from hand-built content.
import 'dart:math';

final Random _secure = Random.secure();

/// A random RFC 4122 version-4 UUID string.
String newEngineInstanceId([Random? rng]) {
  final r = rng ?? _secure;
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
