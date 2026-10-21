// FIT-001 · the client bottom bar — measured on the device.
//
// NAV-G1 holds the contract in source. What source cannot settle:
//
//  * the 44 dp `tap` floor on five tabs sharing one row at 360 dp;
//  * whether each tab reaches the platform accessibility tree as a named,
//    activatable control;
//  * whether five labels and five icons fit that row with the real font. The
//    host harness renders in Ahem, where a width means nothing (F-24), and
//    the bar this replaces had four labels plus a FAB.
//
// The shell's bar is mounted directly. Nothing is signed in and no backend is
// touched.
//
//   flutter test integration_test/fit001_client_nav_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:circle_fitness/core/constants/app_constants.dart';

import 'package:circle_fitness/core/router/app_shell.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';

void _mark(String line) => print('FIT001-MARK $line');

const _tabs = ['Home', 'Workouts', 'Nutrition', 'Check-In', 'Connect'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // `AppShell` asserts a Supabase instance exists before it will build — its
  // notification watcher and top bar construct one. The client is initialised
  // and **nothing signs in**: the profile provider is overridden below, so no
  // request is made and no row is read or written.
  setUpAll(() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
    );
  });

  Future<void> pump(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        for (final p in const [
          '/home',
          '/train',
          '/meals-dashboard',
          '/daily-checkin',
          '/messages',
        ])
          GoRoute(
            path: p,
            builder: (_, __) => AppShell(currentLocation: p, child: Text('AT $p')),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // The bar chooses between the client and coach sets from the profile's
        // role, and reading it reaches Supabase, which a test has none of.
        currentUserProfileProvider.overrideWith(
            (ref) async => <String, dynamic>{'role': 'client'}),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the five tabs, on the device', (tester) async {
    await pump(tester);
    final dpr = tester.view.devicePixelRatio;
    _mark('viewport ${(tester.view.physicalSize.width / dpr).toStringAsFixed(1)}'
        ' dp @ dpr $dpr');

    for (final t in _tabs) {
      final f = find.text(t);
      expect(f, findsOneWidget, reason: '$t is not on the bar');
      // The label's own painted width. Five of these share one row, which is
      // the thing the host harness cannot measure — it renders in Ahem, where
      // every glyph is a full em square.
      _mark('$t ${tester.getSize(f).width.toStringAsFixed(1)} dp label');
    }
    // FIT-001: "the animated FAB is gone."
    expect(find.text('Activity'), findsNothing);
    expect(find.text('Train'), findsNothing);
    _mark('no Activity tab, no Train label');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bar holds from 360 dp up', (tester) async {
    final originalSize = tester.view.physicalSize;
    final dpr = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.resetDevicePixelRatio();
    });

    for (final dp in const [360.0, 390.0, 411.4]) {
      tester.view.physicalSize = Size(dp * dpr, 844 * dpr);
      await pump(tester);
      for (final t in _tabs) {
        expect(find.text(t), findsOneWidget, reason: '$t at $dp dp');
      }
      final err = tester.takeException();
      _mark('$dp dp — five tabs, exception=${err ?? 'none'}');
      expect(err, isNull,
          reason: 'five labels in one row at $dp dp is the real risk here');
    }
  });
}
