// REL-3 — QA tooling must not ship in a release build.
//
// `/qa-center` and `/mie-debugger` were registered unconditionally in the
// shipping router. `QaCenterScreen` checks `kReleaseMode` inside its own
// `build` and draws a placeholder, but a screen that declines to draw is not a
// route that declines to exist: the path still resolved, still showed up in the
// web URL bar, and `MieDebuggerScreen` — which reads decision traces — had no
// check of any kind.
//
// `kReleaseMode` is a compile-time constant, so a debug test binary cannot flip
// it. `buildQaToolingRoutes` takes the flag as a parameter for exactly that
// reason, and these tests drive the REAL route-building code with it set both
// ways — including through a real GoRouter, so what is asserted is resolution
// behaviour and not just a list length.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'dart:io';

import 'package:circle_fitness/core/router/app_router.dart';

Directory _mobileRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) fail('Could not locate the Flutter package root');
    dir = parent;
  }
  return dir;
}

String _read(String relative) =>
    File('${_mobileRoot().path}/$relative').readAsStringSync();

Iterable<File> _dartFilesUnder(String relative) sync* {
  final dir = Directory('${_mobileRoot().path}/$relative');
  if (!dir.existsSync()) return;
  for (final e in dir.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

/// A router with nothing in it but a home route and whatever the gate allows.
GoRouter _router({required bool qaEnabled}) => GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
        ...buildQaToolingRoutes(enabled: qaEnabled),
      ],
      errorBuilder: (_, state) =>
          Scaffold(body: Text('NO ROUTE: ${state.uri.path}')),
    );

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  group('REL-3 a release build registers no QA route', () {
    test('the gate is driven by kReleaseMode, not kDebugMode', () {
      // Profile builds are used for on-device performance work, where the
      // debugger is wanted. Release is the only mode that must lose it.
      expect(kQaToolingEnabled, isTrue,
          reason: 'a debug test binary should have QA tooling enabled');
    });

    test('the gate is defined as !kReleaseMode in source (QAX mutation finding)', () {
      // The runtime assertion above cannot tell the difference: a test binary
      // is a debug build, so `true`, `kDebugMode` and `!kReleaseMode` all
      // evaluate to true here. Run 2 of the QA exhaustion proved it — changing
      // the gate to `=> true` (QA tooling shipped in RELEASE builds) passed this
      // whole file. kReleaseMode is a compile-time constant a test cannot flip,
      // so the contract is pinned in source, with comments stripped first.
      final src = File('lib/core/router/app_router.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .split('\n')
          .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
          .join('\n');
      final gate = RegExp(r'bool\s+get\s+kQaToolingEnabled\s*=>\s*([^;]+);')
          .allMatches(src)
          .toList();
      expect(gate, hasLength(1), reason: 'exactly one definition of the gate');
      expect(gate.single.group(1)!.trim(), '!kReleaseMode');
    });

    test('release excludes every debug-only path', () {
      expect(buildQaToolingRoutes(enabled: false), isEmpty);
    });

    test('debug includes exactly the recorded debug-only paths', () {
      final paths = buildQaToolingRoutes(enabled: true)
          .cast<GoRoute>()
          .map((r) => r.path)
          .toList();
      expect(paths, unorderedEquals(kDebugOnlyRoutePaths));
      expect(kDebugOnlyRoutePaths, containsAll(['/qa-center', '/mie-debugger']));
    });

    for (final path in kDebugOnlyRoutePaths) {
      testWidgets('release: $path does not resolve', (tester) async {
        final router = _router(qaEnabled: false);
        router.go(path);
        await _pump(tester, router);

        // The behavioural assertion: navigation lands on the error page,
        // because no such route exists to match.
        expect(find.text('NO ROUTE: $path'), findsOneWidget,
            reason: '$path resolved in a release-mode router');
      });
    }

    testWidgets('debug: /qa-center still resolves, so the gate is the only '
        'thing removing it', (tester) async {
      // Guards against the false pass where the routes are broken for some
      // unrelated reason and "release excludes them" holds vacuously.
      final router = _router(qaEnabled: true);
      router.go('/qa-center');
      await _pump(tester, router);
      expect(find.text('NO ROUTE: /qa-center'), findsNothing);
    });
  });

  group('REL-3 no affordance survives the route it points at', () {
    // A tile that pushes an unregistered path is a dead end in the shipping
    // build. Source-level, because reaching these screens needs a signed-in
    // session and a populated backend.
    const entryPoints = {
      'lib/features/settings/presentation/settings_screen.dart': '/qa-center',
      'lib/features/exercise_database/presentation/exercise_content_center_screen.dart':
          '/mie-debugger',
    };

    test('every screen that pushes a debug-only path gates on the same flag',
        () {
      entryPoints.forEach((relative, path) {
        final src = _read(relative);
        expect(src, contains("context.push('$path')"),
            reason: '$relative no longer pushes $path — update this test');
        expect(src, contains('kQaToolingEnabled'),
            reason: '$relative pushes the debug-only path $path but does not '
                'gate on kQaToolingEnabled, so a release build shows an '
                'affordance that leads nowhere');
      });
    });

    test('no other file pushes a debug-only path', () {
      final offenders = <String>[];
      for (final f in _dartFilesUnder('lib')) {
        final src = f.readAsStringSync();
        final rel = f.path.split('/apps/mobile/').last;
        if (entryPoints.containsKey(rel)) continue;
        if (rel.endsWith('core/router/app_router.dart')) continue;
        for (final path in kDebugOnlyRoutePaths) {
          if (src.contains("'$path'")) offenders.add('$rel -> $path');
        }
      }
      expect(offenders, isEmpty,
          reason: 'a new entry point into QA tooling appeared; gate it on '
              'kQaToolingEnabled and record it above');
    });
  });
}
