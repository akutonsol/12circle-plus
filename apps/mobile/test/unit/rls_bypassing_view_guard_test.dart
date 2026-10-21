import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SEC-G4 — the two views that deliberately bypass RLS must not widen.
///
/// ── WHY THESE VIEWS EXIST, AND WHY THEY ARE NOT DEFECTS ────────────────────
/// A Postgres view declared `WITH (security_invoker = off)` runs with the
/// **view owner's** privileges, so it reads the underlying table **regardless
/// of that table's RLS**. Two views in this schema do exactly that, on
/// `user_profiles` — the table `102_restrict_user_profiles.sql` exists to
/// restrict.
///
/// Both are deliberate and both are sound:
///
///   * `public_profiles` (`101`, re-declared by `110`) is a **curated
///     projection** — display names and coach-marketplace fields, nothing
///     else — with `REVOKE ALL FROM PUBLIC, anon` and `GRANT SELECT TO
///     authenticated`. The bypass is the point: a directory cannot work if
///     every row is invisible.
///   * `conversation_participant_profiles` (`102`) bypasses too, but carries
///     its **own predicate** — `WHERE public.shares_conversation_with(p.id)` —
///     so the bypass is bounded to people the caller already shares a thread
///     with, and is additionally `security_barrier = true`.
///
/// ── SO WHAT IS THE GAP ─────────────────────────────────────────────────────
/// Their safety rests entirely on two **comments**:
///
///   'Never add medical, contact, billing or intake columns to this view.'
///   'never drop the shares_conversation_with() predicate'
///
/// Nothing enforces either, and `110` already demonstrates that these views
/// **do get re-declared** as the product grows. A future re-declaration that
/// adds `email`, `phone` or `address`, or quietly drops the predicate, would
/// publish that column to **every authenticated account** — a mass disclosure
/// with no failing test anywhere.
///
/// This guard is the enforcement those comments ask for. It changes nothing
/// and proposes nothing; it makes the existing design decision hold.
void main() {
  final dir = Directory('../../supabase/migrations');

  /// The LAST definition wins — migrations replay in filename order, and
  /// `CREATE OR REPLACE VIEW` means a later file silently supersedes an
  /// earlier one. Reading only `101` would miss what `110` did.
  ({String file, String body})? lastDefinitionOf(String view) {
    ({String file, String body})? found;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      for (final m in RegExp(
              'CREATE\\s+OR\\s+REPLACE\\s+VIEW\\s+(?:public\\.)?$view\\b(.*?);',
              dotAll: true,
              caseSensitive: false)
          .allMatches(f.readAsStringSync())) {
        found = (file: f.path.split('/').last, body: m.group(1)!);
      }
    }
    return found;
  }

  Set<String> projectedColumns(String body) {
    final select = RegExp(r'\bSELECT\b(.*?)\bFROM\b', dotAll: true, caseSensitive: false)
        .firstMatch(body);
    if (select == null) return {};
    return select
        .group(1)!
        .split(',')
        .map((c) => c.trim())
        // strip `p.` qualifiers, comments and aliases
        .map((c) => c.replaceAll(RegExp(r'--[^\n]*'), '').trim())
        .map((c) => c.contains('.') ? c.split('.').last.trim() : c)
        .map((c) => c.split(RegExp(r'\s+')).first.trim().toLowerCase())
        .where((c) => c.isNotEmpty)
        .toSet();
  }

  setUpAll(() {
    if (!dir.existsSync()) {
      fail('Could not read supabase/migrations — SEC-G4 asserted nothing.');
    }
  });

  // Columns that must never reach a view every authenticated account can read.
  // `user_profiles` is the source, so this is the list its own restriction
  // migration (102) exists to protect.
  const forbidden = <String>[
    'email', 'phone', 'phone_number', 'address', 'street', 'postcode',
    'date_of_birth', 'dob', 'medical', 'medical_conditions', 'injuries',
    'medications', 'intake', 'intake_answers', 'parq', 'stripe_customer_id',
    'stripe_account_id', 'billing', 'password', 'onboarding_complete',
    'coaching_mode', 'weight_goal_kg', 'fitness_goal',
  ];

  group('SEC-G4 public_profiles', () {
    // Measured 2026-09-23 against 110's re-declaration, which supersedes 101.
    const recorded = <String>{
      'id', 'first_name', 'last_name', 'avatar_url', 'role',
      'coach_title', 'coach_bio', 'bio', 'tagline', 'specialties',
      'certifications', 'years_experience', 'pricing_monthly',
      'pricing_description', 'rating_avg', 'review_count',
      'transformation_photo_urls', 'is_accepting_clients', 'max_clients',
      'created_at', 'is_demo',
    };

    test('the detector found the view, in the file that last defined it', () {
      final v = lastDefinitionOf('public_profiles');
      expect(v, isNotNull, reason: 'no definition found — the parser is broken');
      expect(v!.file, '110_profile_demo_flag.sql',
          reason: 'a later migration re-declared this view. Re-read it, then '
              'update `recorded` deliberately rather than letting the new '
              'column list pass unexamined.');
      expect(projectedColumns(v.body), isNotEmpty);
    });

    test('it projects no column beyond the recorded set', () {
      final cols = projectedColumns(lastDefinitionOf('public_profiles')!.body);
      expect(
        cols.difference(recorded),
        isEmpty,
        reason: 'A column was added to a view that EVERY authenticated account '
            'can read, and which bypasses user_profiles RLS by design '
            '(security_invoker = off). The view\'s own comment says: "Never add '
            'medical, contact, billing or intake columns to this view."',
      );
      expect(recorded.difference(cols), isEmpty,
          reason: 'a recorded column is gone — update `recorded` in the same '
              'change rather than leaving this stale');
    });

    test('it projects nothing from the forbidden list', () {
      final cols = projectedColumns(lastDefinitionOf('public_profiles')!.body);
      for (final f in forbidden) {
        expect(cols.contains(f), isFalse,
            reason: '`$f` would be published to every signed-in account');
      }
    });

    test('it is still revoked from anon', () {
      // The anon key ships inside the published client build, so anon is the
      // open internet. 118's F-07 revokes it globally; this view names it too.
      final src = File('${dir.path}/101_public_profiles_view.sql')
          .readAsStringSync();
      expect(src, contains('REVOKE ALL ON public.public_profiles FROM PUBLIC, anon'));
    });
  });

  group('SEC-G4 conversation_participant_profiles', () {
    const recorded = <String>{
      'id', 'first_name', 'last_name', 'role', 'avatar_url',
    };

    test('the detector found the view', () {
      final v = lastDefinitionOf('conversation_participant_profiles');
      expect(v, isNotNull);
      expect(projectedColumns(v!.body), isNotEmpty);
    });

    test('it projects no column beyond the recorded set', () {
      final cols = projectedColumns(
          lastDefinitionOf('conversation_participant_profiles')!.body);
      expect(cols.difference(recorded), isEmpty);
      expect(recorded.difference(cols), isEmpty);
      for (final f in forbidden) {
        expect(cols.contains(f), isFalse);
      }
    });

    // This is the whole reason the view is safe. Without it, `security_invoker
    // = off` would publish every profile to every account.
    test('it still carries the shares_conversation_with predicate', () {
      final body =
          lastDefinitionOf('conversation_participant_profiles')!.body;
      expect(body, contains('shares_conversation_with'),
          reason: 'the view\'s own comment: "never drop the '
              'shares_conversation_with() predicate". Without it this view '
              'bypasses user_profiles RLS for EVERY row, not just the '
              'caller\'s counterparties.');
      expect(RegExp(r'\bWHERE\b', caseSensitive: false).hasMatch(body), isTrue);
      expect(body, contains('security_barrier = true'),
          reason: 'without security_barrier a cheap user-supplied function can '
              'be evaluated before the predicate and leak filtered rows');
    });

    test('the predicate function is scoped to the caller', () {
      final src =
          File('${dir.path}/102_restrict_user_profiles.sql').readAsStringSync();
      final fn = RegExp(
              r'CREATE OR REPLACE FUNCTION public\.shares_conversation_with.*?\$\$(.*?)\$\$',
              dotAll: true)
          .firstMatch(src);
      expect(fn, isNotNull);
      expect(fn!.group(1), contains('auth.uid()'),
          reason: 'the predicate must bind to the CALLER, not to a parameter '
              'the caller chooses — that is F-21\'s defect');
    });
  });

  // ── The detector must be able to see a violation ─────────────────────────
  group('SEC-G4 the detector works', () {
    test('it reads a column list, qualifiers and all', () {
      expect(
        projectedColumns('WITH (security_invoker = off) AS SELECT p.id, '
            'p.first_name, p.email FROM public.user_profiles'),
        {'id', 'first_name', 'email'},
      );
    });

    test('it would catch an added forbidden column', () {
      final cols = projectedColumns(
          'AS SELECT id, first_name, email, phone FROM public.user_profiles');
      expect(cols.contains('email'), isTrue);
      expect(cols.contains('phone'), isTrue);
    });

    test('it does not mistake the FROM clause for a column', () {
      expect(
          projectedColumns('AS SELECT id FROM public.user_profiles'), {'id'});
    });

    test('a view it cannot find returns null rather than passing quietly', () {
      expect(lastDefinitionOf('no_such_view_anywhere'), isNull);
    });
  });
}
