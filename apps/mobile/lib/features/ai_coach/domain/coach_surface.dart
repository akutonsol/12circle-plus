/// FIT-102 … FIT-110 · `/ai-coach` has two surfaces, and they are tabs.
///
/// ── WHAT THE BOARD SAYS ────────────────────────────────────────────────────
/// **Nine** anchors are drawn on `/ai-coach`, and every one of them carries the
/// same three controls: `Back`, a **`Coaching`** tab and a **`Conversation`**
/// tab. Four of them describe the coaching surface (first open, today, the
/// week, how it speaks) and three describe the conversation (conversation, a
/// turn that failed, coming back). The two are always both reachable.
///
/// ── WHAT SHIPPED ───────────────────────────────────────────────────────────
/// There are no tabs. Both surfaces exist, but they are mutually exclusive on
/// a condition nobody chose:
///
/// ```dart
/// child: _messages.length <= 1
///     ? ListView( … the eight intelligence cards … )
///     : ListView.builder( … the conversation … )
/// ```
///
/// **Send one message and the cards are gone.** The daily brief, the weekly
/// review, the goal projection, the risk card, the persona picker and the
/// coaching memory — every write surface on this screen — become unreachable
/// for the rest of the session, with no control anywhere that brings them
/// back. `_messages.length <= 1` is not a user-facing idea; it is an
/// implementation detail deciding which half of the screen exists.
///
/// This file holds the two names and the one rule, so neither is decided
/// inside a 1,000-line `build`.
library;

enum CoachSurface {
  /// The intelligence cards. FIT-102/103/104/105.
  coaching(label: 'Coaching'),

  /// The chat. FIT-108/109/110.
  conversation(label: 'Conversation');

  const CoachSurface({required this.label});
  final String label;
}

/// FIT-108 names the input. It read "Ask your AI coach...".
const askYourCoachHint = 'Ask your coach';

/// Sending from the coaching surface has to move the user to where the answer
/// will appear — otherwise the suggested prompts post into a surface the user
/// cannot see, which is the shipped behaviour's only redeeming accident: the
/// old code swapped the whole body at exactly that moment.
CoachSurface surfaceAfterSending(CoachSurface current) =>
    CoachSurface.conversation;

/// Whether the mode chips and the composer belong on this surface.
///
/// `General` / `Nutrition` / `Workout` are declared only on the conversation
/// anchors (FIT-108, FIT-109); they choose what the chat is about, and mean
/// nothing beside a goal-projection card.
bool showsComposer(CoachSurface s) => s == CoachSurface.conversation;
