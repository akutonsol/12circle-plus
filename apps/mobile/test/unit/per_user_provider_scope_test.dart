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

/// A service method declaration, two-space indented as in every data/ service.
final _method = RegExp(
    r'^\s{2}(?:static\s+)?(?:Future|Stream)<[^;{=]*?>\s+(\w+)\s*\(',
    multiLine: true);

/// Providers that hand the user read to a service but whose answer is not about
/// who is signed in.
const _exempt = {
  // Keyed by the client's id: the answer is about that client, whoever asks.
  'clientHasPaidPlanProvider',
};

/// A getter that wraps the user read (`String? get _uid => ...auth.currentUser?.id`).
/// A method that uses one reads the user without ever saying `auth.currentUser`.
final _userGetter = RegExp(
    r'(?:String\??|User\??)\s+get\s+(_?\w+)\s*(?:=>|\{)[^;]*auth\.currentUser');

/// Names of service methods that read the signed-in user, in their own body or
/// through a getter. A provider that calls one is per-user even though its own body
/// never says so, and earlier versions of this guard could not see either shape.
Set<String> userReadingMethods(Directory lib) {
  final names = <String>{};
  for (final f in lib.listSync(recursive: true).whereType<File>()) {
    final path = f.path.replaceAll('\\', '/');
    if (!path.endsWith('.dart')) continue;
    if (!(path.contains('/data/') || path.toLowerCase().contains('service'))) continue;
    final src = _stripComments(f.readAsStringSync());
    final getters = [
      for (final g in _userGetter.allMatches(src))
        RegExp('\\b${RegExp.escape(g.group(1)!)}\\b'),
    ];
    final decls = _method.allMatches(src).toList();
    for (var i = 0; i < decls.length; i++) {
      final end = i + 1 < decls.length ? decls[i + 1].start : src.length;
      final body = src.substring(decls[i].start, end);
      if (_readsUser.hasMatch(body) || getters.any((g) => g.hasMatch(body))) {
        names.add(decls[i].group(1)!);
      }
    }
  }
  return names;
}

List<String> offenders(Directory lib) {
  final found = <String>[];
  final delegating = {
    for (final n in userReadingMethods(lib)) n: RegExp('\\.${RegExp.escape(n)}\\('),
  };
  for (final f in lib.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final src = _stripComments(f.readAsStringSync());
    for (final m in _cachedProvider.allMatches(src)) {
      final body = _initializer(src, m.start);
      final readsUser = _readsUser.hasMatch(body) ||
          delegating.values.any((call) => call.hasMatch(body));
      if (readsUser &&
          !_watchesAuth.hasMatch(body) &&
          !_exempt.contains(m.group(1))) {
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

  test('self-test: a provider that delegates the user read to a service is seen',
      () {
    final dir = Directory.systemTemp.createTempSync('qax_ses01_delegate_');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/data').createSync();
    File('${dir.path}/data/svc.dart').writeAsStringSync('''
class Svc {
  Future<int> getMine() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    return 0;
  }
  Future<int> getShared() async {
    return 1;
  }
}
''');
    File('${dir.path}/b.dart').writeAsStringSync('''
final delegatingProvider = FutureProvider<int>((ref) async {
  return Svc().getMine();
});
final watchingDelegateProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserProvider);
  return Svc().getMine();
});
final sharedProvider = FutureProvider<int>((ref) async {
  return Svc().getShared();
});
final clientHasPaidPlanProvider = FutureProvider.family<int, String>((ref, id) async {
  return Svc().getMine();
});
''');
    expect(offenders(dir), ['b.dart: delegatingProvider']);
  });

  test('self-test: a user read hidden behind a getter is seen', () {
    final dir = Directory.systemTemp.createTempSync('qax_ses01_getter_');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/data').createSync();
    File('${dir.path}/data/svc.dart').writeAsStringSync('''
class Svc {
  String? get _uid => Supabase.instance.client.auth.currentUser?.id;
  Future<int> getMine() async {
    final uid = _uid;
    return 0;
  }
}
''');
    File('${dir.path}/c.dart').writeAsStringSync('''
final getterProvider = FutureProvider<int>((ref) async {
  return Svc().getMine();
});
final watchingGetterProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserProvider);
  return Svc().getMine();
});
''');
    expect(offenders(dir), ['c.dart: getterProvider']);
  });

  test('no cached provider reads the current user without watching auth', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from apps/mobile');
    expect(offenders(lib), isEmpty,
        reason: 'each listed provider would serve the previous account\'s data '
            'after a mobile sign-out/sign-in: add ref.watch(currentUserProvider)');
  });
}
