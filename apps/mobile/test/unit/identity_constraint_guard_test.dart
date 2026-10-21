// I-G1 … I-G5 — Wave 3A task 3A-11, the identity-constraint contract (CRC-06).
//
// STATIC guards in the shape `error_contract_guard_test.dart` and
// `product_contract_guard_test.dart` established: they parse the committed
// source, so a regression fails `flutter test` with no database, no credential
// and no running app.
//
// Why these exist at all: `npm run test:contract` derives tables, columns and
// foreign keys from the migrations and is blind to UNIQUE indexes and CHECK
// constraints. Nothing in this repository would notice if migration 131's four
// constraints were deleted tomorrow. That is the gap these close.
//
// What is guarded:
//   I-G1  the four identity constraints exist, on the right table and columns
//   I-G2  the two SECURITY DEFINER writers keep their security posture
//   I-G3  the client writers go through the RPCs — the check-then-insert races
//         the constraints exist to arbitrate do not come back
//   I-G4  the Stripe credit grant stays idempotent, and stays DO NOTHING
//   I-G5  the deferred work stays deferred (no exclusion constraint, no
//         NOT VALID, no policy change smuggled into an identity migration)
//
// These assert what is TRUE of the tree at 3A-11 and nothing that has not been
// done. `I-PAY-01`'s terminal closure is deferred — Stripe test mode does not
// exist (P-8) — and no guard here claims otherwise.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ── Locating the tree ────────────────────────────────────────────────────────

Directory _mobileRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate the Flutter package root');
    }
    dir = parent;
  }
  return dir;
}

Directory _repoRoot() {
  var dir = _mobileRoot();
  while (!Directory('${dir.path}/supabase/migrations').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate supabase/migrations');
    }
    dir = parent;
  }
  return dir;
}

String _read(String relativeToRepoRoot) =>
    File('${_repoRoot().path}/$relativeToRepoRoot').readAsStringSync();

/// SQL with `--` comments stripped, so every assertion below reasons about
/// what EXECUTES and never about what a header happens to discuss.
String _sqlExecutable(String sql) => sql
    .split('\n')
    .map((l) => l.replaceFirst(RegExp(r'--.*$'), ''))
    .join('\n');

Iterable<File> _migrations() sync* {
  final dir = Directory('${_repoRoot().path}/supabase/migrations');
  for (final f in dir.listSync().whereType<File>()) {
    if (f.path.endsWith('.sql')) yield f;
  }
}

