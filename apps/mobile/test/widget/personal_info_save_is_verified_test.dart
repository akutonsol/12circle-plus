import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/profile/presentation/personal_info_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/row_checking_postgrest.dart';

// P0-FL-39 · Personal Info: "Profile updated successfully" only when the
// server confirmed the row changed; a photo shows as changed only when the
// profile now points at it.
//
// At 6f8918f both user_profiles updates (`_save` and the avatar link) were a
// bare `.update(..).eq('id', uid)`. A 0-row update (RLS filtered it) answers
// 204 exactly like a saved one: `_save` said "Profile updated successfully"
// and closed the screen, and the avatar switched to the new photo, though
// nothing was stored. Failures said "Failed to save. Please try again." /
// "Could not upload photo." and were never reported.
//
// HOW TO SEE IT FAIL: with 6f8918f's personal_info_screen.dart the 0-row
// tests find the success message (or the new photo) and nothing reported, and
// the PATCH carries no `select=id`.

const _uid = '00000000-0000-4000-8000-0000000f1391';
const _saveOffline =
    "Couldn't save your details — check your connection and try again.";
const _saveFailed = "Couldn't save your details — try again in a moment. "
    'If it keeps happening, contact support.';
const _photoOffline =
    "Couldn't update your photo — check your connection and try again.";
const _photoFailed = "Couldn't update your photo — try again in a moment. "
    'If it keeps happening, contact support.';

/// [RowCheckingPostgrest] that also answers Storage the way Storage does
/// (`{"Key": …}`), or refuses the upload when [storageFails].
class _Server extends RowCheckingPostgrest {
  _Server(super.uid);
  bool storageFails = false;

