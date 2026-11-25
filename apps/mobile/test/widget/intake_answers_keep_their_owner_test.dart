// P0-FL-59e · W1 / E4 / W30: one member's intake answers (name, DOB, PAR-Q,
// conditions, injuries, consent) are never saved as, or shown to, another.
//
// `_saveProgress`, `_finish`, the photo upload and the coach choice each asked
// "who is signed in?" when they ran. `/intake` stays mounted when the account
// changes in another tab, so merely hiding the tab wrote A's answers (and
// `onboarding_complete: false`) into B's `user_profiles`.
//
// The real screen, the real auth client, no AccountScope; the request log says
// whose token wrote which row.
//
// HOW TO SEE IT FAIL: put back a82f993's intake_flow_screen.dart; every test
// but the POSITIVE / NEGATIVE CONTROLs fails. (Round 2's "correction", "finished
// elsewhere", "nothing new" and Done-page tests fail on 5f8b7f3 too.)
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/onboarding/presentation/intake_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_image_picker.dart';
import '../support/member_switch_server.dart';
import '../support/pump_until.dart';

const _profilePage = 1, _photosPage = 21, _coachPage = 23, _finalPage = 26;

void main() {
  final server = MemberSwitchServer();
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    picker.install();
  });
  tearDownAll(picker.dispose);

  setUp(() async {
    server.reset();
    picker.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);

  Map<String, Object?> profile(String first, int step, {String? email}) => {
        'onboarding_step': step,
        'first_name': first,
        'last_name': '$first-son',
        'gender': 'male',
        'date_of_birth': '1990-01-02',
        'fitness_goal': 'lose_fat',
        'coaching_mode': 'self_guided',
        'parq_answers': {'1': first == 'Alice'},
        'medical_conditions': first == 'Alice' ? 'Pregnancy' : 'None',
        'injury_description': '$first knee',
        'consent_agreed': true,
      };

  void members({int a = _profilePage, int b = _profilePage}) =>
      server.rows['user_profiles'] = {
        memberA: [profile('Alice', a)],
        memberB: [profile('Bob', b)],
      };

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        availableCoachesProvider.overrideWith((ref) async => [
              {'id': 'coach-1', 'first_name': 'Cody', 'last_name': 'Ng'},
            ]),
      ],
      child: const MaterialApp(home: IntakeFlowScreen()),
    ));
    await settle(t);
    server.seen.clear();
    reported.clear();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  Future<void> switchTo(WidgetTester t, String uid) =>
      t.runAsync(() => signInAs(uid));

  /// The app losing focus / the tab being hidden, no frame drawn first.
  Future<void> hide(WidgetTester t) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle(t, 3);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Supabase.instance.client.auth.stopAutoRefresh();
    await settle(t, 3);
  }

  Iterable<SeenRequest> asB() => server.writes().where((w) => w.who == memberB);

  void nothingOfAlice() {
    for (final w in server.writes()) {
      if (w.who == memberB || '${w.query}${w.body}'.contains(memberB)) {
        expect('${w.body}', isNot(contains('Alice')));
      }
    }
    for (final s in ['Alice', 'Alice-son', 'Alice knee']) {
      expect(find.text(s), findsNothing, reason: '$s is still on screen');
    }
  }

  group('A -> B with the flow open', () {
    testWidgets("hiding the tab before any frame: A's answers are not written "
        "into B's row", (t) async {
      members();
      await open(t);
      expect(find.text('Alice'), findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      await hide(t);
      expect(asB(), isEmpty,
          reason: "hiding the tab wrote into B's row: ${asB().toList()}");
      nothingOfAlice();
      await close(t);
    });

    testWidgets("Continue tapped in the undrawn old page: nothing is sent; B's "
        'own answers are read and shown', (t) async {
      members();
      await open(t);
      await switchTo(t, memberB);
      await t.tap(find.text('Continue'));
      await settle(t);
      expect(asB(), isEmpty);
      expect(server.reads('user_profiles', memberB), hasLength(1));
      expect(find.text('Bob'), findsOneWidget);
      nothingOfAlice();
      await close(t);
    });

    testWidgets("B's own answers loaded: hiding the tab writes nothing (it "
        'would mark B incomplete); their Continue saves THEIR row', (t) async {
      members();
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      await hide(t);
      expect(server.writes(), isEmpty);
      await t.tap(find.text('Continue'));
      await settle(t);
      final w = server.writes('user_profiles').toList();
      expect(w, isNotEmpty);
      expect(w.map((r) => (r.who, r.query['id'])).toSet(),
          {(memberB, 'eq.$memberB')});
      expect(w.last.row['first_name'], 'Bob');
      expect(w.last.row['medical_conditions'], 'None');
      nothingOfAlice();
      await close(t);
    });

    testWidgets("B edits a field, then hides the tab: B's edit is saved to B",
        (t) async {
      members();
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      await t.enterText(find.widgetWithText(TextField, 'Bob'), 'Bobby');
      await hide(t);
      expect(server.writes('user_profiles').map((w) => w.query['id']).toSet(),
          {'eq.$memberB'});
      expect(server.writes('user_profiles').last.row['first_name'], 'Bobby');
      await close(t);
    });

    testWidgets("B edits, hides (saved), then puts it back and hides: the "
        'correction is saved too', (t) async {
      members();
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      await t.enterText(find.widgetWithText(TextField, 'Bob'), 'Bobby');
      await hide(t);
      expect(server.writes('user_profiles').last.row['first_name'], 'Bobby',
          reason: 'premise');
      server.seen.clear();
      await t.enterText(find.widgetWithText(TextField, 'Bobby'), 'Bob');
      await hide(t);
      expect(server.writes('user_profiles'), isNotEmpty,
          reason: "B's correction was lost: the row keeps the wrong answer");
      expect(server.writes('user_profiles').last.row['first_name'], 'Bob');
      expect(server.writes('user_profiles').map((w) => w.who).toSet(),
          {memberB});
      await close(t);
    });

    testWidgets("A's challenges are not B's: B has none, and saves none",
        (t) async {
      members();
      server.rows['user_profiles']![memberA]!.single['biggest_challenges'] = [
        'consistency', 'motivation',
      ];
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      await t.tap(find.text('Continue'));
      await settle(t);
      final w = server.writes('user_profiles').last;
      expect((w.who, w.query['id']), (memberB, 'eq.$memberB'));
      expect('${w.body}', isNot(contains('consistency')));
      await close(t);
    });

    testWidgets('B, who finished intake long ago, arrives by a switch: they are '
        'done, nothing marks them incomplete', (t) async {
      members();
      server.rows['user_profiles']![memberB]!.single['onboarding_complete'] =
          true;
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      expect(find.text("That's everything we needed."), findsOneWidget);
      await hide(t);
      expect(server.writes(), isEmpty);
      await close(t);
    });

    testWidgets("B's read pending: nothing of A's, and no save of any kind",
        (t) async {
      members();
      await open(t);
      final hold = server.holds['GET user_profiles:$memberB'] = Completer();
      await switchTo(t, memberB);
      await settle(t);
      nothingOfAlice();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await hide(t);
      expect(server.writes(), isEmpty);
      hold.complete();
      await settle(t);
      expect(find.text('Bob'), findsOneWidget);
      await close(t);
    });

    testWidgets("B's read failed: said as theirs, nothing of A's, no save; Try "
        "again reads B's", (t) async {
      members();
      await open(t);
      server.fails.add('GET user_profiles:$memberB');
      await switchTo(t, memberB);
      await settle(t);
      nothingOfAlice();
      expect(find.textContaining("Couldn't load your answers"), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      await hide(t);
      expect(server.writes(), isEmpty);
      server.fails.clear();
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text('Bob'), findsOneWidget);
      await close(t);
    });

    testWidgets("a typed draft and an open date picker of A's go with A",
        (t) async {
      members();
      await open(t);
      await t.enterText(find.widgetWithText(TextField, 'Alice'), 'Alicia');
      await t.tap(find.textContaining('1990'));
      await settle(t);
      expect(find.byType(DatePickerDialog), findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      await settle(t);
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.text('Alicia'), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
      expect(asB(), isEmpty);
      await close(t);
    });
  });

  testWidgets("A's first read answers after B signed in: dropped, before and "
      "after B's own", (t) async {
    for (final aFirst in [true, false]) {
      server.reset();
      members();
      final holdA = server.holds['GET user_profiles:$memberA'] = Completer();
      final holdB = server.holds['GET user_profiles:$memberB'] = Completer();
      await t.runAsync(() => signInAs(memberA));
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      (aFirst ? holdA : holdB).complete();
      await settle(t);
      nothingOfAlice();
      (aFirst ? holdB : holdA).complete();
      await settle(t);
      nothingOfAlice();
      expect(find.text('Bob'), findsOneWidget, reason: 'aFirst: $aFirst');
      expect(asB(), isEmpty);
      await close(t);
    }
  });

  group('switch during a save', () {
    testWidgets("step saved, then B signs in: A's answers are not sent, and B "
        'is not told about a failed save', (t) async {
      members();
      await open(t);
      final hold = server.holds['PATCH user_profiles:$memberA'] = Completer();
      server.fails.add('PATCH user_profiles:$memberA');
      await t.tap(find.text('Continue'));
      await settle(t, 2);
      expect(server.writes(), hasLength(1), reason: 'premise: phase 1 is out');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writes('user_profiles'), hasLength(1),
          reason: "phase 2 went out as B: ${server.writes().toList()}");
      expect(find.text(kIntakeProgressNotSavedMessage), findsNothing);
      nothingOfAlice();
      await close(t);
    });

    testWidgets("Finish, B signs in before it answers: no points and no plan "
        'for B, and B is not told they are done', (t) async {
      members(a: _finalPage);
      await open(t);
      final hold = server.holds['POST user_profiles:$memberA'] = Completer();
      await t.tap(find.text('Enter 12 Circle'));
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writes('user_profiles').single.row['id'], memberA);
      expect(server.writes('award_points'), isEmpty,
          reason: "A's assessment was scored to B");
      expect(server.writes('generate_client_plan'), isEmpty,
          reason: "B's plan was rebuilt");
      expect(find.text("That's everything we needed."), findsNothing);
      await close(t);
    });

    testWidgets('Finish tapped in the undrawn old page once B is signed in: '
        "A's answers are not upserted as B", (t) async {
      members(a: _finalPage);
      await open(t);
      await switchTo(t, memberB);
      await t.tap(find.text('Enter 12 Circle'));
      await settle(t);
      expect(asB(), isEmpty);
      await close(t);
    });

    testWidgets("the failed Finish's Retry, once B is signed in: gone, nothing "
        'is sent', (t) async {
      members(a: _finalPage, b: _finalPage);
      await open(t);
      server.fails.add('POST user_profiles:$memberA');
      await t.tap(find.text('Enter 12 Circle'));
      await settle(t);
      expect(find.text('Retry'), findsOneWidget, reason: 'premise');
      await switchTo(t, memberB);
      await t.tap(find.text('Retry'));
      await settle(t);
      expect(asB(), isEmpty);
      expect(find.text('Retry'), findsNothing);
      expect(origins(), contains('intake.finish'));
      await close(t);
    });

    testWidgets("Finish fails after B signed in: recorded; B is not told that "
        'their answers were not saved', (t) async {
      members(a: _finalPage, b: _finalPage);
      await open(t);
      final hold = server.holds['POST user_profiles:$memberA'] = Completer();
      server.fails.add('POST user_profiles:$memberA');
      await t.tap(find.text('Enter 12 Circle'));
      await settle(t, 2);
      await switchTo(t, memberB);
      await settle(t); // B's own answers are up
      hold.complete();
      await settle(t);
      expect(find.textContaining('could not save'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(asB(), isEmpty);
      expect(origins(), contains('intake.finish'));
      await close(t);
    });

    testWidgets("B signs in while A's answers (phase 2) are being saved and "
        'fail: theirs, B is not told', (t) async {
      members();
      await open(t);
      final key = 'PATCH user_profiles:$memberA';
      final phase1 = server.holds[key] = Completer();
      await t.tap(find.text('Continue'));
      await settle(t, 2);
      final phase2 = server.holds[key] = Completer();
      phase1.complete();
      await settle(t, 3);
      expect(server.writes('user_profiles'), hasLength(2),
          reason: 'premise: phase 2 is out');
      server.fails.add(key);
      await switchTo(t, memberB);
      await settle(t);
      phase2.complete();
      await settle(t);
      expect(server.writes('user_profiles').map((w) => (w.who, w.query['id'])),
          List.filled(2, (memberA, 'eq.$memberA')));
      expect(find.text(kIntakeProgressNotSavedMessage), findsNothing);
      expect(origins(), contains('intake.saveProgress.data'));
      nothingOfAlice();
      await close(t);
    });

    testWidgets("A -> B -> A while A's step is being saved: what was in memory "
        "then is not sent; A's own answers are read again", (t) async {
      members();
      await open(t);
      await t.enterText(find.widgetWithText(TextField, 'Alice'), 'Alicia');
      final hold = server.holds['PATCH user_profiles:$memberA'] = Completer();
      await t.tap(find.text('Continue'));
      await settle(t, 2);
      await switchTo(t, memberB);
      await settle(t);
      await switchTo(t, memberA);
      await settle(t);
      hold.complete();
      await settle(t);
      expect(server.writes('user_profiles'), hasLength(1),
          reason: 'phase 2 of the first visit');
      expect(find.text('Alice'), findsOneWidget);
      expect(asB(), isEmpty);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: the same member, token refreshed while the '
        'step is being saved: their answers follow, once', (t) async {
      members();
      await open(t);
      await t.enterText(find.widgetWithText(TextField, 'Alice'), 'Alicia');
      final hold = server.holds['PATCH user_profiles:$memberA'] = Completer();
      await t.tap(find.text('Continue'));
      await settle(t, 2);
      await t.runAsync(refreshSession);
      await settle(t, 2);
      hold.complete();
      await settle(t);
      final w = server.writes('user_profiles').toList();
      expect(w, hasLength(2));
      expect((w.last.who, w.last.row['first_name']), (memberA, 'Alicia'));
      expect(reported, isEmpty);
      await close(t);
    });
  });

  group('coach choice (W30)', () {
    testWidgets('tapped once B is signed in: B is linked to nobody', (t) async {
      members(a: _coachPage);
      await open(t);
      await switchTo(t, memberB);
      await t.tap(find.text('Select Coach'));
      await settle(t);
      expect(asB(), isEmpty);
      await close(t);
    });

    testWidgets("A's link answers after B signed in: B's other coach is not "
        'ended, no notification is sent as B, nothing is said', (t) async {
      members(a: _coachPage);
      server.rows['coach_client_relationships'] = {
        memberB: [
          {'coach_id': 'coach-1'},
          {'coach_id': 'coach-9'},
        ],
      };
      await open(t);
      final hold =
          server.holds['POST coach_client_relationships:$memberA'] = Completer();
      await t.tap(find.text('Select Coach'));
      await settle(t, 2);
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.writes('coach_client_relationships').single.row['client_id'],
          memberA);
      expect(asB(), isEmpty);
      expect(server.writes('notifications'), isEmpty);
      expect(find.textContaining('Meet Coach'), findsNothing);
      await close(t);
    });

    testWidgets("B signs in while A's other coaches are read: none is ended as "
        'B, nothing is said', (t) async {
      members(a: _coachPage);
      server.rows['coach_client_relationships'] = {
        memberA: [
          {'coach_id': 'coach-9'},
        ],
      };
      await open(t);
      final hold =
          server.holds['GET coach_client_relationships:$memberA'] = Completer();
      await t.tap(find.text('Select Coach'));
      await settle(t, 4);
      expect(server.reads('coach_client_relationships', memberA), isNotEmpty,
          reason: 'premise');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(server.seen.where((r) => r.who == memberB && r.target == 'subscriptions'),
          isEmpty, reason: 'the end of a coaching was started as B');
      expect(asB(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(origins(), contains('IntakeFlow.selectCoach.identity'));
      await close(t);
    });

    testWidgets("A's previous coaching could not be ended, B signed in "
        'meanwhile: B is not told', (t) async {
      members(a: _coachPage);
      server.rows['coach_client_relationships'] = {
        memberA: [
          {'coach_id': 'coach-9'},
        ],
      };
      await open(t);
      final key = 'PATCH coach_client_relationships:$memberA';
      final hold = server.holds[key] = Completer();
      server.fails.add(key);
      await t.tap(find.text('Select Coach'));
      await settle(t, 6);
      expect(server.writes('coach_client_relationships'), hasLength(2),
          reason: 'premise: the end is out');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(find.byType(SnackBar), findsNothing);
      expect(server.writes('notifications'), isEmpty);
      expect(origins(), contains('IntakeFlow.selectCoach.endPrevious'));
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: the coach is linked and told, by A',
        (t) async {
      members(a: _coachPage);
      await open(t);
      await t.tap(find.text('Select Coach'));
      await settle(t);
      expect(server.writes('coach_client_relationships').single.row['client_id'],
          memberA);
      expect(server.writes('notifications'), hasLength(1));
      expect(find.text('Meet Coach Cody Ng'), findsOneWidget);
      await close(t);
    });
  });

  group('baseline photos (E4)', () {
    Iterable<String> uploads() => server.seen
        .where((r) => r.target.startsWith('progress-photos/'))
        .map((r) => '${r.who}|${r.target}');

    Future<void> pick(WidgetTester t, String label, int n) async {
      await t.tap(find.text(label));
      await settle(t);
      await t.tap(find.text('Choose from Library'));
      await pumpUntil(t, () => find.text('Continue ($n/3)').evaluate().isNotEmpty,
          what: 'photo $n');
      await settle(t);
    }

    testWidgets("B signs in while A's front photo uploads: the side photo is "
        "not stored as B, and A's picks are gone", (t) async {
      members(a: _photosPage, b: _photosPage);
      server.objects.add('$memberA/back.jpg');
      await open(t);
      expect(find.text('Continue (1/3)'), findsOneWidget,
          reason: "premise: A's stored back photo is shown");
      await pick(t, 'Front Photo', 2);
      await pick(t, 'Side Photo', 3);
      final hold =
          server.holds['POST progress-photos/$memberA/front.png:$memberA'] =
              Completer();
      await t.tap(find.text('Continue (3/3)'));
      await pumpUntil(t, () => uploads().isNotEmpty, what: 'the upload');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      await t.pump(const Duration(milliseconds: 500));
      expect(uploads(), ['$memberA|progress-photos/$memberA/front.png']);
      expect(find.text('Continue'), findsOneWidget,
          reason: "B's step has no photos");
      expect(find.textContaining("Couldn't upload"), findsNothing);
      expect(asB(), isEmpty);
      await close(t);
    });

    testWidgets("A's pick answers after B signed in: it is not B's photo",
        (t) async {
      members(a: _photosPage, b: _photosPage);
      await open(t);
      final gate = Completer<Object?>();
      picker.answer = (_) => gate.future;
      await t.tap(find.text('Front Photo'));
      await settle(t);
      await t.tap(find.text('Choose from Library'));
      await settle(t);
      await switchTo(t, memberB);
      gate.complete(picker.photoPath);
      await settle(t, 12);
      expect(t.takeException(), isNull);
      expect(find.text('Continue (1/3)'), findsNothing);
      expect(uploads(), isEmpty);
      await close(t);
    });

    testWidgets('POSITIVE CONTROL: both photos are stored in their member\'s '
        'folder', (t) async {
      members(a: _photosPage);
      await open(t);
      await pick(t, 'Front Photo', 1);
      await pick(t, 'Side Photo', 2);
      await t.tap(find.text('Continue (2/3)'));
      await pumpUntil(t, () => uploads().length == 2, what: 'both uploads');
      expect(uploads(), [
        for (final s in ['front', 'side'])
          '$memberA|progress-photos/$memberA/$s.png',
      ]);
      await settle(t);
      await close(t);
    });
  });

  group('sign-out', () {
    testWidgets("A signs out: A's answers leave the screen; nothing is sent; A "
        'signs back in: the unsaved edit is there and saves to A', (t) async {
      members();
      await open(t);
      await t.enterText(find.widgetWithText(TextField, 'Alice'), 'Alicia');
      await t.runAsync(signOut);
      await settle(t);
      nothingOfAlice();
      expect(find.text('Alicia'), findsNothing);
      await hide(t);
      expect(server.writes(), isEmpty);
      await switchTo(t, memberA);
      await settle(t);
      expect(find.text('Alicia'), findsOneWidget,
          reason: '"Nothing was lost on this device" (EC-03)');
      await hide(t);
      expect(server.writes('user_profiles').map((w) => w.query['id']).toSet(),
          {'eq.$memberA'});
      expect(server.writes('user_profiles').last.row['first_name'], 'Alicia');
      await close(t);
    });

    testWidgets('A signs out and back in with nothing new: hiding the tab writes '
        'nothing; what they change next is saved', (t) async {
      members();
      await open(t);
      await t.runAsync(signOut);
      await settle(t);
      await switchTo(t, memberA);
      await settle(t);
      expect(find.text('Alice'), findsOneWidget);
      await hide(t);
      expect(server.writes(), isEmpty,
          reason: 'a save marks them incomplete: ${server.writes().toList()}');
      await t.enterText(find.widgetWithText(TextField, 'Alice'), 'Alicia');
      await hide(t);
      expect(server.writes('user_profiles').last.row['first_name'], 'Alicia');
      await close(t);
    });

    testWidgets('A signs out with an unsaved edit, finishes elsewhere, signs back '
        'in here: they are done; the old edit is not written over it',
        (t) async {
      members();
      await open(t);
      await t.enterText(find.widgetWithText(TextField, 'Alice'), 'Alicia');
      await t.runAsync(signOut);
      await settle(t);
      server.rows['user_profiles']![memberA]!.single['onboarding_complete'] =
          true;
      await switchTo(t, memberA);
      await settle(t);
      expect(find.text("That's everything we needed."), findsOneWidget);
      await hide(t);
      expect(server.writes(), isEmpty);
      await close(t);
    });

    testWidgets('A is back and their row cannot be read: nothing is sent, the '
        'edit is still theirs after Try again', (t) async {
      members();
      await open(t);
      await t.enterText(find.widgetWithText(TextField, 'Alice'), 'Alicia');
      await t.runAsync(signOut);
      await settle(t);
      server.fails.add('GET user_profiles:$memberA');
      await switchTo(t, memberA);
      await settle(t);
      expect(find.textContaining("Couldn't load your answers"), findsOneWidget);
      await hide(t);
      expect(server.writes(), isEmpty);
      server.fails.clear();
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text('Alicia'), findsOneWidget);
      await close(t);
    });

    testWidgets("A signs out, B signs in: B's own answers; A's are dropped for "
        'good', (t) async {
      members();
      await open(t);
      await t.enterText(find.widgetWithText(TextField, 'Alice'), 'Alicia');
      await t.runAsync(signOut);
      await settle(t);
      await switchTo(t, memberB);
      await settle(t);
      expect(find.text('Bob'), findsOneWidget);
      await hide(t);
      expect(server.writes(), isEmpty);
      await switchTo(t, memberA);
      await settle(t);
      expect(find.text('Alicia'), findsNothing,
          reason: 'read again from the server, not kept through B');
      expect(find.text('Alice'), findsOneWidget);
      await close(t);
    });

    testWidgets('answers given with nobody signed in are not saved over the '
        "stored ones of whoever signs in", (t) async {
      members();
      await t.runAsync(signOut);
      await open(t);
      await t.tap(find.text('Get Started'));
      await settle(t);
      await t.enterText(find.byType(TextField).first, 'Zed');
      await switchTo(t, memberB);
      await hide(t);
      expect(server.writes(), isEmpty);
      await settle(t);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Zed'), findsNothing);
      await close(t);
    });
  });

  group('the Done page', () {
    Future<void> finish(WidgetTester t) async {
      members(a: _finalPage);
      await open(t);
      await t.tap(find.text('Enter 12 Circle'));
      await settle(t);
      expect(find.text("That's everything we needed."), findsOneWidget,
          reason: 'premise');
      server.seen.clear();
    }

    testWidgets('hiding the tab on it does not mark them incomplete again',
        (t) async {
      await finish(t);
      await hide(t);
      expect(server.writes(), isEmpty,
          reason: '${server.writes().toList()}');
      await close(t);
    });

    testWidgets('signed out and back in on it: still done; hiding the tab '
        'does not mark them incomplete', (t) async {
      await finish(t);
      await t.runAsync(signOut);
      await settle(t);
      await hide(t);
      await switchTo(t, memberA);
      await settle(t);
      expect(find.text("That's everything we needed."), findsOneWidget);
      await hide(t);
      expect(server.writes(), isEmpty,
          reason: '${server.writes().toList()}');
      await close(t);
    });

    testWidgets("B signs in on it: B's own flow, not A's; A back: still done",
        (t) async {
      await finish(t);
      await switchTo(t, memberB);
      await settle(t);
      expect(find.text("That's everything we needed."), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
      await switchTo(t, memberA);
      await settle(t);
      expect(find.text("That's everything we needed."), findsOneWidget);
      await hide(t);
      expect(server.writes(), isEmpty);
      await close(t);
    });

    testWidgets('hiding the tab while Finish is being saved sends no '
        '"incomplete" after it', (t) async {
      members(a: _finalPage);
      await open(t);
      final hold = server.holds['POST user_profiles:$memberA'] = Completer();
      await t.tap(find.text('Enter 12 Circle'));
      await settle(t, 2);
      await hide(t);
      expect(server.writes('user_profiles').map((w) => w.method), ['POST']);
      hold.complete();
      await settle(t);
      await close(t);
    });
  });

  group('POSITIVE CONTROL: the same member', () {
    testWidgets('hiding the tab saves their answers to their row', (t) async {
      members();
      await open(t);
      await hide(t);
      final w = server.writes('user_profiles').toList();
      expect(w.length, greaterThanOrEqualTo(2));
      expect(w.map((r) => (r.who, r.query['id'])).toSet(),
          {(memberA, 'eq.$memberA')});
      expect(w[1].row['first_name'], 'Alice');
      expect(w[1].row['parq_answers'], {'1': true});
      expect(reported, isEmpty);
      await close(t);
    });

    testWidgets('a token refresh keeps the draft and reads nothing again; the '
        'save still goes to them', (t) async {
      members();
      await open(t);
      await t.enterText(find.widgetWithText(TextField, 'Alice'), 'Alicia');
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text('Alicia'), findsOneWidget);
      expect(server.reads('user_profiles'), isEmpty);
      await hide(t);
      expect(server.writes('user_profiles').last.row['first_name'], 'Alicia');
      await close(t);
    });

    testWidgets('a save that fails is still said and recorded, and nothing is '
        'lost', (t) async {
      members();
      await open(t);
      server.fails.add('PATCH user_profiles:$memberA');
      await hide(t);
      expect(find.text(kIntakeProgressNotSavedMessage), findsOneWidget);
      expect(origins(),
          containsAll(['intake.saveProgress.step', 'intake.saveProgress.data']));
      expect(find.text('Alice'), findsOneWidget);
      await close(t);
    });

    testWidgets('Finish: saved, awarded and planned as them, then done',
        (t) async {
      members(a: _finalPage);
      await open(t);
      await t.tap(find.text('Enter 12 Circle'));
      await settle(t);
      expect(server.writes('user_profiles').single.row['id'], memberA);
      expect(server.writes('award_points').single.who, memberA);
      expect(server.writes('generate_client_plan').single.who, memberA);
      expect(find.text("That's everything we needed."), findsOneWidget);
      await close(t);
    });

    testWidgets('NEGATIVE CONTROL: a member with no stored answers starts '
        'fresh, not as a failure', (t) async {
      server.rows['user_profiles'] = {
        memberA: [profile('Alice', _profilePage)],
      };
      await open(t);
      await switchTo(t, memberB);
      await settle(t);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      nothingOfAlice();
      await close(t);
    });
  });
}
