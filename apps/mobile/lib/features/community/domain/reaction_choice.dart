/// FIT-065 / FIT-066 · the five reactions, and what a screen reader calls them.
///
/// ── THE SAME DEFECT AS THE POST TYPE, ONE LAYER OVER ───────────────────────
/// `post_model.dart` declares
/// `enum ReactionType { like, love, fire, clap, strong }`, the service takes
/// the type as an argument, and the read path parses all five:
///
/// ```dart
/// Future<void> toggleReaction(String postId, String reactionType) async { … }
///
/// ReactionType _parseReaction(String r) => switch (r) {
///   'fire' => ReactionType.fire, 'love' => ReactionType.love,
///   'clap' => ReactionType.clap, 'strong' => ReactionType.strong,
///   _ => ReactionType.like };
/// ```
///
/// And the provider hardcodes one:
///
/// ```dart
/// Future<void> toggleLike(String postId) async {
///   await _svc.toggleReaction(postId, 'like');   // always
/// ```
///
/// So **four of the five can be read but never written by this app**. The
/// model supports them, the service supports them, the parser supports them,
/// and nothing can create one. The UI offers a single heart.
///
/// ── AND THE SUMMARY HAS NO NAME ────────────────────────────────────────────
/// `ReactionBar` draws the tally as bare emoji — `👍❤️🔥` and a number — so a
/// screen reader gets the emoji characters and a bare integer, with nothing
/// saying what they are.
///
/// The board writes the names out, with the count in them:
/// **`Like, 12 so far`**, **`Love, 4 so far`**, **`Strong, 3 so far`** — and
/// plain **`Fire`**, **`Clap`** where the count is zero. That asymmetry is the
/// rule, not an inconsistency: a reaction nobody has used yet has no tally to
/// announce.
library;

import '../data/models/post_model.dart';

/// The board's word for each reaction.
String reactionLabel(ReactionType t) => switch (t) {
      ReactionType.like => 'Like',
      ReactionType.love => 'Love',
      ReactionType.fire => 'Fire',
      ReactionType.clap => 'Clap',
      ReactionType.strong => 'Strong',
    };

/// What a screen reader announces for one reaction control.
///
/// `Like, 12 so far` when somebody has used it; plain `Fire` when nobody has.
/// Whether the reader has reacted rides on the control's selected state rather
/// than being written into the name, so it is announced in the user's own
/// language — the same rule `habit_row.dart` and `grocery_list.dart` follow.
String reactionSemanticLabel(ReactionType t, int count) =>
    count > 0 ? '${reactionLabel(t)}, $count so far' : reactionLabel(t);

String reactionWire(ReactionType t) => t.name;

ReactionType parseReactionType(String? wire) => switch (wire) {
      'love' => ReactionType.love,
      'fire' => ReactionType.fire,
      'clap' => ReactionType.clap,
      'strong' => ReactionType.strong,
      // 'like', null and anything unrecognised.
      _ => ReactionType.like,
    };

/// How many of each a post has.
Map<ReactionType, int> reactionCounts(List<PostReaction> reactions) {
  final out = {for (final t in ReactionType.values) t: 0};
  for (final r in reactions) {
    out[r.type] = (out[r.type] ?? 0) + 1;
  }
  return out;
}

/// Which one this user has left, if any.
///
/// `post_reactions` carries `UNIQUE(post_id, user_id)`, so one per person per
/// post is the schema's own rule. `toggleReaction` did not honour it: it
/// **deleted** whatever row existed regardless of type, so choosing a
/// different reaction removed the old one and left nothing rather than
/// switching. With one reaction in the UI that was invisible; the moment five
/// are offered it is the common case.
ReactionType? myReaction(List<PostReaction> reactions, String? uid) {
  if (uid == null) return null;
  for (final r in reactions) {
    if (r.userId == uid) return r.type;
  }
  return null;
}

/// What a tap should do to the stored row.
enum ReactionWrite {
  /// Nothing there yet.
  insert,

  /// The same one again — take it back.
  remove,

  /// A different one. `UNIQUE(post_id, user_id)` means this cannot be an
  /// insert, and it must not be a delete.
  change,
}

/// The decision, in a place a test can reach.
///
/// `toggleReaction` had two branches — row exists, delete; no row, insert —
/// so choosing a DIFFERENT reaction fell into the delete branch and removed
/// the old one, leaving nothing. With one reaction in the UI that was
/// invisible. With five it is the common case: every change of mind silently
/// became a removal.
ReactionWrite reactionWriteFor({
  required String? existingType,
  required ReactionType chosen,
}) {
  if (existingType == null) return ReactionWrite.insert;
  return existingType == reactionWire(chosen)
      ? ReactionWrite.remove
      : ReactionWrite.change;
}
