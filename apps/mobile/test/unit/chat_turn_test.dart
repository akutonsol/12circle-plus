import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/ai_nutrition/data/ai_nutrition_service.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/ai_nutrition_provider.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/chat_turn.dart';

// FIT-090 · "AI nutrition — a turn that failed".
//
// When a turn failed, sendMessage appended the error AS THE COACH
// (`isUser: false`). Two consequences, and the second is the serious one:
//
//   * on screen it drew a coach bubble — same avatar, same styling — so a
//     transport failure was indistinguishable from nutrition advice, with no
//     retry but to retype;
//   * `_buildHistory()` mapped every `isUser: false` entry to
//     `role: 'assistant'`, so the next request told the model it had said
//     "Sorry, I encountered an error." — an apology for an error it never had,
//     now part of the conversation it was asked to continue.

ChatMessage _user(String c, {bool failed = false}) =>
    ChatMessage(content: c, isUser: true, timestamp: DateTime(2026), failed: failed);
ChatMessage _coach(String c, {bool failed = false}) =>
    ChatMessage(content: c, isUser: false, timestamp: DateTime(2026), failed: failed);

class _ThrowingService implements AiNutritionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw Exception('network');
}

class _EchoService implements AiNutritionService {
  /// What the notifier passed as prior context on the most recent call.
  List<Map<String, dynamic>>? seenHistory;
  int calls = 0;

  @override
  Future<String> sendMessage({
    required String message,
    List<Map<String, dynamic>>? history,
    dynamic imageFile,
  }) async {
    calls++;
    seenHistory = history;
    return 'Answer to: $message';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('apiHistory', () {
    test('a failed turn is NOT something the assistant said', () {
      final history = apiHistory([
        _user('how much protein?'),
        _coach('That message didn\'t get through.', failed: true),
      ]);

      expect(history, hasLength(1));
      expect(history.single['role'], 'user');
      expect(history.map((h) => h['content']).join(),
          isNot(contains('didn\'t get through')),
          reason: 'the model was being told it had apologised for an error it '
              'never had, and asked to continue that conversation');
    });

    test('ordinary turns still carry their roles', () {
      final history = apiHistory([
        _coach('Hi! I can help with nutrition.'),
        _user('how much protein?'),
        _coach('About 1.6 g per kg.'),
      ]);
      expect(history.map((h) => h['role']), ['assistant', 'user', 'assistant']);
      expect(history.last['content'], 'About 1.6 g per kg.');
    });

    test('a failed turn in the MIDDLE is dropped too, not just a trailing one',
        () {
      final history = apiHistory([
        _user('first'),
        _coach('nope', failed: true),
        _user('second'),
        _coach('answer'),
      ]);
      expect(history.map((h) => h['content']), ['first', 'second', 'answer']);
    });
  });

  group('the retry knows what to re-send', () {
    test('it finds the last thing the USER said, past the notice', () {
      expect(
        lastUserTurn([
          _user('older'),
          _coach('fine'),
          _user('how much protein?'),
          _coach('failed', failed: true),
        ])?.content,
        'how much protein?',
      );
    });

    test('nothing to retry in a conversation the user has not spoken in', () {
      expect(lastUserTurn([_coach('Hi!')]), isNull);
    });

    test('the failure AND the turn it belongs to are removed', () {
      // Otherwise the retry leaves a duplicate of both behind.
      final after = withoutFailedTail([
        _coach('Hi!'),
        _user('how much protein?'),
        _coach('failed', failed: true),
      ]);
      expect(after.map((m) => m.content), ['Hi!']);
    });

    test('awaitingRetry is true only while sitting on a failure', () {
      expect(awaitingRetry([_user('x'), _coach('failed', failed: true)]),
          isTrue);
      expect(awaitingRetry([_user('x'), _coach('fine')]), isFalse);
      expect(awaitingRetry([]), isFalse);
    });
  });

  group('the notifier, end to end', () {
    test('a thrown turn is marked failed, not spoken by the coach', () async {
      final n = AiNutritionNotifier(_ThrowingService());
      await n.sendMessage('how much protein?');

      expect(n.state.last.failed, isTrue);
      expect(n.state.last.isUser, isFalse);
      // The visible sentence is the app's, not written in the coach's voice.
      expect(n.state.last.content, turnFailedNotice);
    });

    test('the NEXT request does not contain the failure', () async {
      // The whole point. A failed turn used to be replayed as assistant
      // context on every subsequent turn for the rest of the session.
      final bad = AiNutritionNotifier(_ThrowingService());
      await bad.sendMessage('how much protein?');
      final withFailure = bad.state;

      final echo = _EchoService();
      final n = AiNutritionNotifier(echo);
      n.state = withFailure;
      await n.sendMessage('and carbs?');

      final sent = echo.seenHistory ?? const [];
      expect(
        sent.any((h) =>
            (h['content'] as String).contains('get through') ||
            (h['content'] as String).contains('encountered an error')),
        isFalse,
        reason: 'the failure was sent back to the model as role: assistant',
      );
    });

    test('Send it again re-sends the turn without duplicating it', () async {
      final bad = AiNutritionNotifier(_ThrowingService());
      await bad.sendMessage('how much protein?');
      expect(bad.state.where((m) => m.isUser), hasLength(1));

      final echo = _EchoService();
      final n = AiNutritionNotifier(echo);
      n.state = bad.state;
      await n.retryLastTurn();

      expect(echo.calls, 1);
      expect(n.state.where((m) => m.isUser).map((m) => m.content),
          ['how much protein?'],
          reason: 'the user turn must not appear twice after a retry');
      expect(n.state.any((m) => m.failed), isFalse,
          reason: 'and the notice it replaced must be gone');
      expect(n.state.last.content, 'Answer to: how much protein?');
    });

    test('retrying with nothing to retry does nothing', () async {
      final echo = _EchoService();
      final n = AiNutritionNotifier(echo);
      await n.retryLastTurn();
      expect(echo.calls, 0);
    });
  });

  test('FIT-090 names the control', () {
    expect(sendItAgainLabel, 'Send it again');
  });
}
