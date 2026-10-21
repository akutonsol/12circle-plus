// SEC-030 … SEC-031 — backend reachability across EVERY caller (Workstream N).
//
// Migration 116 revoked EXECUTE on every function in `public` from PUBLIC, anon
// and authenticated, then granted it back to a named allowlist. That is the
// right shape, and `phase1_security_boundary_test.dart` SEC-024 already guards
// it — but its scan reads `apps/mobile/lib` only:
//
//     "this is the check that stops a new .rpc() call site silently 404ing in
//      production"
//
// The Flutter client is not the only caller. Supabase Edge Functions call RPCs
// too, and one of them calls with the END USER'S JWT rather than the service
// role — so it is subject to exactly the revoke SEC-024 exists to police, and
// SEC-024 cannot see it. The gap is not hypothetical: Workstream D recorded
// E-03, `enrich-exercise` "dead on arrival — migration 116 revoked its RPC",
// and that is precisely this call site.
//
// This guard extends the same reachability check to `supabase/functions`, with
// the caller's ROLE resolved per call so a service-role call (correctly
// unaffected by the revoke) is not reported as broken. The known-unreachable
// set is a SHRINKING allowlist: closing E-03 is a one-line deletion here, and a
// NEW unreachable RPC fails immediately instead of shipping as a dead feature.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

String _migration116() {
  final dir = Directory('${_repoRoot().path}/supabase/migrations');
  final f = dir
      .listSync()
      .whereType<File>()
      .firstWhere((f) => f.path.split('/').last.startsWith('116_'));
  return f.readAsStringSync();
}

/// The `authenticated` EXECUTE allowlist declared by migration 116.
Set<String> _allowlist() {
  final block = RegExp(r'allowed constant text\[\] := ARRAY\[(.*?)\];', dotAll: true)
      .firstMatch(_migration116());
  expect(block, isNotNull, reason: 'migration 116 should declare the allowlist');
  return RegExp(r"'([a-z_0-9]+)'")
      .allMatches(block!.group(1)!)
      .map((m) => m.group(1)!)
      .toSet();
}

/// One `.rpc('name')` call site in an Edge Function, with the Supabase client
/// variable it was called on.
typedef EdgeCall = ({String function, String client, String rpc});

List<EdgeCall> _edgeRpcCalls() {
  final dir = Directory('${_repoRoot().path}/supabase/functions');
  final calls = <EdgeCall>[];
  if (!dir.existsSync()) return calls;
  final callRe = RegExp(r"(\w+)\s*\.rpc\(\s*'([a-z_0-9]+)'");
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.ts')) continue;
    final fnName = e.path
        .split('/supabase/functions/')
        .last
        .split('/')
        .first;
    for (final m in callRe.allMatches(e.readAsStringSync())) {
      calls.add((function: fnName, client: m.group(1)!, rpc: m.group(2)!));
    }
  }
  return calls;
}

/// Whether a client variable in [source] was built from the service-role key.
/// A service-role caller is unaffected by migration 116 — the revokes name
/// PUBLIC, anon and authenticated only, deliberately, so the deterministic
/// engine keeps its execution path.
bool _isServiceRoleClient(String source, String variable) {
  final decl = RegExp(
      'const\\s+$variable\\s*=\\s*createClient\\(([^;]*?)\\);', dotAll: true)
      .firstMatch(source);
  if (decl == null) return false;
  return decl.group(1)!.contains('SERVICE');
}

String _edgeSource(String functionName) => File(
        '${_repoRoot().path}/supabase/functions/$functionName/index.ts')
    .readAsStringSync();

