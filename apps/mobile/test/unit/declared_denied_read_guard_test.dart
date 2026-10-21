import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SEC-G3 — a read the database has already denied must not come back.
///
/// ── THE DEFECT ─────────────────────────────────────────────────────────────
/// `workout_logs` carries exactly one policy, `003_fk_and_rls_fixes.sql:193`:
///
///   CREATE POLICY "users manage own workout logs" ON workout_logs
///     FOR ALL TO authenticated USING (user_id = auth.uid())
///
/// No coach clause exists in any of the 131 migrations. And an RLS-filtered
/// SELECT is **not an error** — PostgREST answers `200` with `[]` — so three
/// coach surfaces did not fail. They reported a confident, permanent zero:
/// every client had trained never, and no `AsyncError` arm could catch it.
///
/// ── AND THE FIX, WHICH NEEDED NO POLICY CHANGE ─────────────────────────────
/// All three now read `workout_sessions`, which a coach **is** authorized to
/// read (`100_rls_harden_client_data.sql`, `user_id = auth.uid() OR
/// public.is_active_coach_of(user_id)` FOR SELECT). Both tables are written on
/// the same completion — `active_workout_screen.dart:649` and `:653` — so
/// nothing was lost.
///
/// This was never OD-14. F-21 is a policy that *claims a role it never
/// verifies*; this was a table with **no coach policy at all**, whose
/// authorized route already existed on another table.
///
/// ── WHAT THIS GUARD DOES NOW ───────────────────────────────────────────────
/// The allowlist is empty, which changes what the guard can assert. It can no
/// longer prove its detector works by finding real offenders, because there
/// are none — so an empty result would be indistinguishable from a broken
/// scanner, which is the H-D1 defect exactly.
///
/// It therefore proves the detector against **synthetic source**: a positive
/// control it must flag, and a negative control it must not.
void main() {
  /// A read is cross-user when it filters `user_id` by anything other than the
  /// caller's own id. `insights_provider.dart` uses `.eq('user_id', uid)` where
  /// `uid` is the signed-in user — a self-read, permitted, and correctly not
  /// flagged.
  Set<String> crossUserReadsIn(Map<String, String> sources) {
    final out = <String>{};
    sources.forEach((name, src) {
      for (final m in RegExp(r"\.from\('workout_logs'\)").allMatches(src)) {
        final window =
            src.substring(m.start, (m.start + 320).clamp(0, src.length));
        final selfRead =
            RegExp(r"\.eq\('user_id',\s*uid\s*\)").hasMatch(window);
        final otherRead = RegExp(
                r"\.inFilter\('user_id'|\.eq\('user_id',\s*(?!uid\s*\))")
            .hasMatch(window);
        if (!selfRead && otherRead) out.add(name);
      }
    });
    return out;
  }

  Map<String, String> repoSources() {
    final out = <String, String>{};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      out[f.path] = f.readAsStringSync();
    }
    return out;
  }

  // ── The detector must work, with nothing real left to find ───────────────
  group('SEC-G3 the detector still works', () {
    const cohort = '''
      final data = await _db
          .from('workout_logs')
          .select('user_id, completed_at')
          .inFilter('user_id', clientIds);
    ''';
    const oneOther = '''
      final data = await db
          .from('workout_logs')
          .select()
          .eq('user_id', clientId)
          .limit(20);
    ''';
    const selfRead = '''
      final workouts = await db
          .from('workout_logs')
          .select('id')
          .eq('user_id', uid);
    ''';
    const otherTable = '''
      final data = await _db
          .from('workout_sessions')
          .select('user_id, completed_at')
          .inFilter('user_id', clientIds)
          .eq('status', 'completed');
    ''';

    test('it flags a cohort read', () {
      expect(crossUserReadsIn({'x.dart': cohort}), {'x.dart'});
    });

    test('it flags a read for one OTHER user', () {
      expect(crossUserReadsIn({'x.dart': oneOther}), {'x.dart'});
    });

    // Both halves matter. A detector that flags everything would be as
    // useless as one that flags nothing, and would have hidden the three real
    // sites inside a wall of noise.
    test('it does NOT flag the caller reading their own logs', () {
      expect(crossUserReadsIn({'x.dart': selfRead}), isEmpty);
    });

    test('it does NOT flag the authorized table', () {
      expect(crossUserReadsIn({'x.dart': otherTable}), isEmpty);
    });
  });

  test('SEC-G3 no code path reads workout_logs for another user', () {
    final found = crossUserReadsIn(repoSources());
    expect(
      found,
      isEmpty,
      reason: 'A call site reads `workout_logs` for another user. RLS denies '
          'it and PostgREST answers 200 + [], so this will not fail — it will '
          'report a confident zero for every client, forever.\n'
          'Read `workout_sessions` instead (100_rls_harden_client_data.sql '
          'permits `is_active_coach_of`), or call the SECURITY DEFINER RPC '
          '`coach_client_ai_signals()`.\nFound: ${found.join(', ')}',
    );
  });

  // ── The three repointed sites must stay repointed ────────────────────────
  group('SEC-G3 the fix holds', () {
    const repointed = <String, String>{
      'lib/features/dashboard/presentation/coach_dashboard_screen.dart':
          'clientWorkoutLogsProvider',
      'lib/features/compliance/data/compliance_service.dart': 'workouts',
      'lib/features/coach/domain/coach_ecosystem_provider.dart': 'workoutLogs',
    };

    test('each reads workout_sessions, completed only', () {
      repointed.forEach((path, anchor) {
        final src = File(path).readAsStringSync();
        expect(src, contains(anchor),
            reason: '$path no longer contains `$anchor` — the anchor moved and '
                'the assertions below would pass vacuously');
        expect(src, contains("from('workout_sessions')"),
            reason: '$path must read the table a coach is authorized to read');
        expect(src, contains("eq('status', 'completed')"),
            reason: '$path must exclude in_progress and abandoned sessions — '
                'their completed_at is null, and an unfinished workout is not '
                'an adherence event');
      });
    });

    test('none of them selects every column', () {
      // `workout_sessions` has gained five columns since 001. A bare
      // `select()` would pull each new one into a coach surface as it lands,
      // with nobody deciding.
      repointed.forEach((path, _) {
        final src = File(path).readAsStringSync();
        final i = src.indexOf("from('workout_sessions')");
        expect(i, greaterThan(-1));
        final window = src.substring(i, (i + 200).clamp(0, src.length));
        expect(window.contains('.select()'), isFalse,
            reason: '$path selects every column of workout_sessions');
        expect(window, contains(".select('"),
            reason: '$path must name the columns it reads');
      });
    });
  });

  test('SEC-G3 the authorized alternative still exists', () {
    final harden =
        File('../../supabase/migrations/100_rls_harden_client_data.sql');
    expect(harden.existsSync(), isTrue);
    final src = harden.readAsStringSync();
    expect(src, contains('workout_sessions'));
    expect(src, contains('is_active_coach_of'));
    // The helper binds coach_id to auth.uid() and requires an ACTIVE row —
    // unlike F-21's shape, the caller cannot forge what satisfies it, because
    // 113:223 revokes `authenticated` from the relationship table outright.
    expect(src, contains('r.coach_id = auth.uid()'));
    expect(src, contains("r.status = 'active'"));

    final rel = File(
        '../../supabase/migrations/113_rls_coach_client_relationships.sql');
    expect(rel.readAsStringSync(),
        contains('REVOKE ALL ON public.coach_client_relationships FROM authenticated'),
        reason: 'if `authenticated` regains write access to this table, '
            '`is_active_coach_of` becomes forgeable and every policy built on '
            'it — including the one this fix depends on — weakens');
  });

  test('SEC-G3 workout_logs still has no coach-read policy', () {
    // The finding is NOT resolved. Its symptom is: nothing reads the table
    // cross-user any more. The condition stands — the table has no coach
    // policy — and a fourth reader would reintroduce the defect, which is
    // what the guard above now prevents. Closing it entirely would be a false
    // closure.
    final dir = Directory('../../supabase/migrations');
    if (!dir.existsSync()) {
      fail('Could not read supabase/migrations — SEC-G3 asserted nothing.');
    }
    final policies = <String>[];
    for (final f in dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))) {
      for (final m in RegExp(
              r'CREATE POLICY\s+"([^"]+)"\s+ON\s+(?:public\.)?workout_logs\b(.*?);',
              dotAll: true,
              caseSensitive: false)
          .allMatches(f.readAsStringSync())) {
        policies.add(m.group(2)!);
      }
    }
    expect(policies, isNotEmpty,
        reason: 'no workout_logs policy found at all — the detector is broken, '
            'or the table lost its RLS entirely, which is far worse');
    expect(
      policies.any((p) => RegExp(r'is_active_coach_of|coach_id').hasMatch(p)),
      isFalse,
      reason: 'a coach-read policy now exists on workout_logs. The reads this '
          'guard forbids may have become legitimate — re-evaluate SEC-G3 and '
          'docs/QA_EVIDENCE.md §3ah together.',
    );
  });
}
