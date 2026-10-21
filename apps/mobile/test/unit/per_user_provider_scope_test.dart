// QAX-SES-01 — cached per-user state must not survive a change of user.
//
// On mobile, logout only navigates to /login; the root ProviderScope lives on.
// A non-autoDispose provider that reads `auth.currentUser` WITHOUT watching an
// auth provider computes once and is served to whoever signs in next — the
// previous account's insights, nutrition goals, coach clients, streak, active
// workout. Watching `currentUserProvider` (derived from the auth stream, see
// auth_provider.dart) makes it recompute on every sign-in and sign-out.
//
// This is a CLASS guard over lib/, not a list of 12 names: a new provider with
// the same shape fails it. Comments are stripped first, so a commented-out
// `ref.watch(currentUserProvider)` cannot satisfy it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

/// The provider's initializer, from its declaration to the matching `)`.
String _initializer(String src, int start) {
  final open = src.indexOf('(', start);
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return src.substring(start, i + 1);
  }
  return src.substring(start);
}

final _cachedProvider = RegExp(
    r'^final\s+(\w+)\s*=\s*(?:Future|Stream|StateNotifier|Notifier|AsyncNotifier)Provider(?!\.autoDispose)\b',
    multiLine: true);
final _readsUser = RegExp(r'auth\.currentUser\b');
final _watchesAuth = RegExp(
    r'ref\.watch\(\s*(?:currentUserProvider|currentUserProfileProvider|authStateProvider)\b');

List<String> offenders(Directory lib) {
  final found = <String>[];
  for (final f in lib.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final src = _stripComments(f.readAsStringSync());
    for (final m in _cachedProvider.allMatches(src)) {
      final body = _initializer(src, m.start);
      if (_readsUser.hasMatch(body) && !_watchesAuth.hasMatch(body)) {
        found.add('${f.path.substring(lib.path.length + 1)}: ${m.group(1)}');
      }
    }
  }
  return found..sort();
}

void main() {
  test('self-test: the guard sees a planted offender and a planted fix', () {
    final dir = Directory.systemTemp.createTempSync('qax_ses01_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/a.dart').writeAsStringSync('''
final badProvider = FutureProvider<int>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  return 0;
});
final goodProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserProvider);
  final uid = Supabase.instance.client.auth.currentUser?.id;
  return 0;
});
final commentedProvider = FutureProvider<int>((ref) async {
  // ref.watch(currentUserProvider);
  final uid = Supabase.instance.client.auth.currentUser?.id;
  return 0;
});
final disposedProvider = FutureProvider.autoDispose<int>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  return 0;
});
''');
    expect(offenders(dir), ['a.dart: badProvider', 'a.dart: commentedProvider']);
  });

  test('no cached provider reads the current user without watching auth', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from apps/mobile');
    expect(offenders(lib), isEmpty,
        reason: 'each listed provider would serve the previous account\'s data '
            'after a mobile sign-out/sign-in: add ref.watch(currentUserProvider)');
  });
}
