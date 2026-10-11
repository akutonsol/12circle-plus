import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SEC-W1 — the Security Foundation Wave 1 fix ratchet.
///
/// Wave 1 closed the QAX-SEC-08 (P0) forgery and the team arm of F-03b (P1) by
/// `132_team_membership_lifecycle.sql`, under owner decisions D1(i)/(ii)/(iii)
/// recorded in `docs/adr/ADR-W1-001-team-membership-lifecycle.md`.
///
/// ── WHY THIS FILE EXISTS RATHER THAN A LOWERED SEC-G1 BASELINE ─────────────
/// SEC-G1 and CHAIN-G1's chain-set detector read `supabase/migrations/*.sql` as
/// text and do **not** resolve supersession — a policy dropped by a later
/// migration still matches the `CREATE POLICY` in the earlier one. So neither
/// can observe this fix, and lowering SEC-G1's baseline to 14 would make it fail
/// against text that is still present in `002_ecosystem_additions.sql`.
/// Deriving those populations from the live catalog instead is recorded as
/// owner/architecture decision **D15** and is out of Wave 1 scope.
///
/// This guard therefore asserts the *corrected* definitions in 132 directly. It
/// is a fix ratchet: it fails if any part of Wave 1 is reverted.
///
/// ── WHAT WAVE 1 DID NOT DO — do not read a pass here as more than it is ────
///   * `may_notify()` still trusts `coach_client_relationships` at ANY status.
///     That is **F-03b's second half** and is outside Wave 1 (decision D3), so
///     F-03b must stay OPEN.
///   * `hosts_event_for(id)` still grants an event host the whole
///     `user_profiles` row. That is **QAX-SEC-09** and is a separate path, so
///     "the P0 is closed" does **not** mean profile PHI is safe.
///   * `coach_team_invites` is still `FOR ALL` with no `WITH CHECK`. Wave 2.
/// Migration source with SQL line comments stripped.
///
/// Migration 132's own header quotes the defective policy and the rejected
/// `security_invoker = on` form in prose. Asserting against the raw text would
/// read that prose as DDL — the commented-code-as-active-code trap this
/// programme has hit seven times. Every assertion below runs on stripped code.
String stripComments(String src) => src
    .split('\n')
    .map((l) {
      final i = l.indexOf('--');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');


// ── D-3 · THE AUTHORITATIVE DEFINITION, NOT A PINNED ONE ────────────────────
//
// OWNER DECISION 2026-10-11 · `D-3` = Option A. Finding B (§9.3) was that this guard pins
// migration **132**'s text for `is_team_lead_of()` and `may_notify()`, while migration
// **134** `CREATE OR REPLACE`s both — and because migrations apply in filename order, 134
// is the authoritative definition at HEAD. The guard did not read 134 at all, so **a future
// migration could weaken either helper while leaving 132 byte-identical and this guard would
// still pass.**
//
// WHY OPTION A AND NOT "ALSO READ 134". Pinning 132 and 134 is the same defect one migration
// later: a `135_*` redefinition would be invisible to a two-file pin exactly as it is
// invisible to a one-file pin. These resolvers therefore find the LAST migration that
// defines each helper, whatever its number — and the coverage ratchet below fails when that
// set changes, so a new redefinition cannot land without this guard being updated to see it.
//
// THE 132 ASSERTIONS ABOVE ARE KEPT, and they prove a different thing: that Wave 1's own
// migration still says what it said. These prove that the definition IN FORCE still carries
// the property. Reverting 132 and weakening 134 are two separate regressions.


// ── D-2 · BOTH QUALIFICATION FORMS ──────────────────────────────────────────
//
// OWNER DECISION 2026-10-11 · `D-2` = Option A. Finding A (§9.2) was that the FOR ALL and
// FOR UPDATE detectors require `ON\s+public\.coach_team_members`, while the real historical
// defective policy at `002_ecosystem_additions.sql:146-147` is written **unqualified**
// (`ON coach_team_members`).
//
// THE LIVE RISK IS SHARPER THAN "IT MISSES A HISTORICAL DEFECT". Both detectors are
// ABSENCE assertions — "no FOR ALL policy is back on this table" — so a qualification the
// detector does not recognise is a way to **evade** them. And the unqualified form is not
// exotic: measured repo-wide over `supabase/migrations/*.sql` with comments stripped, using
// `CREATE\s+POLICY[^;]*?\bON\s+(public\.)?([a-z_]+)`, it is **167 unqualified to 95
// qualified — 1.76:1**. A re-introduced policy is MORE likely to be written in the form the
// detector could not see.
//
// (That ratio is not §9.2's recorded ≈3.6:1. §9.2 said its counts were method-sensitive and
// should not be cited without publishing the expression, so the expression is published
// above and the two numbers are not comparable. For `coach_team_members` specifically the
// picture inverts — 7 qualified to 1 unqualified — and that single unqualified instance IS
// the 002 defect.)
//
// WIDENING A DETECTOR CAN BREAK IT, which is why `\b` is not optional: without a word
// boundary, `(?:public\.)?coach_team_members` also matches
// `coach_team_members_archive`, and the guard would start failing on a table it has no
// business judging. The fixtures below require that case NOT to match.

/// `CREATE POLICY … ON [public.]<table> … FOR <command>`, in BOTH qualification forms.
RegExp policyOn(String table, String command) => RegExp(
    'CREATE\\s+POLICY[^;]*ON\\s+(?:public\\.)?$table\\b[^;]*FOR\\s+$command',
    caseSensitive: false, dotAll: true);

/// The tables that POLICY DDL in [code] targets, in both forms.
///
/// SCOPED TO POLICY DDL, and that scoping is the point. A bare `ON\s+([a-z_]+)` over a
/// migration also captures `ON TABLE` from `COMMENT ON TABLE` and `ON DELETE` from a foreign
/// key — measured on 133, a bare scan yields `{D, TABLE, public.coach_team_members}`. The
/// qualified-only form the guard used before was accidentally protected from that; widening
/// it without scoping would have traded a blind spot for a false alarm.
Set<String> policyTargets(String code) => RegExp(
        r'(?:CREATE|DROP)\s+POLICY\b[^;]*?\bON\s+(?:public\.)?([a-z_]+)\b',
        caseSensitive: false, dotAll: true)
    .allMatches(code)
    .map((m) => m.group(1)!)
    .toSet();

typedef MigrationFile = ({String name, String src});

/// Every migration, in filename order — which is apply order.
List<MigrationFile> migrationCorpus() {
  final dir = Directory('../../supabase/migrations');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      (name: f.uri.pathSegments.last, src: stripComments(f.readAsStringSync())),
  ];
}

/// Every migration that redefines [helper], in apply order.
///
/// Comments are stripped first: 135's header discusses `is_team_lead_of` in prose, and
/// reading prose as DDL is the trap this file's own header names.
List<String> definersOf(String helper, List<MigrationFile> corpus) => [
      for (final m in corpus)
        if (RegExp('CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.$helper\\s*\\(',
                caseSensitive: false)
            .hasMatch(m.src))
          m.name,
    ];

/// The body of the LAST definition of [helper] — the one in force at HEAD.
({String file, String body})? authoritativeOf(
    String helper, List<MigrationFile> corpus) {
  ({String file, String body})? found;
  for (final m in corpus) {
    final match = RegExp(
            'CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.$helper\\s*\\(.*?\\\$function\\\$;',
            dotAll: true, caseSensitive: false)
        .allMatches(m.src)
        .lastOrNull;
    if (match != null) found = (file: m.name, body: match.group(0)!);
  }
  return found;
}

// ── the three properties, as PURE functions over a definition body ──────────
//
// Pure so the regression test can feed them a MUTATED 134 and require them to fail. A
// detector that is only ever run against the passing tree has never been shown to detect
// anything — the lesson every negative control in this repository exists for.

/// D1(ii): only an ACTIVE membership satisfies team-lead authorization.
bool teamLeadRequiresActive(String body) =>
    RegExp(r"t\.status\s*=\s*'active'").hasMatch(body);

/// D1(ii): the notify channel's TEAM arm requires an ACTIVE membership. Scoped to the
/// `coach_team_members` EXISTS clause, because `may_notify` has several arms and a
/// whole-body match could be satisfied by a different one.
bool notifyTeamArmRequiresActive(String body) {
  final arm = RegExp(r'coach_team_members\s+t\s+WHERE\s+([^)]*)', dotAll: true)
      .firstMatch(body.replaceAll(RegExp(r'\s+'), ' '));
  if (arm == null) return false;
  return RegExp(r"t\.status\s*=\s*'active'").hasMatch(arm.group(1)!);
}

/// What migration 134 exists for: an unpinned `search_path` on a SECURITY DEFINER function
/// resolves unqualified names through the CALLER's search_path.
bool hasSearchPathPin(String body) =>
    RegExp(r'SET\s+search_path\s*=', caseSensitive: false).hasMatch(body);

// ── D-1 · LAZY READS, SO THE ASSERTIONS ACTUALLY RUN ───────────────────────
//
// OWNER DECISION 2026-10-11 · `D-1` = Option 4, "change SEC-W1's `setUpAll` to lazy reads".
//
// THE PROBLEM THIS SOLVES IS A PROPERTY OF `package:test`, not of the fix. This group used to
// read migration 132 in an eager `setUpAll`, and **a failing `setUpAll` means the group's
// tests are never run** — so deleting 132 produced exactly one failure, named `(setUpAll)`,
// and **zero of the twelve assertions below executed.** A negative control built on that
// reconstruction would have demonstrated nothing about the assertions it exists to exercise.
//
// Reading on first touch instead means each of the twelve fails on its own.
//
// ── THE CAVEAT, PRESERVED BY THE RULING RATHER THAN ENGINEERED AWAY ────────
//
// With a missing file, `readAsStringSync` throws a `PathNotFoundException` — the Dart 3
// `FileSystemException` subtype for a missing path, and the name its `toString()` reports —
// so the failures surface as **I/O errors rather than this guard's curated `reason:`
// strings**. §365 recorded
// that as Option 4's cost, and the authorization was granted "preserving the documented
// I/O-error caveat" — so it is documented here and NOT papered over with a wrapper that
// re-brands the exception. **What a control built on this proves: the assertions execute and
// fail. What it does not prove: that they fail for the stated reason.** That is a weaker rung
// than the mutation-based controls elsewhere in this repository, and it is the rung that was
// authorized.
//
// Addendum A's own `setUpAll` (migration 133) is deliberately untouched: `D-1` names the 132
// read, and a control that deletes 132 does not reach 133.

String? _m132Cache;
String? _m132CodeCache;

/// Migration 132's raw text, read on first touch. Throws per test when absent — see above.
String get m132 => _m132Cache ??=
    File('../../supabase/migrations/132_team_membership_lifecycle.sql')
        .readAsStringSync();

/// Migration 132 with SQL line comments stripped.
String get code => _m132CodeCache ??= stripComments(m132);

void main() {


  test('SEC-W1 the guard is reading the right migration', () {
    // An absent result must not read as "fixed" — the H-D1 lesson.
    expect(code, contains('coach_team_members'));
    expect(code, contains('team_member_profiles'));
  });

  group('SEC-W1 · D1(i) — a lead cannot create a membership', () {
    test('the defective FOR ALL policy is dropped, not supplemented', () {
      expect(code,
          contains('DROP POLICY IF EXISTS "Head coach manages team" ON public.coach_team_members'),
          reason: 'the 002 policy must be DROPPED. Permissive policies OR '
              'together, so leaving it in place preserves the P0 entirely.');
      // D-2: BOTH qualification forms. A FOR ALL policy written `ON coach_team_members`
      // used to slip past this assertion entirely.
      expect(policyOn('coach_team_members', 'ALL').hasMatch(code),
          isFalse,
          reason: 'a FOR ALL policy is back on coach_team_members. FOR ALL with '
              'USING and no WITH CHECK reuses USING as the INSERT check — that '
              'reuse IS the P0.');
    });

    test('the INSERT policy carries a WITH CHECK that is member-originated', () {
      final insert = RegExp(
              r'CREATE POLICY\s+"member originates own membership"(.*?);',
              dotAll: true, caseSensitive: false)
          .firstMatch(code);
      expect(insert, isNotNull, reason: 'the member-originated INSERT policy is gone');
      final body = insert!.group(1)!;
      expect(body.toUpperCase(), contains('WITH CHECK'),
          reason: 'the INSERT policy lost its WITH CHECK — this is the defect');
      expect(body, contains('member_id = auth.uid()'),
          reason: 'D1(i): creation must be member-originated. A lead must not be '
              'able to name a member.');
      expect(body, contains("status = 'invited'"),
          reason: 'D1(ii): a self-originated row must not be born active, or the '
              'lifecycle is decorative and F-03b reopens in reverse.');
      expect(body, contains('coach_id <> member_id'),
          reason: 'self-membership guard removed');
    });

    test('no UPDATE policy grants an ungoverned activation route', () {
      // D-2: both qualification forms.
      expect(
          policyOn('coach_team_members', 'UPDATE').hasMatch(code),
          isFalse,
          reason: 'an UPDATE policy on coach_team_members would let a row be '
              'moved to status = active outside the Wave 2 governed conversion, '
              'defeating D1(i).');
    });
  });

  // ── ADDENDUM A · migration 133 supersedes 132's INSERT policy ──────────────
  //
  // Agent 3's independent verification found that 132's member-originated INSERT
  // was permitted by no clause of D1(i). D1(i)'s second clause is unscoped —
  // "Membership must originate through the invite/consent flow" — and that flow
  // does not exist, so no origination is authorized yet. Migration 133 replaces
  // the policy with an explicit deny.
  //
  // These assertions exist because the group above still reads 132, where the
  // superseded policy text remains. Without them this guard would pin a policy
  // that is no longer in force — the same supersession blindness that prevents
  // SEC-G1's baseline from being lowered (D15).
  group('SEC-W1 · Addendum A — origination is denied until the consent flow exists', () {
    late String code133;

    setUpAll(() {
      final f = File(
          '../../supabase/migrations/133_team_membership_consent_origination.sql');
      expect(f.existsSync(), isTrue,
          reason: 'migration 133 is missing — the D1(i) fidelity remediation has '
              'been reverted, and 132 alone permits member-originated membership '
              'that no clause of D1(i) authorizes');
      code133 = stripComments(f.readAsStringSync());
    });

    test('the 132 INSERT policy is dropped', () {
      expect(code133,
          contains('DROP POLICY IF EXISTS "member originates own membership"'),
          reason: 'the superseded policy must be dropped, not left alongside the '
              'deny — permissive policies OR together');
    });

    test('INSERT is denied to every caller', () {
      final pol = RegExp(
              r'CREATE POLICY\s+"membership originates only through the consent flow"(.*?);',
              dotAll: true, caseSensitive: false)
          .firstMatch(code133);
      expect(pol, isNotNull, reason: 'the explicit deny policy is gone');
      final body = pol!.group(1)!;
      expect(body.toUpperCase(), contains('FOR INSERT'),
          reason: 'the deny must target INSERT');
      expect(RegExp(r'WITH\s+CHECK\s*\(\s*false\s*\)', caseSensitive: false)
              .hasMatch(body),
          isTrue,
          reason: 'D1(i): origination must go through the invite/consent flow. '
              'That flow does not exist, so nothing may originate a membership. '
              'Anything other than WITH CHECK (false) reopens NEW-W1-01, where an '
              'attacker injected an unsolicited row naming an arbitrary lead.');
    });

    test('Addendum A changes nothing else', () {
      // Scope discipline: 133 must touch one policy on one table. Its own
      // COMMENT text names other tables in prose, so this asserts on DDL only.
      final ddlTargets = RegExp(r'ON\s+public\.([a-z_]+)', caseSensitive: false)
          .allMatches(code133)
          .map((m) => m.group(1))
          .toSet();
      expect(ddlTargets, {'coach_team_members'},
          reason: 'migration 133 touched a table outside its authorized scope');
      // D-2: the scan above is qualified-only, and it stays that way on purpose — a bare
      // `ON <word>` over this file captures `TABLE` and `D` as if they were tables. This
      // companion assertion closes the unqualified gap with an instrument scoped to POLICY
      // DDL, which cannot match a COMMENT or a foreign key.
      expect(policyTargets(code133), {'coach_team_members'},
          reason: 'migration 133 has POLICY DDL on a table outside its authorized scope — '
              'in either qualification form');
      for (final forbidden in [
        'DROP COLUMN', 'DROP CONSTRAINT', 'DROP FUNCTION', 'DROP VIEW',
        'TRUNCATE', 'DELETE FROM', 'DISABLE ROW LEVEL SECURITY',
      ]) {
        expect(code133.toUpperCase().contains(forbidden), isFalse,
            reason: '133 must be a single policy replacement; found $forbidden');
      }
    });
  });

  group('SEC-W1 · D1(ii) — the lifecycle is load-bearing', () {
    test('status exists with a CHECK limited to the four owner states', () {
      expect(code, contains('ADD COLUMN IF NOT EXISTS status text NOT NULL'),
          reason: 'the lifecycle column is gone');
      expect(code, contains("DEFAULT 'invited'"),
          reason: 'D1(ii): existence must not imply authorization, so the '
              'default must not be active');
      for (final s in ['invited', 'active', 'suspended', 'revoked']) {
        expect(code, contains("'$s'"), reason: 'owner state $s missing from the CHECK');
      }
    });

    test('is_team_lead_of() requires ACTIVE', () {
      final fn = RegExp(r'FUNCTION public\.is_team_lead_of\(.*?\$function\$;',
              dotAll: true)
          .firstMatch(code);
      expect(fn, isNotNull, reason: 'is_team_lead_of is no longer redefined by 132');
      expect(fn!.group(0), contains("t.status    = 'active'"),
          reason: 'D1(ii): only ACTIVE membership may satisfy team-lead '
              'authorization. Without this the status column is decorative and '
              'the P0 read path reopens.');
    });

    test('may_notify() requires ACTIVE on the team arm', () {
      final fn = RegExp(r'FUNCTION public\.may_notify\(.*?\$function\$;', dotAll: true)
          .firstMatch(code);
      expect(fn, isNotNull, reason: 'may_notify is no longer redefined by 132');
      final body = fn!.group(0)!;
      expect(
          RegExp(r"coach_team_members t\s*\n\s*WHERE t\.status = 'active'")
              .hasMatch(body),
          isTrue,
          reason: 'D1(ii): the notify channel must require an ACTIVE membership. '
              'This is the team arm of F-03b.');
    });
  });

  group('SEC-W1 · D1(iii) — PHI is out of the team-lead path', () {
    test('the user_profiles SELECT policy no longer trusts is_team_lead_of', () {
      final pol = RegExp(
              r'CREATE POLICY\s+"own profile or active coach reads profile"(.*?);',
              dotAll: true)
          .firstMatch(code);
      expect(pol, isNotNull, reason: '132 no longer redefines the user_profiles SELECT policy');
      final body = pol!.group(1)!;
      expect(body.contains('is_team_lead_of'), isFalse,
          reason: 'D1(iii): a team lead must NOT reach the whole user_profiles '
              'row. This arm granted parq_answers, weights, transformation '
              'photos and billing flags.');
      expect(body, contains('id = auth.uid()'),
          reason: 'self-read broken');
      expect(body, contains('is_active_coach_of(id)'),
          reason: 'the ACTIVE COACH clinical path must not break — an active '
              'coach legitimately needs the PAR-Q');
    });

    test('the roster view is column-limited and carries no PHI', () {
      final view = RegExp(r'CREATE OR REPLACE VIEW public\.team_member_profiles(.*?);',
              dotAll: true)
          .firstMatch(code);
      expect(view, isNotNull, reason: 'the minimum-necessary view is gone');
      final body = view!.group(1)!;
      for (final phi in [
        'parq', 'weight', 'medical', 'injury', 'risk_score', 'stripe',
        'membership_tier', 'transformation', 'date_of_birth', 'phone',
      ]) {
        expect(body.toLowerCase().contains(phi), isFalse,
            reason: 'D1(iii) excludes PHI absolutely, and `$phi` has appeared in '
                'the roster view.');
      }
      expect(body, contains('is_team_lead_of'),
          reason: 'the view must stay gated by the (now ACTIVE-only) helper');
    });

    test('the view does NOT use security_invoker = on', () {
      // NEW-5: the SEC_PHI_1 proposal used `on`, which applies the CALLER's RLS
      // — and the caller is exactly who the base policy now denies, so it would
      // return `200 []` to the users it exists to serve.
      expect(code, contains('security_invoker = off'),
          reason: 'the view must run as owner to serve rows the caller\'s own '
              'RLS denies — this is the corrected pattern');
      expect(code.contains('security_invoker = on'), isFalse,
          reason: 'NEW-5: security_invoker = on makes this view return 200 [] '
              'for every team lead');
      expect(code, contains('security_barrier = true'),
          reason: 'security_barrier keeps the optimizer from leaking rows past '
              'the predicate');
    });

    test('the view is not writable by authenticated — the migration-112 hole', () {
      // Supabase's ALTER DEFAULT PRIVILEGES grants ALL on new views to
      // authenticated. This view is auto-updatable and runs as owner, so a
      // surviving write grant is a write-through into user_profiles that
      // bypasses RLS. Migration 112 exists because 101/102/110 revoked PUBLIC
      // and anon but not authenticated. Wave 1 reproduced that bug once and
      // Agent 3 caught it live.
      expect(code, contains('REVOKE ALL ON public.team_member_profiles FROM PUBLIC, anon, authenticated'),
          reason: 'the write grant is back. An authenticated user could UPDATE '
              'user_profiles through this view as the owner, unfiltered by RLS '
              '— exactly what migration 112 closed for the other five views.');
      expect(code, contains('GRANT SELECT ON public.team_member_profiles TO authenticated'),
          reason: 'the roster can no longer be read');
    });
  });

  test('SEC-W1 the detector can still fail — non-vacuity', () {
    // Without this, every assertion above could be passing because the regexes
    // have rotted rather than because Wave 1 holds. The RG3 vacuous-pass lesson.
    const planted = '''
      CREATE POLICY "member originates own membership" ON public.coach_team_members
        FOR INSERT TO authenticated WITH CHECK (member_id = auth.uid());
    ''';
    // The real policy additionally pins status; a version without it must not
    // satisfy the D1(ii) assertion.
    expect(planted.contains("status = 'invited'"), isFalse,
        reason: 'the planted weaker policy should lack the status pin');
    expect(
        policyOn('coach_team_members', 'ALL')
            .hasMatch('CREATE POLICY "x" ON public.coach_team_members FOR ALL USING (true);'),
        isTrue,
        reason: 'the FOR ALL detector no longer matches the shape it exists to catch');
    // D-2: and the unqualified shape, which it could not match before.
    expect(
        policyOn('coach_team_members', 'ALL')
            .hasMatch('CREATE POLICY "x" ON coach_team_members FOR ALL USING (true);'),
        isTrue,
        reason: 'the FOR ALL detector misses the unqualified form — Finding A');
  });

  // ══ ADDENDUM B · D-3 · the definition IN FORCE, not a pinned one ══════════
  //
  // OWNER DECISION 2026-10-11 · Option A. See the resolvers above for why "also read 134"
  // was rejected: it is the same defect one migration later.
  //
  // WHAT THE RESOLVERS FOUND, and it is more than Finding B recorded: `is_team_lead_of` is
  // redefined by **three** migrations (102, 132, 134) and `may_notify` by **four**
  // (118, 129, 132, 134). The finding named 132 and 134; the real supersession chain is
  // longer, which is itself the argument for resolving the frontier rather than listing it.
  group('SEC-W1 · ADDENDUM B · D-3 — the authoritative helper definitions', () {
    late List<MigrationFile> corpus;

    setUpAll(() {
      corpus = migrationCorpus();
    });

    test('the resolver can see the corpus — non-vacuity before anything is judged', () {
      // An empty corpus would make every assertion below pass for want of input, which is
      // the H-D1 lesson this file already carries once.
      expect(corpus.length, greaterThan(150),
          reason: 'found ${corpus.length} migrations; the set is known to be large, so a '
              'small number means the path or the filter is wrong, not the tree');
      expect(corpus.map((m) => m.name), contains('134_search_path_pin_canonical_form.sql'));
    });

    // THE COVERAGE RATCHET. This is the mechanism the ruling asks for: "fails if those
    // definitions change without corresponding guard coverage". A new redefinition of
    // either helper changes this list, and the guard then fails until somebody records it
    // here — which is the moment to re-check the properties below.
    const expectedDefiners = <String, List<String>>{
      'is_team_lead_of': [
        '102_restrict_user_profiles.sql',
        '132_team_membership_lifecycle.sql',
        '134_search_path_pin_canonical_form.sql',
      ],
      'may_notify': [
        '118_security_sweep.sql',
        '129_notification_contract_and_pr_timing.sql',
        '132_team_membership_lifecycle.sql',
        '134_search_path_pin_canonical_form.sql',
      ],
    };

    for (final helper in expectedDefiners.keys) {
      test('$helper · the set of migrations redefining it is exactly as recorded', () {
        expect(definersOf(helper, corpus), expectedDefiners[helper],
            reason: 'a migration has been added or removed that redefines $helper. That is '
                'not necessarily wrong — but this guard must be updated to see it, and the '
                'properties below re-checked against the new definition in force. That is '
                'what "guard coverage" means here.');
      });

      test('$helper · the definition IN FORCE is 134, and it is readable', () {
        final auth = authoritativeOf(helper, corpus);
        expect(auth, isNotNull, reason: '$helper is no longer defined by any migration');
        expect(auth!.file, '134_search_path_pin_canonical_form.sql',
            reason: 'the authoritative definition has moved to ${auth.file}. The guard now '
                'judges that file — confirm it preserves every property below.');
        // A body that extracted to almost nothing would satisfy the property checks
        // vacuously, since they are substring tests.
        expect(auth.body.length, greaterThan(200),
            reason: 'the extracted body is ${auth.body.length} chars, too short to be the '
                'function — the delimiter match is wrong');
      });

      test('$helper · the definition in force still pins search_path — what 134 is FOR', () {
        final auth = authoritativeOf(helper, corpus)!;
        expect(hasSearchPathPin(auth.body), isTrue,
            reason: 'a SECURITY DEFINER function without a pinned search_path resolves '
                'unqualified names through the CALLER\'s search_path. Migration 134 exists '
                'to close exactly that.');
      });
    }

    test('is_team_lead_of · the definition in force still requires ACTIVE — D1(ii)', () {
      final auth = authoritativeOf('is_team_lead_of', corpus)!;
      expect(teamLeadRequiresActive(auth.body), isTrue,
          reason: 'D1(ii): only ACTIVE membership may satisfy team-lead authorization. '
              'The 132 assertion above proves Wave 1\'s migration still says this; THIS '
              'proves the definition actually in force does.');
    });

    test('may_notify · the TEAM ARM of the definition in force still requires ACTIVE',
        () {
      final auth = authoritativeOf('may_notify', corpus)!;
      expect(notifyTeamArmRequiresActive(auth.body), isTrue,
          reason: 'D1(ii): the notify channel must require an ACTIVE membership. This is '
              'the team arm of F-03b, asserted against 134 rather than 132.');
    });
  });

  // ══ D-3 · THE REGRESSION TEST THE RULING REQUIRES ════════════════════════
  //
  // "Add a regression test proving the guard detects a change to the migration 134
  // definitions." Every mutation below is applied to the REAL text of 134, not to a toy
  // string, and each requires the corresponding check to FAIL. Without this the three
  // property checks above have only ever been observed passing.
  group('SEC-W1 · D-3 · the guard DETECTS a change to 134 — proved by mutation', () {
    late String leadBody;
    late String notifyBody;

    setUpAll(() {
      final corpus = migrationCorpus();
      leadBody = authoritativeOf('is_team_lead_of', corpus)!.body;
      notifyBody = authoritativeOf('may_notify', corpus)!.body;
      // The control: unmutated, every check passes. If this fails the mutations below
      // prove nothing, because the baseline was already broken.
      expect(teamLeadRequiresActive(leadBody), isTrue);
      expect(notifyTeamArmRequiresActive(notifyBody), isTrue);
      expect(hasSearchPathPin(leadBody), isTrue);
      expect(hasSearchPathPin(notifyBody), isTrue);
    });

    test('weakening is_team_lead_of — dropping the ACTIVE predicate — IS detected', () {
      final weakened = leadBody.replaceAll(RegExp(r"AND\s+t\.status\s*=\s*'active'"), '');
      expect(weakened, isNot(leadBody), reason: 'the mutation changed nothing');
      expect(teamLeadRequiresActive(weakened), isFalse,
          reason: 'a definition that no longer requires ACTIVE must fail the check');
    });

    test('weakening may_notify\'s team arm — ACTIVE dropped — IS detected', () {
      // Scoped: only the coach_team_members arm's predicate is removed, so the other arms
      // and their own conditions stay. A mutation that gutted the whole function would
      // prove far less.
      final weakened = notifyBody.replaceAll(
          RegExp(r"(coach_team_members\s+t\s+WHERE\s+)t\.status\s*=\s*'active'\s+AND\s+",
              dotAll: true),
          r'$1');
      expect(weakened, isNot(notifyBody), reason: 'the mutation changed nothing');
      expect(notifyTeamArmRequiresActive(weakened), isFalse,
          reason: 'a notify team arm that no longer requires ACTIVE must fail the check');
    });

    test('unpinning search_path on either helper IS detected', () {
      for (final body in [leadBody, notifyBody]) {
        final weakened =
            body.replaceAll(RegExp(r'SET\s+search_path\s*=.*'), '');
        expect(weakened, isNot(body), reason: 'the mutation changed nothing');
        expect(hasSearchPathPin(weakened), isFalse);
      }
    });

    test('a LATER migration redefining a helper moves the frontier and trips the ratchet',
        () {
      // The mechanism proof for "fails … without corresponding guard coverage". A
      // synthetic corpus is used rather than a file on disk, so nothing in the repository
      // is mutated to run it.
      final corpus = migrationCorpus();
      final synthetic = [
        ...corpus,
        (
          name: '999_hypothetical_weakening.sql',
          src: 'CREATE OR REPLACE FUNCTION public.is_team_lead_of(target_user uuid)\n'
              ' RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER\n'
              'AS \$function\$ SELECT true; \$function\$;',
        ),
      ];

      // 1 · the frontier moves.
      expect(authoritativeOf('is_team_lead_of', synthetic)!.file,
          '999_hypothetical_weakening.sql',
          reason: 'the resolver must follow apply order, not a pinned filename');
      // 2 · the ratchet sees it, so the recorded list no longer matches.
      expect(definersOf('is_team_lead_of', synthetic),
          isNot(const [
            '102_restrict_user_profiles.sql',
            '132_team_membership_lifecycle.sql',
            '134_search_path_pin_canonical_form.sql',
          ]),
          reason: 'a new redefinition must change the definer set, which is what makes the '
              'coverage ratchet fire');
      // 3 · and the weakened definition fails the property checks it was hiding from.
      final weak = authoritativeOf('is_team_lead_of', synthetic)!.body;
      expect(teamLeadRequiresActive(weak), isFalse);
      expect(hasSearchPathPin(weak), isFalse);
    });
  });

  // ══ D-2 · FIXTURES · both forms detected, and nothing else ════════════════
  //
  // OWNER DECISION 2026-10-11 · Option A, whose third clause governs this group: "verify
  // that unrelated SQL does not satisfy the guard." Relaxing a detector WIDENS it, so the
  // fixtures prove two things at once — that the form the guard used to miss is now caught,
  // and that nothing it previously ignored is caught by accident. A guard that fires on the
  // wrong table is not stricter; it is broken.
  group('SEC-W1 · D-2 · the policy detector, both qualification forms', () {
    // ── POSITIVE · the shapes the guard exists to catch ──────────────────────
    const caught = <String, String>{
      'qualified':
          'CREATE POLICY "Head coach manages team" ON public.coach_team_members '
              'FOR ALL USING (coach_id = auth.uid());',
      'unqualified — the 002 form':
          'CREATE POLICY "Head coach manages team" ON coach_team_members '
              'FOR ALL USING (coach_id = auth.uid());',
      'unqualified, newline before FOR':
          'CREATE POLICY "x"\n  ON coach_team_members\n  FOR ALL USING (true);',
      'mixed case':
          'create policy "x" on PUBLIC.coach_team_members for all using (true);',
    };

    caught.forEach((name, sql) {
      test('FOR ALL is detected · $name', () {
        expect(policyOn('coach_team_members', 'ALL').hasMatch(sql), isTrue,
            reason: 'the detector missed: $sql');
      });
    });

    test('the REAL historical defect from migration 002 is detected', () {
      // Read from disk rather than retyped, so the fixture cannot drift from the file it
      // claims to quote — `002_ecosystem_additions.sql:146-147`, the policy Finding A named.
      final src = File('../../supabase/migrations/002_ecosystem_additions.sql');
      expect(src.existsSync(), isTrue, reason: 'migration 002 is missing');
      final code002 = stripComments(src.readAsStringSync());
      expect(code002, contains('ON coach_team_members'),
          reason: 'the unqualified form is no longer in 002 — this fixture is stale, and '
              'Finding A should be re-read before it is trusted');
      expect(policyOn('coach_team_members', 'ALL').hasMatch(code002), isTrue,
          reason: 'the detector still cannot see the defect it was written to catch. That '
              'is Finding A, unremediated.');
    });

    // ── NEGATIVE · what must NOT satisfy the widened detector ────────────────
    const notCaught = <String, String>{
      'a different table':
          'CREATE POLICY "x" ON public.coach_team_invites FOR ALL USING (true);',
      'a LONGER name sharing the prefix — the word-boundary case':
          'CREATE POLICY "x" ON coach_team_members_archive FOR ALL USING (true);',
      'a qualified longer name':
          'CREATE POLICY "x" ON public.coach_team_members_audit FOR ALL USING (true);',
      'a different command on the right table':
          'CREATE POLICY "x" ON coach_team_members FOR SELECT USING (true);',
      'a DROP, not a CREATE':
          'DROP POLICY IF EXISTS "x" ON coach_team_members;',
      'a grant, not a policy':
          'GRANT ALL ON coach_team_members TO authenticated;',
    };

    notCaught.forEach((name, sql) {
      test('NOT detected · $name', () {
        expect(policyOn('coach_team_members', 'ALL').hasMatch(sql), isFalse,
            reason: 'the widened detector now fires on unrelated SQL: $sql');
      });
    });

    test('NOT detected · a COMMENT that merely mentions the shape', () {
      // The trap this file's header names: commented code read as active code.
      const commented =
          '-- CREATE POLICY "x" ON coach_team_members FOR ALL USING (true);';
      expect(policyOn('coach_team_members', 'ALL').hasMatch(stripComments(commented)),
          isFalse);
    });

    test('FOR UPDATE is detected in both forms, and FOR ALL does not satisfy it', () {
      for (final sql in [
        'CREATE POLICY "x" ON public.coach_team_members FOR UPDATE USING (true);',
        'CREATE POLICY "x" ON coach_team_members FOR UPDATE USING (true);',
      ]) {
        expect(policyOn('coach_team_members', 'UPDATE').hasMatch(sql), isTrue);
      }
      // The two detectors stay distinct: the FOR UPDATE assertion exists to catch an
      // ungoverned activation route, and FOR ALL has its own assertion and its own reason.
      expect(
          policyOn('coach_team_members', 'UPDATE')
              .hasMatch('CREATE POLICY "x" ON coach_team_members FOR ALL USING (true);'),
          isFalse,
          reason: 'the UPDATE detector matched a FOR ALL policy — the two findings would '
              'become indistinguishable');
    });

    // ── the policy-scoped target scan ────────────────────────────────────────
    test('policyTargets reads POLICY DDL only — not COMMENT ON TABLE, not ON DELETE', () {
      const noise =
          "COMMENT ON TABLE public.user_profiles IS 'not a policy target';\n"
          'ALTER TABLE x ADD CONSTRAINT f FOREIGN KEY (y) REFERENCES z(id) ON DELETE CASCADE;\n'
          'CREATE POLICY "a" ON coach_team_members FOR SELECT USING (true);\n'
          'DROP POLICY IF EXISTS "b" ON public.coach_team_members;';
      expect(policyTargets(noise), {'coach_team_members'},
          reason: 'a bare ON scan would also return TABLE and DELETE — which is why this '
              'instrument is scoped to POLICY DDL');
    });

    test('policyTargets sees an UNQUALIFIED out-of-scope table — the gap it closes', () {
      const outOfScope =
          'CREATE POLICY "a" ON coach_team_members FOR SELECT USING (true);\n'
          'CREATE POLICY "b" ON some_other_table FOR SELECT USING (true);';
      expect(policyTargets(outOfScope), {'coach_team_members', 'some_other_table'},
          reason: 'an unqualified out-of-scope target must be visible, or the scope check '
              'can be evaded by dropping `public.`');
    });
  });
}