void main() {
  late final String m131raw = _read('supabase/migrations/131_identity_constraints.sql');
  late final String m131 = _sqlExecutable(m131raw);

  // ── I-G1 · the four constraints ───────────────────────────────────────────
  //
  // Each is asserted by table AND by the exact column expression, because a
  // unique index on the wrong column is not a weaker version of the contract —
  // it is a different contract that happens to compile.
  group('I-G1 the four identity constraints exist', () {
    test('I-NUT-04 · at most one ACTIVE nutrition plan per client', () {
      expect(
          m131,
          contains(RegExp(
              r'CREATE UNIQUE INDEX IF NOT EXISTS\s+client_nutrition_plans_one_active_per_client\s+'
              r'ON public\.client_nutrition_plans \(client_id\)\s+WHERE is_active')),
          reason: 'must be PARTIAL on is_active — the contract is "one active '
              'plan", not "one plan"; superseded rows are history');
    });

    test('I-WMH-01 · one period per start date', () {
      expect(
          m131,
          contains(RegExp(
              r'CREATE UNIQUE INDEX IF NOT EXISTS\s+cycle_logs_one_period_per_start\s+'
              r'ON public\.cycle_logs \(user_id, start_date\)')));
    });

    test('I-WMH-01 · a period cannot end before it starts', () {
      expect(m131, contains('cycle_logs_end_on_or_after_start'));
      expect(m131,
          contains('CHECK (end_date IS NULL OR end_date >= start_date)'));
      expect(m131, contains("conrelid = 'public.cycle_logs'::regclass"),
          reason: 'ALTER TABLE ADD CONSTRAINT has no IF NOT EXISTS, so the '
              'guard on pg_constraint is what makes replay safe');
    });

    test('I-NOT-05 · one conversation per UNORDERED participant pair', () {
      expect(
          m131,
          contains(RegExp(
              r'CREATE UNIQUE INDEX IF NOT EXISTS\s+conversations_unique_participant_pair\s+'
              r'ON public\.conversations \(\s*least\(participant_1, participant_2\),\s*'
              r'greatest\(participant_1, participant_2\)\s*\)')),
          reason: 'the pair is unordered — indexing (participant_1, '
              'participant_2) directly would let (A,B) and (B,A) coexist, '
              'which is the defect');
    });

    test('I-PAY-01 · one credit grant per payment', () {
      expect(
          m131,
          contains(RegExp(
              r'CREATE UNIQUE INDEX IF NOT EXISTS\s+client_session_credits_unique_payment\s+'
              r'ON public\.client_session_credits \(payment_id\)')));
      // Deliberately NOT partial: PostgREST's on_conflict carries no index
      // predicate, so a partial index cannot be inferred by the upsert the
      // same finding requires. NULLs are distinct in a plain unique index, so
      // the semantics are identical. See the migration header.
      expect(m131, isNot(contains('client_session_credits (payment_id)\n  WHERE')),
          reason: 'a partial index here would make the required upsert fail '
              'with "no unique or exclusion constraint matching the ON '
              'CONFLICT specification"');
    });

    test('all four are idempotent — replay-safe by construction', () {
      final creates = RegExp(r'CREATE UNIQUE INDEX(?: IF NOT EXISTS)?')
          .allMatches(m131)
          .map((m) => m.group(0))
          .toList();
      expect(creates.length, 4);
      expect(creates.every((c) => c!.contains('IF NOT EXISTS')), isTrue);
    });
  });

  // ── I-G2 · the SECURITY DEFINER writers ───────────────────────────────────
  //
  // Both bypass RLS by construction, so their posture is the whole of their
  // safety. Gate 0.14 and migration 122's convention: definer, pinned
  // search_path, revoked from PUBLIC and anon, granted only to authenticated.
  group('I-G2 the atomic writers keep their security posture', () {
    for (final fn in ['assign_nutrition_plan', 'get_or_create_conversation']) {
      test('$fn is SECURITY DEFINER with a pinned search_path', () {
        final body = RegExp(
                'CREATE OR REPLACE FUNCTION public\\.$fn\\([\\s\\S]*?\\n\\\$\\\$;')
            .firstMatch(m131)
            ?.group(0);
        expect(body, isNotNull, reason: '$fn must be defined in 131');
        expect(body, contains('SECURITY DEFINER'));
        expect(body, contains('SET search_path = public, pg_temp'),
            reason: 'a definer function with a mutable search_path resolves '
                'unqualified names through the CALLER\'s path');
        expect(body, contains('VOLATILE'),
            reason: 'it writes — STABLE would be a lie to the planner');
        expect(body, contains("USING ERRCODE = '42501'"),
            reason: 'an unauthenticated caller must be refused explicitly, '
                'not fall through to a null-valued insert');
      });

      test('$fn is revoked from PUBLIC and anon, granted to authenticated', () {
        expect(m131, contains(RegExp('REVOKE ALL ON FUNCTION public\\.$fn')));
        expect(m131, contains('FROM PUBLIC, anon;'));
        expect(m131, contains(RegExp('GRANT EXECUTE ON FUNCTION public\\.$fn')));
        expect(m131, contains('TO authenticated;'));
      });

      test('$fn uses no dynamic SQL', () {
        expect(m131, isNot(contains('EXECUTE format')));
        expect(m131, isNot(contains('EXECUTE \'')));
      });
    }

    test('assign_nutrition_plan takes coach_id from auth.uid(), not a parameter',
        () {
      final sig = RegExp(
              r'CREATE OR REPLACE FUNCTION public\.assign_nutrition_plan\(([\s\S]*?)\)\s*\nRETURNS')
          .firstMatch(m131)!
          .group(1)!;
      expect(sig, isNot(contains('coach')),
          reason: 'a coach_id parameter would let a caller attribute a plan '
              'to another coach; taking it from auth.uid() satisfies the '
              '"coach client nutrition" policy by construction');
      expect(m131, contains('v_coach uuid := (SELECT auth.uid())'));
    });

    test('get_or_create_conversation takes participant_1 from auth.uid()', () {
      expect(m131, contains('v_me uuid := (SELECT auth.uid())'));
      expect(m131, contains('VALUES (v_me, other_user, now())'),
          reason: 'the caller is always participant_1, so this cannot open a '
              'conversation on someone else\'s behalf');
      expect(m131, contains('IF other_user = v_me THEN'),
          reason: 'a self-conversation would index as (me, me) and is refused');
    });

    test('get_or_create_conversation resolves a race instead of racing', () {
      expect(m131, contains('ON CONFLICT ('));
      expect(m131, contains('DO NOTHING'));
      expect(m131, contains('IF v_id IS NULL THEN'),
          reason: 'DO NOTHING returns no row when the loser of a race hits the '
              'index — it must then READ the winner\'s row, or the caller gets '
              'null and the split this finding is about happens anyway');
    });
  });

  // ── I-G3 · the client writers ─────────────────────────────────────────────
  group('I-G3 the client writers go through the atomic RPCs', () {
    late final String messaging =
        _read('apps/mobile/lib/features/messaging/data/messaging_service.dart');
    late final String coachProgram =
        _read('apps/mobile/lib/features/coach/data/coach_program_service.dart');

    test('I-NOT-05 · neither conversation path inserts directly any more', () {
      for (final m in RegExp(r"\.from\('conversations'\)([\s\S]{0,400}?);")
          .allMatches(messaging)) {
        expect(m.group(1), isNot(contains('.insert(')),
            reason: 'a check-then-insert on conversations is the race the '
                'unique pair index exists to arbitrate — it must not come back');
      }
      // Whitespace-independent on purpose. The first version of this line
      // pinned the call's exact indentation, so re-nesting the call — which
      // the EC-23 anchor restoration required — failed a guard that was never
      // about formatting. The contract is "this file reaches the arbiter RPC",
      // and that is what is asserted.
      expect(
          messaging,
          contains(RegExp(
              r"supabase\.rpc\(\s*'get_or_create_conversation'",
              dotAll: true)),
          reason: 'the conversation path must go through the arbiter RPC');
    });

    test('I-NOT-05 · both entry points collapse onto the one arbiter', () {
      expect(messaging, contains('getOrCreateConversationWith'));
      expect(messaging, contains('getOrCreateCoachClientConversation'));
      expect(messaging, contains('_getOrCreateConversation('),
          reason: 'both sides of the pair must resolve through one path, or '
              'which party is participant_1 decides whether a second thread '
              'gets created');
      expect(RegExp(r'_getOrCreateConversation\(').allMatches(messaging).length,
          greaterThanOrEqualTo(3),
          reason: 'the helper plus both call sites');
    });

    test('I-NOT-05 · a failure is still null, and each entry point reports '
        'under its own name', () {
      // Named reporters, not one shared reporter taking the origin as a
      // parameter. Two reasons, and the second is why this assertion is
      // written by name rather than by shape:
      //   * the failure sink keeps the two entry points distinguishable; and
      //   * ec23_negative_control.sh anchors its mutation on
      //     `reportError('<literal>', e);` in this file, so a parameterised
      //     reporter is invisible to it. Collapsing these two catches into one
      //     took that harness's anchor set from 7 to 5 and made it refuse.
      for (final origin in const [
        'MessagingService.getOrCreateConversationWith',
        'MessagingService.getOrCreateCoachClientConversation',
      ]) {
        expect(messaging, contains("reportError('$origin', e);"),
            reason: '$origin must report under its own name');
      }
      expect(messaging, isNot(contains('reportError(context, e)')),
          reason: 'a parameterised reporter is not anchorable by EC-23');
      expect(messaging, contains('return null;'));
    });

    test('I-NUT-04 · the coach writer is one atomic RPC, not two statements',
        () {
      expect(coachProgram, contains("_db.rpc('assign_nutrition_plan'"));
      final body = RegExp(
              r'Future<void> assignNutritionPlan\([\s\S]*?\n  \}')
          .firstMatch(coachProgram)!
          .group(0)!;
      expect(body, isNot(contains("from('client_nutrition_plans')")),
          reason: 'deactivate-then-insert as two statements is the defect: a '
              'failure between them leaves the client with NO active plan and '
              'every reader answers that with default macros');
      expect(body, isNot(contains("'coach_id'")),
          reason: 'coach_id comes from auth.uid() inside the function');
    });
  });

  // ── I-G4 · the Stripe credit grant ────────────────────────────────────────
  group('I-G4 the session-credit grant is idempotent', () {
    late final String webhook =
        _read('supabase/functions/stripe-webhook/index.ts');

    test('the grant upserts on payment_id and never re-inserts', () {
      final block = RegExp(r"from\('client_session_credits'\)[\s\S]{0,700}?\}\);")
          .firstMatch(webhook)
          ?.group(0);
      expect(block, isNotNull);
      expect(block, contains('.upsert('));
      expect(block, isNot(contains('.insert(')),
          reason: 'Stripe delivers at least once; a bare insert grants the '
              'sessions again on every redelivery. This is money');
      expect(block, contains("onConflict: 'payment_id'"));
    });

    test('a redelivery is a no-op, not a rewrite', () {
      expect(webhook, contains('ignoreDuplicates: true'),
          reason: 'sessions_used may have advanced since the grant; a merge '
              'would rewrite a block that is being consumed');
    });

    test('every other write in the handler still carries a conflict target', () {
      // The finding was that ONE write lacked one. Pin the rest so a future
      // edit cannot quietly remove another.
      for (final target in [
        "onConflict: 'stripe_subscription_id'",
        "onConflict: 'client_id,coach_id'",
        "onConflict: 'event_id,user_id'",
      ]) {
        expect(webhook, contains(target));
      }
    });
  });

  // ── I-G5 · the deferred work stays deferred ───────────────────────────────
  group('I-G5 migration 131 stays inside its authorized scope', () {
    test('no EXCLUSION constraint — the overlap guard is deferred', () {
      expect(m131.toUpperCase(), isNot(contains('EXCLUDE USING')),
          reason: 'Workstream I conditions it on a dedupe pass and '
              '"overlapping periods" has no product definition');
    });

    test('the CHECK is added VALID, not NOT VALID', () {
      expect(m131, isNot(contains('NOT VALID')),
          reason: 'I-MIG-02 already records two ALTER-added CHECKs that are '
              'NOT VALID and were never validated. This does not add a third');
    });

    test('an identity migration changes no policy and drops nothing', () {
      expect(m131, isNot(contains('CREATE POLICY')));
      expect(m131, isNot(contains('DROP POLICY')));
      expect(m131, isNot(contains('ALTER POLICY')));
      expect(m131, isNot(contains(RegExp(r'^DROP ', multiLine: true))));
    });

    test('it touches only the four tables its findings name', () {
      final tables = RegExp(r'\b(?:ON|INTO|UPDATE|FROM)\s+public\.([a-z_]+)')
          .allMatches(m131)
          .map((m) => m.group(1)!)
          .where((t) => !t.startsWith('assign_') && !t.startsWith('get_or_'))
          .toSet();
      expect(
          tables,
          {
            'client_nutrition_plans',
            'cycle_logs',
            'conversations',
            'client_session_credits',
          },
          reason: 'unrelated DDL in an identity migration is scope creep that '
              'a reviewer cannot see from the filename');
    });

    test('no migration writes the ledger', () {
      for (final f in _migrations()) {
        final sql = _sqlExecutable(f.readAsStringSync());
        expect(sql, isNot(contains('supabase_migrations')),
            reason: '${f.path.split('/').last}: a schema_migrations row is '
                'created by application, never by a migration');
      }
    });
  });

  // I-G6 (QA exhaustion Run 2). Everything above reads migration 131 only, so
  // a LATER migration that drops one of these constraints — or silently
  // redefines an atomic writer — passed this whole file (mutation-proven:
  // `drop index cycle_logs_one_period_per_start` in a later file stayed green).
  // That is the 116 -> 119 regression shape the closure standard names.
  group('I-G6 no later migration undoes 131', () {
    const protectedObjects = [
      'client_nutrition_plans_one_active_per_client',
      'cycle_logs_one_period_per_start',
      'cycle_logs_end_on_or_after_start',
      'conversations_unique_participant_pair',
      'client_session_credits_unique_payment',
    ];
    const atomicWriters = ['assign_nutrition_plan', 'get_or_create_conversation'];

    Iterable<(String, String)> later() sync* {
      for (final f in _migrations()) {
        final name = f.path.split('/').last;
        final n = int.tryParse(name.split('_').first);
        if (n != null && n > 131) yield (name, _sqlExecutable(f.readAsStringSync()));
      }
    }

    test('no later migration drops an identity constraint', () {
      for (final (name, sql) in later()) {
        for (final obj in protectedObjects) {
          expect(
              RegExp('drop\\s+(index|constraint)\\s+(if\\s+exists\\s+)?(\\w+\\.)?$obj\\b',
                      caseSensitive: false)
                  .hasMatch(sql),
              isFalse,
              reason: '$name drops $obj, which migration 131 added');
        }
      }
    });

    test('a later redefinition of an atomic writer must be reviewed here', () {
      for (final (name, sql) in later()) {
        for (final fn in atomicWriters) {
          expect(
              RegExp('create\\s+(or\\s+replace\\s+)?function\\s+(public\\.)?$fn\\b',
                      caseSensitive: false)
                  .hasMatch(sql),
              isFalse,
              reason: '$name redefines $fn. Re-prove every property I-G2 pins '
                  '(SECURITY DEFINER, pinned search_path, grants, auth.uid() '
                  'identity) against the NEW body, then extend I-G2 to read it '
                  'and update this test. (QAX-SEC-01 will need exactly this.)');
        }
      }
    });
  });
}
