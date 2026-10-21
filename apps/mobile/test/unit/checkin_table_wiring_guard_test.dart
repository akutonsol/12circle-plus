import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CHK-G1 — the check-in screen must write to a table that exists.
///
/// ── THE FACT THIS GUARDS, VERIFIED LIVE ────────────────────────────────────
/// `public.checkins` **does not exist**. Probed against the QA database
/// (`tool/anon_least_privilege.py`), it answers PostgREST `PGRST205` — not in
/// the schema cache — which is exactly what a deliberately nonsense table name
/// answers. `weekly_checkins` and `user_profiles` answer `42501` (permission
/// denied), which is what an existing relation answers.
///
/// `CheckinService` writes to `checkins`. So **every weekly check-in this
/// screen took was lost**, and the two reads beside it reported "you have not
/// checked in" and a `0` streak about a feature that could not work at all.
///
/// `WeeklyCheckinService` writes to `weekly_checkins`, which exists and whose
/// columns are all present — `stress_level`, `sleep_hours` and `notes` were
/// added by migration `001`, and `weekly_checkins_user_week_unique
/// (user_id, week_start_date)` matches the service's
/// `onConflict: 'user_id,week_start_date'`.
///
/// ── WHY THIS IS A SOURCE GUARD ─────────────────────────────────────────────
/// Both services hold `Supabase.instance.client` as a field, so neither can be
/// substituted and the screen cannot be pumped. This proves the WIRING — which
/// table the screen reaches — and nothing about the round trip. The round trip
/// needs an authenticated QA session (OD-51).
void main() {
  late String screen;

  setUpAll(() {
    screen = File('lib/features/checkins/presentation/daily_checkin_screen.dart')
        .readAsStringSync()
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i < 0 ? l : l.substring(0, i);
        })
        .join('\n');
  });

  test('CHK-G1 the guard is reading the right screen', () {
    // An absent result must not read as "no defect" — the H-D1 lesson.
    expect(screen, contains('_submit()'));
    expect(screen, contains('class _WeeklyCheckinState'));
  });

  test('CHK-G1 the submission does not go to the absent table', () {
    expect(screen, contains('_weekly.submitWeeklyCheckin('),
        reason: 'the weekly check-in must be written to `weekly_checkins`');
    expect(screen.contains('_service.saveWeeklyCheckin('), isFalse,
        reason: 'this writes to `public.checkins`, which does not exist — '
            'every submission is silently lost');
  });

  test('CHK-G1 the already-checked-in gate does not read the absent table', () {
    expect(screen, contains('_weekly.weekStatus()'));
    expect(screen.contains('_service.hasCheckedInThisWeek()'), isFalse,
        reason: 'this reads `public.checkins`; with the table absent it always '
            'failed, and before CON-01 that failure read as "not done" and '
            'opened the form');
  });

  test('CHK-G1 the honest week status has no swallowing arm', () {
    final svc = File('lib/features/checkins/data/weekly_checkin_service.dart')
        .readAsStringSync();
    final start = svc.indexOf('Future<CheckinKnown> weekStatus() async {');
    expect(start, greaterThan(0), reason: 'weekStatus has gone');
    final body = svc.substring(start, svc.indexOf('Future<bool> submitWeeklyCheckin', start));

    expect(body, contains('return CheckinKnown.unknown;'),
        reason: 'a failed read must not answer "not done" — that is what '
            '`getCurrentWeekCheckin()` does, returning a pending row from its '
            '`catch (_) {}`');
    // And a real "no row" is still a real answer.
    expect(body, contains('if (data == null) return CheckinKnown.notDone;'));
  });
}
