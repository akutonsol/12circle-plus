import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAP-G1 — tappables that wrap a fixed box under 44 dp must not multiply.
///
/// ── WHY THIS EXISTS, AND WHY IT IS ONLY A CANDIDATE COUNT ──────────────────
/// `A-G8` ratchets whether an icon control has a **name**. Nothing ratcheted
/// its **size**, and the design package keeps finding the same defect by hand:
///
///   * FIT-058 — *"Tapping the row is the whole interaction"*; the shipped tap
///     target was a 32 × 32 circle;
///   * FIT-100 — *"Toggle is 44px — **the source has 32**."*
///
/// Two anchors, independently, measuring the same 32 px.
///
/// ── WHAT IT DETECTS ────────────────────────────────────────────────────────
/// A `GestureDetector` / `InkWell` / `InkResponse` with an `onTap` whose
/// **immediate** child is a `Container` or `AnimatedContainer` with a fixed
/// `width`/`height` under 44 — which, with the default `deferToChild` hit
/// behaviour, IS the hit area.
///
/// The "immediate child" restriction matters. A looser first pass — any
/// `width:`/`height:` within 520 characters — reported **44** sites across 30
/// files, and most of the extra were decorative boxes **inside** a large
/// tappable: a 12 × 12 dot, an 18 × 18 icon. Tightening to the immediate child
/// gave **17**, and two spot-checks (`app_top_nav.dart`, `directory_screen`)
/// confirmed those are real hit areas.
///
/// ── WHAT IT STILL CANNOT DO ────────────────────────────────────────────────
/// **Source cannot measure a touch target.** A target sized by its parent, by
/// padding, or by an `IconButton`'s own 48 dp default is invisible here, and a
/// fixed box inside a larger `InkWell` can still be fine. F-6/F-6b are the
/// record of why runtime is authoritative: the password toggle *looked* correct
/// in source and measured **19.8 × 20.2 dp** on the device.
///
/// So this is a **candidate ratchet**, in the same spirit as A-G8's recorded
/// overstatement. It may fall. It may not rise.
void main() {
  /// Measured 2026-09-24, after lifting `app_top_nav.dart`'s avatar — a 42 dp
  /// hit area on the control that appears in **every** screen's top bar — to
  /// the floor.
  const baseline = 16;

  final pattern = RegExp(
    r'(GestureDetector|InkWell|InkResponse)\(\s*(?:[^()]{0,120}?)?onTap:'
    r'[\s\S]{0,180}?child:\s*(?:Animated)?Container\(\s*(?:[\s\S]{0,60}?)'
    r'width:\s*(\d+)(?:\.\d+)?\s*,\s*height:\s*(\d+)(?:\.\d+)?',
  );

  List<({String file, int line, int w, int h})> scan() {
    final out = <({String file, int line, int w, int h})>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // Comments quote sizes constantly in this codebase — five detectors
      // here have read their own prose as evidence.
      final src = f
          .readAsStringSync()
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i < 0 ? l : l.substring(0, i);
          })
          .join('\n');

      for (final m in pattern.allMatches(src)) {
        final w = int.parse(m.group(2)!);
        final h = int.parse(m.group(3)!);
        if (w >= 44 && h >= 44) continue;
        final seg = src.substring(
            m.start, (m.start + 400).clamp(0, src.length));
        // Already lifted by an explicit floor.
        if (seg.contains('minWidth: 44') || seg.contains('minHeight: 44')) {
          continue;
        }
        out.add((
          file: f.path,
          line: src.substring(0, m.start).split('\n').length,
          w: w,
          h: h
        ));
      }
    }
    return out;
  }

  test('TAP-G1 the detector still finds the shape it counts', () {
    // An absent result must not read as "everything clears the floor" — the
    // H-D1 lesson, which this suite has been bitten by repeatedly.
    final found = scan();
    expect(found, isNotEmpty,
        reason: 'the scanner found nothing at all, which is false of this '
            'codebase — the detector is broken');

    // And it must still see known sites. When one is fixed, delete it here
    // and lower the baseline in the same change.
    final files = found.map((h) => h.file).toSet();
    for (final path in const [
      'lib/features/dashboard/presentation/directory_screen.dart',
      'lib/features/nutrition/presentation/meals_dashboard_screen.dart',
    ]) {
      expect(files, contains(path),
          reason: '$path is a recorded sub-44 site; the detector no longer '
              'sees it, so the count means nothing');
    }
  });

  test('TAP-G1 the high-traffic avatar keeps its 44 dp hit area', () {
    // `app_top_nav.dart` renders on every screen's top bar. Its avatar was
    // 42 x 42 — two dp under — and is the single most-shown touch target in
    // the app.
    final nav = File('lib/core/widgets/app_top_nav.dart').readAsStringSync();
    expect(nav, contains('minWidth: 44'));
    expect(nav, contains('minHeight: 44'));
    expect(nav, contains('HitTestBehavior.opaque'),
        reason: 'without it the lifted box is not itself tappable');
  });

  test('TAP-G1 sub-44 tappables do not increase', () {
    final found = scan();
    final worst = (found.toList()
          ..sort((a, b) => (a.w * a.h).compareTo(b.w * b.h)))
        .take(8)
        .map((h) => '  ${h.w}x${h.h}  ${h.file}:${h.line}')
        .join('\n');

    expect(
      found.length,
      lessThanOrEqualTo(baseline),
      reason: 'A tappable was added whose hit area is a fixed box under 44 dp. '
          'The design package has now named this defect on two separate '
          'anchors (FIT-058, FIT-100), both measuring 32 px.\n'
          'Found ${found.length} (baseline $baseline). Smallest:\n$worst\n\n'
          'Wrap the child in `BoxConstraints(minWidth: 44, minHeight: 44)` '
          'with `HitTestBehavior.opaque`, or use `NamedIconButton`, which '
          'does both and carries a name.',
    );
  });
}
