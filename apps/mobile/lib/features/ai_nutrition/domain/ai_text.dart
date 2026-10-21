/// FIT-093 / FIT-094 · one generated text, and whether it arrived.
///
/// ── THE ROOT CAUSE, IN ONE LINE ────────────────────────────────────────────
/// Both AI notifiers were `StateNotifier<String?>`, and both wrote their error
/// **into the slot the content lives in**:
///
/// ```dart
/// state = 'Error generating meal plan. Please try again.';
/// ```
///
/// A nullable string has two states and the screens needed three. With
/// `null` meaning "not asked yet", there was nowhere left to put "asked, and
/// it failed" — so the failure was written as content, and every consumer
/// downstream treated it as content:
///
///   * `/meal-plan` rendered the sentence **under the heading "Your Meal
///     Plan"**, and because `mealPlan != null` it then offered two routes to
///     build a grocery list *from an error message*;
///   * `/grocery-list` parsed it, kept nothing, and drew its header over an
///     empty column.
///
/// One failed request, presented as a plan on one screen and as an empty list
/// on the next.
///
/// Three states, named, so there is nowhere to hide a failure.
library;

class AiText {
  /// The generated text. `null` unless this is a `ready` result.
  final String? content;

  /// The request was made and did not produce usable text.
  final bool failed;

  const AiText._(this.content, this.failed);

  /// Nothing has been asked for yet.
  const AiText.idle() : this._(null, false);

  /// FIT-093's and FIT-094's `failure`. Content is deliberately `null`: there
  /// is no such thing as a failure that is also a plan.
  const AiText.failed() : this._(null, true);

  const AiText.ready(String text) : this._(text, false);

  bool get isReady => content != null;
}
