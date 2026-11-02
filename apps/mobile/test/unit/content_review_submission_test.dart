import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/exercise_database/domain/content_review_submission.dart';

void main() {
  bool submit({
    String? role = 'admin',
    bool editingExisting = true,
    bool mediaOnly = false,
    String? visibility = 'global',
    String? contentStatus = 'draft',
    List<String> instructions = const ['Brace, then press.'],
  }) =>
      shouldSubmitForReview(
        role: role,
        editingExisting: editingExisting,
        mediaOnly: mediaOnly,
        visibility: visibility,
        contentStatus: contentStatus,
        instructions: instructions,
      );

  group('a hand-written library draft is submitted for review', () {
    test('admin saving instructions on a global draft → submitted', () {
      expect(submit(), isTrue);
    });
    test('content_manager is a content editor too', () {
      expect(submit(role: 'content_manager'), isTrue);
    });
  });

  group('nothing else is submitted', () {
    test('a coach or client never submits', () {
      expect(submit(role: 'coach'), isFalse);
      expect(submit(role: 'client'), isFalse);
      expect(submit(role: null), isFalse);
    });
    test('a new exercise (not an edit) is not submitted', () {
      expect(submit(editingExisting: false), isFalse);
    });
    test('a media-only save is not submitted', () {
      expect(submit(mediaOnly: true), isFalse);
    });
    test('a private or team exercise is not submitted', () {
      expect(submit(visibility: 'private'), isFalse);
      expect(submit(visibility: 'team'), isFalse);
    });
    test('only drafts move — reviewed, approved or published content is left alone', () {
      for (final s in ['ai_generated', 'under_review', 'needs_revision', 'approved', 'published', 'archived', null]) {
        expect(submit(contentStatus: s), isFalse, reason: 'status $s');
      }
    });
    test('no written instructions → not submitted (blank lines do not count)', () {
      expect(submit(instructions: const []), isFalse);
      expect(submit(instructions: const ['   ', '']), isFalse);
    });
  });
}
