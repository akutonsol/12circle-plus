import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/admin/domain/admin_metrics.dart';
import 'package:circle_fitness/features/admin/domain/admin_provider.dart';
import 'package:circle_fitness/features/admin/presentation/admin_metric_tile.dart';
import 'package:circle_fitness/features/admin/presentation/admin_metrics_screen.dart';
import 'package:circle_fitness/features/admin/presentation/admin_tokens.dart';

/// V5 §167 — the hosted screen. The route is deliberately NOT role-gated on the
/// client, because enforcement is server-side: every surface it reads gates on
/// `admin_can` inside the view's own WHERE. So the case that matters most here is
/// what a caller WITHOUT the capability actually sees, and the answer must be an
/// honest `A11` state — not an empty page, and above all not zeros.
Future<void> _pump(WidgetTester t, List<Override> overrides) async {
  await t.pumpWidget(ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: AdminMetricsScreen()),
  ));
  await t.pump();
}

final _denied = [
  adminActivityOverviewProvider.overrideWith((_) async => null),
  adminUserOverviewProvider.overrideWith((_) async => null),
  adminEventsOverviewProvider.overrideWith((_) async => null),
  adminCommunityOverviewProvider.overrideWith((_) async => null),
  adminRevenueOverviewProvider.overrideWith((_) async => null),
  adminReleaseStatusProvider.overrideWith((_) async => null),
  // Overridden EXPLICITLY, not left to chance. Without it the attention queue
  // reaches for an uninitialised Supabase client and lands in the error state, so
  // these tests would pass for an accidental reason rather than a stated one.
  adminIncidentsProvider.overrideWith((_) async => null),
];

void main() {
  testWidgets('a caller with no Admin capability reaching the route directly sees '
      'every area say why it is empty, and NO figure anywhere — the route being '
      'ungated on the client is safe precisely because this is what it renders',
      (t) async {
    await _pump(t, _denied);
    expect(find.text('Metrics'), findsOneWidget);
    expect(find.text('Not available to your role'), findsWidgets);
    // A FIGURE IS A TILE VALUE, NOT ANY DIGIT ON THE PAGE. This banned `\d` anywhere, and
    // §194's "Not shown here" card broke it by citing the rulings BY NAME — PD-A24, PD-G01,
    // WI-13, P7. Those digits are why an absence is an absence, so a sweep forbidding them
    // forbids explaining the gap. Sixth instance of this shape in the run.
    //
    // Reading the tiles is strictly STRONGER than the digit sweep it replaces: it also
    // catches a tile rendering "0" or one rendering "none", neither of which `\d` would see
    // as a problem.
    final tiles = t.widgetList<AdminMetricTile>(find.byType(AdminMetricTile)).toList();
    expect(tiles, isNotEmpty,
        reason: 'no tiles were found at all, so this assertion would prove nothing');
    final shown = tiles.where((x) => !x.isAbsent).toList();
    expect(shown, isEmpty,
        reason: 'these tiles rendered a value to an uncapable caller: '
            '${shown.map((x) => x.label).join(', ')}');
  });

  testWidgets('the screen is scrollable, because the panel does not own scrolling',
      (t) async {
    await _pump(t, _denied);
    expect(find.byType(Scrollable), findsWidgets);
  });

  testWidgets('the canvas uses the published token, not an ad-hoc background',
      (t) async {
    await _pump(t, _denied);
    expect(t.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        AdminColors.colorBgCanvas);
  });

  testWidgets('an authorized caller sees figures, so the denial case above is not '
      'passing for want of any data path at all', (t) async {
    await _pump(t, [
      ..._denied,
      adminUserOverviewProvider.overrideWith((_) async =>
          AdminUserOverview.fromRow(const {
            'users_total': 640,
            'coaches_total': 135,
            'vendors_total': 0,
            'coaches_active_this_month': 2,
            'coaches_no_client_this_month': 133,
            'age_18_30': 0,
            'age_30_45': 1,
            'age_45_60': 0,
            'age_unknown': 639,
            'age_out_of_range': 0,
          })),
    ]);
    expect(find.text('640'), findsOneWidget);
    expect(find.text('135'), findsOneWidget);
  });
}
