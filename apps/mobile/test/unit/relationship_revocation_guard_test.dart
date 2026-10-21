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
/// ── STATUS CORRECTION, 2026-10-20 ──────────────────────────────────────────
/// Both policies HAVE since been corrected in code: migration 136 replaced them
/// to delegate to `is_active_coach_of`, and 137 re-created the progress-photos
/// one after the overload disambiguation. `known` below could not detect that
/// and can never retire itself, because the sweep requires
/// `coach_client_relationships` in the policy body while the corrected versions
/// name only the HELPER — so 136/137 are never considered, and the historical
/// unguarded CREATEs in 029/035 keep satisfying the allowlist. The promise
/// below that this guard "fails loudly when either known one is corrected" is
/// therefore unfulfillable as written.
///
/// `known` is NOT emptied here: shrinking it is described as the last step of a
/// fix, and whether these findings may be retired is an owner call, not a test
/// edit. REVOKE-G3 at the end of this file is added instead, asserting the
/// LANDED fix positively so a regression is caught. It asserts CODE STATE ONLY
/// — SEC-PHI-9 / SEC-PHI-10 and QAX-SEC-02 remain formally OPEN.
///
/// ── WHAT THIS GUARD RATCHETS ───────────────────────────────────────────────
/// Not "these two policies are fixed" — they were not when this was written;
/// remediation is migration-governed and the proposal is
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

  // ── REVOKE-G3 · the landed active-relationship fix must not regress ───────
  //
  // REVOKE-G1 above is a DRIFT detector: it flags a policy that joins
  // `coach_client_relationships` with no status predicate. It is intact and
  // still valuable, but it has two blind spots that matter now 136/137 landed:
  //
  //   * it pre-filters on `coach_client_relationships` in the body, so a policy
  //     rewritten to delegate to `is_active_coach_of` leaves its view entirely;
  //   * it keys offenders by policy NAME over an unordered directory walk, so
  //     it has no notion of which definition WINS.
  //
  // Consequence: if a future migration re-created either policy WITHOUT the
  // predicate and without naming the relationships table, or dropped it
  // outright, REVOKE-G1 would not notice — a drop leaves no offender at all.
  //
  // REVOKE-G3 closes that by reading the WINNING definition and requiring an
  // active-relationship predicate. Same "read the last definition" rule as
  // admin_view_authorization_guard_test.dart.
  //
  // ── WHAT THIS DOES **NOT** COVER, stated so it is not mistaken for more ───
  //   * It reads migration SOURCE. It is NOT runtime verification: nothing here
  //     executes SQL or observes a denial. The live probe for this boundary is
  //     `supabase/tests/security/d10-p1-profile-and-status-boundaries.mjs`
  //     (section SEC-PHI-9), which this guard does not replace.
  //   * A later migration that only DROPS the policy and never re-creates it is
  //     NOT flagged: `named.last` stays at the earlier CREATE and the assertion
  //     passes. For a SELECT policy a drop is fail-closed — the read stops
  //     working rather than widening — so it is a safe gap, but it is a gap.
  //   * It asserts CODE STATE. It does not and cannot close SEC-PHI-9 /
  //     SEC-PHI-10 / QAX-SEC-02, which remain formally OPEN.
  group('REVOKE-G3 the landed active-relationship fix', () {
    /// The winning definition, plus every file whose text NAMES this policy.
    ///
    /// `named` exists because the body pattern is BOUNDED at 1400 characters,
    /// inherited from REVOKE-G1. A later definition longer than that does not
    /// match, and without this the extractor would silently fall back to an
    /// EARLIER definition and the assertions below would pass while the real
    /// winning policy is unguarded. That false pass was demonstrated with a
    /// 2,779-character unguarded re-creation before this was added, so the
    /// mismatch is reported rather than absorbed.
    ({({String file, String body})? won, List<String> named}) resolve(
        String policyName, [Directory? override]) {
      final dir = override ?? Directory('../../supabase/migrations');
      if (!dir.existsSync()) return (won: null, named: const []);
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      // The name is INTERPOLATED straight into the pattern below, so a name
      // containing a regex metacharacter would silently change what is matched.
      // Asserted rather than trusted. `.` is deliberately excluded from the
      // allowed set: it is the metacharacter most likely to appear in a name.
      expect(RegExp(r'^[A-Za-z0-9 :_-]+$').hasMatch(policyName), isTrue,
          reason: 'policy name "$policyName" contains a character that would '
              'change the meaning of the interpolated pattern. Escape it, or '
              'widen this allow-list deliberately.');

      final re = RegExp(
          'CREATE\\s+POLICY\\s+"$policyName"\\s+ON\\s+[a-z_.]+(.{0,1400}?);\\s*\\n',
          dotAll: true, caseSensitive: false);
      final nameOnly =
          RegExp('CREATE\\s+POLICY\\s+"$policyName"', caseSensitive: false);

      ({String file, String body})? found;
      final named = <String>[];
      for (final f in files) {
        // Comment-stripped, for the same reason REVOKE-G1 strips: a rollback
        // note showing the OLD policy is not the policy.
        final src = f.readAsStringSync().split('\n').map((l) {
          final i = l.indexOf('--');
          return i < 0 ? l : l.substring(0, i);
        }).join('\n');
        final name = f.uri.pathSegments.last;
        if (nameOnly.hasMatch(src)) named.add(name);
        for (final m in re.allMatches(src)) {
          found = (file: name, body: m.group(1)!);
        }
      }
      return (won: found, named: named);
    }

    ({String file, String body})? winning(String policyName) =>
        resolve(policyName).won;

    /// An active-relationship requirement, however it is spelled.
    bool requiresActive(String body) =>
        body.contains('is_active_coach_of') ||
        RegExp(r"status\s*(=|in)\s*\(?\s*'active'", caseSensitive: false)
            .hasMatch(body);

    test('the extractor is not vacuous and prefers the LAST definition', () {
      final d = winning('coach reads client progress photos');
      expect(d, isNotNull,
          reason: 'no CREATE POLICY "coach reads client progress photos" found '
              'anywhere. Either it was renamed or dropped — in both cases this '
              'guard is now lying and must be updated deliberately.');
      expect(d!.file, isNot('029_progress_photos_storage_rls.sql'),
          reason: 'the winning definition is still 029, the PRE-FIX one. Either '
              'migrations 136/137 were reverted, or this extractor is picking '
              'the first definition instead of the last.');

      // Negative control: without this the assertions below prove nothing.
      expect(
          requiresActive('USING (EXISTS (SELECT 1 FROM coach_client_relationships r '
              'WHERE r.coach_id = auth.uid()))'),
          isFalse,
          reason: 'requiresActive() accepts a body with no status predicate — '
              'the checks below are inert');
      expect(requiresActive('USING (public.is_active_coach_of(x))'), isTrue,
          reason: 'requiresActive() rejects the real fix shape');
    });

    // ── the detector proved in DART, on a synthetic corpus ────────────────
    //
    // These assert the extractor's BEHAVIOUR, not the repository's state, so a
    // fail-before case is demonstrated in the same language as the guard rather
    // than in a separate reimplementation.
    group('the extractor itself', () {
      late Directory tmp;
      const policy = 'coach reads client progress photos';
      const guardedDef = 'CREATE POLICY "coach reads client progress photos"\n'
          '  ON storage.objects FOR SELECT TO authenticated\n'
          "  USING (bucket_id = 'progress-photos'\n"
          '    AND public.is_active_coach_of((storage.foldername(name))[1]));\n';

      setUp(() => tmp = Directory.systemTemp.createTempSync('revokeg3-'));
      tearDown(() => tmp.deleteSync(recursive: true));

      void write(String name, String body) =>
          File('${tmp.path}/$name')..writeAsStringSync(body);

      test('a LATER unguarded re-creation is detected', () {
        write('100_ok.sql', guardedDef);
        write('190_regression.sql',
            'CREATE POLICY "coach reads client progress photos"\n'
            '  ON storage.objects FOR SELECT TO authenticated\n'
            "  USING (bucket_id = 'progress-photos');\n");
        final r = resolve(policy, tmp);
        expect(r.won!.file, '190_regression.sql', reason: 'last definition must win');
        expect(requiresActive(r.won!.body), isFalse,
            reason: 'the unguarded re-creation must NOT satisfy the predicate');
      });

      test('an OVER-LONG later definition is reported, not silently skipped', () {
        // The false pass this detector exists to close: before `named` was
        // tracked, the bounded pattern missed this file and the extractor fell
        // back to 100_ok, so the guard passed on superseded SQL.
        write('100_ok.sql', guardedDef);
        final pad = List.generate(
            40, (i) => '      /* padding $i to exceed the bounded pattern */').join('\n');
        write('191_long.sql',
            'CREATE POLICY "coach reads client progress photos"\n'
            '  ON storage.objects FOR SELECT TO authenticated\n'
            '  USING (\n'
            "    bucket_id = 'progress-photos'\n$pad\n"
            '  );\n');
        final r = resolve(policy, tmp);
        expect(r.named.last, '191_long.sql',
            reason: 'the over-long file must still be seen as NAMING the policy');
        expect(r.won!.file, '100_ok.sql',
            reason: 'premise: the bounded pattern cannot parse the long one');
        expect(r.won!.file == r.named.last, isFalse,
            reason: 'so winning != lastNamed, which is what the per-policy test '
                'now fails on instead of judging superseded SQL');
      });

      test('the policy-name guard FIRES on a metacharacter — it is not decorative',
          () {
        // Without this the allow-list above is unfalsifiable: it passes for
        // every name actually used, so nothing shows it would reject a bad one.
        write('100_ok.sql', guardedDef);
        expect(() => resolve('coach reads (any) client', tmp),
            throwsA(isA<TestFailure>()),
            reason: 'a name containing regex metacharacters must be refused, '
                'not interpolated into the pattern');
        // And a legitimate name with the punctuation real policies DO use passes.
        expect(() => resolve("Coach: read an ACTIVE client_photo-set", tmp),
            returnsNormally);
      });

      test('a commented-out definition does not win', () {
        write('100_ok.sql', guardedDef);
        write('192_comment.sql',
            '-- CREATE POLICY "coach reads client progress photos"\n'
            "--   ON storage.objects FOR SELECT USING (bucket_id = 'progress-photos');\n");
        final r = resolve(policy, tmp);
        expect(r.named, isNot(contains('192_comment.sql')),
            reason: 'a commented definition must not even register as naming it');
        expect(r.won!.file, '100_ok.sql');
      });

      test('an unrelated policy on the same table is not confused for it', () {
        write('100_ok.sql', guardedDef);
        write('193_other.sql',
            'CREATE POLICY "owner reads own progress photos"\n'
            "  ON storage.objects FOR SELECT USING (owner = auth.uid());\n");
        final r = resolve(policy, tmp);
        expect(r.named, isNot(contains('193_other.sql')));
        expect(r.won!.file, '100_ok.sql');
      });
    });

    for (final policy in const [
      'coach reads client progress photos',
      'coach reads client events',
    ]) {
      test('"$policy" still requires an ACTIVE relationship', () {
        final r = resolve(policy);
        final d = r.won;
        expect(d, isNotNull, reason: '"$policy" has no definition anywhere');

        // Every file that NAMES the policy must also have been parsed. If one
        // names it but the bounded body pattern did not match there, the
        // extractor fell back to an older definition and the assertion below
        // would be judging superseded SQL.
        expect(r.named, contains(d!.file),
            reason: 'internal: the winning file is not in the named set');
        final lastNamed = r.named.last;
        expect(d.file, lastNamed,
            reason: 'the LAST file naming "$policy" is $lastNamed, but the '
                'extractor could only parse as far as ${d.file}. The bounded '
                '1400-character body pattern did not match in $lastNamed — most '
                'likely the definition there is longer. This guard will not '
                'judge a superseded definition: widen the bound deliberately, '
                'in the same change that reviews $lastNamed.');
        expect(requiresActive(d.body), isTrue,
            reason: '"$policy" won by ${d.file} and no longer requires an '
                'ACTIVE relationship. A `pending` coach — one the client merely '
                'requested and may never accept — and every CANCELLED former '
                'coach regain access. For progress-photos that data is body '
                'photographs. Restore public.is_active_coach_of(...), and mind '
                'the cast hazard in migration 130: a raising ::uuid cast inside '
                'an RLS predicate aborts every read of the bucket for everyone.');
      });
    }
  });

}
