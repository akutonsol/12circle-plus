import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CORR-G1 — a member's correction of their own health data must not fail
/// silently, and a cleared field must actually clear.
///
/// Originally a shrinking allowlist over three defects found in the
/// correction-rights audit. **Two are now closed** — the Cloud workstream
/// found and fixed CORR-1 and CORR-3 independently, which the local↔cloud
/// reconciliation surfaced when those assertions started failing.
///
/// Rather than delete the closed entries, they are **inverted**: the same
/// guard now asserts the FIX and fails if it is reverted. A shrinking
/// allowlist that merely loses an entry stops protecting anything, and the
/// two fixes here cover reproductive-health writes and the clearing of
/// personal data — both worth a standing ratchet.
///
///   CORR-1  CLOSED by Cloud `b0954f5` (QAX-ERR-01) — now a fix ratchet
///   CORR-2  **STILL OPEN** — `_persistUnit` swallows silently
///   CORR-3  CLOSED by Cloud `fdbd67b` (QAX-COR-01) — now a fix ratchet
///
/// ── WHY THE APP'S OWN CODE IS THE BASELINE ─────────────────────────────────
/// `daily_checkin_screen` + `WeeklyCheckinService.submitWeeklyCheckin` do this
/// correctly: the service returns `bool`, the screen branches on it and shows
/// *"Failed to save. Please try again."*, and `'notes': notes ?? ''` **clears**
/// rather than omitting. So the failures below are deviations from a pattern
/// this repository already established, not an absent convention.
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// Source with line comments removed.
  ///
  /// Mutation testing caught this: asserting `src.contains('catch')` on the
  /// raw file was killed by the word `catch` appearing in a **comment**. That
  /// is the commented-code-as-active-code trap this programme has already been
  /// bitten by in SQL, and it would have made the guard fail on a change that
  /// altered no behaviour.
  String code(String p) => read(p)
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i < 0 ? l : l.substring(0, i);
      })
      .join('\n');

  // ── 1. Women's health: CLOSED BY CLOUD (QAX-ERR-01) — now a FIX ratchet ───
  //
  // CORR-1 recorded that all four CycleService writes were `Future<void>` with
  // no `catch` and an `if (uid == null) return;` that made a signed-out write
  // indistinguishable from a saved one. The Cloud workstream fixed it
  // independently in `b0954f5` with `_requireUid()`, which THROWS.
  //
  // The defect assertions are not deleted — they are INVERTED. A shrinking
  // allowlist that simply loses its entry stops protecting anything; this way
  // the same guard now fails if the fix is ever reverted.
  group('CORR-1 · CycleService — fixed, now protected', () {
    late String src;
    setUpAll(() => src = code('lib/features/womens_health/data/cycle_service.dart'));

    test('the guard is reading the right file', () {
      // An absent result must not read as "fixed" — the H-D1 lesson.
      expect(src, contains('class CycleService'));
      expect(src, contains("from('cycle_logs')"));
    });

    test('a signed-out write refuses instead of silently no-opping', () {
      expect(src, contains('String _requireUid()'),
          reason: 'the _requireUid guard is gone — a signed-out cycle write '
              'would silently no-op again while the sheet closes as though it '
              'saved. These are period and symptom records.');
      expect(src, contains("throw StateError("),
          reason: '_requireUid no longer throws, so callers cannot tell that '
              'nothing was persisted');
      expect(RegExp(r'if\s*\(\s*uid\s*==\s*null\s*\)\s*return\s*;').hasMatch(src), isFalse,
          reason: 'a silent-return arm is back in CycleService');
    });

    test('ending a period reports whether there was one to end', () {
      expect(src, contains('Future<bool> endCurrentPeriod('),
          reason: 'endCurrentPeriod no longer reports its outcome');
    });
  });

  // ── 2. Unit preference: FIXED — now a fix ratchet ────────────────────────
  //
  // CORR-2 was the last of the three still open. It was `Future<void>` with a
  // bare `catch (_) {}` and `if (uid == null) return;`, called unawaited after
  // an optimistic setState, so the toggle moved and nothing persisted.
  group('CORR-2 · settings unit preference — fixed, now protected', () {
    late String src;
    setUpAll(() => src = code('lib/features/settings/presentation/settings_screen.dart'));

    test('the guard is reading the right file', () {
      expect(src, contains('_persistUnit('));
      expect(src, contains("'unit_preference'"));
    });

    test('_persistUnit reports whether the preference was stored', () {
      expect(src, contains('Future<bool> _persistUnit('),
          reason: '_persistUnit no longer reports its outcome, so the caller '
              'cannot tell that the preference was not stored');
      final i = src.indexOf('Future<bool> _persistUnit(');
      final body = src.substring(i, src.indexOf('\n  }', i));
      expect(RegExp(r'catch\s*\(_\)\s*\{\s*\}').hasMatch(body), isFalse,
          reason: 'the fully silent catch is back');
      expect(body, contains('return false;'),
          reason: 'failure is no longer reported to the caller');
    });

    test('a failed save reverts the optimistic toggle and says so', () {
      // Returning bool is worthless if the caller discards it, and an
      // un-reverted toggle shows a preference that was never stored.
      final i = src.indexOf('final ok = await _persistUnit(');
      expect(i, greaterThan(0),
          reason: 'the call site no longer awaits _persistUnit');
      final around = src.substring(i, i + 420);
      expect(around, contains('if (!ok'),
          reason: 'the result is discarded again');
      expect(around, contains('_selectedUnit = previous'),
          reason: 'the optimistic toggle is no longer reverted on failure');
      expect(around, contains('ScaffoldMessenger'),
          reason: 'nothing tells the member the preference was not saved');
    });
  });

  // ── 3. The pattern that makes a field un-clearable ───────────────────────
  group('CORR-3 · guarded writes cannot clear a value', () {
    // CLOSED BY CLOUD (QAX-COR-01, fdbd67b). The payload builder was extracted
    // and the five fields this audit validated as genuinely clearable —
    // gender, phone, height, weight, goal weight — are now written
    // unconditionally, so clearing them in the UI clears the stored value.
    // Inverted into a fix ratchet rather than deleted.
    test('the five clearable fields are written unconditionally', () {
      final src = code('lib/features/profile/presentation/personal_info_screen.dart');
      expect(src, contains('buildPersonalInfoPayload('),
          reason: 'the extracted payload builder is gone');

      // `gender` is the decisive one: the UI has a deliberate deselect gesture,
      // so a conditional write silently discards an explicit clear.
      expect(src, contains("'gender':     gender,"),
          reason: 'gender is conditionally written again — the UI deselect '
              'gesture would be silently discarded');
      expect(src, contains('orNull(phone)'),
          reason: 'phone no longer clears to null when emptied');
      expect(RegExp(r"if \(_gender != null\) payload\['gender'\]").hasMatch(src), isFalse,
          reason: 'the conditional gender write is back');
    });

    test('the correct pattern still exists, so the deviation is provable', () {
      // Without this, "everything omits empty values" would look like a house
      // style rather than a defect.
      final src = read('lib/features/checkins/data/weekly_checkin_service.dart');
      expect(src, contains("'notes': notes ?? ''"),
          reason: 'the one surface that CLEARS correctly has changed; CORR-G1 '
              'loses its baseline for calling the others defective');
    });
  });
}
