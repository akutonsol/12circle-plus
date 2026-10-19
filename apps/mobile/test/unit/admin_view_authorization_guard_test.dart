import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The nine Admin views bypass RLS on purpose. Their ONLY gate is the
/// `admin_can` predicate inside the view body, and nothing offline protected it.
///
/// ── WHY THESE VIEWS BYPASS RLS, AND WHY THAT IS NOT A DEFECT ───────────────
/// A view declared `WITH (security_invoker = off)` executes as its **owner**, so
/// it reads the base tables regardless of their RLS. Every Admin surface view
/// does this deliberately: the Admin layer must aggregate across users, which
/// per-row RLS on `workout_sessions`, `payments` and the rest would prevent.
///
/// The authorization therefore moves INTO the view. `174:50` is the pattern:
///
///   CREATE OR REPLACE VIEW public.admin_release_status
///   WITH (security_invoker = off) AS
///     SELECT ... WHERE public.admin_can('System', 'view');
///
/// `172:48` goes finer still and gates per COLUMN —
/// `CASE WHEN public.admin_can('Users','view') THEN (...) END` — so an uncapable
/// caller receives NULL for that column rather than an error, which is why
/// `admin_metrics_service.dart` asks `admin_can` explicitly instead of inferring
/// a permission from an empty read.
///
/// ── WHAT WAS UNPROTECTED ───────────────────────────────────────────────────
/// `security_invoker = off` plus a missing predicate is a silent full-table
/// read for any authenticated caller. `CREATE OR REPLACE VIEW` replaces the
/// WHOLE definition, so a later migration that redefines one of these views and
/// omits its `WHERE public.admin_can(...)` removes the only gate — and:
///
///   * `schema-facts.mjs` asserts nothing about these views (0 references to
///     `security_invoker`, `admin_can`, or any Admin view name);
///   * `rls_bypassing_view_guard_test.dart` guards the profile-exposing views by
///     column projection and names none of the Admin views;
///   * the behavioural coverage that does exist — `d15` for
///     `admin_integration_connections`, `d16` for `admin_release_status` — lives
///     in the LIVE QA labs, needs credentials, and does not run offline.
///
/// So the 2006-test offline suite would stay green through exactly that
/// regression. This guard closes that, and nothing more: it asserts the posture
/// the migrations already have. Verified at the time of writing — all nine views
/// satisfy all three invariants, so this guard starts green by describing
/// reality rather than by demanding a change.
void main() {
  final dir = Directory('../../supabase/migrations');

  /// Every Admin view that runs `security_invoker = off`, with the migration
  /// whose definition currently wins. A view redefined later supersedes the
  /// earlier body entirely, which is the whole reason this guard reads the LAST
  /// definition rather than the first.
  /// The last three were found by this guard's own completeness check on its
  /// first run — the hand-built list from migrations 156–181 missed them, which
  /// is precisely why that check exists rather than a static count.
  const adminViews = <String, String>{
    'admin_audit_events': '156',
    'admin_training_overview': '156',
    'admin_integration_connections': '157',
    'admin_security_events': '159',
    'admin_user_directory': '160',
    'admin_incidents': '160',
    'admin_events_overview': '172',
    'admin_community_overview': '172',
    'admin_release_status': '174',
    'admin_user_overview': '179',
    'admin_revenue_overview': '180',
    'admin_activity_overview': '181',
  };

  /// The body of a view's LAST definition, bounded by the next TOP-LEVEL
  /// statement rather than by the next semicolon.
  ///
  /// THE BOUNDARY MATTERS, and getting it wrong is not hypothetical. A
  /// non-greedy `(.*?);` — the form used by the sibling guard, which is safe for
  /// its short single-table views — truncates at the first semicolon INSIDE the
  /// body. `admin_revenue_overview` is 6134 characters with CTEs, and its
  /// `WHERE public.admin_can('Monetization','view')` sits on the final line. A
  /// first-semicolon match returns a fragment that omits the gate and reports a
  /// security regression that does not exist. That false positive was produced
  /// while writing this guard, which is why the boundary is anchored here.
  ({String file, String body})? lastDefinitionOf(String view) {
    ({String file, String body})? found;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    // `OR REPLACE` optional, matching the completeness sweep below. If that
    // sweep ever surfaces a plain `CREATE VIEW admin_foo`, this must be able to
    // read it — otherwise the new view fails with a misleading "no definition
    // anywhere" instead of its real posture.
    final start = RegExp(
        'CREATE\\s+(?:OR\\s+REPLACE\\s+)?VIEW\\s+(?:public\\.)?$view\\b',
        caseSensitive: false);
    // A new statement begins at column 0 with one of these keywords.
    final nextStatement = RegExp(
        r'\n(?=(COMMENT|GRANT|REVOKE|CREATE|ALTER|DROP|DO)\b)',
        caseSensitive: false);
    for (final f in files) {
      final text = f.readAsStringSync();
      for (final m in start.allMatches(text)) {
        final rest = text.substring(m.start);
        final end = nextStatement.firstMatch(rest.substring(1));
        found = (
          file: f.path.split('/').last,
          body: end == null ? rest : rest.substring(0, end.start + 1),
        );
      }
    }
    return found;
  }

  /// SQL with `--` line comments and `/* */` blocks removed.
  ///
  /// The predicate checks below MUST run against code, not prose. These
  /// migrations are heavily commented and several of them describe their own
  /// gate in words — `174:55` and `180:196` both contain the literal text
  /// `Gated admin_can('…','…')`. Testing the raw body therefore admits a proven
  /// false negative: delete the real `WHERE public.admin_can(...)`, leave a
  /// comment mentioning it, and a raw-text check still passes. That was
  /// demonstrated against `admin_release_status`'s real body — raw match `true`,
  /// comment-stripped match `false` — so the strip is what makes the assertion
  /// mean anything.
  ///
  /// It also removes a false POSITIVE: a comment warning "never use
  /// security_invoker = on" no longer trips the negative assertion.
  String codeOf(String body) => body
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'--[^\n]*'), '');

  group('Admin views keep the gate their RLS bypass depends on', () {
    test('the migration directory is readable and non-trivial', () {
      // Without this, every assertion below could pass by finding nothing.
      expect(dir.existsSync(), isTrue, reason: 'migrations not at ${dir.path}');
      final count = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .length;
      expect(count, greaterThan(150),
          reason: 'only $count migrations found — the sweep is not seeing the tree');
    });

    for (final entry in adminViews.entries) {
      final view = entry.key;
      final expectedMigration = entry.value;

      test('$view is gated and still bypasses RLS deliberately', () {
        final def = lastDefinitionOf(view);
        expect(def, isNotNull,
            reason: '$view has no CREATE OR REPLACE VIEW anywhere. Either it was '
                'renamed or dropped — in both cases this guard is now lying and '
                'must be updated deliberately, not deleted.');

        expect(def!.file, startsWith(expectedMigration),
            reason: "$view's winning definition moved to ${def.file}. That is "
                'allowed, but the new definition must be re-read by a human: '
                'CREATE OR REPLACE replaces the whole body, gate included.');

        // Predicates are asserted against CODE, never prose — see codeOf().
        final code = codeOf(def.body);

        expect(RegExp(r'security_invoker\s*=\s*off', caseSensitive: false)
            .hasMatch(code), isTrue,
            reason: '$view (${def.file}) no longer declares security_invoker = off.');

        expect(RegExp(r'security_invoker\s*=\s*on', caseSensitive: false)
            .hasMatch(code), isFalse,
            reason: '$view (${def.file}) declares security_invoker = on. The Admin '
                'layer aggregates across users, so per-row RLS makes it return an '
                'empty result rather than a denial — a silent wrong answer.');

        expect(RegExp(r'admin_can\s*\(', caseSensitive: false).hasMatch(code),
            isTrue,
            reason: '$view (${def.file}) bypasses RLS and carries NO admin_can '
                'predicate IN CODE — a comment that merely mentions one does not '
                'count. With security_invoker = off and no gate, any authenticated '
                'caller reads the whole base table. This is the regression this '
                'guard exists to catch.');
      });
    }

    test('the body extractor does not truncate at an inner semicolon', () {
      // A direct regression test for the bug that produced a false positive
      // while this guard was being written. admin_revenue_overview's gate is on
      // its last line, thousands of characters past the first inner semicolon.
      final def = lastDefinitionOf('admin_revenue_overview');
      expect(def, isNotNull);
      expect(def!.body.length, greaterThan(2000),
          reason: 'extracted only ${def.body.length} chars — the boundary '
              'collapsed, and every admin_can assertion above is now capable of '
              'failing for a view that is correctly gated');
      expect(def.body, contains("admin_can('Monetization'"),
          reason: 'the gate on the final line was not captured');
    });

    test('a gate mentioned only in a comment does not satisfy the check', () {
      // Regression test for a proven false negative in this guard's first
      // version, which matched the raw body. Delete the real predicate, leave a
      // comment naming it, and the raw check still passed — so the assertion
      // was satisfiable by prose. codeOf() is what closes that.
      final def = lastDefinitionOf('admin_release_status');
      expect(def, isNotNull);

      final masked = def!.body.replaceAll(
          RegExp(r'WHERE\s+public\.admin_can\([^)]*\)\s*;?', caseSensitive: false),
          "-- gate was here: admin_can('System','view')\n;");

      final gate = RegExp(r'admin_can\s*\(', caseSensitive: false);
      expect(gate.hasMatch(masked), isTrue,
          reason: 'premise: the comment does mention admin_can, so a raw-text '
              'check would pass. If this is false the probe is inert.');
      expect(gate.hasMatch(codeOf(masked)), isFalse,
          reason: 'codeOf() must strip the comment so the gate check fails. If '
              'this passes, the guard is once again satisfiable by prose.');
    });

    test('no Admin view is missing from this guard', () {
      // If a new security_invoker = off Admin view is added, it must be listed
      // above rather than silently unguarded.
      final declared = adminViews.keys.toSet();
      final discovered = <String>{};
      for (final f in dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))) {
        for (final m in RegExp(
                // `OR REPLACE` optional: every Admin view uses it today, but a
                // plain `CREATE VIEW admin_foo` would otherwise be invisible to
                // this sweep, and so silently unguarded.
                r'CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(?:public\.)?(admin_[a-z_]+)',
                caseSensitive: false)
            .allMatches(f.readAsStringSync())) {
          discovered.add(m.group(1)!.toLowerCase());
        }
      }
      expect(discovered.difference(declared), isEmpty,
          reason: 'Admin views exist that this guard does not cover: '
              '${discovered.difference(declared).join(', ')}. Add them above '
              'with their winning migration, or state why they are exempt.');
    });
  });
}
