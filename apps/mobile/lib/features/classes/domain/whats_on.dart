import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/class_model.dart';
import '../../challenges/data/models/challenge_model.dart';

/// FIT-027 · "What's on" — `/classes · /events · /challenges under one list`.
///
/// ── WHAT THIS FILE IS ──────────────────────────────────────────────────────
/// The pure half of the anchor: three unrelated shapes folded into one
/// chronological list, and the rules for what happens when one of the three
/// fails. No Riverpod, no Supabase, no widgets — so every rule below is
/// testable, which is the point. `plan_summary.dart`, `extendRest()`,
/// `weekProgressFrom` and `coachSectionFor` were extracted for the same reason.
///
/// ── THE RULE THAT MATTERS ──────────────────────────────────────────────────
/// **A partial failure is reported, never hidden.** Three sources load
/// independently. If Events fails and the other two succeed, showing the
/// surviving two as "what's on" tells the client there are no events this
/// month — a false answer assembled out of a true one and a failure. That is
/// the F-15 collapse with extra steps, and it is why [WhatsOn] carries
/// [WhatsOn.failed] rather than just a list.
enum WhatsOnKind { classes, events, challenges }

/// One row in the unified list.
class WhatsOnItem {
  /// Stable identity from the source row, prefixed by kind so two sources
  /// cannot collide on the same id.
  final String id;
  final WhatsOnKind kind;

  /// What the list sorts and groups by.
  final DateTime when;
  final String title;

  /// The design's second line: `Class · Studio 2 · 4 places left`.
  final String detail;

  /// The trailing affordance the design draws on some rows — "Book", "Going".
  /// Null where the row has none.
  final String? action;

  const WhatsOnItem({
    required this.id,
    required this.kind,
    required this.when,
    required this.title,
    required this.detail,
    this.action,
  });
}

/// What the screen has to work with: the rows that loaded, and which sources
/// did not.
typedef WhatsOn = ({List<WhatsOnItem> items, Set<WhatsOnKind> failed});

/// The design's own segment labels, in the order it draws them.
const whatsOnSegments = <String>['All', 'Classes', 'Events', 'Challenges'];

/// The kind a segment index selects. Index 0 ("All") selects everything.
WhatsOnKind? kindForSegment(int index) => switch (index) {
      1 => WhatsOnKind.classes,
      2 => WhatsOnKind.events,
      3 => WhatsOnKind.challenges,
      _ => null,
    };

/// A class as a row.
///
/// The detail line follows the design's shape — `Class · Studio 2 · 4 places
/// left` — and every part of it comes from the row. Capacity that is
/// already full says so rather than reporting a negative number.
WhatsOnItem classRow(FitnessClass c) {
  final left = c.capacity - c.bookedCount;
  final places = left > 0 ? '$left places left' : 'Full';
  return WhatsOnItem(
    id: 'class:${c.id}',
    kind: WhatsOnKind.classes,
    when: c.startTime,
    title: c.title,
    detail: 'Class · ${c.location} · $places',
    // A class the client has already booked does not offer "Book" again —
    // the same one-way rule the set tracker's "Log set" follows.
    action: c.isBooked ? 'Booked' : (left > 0 ? 'Book' : null),
  );
}

/// An event as a row. Events arrive as raw `Map`s from PostgREST, so every
/// field is treated as absent-until-proven rather than force-unwrapped.
WhatsOnItem? eventRow(Map<String, dynamic> e) {
  final raw = e['event_date'] as String?;
  final when = raw == null ? null : DateTime.tryParse(raw);
  // A row with no date cannot be placed in a chronological list. Dropping it is
  // the only honest option; inventing a date would put a real event on a day it
  // is not happening.
  if (when == null) return null;
  final id = e['id']?.toString();
  if (id == null) return null;

  final time = _hhmm(when.toLocal());
  final going = e['current_registered'] as int? ?? 0;
  return WhatsOnItem(
    id: 'event:$id',
    kind: WhatsOnKind.events,
    when: when.toLocal(),
    title: e['title'] as String? ?? 'Event',
    detail: 'Event · $time · $going going',
  );
}

/// A challenge as a row.
///
/// The design draws challenges by their **closing** date ("14 Sep · Challenge
/// closes"), not their start, because that is the date that matters to someone
/// deciding whether to join.
WhatsOnItem challengeRow(Challenge c) => WhatsOnItem(
      id: 'challenge:${c.id}',
      kind: WhatsOnKind.challenges,
      when: c.endDate,
      title: c.title,
      detail: 'Challenge closes · ${c.participantCount} in',
      action: c.isJoined ? 'Joined' : null,
    );

/// Folds the three sources into one list, oldest first.
///
/// Ties are broken by kind then id so the order is total and a rebuild cannot
/// reshuffle rows that share a timestamp.
List<WhatsOnItem> mergeWhatsOn({
  required List<WhatsOnItem> classes,
  required List<WhatsOnItem> events,
  required List<WhatsOnItem> challenges,
}) {
  final all = <WhatsOnItem>[...classes, ...events, ...challenges];
  all.sort((a, b) {
    final t = a.when.compareTo(b.when);
    if (t != 0) return t;
    final k = a.kind.index.compareTo(b.kind.index);
    return k != 0 ? k : a.id.compareTo(b.id);
  });
  return all;
}

