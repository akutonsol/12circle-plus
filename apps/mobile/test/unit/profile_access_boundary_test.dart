// SEC-010 … SEC-017 — user_profiles access boundary (migrations 100/101/102/110).
//
// Migration 102 is the migration that closes the user_profiles hole: after it,
// the base table is readable only by the owner, their active coach, their team
// lead and an event host. Two app surfaces used to read the base table for a
// display name (messaging) or an email (community member discovery), and the
// tempting repairs -- re-adding `USING (true)`, or projecting email through
// public_profiles -- would each undo more than 102 gains.
//
// These tests are a standing guard against exactly those regressions. They are
// static: they parse the committed SQL and the committed Dart, so a regression
// fails `flutter test` before anything is applied to a database. Live RLS
// enforcement is separately the job of the QA integration pass -- what is
// asserted here is that the *committed source* cannot express the hole.
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

String _migration(String fileName) {
  final f = File('${_repoRoot().path}/supabase/migrations/$fileName');
  if (!f.existsSync()) throw StateError('$fileName should exist');
  return f.readAsStringSync();
}

/// Every migration file, keyed by its numeric prefix.
Map<int, ({String name, String sql})> _allMigrations() {
  final dir = Directory('${_repoRoot().path}/supabase/migrations');
  final out = <int, ({String name, String sql})>{};
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.sql')) continue;
    final n = int.tryParse(name.split('_').first);
    if (n == null) continue;
    out[n] = (name: name, sql: f.readAsStringSync());
  }
  return out;
}

// ── SQL text handling ────────────────────────────────────────────────────────

/// Strips `--` line comments so an assertion about SQL never matches prose.
/// Migration 102 ends with a commented-out rollback that contains a literal
/// `USING (true)`; without this every blanket-policy test would false-positive.
String _stripComments(String sql) => sql
    .split('\n')
    .map((line) {
      final i = line.indexOf('--');
      return i == -1 ? line : line.substring(0, i);
    })
    .join('\n');

/// Collapses whitespace so multi-line statements can be matched with one regex.
String _flat(String sql) => _stripComments(sql).replaceAll(RegExp(r'\s+'), ' ');

/// The body of a `CREATE [OR REPLACE] VIEW <name> ... ;` statement, comments out.
String _viewBody(String sql, String viewName) {
  final stripped = _stripComments(sql);
  final start = stripped.indexOf(RegExp('CREATE\\s+(OR\\s+REPLACE\\s+)?VIEW\\s+$viewName'));
  if (start < 0) throw StateError('view $viewName should be declared');
  final end = stripped.indexOf(';', start);
  if (end <= start) throw StateError('view $viewName statement should terminate');
  return stripped.substring(start, end);
}

/// Columns that must never leave user_profiles through a view granted to
/// `authenticated`. `email` heads the list: it is the one the community fix was
/// tempted to add.
const _sensitiveProfileColumns = <String>[
  'email',
  'phone',
  'date_of_birth',
  'medical_conditions',
  'parq_answers',
  'injury_description',
  'risk_score',
  'stripe_customer_id',
  'stripe_account_id',
];

// ── Executable model of the SQL authorization predicates ─────────────────────
//
// A mirror of the two predicates the design turns on, so the intended behaviour
// is asserted as behaviour and not only as matched SQL text. The SQL itself is
// checked to still say this, further down.

class Conversation {
  final String participant1;
  final String participant2;
  const Conversation(this.participant1, this.participant2);
}

/// Mirrors `public.shares_conversation_with(target_user uuid)`.
/// `caller == null` models an anonymous request, where auth.uid() is NULL and
/// every comparison collapses to NULL, so EXISTS is false.
bool sharesConversationWith(
  String? caller,
  String target,
  List<Conversation> conversations,
) {
  if (caller == null) return false;
  return conversations.any((c) =>
      (c.participant1 == caller && c.participant2 == target) ||
      (c.participant2 == caller && c.participant1 == target));
}

/// The five columns conversation_participant_profiles projects.
const _messagingColumns = {'id', 'first_name', 'last_name', 'role', 'avatar_url'};