  @override
  void reset() {
    super.reset();
    storageFails = false;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.startsWith('/storage/v1/')) {
      writes.add('${request.method} ${request.url.path}');
      return storageFails
          ? _json({'statusCode': '403', 'error': 'denied', 'message': 'no'},
              403, request)
          : _json({'Key': 'avatars/$uid/avatar.jpg'}, 200, request);
    }
    return super.send(request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

final _profile = <String, Object?>{
  'id': _uid,
  'first_name': 'Ana',
  'last_name': 'Lee',
  'role': 'client',
  'gender': 'Female',
  'height_cm': 170,
  'weight_kg': 64.5,
  'avatar_url': 'https://cdn.example/old.jpg',
};

void main() {
  late _Server server;
  final reported = <AppFailure>[];
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server(_uid);
    await initSignedInSupabase(server);
    tmp = Directory.systemTemp.createTempSync('fl39_avatar_');
    final img = File('${tmp.path}/new.jpg')
      ..writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (call) async => img.path);
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  /// Pushed over a base route, as in the app, so the success pop has
  /// somewhere to go.
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProfileProvider.overrideWith((ref) async => Map.of(_profile)),
      ],
      child: MaterialApp(
          home: Navigator(
              onGenerateInitialRoutes: (_, __) => [
                    MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(body: Text('BASE'))),
                    MaterialPageRoute<void>(
                        builder: (_) => const PersonalInfoScreen()),
                  ])),
    ));
    await tester.pumpAndSettle();
  }

  List<String> profileWrites() =>
      server.writes.where((w) => w.contains('/rest/v1/user_profiles')).toList();

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Save').first);
    await tester.pumpAndSettle();
  }

  /// The picked file is read with real I/O before the upload is sent:
  /// alternate fake-time pumps with real-time waits until the chain settles.
  Future<void> changePhoto(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.camera_alt));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    await tester.pumpAndSettle();
  }

  /// The URL the avatar is drawn from (a NetworkImage), or null.
  String? shownAvatar(WidgetTester tester) {
    for (final w in tester.widgetList<Container>(find.byType(Container))) {
      final d = w.decoration;
      if (d is BoxDecoration && d.image?.image is NetworkImage) {
        return (d.image!.image as NetworkImage).url;
      }
    }
    for (final w in tester.widgetList<CircleAvatar>(find.byType(CircleAvatar))) {
      final i = w.backgroundImage;
      if (i is NetworkImage) return i.url;
    }
    for (final w in tester.widgetList<Image>(find.byType(Image))) {
      final i = w.image;
      if (i is NetworkImage) return i.url;
    }
    return null;
  }

  group('Save', () {
    testWidgets('a 0-row update is not "updated successfully": said, '
        'reported, the screen stays open', (tester) async {
      await open(tester);
      server.mode = WriteMode.zeroRows;
      await tapSave(tester);

      expect(profileWrites().single, contains('select=id'),
          reason: 'the save must ask for its row back to see a 0-row update');
      expect(find.text('Profile updated successfully'), findsNothing,
          reason: 'THE defect: nothing was stored and it said it was');
      expect(find.text(_saveFailed), findsOneWidget);
      expect(find.byType(PersonalInfoScreen), findsOneWidget,
          reason: 'the screen did not "save" and close');
      expect(reported.single.origin, 'PersonalInfoScreen._save');
    });

    testWidgets('a server error: try-again copy, no connection hint, no '
        'exception text, reported', (tester) async {
      await open(tester);
      server.mode = WriteMode.serverError;
      await tapSave(tester);
      expect(find.text(_saveFailed), findsOneWidget);
      expect(find.textContaining('Check your connection'), findsNothing);
      expect(find.textContaining('refused'), findsNothing);
      expect(find.byType(PersonalInfoScreen), findsOneWidget);
      expect(reported, hasLength(1));
    });

    testWidgets('a connection failure gives the connection hint',
        (tester) async {
      await open(tester);
      server.mode = WriteMode.network;
      await tapSave(tester);
      expect(find.text(_saveOffline), findsOneWidget);
      expect(find.byType(PersonalInfoScreen), findsOneWidget);
      expect(reported, hasLength(1));
    });

    testWidgets('control: a confirmed save still says so, closes, and writes '
        'the same keys', (tester) async {
      await open(tester);
      await tapSave(tester);
      final w = profileWrites().single;
      for (final key in ['first_name', 'last_name', 'gender', 'phone',
          'height_cm', 'weight_kg', 'weight_goal_kg',
          'training_days_per_week']) {
        expect(w, contains('"$key"'));
      }
      expect(find.text('Profile updated successfully'), findsOneWidget);
      expect(find.text('BASE'), findsOneWidget, reason: 'closed');
      expect(reported, isEmpty);
    });
  });

  group('Photo', () {
    testWidgets('a 0-row avatar link keeps the old photo, says so, reports',
        (tester) async {
      await open(tester);
      expect(shownAvatar(tester), 'https://cdn.example/old.jpg',
          reason: 'premise: the stored photo is shown');
      server.mode = WriteMode.zeroRows;
      server.modeAppliesTo = (w) => w.contains('/rest/v1/user_profiles');
      await changePhoto(tester);

      expect(profileWrites().single, contains('select=id'));
      expect(profileWrites().single, contains('"avatar_url"'));
      expect(shownAvatar(tester), 'https://cdn.example/old.jpg',
          reason: 'THE defect: the new photo was shown though the profile '
              'does not point at it');
      expect(find.text(_photoFailed), findsOneWidget);
      expect(reported.single.origin, 'PersonalInfoScreen._pickAndUploadAvatar');
    });

    testWidgets('a refused upload: house voice, reported, old photo kept',
        (tester) async {
      await open(tester);
      server.storageFails = true;
      await changePhoto(tester);
      expect(profileWrites(), isEmpty, reason: 'nothing to link');
      expect(shownAvatar(tester), 'https://cdn.example/old.jpg');
      expect(find.text(_photoFailed), findsOneWidget);
      expect(find.textContaining('Could not upload'), findsNothing);
      expect(reported, hasLength(1));
    });

    testWidgets('a connection failure on the link gives the connection hint',
        (tester) async {
      await open(tester);
      server.mode = WriteMode.network;
      server.modeAppliesTo = (w) => w.contains('/rest/v1/user_profiles');
      await changePhoto(tester);
      expect(find.text(_photoOffline), findsOneWidget);
      expect(shownAvatar(tester), 'https://cdn.example/old.jpg');
      expect(reported, hasLength(1));
    });

    testWidgets('control: a confirmed link shows the new photo, says nothing '
        'wrong', (tester) async {
      await open(tester);
      await changePhoto(tester);
      expect(profileWrites().single, contains('"avatar_url"'));
      expect(shownAvatar(tester), contains('/avatars/$_uid/avatar.jpg'));
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(reported, isEmpty);
    });
  });
}
