import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_availability_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/failing_reads_postgrest.dart';
import '../support/fit_matrix.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-58 (b) · Manage Availability: fit and touch targets.
//
// At f191d48: a slot card's 52×52 time box overflowed from 1.3× (248px at
// 3×), the slot and session cards overflowed sideways at 3×, every delete
// button was announced "Remove slot" (which one was not said) and every cancel
// "Cancel"; the Add-slot sheet's Type / Duration chips were ~30px with no
// role, its date and dropdowns unnamed; and the floating Add Slot button
// covered the last card's delete button.
//
// A primary coach flow, so the matrix includes 3.0×.
//
// HOW TO SEE IT FAIL: `git checkout f191d48 -- lib/features/coach/
// presentation/coach_availability_screen.dart`; only the controls pass.

const _uid = '00000000-0000-4000-8000-0000000f58b0';

DateTime _day() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + 2, 9, 5);
}

String _dayLabel() {
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final d = _day();
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

String _iso([int addHours = 0]) =>
    _day().add(Duration(hours: addHours)).toUtc().toIso8601String();

/// Holds a DELETE until [deleteGate] completes (a delete "in flight").
class _Server extends FailingReadsPostgrest {
  _Server(super.uid);
  Completer<void>? deleteGate;
  @override
  void reset() {
    super.reset();
    deleteGate = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'DELETE') await deleteGate?.future;
    return super.send(request);
  }
}

