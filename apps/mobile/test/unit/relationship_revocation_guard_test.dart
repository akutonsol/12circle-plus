import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// REVOKE-G1 — SEC-PHI-9 / SEC-PHI-10.
///
/// Every policy that authorises a coach against a client must require the
/// relationship to be **active**. Two do not, and they are the only two.
///
/// ── WHY THIS IS NOT THEORETICAL ────────────────────────────────────────────
/// Verified live on QA. A throwaway object was uploaded by the owner, probed,
/// and removed (net state change: none):
///
///   owner    signs it -> 200 SIGNED
///   attacker signs it -> 400 not_found      (denied)
///   COACH    signs it -> 200 SIGNED         <-- the finding
///   admin    signs it -> 400 not_found      (denied)
///
/// That coach's relationship with that client has status **`cancelled`**. The
/// same identity is correctly denied the client's profile, PAR-Q, check-ins,
/// weight logs, body measurements and AI memories. Revocation works
/// everywhere except these policies — and the data here is **body
/// photographs**.
///
/// The missing predicate also admits a **pending** coach: someone the client
/// merely requested, who has not accepted and may never accept.
///
/// ── WHAT THIS GUARD RATCHETS ───────────────────────────────────────────────
/// Not "these two policies are fixed" — they are not; remediation is
/// migration-governed and the proposal is
/// `docs/proposed/SEC_PHI_9_progress_photo_revocation.sql`. It ratchets that
/// **no THIRD one appears**, and it fails loudly when either known one is
/// corrected so the allowlist cannot outlive the defect.
void main() {
  /// Policies that join `coach_client_relationships` with no status predicate.
  /// This list may only shrink. Shrinking it is the last step of the fix.
  const known = <String>{
    'coach reads client progress photos', // 029, storage.objects — VERIFIED live
    'coach reads client events', // 035, score_events — source only
  };

  late Map<String, String> offenders; // policy name -> migration file

  setUpAll(() {
    offenders = {};
    final dir = Directory('../../supabase/migrations');
    expect(dir.existsSync(), isTrue,
        reason: 'migrations directory has moved; this guard must be repointed '
            'in the same change rather than left checking nothing');

    final policy = RegExp(
        r'CREATE\s+POLICY\s+"([^"]+)"\s+ON\s+([a-z_.]+)(.{0,1400}?);\s*\n',
        dotAll: true, caseSensitive: false);

    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.sql')) continue;
      // Strip line comments: a rollback note showing the OLD policy is not the
      // policy. Commented SQL has been mistaken for active SQL in this
      // programme before.
      final src = f.readAsStringSync().split('\n').map((l) {
        final i = l.indexOf('--');
        return i < 0 ? l : l.substring(0, i);
      }).join('\n');

      for (final m in policy.allMatches(src)) {
        final body = m.group(3)!;
        if (!body.contains('coach_client_relationships')) continue;
        // The helper enforces status = 'active' internally.
        if (body.contains('is_active_coach_of')) continue;
        if (RegExp(r"""status\s*(=|in)\s*\(?\s*'""", caseSensitive: false)
            .hasMatch(body)) {
          continue;
        }
        offenders[m.group(1)!] = f.uri.pathSegments.last;
      }
    }
  });

  test('REVOKE-G1 the sweep actually parsed the migrations', () {
    // An empty result must not read as "no offenders" — the H-D1 lesson, and
    // the exact error that produced the retracted SEC-DRIFT-1.
    final dir = Directory('../../supabase/migrations');
    final n = dir.listSync().where((e) => e.path.endsWith('.sql')).length;
    expect(n, greaterThan(100),
        reason: 'found almost no migrations; every assertion below is vacuous');
    // And the detector must be able to SEE the known offenders.
    for (final k in known) {
      expect(offenders.keys, contains(k),
          reason: '"$k" is no longer detected. If it was FIXED, delete it from '
              '`known` in the same change. If the detector broke, this guard '
              'is protecting nothing.');
    }
  });

  test('REVOKE-G1 no NEW policy authorises a coach without checking status',
      () {
    final novel = offenders.keys.where((k) => !known.contains(k)).toList()
      ..sort();

    expect(
      novel,
      isEmpty,
      reason: 'A policy authorises a coach against a client without requiring '
          'the relationship to be active:\n  '
          '${novel.map((k) => '"$k"  (${offenders[k]})').join('\n  ')}\n\n'
          'It tests only that a relationship ROW EXISTS, so `pending`, '
          '`declined` and `cancelled` all satisfy it — a former coach keeps '
          'access forever, because the row is never deleted, only set to '
          '`cancelled`.\n\n'
          'Use `public.is_active_coach_of(<uuid>)`, which is used 30 times '
          'across the table policies and requires status = \'active\'. If the '
          'subject is a storage path segment, mind the cast hazard documented '
          'in migration 130 — a raising cast aborts every read of the bucket '
          'for every user.',
    );
  });

  test('REVOKE-G1 the helper still enforces status, so callers inherit it', () {
    // 30 policies delegate to this. If its predicate is ever relaxed, every
    // one of them silently widens and this guard would still pass.
    final f = File('../../supabase/migrations/100_rls_harden_client_data.sql');
    expect(f.existsSync(), isTrue, reason: 'migration 100 has moved');
    final src = f.readAsStringSync();
    final i = src.indexOf('FUNCTION public.is_active_coach_of');
    expect(i, greaterThan(0), reason: 'is_active_coach_of has moved');
    final body = src.substring(i, src.indexOf(r'$$;', i));

    expect(body, contains("r.status = 'active'"),
        reason: 'is_active_coach_of no longer requires an ACTIVE relationship. '
            'Every policy that delegates to it has just widened to include '
            'cancelled and pending coaches.');
    expect(body, contains('r.coach_id = auth.uid()'),
        reason: 'the helper no longer scopes to the calling coach');
  });
}
