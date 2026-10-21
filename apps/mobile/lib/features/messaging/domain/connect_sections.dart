import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../classes/domain/whats_on.dart';
import '../../community/data/models/post_model.dart';

/// FIT-005 · Connect — "Coach, community and pods in one relationship layer".
///
/// ── WHAT THE ANCHOR ACTUALLY ASKS FOR ──────────────────────────────────────
/// `/messages` was a conversation list. FIT-005 makes it the place a client
/// sees every relationship they have: their coach, the feed, their groups, and
/// what is coming up. Its declared rows are a community post, a group, a class
/// and a challenge — four different shapes, three more sources behind one
/// screen.
///
/// ── AND THE RULE THAT COMES WITH THAT ──────────────────────────────────────
/// The same one FIT-027 is built around, for the same reason: **a section whose
/// source failed must never be drawn as a section with nothing in it.** A
/// relationship layer that quietly omits your groups when the read fails tells
/// you that you have none. [ConnectSection] therefore has a `failed` state
/// distinct from `empty`, and the screen cannot render one as the other.
///
/// Nothing here fabricates content. Every row is a real post, group, class or
/// challenge; the anchor's own sample rows ("Priya Hit 70 kg on the hinge
/// today") are demo data on the board, not a requirement.
enum ConnectSectionState { loading, failed, empty, data }

/// A teaser section: a title, a handful of rows, and a truthful state.
typedef ConnectSection<T> = ({
  ConnectSectionState state,
  List<T> items,
});

/// How many rows a teaser shows before deferring to the full screen.
const connectTeaserLimit = 2;

/// Derives a teaser from a source read.
///
/// Matches on the STATE, never on `.valueOrNull`: an error's value and an
/// empty result's value are the same null at the call site, which is exactly
/// how the `/profile` "No coach assigned yet" collapse worked.
ConnectSection<T> teaserFrom<T>(AsyncValue<List<T>> source,
    {int limit = connectTeaserLimit}) {
  return switch (source) {
    AsyncError() => (state: ConnectSectionState.failed, items: const []),
    AsyncValue(:final List<T> value) => value.isEmpty
        ? (state: ConnectSectionState.empty, items: const [])
        : (
            state: ConnectSectionState.data,
            items: value.take(limit).toList(),
          ),
    _ => (state: ConnectSectionState.loading, items: const []),
  };
}

/// The "What's on" teaser, built from FIT-027's merged list rather than from a
/// second pipeline over the same three tables.
///
/// Reusing it is deliberate. Two independent definitions of "what is coming up"
/// would drift, and the first symptom would be `/messages` and `/classes`
/// disagreeing in front of the client.
ConnectSection<WhatsOnItem> whatsOnTeaser(AsyncValue<WhatsOn> source,
    {int limit = connectTeaserLimit}) {
  return switch (source) {
    AsyncError() => (state: ConnectSectionState.failed, items: const []),
    AsyncValue(:final WhatsOn value) => () {
        // Any source behind the merged list having failed makes this teaser a
        // partial view, and a partial view presented as a summary is the same
        // lie in a smaller box.
        if (value.failed.isNotEmpty && value.items.isEmpty) {
          return (
            state: ConnectSectionState.failed,
            items: const <WhatsOnItem>[]
          );
        }
        return value.items.isEmpty
            ? (state: ConnectSectionState.empty, items: const <WhatsOnItem>[])
            : (
                state: ConnectSectionState.data,
                items: value.items.take(limit).toList(),
              );
      }(),
    _ => (state: ConnectSectionState.loading, items: const []),
  };
}

/// One line describing a post, in the shape the anchor draws:
/// `Priya Hit 70 kg on the hinge today · 2h`.
String postLine(CommunityPost p, {DateTime? now}) {
  final body = p.content.trim();
  final short = body.length <= 60 ? body : '${body.substring(0, 57)}…';
  return '${p.userName} $short · ${relativeAge(p.createdAt, now: now)}';
}

/// One line describing a group: `Tues Lifters · 12 members`.
String groupLine(CommunityGroup g) =>
    '${g.name} · ${g.memberCount} ${g.memberCount == 1 ? 'member' : 'members'}';

/// `2h`, `3d`, `now`. The anchor's own shorthand.
String relativeAge(DateTime at, {DateTime? now}) {
  final delta = (now ?? DateTime.now()).difference(at);
  if (delta.inMinutes < 1) return 'now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m';
  if (delta.inHours < 24) return '${delta.inHours}h';
  return '${delta.inDays}d';
}

/// The already-shipped failure line for each section.
///
/// "Could not load posts" is rendered verbatim at `community_screen.dart:246`.
/// The other two follow the `Could not load [noun]` pattern this repository
/// uses in fifteen files, with nouns taken from the design package's own
/// declared labels ("Groups", "What's on"). A bespoke sentence would be new
/// product copy and would need OD-8.
const connectFeedFailure = 'Could not load posts';
const connectGroupsFailure = 'Could not load groups';
