import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/core/config/app_env.dart';
import 'package:circle_fitness/features/admin/domain/admin_provider.dart';
import 'package:circle_fitness/features/admin/presentation/admin_chrome.dart';
import 'package:circle_fitness/features/admin/presentation/admin_settings_screen.dart';
import 'package:circle_fitness/features/admin/presentation/admin_tokens.dart';

/// §201 · the environment strip `COMPONENTS.md` specifies.
///
/// THE PRODUCTION ARM IS THE ONE THAT MATTERS, and it is the one a careless implementation
/// gets wrong in the safe-looking direction. The design's rule is *"No banner. Only staging
/// and development show the amber strip at the top."* A strip that appeared in production
/// would be a permanent false alarm that operators learn to ignore; one that failed to appear
/// in staging lets an operator act on what they believe is a sandbox. Both arms are asserted.
Future<void> _pump(WidgetTester t, AppEnvironment env) async {
  await t.binding.setSurfaceSize(const Size(500, 2000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ProviderScope(
    overrides: [
      adminEnvironmentProvider.overrideWithValue(env),
      adminAdministratorCountProvider.overrideWith((_) async => null),
      adminRoleCapabilitiesProvider.overrideWith((_) async => null),
      adminPlatformSettingsProvider.overrideWith((_) async => null),
    ],
    child: const MaterialApp(home: AdminSettingsScreen()),
  ));
  await t.pump();
}

void main() {
  testWidgets('PRODUCTION shows no strip at all — the design says "No banner"', (t) async {
    await _pump(t, AppEnvironment.prod);
    expect(find.text(AdminEnvironmentStrip.stagingText), findsNothing);
    expect(find.text(AdminEnvironmentStrip.devText), findsNothing);
    // And it occupies no space, so it cannot push the page down invisibly.
    expect(
        const AdminEnvironmentStrip(environment: AppEnvironment.prod)
            .preferredSize
            .height,
        0);
  });

  testWidgets('STAGING shows the design\'s verbatim sentence', (t) async {
    await _pump(t, AppEnvironment.qa);
    expect(find.text('Staging environment — changes here do not affect members'),
        findsOneWidget);
  });

  testWidgets('DEVELOPMENT shows a strip but makes NO guarantee about members — ENV-4 '
      'leaves dev with no backend default, so this layer cannot promise where it points',
      (t) async {
    await _pump(t, AppEnvironment.dev);
    expect(find.text(AdminEnvironmentStrip.devText), findsOneWidget);
    expect(find.textContaining('do not affect members'), findsNothing,
        reason: 'dev must not inherit the staging guarantee');
  });

  test('the strip is 34px, per COMPONENTS.md\'s "environment strip (34px)"', () {
    expect(AdminEnvironmentStrip.height, 34.0);
    for (final env in [AppEnvironment.qa, AppEnvironment.dev]) {
      expect(AdminEnvironmentStrip(environment: env).preferredSize.height, 34.0);
    }
  });

  testWidgets('the amber is the generated token, not a literal — and the foreground is the '
      'token made FOR that fill, so it is not amber on amber', (t) async {
    await _pump(t, AppEnvironment.qa);
    final box = t.widget<Container>(find.ancestor(
        of: find.text(AdminEnvironmentStrip.stagingText),
        matching: find.byType(Container)).first);
    expect(box.color, AdminColors.colorStatusWarning);
    final text = t.widget<Text>(find.text(AdminEnvironmentStrip.stagingText));
    expect(text.style?.color, AdminColors.colorTextOnWarning);
    expect(text.style?.color, isNot(AdminColors.colorStatusWarning));
  });

  test('every one of the six admin pages carries it — a page without it would tell an '
      'operator nothing about where they are', () {
    final dir = Directory('lib/features/admin/presentation');
    final pages = [
      'admin_metrics_screen.dart',
      'admin_people_screen.dart',
      'admin_ecosystem_screen.dart',
      'admin_trust_screen.dart',
      'admin_operations_screen.dart',
      'admin_settings_screen.dart',
    ];
    final missing = <String>[];
    for (final name in pages) {
      final f = File('${dir.path}/$name');
      expect(f.existsSync(), isTrue, reason: '$name is gone; this guard judges nothing');
      if (!f.readAsStringSync().contains('AdminEnvironmentStrip')) missing.add(name);
    }
    expect(missing, isEmpty, reason: 'these pages carry no environment strip: $missing');
  });

  test('textFor covers every AppEnvironment value, so a new environment cannot be added '
      'and silently render nothing', () {
    // The switch is exhaustive by language rule; this asserts the MAPPING rather than the
    // syntax — exactly one environment yields null, and it is prod.
    final nulls = AppEnvironment.values
        .where((e) => AdminEnvironmentStrip.textFor(e) == null)
        .toList();
    expect(nulls, [AppEnvironment.prod]);
  });
}
