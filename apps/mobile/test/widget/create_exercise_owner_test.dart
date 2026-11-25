import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/exercise_database/domain/custom_exercise_provider.dart';
import 'package:circle_fitness/features/exercise_database/presentation/create_exercise_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_tools_server.dart';
import '../support/fake_image_picker.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-59d (W21, S-57a-2) · the exercise form belongs to the coach who filled
// it, with the REAL service and real sign-ins.
//
// It stayed filled over a switch on this device: Save made coach A's typed
// exercise coach B's; a save already running uploaded media and synced
// relations on A's exercise as B; an open edit turned into a media-only write
// (`update_exercise_media`) on A's exercise by B. And (routed from FL-60) a
// failure the service records was recorded a second time.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- apps/mobile/lib/features/
// exercise_database/presentation/create_exercise_screen.dart`; only the
// controls pass.

void main() {
  final server = CoachToolsServer();
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    picker.install();
  });
  tearDownAll(picker.dispose);

  setUp(() {
    server.reset();
    picker.reset();
    reported.clear();
    setFailureSink(reported.add);
    server.tables['user_profiles'] = [
      for (final u in [memberA, memberB]) {'id': u, 'role': 'coach'},
    ];
    server.tables['custom_exercises'] = [
      {'id': 'ex-a', 'coach_id': memberA, 'name': 'A private press', 'slug': 'a-private-press',
        'visibility': 'private', 'content_status': 'approved', 'description': 'A words'},
    ];
    server.answers['update_exercise_media'] = true;
  });
  tearDown(resetFailureSink);

  final name = find.widgetWithText(TextFormField, 'Exercise Name *');
  Iterable<Sent> sync() => server.to('sync_exercise_relations');
  Iterable<String> origins() => reported.map((f) => f.origin);
  Iterable<String> changed() => reported
      .where((f) => '${f.error}'.contains('signed-in account changed'))
      .map((f) => f.origin);
  String typedName(WidgetTester t) =>
      t.widget<TextFormField>(find.byType(TextFormField).first).controller!.text;

  Future<void> open(WidgetTester t, {String? editing}) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 2600);
    addTearDown(t.view.reset);
    await t.runAsync(() => signInAs(memberA));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(editingExerciseProvider.notifier).state = editing;
    await t.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: CreateExerciseScreen())));
    await settleReal(t);
  }

  VoidCallback saveTap(WidgetTester t) => t
      .widget<GestureDetector>(
          find.ancestor(of: find.text('Save'), matching: find.byType(GestureDetector)).first)
      .onTap!;

  Future<void> addImage(WidgetTester t) async {
    await t.tap(find.text('MEDIA'));
    await settleReal(t);
    await t.tap(find.text('Tap to add image'));
    await pumpUntil(t, () => find.text('Tap to add image').evaluate().isEmpty,
        what: 'the picked image');
  }

  void blank(WidgetTester t) {
    expect(find.text('Create Exercise'), findsOneWidget);
    expect(find.textContaining('A private'), findsNothing, reason: "A's exercise is shown to B");
    expect(find.textContaining('A words'), findsNothing);
  }

  Future<void> type(WidgetTester t, [String text = 'A private squat']) async {
    await t.enterText(name, text);
    await t.pump();
  }

  group('a new exercise', () {
    testWidgets("A→B: A's form is cleared; Save makes nothing of A's B's", (t) async {
      await open(t);
      await type(t);
      final save = saveTap(t);
      await switchTo(t, memberB);
      blank(t);
      expect(typedName(t), isEmpty);
      save(); // the tap already on its way
      await settleReal(t);
      expect(server.writes, isEmpty, reason: "A's exercise was created for B");
      await unmountAll(t);
    });

    testWidgets('a Save tapped before the form noticed writes nothing', (t) async {
      await open(t);
      await type(t);
      final save = saveTap(t);
      final b = t.runAsync(() => signInAs(memberB));
      save();
      await b;
      await settleReal(t);
      expect(server.writesBy(memberB), isEmpty);
      blank(t);
      await unmountAll(t);
    });

    testWidgets("switch during the create: nothing of A's goes on as B", (t) async {
      await open(t);
      await type(t);
      await addImage(t);
      final hold = server.hold((s) => s.table == 'custom_exercises' && s.isWrite);
      saveTap(t)();
      await settleReal(t);
      expect(server.writes.single.json, containsPair('coach_id', memberA));
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(server.writes, hasLength(1),
          reason: "uploads and relations of A's exercise ran as B: "
              '${server.writesBy(memberB).join('\n')}');
      blank(t); // not "Edit Exercise" of A's new row
      expect(find.text('Exercise Saved!'), findsNothing);
      expect(changed(), ['CreateExerciseScreen._save']);
      // B's own form works, and is B's.
      await t.tap(find.text('BASICS'));
      await settleReal(t);
      await type(t, 'B row');
      saveTap(t)();
      await settleReal(t);
      final b = server.writesBy(memberB).toList();
      expect(b.first.method, 'POST', reason: "a new row, not an update of A's");
      expect(b.first.json, allOf(containsPair('coach_id', memberB), containsPair('name', 'B row')));
      await unmountAll(t);
    });

    testWidgets('switch during the upload: no attach, no sync as B', (t) async {
      await open(t);
      await type(t);
      await addImage(t);
      final hold = server.hold((s) => s.path.startsWith('/storage/v1/'));
      saveTap(t)();
      await pumpUntil(t, () => server.writes.length == 2, what: 'the upload');
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(server.writesBy(memberB), isEmpty);
      expect(sync(), isEmpty);
      expect(changed(), ['CreateExerciseScreen._save']);
      expect(find.byType(SnackBar), findsNothing);
      await unmountAll(t);
    });

    testWidgets('switch during the first of two videos: the second is not uploaded as B',
        (t) async {
      await open(t);
      await type(t);
      await t.tap(find.text('MEDIA'));
      await settleReal(t);
      for (var i = 1; i <= 2; i++) {
        await t.tap(find.byIcon(Icons.add_circle_outline));
        await settleReal(t);
        await t.tap(find.text('Upload from device').first);
        await pumpUntil(t, () => find.text('Video selected').evaluate().length == i,
            what: 'video $i');
      }
      bool uploads(Sent s) => s.path.startsWith('/storage/v1/');
      final hold = server.hold(uploads);
      saveTap(t)();
      await pumpUntil(t, () => server.writes.any(uploads), what: 'the first upload');
      await switchNoFrame(t, memberB);
      hold.complete();
      await settleNoFrame(t);
      await settleReal(t);
      expect(server.writes.where(uploads).map((s) => s.who), [memberA],
          reason: "A's second video was uploaded by B");
      expect(server.writesBy(memberB), isEmpty);
      expect(changed(), ['CreateExerciseScreen._save']);
      await unmountAll(t);
    });

    testWidgets('switch during the last step: B is not told "Exercise Saved!"',
        (t) async {
      await open(t);
      await type(t);
      final hold = server.hold((s) => s.table == 'sync_exercise_relations');
      server.failing = (s) => s.table == 'sync_exercise_relations';
      saveTap(t)();
      await settleReal(t);
      expect(sync(), hasLength(1), reason: 'premise');
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Exercise Saved!'), findsNothing);
      blank(t);
      await unmountAll(t);
    });

    testWidgets('signed out, and the same coach again: a blank form that saves',
        (t) async {
      await open(t);
      await type(t);
      await signOutNow(t);
      blank(t);
      expect(typedName(t), isEmpty);
      await switchTo(t, memberA);
      blank(t);
      await type(t, 'Second');
      saveTap(t)();
      await settleReal(t);
      expect(server.writes.first.json, containsPair('name', 'Second'));
      expect(find.text('Exercise Saved!'), findsOneWidget);
      await unmountAll(t);
    });

    testWidgets("an image A picked is not put on B's form", (t) async {
      await open(t);
      await t.tap(find.text('MEDIA'));
      await settleReal(t);
      final gate = Completer<String?>();
      picker.answer = (_) => gate.future;
      await t.tap(find.text('Tap to add image'));
      await settleReal(t);
      await switchTo(t, memberB);
      gate.complete(picker.photoPath);
      await settleReal(t);
      expect(find.text('Tap to add image'), findsOneWidget);
      await unmountAll(t);
    });

    testWidgets("A's open Import JSON closes", (t) async {
      await open(t);
      await t.tap(find.text('Import JSON'));
      await settleReal(t);
      await t.enterText(find.byType(TextField).last, '{"exercise_name":"A private row"}');
      await switchTo(t, memberB);
      expect(find.text('Paste exercise JSON'), findsNothing);
      blank(t);
      await unmountAll(t);
    });

    testWidgets("a Submit fired after A's Exercise Saved! closed publishes nothing as B",
        (t) async {
      await open(t);
      await type(t);
      saveTap(t)();
      await settleReal(t);
      final submit = tapOf(t, 'Submit to Global Library');
      final before = server.writes.length;
      await switchTo(t, memberB);
      submit();
      await settleReal(t);
      expect(server.writes.length, before, reason: "A's exercise was published by B");
      expect(changed(), ['CreateExerciseScreen._submitForGlobal']);
      expect(find.byType(SnackBar), findsNothing);
      await unmountAll(t);
    });

    testWidgets("A's Exercise Saved! closes: B cannot submit A's exercise", (t) async {
      await open(t);
      await type(t);
      saveTap(t)();
      await settleReal(t);
      expect(find.text('Submit to Global Library'), findsOneWidget, reason: 'premise');
      final before = server.writes.length;
      await switchTo(t, memberB);
      expect(find.text('Submit to Global Library'), findsNothing);
      expect(server.writes.length, before);
      await unmountAll(t);
    });

    testWidgets('positive control: a token refresh keeps the form and its picture; '
        'A saves everything', (t) async {
      await open(t);
      await type(t);
      await addImage(t);
      await refreshToken(t);
      expect(find.text('Tap to add image'), findsNothing, reason: 'the pick is kept');
      saveTap(t)();
      await pumpUntil(t, () => find.text('Exercise Saved!').evaluate().isNotEmpty,
          what: 'saved');
      expect(server.writes.map((s) => '${s.method} ${s.path.split('/')[1]} ${s.who == memberA}'), [
        'POST rest true', // the row
        'POST storage true', // the image
        'PATCH rest true', // its URL
        'POST rest true', // relations
      ]);
      expect(reported, isEmpty);
      // (Refused, so the screen does not pop: there is no router here.)
      server.failing = (s) => s.isWrite;
      await t.tap(find.text('Submit to Global Library'));
      await settleReal(t);
      expect(server.writes.last.json, containsPair('visibility', 'global'));
      expect(server.writes.last.who, memberA);
      await unmountAll(t);
    });
  });

  group('an edit', () {
    testWidgets("A→B with A's edit open: no media write on A's exercise by B",
        (t) async {
      await open(t, editing: 'ex-a');
      expect(find.text('Edit Exercise'), findsOneWidget, reason: 'premise');
      expect(typedName(t), 'A private press', reason: 'premise');
      final save = saveTap(t);
      await switchTo(t, memberB);
      blank(t);
      save();
      await settleReal(t);
      expect(server.to('update_exercise_media'), isEmpty,
          reason: "the edit became a media-only write on A's exercise");
      expect(server.writes, isEmpty);
      await unmountAll(t);
    });

    for (final fails in [false, true]) {
      testWidgets("A's late prefill (${fails ? 'failed' : 'loaded'}) is not B's form",
          (t) async {
        final hold = server.hold(
            (s) => s.table == 'custom_exercises' && s.query.contains('id=eq.ex-a'));
        if (fails) server.failing = (s) => s.query.contains('id=eq.ex-a');
        await open(t, editing: 'ex-a');
        await switchTo(t, memberB);
        hold.complete();
        await settleReal(t);
        blank(t);
        expect(find.textContaining("Couldn't load this exercise"), findsNothing);
        await unmountAll(t);
      });
    }

    testWidgets('switch during the update: nothing more is written', (t) async {
      await open(t, editing: 'ex-a');
      final hold = server.hold((s) => s.isWrite);
      saveTap(t)();
      await settleReal(t);
      await switchTo(t, memberB);
      hold.complete();
      await settleReal(t);
      expect(server.writes.single.who, memberA);
      expect(changed(), ['CreateExerciseScreen._save']);
      await unmountAll(t);
    });

    testWidgets("switch while the videos are attached: A's muscles and equipment "
        'are not written as B', (t) async {
      await open(t, editing: 'ex-a');
      final hold = server.hold((s) => s.method == 'PATCH' &&
          s.json.containsKey('video_variants') && !s.json.containsKey('name'));
      saveTap(t)();
      await settleReal(t);
      expect(server.writes, hasLength(2), reason: 'premise: details, then videos');
      await switchNoFrame(t, memberB);
      hold.complete();
      await settleNoFrame(t);
      await settleReal(t);
      expect(sync(), isEmpty);
      expect(server.writesBy(memberB), isEmpty);
      expect(changed(), ['CreateExerciseScreen._save']);
      blank(t);
      await unmountAll(t);
    });

    for (final switches in [true, false]) {
      testWidgets(
          switches
              ? "switch during an editor's update: not submitted for review as B"
              : 'control: an editor\'s update is submitted for review', (t) async {
        server.tables['user_profiles'] = [
          {'id': memberA, 'role': 'admin'}, {'id': memberB, 'role': 'admin'},
        ];
        server.tables['custom_exercises'] = [
          {...server.tables['custom_exercises']!.single, 'visibility': 'global',
            'content_status': 'draft', 'instructions': ['Press up']},
        ];
        await open(t, editing: 'ex-a');
        final hold = server.hold((s) => s.method == 'PATCH' && s.json.containsKey('name'));
        saveTap(t)();
        await settleReal(t);
        expect(server.writes, hasLength(1), reason: 'premise: the details');
        if (switches) await switchNoFrame(t, memberB);
        hold.complete();
        await settleNoFrame(t);
        await settleReal(t);
        final review = server.to('review_exercise_content');
        if (switches) {
          expect(review, isEmpty, reason: "A's draft was submitted by B");
          expect(server.writesBy(memberB), isEmpty);
          expect(changed(), ['CreateExerciseScreen._save']);
        } else {
          expect(review.single.who, memberA);
        }
        await unmountAll(t);
      });
    }

    testWidgets("positive control: A saves A's edit", (t) async {
      await open(t, editing: 'ex-a');
      await type(t, 'A renamed');
      saveTap(t)();
      await settleReal(t);
      final w = server.writes.first;
      expect(w.method, 'PATCH');
      expect(w.query, contains('id=eq.ex-a'));
      expect(w.json, containsPair('name', 'A renamed'));
      expect(sync().single.who, memberA);
      expect(find.text('Exercise Saved!'), findsOneWidget);
      expect(reported, isEmpty);
      await unmountAll(t);
    });

    testWidgets('negative control: a missing exercise is said as missing', (t) async {
      await open(t, editing: 'ex-none');
      expect(find.textContaining("This exercise wasn't found"), findsOneWidget);
      expect(reported, isEmpty);
      await unmountAll(t);
    });
  });

  group('a failure is recorded exactly once', () {
    testWidgets('create', (t) async {
      server.failing = (s) => s.isWrite;
      await open(t);
      await type(t);
      saveTap(t)();
      await settleReal(t);
      expect(find.textContaining("Couldn't save the exercise"), findsOneWidget);
      expect(origins(), ['CustomExerciseService.createExercise']);
      await unmountAll(t);
    });

    testWidgets('update', (t) async {
      await open(t, editing: 'ex-a');
      server.zeroRows = (s) => true;
      saveTap(t)();
      await settleReal(t);
      expect(origins(), ['CustomExerciseService.updateExercise']);
      await unmountAll(t);
    });

    testWidgets('attaching the image', (t) async {
      server.failing = (s) => s.method == 'PATCH';
      await open(t);
      await type(t);
      await addImage(t);
      saveTap(t)();
      await pumpUntil(t, () => find.byType(SnackBar).evaluate().isNotEmpty, what: 'said');
      expect(origins(), ['CustomExerciseService.updateExercise']);
      await unmountAll(t);
    });

    testWidgets('control: a step the service does not record is still recorded', (t) async {
      server.failing = (s) => s.table == 'sync_exercise_relations';
      await open(t);
      await type(t);
      saveTap(t)();
      await settleReal(t);
      expect(origins(), ['CreateExerciseScreen.syncRelations']);
      await unmountAll(t);
    });
  });
}
