import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/profile/presentation/personal_info_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_image_picker.dart';
import '../support/pump_until.dart';
import '../support/row_checking_postgrest.dart';
import '../support/session_switch.dart';

// P0-FL-56a · Personal Info's photo button.
//
// At f191d48 the picker call sat outside the try: a denied permission was an
// uncaught async error and the button did nothing; two taps opened two
// pickers; an unreadable file was "Couldn't update your photo" under the
// write's origin; and the member was read AFTER the pick, so a photo picked by
// A was stored as B's when B signed in meanwhile.
// (The upload and the 0-row link are pinned by personal_info_save_is_verified.)
//
// HOW TO SEE IT FAIL: run against f191d48's personal_info_screen.dart.

const _uid = '00000000-0000-4000-8000-00000000a56a';
const _uidB = '00000000-0000-4000-8000-00000000b56a';

class _Server extends RowCheckingPostgrest {
  _Server() : super(_uid);
  final storage = <String>[];
  Completer<void>? uploadGate;

  @override
  void reset() {
    super.reset();
    uploadGate = null;
    storage.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.startsWith('/storage/v1/')) {
      storage.add('${request.method} ${request.url.path}');
      await uploadGate?.future;
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'Key': 'k'}))), 200,
          request: request, headers: {'content-type': 'application/json'});
    }
    return super.send(request);
  }
}