/// The rows a segment should show.
List<WhatsOnItem> itemsForSegment(List<WhatsOnItem> items, int segment) {
  final kind = kindForSegment(segment);
  return kind == null ? items : items.where((i) => i.kind == kind).toList();
}

/// Whether the selected segment is missing a source.
///
/// On "All" any failure is relevant. On a single segment only that source's
/// failure is — telling someone looking at Classes that Challenges failed is
/// noise, and hiding it from them when Classes itself failed is the defect.
Set<WhatsOnKind> failedForSegment(Set<WhatsOnKind> failed, int segment) {
  final kind = kindForSegment(segment);
  if (kind == null) return failed;
  return failed.contains(kind) ? {kind} : const {};
}

/// Day headers: `11 Sep`.
String dayLabel(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// Rows grouped under their day, preserving the merged order.
List<({String day, List<WhatsOnItem> items})> groupByDay(
    List<WhatsOnItem> items) {
  final out = <({String day, List<WhatsOnItem> items})>[];
  for (final item in items) {
    final label = dayLabel(item.when);
    if (out.isNotEmpty && out.last.day == label) {
      out.last.items.add(item);
    } else {
      out.add((day: label, items: <WhatsOnItem>[item]));
    }
  }
  return out;
}

/// The already-shipped failure line for a source.
///
/// Not invented: "Could not load events" is the exact string
/// `events_screen.dart:66` already renders, "Could not load classes" is
/// `coach_classes_screen.dart:37`'s, and `Could not load [noun]` is the
/// pattern this repository uses in fifteen other places. A bespoke sentence
/// for this screen would be new product copy and would need OD-8.
String failureLine(WhatsOnKind kind) => switch (kind) {
      WhatsOnKind.classes => 'Could not load classes',
      WhatsOnKind.events => 'Could not load events',
      WhatsOnKind.challenges => 'Could not load challenges',
    };

/// The already-shipped empty line for a source.
///
/// FIT-027 declares only a `default` state, so it supplies no empty copy for
/// this screen. Rather than write some, each kind borrows the line its own
/// screen already renders: `coach_classes_screen.dart:45`,
/// `events_screen.dart:234`, `challenges_screen.dart:153`. Every one of them is
/// literally true when that source returned nothing.
///
/// On "All" the three are shown together, because there is no shipped sentence
/// that covers all three at once and inventing one is what OD-8 reserves.
String emptyLine(WhatsOnKind kind) => switch (kind) {
      WhatsOnKind.classes => 'No classes yet',
      WhatsOnKind.events => 'No upcoming events',
      WhatsOnKind.challenges => 'No challenges here',
    };

/// The empty lines to show for a segment: one for a single kind, all three on
/// "All".
List<String> emptyLinesForSegment(int segment) {
  final kind = kindForSegment(segment);
  return kind == null
      ? WhatsOnKind.values.map(emptyLine).toList()
      : [emptyLine(kind)];
}

/// Combines the three source reads into one answer.
///
/// Pure, because the two rules it encodes are the ones most likely to be
/// quietly undone by a later edit, and both are invisible in a screenshot.
///
/// **It waits for all three to settle.** A source still in flight contributes
/// no rows, which is indistinguishable from one that returned none. Rendering
/// early shows a list that is briefly, silently wrong — and on a fast
/// connection nobody ever sees it happen.
///
/// **A failed source contributes nothing, including any stale value it is
/// still carrying.** Riverpod hands an `AsyncError` its previous value during
/// a refresh, so `.valueOrNull` on a failed read returns last week's rows.
/// Showing those under today's headings is a quieter version of the same lie,
/// and reaching for `.valueOrNull` is exactly how the `/profile` collapse
/// worked.
AsyncValue<WhatsOn> combineWhatsOn({
  required AsyncValue<List<FitnessClass>> classes,
  required AsyncValue<List<Map<String, dynamic>>> events,
  required AsyncValue<List<Challenge>> challenges,
}) {
  bool settled(AsyncValue<Object?> v) => v.hasValue || v.hasError;
  if (!settled(classes) || !settled(events) || !settled(challenges)) {
    return const AsyncValue.loading();
  }

  final failed = <WhatsOnKind>{
    if (classes.hasError) WhatsOnKind.classes,
    if (events.hasError) WhatsOnKind.events,
    if (challenges.hasError) WhatsOnKind.challenges,
  };

  return AsyncValue.data((
    items: mergeWhatsOn(
      classes: _rows(classes).map(classRow).toList(),
      events: _rows(events).map(eventRow).whereType<WhatsOnItem>().toList(),
      challenges: _rows(challenges).map(challengeRow).toList(),
    ),
    failed: failed,
  ));
}

/// The rows a source contributes.
///
/// Matches on the STATE, never on `.valueOrNull`. Two reasons, and they are the
/// same one twice: an error's value and an empty result's value are
/// indistinguishable at the call site — which is how the `/profile` collapse
/// worked — and `.valueOrNull` is the read EC-G8 ratchets, so fixing an
/// error-to-empty collapse by adding three of them would have been
/// self-defeating.
List<S> _rows<S>(AsyncValue<List<S>> v) => switch (v) {
      AsyncError() => const [],
      AsyncValue(:final List<S> value) => value,
      _ => const [],
    };

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
