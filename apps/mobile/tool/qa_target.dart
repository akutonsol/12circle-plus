// ENV-5 — the one place a `tool/` harness is allowed to learn where to point.
//
// Every harness under `tool/` writes: between them they hold 20+ DELETEs, and
// two will delete an `auth.users` row through the admin API when a service-role
// key is present. All three used to open with
//
//     const _url  = 'https://<production ref>.supabase.co';
//     const _anon = '<production anon key>';
//
// so an operator running the repository's own "QA certification harness" signed
// up users and wrote subscription rows into production. Their headers called the
// target "the real Supabase dev instance"; it was not.
//
// The target now comes from `QA_URL` / `QA_ANON` with **no default**, and this
// file refuses anything it cannot positively identify as the 12 Circle QA
// project. Refusal is by allowlist, not by blocklist: "is not production" is not
// the same claim as "is QA", and only the second one is safe to write against.
//
// This mirrors `supabase/tests/security/lib.mjs`, which does the same job for
// the Node suites. It is a shared file rather than three copies because three
// copies is three chances to drift, and the copy that drifts is the one that
// still says `const _url = production`.
//
//   export QA_URL=https://<qa ref>.supabase.co
//   export QA_ANON=<qa publishable/anon key>
//   dart run tool/qa_entitlements.dart
import 'dart:convert';
import 'dart:io';

/// The 12 Circle **production** project. Named here only so the refusal can say
/// what it refused. Nothing in this repository may write to it.
const String kProductionRef = 'nxdbooufqzkpslkcogxc';

/// The 12 Circle **QA** project — the only remote project these harnesses may
/// touch. Matches `supabase/config.toml`'s `project_id` and
/// `dart_defines/qa.json`.
const String kQaRef = 'eyqtldjqpgpljlqvpowh';

/// A resolved, verified harness target.
class QaTarget {
  final String url;
  final String anonKey;

  /// The project ref this target resolved to, or `local` for a local stack.
  final String ref;

  const QaTarget({required this.url, required this.anonKey, required this.ref});

  bool get isLocal => ref == 'local';

  @override
  String toString() => '$url  (ref: $ref)';
}

/// Reads the `ref` claim out of a Supabase anon/publishable JWT, so a
/// production key pasted alongside a QA URL is caught rather than used.
///
/// **Throws** [FormatException] rather than returning null for a key it cannot
/// read. This is a safety input: "I could not tell which project this key
/// belongs to" and "this key belongs to the right project" must not be the same
/// answer, because the caller acts on the second one. The earlier version of
/// this function returned null on any parse failure and the caller skipped the
/// check — an unreadable key verified as clean.
String refFromKey(String key) {
  final parts = key.split('.');
  if (parts.length != 3) {
    throw const FormatException('not a three-part JWT');
  }
  var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
  payload = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
  final Object? claims = jsonDecode(utf8.decode(base64.decode(payload)));
  if (claims is! Map) {
    throw const FormatException('JWT payload is not an object');
  }
  final ref = claims['ref'];
  if (ref == null || ref.toString().isEmpty) {
    throw const FormatException('JWT carries no "ref" claim');
  }
  return ref.toString();
}

/// [refFromKey], but a key that cannot be read refuses the run instead of
/// being waved through.
String _refFromKeyOrRefuse(String key) {
  try {
    return refFromKey(key);
  } on FormatException catch (e) {
    _refuse('QA_ANON could not be verified (${e.message}). A key whose '
        'project cannot be read is not a key that has been checked — supply '
        'the QA project\'s publishable/anon key.');
  }
}

Never _refuse(String why) {
  stderr.writeln('');
  stderr.writeln('  REFUSING TO RUN — $why');
  stderr.writeln('');
  stderr.writeln('  These harnesses write. They are only ever pointed at the');
  stderr.writeln('  12 Circle QA project ($kQaRef) or a local stack:');
  stderr.writeln('');
  stderr.writeln('    export QA_URL=https://$kQaRef.supabase.co');
  stderr.writeln('    export QA_ANON=<qa publishable/anon key>');
  stderr.writeln('');
  exit(2);
}

/// Resolves the project a `tool/` harness may write to, or exits 2.
///
/// Refuses when: `QA_URL`/`QA_ANON` are unset; the URL names production; the
/// URL names a project that is neither QA nor local; the anon key was issued
/// for a different project than the URL names; or the key is a service-role
/// key, which would bypass every policy the harness claims to be testing.
QaTarget resolveQaTarget({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final url = (env['QA_URL'] ?? '').trim();
  final anon = (env['QA_ANON'] ?? '').trim();

  if (url.isEmpty || anon.isEmpty) {
    _refuse('QA_URL and QA_ANON must both be set. There is no default: a '
        'harness that guesses its own target is how writes reach production.');
  }

  if (url.contains(kProductionRef)) {
    _refuse('$kProductionRef is the PRODUCTION project.');
  }

  final isLocal = url.contains('localhost') || url.contains('127.0.0.1');
  if (!isLocal && !url.contains(kQaRef)) {
    _refuse('QA_URL is "$url", which is neither the QA project ($kQaRef) nor '
        'a local stack. A target is QA because its ref says so — never '
        'because a variable or a filename is called "qa".');
  }

  // A service-role key bypasses RLS entirely. A harness that asserts "the
  // policy blocked this" while holding one is asserting nothing at all.
  if (anon.contains('service_role')) {
    _refuse('QA_ANON is a service-role key. Pass the publishable/anon key; '
        'service-role belongs in SERVICE_ROLE_KEY where it is used '
        'deliberately and visibly.');
  }

  // A local stack's demo key carries no `ref` claim, so the ref cross-check
  // applies to remote targets only — where it is the check that catches a
  // production key pasted under a QA URL.
  if (!isLocal) {
    final keyRef = _refFromKeyOrRefuse(anon);
    if (keyRef == kProductionRef) {
      _refuse('QA_ANON is a PRODUCTION key ($kProductionRef), whatever QA_URL '
          'says. The key carries its own project ref and it does not match.');
    }
    if (keyRef != kQaRef) {
      _refuse('QA_ANON was issued for project "$keyRef" but QA_URL names '
          '"$kQaRef". Refusing a mixed pair.');
    }
  }

  final target = QaTarget(
    url: url.endsWith('/') ? url.substring(0, url.length - 1) : url,
    anonKey: anon,
    ref: isLocal ? 'local' : kQaRef,
  );

  stdout.writeln('  target verified: $target');
  return target;
}
