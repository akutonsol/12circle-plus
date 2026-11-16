import 'dart:io';

import 'package:circle_fitness/features/exercise_database/domain/exercise_edit_rights.dart';
import 'package:flutter_test/flutter_test.dart';

// Owner decision 15 (migration 199): platform exercise media belongs to the
// content editors (admin, content_manager); a private exercise to its coach
// (and an admin). The app offers Edit only where the database will accept it.
// Before, the Edit button showed for every coach on every exercise.

const coach = 'coach-a';
const other = 'coach-b';

void main() {
  group('a PLATFORM exercise (no owning coach)', () {
    test('admins and content managers may edit it', () {
      expect(canEditExercise(role: 'admin', uid: 'x', exerciseCoachId: null), isTrue);
      expect(canEditExercise(role: 'content_manager', uid: 'x', exerciseCoachId: null), isTrue);
    });
    test('a coach may not (shared media is not one coach\'s to replace)', () {
      expect(canEditExercise(role: 'coach', uid: coach, exerciseCoachId: null), isFalse);
      expect(canEditExercise(role: 'coach', uid: coach, exerciseCoachId: ''), isFalse);
    });
    test('a client may not', () {
      expect(canEditExercise(role: 'client', uid: 'c', exerciseCoachId: null), isFalse);
    });
  });

  group('a PRIVATE exercise', () {
    test('its coach may edit it', () {
      expect(canEditExercise(role: 'coach', uid: coach, exerciseCoachId: coach), isTrue);
    });
    test('another coach may not', () {
      expect(canEditExercise(role: 'coach', uid: other, exerciseCoachId: coach), isFalse);
    });
    test('a content manager may not; an admin may', () {
      expect(canEditExercise(role: 'content_manager', uid: 'k', exerciseCoachId: coach), isFalse);
      expect(canEditExercise(role: 'admin', uid: 'm', exerciseCoachId: coach), isTrue);
    });
    test('no session, no edit', () {
      expect(canEditExercise(role: 'coach', uid: null, exerciseCoachId: coach), isFalse);
    });
  });

  test('the exercise screen\'s Edit button uses this rule', () {
    final src = File('lib/features/exercise_database/presentation/exercise_detail_screen.dart')
        .readAsStringSync();
    final fab = src.substring(src.indexOf('class _EditFab'), src.indexOf('class _EnrichFab'));
    expect(fab, contains('canEditExercise(role: role, uid: uid, exerciseCoachId: exercise.coachId)'));
    expect(fab, isNot(contains("role != 'coach' && role != 'admin'")),
        reason: 'THE defect: every coach was offered Edit on every exercise');
  });
}
