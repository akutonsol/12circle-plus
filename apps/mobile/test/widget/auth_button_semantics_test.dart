import 'package:circle_fitness/features/auth/presentation/widgets/auth_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

// P0-FL-48 · AuthButton tells a screen reader the truth about whether it works.
//
// Its Semantics said `enabled: !loading`, ignoring `onTap == null`: a button
// with nothing to do (a form not yet valid, a flow that passes null to block a
// second submit) was announced as an active "Sign in" button, and a double tap
// did nothing. Enabled is now `onTap != null && !loading`.
//
// AuthFooterLink ("Already have an account? Sign In") was a bare text-height
// GestureDetector with no button role; it is now >= 44px and a button.
//
// HOW TO SEE IT FAIL: `git checkout 185261e -- lib/features/auth/presentation/
// widgets/auth_design.dart` — the null-onTap case reports isEnabled: true and
// the footer link is ~17px tall with no button flag.

Future<void> _pump(WidgetTester t, Widget child) => t.pumpWidget(MaterialApp(
    home: Scaffold(body: Center(child: SizedBox(width: 320, child: child)))));

SemanticsNode _button(WidgetTester t, String label) =>
    t.getSemantics(find.text(label));

void main() {
  testWidgets('onTap null: announced as a DISABLED button, with no tap action',
      (t) async {
    final h = t.ensureSemantics();
    await _pump(t, const AuthButton(label: 'Sign in'));
    final node = _button(t, 'Sign in');
    expect(
        node,
        // Strict: every flag/action on the node is listed — no tap action.
        matchesSemantics(
            label: 'Sign in', isButton: true, hasEnabledState: true),
        reason: 'a button with nothing to do must not be announced as active');
    h.dispose();
  });

  testWidgets('onTap set, not loading: an ENABLED button that taps', (t) async {
    final h = t.ensureSemantics();
    var taps = 0;
    await _pump(t, AuthButton(label: 'Sign in', onTap: () => taps++));
    final node = _button(t, 'Sign in');
    expect(
        node,
        matchesSemantics(
            label: 'Sign in',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true));
    await t.tap(find.text('Sign in'));
    expect(taps, 1);
    h.dispose();
  });

  testWidgets('loading: DISABLED even with an onTap, and a tap does nothing',
      (t) async {
    final h = t.ensureSemantics();
    var taps = 0;
    await _pump(
        t, AuthButton(label: 'Sign in', loading: true, onTap: () => taps++));
    final node = t.getSemantics(find.byType(AuthButton));
    expect(
        node,
        matchesSemantics(isButton: true, hasEnabledState: true));
    await t.tap(find.byType(AuthButton));
    expect(taps, 0);
    h.dispose();
  });

  testWidgets(
      'AuthFooterLink is a button with its text as the name and a >= 44px '
      'tap target', (t) async {
    final h = t.ensureSemantics();
    var taps = 0;
    await _pump(
        t,
        AuthFooterLink(
            prefix: 'Already have an account?',
            action: 'Sign In',
            onTap: () => taps++));
    final link = find.byType(AuthFooterLink);
    final target = find
        .descendant(of: link, matching: find.byType(GestureDetector))
        .first;
    expect(t.getSize(target).height, greaterThanOrEqualTo(44));
    expect(
        t.getSemantics(find.byType(RichText)),
        matchesSemantics(
            label: 'Already have an account? Sign In',
            isButton: true,
            hasTapAction: true));
    // The whole 44px band answers a tap, not just the glyphs.
    final r = t.getRect(target);
    await t.tapAt(Offset(r.center.dx, r.top + 2));
    expect(taps, 1);
    h.dispose();
  });
}
