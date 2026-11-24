import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/package_provider.dart';
import 'package:circle_fitness/features/coach/presentation/choose_package_screen.dart';
import 'package:circle_fitness/features/coach/presentation/coach_marketplace_screen.dart';
import 'package:circle_fitness/features/coach/presentation/coach_packages_screen.dart';
import 'package:circle_fitness/features/coach/presentation/coach_packages_view_sheet.dart';
import 'package:circle_fitness/features/coach/presentation/coach_pricing_sheet.dart';
import 'package:circle_fitness/features/payments/data/payment_service.dart';
import 'package:circle_fitness/features/payments/domain/payment_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/packages_server.dart';

// P0-FL-56b (b)–(e) · coach packages, pricing, marketplace and package choice
// tell the truth on failure.
//
// At f191d48:
//  (b) Coach Packages: a failed read had no retry and was unrecorded; a failed
//      refresh replaced the list. The editor's read of the session tiers was
//      uncaught: the fields were blank, and Save — where a blank price means
//      "don't offer" — deleted every tier. A partial tier save said only
//      "couldn't save". A package hidden instead of deleted looked untouched.
//  (c) Marketplace: the ranked read's failure was unrecorded; a failed list had
//      no retry; a failed status read offered "Request to Connect" on every
//      card, the client's own coach's included; failed prices showed as none.
//  (d) Choose Package: a failed schedule save escaped — the button spun for
//      good; a failed schedule READ left the days blank and savable (a save
//      replaces the whole schedule); a refused checkout spun too.
//  (e) Price sheet: the save's failure was not recorded.
//  + the packages view sheet: no retry, and a new read on every rebuild.
//
// HOW TO SEE IT FAIL: `git checkout f191d48 -- lib/features/coach/data/
// package_service.dart lib/features/coach/domain/package_provider.dart
// lib/features/coach/presentation/`.

const _otherHint = 'Try again in a moment. If it keeps happening, contact support.';
const _networkHint = 'Check your connection and try again.';

class _Payments extends PaymentService {
  int checkouts = 0;
  bool answer = true;
  Object? error;
  Completer<void>? hold;
  @override
  Future<bool> startCheckout({required String kind, String? coachId,
      String? eventId, String? packageId, String? tier}) async {
    checkouts++;
    await hold?.future;
    final e = error;
    if (e != null) throw e;
    return answer;
  }
}

Map<String, Object?> _pkg(String id, String coach, String name,
        {String type = 'monthly', num price = 99, int sessions = 0}) =>
    {'id': id, 'coach_id': coach, 'type': type, 'name': name, 'price': price,
     'sessions': sessions, 'description': '', 'active': true};

Map<String, Object?> _coach(String id, String name) => {
      'id': id, 'first_name': name, 'last_name': 'Stone',
      'specialties': <String>[], 'rating_avg': 4.8, 'review_count': 3,
      'pricing_monthly': 0, 'years_experience': 5,
    };

