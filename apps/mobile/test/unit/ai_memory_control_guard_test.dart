import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// AIMEM-G1 — the member's only control over what the AI remembers about them.
///
/// `ai_memories` rows are health facts. `kind` includes **`injury`**, and
/// `supabase/functions/ai-coach` captures them **automatically** — it scans
/// each message for *injur/hurt/sore/pain/allerg/…* and writes what it
/// extracts. The member never explicitly submits them.
///
/// The one control over that is a long-press on the chip. It called a
/// `deleteMemory` that returned `void` and ended in `catch (_) {}`, so a
/// failed delete was indistinguishable from a successful one: the chip
/// reappeared after the refresh with no explanation, which reads as a glitch
/// rather than "the injury your coach remembers is still on record".
///
/// ── WHAT THIS GUARD DOES *NOT* CLAIM ───────────────────────────────────────
/// It does not claim the control is discoverable. A long-press with no label,
/// no affordance and no confirmation is a **design** question, recorded as
/// OD-60 and left to the owner. This pins the error contract and the
/// authorization, which are not design questions.
void main() {
  late String service;
  late String screen;

  setUpAll(() {
    service = File('lib/features/ai_coach/data/ai_coach_service.dart')
        .readAsStringSync();
    screen = File('lib/features/ai_coach/presentation/ai_coach_screen.dart')
        .readAsStringSync();
  });

  test('AIMEM-G1 the guard is reading the right files', () {
    // An absent result must not read as "no defect" — the H-D1 lesson.
    expect(service, contains("from('ai_memories')"));
    expect(screen, contains('_CoachingMemoryCard'));
  });

  test('AIMEM-G1 a failed deletion is not reported as a success', () {
    final start = service.indexOf('Future<bool> deleteMemory(');
    expect(start, greaterThan(0),
        reason: 'deleteMemory no longer returns bool — a caller cannot tell a '
            'failed deletion of a health fact from a successful one');
    final body = service.substring(start, service.indexOf('\n  }', start));

    expect(RegExp(r'catch\s*\(_\)\s*\{\s*\}').hasMatch(body), isFalse,
        reason: 'the empty catch is back: a failed delete looks identical to a '
            'successful one');
    expect(body, contains('return false;'),
        reason: 'failure must be reported to the caller');
    expect(body, contains('return true;'));
  });

  test('AIMEM-G1 the screen acts on the result', () {
    // Returning bool is worthless if the caller discards it — the two-layer
    // blindness A-G6 was written about.
    final i = screen.indexOf('deleteMemory(');
    expect(i, greaterThan(0));
    final around = screen.substring(i, i + 420);
    expect(around, contains('if (!ok'),
        reason: 'the screen ignores the result again, so a failed deletion is '
            'silent at the UI even though the service now reports it');
    expect(around, contains('ScaffoldMessenger'),
        reason: 'nothing tells the member the deletion did not happen');
  });

  test('AIMEM-G1 deletion is authorized by the database, not by the query', () {
    // `delete().eq('id', id)` carries NO user_id predicate. That is only safe
    // because RLS constrains it. If that policy is ever dropped, this becomes
    // a cross-user delete by id — so the policy is asserted here, from the
    // migration, rather than assumed.
    //
    // It is created by a DO-block loop over an array of table names, NOT by a
    // literal `ALTER TABLE ai_memories`. A previous audit grepped for the
    // literal form, found nothing, and reported the protection missing. It is
    // matched here the way it is actually written.
    // Tests run from apps/mobile.
    final f = File('../../supabase/migrations/074_ai_coaching_layer.sql');
    expect(f.existsSync(), isTrue,
        reason: 'migration 074 has moved or been renamed; this guard must be '
            'repointed in the same change rather than left checking nothing');
    final m = f.readAsStringSync();

    expect(m, contains("'ai_memories'"),
        reason: 'ai_memories is no longer in the RLS loop');
    expect(m, contains('enable row level security'));
    // Assert each CLAUSE, not the bare predicate. `user_id = auth.uid()`
    // appears twice — in `using` and in `with check` — so a `contains` check
    // on the predicate alone passes while the READ side has been opened to
    // `using (true)`. Mutation testing caught exactly that: the mutation
    // survived because the `with check` occurrence still matched.
    expect(m, contains('using (user_id = auth.uid())'),
        reason: 'the "own ai data" READ/DELETE clause no longer scopes to the '
            "owner — deleteMemory's delete-by-id becomes cross-user");
    expect(m, contains('with check (user_id = auth.uid())'),
        reason: 'the WRITE clause no longer scopes to the owner — a member '
            "could write a memory onto someone else's record");
    // FOR ALL is what makes the policy cover DELETE and not just SELECT.
    expect(m, contains('for all to authenticated'),
        reason: 'the policy no longer covers DELETE, so delete-by-id is '
            'unconstrained');
  });
}
