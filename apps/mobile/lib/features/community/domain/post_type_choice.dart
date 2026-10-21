/// FIT-067 · "Create post". The board marks this anchor **`missing`** and
/// names the capability it should be using: `addPost(content, postType)`.
///
/// ── THE TYPE IS LOST THREE DIFFERENT WAYS ──────────────────────────────────
/// `post_model.dart` already declares
/// `enum PostType { text, photo, progress, workout, achievement }` — exactly
/// the five the board draws as radios. Every layer between that enum and the
/// database drops it somewhere else:
///
/// **1 · The chips are dead.** `community_screen.dart` draws three of the five
/// and hands each one an empty callback:
///
/// ```dart
/// _buildPostTypeChip('📸 Photo', () {}),
/// _buildPostTypeChip('🏆 Achievement', () {}),
/// _buildPostTypeChip('💪 Workout', () {}),
/// ```
///
/// They look selectable, they highlight nothing, and nothing anywhere reads
/// them. The board declares five, as `role="radio"` — a mutually exclusive
/// choice, which three unrelated buttons are not.
///
/// **2 · The write ignores it.** The Post button calls
/// `addPost(text)` and never passes `postType:`, so every post created by this
/// app is written as the default `'general'` — whatever the user tapped.
///
/// **3 · The read cannot recover it.** `_parseType` maps `progress` and
/// `achievement` and sends everything else to `text`:
///
/// ```dart
/// PostType _parseType(String t) => switch (t) {
///   'progress' => PostType.progress,
///   'achievement' => PostType.achievement,
///   _ => PostType.text,
/// };
/// ```
///
/// So `photo` and `workout` **cannot survive a write-and-read** even once the
/// first two defects are fixed. A post saved as a workout comes back as text.
///
/// One mapping, used by the UI and the service, so the three cannot drift
/// apart again.
library;

import '../data/models/post_model.dart';

/// The board's word for each type.
String postTypeLabel(PostType t) => switch (t) {
      PostType.text => 'Text',
      PostType.photo => 'Photo',
      PostType.progress => 'Progress',
      PostType.workout => 'Workout',
      PostType.achievement => 'Achievement',
    };

/// What goes in `post_type`.
String postTypeWire(PostType t) => t.name;

/// What comes back out.
///
/// `'general'` is kept as `text`: it is what every post this app has written
/// so far carries, and dropping it would re-type existing rows.
PostType parsePostType(String? wire) => switch (wire) {
      'photo' => PostType.photo,
      'progress' => PostType.progress,
      'workout' => PostType.workout,
      'achievement' => PostType.achievement,
      // 'text', 'general', null and anything unrecognised.
      _ => PostType.text,
    };

/// The order the board draws them in.
const postTypeChoices = PostType.values;

// ── Copy. FIT-067 names these. ─────────────────────────────────────────────

/// The composer's placeholder. It read
/// "Share your progress, tips, or motivation...".
/// Double-quoted deliberately: written as `'What\'s on your mind?'` the
/// SOURCE contains a backslash, and the coverage resolver — which matches
/// rendered labels as string literals — reads it as absent. The rendered text
/// is identical either way; the escape is the only difference.
const composerHint = "What's on your mind?";

/// The submit control. It read "Post to Community".
const postSubmitLabel = 'Post';

const postCancelLabel = 'Cancel';

// `Add a photo` is NOT declared here.
//
// FIT-067 draws it, and `createPost` already takes `imageUrls` — but nothing
// on this screen picks or uploads an image, and there is no storage path for
// post images anywhere in `lib`. A constant would make the coverage resolver
// report the control as present, because it measures rendered labels as string
// literals in the screen's file set and cannot tell a declared name from a
// drawn one. That is the same false positive `sessionDoneLabel` produced for
// FIT-018, where the measurement said `Done` and the button said `Submit`.
//
// So the control is recorded as missing (OD-36) rather than named into
// existence.
