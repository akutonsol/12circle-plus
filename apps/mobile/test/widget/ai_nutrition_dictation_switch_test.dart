import 'dart:convert';
import 'dart:io';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/ai_nutrition/data/ai_nutrition_service.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/ai_nutrition_provider.dart';
import 'package:circle_fitness/features/ai_nutrition/presentation/ai_nutrition_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/two_member_postgrest.dart';

// P0-FL-60b · a question being dictated to the nutrition AI when the account
// changes. At a82f993 the microphone kept listening and A's words landed in
// B's composer (to be sent by B).
//
// Its own file: the speech plugin is a singleton that initializes once, and
// here it answers that it can listen.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 -- lib/features/ai_nutrition`;
// the control passes.

const _speech = MethodChannel('plugin.csdcorp.com/speech_to_text');

class _Coach implements AiNutritionService {
  final sent = <String>[];

  @override
  Future<String> sendMessage({
    required String message,
    required List<Map<String, dynamic>> history,
    File? imageFile,
  }) async {
    sent.add(message);
    return 'reply';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  final asked = <String>[];
  final reported = <AppFailure>[];
  late _Coach coach;

  setUpAll(() async {
    await initTwoMemberSupabase(TwoMemberPostgrest());
    messenger.setMockMethodCallHandler(_speech, (call) async {
      asked.add(call.method);
      return true;
    });
  });

  setUp(() async {
    asked.clear();
    reported.clear();
    coach = _Coach();
    setFailureSink(reported.add);
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  /// The plugin heard [words].
  Future<void> hear(WidgetTester t, String words, {bool last = false}) =>
      messenger.handlePlatformMessage(
          _speech.name,
          _speech.codec.encodeMethodCall(MethodCall(
              'textRecognition',
              jsonEncode({
                'alternates': [
                  {'recognizedWords': words, 'confidence': 0.9}
                ],
                'finalResult': last,
                'resultType': last ? 2 : 0,
              }))),
          // Throws here if the plugin could not read it.
          (reply) => _speech.codec.decodeEnvelope(reply!));

  String draft(WidgetTester t) =>
      t.widget<TextField>(find.byType(TextField)).controller!.text;

  bool listening() => find.byIcon(Icons.mic).evaluate().isNotEmpty;

  Future<void> dictating(WidgetTester t) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2000);
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
        overrides: [aiNutritionServiceProvider.overrideWithValue(coach)],
        child: const MaterialApp(home: AiNutritionScreen())));
    await settle(t);
    await t.tap(find.byIcon(Icons.mic_none_outlined));
    await settle(t);
    expect(asked, contains('listen'), reason: 'premise');
    expect(listening(), isTrue, reason: 'premise');
    await hear(t, 'I am');
    await settle(t);
    expect(draft(t), 'I am', reason: 'premise: dictation reaches the composer');
    asked.clear();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 40));
  }

  for (final (how, to, back) in [
    ('A → B', memberB, null),
    ('sign-out', null, null),
    ('sign-out, then A back', null, memberA),
  ]) {
    testWidgets('$how: the microphone is cancelled, and words heard late land '
        'in nobody\'s composer', (t) async {
      await dictating(t);
      for (final uid in [to, if (back != null) back]) {
        await t.runAsync(() => uid == null ? signOut() : signInAs(uid));
        await settle(t);
      }
      expect(asked, contains('cancel'), reason: 'THE defect: still listening');
      expect(listening(), isFalse);
      expect(draft(t), isEmpty);
      await hear(t, 'I am diabetic', last: true);
      await settle(t);
      expect(draft(t), isEmpty, reason: "THE defect: the last member's words");
      await t.tap(find.byIcon(Icons.send));
      await settle(t);
      expect(coach.sent, isEmpty);
      await close(t);
    });
  }

  testWidgets('B signs in, no frame, and more words are heard: they are dropped '
      'and the microphone cancelled; Send sends nothing', (t) async {
    await dictating(t);
    await t.runAsync(() async {
      await signInAs(memberB);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(listening(), isTrue, reason: 'premise: no frame');
    await hear(t, 'I am diabetic');
    expect(draft(t), isNot(contains('diabetic')),
        reason: "heard while B is the one signed in");
    expect(asked, contains('cancel'));
    await t.tap(find.byIcon(Icons.send));
    await settle(t);
    expect(coach.sent, isEmpty);
    expect(reported.map((f) => f.origin), ['aiNutrition.identity']);
    expect(draft(t), isEmpty);
    expect(listening(), isFalse);
    await close(t);
  });

  testWidgets('B dictates after A left: B\'s words land in B\'s composer',
      (t) async {
    await dictating(t);
    await t.runAsync(() => signInAs(memberB));
    await settle(t);
    await t.tap(find.byIcon(Icons.mic_none_outlined));
    await settle(t);
    await hear(t, 'lunch ideas');
    await settle(t);
    expect(draft(t), 'lunch ideas');
    await close(t);
  });

  testWidgets("CONTROL: the same member's new session: still listening, the "
      'words land and are sent', (t) async {
    await dictating(t);
    await t.runAsync(refreshSession);
    await settle(t);
    expect(asked, isNot(contains('cancel')));
    expect(listening(), isTrue);
    await hear(t, 'I am hungry', last: true);
    await settle(t);
    expect(draft(t), 'I am hungry');
    expect(listening(), isFalse);
    await t.tap(find.byIcon(Icons.send));
    await settle(t);
    expect(coach.sent, ['I am hungry']);
    expect(reported, isEmpty);
    await close(t);
  });
}
