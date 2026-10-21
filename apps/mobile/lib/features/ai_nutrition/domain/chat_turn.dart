/// FIT-090 · "AI nutrition — a turn that failed".
///
/// ── THE DEFECT, WHICH IS TWO DEFECTS ───────────────────────────────────────
/// When a turn failed, `sendMessage` appended the error **as the coach**:
///
/// ```dart
/// state = [...state, ChatMessage(
///   content: 'Sorry, I encountered an error. Please try again.',
///   isUser: false,          // <- presented as the assistant speaking
/// )];
/// ```
///
/// **On screen** it is a coach bubble, with the coach's avatar and the coach's
/// styling, indistinguishable from nutrition advice. There is no retry — the
/// user has to retype what they just said.
///
/// **In the request** it is worse. `_buildHistory()` walks the whole message
/// list and maps every `isUser: false` entry to `role: 'assistant'`, so on the
/// next turn the model is told it previously said *"Sorry, I encountered an
/// error."* — an apology for an error it never had, now part of the
/// conversation it is asked to continue. A transport failure became a fact
/// about the coach.
///
/// FIT-090 is a designed screen with one control: **`Send it again`**.
///
/// The repair is to mark the turn `failed` and let both readers act on it: the
/// bubble draws a notice instead of the coach, and the history skips it.
library;

import 'ai_nutrition_provider.dart';

/// What actually goes to the model.
///
/// Failed turns are **excluded**. They are not something the assistant said.
List<Map<String, dynamic>> apiHistory(List<ChatMessage> messages) {
  final out = <Map<String, dynamic>>[];
  for (final m in messages) {
    if (m.failed) continue;
    final role = m.isUser ? 'user' : 'assistant';
    if (m.isUser && m.image != null) {
      // Image messages can't be replayed as base64 in history efficiently;
      // send a text summary so the conversation context is preserved.
      out.add({'role': role, 'content': '[Photo: ${m.content}]'});
    } else {
      out.add({'role': role, 'content': m.content});
    }
  }
  return out;
}

/// The turn `Send it again` will re-send: the last thing the user actually
/// said, ignoring the failure notice sitting after it.
ChatMessage? lastUserTurn(List<ChatMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    if (messages[i].isUser) return messages[i];
  }
  return null;
}

/// State with the trailing failure notice and the user turn it belongs to
/// removed, so a retry re-sends rather than duplicating both.
List<ChatMessage> withoutFailedTail(List<ChatMessage> messages) {
  final out = [...messages];
  while (out.isNotEmpty && out.last.failed) {
    out.removeLast();
  }
  if (out.isNotEmpty && out.last.isUser) out.removeLast();
  return out;
}

/// Whether the conversation is sitting on a failure right now.
bool awaitingRetry(List<ChatMessage> messages) =>
    messages.isNotEmpty && messages.last.failed;

// ── Copy. FIT-090 names the control. ───────────────────────────────────────

const sendItAgainLabel = 'Send it again';

/// The notice replaces a sentence that was written in the coach's voice
/// ("Sorry, I encountered an error") — which is what made it read as the coach
/// rather than as the app.
const turnFailedNotice = 'That message didn\'t get through.';
