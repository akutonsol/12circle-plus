import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/directory_screen.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fit_matrix.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60b (UX 2) · Directory's header. At d449142 the chat button was 40px
// with no name, and the greeting overflowed the bar (across for a long name on
// a narrow phone, down at large text).
//
// HOW TO SEE IT FAIL: `git checkout d449142 -- lib/features/dashboard/
// presentation/directory_screen.dart`; the controls pass.

const _long = 'Bartholomew-Alexandros';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(TwoMemberPostgrest());
  });

  Future<void> show(WidgetTester t,
      {double width = 390, double scale = 1, String name = 'Sam'}) async {
    fitWindow(t, width, 6000, scale);
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final router = GoRouter(initialLocation: '/directory', routes: [
      GoRoute(path: '/directory', builder: (_, __) => const DirectoryScreen()),
      GoRoute(path: '/messages', builder: (_, __) => const Text('MESSAGES')),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(ProviderScope(
        overrides: [
          currentFirstNameProvider.overrideWithValue(name),
          confirmedCurrentProfileProvider.overrideWithValue(null),
          assignedWorkoutsProvider.overrideWith((ref) async => const []),
          programSessionStatusProvider.overrideWith((ref) async => const {}),
          assignedCoachProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp.router(routerConfig: router)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
  }

  final header = find.byType(BackdropFilter);

  for (final w in fitPhones.keys) {
    for (final s in fitScales) {
      for (final name in ['Sam', _long]) {
        testWidgets('${w}dp at ${s}x, "$name": the greeting is whole, not '
            'shrunk, and clear of the buttons', (t) async {
          final seen = recordOverflows();
          await show(t, width: w.toDouble(), scale: s, name: name);
          expect(overflowsIn(t, seen, header), isEmpty,
              reason: 'THE defect: ${seen.join('\n\n')}');
          final bar = t.getRect(header);
          for (final (text, size) in [('Good Morning', 10.0), (name, 20.0)]) {
            final f = find.text(text);
            expect(f, findsOneWidget);
            expect(renderedFontSize(t, f), closeTo(size * s, 0.01));
            expect(
                t
                    .renderObject<RenderParagraph>(find
                        .descendant(of: f, matching: find.byType(RichText))
                        .first)
                    .didExceedMaxLines,
                isFalse);
            final r = t.getRect(f);
            expect(r.left >= 0 && r.right <= w, isTrue, reason: '$text: $r');
            final inBar =
                find.ancestor(of: f, matching: header).evaluate().isNotEmpty;
            if (inBar) {
              expect(r.top >= bar.top && r.bottom <= bar.bottom, isTrue,
                  reason: '$text: $r in $bar');
              final chat =
                  t.getRect(find.byIcon(Icons.chat_bubble_outline_rounded));
              expect(r.overlaps(chat), isFalse);
            } else {
              expect(r.top, greaterThanOrEqualTo(bar.bottom),
                  reason: 'not under the bar');
            }
          }
          final Rect bell = t.getRect(find.byIcon(Icons.notifications_outlined));
          expect(bell.right, lessThanOrEqualTo(w.toDouble()));
          await t.pumpWidget(const SizedBox());
        });
      }
    }
  }

  testWidgets('CONTROL: at 1x a short name stays in the bar', (t) async {
    await show(t);
    expect(find.descendant(of: header, matching: find.text('Sam')),
        findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('Good Morning')),
        findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  for (final s in fitScales) {
    testWidgets('320dp at ${s}x: the chat button is 44×44, named, and a screen '
        'reader can press it', (t) async {
      final h = t.ensureSemantics();
      await show(t, width: 320, scale: s);
      expectNamedButton(t, 'Open messages'); // THE defect: no name, 40px
      expectNamedButton(t, 'Show upcoming classes and events');
      final node = t.getSemantics(find.bySemanticsLabel('Open messages'));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await t.pumpAndSettle();
      expect(find.text('MESSAGES'), findsOneWidget);
      h.dispose();
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('POSITIVE CONTROL: a tap opens messages', (t) async {
    await show(t);
    await t.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await t.pumpAndSettle();
    expect(find.text('MESSAGES'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
