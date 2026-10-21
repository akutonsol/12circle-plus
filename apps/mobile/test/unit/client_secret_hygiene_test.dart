// SEC-007 — no Anthropic secret may exist in the Flutter client.
//
// The AI integration moved behind the NestJS API. These tests are a standing
// guard on the *source* tree, so a regression is caught by `flutter test`
// before anything is built. `tool/check_web_build_secrets.sh` runs the
// equivalent check against a compiled `build/web` bundle.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Patterns that must never appear in client source.
const _forbidden = <String, String>{
  'sk-ant-': 'an Anthropic API key',
  'api.anthropic.com': 'a direct call to the Anthropic API',
  'x-api-key': 'an Anthropic-style API key header',
  'ANTHROPIC_API_KEY': 'an Anthropic API key build define',
};

/// Files allowed to mention a forbidden token, with the reason.
/// These reference the *server-side* Supabase Edge Function secret in operator
/// guidance shown to admins — they never hold or send a key.
const _allowlist = <String>{
  'lib/features/exercise_database/presentation/exercise_content_center_screen.dart',
  'lib/features/exercise_database/presentation/mie_debugger_screen.dart',
};

Directory _mobileRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('Could not locate the Flutter package root from ${Directory.current.path}');
    }
    dir = parent;
  }
  return dir;
}

void main() {
  final root = _mobileRoot();

  List<File> dartSources(String relative) {
    final dir = Directory('${root.path}/$relative');
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  String relPath(File f) =>
      f.path.substring(root.path.length + 1).replaceAll(r'\', '/');

  group('SEC-007 no Anthropic secret in the Flutter client', () {
    test('lib/ contains no Anthropic key, host or key header', () {
      final offences = <String>[];

      for (final file in dartSources('lib')) {
        final path = relPath(file);
        if (_allowlist.contains(path)) continue;

        final contents = file.readAsStringSync();
        _forbidden.forEach((pattern, description) {
          if (contents.contains(pattern)) {
            offences.add('$path contains $description ("$pattern")');
          }
        });
      }

      expect(offences, isEmpty,
          reason: 'Client source must not carry AI credentials:\n'
              '${offences.join('\n')}');
    });

    test('the build-time define files carry no Anthropic secret', () {
      final defines = Directory('${root.path}/dart_defines');
      expect(defines.existsSync(), isTrue,
          reason: 'dart_defines/ should hold the per-environment templates');

      for (final file in defines
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))) {
        final contents = file.readAsStringSync();
        for (final pattern in _forbidden.keys) {
          expect(contents.contains(pattern), isFalse,
              reason: '${relPath(file)} must not contain "$pattern"');
        }
      }
    });

    test('allowlisted files reference only the server-side secret name', () {
      for (final path in _allowlist) {
        final file = File('${root.path}/$path');
        expect(file.existsSync(), isTrue,
            reason: 'Stale allowlist entry: $path no longer exists');

        final contents = file.readAsStringSync();
        // They may name the env var in operator guidance, but must not hold a
        // key or call Anthropic directly.
        expect(contents.contains('sk-ant-'), isFalse, reason: path);
        expect(contents.contains('api.anthropic.com'), isFalse, reason: path);
        expect(contents.contains('x-api-key'), isFalse, reason: path);
      }
    });

    test('the AI nutrition client talks to the 12 Circle API, not Anthropic',
        () {
      final service = File(
        '${root.path}/lib/features/ai_nutrition/data/ai_nutrition_service.dart',
      );
      expect(service.existsSync(), isTrue);

      final contents = service.readAsStringSync();
      expect(contents, contains('/ai/nutrition/message'));
      expect(contents, contains('Authorization'));
      expect(contents, isNot(contains('anthropic')));
      expect(contents, isNot(contains('claudeApiKey')));
    });
  });
}