void main() {
  final server = PackagesServer();
  final reported = <AppFailure>[];
  late _Payments payments;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPackagesSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    payments = _Payments();
    await Supabase.instance.client.auth.recoverSession(sessionFor(userA));
  });
  tearDown(resetFailureSink);

  List<String> origins() => [for (final f in reported) f.origin];

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  ProviderContainer containerOf(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(Scaffold).first));

  Future<void> pumpApp(WidgetTester t, Widget app,
      {List<Override> overrides = const [], Size size = const Size(900, 2600),
      double textScale = 1}) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(t.view.reset);
    t.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(ProviderScope(overrides: [
      paymentServiceProvider.overrideWithValue(payments),
      coachConnectStatusProvider
          .overrideWith((ref) async => const {'connected': true, 'charges_enabled': true}),
      ...overrides,
    ], child: app));
    await settle(t);
  }

  /// Signs out, then in as [uid], through the REAL auth stream.
  Future<void> switchTo(WidgetTester t, String? uid, {bool observe = true}) async {
    await t.runAsync(() => Supabase.instance.client.auth.signOut());
    if (observe) await settle(t);
    if (uid != null) {
      await t.runAsync(() =>
          Supabase.instance.client.auth.recoverSession(sessionFor(uid)));
    }
    await settle(t);
  }

  Finder button(String text) => find.ancestor(
      of: find.text(text), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
  bool enabled(WidgetTester t, String text) =>
      t.widget<ButtonStyleButton>(button(text)).onPressed != null;
  bool live(WidgetTester t, Finder f) => t
      .widgetList<Semantics>(find.ancestor(of: f, matching: find.byType(Semantics)))
      .any((s) => s.properties.liveRegion ?? false);

  /// The load failure for [what] is said, live, with a >= 44px retry, and no
  /// backend text.
  void expectLoadFailure(WidgetTester t, String what, {String hint = _otherHint}) {
    final title = find.text("Couldn't load $what");
    expect(title, findsOneWidget);
    expect(find.textContaining(hint), findsWidgets);
    expect(live(t, title), isTrue, reason: 'announced');
    expect(find.textContaining(secret), findsNothing);
    final size = t.getSize(button('Try again').first);
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
  }

  // ── (b) Coach Packages ────────────────────────────────────────────────────
  group('Coach Packages', () {
    Future<void> open(WidgetTester t, {List<Override> overrides = const [],
            Size size = const Size(900, 2600), double textScale = 1}) =>
        pumpApp(t, const MaterialApp(home: CoachPackagesScreen()),
            overrides: overrides, size: size, textScale: textScale);

    testWidgets('a failed read says so, never "No packages yet"; the retry '
        'fires once, then shows the list', (t) async {
      server.readMode['coach_packages'] = Answer.fails;
      server.packages.add(_pkg('p1', userA, 'Solo Monthly'));
      await open(t);
      expectLoadFailure(t, 'your packages');
      expect(find.textContaining('No packages yet'), findsNothing);
      expect(origins(), ['myPackagesProvider']);

      server.readMode.clear();
      server.readGate['coach_packages'] = Completer();
      final before = server.readsOf('coach_packages');
      await t.tap(find.text('Try again'));
      await t.pump(const Duration(milliseconds: 50));
      expect(server.readsOf('coach_packages'), before + 1);
      expect(find.text("Couldn't load your packages"), findsOneWidget,
          reason: 'stays, busy');
      expect(find.text('Try again'), findsNothing);
      await t.tap(find.byType(TextButton), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 50));
      expect(server.readsOf('coach_packages'), before + 1, reason: 'no double fire');

      server.readGate.remove('coach_packages')!.complete();
      await settle(t);
      expect(find.text('Solo Monthly'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
    });

    testWidgets('a connection failure gets the connection hint', (t) async {
      server.readMode['coach_packages'] = Answer.network;
      await open(t);
      // postgrest-dart retries a GET that throws (1 + 2 + 4 s, fake clock).
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(seconds: 1));
      }
      expectLoadFailure(t, 'your packages', hint: _networkHint);
    });

    testWidgets('a failed refresh keeps the list and says so', (t) async {
      server.packages.add(_pkg('p1', userA, 'Solo Monthly'));
      await open(t);
      expect(find.text('Solo Monthly'), findsOneWidget, reason: 'premise');
      server.readMode['coach_packages'] = Answer.fails;
      containerOf(t).invalidate(myPackagesProvider);
      await settle(t);
      expect(find.text('Solo Monthly'), findsOneWidget,
          reason: 'THE defect: the failure replaced the list');
      expectLoadFailure(t, 'your packages');
      expect(find.textContaining('may be out of date'), findsWidgets);
    });

    testWidgets('negative control: a genuine empty list stays empty', (t) async {
      await open(t);
      expect(find.textContaining('No packages yet'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });

    testWidgets('positive control: the list, with nothing said', (t) async {
      server.packages.add(_pkg('p1', userA, 'Solo Monthly'));
      await open(t);
      expect(find.text('Solo Monthly'), findsOneWidget);
      expect(find.text('Hidden from clients'), findsNothing);
      expect(reported, isEmpty);
    });

    testWidgets('320px at 2x text: the failure wraps, nothing overflows or '
        'shrinks', (t) async {
      server.readMode['coach_packages'] = Answer.fails;
      await open(t, size: const Size(320, 568), textScale: 2);
      expect(t.takeException(), isNull);
      final title = find.text("Couldn't load your packages");
      expect(t.widget<Text>(title).style!.fontSize, 13);
      expect(t.renderObject(title), isNotNull);
      expect(MediaQuery.textScalerOf(t.element(title)).scale(13), 26);
      expect(find.ancestor(of: title, matching: find.byType(FittedBox)), findsNothing);
    });

    Future<void> delete(WidgetTester t) async {
      await t.tap(find.byIcon(Icons.more_horiz).first);
      await settle(t);
      await t.tap(find.text('Delete'));
      await settle(t);
    }

    testWidgets('a delete that removes nothing is said, and the list re-read',
        (t) async {
      server.packages.add(_pkg('p1', userA, 'Solo Monthly'));
      await open(t);
      server.writeMode = (_) => Answer.zeroRows;
      final before = server.readsOf('coach_packages');
      await delete(t);
      expect(find.textContaining("Couldn't delete this package"), findsOneWidget,
          reason: 'THE defect: a 0-row delete read as deleted');
      expect(origins(), ['CoachPackagesScreen.deletePackage']);
      expect(find.text('Solo Monthly'), findsOneWidget);
      expect(server.readsOf('coach_packages'), before + 1);
    });

    testWidgets('a package hidden because a schedule uses it says it is hidden',
        (t) async {
      server.packages.add(_pkg('p1', userA, 'Solo Monthly'));
      await open(t);
      server.writeMode =
          (l) => l.startsWith('DELETE') ? Answer.foreignKey : Answer.ok;
      await delete(t);
      expect(find.text('Hidden from clients'), findsOneWidget,
          reason: 'THE defect: the card looked untouched');
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
      const said = "Can't delete a package clients are using — "
          'hidden from clients instead.';
      expect(find.text(said), findsOneWidget,
          reason: 'THE defect: Delete became hide and nothing was announced');
      expect(live(t, find.text(said)), isTrue);
    });

    testWidgets("A's package hidden after B signed in is not announced to B", (t) async {
      server.packages.add(_pkg('p1', userA, 'Solo Monthly'));
      await open(t);
      server.writeMode =
          (l) => l.startsWith('DELETE') ? Answer.foreignKey : Answer.ok;
      final gate = server.writeGate = Completer();
      await delete(t);
      await switchTo(t, userB);
      gate.complete();
      await settle(t);
      expect(server.packages.single['active'], isFalse, reason: 'premise');
      expect(find.textContaining('hidden from clients instead'), findsNothing);
    });

    testWidgets('positive control: a delete removes it and says nothing', (t) async {
      server.packages.add(_pkg('p1', userA, 'Solo Monthly'));
      await open(t);
      await delete(t);
      expect(find.text('Solo Monthly'), findsNothing);
      expect(find.textContaining('No packages yet'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(reported, isEmpty);
    });

    // The session-tier editor.
    const saveTiers = 'Save session packages';
    void seedTiers() => server.packages.addAll([
          for (final s in [4, 8])
            _pkg('b$s', userA, 'Pack $s', type: 'bulk', price: s * 100, sessions: s),
        ]);
    Future<void> editTiers(WidgetTester t) async {
      await t.tap(find.text('New Package'));
      await settle(t);
      await t.tap(find.text('Session Package').last);
      await settle(t);
    }

    Future<void> tapSave(WidgetTester t) async {
      await t.ensureVisible(button(saveTiers));
      await t.tap(button(saveTiers), warnIfMissed: false);
      await settle(t);
    }

    testWidgets('tiers that could not be read: Save is paused, no tier is '
        'deleted; the retry shows them', (t) async {
      seedTiers();
      await open(t);
      server.readMode['coach_packages'] = Answer.fails;
      await editTiers(t);
      expect(t.takeException(), isNull, reason: 'THE defect: escaped unhandled');
      expectLoadFailure(t, 'your session packages');
      expect(find.textContaining('Saving is paused until they load.'), findsOneWidget);
      expect(find.text('Use suggested prices'), findsNothing);
      expect(origins(), ['CoachPackagesScreen._PackageEditor._loadTiers']);
      server.readMode.clear();
      await tapSave(t);
      expect(server.writes, isEmpty,
          reason: 'THE defect: Save with unread (blank) tiers DELETED them all');
      expect(server.packages, hasLength(2));

      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text('400'), findsOneWidget);
      expect(find.text('Pack 8'), findsWidgets);
      await tapSave(t);
      expect(server.packages, hasLength(2));
      expect(find.text(saveTiers), findsNothing, reason: 'saved: closed');
    });

    testWidgets('Save after a failed tier read deletes no tier', (t) async {
      seedTiers();
      await open(t);
      server.readMode['coach_packages'] = Answer.fails;
      await editTiers(t);
      t.takeException(); // f191d48: the read's failure escaped unhandled
      server.readMode.clear();
      await tapSave(t);
      t.takeException();
      expect([for (final p in server.packages) p['id']], ['b4', 'b8'],
          reason: 'THE defect: blank (unread) prices deleted every tier');
    });

    testWidgets('Save tapped in the same frame as "Session Package": the button '
        'is still the enabled "Save package", and no tier is deleted', (t) async {
      seedTiers();
      await open(t);
      await t.tap(find.text('New Package'));
      await settle(t);
      await t.ensureVisible(button('Save package'));
      await t.pump();
      expect(enabled(t, 'Save package'), isTrue, reason: 'premise');
      // No frame between the two taps, and the tiers are not read yet (only that
      // read is held: the save's own would answer).
      final gate = server.readGate['coach_packages'] = Completer();
      await t.tap(find.text('Session Package').last);
      server.readGate.remove('coach_packages');
      expect(enabled(t, 'Save package'), isTrue, reason: 'premise: still enabled');
      await t.tap(button('Save package'));
      await settle(t);
      expect(server.writes, isEmpty,
          reason: 'blank (unread) prices would delete every tier');
      expect([for (final p in server.packages) p['id']], ['b4', 'b8']);
      gate.complete();
      await settle(t);
      expect(find.text('400'), findsOneWidget, reason: 'still open, tiers read');
    });

    testWidgets('while a save is in flight the button says "Saving"', (t) async {
      await open(t);
      await editTiers(t);
      await t.enterText(find.widgetWithText(TextField, 'Price').first, '350');
      server.writeGate = Completer();
      expect(find.bySemanticsLabel('Saving'), findsNothing);
      await tapSave(t);
      expect(find.bySemanticsLabel('Saving'), findsOneWidget);
      server.writeGate!.complete();
      await settle(t);
      expect(find.bySemanticsLabel('Saving'), findsNothing);
      expect(server.packages.single['price'], 350);
    });

    testWidgets('tiers still being read: Save is paused', (t) async {
      seedTiers();
      await open(t);
      server.readGate['coach_packages'] = Completer();
      await editTiers(t);
      expect(enabled(t, saveTiers), isFalse);
      await tapSave(t);
      expect(server.writes, isEmpty);
      server.readGate.remove('coach_packages')!.complete();
      await settle(t);
      expect(find.text('400'), findsOneWidget);
      expect(enabled(t, saveTiers), isTrue);
    });

    testWidgets('negative control: a coach with no tiers gets blank fields and '
        'can save', (t) async {
      await open(t);
      await editTiers(t);
      expect(find.textContaining("Couldn't"), findsNothing);
      await t.enterText(find.widgetWithText(TextField, 'Price').first, '350');
      await tapSave(t);
      expect(server.packages.single['price'], 350);
      expect(find.text(saveTiers), findsNothing);
      expect(reported, isEmpty);
    });

    testWidgets('a partial save says what was and was not saved, is recorded, '
        're-reads the list, and can be completed', (t) async {
      await open(t);
      await editTiers(t);
      await t.tap(find.text('Use suggested prices'));
      await t.pump();
      server.writeMode = (l) => l.contains('"sessions":12') ? Answer.fails : Answer.ok;
      final before = server.readsOf('coach_packages');
      await tapSave(t);
      const msg = 'Only part of this was saved: your changes to the 4- and '
          "8-session packages are saved. Couldn't save the 12- and 16-session "
          'packages — try again in a moment. If it keeps happening, contact support.';
      expect(find.text(msg), findsOneWidget);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(msg)),
          findsOneWidget);
      expect(live(t, find.text(msg)), isTrue);
      expect(origins(), ['CoachPackagesScreen._PackageEditor._save']);
      expect(find.textContaining(secret), findsNothing);
      expect(server.readsOf('coach_packages'), before + 2,
          reason: 'the save read the tiers; the list under the sheet re-read');

      server.writeMode = null;
      await tapSave(t);
      expect(find.text(saveTiers), findsNothing);
      expect([for (final p in server.packages) p['sessions']], [4, 8, 12, 16]);
    });

    testWidgets('a failure before anything was saved does not claim a part was',
        (t) async {
      await open(t);
      await editTiers(t);
      await t.tap(find.text('Use suggested prices'));
      await t.pump();
      server.writeMode = (_) => Answer.network;
      await tapSave(t);
      expect(find.text("Couldn't save this package — check your connection and try again."),
          findsOneWidget);
      expect(find.textContaining('Only part'), findsNothing);
      expect(server.packages, isEmpty);
    });

    // Identity.
    for (final observe in [true, false]) {
      for (final b in ['ok', 'fails', 'pending', 'empty']) {
        testWidgets('A → B (${observe ? 'sign-out seen' : 'same frame'}), B\'s '
            'read $b: nothing of A\'s', (t) async {
          server.packages.addAll([
            _pkg('pa', userA, 'Alpha Monthly'),
            if (b != 'empty') _pkg('pb', userB, 'Bravo Monthly'),
          ]);
          await open(t);
          expect(find.text('Alpha Monthly'), findsOneWidget, reason: 'premise');
          if (b == 'fails') server.readMode['coach_packages'] = Answer.fails;
          if (b == 'pending') server.readGate['coach_packages'] = Completer();
          await switchTo(t, userB, observe: observe);
          expect(find.text('Alpha Monthly'), findsNothing);
          switch (b) {
            case 'ok':
              expect(find.text('Bravo Monthly'), findsOneWidget);
            case 'fails':
              expectLoadFailure(t, 'your packages');
              expect(find.textContaining('may be out of date'), findsNothing);
            case 'pending':
              expect(find.byType(CircularProgressIndicator), findsOneWidget);
              expect(find.textContaining('No packages yet'), findsNothing);
              server.readGate.remove('coach_packages')!.complete();
              await settle(t);
              expect(find.text('Bravo Monthly'), findsOneWidget);
            case 'empty':
              expect(find.textContaining('No packages yet'), findsOneWidget);
          }
          expect(find.text('Alpha Monthly'), findsNothing);
        });
      }
    }

    for (final late in ['answer', 'failure']) {
      testWidgets("A's late $late is dropped: B sees B's packages", (t) async {
        server.packages.addAll([
          _pkg('pa', userA, 'Alpha Monthly'), _pkg('pb', userB, 'Bravo Monthly')]);
        final gateA = server.readGate['coach_packages'] = Completer();
        await open(t);
        server.readGate.remove('coach_packages');
        await switchTo(t, userB);
        expect(find.text('Bravo Monthly'), findsOneWidget, reason: 'premise');
        if (late == 'failure') server.readMode['coach_packages'] = Answer.fails;
        gateA.complete();
        await settle(t);
        expect(find.text('Alpha Monthly'), findsNothing);
        expect(find.text('Bravo Monthly'), findsOneWidget);
        expect(find.textContaining("Couldn't"), findsNothing);
      });
    }

    testWidgets("A's failed read is not B's: B is loading, then B's packages",
        (t) async {
      server.packages.add(_pkg('pb', userB, 'Bravo Monthly'));
      server.readMode['coach_packages'] = Answer.fails;
      await open(t);
      expectLoadFailure(t, 'your packages');
      server.readMode.clear();
      final gateB = server.readGate['coach_packages'] = Completer();
      await switchTo(t, userB, observe: false);
      expect(find.textContaining("Couldn't"), findsNothing, reason: "A's failure");
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      server.readGate.remove('coach_packages');
      gateB.complete();
      await settle(t);
      expect(find.text('Bravo Monthly'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
    });

    testWidgets("A's open editor is dropped when B signs in: nothing of A's is "
        'written for B', (t) async {
      seedTiers();
      await open(t);
      await editTiers(t);
      expect(find.text('400'), findsOneWidget, reason: 'premise');
      await switchTo(t, userB, observe: false);
      expect(find.text('400'), findsNothing,
          reason: "THE defect: A's tiers, savable into B's account");
      expect(find.text(saveTiers), findsNothing);
      expect(server.writes, isEmpty);
      await editTiers(t);
      expect(find.text('400'), findsNothing, reason: 'B has no tiers');
      expect(enabled(t, saveTiers), isTrue);
    });

    testWidgets("A's connect prompt is not shown to B while B's status is unread",
        (t) async {
      const prompt = 'Connect your Stripe account to receive payments for these packages.';
      await open(t, overrides: [
        coachConnectStatusProvider.overrideWith((ref) {
          final who = ref.watch(currentUserProvider)?.id;
          return who == userA
              ? Future.value(const {'connected': false})
              : Completer<Map<String, dynamic>>().future;
        }),
      ]);
      expect(find.text(prompt), findsOneWidget, reason: 'positive control: A');
      await switchTo(t, userB);
      expect(find.text(prompt), findsNothing);
    });
  });

  // ── the packages view sheet ───────────────────────────────────────────────
  group('packages view sheet', () {
    Future<void> open(WidgetTester t) async {
      await pumpApp(t, MaterialApp(home: Scaffold(body: Builder(
        builder: (c) => TextButton(
            onPressed: () => showCoachPackagesSheet(c, userB, 'Kim'),
            child: const Text('open'))))), size: const Size(430, 900));
      await t.tap(find.text('open'));
      await settle(t);
    }

    testWidgets('a failed read is said and recorded; the retry shows them', (t) async {
      server.packages.add(_pkg('pb', userB, 'Bravo Monthly'));
      server.readMode['coach_packages'] = Answer.fails;
      await open(t);
      expectLoadFailure(t, 'packages');
      expect(find.textContaining("hasn't published"), findsNothing);
      expect(origins(), ['CoachPackagesViewSheet._load']);
      server.readMode.clear();
      server.readGate['coach_packages'] = Completer();
      final before = server.readsOf('coach_packages');
      await t.tap(find.text('Try again'));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Try again'), findsNothing, reason: 'busy');
      expect(server.readsOf('coach_packages'), before + 1);
      server.readGate.remove('coach_packages')!.complete();
      await settle(t);
      expect(find.text('Bravo Monthly'), findsOneWidget);
    });

    testWidgets('one read per opening: a rotation does not read again', (t) async {
      server.packages.add(_pkg('pb', userB, 'Bravo Monthly'));
      await open(t);
      expect(server.readsOf('coach_packages'), 1);
      t.view.physicalSize = const Size(900, 430);
      await settle(t);
      expect(server.readsOf('coach_packages'), 1,
          reason: 'THE defect: the read was started in build');
      expect(find.text('Bravo Monthly'), findsOneWidget);
    });

    testWidgets('negative control: a coach with none published stays empty', (t) async {
      await open(t);
      expect(find.text("Kim hasn't published any packages yet."), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });
  });

  // ── (c) marketplace ───────────────────────────────────────────────────────
  group('marketplace', () {
    Future<void> open(WidgetTester t, {Size size = const Size(900, 2600), double textScale = 1}) =>
        pumpApp(t, const MaterialApp(home: CoachMarketplaceScreen()),
            size: size, textScale: textScale);
    const request = 'Request to Connect';
    const paused = 'Unavailable until your coach connections load';
    String hint(WidgetTester t) =>
        t.getSemantics(find.text(request)).getSemanticsData().hint;
    List<String> requests() =>
        server.writes.where((w) => w.contains('coach_client_relationships')).toList();

    testWidgets('the list could not be read at all: said, never "No coaches '
        'found"; the retry shows them', (t) async {
      server.coaches = [_coach('c1', 'Avery')];
      server.readMode['rpc/marketplace_coaches'] = Answer.fails;
      server.readMode['public_profiles'] = Answer.fails;
      await open(t);
      expectLoadFailure(t, 'coaches');
      expect(find.text('No coaches found'), findsNothing);
      expect(origins(), containsAll(['coachMarketplaceProvider.ranked',
          'coachMarketplaceProvider.fallback']));
      server.readMode.clear();
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text('Avery Stone'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
    });

    testWidgets('only the ranking failed: the coaches show, the failure is recorded',
        (t) async {
      server.coaches = [_coach('c1', 'Avery')];
      server.readMode['rpc/marketplace_coaches'] = Answer.fails;
      await open(t);
      expect(find.text('Avery Stone'), findsOneWidget);
      expect(origins(), ['coachMarketplaceProvider.ranked'],
          reason: 'THE defect: swallowed unrecorded');
    });

    testWidgets('negative control: no coaches stays "No coaches found"', (t) async {
      await open(t);
      expect(find.text('No coaches found'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });

    testWidgets('a failed refresh keeps the coaches', (t) async {
      server.coaches = [_coach('c1', 'Avery')];
      await open(t);
      server.readMode['rpc/marketplace_coaches'] = Answer.fails;
      server.readMode['public_profiles'] = Answer.fails;
      containerOf(t).invalidate(coachMarketplaceProvider);
      await settle(t);
      expect(find.text('Avery Stone'), findsOneWidget);
      expectLoadFailure(t, 'coaches');
    });

    testWidgets('a status that could not be read never offers a request; the '
        'retry marks the client\'s coach', (t) async {
      server.coaches = [_coach('c1', 'Avery')];
      server.relationships[userA] = [{'coach_id': 'c1', 'status': 'pending'}];
      server.readMode['coach_client_relationships'] = Answer.fails;
      await open(t);
      expectLoadFailure(t, 'your coach connections');
      expect(origins(), ['coachMarketplace.relationshipStatus']);
      // Readable again: the request's own check would pass, so only the paused
      // button stops it.
      server.readMode.clear();
      await t.tap(find.text(request));
      await settle(t);
      expect(requests(), isEmpty,
          reason: 'THE defect: an unread status read as "no relationship"');
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text('Request Sent'), findsOneWidget);
      expect(find.text(request), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
    });

    testWidgets('a status still being read does not offer a request', (t) async {
      server.coaches = [_coach('c1', 'Avery')];
      final gate = server.readGate['coach_client_relationships'] = Completer();
      await open(t);
      // Only the status read stays held (not the request's own check).
      server.readGate.remove('coach_client_relationships');
      await t.tap(find.text(request));
      await settle(t);
      expect(requests(), isEmpty);
      gate.complete();
      await settle(t);
      await t.tap(find.text(request));
      await settle(t);
      expect(requests(), hasLength(1));
    });

    testWidgets('positive control: no relationship — the request is sent once on '
        'a double tap, and said', (t) async {
      server.coaches = [_coach('c1', 'Avery')];
      await open(t);
      expect(t.getSize(find.ancestor(of: find.text(request),
          matching: find.byType(GestureDetector)).first).height, greaterThanOrEqualTo(44));
      server.writeGate = Completer();
      await t.tap(find.text(request));
      await t.tap(find.text(request));
      await t.pump(const Duration(milliseconds: 50));
      server.relationships[userA] = [{'coach_id': 'c1', 'status': 'pending'}];
      server.writeGate!.complete();
      await settle(t);
      expect(requests(), hasLength(1), reason: 'no double fire');
      expect(find.textContaining('Request sent!'), findsOneWidget);
      expect(find.text('Request Sent'), findsOneWidget);
      expect(reported, isEmpty);
    });

    testWidgets('a failed request is recorded and said; it can be sent again', (t) async {
      server.coaches = [_coach('c1', 'Avery')];
      await open(t);
      server.writeMode = (_) => Answer.fails;
      await t.tap(find.text(request));
      await settle(t);
      const msg = "Couldn't send your request — try again in a moment. "
          'If it keeps happening, contact support.';
      expect(find.text(msg), findsOneWidget);
      expect(live(t, find.text(msg)), isTrue);
      expect(origins(), ['CoachMarketplaceScreen._requestCoach']);
      server.writeMode = null;
      server.writes.clear();
      await t.tap(find.text(request));
      await settle(t);
      expect(requests(), hasLength(1));
    });

    testWidgets('prices that could not be read are said, with a retry', (t) async {
      server.coaches = [_coach('c1', 'Avery')];
      server.packages.add(_pkg('p1', 'c1', 'Monthly', price: 199));
      server.readMode['coach_packages'] = Answer.fails;
      await open(t);
      expectLoadFailure(t, 'package prices');
      expect(origins(), ['coachPackagesProvider']);
      server.readMode.clear();
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text(r'Monthly from $199/mo'), findsOneWidget);
    });

    testWidgets('negative control: a coach with no packages shows no prices and '
        'no failure', (t) async {
      server.coaches = [_coach('c1', 'Avery')];
      await open(t);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(find.textContaining('from'), findsNothing);
      expect(reported, isEmpty);
    });

    testWidgets('320px at 2x text: the list failure does not overflow', (t) async {
      server.readMode['rpc/marketplace_coaches'] = Answer.fails;
      server.readMode['public_profiles'] = Answer.fails;
      await open(t, size: const Size(320, 568), textScale: 2);
      expect(t.takeException(), isNull);
      expect(MediaQuery.textScalerOf(
          t.element(find.text("Couldn't load coaches"))).scale(13), 26);
    });

    for (final b in ['ok', 'fails', 'pending']) {
      testWidgets("A → B, B's status $b: A's coach is not marked as B's", (t) async {
        server.coaches = [_coach('c1', 'Avery')];
        server.relationships[userA] = [{'coach_id': 'c1', 'status': 'active'}];
        server.relationships[userB] = [{'coach_id': 'c1', 'status': 'pending'}];
        await open(t);
        expect(find.text('Your Coach'), findsOneWidget, reason: 'premise');
        if (b == 'fails') server.readMode['coach_client_relationships'] = Answer.fails;
        final gate = Completer<void>();
        if (b == 'pending') server.readGate['coach_client_relationships'] = gate;
        await switchTo(t, userB, observe: false);
        expect(find.text('Your Coach'), findsNothing, reason: "A's coach");
        if (b != 'ok') {
          // The request's own check would pass: only the button stops it.
          server.readMode.clear();
          server.readGate.clear();
          await t.tap(find.text(request));
          await settle(t);
          expect(requests(), isEmpty, reason: "B's status is not known");
        }
        if (b == 'pending') {
          gate.complete();
          await settle(t);
        }
        if (b != 'fails') expect(find.text('Request Sent'), findsOneWidget);
        if (b == 'fails') expectLoadFailure(t, 'your coach connections');
      });
    }

    testWidgets("a same-client failed re-read keeps \"Your Coach\" and says so; a "
        'card not known to be theirs cannot be requested', (t) async {
      server.coaches = [_coach('c1', 'Avery'), _coach('c2', 'Blake')];
      server.relationships[userA] = [{'coach_id': 'c1', 'status': 'active'}];
      await open(t);
      // The request is sent, then the status cannot be re-read.
      server.writeGate = Completer();
      await t.tap(find.text(request));
      await settle(t);
      expect(requests(), hasLength(1), reason: 'premise: the write is in flight');
      server.readMode['coach_client_relationships'] = Answer.fails;
      server.writeGate!.complete();
      await settle(t);
      expect(find.text('Your Coach'), findsOneWidget);
      expectLoadFailure(t, 'your coach connections');
      expect(hint(t), paused, reason: 'a known status is not a current one');
      server.writes.clear();
      // Readable again (so the request's own check would pass), but the status
      // shown was not re-read: only the paused button stops the request.
      server.readMode.clear();
      await t.tap(find.text(request));
      await settle(t);
      expect(requests(), isEmpty,
          reason: 'a known but out-of-date status offered the request again');

      // Positive control: once it is re-read, the request goes.
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(hint(t), isEmpty);
      await t.tap(find.text(request));
      await settle(t);
      expect(requests(), hasLength(1));
    });

    testWidgets('a request paused by an unread status says why to a screen reader; '
        'one that is offered, or being sent, does not', (t) async {
      server.coaches = [_coach('c1', 'Avery')];
      server.readMode['coach_client_relationships'] = Answer.fails;
      await open(t);
      expect(hint(t), paused, reason: 'THE defect: a dimmed button with no reason');
      server.readMode.clear();
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(hint(t), isEmpty, reason: 'offered');
      server.writeGate = Completer();
      await t.tap(find.text(request));
      await t.pump(const Duration(milliseconds: 50));
      expect(hint(t), isEmpty, reason: 'being sent: the connections are known');
      server.writeGate!.complete();
      await settle(t);
      expect(requests(), hasLength(1));
    });
  });

  // ── (d) choose package ────────────────────────────────────────────────────
  group('choose package', () {
    Future<void> open(WidgetTester t, {Size size = const Size(900, 2600), double textScale = 1}) {
      final router = GoRouter(initialLocation: '/choose', routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME')), routes: [
          GoRoute(path: 'choose', builder: (_, __) =>
              const ChoosePackageScreen(coachId: 'c1', coachName: 'Avery')),
        ]),
        GoRoute(path: '/booking-handoff',
            builder: (_, __) => const Scaffold(body: Text('BOOKING'))),
      ]);
      return pumpApp(t, MaterialApp.router(routerConfig: router),
          size: size, textScale: textScale);
    }

    const pay = r'Continue to payment · $99/mo';
    const free = 'Confirm & save schedule';
    setUp(() => server.packages.addAll([
          _pkg('paid', 'c1', 'Paid Plan'),
          _pkg('free', 'c1', 'Free Plan', price: 0),
        ]));
    Future<void> choose(WidgetTester t, String name) async {
      await t.tap(find.text(name));
      await settle(t);
    }

    Future<void> tapLabel(WidgetTester t, String label) async {
      await t.ensureVisible(find.text(label));
      await t.tap(find.text(label), warnIfMissed: false);
      await settle(t);
    }

    const saveMsg = "Couldn't save your schedule — try again in a moment. "
        'If it keeps happening, contact support.';

    for (final (name, label) in [('Paid Plan', pay), ('Free Plan', free)]) {
      for (final a in [Answer.fails, Answer.zeroRows]) {
        testWidgets('$name: a schedule save that ${a.name} is said and recorded, '
            'and nothing follows it', (t) async {
          await open(t);
          await choose(t, name);
          server.writeMode = (_) => a;
          await tapLabel(t, label);
          expect(t.takeException(), isNull, reason: 'THE defect: escaped unhandled');
          expect(find.text(saveMsg), findsOneWidget);
          expect(live(t, find.text(saveMsg)), isTrue);
          expect(find.textContaining(secret), findsNothing);
          expect(origins(), ['ChoosePackageScreen._save']);
          expect(payments.checkouts, 0, reason: 'no payment for an unsaved schedule');
          expect(find.text('BOOKING'), findsNothing);
          expect(enabled(t, label), isTrue, reason: 'THE defect: spun for good');

          server.writeMode = null;
          await tapLabel(t, label);
          expect(server.schedules[userA], isNotNull);
          if (name == 'Free Plan') {
            expect(find.text('BOOKING'), findsOneWidget);
          } else {
            expect(payments.checkouts, 1);
          }
        });
      }
    }

    testWidgets('a connection failure gets the connection hint', (t) async {
      await open(t);
      await choose(t, 'Paid Plan');
      server.writeMode = (_) => Answer.network;
      await tapLabel(t, pay);
      expect(find.text("Couldn't save your schedule — check your connection and try again."),
          findsOneWidget);
    });

    testWidgets('positive control: saved, then checkout, said as before', (t) async {
      await open(t);
      await choose(t, 'Paid Plan');
      await tapLabel(t, pay);
      expect(payments.checkouts, 1);
      expect(server.schedules[userA]!['package_id'], 'paid');
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });

    testWidgets('a checkout the server refused says why; the button is back', (t) async {
      payments.error = const CheckoutRefused('You already have this plan.');
      await open(t);
      await choose(t, 'Paid Plan');
      await tapLabel(t, pay);
      expect(t.takeException(), isNull, reason: 'THE defect: escaped unhandled');
      expect(find.text('Schedule saved. You already have this plan.'), findsOneWidget);
      expect(enabled(t, pay), isTrue);
      expect(reported, isEmpty, reason: 'an answer, not a fault');
    });

    testWidgets('a checkout that throws is recorded and said', (t) async {
      payments.error = Exception(secret);
      await open(t);
      await choose(t, 'Paid Plan');
      await tapLabel(t, pay);
      expect(find.textContaining('Schedule saved, but we couldn’t open checkout'),
          findsOneWidget);
      expect(find.textContaining(secret), findsNothing);
      expect(origins(), ['ChoosePackageScreen._save.checkout']);
      expect(enabled(t, pay), isTrue);
    });

    for (final table in ['client_schedules', 'user_profiles']) {
      testWidgets('a failed read of $table pauses Save; the retry seeds the days',
          (t) async {
        if (table == 'client_schedules') {
          server.schedules[userA] = {
            'client_id': userA, 'package_id': 'paid', 'days': ['friday'],
            'session_time': '18:30', 'day_times': {'friday': '18:30'},
          };
        }
        server.readMode[table] = Answer.fails;
        await open(t);
        expect(t.takeException(), isNull, reason: 'THE defect: escaped unhandled');
        await choose(t, 'Paid Plan');
        expectLoadFailure(t, 'your training schedule');
        expect(find.textContaining('Saving is paused until it loads.'), findsOneWidget);
        expect(find.text('Mon'), findsNothing);
        await tapLabel(t, pay);
        expect(server.writes, isEmpty,
            reason: 'THE defect: a schedule never read could be replaced');
        expect(origins(), ['ChoosePackageScreen._seedDays']);

        server.readMode.clear();
        await t.tap(find.text('Try again'));
        await settle(t);
        if (table == 'client_schedules') {
          expect(find.text('Friday'), findsOneWidget);
          expect(find.text('Monday'), findsNothing);
          expect(find.text('CURRENT PLAN'), findsOneWidget);
        } else {
          expect(find.text('Monday'), findsOneWidget, reason: '3 days: Mon/Wed/Fri');
        }
        await tapLabel(t, pay);
        expect(payments.checkouts, 1);
      });
    }

    testWidgets('negative control: no schedule and no onboarding days is an '
        'answer — the client picks their own', (t) async {
      server.trainingDays = null;
      await open(t);
      await choose(t, 'Free Plan');
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(find.text('Pick your training days above to set times.'), findsOneWidget);
      await tapLabel(t, 'Tue');
      await tapLabel(t, free);
      expect(server.schedules[userA]!['days'], ['tuesday']);
      expect(find.text('BOOKING'), findsOneWidget);
      expect(reported, isEmpty);
    });

    testWidgets('packages that could not be read are said, with a retry; a failed '
        'refresh keeps them', (t) async {
      server.readMode['coach_packages'] = Answer.fails;
      await open(t);
      expectLoadFailure(t, 'packages');
      expect(find.textContaining('hasn’t published'), findsNothing);
      server.readMode.clear();
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text('Paid Plan'), findsOneWidget);

      server.readMode['coach_packages'] = Answer.fails;
      containerOf(t).invalidate(coachPackagesProvider('c1'));
      await settle(t);
      expect(find.text('Paid Plan'), findsOneWidget);
      expectLoadFailure(t, 'packages');
    });

    testWidgets('negative control: a coach with none published stays empty', (t) async {
      server.packages.clear();
      await open(t);
      expect(find.textContaining('hasn’t published any packages yet'), findsOneWidget);
      expect(find.textContaining("Couldn't"), findsNothing);
    });

    testWidgets('320px at 2x text: the failure does not overflow', (t) async {
      server.readMode['coach_packages'] = Answer.fails;
      await open(t, size: const Size(320, 568), textScale: 2);
      expect(t.takeException(), isNull);
      expect(MediaQuery.textScalerOf(
          t.element(find.text("Couldn't load packages"))).scale(13), 26);
    });

    Map<String, Object?> fridays(String uid) => {
          'client_id': uid, 'package_id': 'paid', 'days': ['friday'],
          'session_time': '18:30', 'day_times': {'friday': '18:30'},
        };
    for (final b in ['ok', 'fails', 'pending']) {
      testWidgets("A → B, B's schedule $b: A's plan and days are gone", (t) async {
        server.schedules[userA] = fridays(userA);
        server.trainingDays = 1; // B: one day, Wednesday
        await open(t);
        expect(find.text('CURRENT PLAN'), findsOneWidget, reason: 'premise');
        expect(find.text('Friday'), findsOneWidget, reason: 'premise');
        if (b == 'fails') server.readMode['client_schedules'] = Answer.fails;
        if (b == 'pending') server.readGate['client_schedules'] = Completer();
        await switchTo(t, userB, observe: false);
        expect(find.text('CURRENT PLAN'), findsNothing);
        expect(find.text('Friday'), findsNothing,
            reason: "THE defect: A's days, savable as B's");
        expect(find.text('Select a package'), findsOneWidget, reason: "A's choice");
        if (b == 'fails') expectLoadFailure(t, 'your training schedule');
        if (b == 'pending') {
          server.readGate.remove('client_schedules')!.complete();
          await settle(t);
        }
        if (b != 'fails') expect(find.text('Wednesday'), findsOneWidget);
      });
    }

    testWidgets("A's late schedule is not B's", (t) async {
      server.schedules[userA] = fridays(userA);
      server.trainingDays = 1;
      final gate = server.readGate['client_schedules'] = Completer();
      await open(t);
      server.readGate.remove('client_schedules');
      await switchTo(t, userB, observe: false);
      gate.complete();
      await settle(t);
      expect(find.text('Friday'), findsNothing);
      expect(find.text('Wednesday'), findsOneWidget);
    });

    testWidgets("A's save in flight starts no checkout for B", (t) async {
      await open(t);
      await choose(t, 'Paid Plan');
      server.writeGate = Completer();
      await t.ensureVisible(find.text(pay));
      await t.tap(find.text(pay));
      await t.pump(const Duration(milliseconds: 50));
      await switchTo(t, userB, observe: false);
      server.writeGate!.complete();
      await settle(t);
      expect(payments.checkouts, 0, reason: 'B chose nothing');
      expect(t.takeException(), isNull);
    });

    for (final (outcome, a) in [
      ('is confirmed', Answer.ok),
      ('fails', Answer.fails),
    ]) {
      testWidgets('A → B → A during a held save that then $outcome: it is not the '
          "save on A's new screen", (t) async {
        await open(t);
        await choose(t, 'Paid Plan');
        final held = server.writeGate = Completer();
        await t.ensureVisible(find.text(pay));
        await t.tap(find.text(pay));
        await t.pump(const Duration(milliseconds: 50));
        server.writeGate = null;
        await switchTo(t, userB, observe: false);
        await switchTo(t, userA, observe: false);
        await choose(t, 'Paid Plan');
        expect(enabled(t, pay), isTrue, reason: 'premise: a second Save is possible');
        server.writeMode = (_) => a;
        held.complete();
        await settle(t);
        expect(payments.checkouts, 0,
            reason: 'THE defect: the stale save opened a checkout of its own');
        expect(find.textContaining("Couldn't"), findsNothing);
        expect(enabled(t, pay), isTrue);

        // Positive control: the save on this screen opens exactly one checkout.
        server.writeMode = null;
        await tapLabel(t, pay);
        expect(payments.checkouts, 1);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('A → B → A while a checkout is opening: its answer does not close '
        "A's new screen", (t) async {
      await open(t);
      await choose(t, 'Paid Plan');
      payments.hold = Completer();
      await tapLabel(t, pay);
      expect(payments.checkouts, 1, reason: 'premise');
      await switchTo(t, userB, observe: false);
      await switchTo(t, userA, observe: false);
      payments.hold!.complete();
      await settle(t);
      expect(find.text('HOME'), findsNothing,
          reason: 'THE defect: the stale checkout popped the screen');
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Choose a package'), findsOneWidget);
    });

    testWidgets('while a save is in flight the button says "Saving"', (t) async {
      await open(t);
      await choose(t, 'Free Plan');
      expect(find.bySemanticsLabel('Saving'), findsNothing);
      server.writeGate = Completer();
      await tapLabel(t, free);
      expect(find.bySemanticsLabel('Saving'), findsOneWidget);
      server.writeGate!.complete();
      await settle(t);
      expect(find.text('BOOKING'), findsOneWidget);
    });

    testWidgets('leaving mid-save starts no checkout and throws nothing', (t) async {
      await open(t);
      await choose(t, 'Paid Plan');
      server.writeGate = Completer();
      await t.ensureVisible(find.text(pay));
      await t.tap(find.text(pay));
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(find.byType(BackButton));
      await settle(t);
      expect(find.text('HOME'), findsOneWidget, reason: 'premise');
      server.writeGate!.complete();
      await settle(t);
      expect(t.takeException(), isNull);
      expect(server.schedules[userA], isNotNull, reason: 'the choice was saved');
      expect(payments.checkouts, 0);
    });
  });

  // ── (e) price sheet ───────────────────────────────────────────────────────
  group('price sheet', () {
    Future<void> open(WidgetTester t) async {
      await pumpApp(t, MaterialApp(home: Scaffold(body: Builder(
        builder: (c) => TextButton(
            onPressed: () => showCoachPricingSheet(c), child: const Text('open'))))));
      await t.tap(find.text('open'));
      await settle(t);
    }

    for (final a in [Answer.fails, Answer.zeroRows, Answer.network]) {
      testWidgets('a save that ${a.name} is recorded, and not "Pricing updated."',
          (t) async {
        await open(t);
        await t.enterText(find.byType(TextField), '150');
        server.writeMode = (_) => a;
        await t.tap(find.text('Save price'));
        await settle(t);
        expect(origins(), ['CoachPricingSheet._save'], reason: 'THE defect');
        expect(find.textContaining('Pricing updated'), findsNothing);
        expect(enabled(t, 'Save price'), isTrue);
      });
    }

    testWidgets('positive control: saved; negative: no price set is an empty '
        'field, not a failure', (t) async {
      await open(t);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      await t.enterText(find.byType(TextField), '150');
      await t.tap(find.text('Save price'));
      await settle(t);
      expect(find.textContaining('Pricing updated'), findsOneWidget);
      expect(reported, isEmpty);
    });

    testWidgets('closed while its price was being read: not a failure', (t) async {
      server.pricingMonthly = 175;
      final gate = server.readGate['user_profiles'] = Completer();
      await open(t);
      await t.tapAt(const Offset(10, 10));
      await settle(t);
      expect(find.text('Coaching Price'), findsNothing, reason: 'premise');
      gate.complete();
      await settle(t);
      expect(reported, isEmpty,
          reason: 'THE defect: writing to the disposed field was recorded');
    });
  });
}