void main() {
  late _Server server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server(_uid);
    await initSignedInSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    server.reads['coach_availability'] = [
      {'id': 's1', 'slot_time': _iso(), 'is_booked': false, 'duration_minutes': 30, 'type': 'consultation'},
      {'id': 's2', 'slot_time': _iso(2), 'is_booked': true, 'duration_minutes': 45, 'type': 'nutrition_review'},
      {'id': 's3', 'slot_time': _iso(4), 'is_booked': false, 'duration_minutes': 60, 'type': 'check_in'},
    ];
    server.reads['coaching_calls'] = [
      {'id': 'c1', 'scheduled_at': _iso(6), 'duration_minutes': 30, 'call_type': 'nutrition_review',
       'client_id': 'x', 'client': {'first_name': 'Alexandria', 'last_name': 'Montgomery'}},
    ];
  });
  tearDown(resetFailureSink);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
    await tester.pumpAndSettle();
    expect(find.text('YOUR AVAILABILITY'), findsOneWidget, reason: 'premise: loaded');
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Publish Slot'), findsOneWidget, reason: 'premise');
  }

  final sheet = find.byType(BottomSheet);

  void whole(WidgetTester tester, String text, double size, double scale, {Finder? within}) {
    var f = find.text(text);
    if (within != null) f = find.descendant(of: within, matching: f);
    expect(f, findsOneWidget, reason: text);
    expect(renderedFontSize(tester, f), closeTo(size * scale, 0.01), reason: text);
  }

  group('fit: no overflow, no shrunk text', () {
    for (final w in fitPhones.keys) {
      for (final s in fitScales) {
        testWidgets('slots and sessions, ${w}dp at ${s}x', (tester) async {
          final seen = recordOverflows();
          fitWindow(tester, w, 6000, s);
          await open(tester);
          expect(seen, isEmpty, reason: seen.join('\n\n'));
          expectTextNotShrunk(tester, find.byType(ListView), s);
          whole(tester, '09:05', 14, s);
          whole(tester, 'Strategy Consultation', 14, s);
          whole(tester, '30 min • Available', 12, s);
          whole(tester, 'Alexandria Montgomery', 14, s);
          whole(tester, 'Cancel', 13, s);
          whole(tester, 'Add Slot', 14, s);
          // The floating button is on screen, and its label inside it.
          final fab = tester.getRect(find.byType(FloatingActionButton));
          final label = tester.getRect(find.text('Add Slot'));
          expect(fab.left >= 0 && fab.height >= 56, isTrue, reason: '$fab');
          expect(label.left >= fab.left && label.right <= fab.right &&
              label.top >= fab.top && label.bottom <= fab.bottom, isTrue,
              reason: 'label $label cut off by the button $fab');
          // The time is inside its box, on one line: the box grew with it.
          final time = tester.getRect(find.text('09:05'));
          final box = tester.getRect(
              find.ancestor(of: find.text('09:05'), matching: find.byType(Container)).first);
          expect(box.width, greaterThanOrEqualTo(52));
          expect(box.height, greaterThanOrEqualTo(52));
          expect(box.contains(time.topLeft) && box.contains(time.bottomRight - const Offset(.1, .1)),
              isTrue, reason: 'time $time outside its box $box');
          expect(time.width, greaterThanOrEqualTo(14 * s * 5 - 0.5), reason: 'on one line');
        });

        testWidgets('the Add-slot sheet, ${w}dp at ${s}x', (tester) async {
          final seen = recordOverflows();
          fitWindow(tester, w, 4000, s);
          await open(tester);
          await openSheet(tester);
          expect(seen, isEmpty, reason: seen.join('\n\n'));
          expectTextNotShrunk(tester, sheet, s);
          whole(tester, 'Strategy Consultation', 12, s, within: sheet);
          whole(tester, '45 min', 13, s, within: sheet);
          // The dropdown text is whole, not clipped at 48px.
          final hour = find.descendant(of: sheet, matching: find.text('09h')).first;
          final field = find.ancestor(of: hour, matching: find.byWidgetPredicate(
              (x) => x is DropdownButton<int>)).first;
          expect(tester.getSize(field).height,
              greaterThanOrEqualTo(tester.getSize(hour).height));
        });
      }
    }

    for (final w in fitPhones.keys) {
      testWidgets('the cancel dialog at 3.0x on a ${w}dp phone can be read and answered',
          (tester) async {
        final seen = recordOverflows();
        fitWindow(tester, w, 6000, 3);
        await open(tester);
        tester.view.physicalSize = Size(w.toDouble(), fitPhones[w]!);
        await tester.pumpAndSettle();
        final cancel = find.text('Cancel');
        await tester.ensureVisible(cancel);
        await tester.pumpAndSettle();
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.text('Cancel session?'), findsOneWidget);
        final dialog = find.byType(AlertDialog);
        expect(overflowsIn(tester, seen, dialog), isEmpty);
        // The message is whole in a scroll view tall enough to read a line of
        // it, and its end can be brought into view.
        final scroll = find.descendant(
            of: dialog, matching: find.byType(SingleChildScrollView));
        expect(scroll, findsWidgets, reason: 'the message scrolls');
        final message = find.text('The client will be notified and the slot reopened.');
        final port = tester.getRect(scroll.first);
        expect(port.height, greaterThanOrEqualTo(14 * 3 * 1.5), reason: 'a line is readable');
        tester.state<ScrollableState>(find.descendant(of: dialog,
            matching: find.byType(Scrollable)).first).position.jumpTo(
            tester.state<ScrollableState>(find.descendant(of: dialog,
                matching: find.byType(Scrollable)).first).position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.getRect(message).bottom, lessThanOrEqualTo(port.bottom + 0.5));
        expect(renderedFontSize(tester, message), greaterThanOrEqualTo(14 * 3));
        for (final t in ['Keep', 'Cancel session']) {
          expect(find.text(t).hitTestable(), findsOneWidget, reason: t);
        }
      });
    }

    testWidgets('empty calendar at 320dp, 3.0x', (tester) async {
      final seen = recordOverflows();
      server.reads['coach_availability'] = [];
      server.reads['coaching_calls'] = [];
      fitWindow(tester, 320, 6000, 3);
      await open(tester);
      expect(find.text('No availability published'), findsOneWidget);
      expect(seen, isEmpty, reason: seen.join('\n\n'));
      expect(tester.getSize(find.byType(ElevatedButton)).height, greaterThanOrEqualTo(44));
    });
  });

  group('targets', () {
    for (final s in [1.0, 3.0]) {
      testWidgets('every card target is at least 44×44 and named for its item (${s}x)',
          (tester) async {
        final h = tester.ensureSemantics();
        fitWindow(tester, 320, 6000, s);
        await open(tester);
        expectTargets(tester, find.byType(CoachAvailabilityScreen), atLeast: 6);
        expectNamedButton(tester, 'Delete Strategy Consultation slot, ${_dayLabel()} 09:05');
        expectNamedButton(tester, 'Delete Weekly Check-In slot, ${_dayLabel()} 13:05');
        expect(find.bySemanticsLabel(RegExp('^Delete Nutrition Review')), findsNothing,
            reason: 'a booked slot has no delete');
        final d = _day();
        expectNamedButton(tester,
            'Cancel session with Alexandria Montgomery, ${d.month}/${d.day} · 3:05 PM');
        expect(find.byTooltip('Add slot'), findsOneWidget);
        expect(find.byTooltip('Back'), findsOneWidget);
        h.dispose();
      });
    }

    testWidgets('a screen reader deletes the slot it named — one request', (tester) async {
      final h = tester.ensureSemantics();
      fitWindow(tester, 390, 2000, 1);
      await open(tester);
      tester.semantics.tap(
          find.semantics.byLabel('Delete Weekly Check-In slot, ${_dayLabel()} 13:05'));
      await tester.pumpAndSettle();
      final deletes = server.writes.where((w) => w.startsWith('DELETE')).toList();
      expect(deletes, hasLength(1));
      expect(deletes.single, contains('id=eq.s3'));
      expect(reported, isEmpty);
      h.dispose();
    });

    testWidgets('a delete in flight is announced, and cannot be pressed again',
        (tester) async {
      final h = tester.ensureSemantics();
      fitWindow(tester, 390, 2000, 1);
      await open(tester);
      server.deleteGate = Completer<void>();
      final label = 'Strategy Consultation slot, ${_dayLabel()} 09:05';
      tester.semantics.tap(find.semantics.byLabel('Delete $label'));
      await tester.pump(); // the delete is in flight for this frame
      final f = find.bySemanticsLabel('Deleting $label');
      expect(f, findsOneWidget);
      final d = tester.getSemantics(f).getSemanticsData();
      expect(d.hasAction(SemanticsAction.tap), isFalse, reason: 'no double fire');
      expect(d.flagsCollection.isLiveRegion, isTrue);
      server.deleteGate!.complete();
      server.deleteGate = null;
      await tester.pumpAndSettle();
      expect(server.writes.where((w) => w.startsWith('DELETE')), hasLength(1));
      h.dispose();
    });

    testWidgets('a screen reader cancels the session it named', (tester) async {
      final h = tester.ensureSemantics();
      fitWindow(tester, 390, 2000, 1);
      await open(tester);
      tester.semantics.tap(
          find.semantics.byLabel(RegExp('^Cancel session with Alexandria Montgomery')));
      await tester.pumpAndSettle();
      expect(find.text('Cancel session?'), findsOneWidget);
      h.dispose();
    });

    testWidgets('negative control: a session with no client name is not named after '
        'nobody', (tester) async {
      final h = tester.ensureSemantics();
      server.reads['coaching_calls'] = [
        {'id': 'c1', 'scheduled_at': _iso(6), 'duration_minutes': 30, 'call_type': 'check_in',
         'client_id': 'x', 'client': null},
      ];
      fitWindow(tester, 390, 2000, 1);
      await open(tester);
      expect(find.bySemanticsLabel(RegExp('^Cancel session with this client, ')), findsOneWidget);
      expect(find.text('Client'), findsOneWidget);
      h.dispose();
    });

    testWidgets('the Add-slot sheet: every target 44×44, named, and says what is chosen',
        (tester) async {
      final h = tester.ensureSemantics();
      fitWindow(tester, 320, 3000, 1);
      await open(tester);
      await openSheet(tester);
      expectTargets(tester, sheet, atLeast: 10);
      for (final l in ['Type: Weekly Check-In', 'Type: Strategy Consultation',
          'Type: Nutrition Review', 'Duration: 30 min', 'Duration: 45 min', 'Duration: 60 min']) {
        expectNamedButton(tester, l);
      }
      expect(find.byTooltip('Close Add Availability Slot'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Change date, ')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Hour')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Minute')), findsOneWidget);
      bool selected(String l) =>
          tester.getSemantics(find.bySemanticsLabel(l)).getSemanticsData()
              .flagsCollection.isSelected == Tristate.isTrue;
      expect(selected('Type: Weekly Check-In'), isTrue);
      expect(selected('Type: Strategy Consultation'), isFalse);
      h.dispose();
    });

    testWidgets('positive control: the choices touched are the ones published',
        (tester) async {
      fitWindow(tester, 900, 2400, 1);
      await open(tester);
      await openSheet(tester);
      await tester.tap(find.descendant(of: sheet, matching: find.text('Strategy Consultation')));
      await tester.tap(find.descendant(of: sheet, matching: find.text('60 min')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish Slot'));
      await tester.pumpAndSettle();
      final post = server.writes.singleWhere((w) => w.startsWith('POST'));
      expect(post, contains('"type":"consultation"'));
      expect(post, contains('"duration_minutes":60'));
      expect(reported, isEmpty);
    });

    testWidgets('choices made by screen reader, or at the edge of a target, are the '
        'ones published', (tester) async {
      final h = tester.ensureSemantics();
      fitWindow(tester, 390, 2000, 1);
      await open(tester);
      await openSheet(tester);
      tester.semantics.tap(find.semantics.byLabel('Type: Nutrition Review'));
      await tester.pumpAndSettle();
      // Touch the edge of the 44px target, outside the ~30px chip.
      final chip = tester.getRect(find.bySemanticsLabel('Duration: 45 min'));
      await tester.tapAt(chip.topCenter + const Offset(0, 2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish Slot'));
      await tester.pumpAndSettle();
      final post = server.writes.singleWhere((w) => w.startsWith('POST'));
      expect(post, contains('"type":"nutrition_review"'));
      expect(post, contains('"duration_minutes":45'));
      expect(reported, isEmpty);
      h.dispose();
    });

    for (final (w, h, s) in [(390, 844.0, 1.0), (320, 568.0, 3.0)]) {
    testWidgets("the last slot's delete is not under the Add Slot button, ${w}dp at ${s}x",
        (tester) async {
      server.reads['coach_availability'] = [
        for (var i = 0; i < 12; i++)
          {'id': 'n$i', 'slot_time': _iso(i ~/ 2), 'is_booked': false,
           'duration_minutes': 30, 'type': 'check_in'},
      ];
      server.reads['coaching_calls'] = [];
      fitWindow(tester, w, h, s);
      await open(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -40000));
      await tester.pumpAndSettle();
      final last = tester.getRect(find.byIcon(Icons.delete_outline_rounded).last);
      final fab = tester.getRect(find.byType(FloatingActionButton));
      expect(last.overlaps(fab), isFalse, reason: 'delete $last under the button $fab');
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).last);
      await tester.pumpAndSettle();
      expect(server.writes.where((w) => w.startsWith('DELETE')), hasLength(1));
      expect(find.text('Publish Slot'), findsNothing);
    });
    }
  });

  testWidgets('control: 1.0x on 390dp keeps its layout', (tester) async {
    fitWindow(tester, 390, 844, 1);
    await open(tester);
    Rect r(Finder f) => tester.getRect(f);
    final time = r(find.text('09:05')), type = r(find.text('Strategy Consultation'));
    final bin = r(find.byIcon(Icons.delete_outline_rounded).first);
    expect(time.right, lessThan(type.left), reason: 'the time beside the type');
    expect(type.right, lessThan(bin.left), reason: 'the delete at the right');
    expect((time.center.dy - bin.center.dy).abs(), lessThan(2), reason: 'one line');
    final name = r(find.text('Alexandria Montgomery')), cancel = r(find.text('Cancel'));
    expect(cancel.left, greaterThan(name.left + 100));
    expect((cancel.center.dy - name.center.dy).abs(), lessThan(60));
  });

  testWidgets('control: a delete by touch still removes the slot it is on', (tester) async {
    fitWindow(tester, 390, 844, 1);
    await open(tester);
    await tester.tap(find.byTooltip('Remove slot').first);
    await tester.pumpAndSettle();
    expect(server.writes.single, contains('id=eq.s1'));
    expect(reported, isEmpty);
  });
}
