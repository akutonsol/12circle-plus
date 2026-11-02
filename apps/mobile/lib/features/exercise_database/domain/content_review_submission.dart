// When saving an exercise should put it into the editorial review queue.
//
// The library's 601 `draft` exercises had no route to approval: the review queue
// lists only `ai_generated` / `under_review` / `needs_revision` rows, and saving
// in the editor never changes `content_status`. So content an admin writes by hand
// stayed `draft` — invisible to reviewers and never certifiable (182's
// certification needs `content_status` approved or published).
//
// This only SUBMITS for review (draft → under_review, through the existing
// review_exercise_content RPC, which snapshots a version). A human still approves
// it in the queue; nothing here approves or publishes anything.

/// Roles the database treats as content editors (`is_content_editor()`, 083).
const Set<String> kContentEditorRoles = {'admin', 'content_manager'};

/// True when a save should submit the exercise for editorial review: an existing
/// global library exercise, still `draft`, saved by a content editor through a
/// full text update, with written instructions.
bool shouldSubmitForReview({
  required String? role,
  required bool editingExisting,
  required bool mediaOnly,
  required String? visibility,
  required String? contentStatus,
  required List<String> instructions,
}) =>
    editingExisting &&
    !mediaOnly &&
    kContentEditorRoles.contains(role) &&
    visibility == 'global' &&
    contentStatus == 'draft' &&
    instructions.any((s) => s.trim().isNotEmpty);
