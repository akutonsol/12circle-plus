// FIT-005 · Connect — the relationship layer, measured on the device.
//
// The claims worth re-measuring here are physical: the section headings really
// do reach the platform as headings, the "Open …" affordances really are
// pressable from the accessibility tree, and the targets really clear 44 dp at
// the device's own density. F-6 and F-6b were both found by measuring a control
// that looked fine in source, and a `Semantics` that excludes its child drops
// the child's ACTIONS along with its labels — a defect that shipped once and
// was caught only by reading the real tree.
//
// The sections are mounted with their sources overridden, so nothing is signed
// in and no backend is touched.
//
//   flutter test integration_test/fit005_connect_device_test.dart \
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
import 'package:circle_fitness/features/classes/domain/whats_on_provider.dart';
import 'package:circle_fitness/features/community/data/models/post_model.dart';
import 'package:circle_fitness/features/community/domain/community_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/connect_sections_view.dart';

void _mark(String line) => print('FIT005-MARK $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Override pin<T>(ProviderBase<AsyncValue<T>> p, AsyncValue<T> v) =>
      (p as FutureProvider<T>).overrideWith((ref) => v.when(
            data: (d) => d,
            error: (e, s) => Future<T>.error(e, s),
            loading: () => Completer<T>().future,
          ));

  testWidgets('FIT-005 headings, affordances and targets on device', (t) async {
    final handle = t.ensureSemantics();

    final post = CommunityPost(
      id: 'p1',
      userId: 'u1',
      userName: 'Priya',
      userRole: 'client',
      content: 'Hit 70 kg on the hinge today',
      type: PostType.text,
      imageUrls: const [],
      reactions: const [],
      comments: const [],
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    );
    final grp = CommunityGroup(
      id: 'g1',
      name: 'Tues Lifters',
      description: '',
      emoji: '🏋️',
      memberCount: 12,
      isJoined: true,
    );

    await t.pumpWidget(ProviderScope(
      overrides: [
        pin(livePostsProvider, AsyncData([post])),
        pin(liveGroupsProvider, AsyncData([grp])),
        pin(liveClassesFromDbProvider, const AsyncData(<FitnessClass>[])),
        pin(whatsOnEventsProvider, const AsyncData(<Map<String, dynamic>>[])),
        pin(liveChallengesProvider, const AsyncData(<Challenge>[])),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ConnectSectionsView())),
      ),
    ));
    await t.pump();

    _mark('DEVICE dpr=${t.view.devicePixelRatio} '
        'width=${t.binding.renderViews.first.size.width.toStringAsFixed(1)}dp');

    for (final title in ['Feed', 'Groups', "What's on"]) {
      final heading = t.getSemantics(find.text(title)).getSemanticsData();
      expect(heading.hasFlag(SemanticsFlag.isHeader), isTrue, reason: title);

      final open = find.bySemanticsLabel('Open $title');
      expect(open, findsOneWidget);
      final d = t.getSemantics(open).getSemanticsData();
      final size = t.getSize(find
          .ancestor(of: find.text('Open $title'), matching: find.byType(GestureDetector))
          .first);

      _mark('SECTION "$title" header=${heading.hasFlag(SemanticsFlag.isHeader)} '
          'open=button:${d.hasFlag(SemanticsFlag.isButton)},'
          'tap:${d.hasAction(SemanticsAction.tap)} '
          'target=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}dp');

      expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(d.hasAction(SemanticsAction.tap), isTrue);
      expect(size.height, greaterThanOrEqualTo(44.0));
    }

    // The anchor's own row shapes, with real text metrics.
    expect(find.textContaining('Priya Hit 70 kg on the hinge today'), findsOneWidget);
    expect(find.text('Tues Lifters · 12 members'), findsOneWidget);

    _mark('PASS three sections, named, headed and pressable');
    handle.dispose();
  });
}
