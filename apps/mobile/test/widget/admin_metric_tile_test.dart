import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/admin/domain/admin_metrics.dart';
import 'package:circle_fitness/features/admin/presentation/admin_metric_tile.dart';
import 'package:circle_fitness/features/admin/presentation/admin_tokens.dart';

Future<void> _pump(WidgetTester t, Widget child) => t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 360, child: child)),
      ),
    );

TextStyle _styleOf(WidgetTester t, String text) =>
    t.widget<Text>(find.text(text)).style!;

void main() {
  group('a measured value', () {
    testWidgets('renders grouped, with its label', (t) async {
      await _pump(t, const AdminMetricTile.value(label: 'Registrations', value: 1640));
      expect(find.text('Registrations'), findsOneWidget);
      expect(find.text('1,640'), findsOneWidget);
    });

    testWidgets('a measured ZERO uses the design\'s own wording, not an empty panel '
        '— STATE-SPECS-A11 §1 specifies "None" / "none raised" / "none open"',
        (t) async {
      await _pump(t, const AdminMetricTile.value(
          label: 'Critical alerts', value: 0, zeroCopy: 'none raised'));
      expect(find.text('none raised'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a measured zero with no specified wording still renders as a value',
        (t) async {
      await _pump(t, const AdminMetricTile.value(label: 'Open reports', value: 0));
      expect(find.text('0'), findsOneWidget);
    });
  });

  group('the two absence states are distinguishable, and neither is a number', () {
    testWidgets('notAuthorized says so, and renders NO DIGIT ANYWHERE — a zero here '
        'would be a claim about data this role may not query', (t) async {
      await _pump(t, const AdminMetricTile.absent(
          label: 'Sign-ins today', absence: MetricAbsence.notAuthorized));
      expect(find.text('Not available to your role'), findsOneWidget);
      expect(find.text('0'), findsNothing);

      final rendered = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' ');
      expect(RegExp(r'\d').hasMatch(rendered), isFalse,
          reason: 'an unauthorized metric must not render any figure: "$rendered"');
    });

    testWidgets('notRecorded is a DIFFERENT state from notAuthorized — "nothing was '
        'recorded" and "you may not see it" are not the same finding', (t) async {
      await _pump(t, const AdminMetricTile.absent(
          label: 'CI status', absence: MetricAbsence.notRecorded));
      expect(find.text('Not recorded'), findsOneWidget);
      expect(find.text('Not available to your role'), findsNothing);
    });

    testWidgets('the absent treatment uses the published Empty-state token, not an '
        'ad-hoc grey', (t) async {
      await _pump(t, const AdminMetricTile.absent(
          label: 'x', absence: MetricAbsence.notRecorded));
      expect(_styleOf(t, 'Not recorded').color, AdminColors.colorTextMuted);
      expect(_styleOf(t, 'Not recorded').fontSize, AdminDims.typeSmallSize);
    });
  });

  group('AdminMetricTile.of — the only nullable entry point', () {
    testWidgets('a null figure becomes the named absence, never a zero', (t) async {
      await _pump(t, AdminMetricTile.of('Sign-ins', null,
          whenNull: MetricAbsence.notAuthorized));
      expect(find.text('Not available to your role'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a real zero passes through as a value even though it is falsy', (t) async {
      await _pump(t, AdminMetricTile.of('Sign-ins', 0,
          whenNull: MetricAbsence.notAuthorized));
      expect(find.text('0'), findsOneWidget);
      expect(find.text('Not available to your role'), findsNothing);
    });
  });

  group('the month-on-month delta', () {
    testWidgets('an UNKNOWN delta renders nothing — a flat month and an '
        'unmeasurable one are different claims', (t) async {
      await _pump(t, const AdminMetricTile.value(label: 'DAU', value: 26));
      expect(find.text('+0'), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a positive delta is signed and uses the success token', (t) async {
      await _pump(t, const AdminMetricTile.value(label: 'DAU', value: 26, delta: 7));
      expect(find.text('+7'), findsOneWidget);
      expect(_styleOf(t, '+7').color, AdminColors.colorStatusSuccessText);
    });

    testWidgets('a negative delta uses the danger token', (t) async {
      await _pump(t, const AdminMetricTile.value(label: 'DAU', value: 19, delta: -7));
      expect(find.text('-7'), findsOneWidget);
      expect(_styleOf(t, '-7').color, AdminColors.colorStatusDangerText);
    });
  });

  group('a pre-formatted figure', () {
    testWidgets('is rendered as given, because only the caller knows its units',
        (t) async {
      await _pump(t, const AdminMetricTile.text(
          label: 'Attendance rate', display: '74.0%'));
      expect(find.text('74.0%'), findsOneWidget);
    });
  });
}
