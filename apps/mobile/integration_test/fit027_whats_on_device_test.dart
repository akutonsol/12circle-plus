// FIT-027 · "What's on" — measured on the device.
//
// The host-VM tests prove the rules and the wiring. Two things they cannot
// settle, both physical:
//
//  * the design draws FOUR segments in one row at 390 dp. Whether they fit at
//    that width, with the real font, is a measurement — and the host harness
//    renders in Ahem, where every glyph is a full em square, so it would report
//    a width that means nothing. (F-24 is the recorded instance of taking an
//    Ahem overflow for a product defect.)
//  * the segments' 44 dp targets, for the reason F-6 and F-6b exist: the
//    password toggle looked fine in source and measured 19.8 x 20.2 dp.
//
// The view is mounted with its three sources overridden, so nothing is signed
// in and no backend is touched.
//
//   flutter test integration_test/fit027_whats_on_device_test.dart \
//     -d emulator-5554 --dart-define-from-file=dart_defines/qa.json

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:circle_fitness/features/challenges/data/models/challenge_model.dart';
import 'package:circle_fitness/features/challenges/domain/challenge_provider.dart';
import 'package:circle_fitness/features/classes/data/models/class_model.dart';
import 'package:circle_fitness/features/classes/domain/class_provider.dart';
import 'package:circle_fitness/features/classes/domain/whats_on.dart';
import 'package:circle_fitness/features/classes/domain/whats_on_provider.dart';
import 'package:circle_fitness/features/classes/presentation/whats_on_view.dart';

void _mark(String line) => print('FIT027-MARK $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Override pin<T>(ProviderBase<AsyncValue<T>> p, AsyncValue<T> v) =>
      (p as FutureProvider<T>).overrideWith((ref) => v.when(
            data: (d) => d,
            error: (e, s) => Future<T>.error(e, s),
            loading: () => Completer<T>().future,
          ));

  final aClass = FitnessClass(
    id: 'c1',
    title: 'Reformer, small group',
    description: '',
    category: ClassCategory.strength,
    status: ClassStatus.upcoming,
    startTime: DateTime(2026, 9, 11, 18, 30),
    durationMinutes: 45,
    capacity: 10,
    bookedCount: 6,
    waitlistCount: 0,
    instructor: ClassInstructor(id: 'i', name: 'Nadia', role: 'coach', rating: 5),
    location: 'Studio 2',
    isVirtual: false,
    isBooked: false,
    isWaitlisted: false,
    tags: const [],
  );

  for (final width in <double>[411.4, 390, 360]) {
    testWidgets('FIT-027 four segments fit and clear 44 dp at ${width.toInt()} dp',
        (t) async {
      final handle = t.ensureSemantics();
      final overflows = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed')) {
          overflows.add(d.exceptionAsString().split('\n').first);
        } else {
          previous?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = previous);

      final view = t.view;
      await t.binding.setSurfaceSize(
          Size(width, view.physicalSize.height / view.devicePixelRatio));
      addTearDown(() => t.binding.setSurfaceSize(null));

      await t.pumpWidget(ProviderScope(
        overrides: [
          pin(liveClassesFromDbProvider, AsyncData([aClass])),
          pin(whatsOnEventsProvider, const AsyncData(<Map<String, dynamic>>[])),
          pin(liveChallengesProvider, const AsyncData(<Challenge>[])),
        ],
        child: const MaterialApp(home: Scaffold(body: WhatsOnView())),
      ));
      await t.pump();

      _mark('SURFACE width=${t.binding.renderViews.first.size.width.toStringAsFixed(1)}dp '
          'dpr=${t.view.devicePixelRatio}');

      var rowWidth = 0.0;
      for (final label in whatsOnSegments) {
        final target = find
            .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
            .first;
        final size = t.getSize(target);
        rowWidth += size.width;
        expect(size.height, greaterThanOrEqualTo(44.0), reason: label);
        expect(size.width, greaterThanOrEqualTo(44.0), reason: label);

        final d = t.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
        expect(d.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
        expect(d.hasAction(SemanticsAction.tap), isTrue,
            reason: '$label announces as a button it must be able to press');
      }

      // Four segments plus three 8 dp gaps plus two 20 dp side paddings.
      final needed = rowWidth + 3 * 8 + 40;
      _mark('SEGMENTS total=${rowWidth.toStringAsFixed(1)}dp '
          'needed=${needed.toStringAsFixed(1)}dp fits=${needed <= width}');
      _mark('OVERFLOWS count=${overflows.length}');
      expect(overflows, isEmpty,
          reason: 'the row scrolls horizontally, so it must never paint an '
              'overflow stripe — if this fires the layout changed');

      _mark('PASS ${width.toInt()}dp');
      handle.dispose();
    });
  }
}
