import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach_notes/data/coach_note_service.dart';
import 'package:circle_fitness/features/dashboard/domain/still_reading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/two_coach_postgrest.dart';

// P0-FL-59f · whose rows a held list is, and what that lets a screen say.
// (New functions: at a82f993 this file does not compile.)

typedef _Rows = List<Map<String, dynamic>>;

_Rows _rows() => [
      {'id': 'c1'}
    ];

void main() {
  late TwoCoachPostgrest server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoCoachPostgrest();
    await initTwoMemberSupabase(server);
  });
  setUp(() async {
    server.reset();
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  group('stillReading', () {
    AsyncValue<_Rows> held(_Rows rows) => const AsyncLoading<_Rows>()
        .copyWithPrevious(AsyncData(rows), isRefresh: false);

    test("another coach's rows: still reading, loading or not", () {
      final rows = ownedBy('a', _rows());
      expect(stillReading(held(rows), uid: 'b'), isTrue);
      expect(stillReading(AsyncData(rows), uid: 'b'), isTrue);
      expect(stillReading(AsyncData(rows)), isTrue, reason: 'signed out');
    });

    test('their own rows are an answer, also while re-read, also empty', () {
      for (final rows in [_rows(), <Map<String, dynamic>>[]]) {
        ownedBy('a', rows);
        expect(stillReading(held(rows), uid: 'a'), isFalse);
        expect(stillReading(AsyncData(rows), uid: 'a'), isFalse);
      }
    });

    test("a failure over another coach's rows is a failure, not reading", () {
      final failed = AsyncError<_Rows>('offline', StackTrace.empty)
          .copyWithPrevious(AsyncData(ownedBy('a', _rows())));
      expect(failed.hasValue, isTrue, reason: 'premise: Riverpod holds them');
      expect(stillReading(failed, uid: 'b'), isFalse);
      expect(ownerOfHeld(failed), 'a');
    });

    test('signed out marks nothing', () {
      expect(ownerOfHeld(AsyncData(ownedBy(null, _rows()))), isNull);
      expect(ownerOfHeld(const AsyncLoading<_Rows>()), isNull);
    });
  });

  group('CoachNoteService.addNote', () {
    test("A's note is not stored once B is signed in, and it is recorded",
        () async {
      final reported = <AppFailure>[];
      setFailureSink(reported.add);
      await signInAs(memberB);
      expect(
          await CoachNoteService().addNote('cl', 'private', owner: memberA),
          isFalse);
      expect(server.writes, isEmpty);
      expect(reported.single.origin, 'CoachNoteService.addNote');
    });

    test('control: A signed in: one row, stamped A', () async {
      expect(
          await CoachNoteService().addNote('cl', 'private', owner: memberA),
          isTrue);
      final w = server.writesTo('coach_notes').single;
      expect((w.who, w.body['coach_id'], w.body['body']),
          (memberA, memberA, 'private'));
    });

    test('a refused insert is false, and recorded', () async {
      final reported = <AppFailure>[];
      setFailureSink(reported.add);
      server.fails.add('POST coach_notes:$memberA');
      expect(
          await CoachNoteService().addNote('cl', 'private', owner: memberA),
          isFalse);
      expect(reported.single.origin, 'CoachNoteService.addNote');
    });
  });
}