/// Mirrors a SELECT against `conversation_participant_profiles`: rows filtered
/// by the predicate, columns fixed by the view definition.
List<Map<String, String>> readConversationParticipantProfiles({
  required String? caller,
  required List<String> requestedIds,
  required List<Conversation> conversations,
  required Map<String, Map<String, String>> profiles,
}) {
  final out = <Map<String, String>>[];
  for (final id in requestedIds) {
    if (!sharesConversationWith(caller, id, conversations)) continue;
    final row = profiles[id];
    if (row == null) continue;
    out.add({
      for (final e in row.entries)
        if (_messagingColumns.contains(e.key)) e.key: e.value,
    });
  }
  return out;
}

/// Mirrors the post-102 SELECT policy on user_profiles.
bool canReadUserProfileRow({
  required String? caller,
  required String rowOwner,
  Set<String> activeClientsOfCaller = const {},
  Set<String> teamMembersOfCaller = const {},
  Set<String> eventAttendeesOfCaller = const {},
}) {
  if (caller == null) return false;
  return caller == rowOwner ||
      activeClientsOfCaller.contains(rowOwner) ||
      teamMembersOfCaller.contains(rowOwner) ||
      eventAttendeesOfCaller.contains(rowOwner);
}

void main() {
  final m102 = _migration('102_restrict_user_profiles.sql');
  final m110 = _migration('110_profile_demo_flag.sql');
  final flat102 = _flat(m102);
  final flat110 = _flat(m110);
  final repo = _repoRoot();
  final mobile = _mobileRoot();

  // ══════════════════════════════════════════════════════════════════════════
  // SEC-010 — migration 102 does not restore blanket authenticated access
  // ══════════════════════════════════════════════════════════════════════════
  group('SEC-010 migration 102 grants no blanket read of user_profiles', () {
    test('drops both live blanket policies by name', () {
      expect(flat102, contains('DROP POLICY IF EXISTS "authenticated_read_profiles" ON public.user_profiles'));
      expect(
        flat102,
        contains('DROP POLICY IF EXISTS "profiles are viewable by authenticated users" ON public.user_profiles'),
      );
    });

    test('creates no USING (true) policy on user_profiles', () {
      final blanket = RegExp(
        r'CREATE POLICY [^;]*?ON (public\.)?user_profiles[^;]*?USING\s*\(\s*true\s*\)',
        caseSensitive: false,
      );
      expect(blanket.hasMatch(flat102), isFalse,
          reason: 'a USING (true) SELECT policy on user_profiles is the hole 102 exists to close');
    });

    test('the SELECT policy is scoped to the four authorized relationships', () {
      final policy = RegExp(
        r'CREATE POLICY "own profile or active coach reads profile" ON public\.user_profiles FOR SELECT TO authenticated USING \(([^;]*?)\);',
      ).firstMatch(flat102);
      expect(policy, isNotNull, reason: 'the restrictive SELECT policy should exist');
      final using = policy!.group(1)!;
      expect(using, contains('id = auth.uid()'));
      expect(using, contains('public.is_active_coach_of(id)'));
      expect(using, contains('public.is_team_lead_of(id)'));
      expect(using, contains('public.hosts_event_for(id)'));
      expect(using, isNot(contains('true')));
    });

    test('the base-table policy is NOT widened for messaging', () {
      // The conversation predicate deliberately does not appear in the policy:
      // a row grant would hand a conversation partner medical_conditions,
      // parq_answers, email and the Stripe ids along with the display name.
      final policy = RegExp(
        r'CREATE POLICY "own profile or active coach reads profile" ON public\.user_profiles FOR SELECT TO authenticated USING \(([^;]*?)\);',
      ).firstMatch(flat102)!;
      expect(policy.group(1)!, isNot(contains('shares_conversation_with')),
          reason: 'messaging is served by a column-limited view, not by a row grant');
    });

    test('no migration after 102 re-opens user_profiles for SELECT', () {
      final blanket = RegExp(
        r'CREATE POLICY [^;]*?ON (public\.)?user_profiles[^;]*?FOR SELECT[^;]*?USING\s*\(\s*true\s*\)',
        caseSensitive: false,
      );
      _allMigrations().forEach((n, mig) {
        if (n <= 102) return;
        expect(blanket.hasMatch(_flat(mig.sql)), isFalse,
            reason: '${mig.name} must not restore blanket SELECT on user_profiles');
      });
    });

    test('every historical blanket policy is dropped by 102', () {
      // Migration 015 created "profiles are viewable by authenticated users"
      // with USING (true). Any such policy must be named in a DROP at 102+,
      // or it survives the hardening.
      final create = RegExp(
        r'CREATE POLICY "([^"]+)"\s+ON (?:public\.)?user_profiles\s+FOR SELECT[^;]*?USING\s*\(\s*true\s*\)',
        caseSensitive: false,
      );
      final migrations = _allMigrations();
      final blanketNames = <String, String>{}; // policy name -> migration
      migrations.forEach((n, mig) {
        for (final match in create.allMatches(_flat(mig.sql))) {
          blanketNames[match.group(1)!] = mig.name;
        }
      });
      expect(blanketNames, isNotEmpty,
          reason: 'migration 015 should still be the historical source of the hole');

      final droppedAt102Plus = migrations.entries
          .where((e) => e.key >= 102)
          .map((e) => _flat(e.value.sql))
          .join('\n');
      for (final entry in blanketNames.entries) {
        expect(
          droppedAt102Plus,
          contains('DROP POLICY IF EXISTS "${entry.key}" ON public.user_profiles'),
          reason: 'blanket policy "${entry.key}" from ${entry.value} is never dropped',
        );
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SEC-011 — the conversation-participant authorization path exists in SQL
  // ══════════════════════════════════════════════════════════════════════════
  group('SEC-011 shares_conversation_with() is a hardened SECURITY DEFINER predicate', () {
    late String fn;

    setUpAll(() {
      final start = flat102.indexOf('CREATE OR REPLACE FUNCTION public.shares_conversation_with');
      expect(start, greaterThanOrEqualTo(0), reason: 'the predicate should be declared in 102');
      fn = flat102.substring(start, flat102.indexOf(r'$$;', start));
    });

    test('returns boolean, STABLE, SECURITY DEFINER, pinned search_path', () {
      expect(fn, contains('RETURNS boolean'));
      expect(fn, contains('STABLE'));
      expect(fn, contains('SECURITY DEFINER'));
      expect(fn, contains('SET search_path = public'),
          reason: 'an unpinned search_path on a definer function is hijackable');
    });

    test('resolves membership symmetrically against public.conversations', () {
      expect(fn, contains('FROM public.conversations'));
      expect(fn, contains('c.participant_1 = auth.uid() AND c.participant_2 = target_user'));
      expect(fn, contains('c.participant_2 = auth.uid() AND c.participant_1 = target_user'));
    });

    test('returns only an EXISTS boolean — never a conversation or message row', () {
      expect(fn, contains('SELECT EXISTS'));
      expect(fn, isNot(contains('messages')),
          reason: 'the predicate must not touch message content');
    });

    test('execute is revoked from PUBLIC and granted only to authenticated', () {
      expect(flat102, contains('REVOKE ALL ON FUNCTION public.shares_conversation_with(uuid) FROM PUBLIC'));
      expect(flat102, contains('GRANT EXECUTE ON FUNCTION public.shares_conversation_with(uuid) TO authenticated'));
      expect(flat102, isNot(contains('GRANT EXECUTE ON FUNCTION public.shares_conversation_with(uuid) TO anon')));
    });

    test('is declared before the policy swap that depends on it', () {
      expect(
        flat102.indexOf('CREATE OR REPLACE FUNCTION public.shares_conversation_with'),
        lessThan(flat102.indexOf('CREATE POLICY "own profile or active coach reads profile"')),
        reason: '102 must be self-contained: no window where the app has no path at all',
      );
    });
  });

  group('SEC-011 conversation_participant_profiles is minimal and row-scoped', () {
    late String body;

    setUpAll(() => body = _viewBody(m102, r'public\.conversation_participant_profiles'));

    test('is row-scoped by the membership predicate', () {
      expect(_flat(body), contains('WHERE public.shares_conversation_with(p.id)'),
          reason: 'without the predicate the view is a blanket profile directory');
    });

    test('projects exactly the five display columns messaging needs', () {
      final selected = RegExp(r'p\.([a-z_]+)')
          .allMatches(_flat(body))
          .map((m) => m.group(1)!)
          .toSet()
        ..remove('id'); // also appears in the WHERE predicate
      expect({...selected, 'id'}, equals(_messagingColumns));
    });

    test('projects no sensitive column', () {
      final flatBody = _flat(body);
      for (final col in _sensitiveProfileColumns) {
        expect(flatBody, isNot(contains(col)),
            reason: '$col must never reach a conversation partner');
      }
    });

    test('reads as owner but is a security barrier', () {
      final flatBody = _flat(body);
      expect(flatBody, contains('security_invoker = off'),
          reason: 'the view must be unaffected by the row restriction on the base table');
      expect(flatBody, contains('security_barrier = true'),
          reason: 'a caller-supplied filter must not run ahead of the membership check');
    });

    test('is granted to authenticated only, never anon', () {
      expect(flat102, contains('REVOKE ALL ON public.conversation_participant_profiles FROM PUBLIC, anon'));
      expect(flat102, contains('GRANT SELECT ON public.conversation_participant_profiles TO authenticated'));
      expect(flat102, isNot(contains('GRANT SELECT ON public.conversation_participant_profiles TO anon')));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SEC-012 — behaviour of the authorization model
  // ══════════════════════════════════════════════════════════════════════════
  group('SEC-012 authorization behaviour', () {
    const alice = 'alice';
    const bob = 'bob';
    const mallory = 'mallory';
    const coach = 'coach';

    const conversations = [Conversation(alice, bob)];

    final profiles = <String, Map<String, String>>{
      bob: {
        'id': bob,
        'first_name': 'Bob',
        'last_name': 'Reyes',
        'role': 'client',
        'avatar_url': 'https://cdn/bob.png',
        // deliberately present in the fixture: the view must drop these
        'email': 'bob@example.com',
        'phone': '+15550001111',
        'medical_conditions': 'asthma',
        'risk_score': '7',
        'stripe_customer_id': 'cus_123',
      },
    };

    test('unauthorized users cannot read arbitrary user_profiles rows', () {
      expect(canReadUserProfileRow(caller: mallory, rowOwner: bob), isFalse);
      expect(canReadUserProfileRow(caller: alice, rowOwner: bob), isFalse,
          reason: 'sharing a conversation does not grant the base-table row');
      expect(canReadUserProfileRow(caller: null, rowOwner: bob), isFalse);
    });

    test('the owner and their active coach still read the base-table row', () {
      expect(canReadUserProfileRow(caller: bob, rowOwner: bob), isTrue);
      expect(
        canReadUserProfileRow(caller: coach, rowOwner: bob, activeClientsOfCaller: {bob}),
        isTrue,
      );
      expect(
        canReadUserProfileRow(caller: coach, rowOwner: bob, activeClientsOfCaller: const {}),
        isFalse,
        reason: 'a coach with no active relationship is just another authenticated user',
      );
    });

    test('a conversation participant obtains the profile info messaging needs', () {
      final rows = readConversationParticipantProfiles(
        caller: alice,
        requestedIds: [bob],
        conversations: conversations,
        profiles: profiles,
      );
      expect(rows, hasLength(1));
      expect(rows.single['first_name'], 'Bob');
      expect(rows.single['last_name'], 'Reyes');
      expect(rows.single['avatar_url'], isNotNull);
      expect(rows.single['role'], 'client');
    });

    test('and obtains nothing beyond it', () {
      final row = readConversationParticipantProfiles(
        caller: alice,
        requestedIds: [bob],
        conversations: conversations,
        profiles: profiles,
      ).single;
      expect(row.keys.toSet(), equals(_messagingColumns));
      for (final col in _sensitiveProfileColumns) {
        expect(row.containsKey(col), isFalse, reason: '$col leaked to a conversation partner');
      }
    });

    test('unrelated users cannot obtain that information', () {
      expect(
        readConversationParticipantProfiles(
          caller: mallory,
          requestedIds: [bob],
          conversations: conversations,
          profiles: profiles,
        ),
        isEmpty,
        reason: 'an id smuggled into the filter must not resolve for a non-participant',
      );
    });

    test('the predicate is symmetric — either participant may look up the other', () {
      expect(sharesConversationWith(alice, bob, conversations), isTrue);
      expect(sharesConversationWith(bob, alice, conversations), isTrue);
    });

    test('anonymous callers resolve nothing', () {
      expect(sharesConversationWith(null, bob, conversations), isFalse);
      expect(
        readConversationParticipantProfiles(
          caller: null,
          requestedIds: [bob],
          conversations: conversations,
          profiles: profiles,
        ),
        isEmpty,
      );
    });

    test('ending the conversation ends the access', () {
      expect(
        readConversationParticipantProfiles(
          caller: alice,
          requestedIds: [bob],
          conversations: const [],
          profiles: profiles,
        ),
        isEmpty,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SEC-013 — public_profiles never exposes email
  // ══════════════════════════════════════════════════════════════════════════
  group('SEC-013 public_profiles exposes no sensitive column', () {
    test('migration 101 declaration is clean', () {
      final body = _flat(_viewBody(_migration('101_public_profiles_view.sql'), r'public\.public_profiles'));
      for (final col in _sensitiveProfileColumns) {
        expect(body, isNot(contains(col)), reason: '101 projects $col');
      }
    });

    test('migration 110 re-declaration is still clean', () {
      final body = _flat(_viewBody(m110, r'public\.public_profiles'));
      for (final col in _sensitiveProfileColumns) {
        expect(body, isNot(contains(col)),
            reason: '110 projects $col — the community fix must not buy discovery with email');
      }
    });

    test('no migration ever adds email to public_profiles', () {
      final addsEmail = RegExp(
        r'CREATE\s+(OR\s+REPLACE\s+)?VIEW\s+(public\.)?public_profiles[^;]*?\bemail\b',
        caseSensitive: false,
      );
      _allMigrations().forEach((n, mig) {
        expect(addsEmail.hasMatch(_flat(mig.sql)), isFalse,
            reason: '${mig.name} adds email to public_profiles');
      });
    });

    test('110 only appends columns, so CREATE OR REPLACE VIEW stays legal', () {
      // OR REPLACE may add trailing columns but may not reorder/rename/drop.
      List<String> cols(String body) => body
          .split('\n')
          .map((l) => l.trim().replaceAll(',', ''))
          .where((l) => RegExp(r'^[a-z_]+$').hasMatch(l))
          .toList();
      final before = cols(_stripComments(
          _viewBody(_migration('101_public_profiles_view.sql'), r'public\.public_profiles')));
      final after = cols(_stripComments(_viewBody(m110, r'public\.public_profiles')));
      expect(before, isNotEmpty);
      expect(after.sublist(0, before.length), equals(before),
          reason: 'existing columns must keep their exact positions');
      expect(after.sublist(before.length), equals(['created_at', 'is_demo']));
    });

    test('the view is granted to authenticated only, never anon', () {
      expect(flat110, contains('REVOKE ALL ON public.public_profiles FROM PUBLIC, anon'));
      expect(flat110, contains('GRANT SELECT ON public.public_profiles TO authenticated'));
      expect(flat110, isNot(contains('GRANT SELECT ON public.public_profiles TO anon')));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SEC-014 — demo/test accounts are excluded without reading email
  // ══════════════════════════════════════════════════════════════════════════
  group('SEC-014 is_demo is the fixture filter', () {
    test('110 adds the flag as a non-null boolean defaulting to false', () {
      expect(
        flat110,
        contains('ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false'),
        reason: 'a nullable flag would make `is_demo = false` silently drop real members',
      );
    });

    test('110 projects is_demo and created_at through public_profiles', () {
      final body = _flat(_viewBody(m110, r'public\.public_profiles'));
      expect(body, contains('is_demo'));
      expect(body, contains('created_at'));
    });

    test('the email pattern survives only as a one-time backfill', () {
      expect(flat110, contains("SET is_demo = true WHERE lower(email) LIKE '%@marketplace.test'"));
      // The backfill is idempotent and never clears a flag someone set.
      expect(flat110, contains('is_demo IS DISTINCT FROM true'));
      expect(flat110, isNot(contains('SET is_demo = false')));
    });

    test('the seed flags its demo coaches explicitly', () {
      // The backfill runs during the migration replay, i.e. BEFORE the seed
      // inserts these rows, so the seed has to set the flag itself.
      final seed = File('${repo.path}/supabase/seeds/full_test_data.sql').readAsStringSync();
      expect(_flat(seed), contains('UPDATE user_profiles SET is_demo = true'));
      for (final v in ['v_coach_sarah', 'v_coach_marcus', 'v_coach_priya', 'v_coach_derek', 'v_coach_natasha']) {
        expect(_flat(seed), contains(v));
      }
    });

    test('community members are filtered by is_demo, not by email', () {
      const rows = [
        {'first_name': 'Maria', 'is_demo': false},
        {'first_name': 'Sarah', 'is_demo': true},
        {'first_name': 'Marcus', 'is_demo': true},
        {'first_name': 'Jordan', 'is_demo': false},
      ];
      final visible = rows.where((r) => r['is_demo'] == false).toList();
      expect(visible, hasLength(2), reason: 'community member discovery still returns real members');
      expect(visible.map((r) => r['first_name']), containsAll(['Maria', 'Jordan']));
      for (final r in rows) {
        expect(r.containsKey('email'), isFalse,
            reason: 'the discovery projection carries no email to filter on');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SEC-015 — the app reads the scoped paths, not the base table
  // ══════════════════════════════════════════════════════════════════════════
  group('SEC-015 app source uses the scoped read paths', () {
    String source(String relative) {
      final f = File('${mobile.path}/$relative');
      expect(f.existsSync(), isTrue, reason: '$relative should exist');
      return f.readAsStringSync();
    }

    test('messaging reads conversation_participant_profiles', () {
      final s = source('lib/features/messaging/data/messaging_service.dart');
      expect(s, contains("from('conversation_participant_profiles')"));
      expect(s, isNot(contains("from('user_profiles')")),
          reason: 'messaging must not read the restricted base table');
    });

    test('messaging requests no sensitive column', () {
      final s = source('lib/features/messaging/data/messaging_service.dart');
      for (final col in _sensitiveProfileColumns) {
        expect(s, isNot(contains("'$col'")), reason: 'messaging selects $col');
      }
    });

    test('community member discovery reads public_profiles', () {
      final s = source('lib/features/community/domain/community_provider.dart');
      expect(s, contains("from('public_profiles')"));
      expect(s, contains(".eq('is_demo', false)"));
      expect(s, isNot(contains("from('user_profiles')")),
          reason: 'member discovery must not read the restricted base table');
    });

    test('community member discovery never touches email', () {
      final s = source('lib/features/community/domain/community_provider.dart');
      expect(s, isNot(contains("'email'")));
      expect(s, isNot(contains('marketplace.test')),
          reason: 'the address pattern belongs to the one-time backfill, not the query');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SEC-016 — local structural validation of the two migrations
  // ══════════════════════════════════════════════════════════════════════════
  group('SEC-016 migration files are structurally sound', () {
    for (final entry in {'102': '102_restrict_user_profiles.sql', '110': '110_profile_demo_flag.sql'}.entries) {
      group('migration ${entry.key}', () {
        late String sql;
        setUpAll(() => sql = _migration(entry.value));

        test(r'dollar-quoted bodies are balanced', () {
          final count = RegExp(r'\$\$').allMatches(_stripComments(sql)).length;
          expect(count.isEven, isTrue, reason: 'unbalanced \$\$ delimiters');
        });

        test('no transaction wrapper (the CLI supplies one)', () {
          final flat = _flat(sql).toUpperCase();
          expect(flat, isNot(contains('BEGIN;')));
          expect(flat, isNot(contains('COMMIT;')));
        });

        test('every statement is terminated', () {
          expect(_stripComments(sql).trimRight().endsWith(';'), isTrue);
        });

        test('touches no workout migration territory', () {
          final flat = _flat(sql);
          for (final t in ['workout_set_logs', 'workout_sessions', 'program_workouts']) {
            expect(flat, isNot(contains(t)),
                reason: '${entry.value} must not touch $t — that is 104-109 territory');
          }
        });
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SEC-018 — views must never be writable by `authenticated`
  //
  // Supabase's ALTER DEFAULT PRIVILEGES grants ALL on new relations in public to
  // authenticated, and that fires for VIEWS too. A view declared
  // security_invoker = off executes writes as its OWNER, so a writable view is a
  // straight RLS bypass on its base table. Stage B.4 confirmed this live: an
  // authenticated user who could read zero rows of another user's user_profiles
  // could still UPDATE it through public_profiles, including setting `role`.
  // Migration 112 revokes write on every view that existed then; these guards
  // make sure nothing reintroduces it.
  // ══════════════════════════════════════════════════════════════════════════
  group('SEC-018 views are read-only for authenticated', () {
    final migrations = _allMigrations();

    test('migration 112 exists and revokes write on every view', () {
      final m112 = migrations[112];
      expect(m112, isNotNull, reason: 'the view-grant fix should be migration 112');
      final flat = _flat(m112!.sql);
      expect(flat, contains("relkind IN ('v', 'm')"),
          reason: '112 should cover every view and materialized view, not a fixed list');
      expect(flat, contains('REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated'));
      expect(flat, contains('GRANT SELECT ON public.%I TO authenticated'));
    });

    test('112 does not narrow default privileges on TABLES', () {
      // Postgres has no view-only default-privilege class: `ON TABLES` covers
      // tables too, so revoking write there would break every table the app
      // writes to.
      final flat = _flat(migrations[112]!.sql);
      expect(flat, isNot(contains('ALTER DEFAULT PRIVILEGES')),
          reason: 'narrowing ON TABLES defaults would strip write access from real tables');
    });

    test('no migration grants write on a view to anon or authenticated', () {
      final grantWrite = RegExp(
        r'GRANT[^;]*\b(INSERT|UPDATE|DELETE|ALL)\b[^;]*ON\s+(public\.)?'
        r'(public_profiles|conversation_participant_profiles|exercises|'
        r'exercise_certifications|coach_client_workout_stats)\b[^;]*TO[^;]*'
        r'\b(anon|authenticated)\b',
        caseSensitive: false,
      );
      migrations.forEach((n, mig) {
        expect(grantWrite.hasMatch(_flat(mig.sql)), isFalse,
            reason: '${mig.name} grants write on a view');
      });
    });

    // SEC-018 · every view created after 112 must end up with its write grants
    // revoked from `authenticated`. Supabase ships
    // `ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES TO authenticated`, so a new
    // view is BORN with INSERT/UPDATE/DELETE granted and a later GRANT SELECT does
    // not take them away.
    //
    // WHY THIS CHECKS THE CUMULATIVE END STATE RATHER THAN ONE FILE. It used to
    // require the REVOKE in the SAME migration that creates the view. That is the
    // right way to AUTHOR a migration, but it is unsatisfiable for a FORWARD-ONLY
    // remediation: when a view has already been applied to an environment, the
    // repository's own rule is that the applied file is not edited in place
    // (check-migration-hygiene.sh, on Wave 0's finding that 15 migrations edited in
    // place made "replay from empty" and "what production actually ran" diverge).
    // So a defect of exactly this kind could only ever be fixed by breaking one
    // rule or the other.
    //
    // V5 §129 is the case that forced the question: 156/157 created three Admin
    // views revoking from PUBLIC and anon but NOT authenticated, and because both
    // single-table views are auto-updatable and run security_invoker = off, a user
    // holding only the Admin-layer `viewer` role DELETED another user's row through
    // one of them. 158 revokes the grants forward.
    //
    // THE INVARIANT IS NOT RELAXED. A view with no REVOKE anywhere still fails, so
    // this test would still have gone red on 9681ff6, where 158 did not yet exist —
    // which is exactly how the defect was caught. What changed is only WHERE the
    // satisfying statement may live, and a later migration must still name the view
    // explicitly. The reason string reports which migration satisfied it, so a
    // remediation sitting far from its cause stays visible rather than silent.
    test('every view created after 112 has its write grants revoked', () {
      final createView = RegExp(
        r'CREATE\s+(OR\s+REPLACE\s+)?VIEW\s+(public\.)?([a-z_][a-z0-9_]*)',
        caseSensitive: false,
      );
      // view name -> the migration that creates it (first one wins)
      final created = <String, MapEntry<int, String>>{};
      migrations.forEach((n, mig) {
        if (n <= 112) return;
        for (final m in createView.allMatches(_flat(mig.sql))) {
          created.putIfAbsent(m.group(3)!, () => MapEntry(n, mig.name));
        }
      });

      created.forEach((view, origin) {
        final revoke = RegExp(
          'REVOKE[^;]*ON\\s+(public\\.)?$view\\b[^;]*authenticated',
          caseSensitive: false,
        );
        String? satisfiedBy;
        migrations.forEach((n, mig) {
          if (satisfiedBy != null || n < origin.key) return;
          if (revoke.hasMatch(_flat(mig.sql))) satisfiedBy = mig.name;
        });
        expect(
          satisfiedBy,
          isNotNull,
          reason: '${origin.value} creates view "$view" and NO migration at or '
              'after it revokes write from authenticated — Supabase default '
              'privileges will have granted ALL, and a security_invoker = off view '
              'over a single table is auto-updatable, so a write through it runs as '
              'the view owner and base-table RLS does not apply',
        );
        if (satisfiedBy != origin.value) {
          // Allowed, but recorded: the fix is not where the hazard was introduced.
          // ignore: avoid_print
          print('SEC-018 note: view "$view" created in ${origin.value} is revoked '
              'later, in $satisfiedBy (forward-only remediation)');
        }
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SEC-017 — standing static scan (Stage B.1 exit criteria)
  // ══════════════════════════════════════════════════════════════════════════
  group('SEC-017 static scan', () {
    const prodRef = 'nxdbooufqzkpslkcogxc';

    /// app_env.dart is the ONE place allowed to name the production project:
    /// it holds the documented `prod` build defaults. Everything else in lib/
    /// must resolve its backend from --dart-define.
    const prodRefAllowlist = <String>{'lib/core/config/app_env.dart'};

    List<File> dartSources(String relative) {
      final dir = Directory('${mobile.path}/$relative');
      if (!dir.existsSync()) return const [];
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
    }

    String rel(File f) => f.path.substring(mobile.path.length + 1);

    test('no production project ref in client code outside app_env.dart', () {
      for (final f in dartSources('lib')) {
        if (prodRefAllowlist.contains(rel(f))) continue;
        expect(f.readAsStringSync(), isNot(contains(prodRef)),
            reason: '${rel(f)} names the production project');
      }
    });

    test('no hardcoded Supabase URL in client code outside app_env.dart', () {
      final url = RegExp(r'https://[a-z0-9]{20}\.supabase\.co');
      for (final f in dartSources('lib')) {
        if (prodRefAllowlist.contains(rel(f))) continue;
        expect(url.hasMatch(f.readAsStringSync()), isFalse,
            reason: '${rel(f)} hardcodes a Supabase URL instead of reading --dart-define');
      }
    });

    test('no service-role credential in client code', () {
      final patterns = <String, String>{
        'service_role': 'a service-role key or claim',
        'SERVICE_ROLE': 'a service-role build define',
        'SUPABASE_SERVICE': 'a service-role build define',
      };
      for (final f in dartSources('lib')) {
        final s = f.readAsStringSync();
        patterns.forEach((needle, what) {
          expect(s, isNot(contains(needle)), reason: '${rel(f)} contains $what');
        });
      }
    });

    test('no migration hardcodes a Supabase project URL', () {
      // 076/080 previously baked the production URL into cron/pg_net calls.
      final url = RegExp(r'https://[a-z0-9]{20}\.supabase\.co');
      _allMigrations().forEach((n, mig) {
        expect(url.hasMatch(_stripComments(mig.sql)), isFalse,
            reason: '${mig.name} hardcodes a Supabase project URL');
      });
    });

    test('no migration names the production project', () {
      _allMigrations().forEach((n, mig) {
        expect(_stripComments(mig.sql), isNot(contains(prodRef)),
            reason: '${mig.name} names the production project');
      });
    });
  });
}
