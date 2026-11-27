import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:circle_fitness/shared/widgets/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fit_matrix.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-61 round 2 · the AppScaffold header (9 screens).
//
// At a82f993 it was 64 tall whatever the text size: a titled header's wrapped
// title was cut off (silently: a Text reports no overflow) and the greeting's
// rows overflowed. At 924bbf0 the bell's 44px target also took 18dp more of
// the title's width.
//
// HOW TO SEE IT FAIL: run against 924bbf0's (or a82f993's) app_scaffold.dart.
// The 1× geometry is a82f993's, and passes there.

const _uid = '00000000-0000-4000-8000-00000000d61d';

/// Ends with the header gone and its timers run out (a82f993's bell always
/// has one pending), so a test fails for its own reason only.
void headerTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (t) async {
      await body(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSignedInSupabase(RowCheckingPostgrest(_uid));
  });

  Future<void> mount(WidgetTester t,
      {String? title, bool back = false, String name = 'Alexandria'}) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        confirmedCurrentProfileProvider.overrideWith((ref) => {'first_name': name}),
        unreadCountProvider.overrideWith((ref) async => 3),
      ],
      child: MaterialApp(
        home: MediaQuery.withClampedTextScaling(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: AppScaffold(
                title: title,
                showBackButton: back,
                body: const SizedBox.expand(key: Key('body')),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  final bell = find.byIcon(Icons.notifications);
  final lead = find.byWidgetPredicate((w) =>
      w is IconButton || (w is Container && w.constraints == BoxConstraints.tight(const Size(40, 40))));

  /// The whole header.
  Rect header(WidgetTester t) => Rect.fromLTRB(
      0, 0, t.view.physicalSize.width, t.getRect(find.byKey(const Key('body'))).top);

  /// [text] is painted whole: nothing of it is cut off by the box it got, and
  /// the box is inside the header, clear of the bell.
  void expectReadable(WidgetTester t, String text) {
    final p = t.renderObject<RenderParagraph>(find.descendant(
        of: find.text(text), matching: find.byType(RichText)).first);
    final needs = TextPainter(
        text: p.text, textDirection: p.textDirection, textScaler: p.textScaler)
      ..layout(maxWidth: p.constraints.maxWidth);
    addTearDown(needs.dispose);
    expect(p.didExceedMaxLines, isFalse, reason: '"$text" is cut off');
    expect(p.size.height, greaterThanOrEqualTo(needs.height - 0.5),
        reason: '"$text" needs ${needs.height} and got ${p.size.height}');
    expect(p.size.width, greaterThanOrEqualTo(needs.width - 0.5),
        reason: '"$text" is cut off at the side');
    final box = t.getRect(find.text(text));
    final h = header(t);
    expect(box.top >= 0 && box.bottom <= h.bottom, isTrue,
        reason: '"$text" $box is outside the header $h');
    expect(box.right, lessThanOrEqualTo(t.getRect(bell).left + 0.01));
  }

  for (final width in fitPhones.keys) {
    for (final scale in fitScales) {
      for (final back in [false, true]) {
        final at = '${width}dp, text $scale×${back ? ', back button' : ''}';

        for (final title in ['PERFORMANCE', 'EXERCISE LIBRARY']) {
          headerTest('"$title", $at: readable at full size, the bell '
              'takes none of its width', (t) async {
            final seen = recordOverflows();
            fitWindow(t, width, 900, scale);
            await mount(t, title: title, back: back);
            expect(seen, isEmpty);
            expectTextNotShrunk(t, find.text(title), scale);
            expect(renderedFontSize(t, find.text(title)), closeTo(18 * scale, 0.01));
            expectReadable(t, title);
            // Everything between the leading control and the icon is its.
            final p = t.renderObject<RenderParagraph>(find.descendant(
                of: find.text(title), matching: find.byType(RichText)).first);
            expect(p.constraints.maxWidth,
                closeTo(t.getRect(bell).left - t.getRect(lead.first).right - 12, 0.01));
            expect(t.getRect(bell).right, closeTo(width - 20, 0.01));
          });
        }

        headerTest('the greeting, $at: readable at full size', (t) async {
          final seen = recordOverflows();
          fitWindow(t, width, 900, scale);
          await mount(t, back: back);
          expect(seen, isEmpty);
          final hour = DateTime.now().hour;
          final greeting = hour < 12
              ? 'GOOD MORNING'
              : hour < 17
                  ? 'GOOD AFTERNOON'
                  : 'GOOD EVENING';
          for (final (text, size) in [(greeting, 10.0), ('Alexandria', 20.0)]) {
            expectTextNotShrunk(t, find.text(text), scale);
            expect(renderedFontSize(t, find.text(text)), closeTo(size * scale, 0.01));
            expectReadable(t, text);
          }
          final bolt = t.getRect(find.byIcon(Icons.bolt));
          expect(bolt.right, lessThanOrEqualTo(t.getRect(bell).left + 0.01));
        });
      }
    }
  }

  headerTest('the bell takes a touch anywhere in its 44px, at 1× and 3×',
      (t) async {
    for (final scale in [1.0, 3.0]) {
      fitWindow(t, 390, 900, scale);
      await mount(t, title: 'PERFORMANCE');
      final target = t.getRect(
          find.ancestor(of: bell, matching: find.byType(GestureDetector)).first);
      expect(target.size, const Size(44, 44));
      expect(target.left, t.getRect(bell).left, reason: 'none of it on the title');
      expect(target.right, lessThanOrEqualTo(390));
    }
  });

  // ── a82f993's own geometry ────────────────────────────────────────────────

  headerTest('CONTROL 1×, 390dp: a titled header is laid out as before',
      (t) async {
    fitWindow(t, 390, 844, 1);
    await mount(t, title: 'PERFORMANCE');
    expect(header(t), const Rect.fromLTRB(0, 0, 390, 64));
    expect(t.getRect(lead.first), const Rect.fromLTWH(20, 11.5, 40, 40));
    // Round 3: the avatar's 44px target lies around it; nothing else moved.
    expect(
        t.getRect(find
            .ancestor(of: lead.first, matching: find.byType(GestureDetector))
            .first),
        const Rect.fromLTWH(18, 9.5, 44, 44));
    expect(t.getRect(find.text('PERFORMANCE')), const Rect.fromLTRB(72, 18.5, 344, 44.5));
    expect(t.getRect(bell), const Rect.fromLTWH(344, 18.5, 26, 26));
  });

  headerTest('CONTROL 1×, 390dp: with a back button, as before', (t) async {
    fitWindow(t, 390, 844, 1);
    await mount(t, title: 'PERFORMANCE', back: true);
    expect(header(t), const Rect.fromLTRB(0, 0, 390, 64));
    expect(t.getRect(find.byType(IconButton)), const Rect.fromLTWH(8, 7.5, 48, 48));
    expect(t.getRect(find.text('PERFORMANCE')), const Rect.fromLTRB(68, 18.5, 344, 44.5));
    expect(t.getRect(bell), const Rect.fromLTWH(344, 18.5, 26, 26));
  });

  headerTest('CONTROL 1×, 390dp: the greeting is laid out as before', (t) async {
    fitWindow(t, 390, 844, 1);
    await mount(t, name: 'Alex');
    expect(header(t), const Rect.fromLTRB(0, 0, 390, 64));
    expect(t.getRect(lead.first), const Rect.fromLTWH(20, 11.5, 40, 40));
    expect(t.getRect(find.textContaining('GOOD ')).topLeft, const Offset(72, 10));
    expect(t.getRect(find.text('Alex')), const Rect.fromLTRB(72, 24, 150, 53));
    expect(t.getRect(find.byIcon(Icons.bolt)), const Rect.fromLTWH(154, 28.5, 20, 20));
    expect(t.getRect(bell), const Rect.fromLTWH(344, 18.5, 26, 26));
  });

  headerTest('CONTROL: the status bar is still added above', (t) async {
    fitWindow(t, 390, 844, 1);
    t.view.padding = const FakeViewPadding(top: 47);
    await mount(t, title: 'PLAN');
    expect(header(t).bottom, 64 + 47);
    expect(t.getRect(bell), const Rect.fromLTWH(344, 65.5, 26, 26));
  });
}
