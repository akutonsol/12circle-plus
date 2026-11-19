import 'dart:async';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/profile/presentation/notification_preferences_screen.dart';
import 'package:circle_fitness/features/profile/presentation/personal_info_screen.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/profile_read_postgrest.dart';
import '../support/row_checking_postgrest.dart';

// P0-FL-16 review round · the profile-read lock must hold for EVERY way in.
//
// The edit screens lock their controls until the member's profile has been
// read (it is loading, or the read failed). The lock was an AbsorbPointer +
// Opacity: it stopped a finger, not TalkBack/VoiceOver, which could still
// activate the photo picker, gender chips, pickers and the notification
// toggles — and a toggle WRITES a default over the stored setting (UX-F2).
// These tests drive the screens through the SEMANTICS tree, the way a screen
// reader does, while the read is held in flight and after it fails.
//
// Also covered: the Personal Info lock itself (a mutant `locked = false`
// survived the first round), the Save button's whole-button disabled look
// (UX-F1), Settings' first load drawing "Member" and client rows for a coach
// (UX-F3), the Notifications one-frame lock flash (UX-F4), the unit toggle's
// announced lock (UX-F5), and a refresh that fails after a good read
// (Settings must not lock Default Units without saying why).
//
// HOW TO SEE THEM FAIL: check out the four lib files of the commit before the
// review fix (28ad13e) and run this file.

const _uid = '00000000-0000-4000-8000-0000000f1617';
const _offline =
    "Couldn't load your profile — check your connection and try again.";

final _client = <String, Object?>{
  'id': _uid,
  'first_name': 'Ana',
  'last_name': 'Lee',
  'email': 'ana@example.com',
  'role': 'client',
  'phone': '555-0100',
  'gender': 'Female',
  'height_cm': 170,
  'weight_kg': 64.5,
  'unit_preference': 'imperial',
  'notif_workout_reminders': false,
  'notif_checkin_reminders': true,
};

final _coach = <String, Object?>{
  'id': _uid,
  'first_name': 'Cara',
  'last_name': 'Cole',
  'email': 'cara@example.com',
  'role': 'coach',
  'unit_preference': 'metric',
};