void main() {
  // ── SEC-030 · the reachability check covers every caller ──────────────────
  group('SEC-030 every RPC an Edge Function calls as the user is reachable', () {
    // Known-unreachable, tracked as Workstream D E-03. `enrich-exercise` calls
    // `seed_exercise` on a client built from the END USER'S Authorization
    // header, so it runs as `authenticated` and migration 116 took its EXECUTE
    // away. The function returns 500 "Failed to save enrichment" for every
    // caller, coach or admin.
    //
    // Remove the entry when the RPC is added to 116's allowlist (or a forward
    // migration grants it), or when the call is moved to the service-role
    // client. Do not add to this list to make a new failure go away.
    const knownUnreachable = {'seed_exercise'};

    test('no Edge Function calls an RPC the caller cannot execute', () {
      final allowed = _allowlist();
      final unreachable = <String, Set<String>>{};

      for (final c in _edgeRpcCalls()) {
        final src = _edgeSource(c.function);
        if (_isServiceRoleClient(src, c.client)) continue; // engine path, exempt
        if (allowed.contains(c.rpc)) continue;
        unreachable.putIfAbsent(c.rpc, () => <String>{}).add(c.function);
      }

      printOnFailure(unreachable.entries
          .map((e) => '  ${e.key} <- ${e.value.join(', ')}')
          .join('\n'));

      expect(unreachable.keys.toSet().difference(knownUnreachable), isEmpty,
          reason: 'these RPCs are called from an Edge Function on a user-scoped '
              'client but hold no EXECUTE grant for `authenticated` after '
              'migration 116, so every call fails at runtime. Grant it in a '
              'forward migration or call it on the service-role client — the '
              'Flutter-only scan in SEC-024 cannot see this.');

      expect(knownUnreachable.difference(unreachable.keys.toSet()), isEmpty,
          reason: 'a known-unreachable RPC is now reachable — delete it from '
              '`knownUnreachable` so the guard tightens');
    });

    test('the service-role callers are correctly exempt, and still identified',
        () {
      // If this ever flips to a user-scoped client the exemption above would
      // silently start hiding a real break, so the exemption itself is pinned.
      final serviceRoleCalls = _edgeRpcCalls()
          .where((c) => _isServiceRoleClient(_edgeSource(c.function), c.client))
          .map((c) => '${c.function}:${c.rpc}')
          .toSet();
      expect(serviceRoleCalls, {
        'ai-coaching-engine:ai_detect_patterns',
        'ai-coaching-engine:ai_adjust_nutrition',
        'enrich-exercise-content:snapshot_exercise_content',
      });
    });

    test('the engine path is never revoked from', () {
      // The exemption above is only sound while this holds.
      expect(
          RegExp(r'REVOKE[^;]*FROM[^;]*\bservice_role\b', caseSensitive: false)
              .hasMatch(_migration116()),
          isFalse);
    });
  });

  // ── SEC-031 · the two subject-scoped writers the Edge layer reaches ───────
  //
  // SEC-04 is that seven SECURITY DEFINER functions took a subject uuid as a
  // parameter and never reconciled it with auth.uid(). Migration 116 re-declared
  // five of them behind `can_act_for`. `ai_adjust_nutrition` and
  // `ai_detect_patterns` are the other two, and they are reached from
  // `ai-coaching-engine` as service_role — a path `can_act_for` deliberately
  // permits. What makes that safe is the subject, so the subject is pinned.
  group('SEC-031 the AI engine names its subject from the verified caller', () {
    late final String src = _edgeSource('ai-coaching-engine');

    test('the subject is the token holder, not a request field', () {
      expect(src, contains("createClient(SUPABASE_URL, SUPABASE_ANON_KEY"),
          reason: 'the caller is identified by their own JWT first');
      expect(src, contains('.auth.getUser()'));
      expect(RegExp(r'rpc\(\s*.ai_detect_patterns.,\s*\{\s*p_uid:\s*uid\s*\}')
          .hasMatch(src), isTrue);
      expect(RegExp(r'rpc\(\s*.ai_adjust_nutrition.,\s*\{\s*p_uid:\s*uid\s*\}')
          .hasMatch(src), isTrue);
    });

    test('a subject uuid is never read straight off the request body', () {
      // If a caller could name p_uid, the service-role client would turn
      // SEC-04 back on from outside the database, below every policy.
      expect(RegExp(r'p_uid:\s*(body|payload|req|params)\b').hasMatch(src), isFalse,
          reason: 'p_uid must derive from the verified token, never from input');
    });

    test('can_act_for keeps its service-role arm, which is what this path uses',
        () {
      expect(_migration116(),
          contains('CREATE OR REPLACE FUNCTION public.can_act_for(subject uuid)'));
      expect(_migration116(), contains('(SELECT auth.uid()) IS NULL'));
    });
  });
}
