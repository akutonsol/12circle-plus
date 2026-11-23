import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/row_checking_postgrest.dart';

// P0-FL-45b (UX) · Profile and Settings at 2x text on a 320dp phone.
//
// The Profile header's chip row ('Member' · goal · coaching mode) was a Row
// of fixed-width chips, the weight-goal card a Row whose text column could
// not shrink, and Settings' "SETTINGS" title wrapped past its 56px bar: each
// threw a RenderFlex overflow (yellow-black stripes, clipped content) for a
// member using large text. Now the chips wrap, the text column flexes, and
// the title is one line, scaled down to fit — shown in full, never "SETT…"
// (UX F2 of the review: the first fix ellipsised it).
//
// The surface is 320dp wide and tall enough that every row is laid out (an
// overflow below the fold is still an overflow when scrolled to).
//
// HOW TO SEE IT FAIL: `git checkout 185261e -- lib/features/profile/presentation/profile_screen.dart lib/features/settings/presentation/settings_screen.dart`.

const _uid = '00000000-0000-4000-8000-0000000f4545';

Map<String, dynamic> _row(String role) => {
      'id': _uid,
      'role': role,
      'first_name': 'Maximiliana',
      'last_name': 'Featherstonehaugh',
      'email': 'maximiliana.featherstonehaugh@example.com',
      'fitness_goal': 'build_muscle',
      'activity_level': 'moderately_active',
      'height_cm': 172,
      'weight_kg': 82.5,
      'weight_goal_kg': 78.0,
      'training_days_per_week': 4,
      'unit_preference': 'metric',
    };

void main() {
  late RowCheckingPostgrest server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = RowCheckingPostgrest(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() => server.reset());

  Future<void> open(WidgetTester tester, Widget screen, String role) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(320, 4000);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider
            .overrideWithValue(Supabase.instance.client.auth.currentUser),
        currentUserProfileProvider.overrideWith((ref) async => _row(role)),
        clientPlanProvider.overrideWith((ref) async => ClientPlan.selfGuided),
        tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
      ],
      child: MaterialApp(home: screen),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  for (final role in ['client', 'coach']) {
    testWidgets('Profile ($role) at 2x text, 320dp: no overflow, header chips '
        'all on screen', (tester) async {
      await open(tester, const ProfileScreen(), role);
      expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
      for (final chip in [role == 'coach' ? 'Coach' : 'Member', 'Build Muscle']) {
        final r = tester.getRect(find.text(chip));
        expect(r.left, greaterThanOrEqualTo(0), reason: chip);
        expect(r.right, lessThanOrEqualTo(320), reason: chip);
      }
      final edit = tester.getRect(find.text('Edit Profile'));
      expect(edit.right, lessThanOrEqualTo(320));
      await unmount(tester);
    });

    testWidgets('Settings ($role) at 2x text, 320dp: no overflow, the title '
        'stays in its bar', (tester) async {
      await open(tester, const SettingsScreen(), role);
      expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
      final title = tester.getRect(find.text('SETTINGS'));
      expect(title.height, lessThanOrEqualTo(56), reason: 'one line, in the bar');
      expect(title.right, lessThanOrEqualTo(320));
      // UX F2: the whole word, not "SETT…" — the line is scaled to fit, never
      // cut (an ellipsised or clipped paragraph reports it exceeded its lines).
      final text = tester.widget<Text>(find.text('SETTINGS'));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      final para = tester.renderObject<RenderParagraph>(find.text('SETTINGS'));
      expect(para.didExceedMaxLines, isFalse,
          reason: 'the title is shown in full');
      expect(para.size.width,
          greaterThanOrEqualTo(para.getMaxIntrinsicWidth(double.infinity) - 0.5),
          reason: 'laid out at its full width (then scaled), not truncated');
      await unmount(tester);
    });
  }
}