void main() {
  late ProfileReadPostgrest server;
  final reported = <AppFailure>[];
  var pickerCalls = 0;
  // When set, the gallery picker answers with this image instead of
  // "cancelled" — so a picker that opens leads on to a real upload attempt.
  String? pickedImagePath;
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = ProfileReadPostgrest(_uid);
    await initSignedInSupabase(server);
    tmp = Directory.systemTemp.createTempSync('fl16_avatar_');
    // The gallery picker: counted, and answered "cancelled" (or with
    // [pickedImagePath]).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'), (call) async {
      pickerCalls++;
      return pickedImagePath;
    });
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUp(() {
    server.reset();
    reported.clear();
    pickerCalls = 0;
    pickedImagePath = null;
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Widget app(Widget screen,
      {ProviderContainer? container, bool stacked = false}) {
    // [stacked]: the screen is pushed over a base route, as in the app, so a
    // save that pops it (the success path) has somewhere to go back to.
    final child = stacked
        ? MaterialApp(
            home: Navigator(
                onGenerateInitialRoutes: (_, __) => [
                      MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(body: Text('BASE'))),
                      MaterialPageRoute<void>(builder: (_) => screen),
                    ]))
        : MaterialApp(home: screen);
    if (container != null) {
      return UncontrolledProviderScope(container: container, child: child);
    }
    return ProviderScope(overrides: _overrides(), child: child);
  }

  /// Opens [screen] with the profile read held in flight (no settle: the
  /// spinner never stops).
  Future<void> openPending(WidgetTester tester, Widget screen,
      {bool stacked = false}) async {
    await tester.binding.setSurfaceSize(const Size(600, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    server.readGate = Completer<void>();
    await tester.pumpWidget(app(screen, stacked: stacked));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(server.profileReads, greaterThanOrEqualTo(1),
        reason: 'premise: the read is in flight');
  }

  Future<void> release(WidgetTester tester, Map<String, Object?>? row) async {
    server.profile = row == null ? null : Map.of(row);
    server.readGate!.complete();
    server.readGate = null;
    await tester.pumpAndSettle();
  }

  /// [noticePremise]: false checks the failure on the provider instead of
  /// the on-screen notice — for tests whose point is "no write", so a mutant
  /// that also hides the notice is caught by the write assertion itself.
  Future<void> openFailed(WidgetTester tester, Widget screen,
      {bool stacked = false, bool noticePremise = true}) async {
    await tester.binding.setSurfaceSize(const Size(600, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    server.profileRead = ProfileRead.network;
    await tester.pumpWidget(app(screen, stacked: stacked));
    await tester.pumpAndSettle();
    // postgrest retries a GET that hit a network failure, on timers.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    if (noticePremise) {
      expect(find.text(_offline), findsOneWidget, reason: 'premise: it failed');
    } else {
      final container = ProviderScope.containerOf(
          tester.element(find.byWidget(screen)));
      expect(container.read(currentUserProfileProvider).hasError, isTrue,
          reason: 'premise: the profile read failed');
    }
  }

  Future<void> openOk(WidgetTester tester, Widget screen,
      Map<String, Object?>? row) async {
    await tester.binding.setSurfaceSize(const Size(600, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    server.profile = row == null ? null : Map.of(row);
    await tester.pumpWidget(app(screen));
    await tester.pumpAndSettle();
  }

  /// Every node a screen reader could activate, as `label` strings.
  List<String> activatable() {
    final labels = <String>[];
    for (final n in find.semantics
        .byPredicate((n) => n.getSemanticsData().hasAction(SemanticsAction.tap))
        .evaluate()) {
      labels.add(n.getSemanticsData().label);
    }
    return labels;
  }

  /// Activates, through the semantics tree, every node that offers a tap —
  /// except leaving the screen and the failure notice's own Try again.
  Future<int> activateEverything(WidgetTester tester) async {
    bool skip(SemanticsData d) =>
        d.tooltip.contains('Back') ||
        d.label.contains('Back') ||
        d.label.contains('Try again');
    final ids = find.semantics
        .byPredicate((n) =>
            n.getSemanticsData().hasAction(SemanticsAction.tap) &&
            !skip(n.getSemanticsData()))
        .evaluate()
        .map((n) => n.id)
        .toList();
    var activated = 0;
    for (final id in ids) {
      final node = find.semantics.byPredicate((n) => n.id == id);
      if (node.evaluate().isEmpty) continue; // gone after an earlier tap
      tester.semantics.tap(node);
      activated++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    // Close anything an activation opened (sheets, the date picker).
    for (var i = 0; i < 3; i++) {
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      if (!nav.canPop()) break;
      nav.pop();
      await tester.pump(const Duration(milliseconds: 400));
    }
    return activated;
  }

  List<String> writes() => List.of(server.writes);

  // ── Personal Info ────────────────────────────────────────────────────────
  group('Personal Info lock', () {
    testWidgets(
        'while the read is in flight: a screen reader reaches no form control, '
        'Save is disabled, nothing is written', (tester) async {
      final semantics = tester.ensureSemantics();
      await openPending(tester, const PersonalInfoScreen());
      expect(find.text('Loading your details…'), findsOneWidget);

      final reachable = activatable();
      for (final label in ['Male', 'Female', 'Date of Birth', 'Tap to change photo']) {
        expect(reachable.where((l) => l.contains(label)), isEmpty,
            reason: 'THE defect (UX-F2 / survived mutant): "$label" was '
                'activatable while the form held none of the member\'s data. '
                'Reachable: $reachable');
      }
      expect(
          tester
              .getSemantics(find.text('Save Changes'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse,
          reason: 'Save Changes must not be activatable while locked');

      await activateEverything(tester);
      await tester.tap(find.text('Save Changes'), warnIfMissed: false);
      await tester.pump();
      expect(writes(), isEmpty);
      expect(pickerCalls, 0, reason: 'the photo picker opened while locked');

      // Control: once the read lands the form is filled and reachable.
      await release(tester, _client);
      expect(find.text('Loading your details…'), findsNothing);
      expect(activatable().where((l) => l.contains('Male')), isNotEmpty,
          reason: 'control: unlocked controls are reachable again');
      semantics.dispose();
    });

    testWidgets('after a failed read: activating every control semantically '
        'sends no write and opens no picker', (tester) async {
      final semantics = tester.ensureSemantics();
      await openFailed(tester, const PersonalInfoScreen());
      final activated = await activateEverything(tester);
      expect(activated, greaterThanOrEqualTo(0));
      expect(writes(), isEmpty,
          reason: 'THE defect (UX-F2): a screen reader could write while '
              'locked');
      expect(pickerCalls, 0);
      expect(find.text('Profile updated successfully'), findsNothing);
      semantics.dispose();
    });

    testWidgets('Save Changes is dimmed and flat as a whole while locked',
        (tester) async {
      await openPending(tester, const PersonalInfoScreen());
      final button = find.ancestor(
          of: find.text('Save Changes'),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient != null));
      expect(button, findsOneWidget);
      final dim = find.ancestor(
          of: button,
          matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1));
      expect(dim, findsOneWidget,
          reason: 'THE defect (UX-F1): only the label was dimmed; the '
              'gradient button still looked live');
      final deco = tester.widget<Container>(button).decoration as BoxDecoration;
      expect(deco.boxShadow, isNull, reason: 'no glow while locked');

      await release(tester, _client);
      expect(
          find.ancestor(
              of: button,
              matching:
                  find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1)),
          findsNothing,
          reason: 'control: full strength once loaded');
    });
  });

  // ── Notifications ────────────────────────────────────────────────────────
  Finder toggles() => find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_PurpleToggle');

  group('Notifications lock', () {
    testWidgets('after a failed read: activating every toggle semantically '
        'writes nothing', (tester) async {
      final semantics = tester.ensureSemantics();
      await openFailed(tester, const NotificationPreferencesScreen());
      await activateEverything(tester);
      expect(writes(), isEmpty,
          reason: 'THE defect (UX-F2): TalkBack could flip a default toggle '
              'and store it over the member\'s setting');
      semantics.dispose();
    });

    testWidgets('while the read is in flight: taps and semantic activation '
        'write nothing; the stored values arrive and then save',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await openPending(tester, const NotificationPreferencesScreen());
      expect(find.text('Loading your notification settings…'), findsOneWidget);
      await tester.tap(toggles().first, warnIfMissed: false);
      await activateEverything(tester);
      expect(writes(), isEmpty);

      await release(tester, _client);
      expect((tester.widget(toggles().first) as dynamic).value as bool, isFalse,
          reason: 'stored notif_workout_reminders=false');
      await tester.tap(toggles().first);
      await tester.pumpAndSettle();
      expect(writes().single, contains('"notif_workout_reminders":true'));
      semantics.dispose();
    });

    testWidgets('a profile already read shows no lock on the first frame',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      server.profile = Map.of(_client);
      final container = ProviderContainer(overrides: _overrides());
      addTearDown(container.dispose);
      final sub = container.listen(currentUserProfileProvider, (_, __) {});
      addTearDown(sub.close);
      await tester.runAsync(
          () => container.read(currentUserProfileProvider.future));
      expect(container.read(currentUserProfileProvider), isA<AsyncData>(),
          reason: 'premise: the profile is already read');

      await tester.pumpWidget(
          app(const NotificationPreferencesScreen(), container: container));
      // ONE frame — no further pump.
      expect(find.text('Loading your notification settings…'), findsNothing,
          reason: 'THE defect (UX-F4): a locked "Loading…" frame flashed '
              'before the stored values were applied');
      expect((tester.widget(toggles().first) as dynamic).value as bool, isFalse,
          reason: 'the stored value is on the first frame, not the default');
    });
  });

  // ── No write over the stored profile, whichever lock layer is gone ───────
  //
  // Lead mutation round (P0-FL-16): removing ALL of Personal Info's lock
  // layers at once — `_isLocked() => false`, `locked = false` in build and the
  // `if (!_loaded)` refusal in _save — survived, because every earlier test
  // left the form EMPTY, and an empty form stops at "First name is required"
  // before any write. These tests put a name (and the other fields) into the
  // form while the profile is unread, drive every Save, and require that no
  // PATCH reaches user_profiles. Same for the photo and the notification
  // toggles. Each test must FAIL with the multi-layer mutant applied.

  List<String> profileWrites() =>
      server.writes.where((w) => w.contains('/user_profiles')).toList();
  List<String> storageWrites() =>
      server.writes.where((w) => w.contains('/storage/')).toList();

  /// Taps, through the semantics tree, the node that carries [widget]'s tap
  /// action — only if one is offered (a locked control offers none).
  Future<void> semanticTapIfOffered(WidgetTester tester, Finder widget) async {
    if (widget.evaluate().isEmpty) return;
    final node = tester.getSemantics(widget.first);
    if (!node.getSemanticsData().hasAction(SemanticsAction.tap)) return;
    tester.semantics.tap(find.semantics.byPredicate((n) => n.id == node.id));
    await tester.pump();
  }

  /// Puts a full set of edits into the Personal Info form. The fields are
  /// disabled while locked (a separate layer, not part of the mutant), so the
  /// keyboard cannot type into them; the text is set on their controllers —
  /// what an autofill/IME restore, or a form still holding text from before
  /// a lock, would leave there.
  void fillPersonalInfo(WidgetTester tester) {
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.length, greaterThanOrEqualTo(6),
        reason: 'premise: name, phone and the three body fields are drawn');
    const values = ['Zed', 'Typed', '555-9999', '199', '99.9', '88.8'];
    for (var i = 0; i < values.length; i++) {
      fields[i].controller!.text = values[i];
    }
    expect(fields.first.controller!.text, 'Zed',
        reason: 'premise: the form is NOT empty, so "First name is required" '
            'cannot be what stops the save');
  }

  /// Every way to fire Personal Info's Save: the header "Save", the
  /// "Save Changes" button, by finger and by screen reader.
  Future<void> driveEverySave(WidgetTester tester) async {
    await semanticTapIfOffered(tester, find.text('Save Changes'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save Changes'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    final header = find.text('Save');
    if (header.evaluate().isNotEmpty) {
      await tester.tap(header, warnIfMissed: false);
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Activates the photo control by finger and by screen reader; the picker
  /// answers with a real image, so an opened picker goes on to upload.
  Future<void> activateAvatar(WidgetTester tester) async {
    final img = File('${tmp.path}/avatar.jpg')
      ..writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    pickedImagePath = img.path;
    final camera = find.byIcon(Icons.camera_alt);
    expect(camera, findsOneWidget, reason: 'premise: the photo control');
    await semanticTapIfOffered(tester, camera);
    await tester.tap(camera, warnIfMissed: false);
    // The picked file is read with real I/O before the upload is sent:
    // alternate fake-time pumps with real-time waits until the chain settles.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('No write over the stored profile', () {
    testWidgets('Personal Info, read FAILED: a filled form + every Save sends '
        'no user_profiles PATCH', (tester) async {
      final semantics = tester.ensureSemantics();
      await openFailed(tester, const PersonalInfoScreen(), stacked: true);
      fillPersonalInfo(tester);
      await driveEverySave(tester);
      expect(profileWrites(), isEmpty,
          reason: 'THE defect (multi-layer lock mutant): a form that was '
              'never filled from the stored profile was written over it. '
              'Writes: ${profileWrites()}');
      expect(find.text('Profile updated successfully'), findsNothing);
      expect(find.byType(PersonalInfoScreen), findsOneWidget,
          reason: 'the screen did not "save" and close');
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets('Personal Info, read IN FLIGHT: a filled form + every Save '
        'sends no user_profiles PATCH; once read, Save writes the stored '
        'values', (tester) async {
      final semantics = tester.ensureSemantics();
      await openPending(tester, const PersonalInfoScreen(), stacked: true);
      fillPersonalInfo(tester);
      await driveEverySave(tester);
      expect(profileWrites(), isEmpty,
          reason: 'THE defect (multi-layer lock mutant): Save wrote while '
              'the stored profile was still loading. '
              'Writes: ${profileWrites()}');
      expect(find.text('Profile updated successfully'), findsNothing);

      // Control: the read lands, the form shows the STORED values, and Save
      // now writes them — the test can see a write when there is one.
      await release(tester, _client);
      expect(tester.widget<TextField>(find.byType(TextField).first)
          .controller!.text, 'Ana');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(profileWrites(), hasLength(1));
      expect(profileWrites().single, contains('"first_name":"Ana"'));
      expect(profileWrites().single, isNot(contains('Zed')));
      semantics.dispose();
    });

    testWidgets('Personal Info photo, read FAILED: activating it opens no '
        'picker and sends no upload or PATCH', (tester) async {
      final semantics = tester.ensureSemantics();
      await openFailed(tester, const PersonalInfoScreen(), stacked: true);
      await activateAvatar(tester);
      expect(storageWrites(), isEmpty,
          reason: 'THE defect: a photo was uploaded while the profile was '
              'unread. Writes: ${server.writes}');
      expect(profileWrites(), isEmpty,
          reason: 'avatar_url was written over the unread profile');
      expect(pickerCalls, 0, reason: 'the photo picker opened while locked');
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets('Personal Info photo, read IN FLIGHT: activating it opens no '
        'picker and sends no upload or PATCH', (tester) async {
      final semantics = tester.ensureSemantics();
      await openPending(tester, const PersonalInfoScreen(), stacked: true);
      await activateAvatar(tester);
      expect(storageWrites(), isEmpty,
          reason: 'THE defect: a photo was uploaded while the profile was '
              'loading. Writes: ${server.writes}');
      expect(profileWrites(), isEmpty);
      expect(pickerCalls, 0, reason: 'the photo picker opened while locked');
      await release(tester, _client);
      semantics.dispose();
    });

    Future<void> toggleEverything(WidgetTester tester) async {
      final n = toggles().evaluate().length;
      expect(n, 6, reason: 'premise: the six notification toggles are drawn');
      for (var i = 0; i < n; i++) {
        await semanticTapIfOffered(tester, toggles().at(i));
        await tester.tap(toggles().at(i), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('Notifications, read FAILED: toggling every switch sends no '
        'PATCH', (tester) async {
      final semantics = tester.ensureSemantics();
      await openFailed(tester, const NotificationPreferencesScreen(),
          noticePremise: false);
      await toggleEverything(tester);
      expect(profileWrites(), isEmpty,
          reason: 'THE defect (lock mutant): a default toggle was flipped and '
              'stored over the unread setting. Writes: ${profileWrites()}');
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets('Notifications, read IN FLIGHT: toggling every switch sends '
        'no PATCH', (tester) async {
      final semantics = tester.ensureSemantics();
      await openPending(tester, const NotificationPreferencesScreen());
      await toggleEverything(tester);
      expect(profileWrites(), isEmpty,
          reason: 'THE defect (lock mutant): a toggle wrote while the stored '
              'settings were loading. Writes: ${profileWrites()}');
      await release(tester, _client);
      semantics.dispose();
    });
  });

  // ── Settings ─────────────────────────────────────────────────────────────
  /// The button/enabled properties the screen declares for a unit button
  /// (the nearest Semantics widget above its label that declares `button`).
  ({bool? button, bool? enabled}) unitSemantics(WidgetTester tester, String u) {
    final s = tester
        .widgetList<Semantics>(find.ancestor(
            of: find.text(u).first, matching: find.byType(Semantics)))
        .where((s) => s.properties.button != null)
        .firstOrNull;
    return (button: s?.properties.button, enabled: s?.properties.enabled);
  }

  group('Settings', () {
    testWidgets('a coach\'s first load draws no "Member" and no client rows',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await openPending(tester, const SettingsScreen());
      expect(find.text('Member'), findsNothing,
          reason: 'THE defect (UX-F3): "Member" was drawn while loading');
      expect(find.text('Subscription'), findsNothing,
          reason: 'a client-only row drawn before the role is known');
      expect(find.text('Coaching Mode'), findsNothing);
      expect(find.text('Loading your account…'), findsOneWidget);
      // UX-F5: the locked unit toggle is announced as disabled.
      expect(unitSemantics(tester, 'LB'), (button: true, enabled: false),
          reason: 'UX-F5: the lock was colour-only');
      expect(
          tester
              .getSemantics(find.text('LB').first)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse);
      await tester.tap(find.text('LB').first);
      await tester.tap(find.text('KG').first);
      await tester.pump();
      expect(writes(), isEmpty);

      await release(tester, _coach);
      expect(find.text('Cara Cole'), findsOneWidget);
      expect(find.text('Subscription'), findsNothing, reason: 'a coach');
      expect(find.text('Coaching Mode'), findsNothing, reason: 'a coach');
      expect(find.text('Loading your account…'), findsNothing);
      expect(unitSemantics(tester, 'KG'), (button: true, enabled: true),
          reason: 'control: enabled once the stored unit is known');
      semantics.dispose();
    });

    testWidgets('a refresh that fails after a "no profile row" read does not '
        'lock Default Units silently', (tester) async {
      await openOk(tester, const SettingsScreen(), null);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(SettingsScreen)));
      server.profileRead = ProfileRead.network;
      container.invalidate(currentUserProfileProvider);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(container.read(currentUserProfileProvider).hasError, isTrue,
          reason: 'premise: the refresh failed');

      // The server is reachable again for the write and the re-read it
      // triggers; what matters is whether the toggle still responds.
      server.profileRead = ProfileRead.ok;
      await tester.tap(find.text('LB').first);
      await tester.pumpAndSettle();
      final toggleLive = writes().any((w) => w.contains('unit_preference'));
      final noticeShown = find.text(_offline).evaluate().isNotEmpty;
      expect(toggleLive || noticeShown, isTrue,
          reason: 'THE defect: the toggle went dead with no notice saying why');
    });

    testWidgets('a refresh that fails after a good read keeps the stored unit '
        'and a live toggle', (tester) async {
      await openOk(tester, const SettingsScreen(), _client);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(SettingsScreen)));
      server.profileRead = ProfileRead.network;
      container.invalidate(currentUserProfileProvider);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(container.read(currentUserProfileProvider).hasError, isTrue,
          reason: 'premise: the refresh failed');
      expect(find.text('Ana Lee'), findsOneWidget,
          reason: 'the earlier real profile, not "Member"');
      server.profileRead = ProfileRead.ok;
      server.profile = Map.of(_client);
      await tester.tap(find.text('KG').first);
      await tester.pumpAndSettle();
      expect(writes().where((w) => w.contains('"unit_preference":"metric"')),
          hasLength(1));
    });
  });
}

List<Override> _overrides() => [
      currentUserProvider
          .overrideWithValue(Supabase.instance.client.auth.currentUser),
      clientPlanProvider.overrideWith((ref) async => ClientPlan.selfGuided),
    ];
