import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/presentation/coach_business_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-FL-60b (d) · Business Profile › Team: the invite is saved, then emailed.
// A thrown email failure was swallowed (`catch (_)`) and recorded nowhere. The
// outcome said is unchanged: saved, not sent.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- lib/features/coach/
// presentation/coach_business_screen.dart`; the controls pass.

const _notSent =
    "Invite saved, but the email couldn't be sent — ask them to check back, "
    'or send the invite again later.';

enum _Mail { sent, notSent, refused, unreachable }

class _Server extends TwoMemberPostgrest {
  _Mail mail = _Mail.sent;
  bool insertFails = false;
  int emails = 0;
  final invites = <Map<String, Object?>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    http.StreamedResponse json(Object? b, [int status = 200]) =>
        http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(b))), status,
            request: request, headers: {'content-type': 'application/json'});
    if (path.endsWith('/send-invite-email')) {
      emails++;
      return switch (mail) {
        _Mail.sent => json({'sent': true}),
        _Mail.notSent => json({'sent': false}),
        _Mail.refused => json({'error': 'Email send failed SECRET'}, 502),
        _Mail.unreachable =>
          throw http.ClientException('Connection refused', request.url),
      };
    }
    if (path.endsWith('/coach_team_invites') && request.method == 'POST') {
      if (insertFails) return json({'message': 'SECRET', 'code': 'XX000'}, 500);
      invites.add(jsonDecode((request as http.Request).body)
          as Map<String, Object?>);
      return http.StreamedResponse(const Stream.empty(), 201, request: request);
    }
    if (path.endsWith('/user_profiles') && request.method == 'GET') {
      return json({'id': memberA, 'bio': 'Alpha bio', 'specialties': []});
    }
    return super.send(request);
  }
}

void main() {
  late _Server server;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server
      ..reset()
      ..mail = _Mail.sent
      ..insertFails = false
      ..emails = 0
      ..invites.clear();
    reported.clear();
    setFailureSink(reported.add);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Future<void> invite(WidgetTester t) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 2000);
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: CoachBusinessScreen()));
    await pumpUntil(t, () => find.text('Alpha bio').evaluate().isNotEmpty,
        what: 'the profile');
    await t.tap(find.text('Team'));
    await t.pumpAndSettle();
    await t.tap(find.text('Invite Assistant Coach'));
    await t.pumpAndSettle();
    await t.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'assistant@example.com');
    await t.tap(find.text('Invite'));
    await pumpUntil(t, () => find.byType(SnackBar).evaluate().isNotEmpty,
        what: 'the outcome');
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 7));
  }

  for (final mail in [_Mail.refused, _Mail.unreachable]) {
    testWidgets('email ${mail.name}: saved, said as not sent, and recorded',
        (t) async {
      server.mail = mail;
      await invite(t);
      expect(find.text(_notSent), findsOneWidget);
      expect(find.textContaining('Invite email sent'), findsNothing);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(server.invites.single['coach_id'], memberA);
      expect(server.emails, 1);
      expect(reported.map((f) => f.origin),
          ['CoachBusinessScreen._showInviteTeam.email'],
          reason: 'THE defect: swallowed');
      await close(t);
    });
  }

  testWidgets('NEGATIVE CONTROL: answered "not sent" — said, nothing thrown',
      (t) async {
    server.mail = _Mail.notSent;
    await invite(t);
    expect(find.text(_notSent), findsOneWidget);
    expect(reported, isEmpty);
    await close(t);
  });

  testWidgets('CONTROL: the invite itself not saved: no email goes out',
      (t) async {
    server.insertFails = true;
    await invite(t);
    expect(find.textContaining("Couldn't save the invite"), findsOneWidget);
    expect(server.emails, 0);
    expect(reported.map((f) => f.origin),
        ['CoachBusinessScreen._showInviteTeam']);
    await close(t);
  });

  testWidgets('POSITIVE CONTROL: saved and sent', (t) async {
    await invite(t);
    expect(find.text('Invite email sent to assistant@example.com'),
        findsOneWidget);
    expect(reported, isEmpty);
    await close(t);
  });
}