void main() {
  late _Server server;
  final picker = FakeImagePicker();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await initSignedInSupabase(server);
    picker.install();
  });
  tearDownAll(picker.dispose);

  setUp(() async {
    await signInAs(_uid);
    server.reset();
    picker.reset();
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Iterable<String> origins() => reported.map((f) => f.origin);
  Iterable<String> links() =>
      server.writes.where((w) => w.contains('/rest/v1/user_profiles'));

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(600, 3200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        // The profile read (not the identity) is answered here, for whoever
        // is really signed in.
        currentUserProfileProvider.overrideWith((ref) async {
          final uid = ref.watch(currentUserProvider)?.id;
          return {
            'id': uid,
            'first_name': uid == _uidB ? 'Bea' : 'Ana',
            'last_name': 'Lee',
            'role': 'client',
            'avatar_url': uid == _uidB
                ? 'https://cdn.example/b.jpg'
                : 'https://cdn.example/old.jpg',
          };
        }),
      ],
      child: const MaterialApp(home: PersonalInfoScreen()),
    ));
    await t.pumpAndSettle();
  }

  String? shownAvatar(WidgetTester t) {
    for (final w in t.widgetList<Container>(find.byType(Container))) {
      final d = w.decoration;
      if (d is BoxDecoration && d.image?.image is NetworkImage) {
        return (d.image!.image as NetworkImage).url;
      }
    }
    for (final w in t.widgetList<Image>(find.byType(Image))) {
      if (w.image is NetworkImage) return (w.image as NetworkImage).url;
    }
    return null;
  }

  Future<void> tapPhoto(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.camera_alt));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  void kept(WidgetTester t) {
    expect(shownAvatar(t), 'https://cdn.example/old.jpg',
        reason: 'the earlier photo is kept');
    expect(server.storage, isEmpty);
    expect(links(), isEmpty);
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('vanished'), findsNothing);
  }

  testWidgets('photo access denied: says where to allow it, recorded',
      (t) async {
    await open(t);
    expect(shownAvatar(t), 'https://cdn.example/old.jpg', reason: 'premise');
    picker.fails('photo_access_denied');
    await tapPhoto(t);
    const msg = "Couldn't open your photos — allow photo access in Settings, "
        'then try again.';
    expect(find.text(msg), findsOneWidget,
        reason: 'THE defect: uncaught, and the button did nothing');
    expect(liveRegionOver(msg), findsWidgets);
    expect(origins(), ['profile.avatar.pick.gallery']);
    kept(t);
  });

  testWidgets('any other picker failure: the generic next step; the button '
      'works again', (t) async {
    await open(t);
    picker.fails('boom');
    await tapPhoto(t);
    expect(find.text("Couldn't open your photos — $tryAgainHint"),
        findsOneWidget);
    expect(origins(), ['profile.avatar.pick.gallery']);
    kept(t);
    picker.cancels();
    await tapPhoto(t);
    expect(picker.calls, hasLength(2));
  });

  testWidgets('an unreadable pick: its own words and origin, photo kept',
      (t) async {
    await open(t);
    picker.picksUnreadable();
    await tapPhoto(t);
    await pumpUntil(t, () => find.byType(SnackBar).evaluate().isNotEmpty,
        what: 'the outcome');
    await t.pumpAndSettle();
    expect(
        find.text("Couldn't use that photo — $tryAgainHint"), findsOneWidget);
    expect(origins(), ['profile.avatar.read']);
    kept(t);
  });

  testWidgets('NEGATIVE CONTROL: cancelling is silent', (t) async {
    await open(t);
    picker.cancels();
    await tapPhoto(t);
    expect(picker.calls, ['pickImage:1']);
    expect(find.byType(SnackBar), findsNothing);
    expect(reported, isEmpty);
    kept(t);
  });

  testWidgets('a second tap while the picker is open opens no second one',
      (t) async {
    await open(t);
    final gate = Completer<Object?>();
    picker.answer = (_) => gate.future;
    await tapPhoto(t);
    await tapPhoto(t);
    expect(picker.calls, hasLength(1));
    gate.complete(null);
    await t.pumpAndSettle();
  });

  testWidgets('POSITIVE CONTROL: a readable pick is uploaded, linked and '
      'shown, with no notice', (t) async {
    await open(t);
    await tapPhoto(t);
    await pumpUntil(
        t, () => (shownAvatar(t) ?? '').contains('/avatars/$_uid/avatar.png'),
        what: 'the new avatar');
    expect(server.storage, hasLength(1));
    expect(links().single, contains('select=id'));
    expect(find.byType(SnackBar), findsNothing);
    expect(reported, isEmpty);
  });

  // B signs in and B's own form fills (A's form was dropped).
  Future<void> switchToB(WidgetTester t) async {
    await t.runAsync(() => signInAs(_uidB));
    await pumpUntil(t, () => find.text('Bea').evaluate().isNotEmpty,
        what: "B's own form");
  }

  Future<void> uploadSettled(WidgetTester t) async {
    await pumpUntil(t, () => shownAvatar(t) != null,
        what: 'the photo (no spinner)');
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets("A's link saves after B signed in: A's photo is not shown on "
      "B's form, and nothing is said to B", (t) async {
    await open(t);
    server.gate = Completer<void>();
    await tapPhoto(t);
    await pumpUntil(t, () => links().isNotEmpty, what: 'the link PATCH');
    await switchToB(t);
    server.gate!.complete();
    await uploadSettled(t);
    expect(links(), hasLength(1));
    expect(shownAvatar(t), 'https://cdn.example/b.jpg',
        reason: "A's late success landed on B's form");
    expect(find.byType(SnackBar), findsNothing);
    expect(reported, isEmpty);
  });

  testWidgets("B signs in during A's upload: the link is not written, "
      'recorded, nothing said to B', (t) async {
    await open(t);
    server.uploadGate = Completer<void>();
    await tapPhoto(t);
    await pumpUntil(t, () => server.storage.isNotEmpty, what: 'the upload');
    await switchToB(t);
    server.uploadGate!.complete();
    await pumpUntil(t, () => reported.isNotEmpty || links().isNotEmpty,
        what: 'the refusal');
    await uploadSettled(t);
    expect(links(), isEmpty,
        reason: "THE defect: A's row was written under B's session");
    expect(origins(), ['PersonalInfoScreen._pickAndUploadAvatar']);
    expect((reported.single.error as StateError).message,
        'the member changed during an upload');
    expect(shownAvatar(t), 'https://cdn.example/b.jpg');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets("A's pick, B signs in while the picker is open: nothing is "
      "uploaded to or linked on B's profile, and it is recorded", (t) async {
    await open(t);
    final gate = Completer<Object?>();
    picker.answer = (_) => gate.future;
    await tapPhoto(t);
    await t.runAsync(() => signInAs(_uidB));
    expect(Supabase.instance.client.auth.currentUser?.id, _uidB,
        reason: 'premise');
    gate.complete(picker.photoPath);
    await pumpUntil(t, () => reported.isNotEmpty, what: 'the refusal');
    expect(origins(), ['PersonalInfoScreen._pickAndUploadAvatar']);
    expect((reported.single.error as StateError).message,
        'the member changed during a pick');
    expect(server.storage, isEmpty);
    expect(links(), isEmpty);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'the notice belonged to the member who left');
  });
}
