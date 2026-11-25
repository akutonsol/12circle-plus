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
      for (final read in [_rows(), <Map<String, dynamic>>[]]) {
        final rows = ownedBy('a', read);
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

    test('signed out marks nothing; no value has no owner', () async {
      expect(ownerOfHeld(AsyncData(ownedBy(null, _rows()))), unknownOwner,
          reason: 'A is signed in here: rows nobody marked are not theirs');
      expect(ownerOfHeld(const AsyncLoading<_Rows>()), isNull);
      await signOut();
      expect(ownerOfHeld(AsyncData(ownedBy(null, _rows()))), isNull);
    });

    test('rows that lost their mark fail closed for whoever is signed in', () {
      for (final lost in [
        _rows(),
        ownedBy(memberA, _rows()).toList(),
        ownedBy(memberA, _rows()).map((r) => r).toList(),
      ]) {
        expect(ownerOfHeld(AsyncData(lost)), unknownOwner);
        expect(stillReading(AsyncData(lost), uid: memberA), isTrue);
      }
      // Control: a real empty answer nobody marked is still an answer.
      expect(ownerOfHeld(const AsyncData(<Map<String, dynamic>>[])), isNull);
      expect(
          stillReading(const AsyncData(<Map<String, dynamic>>[]), uid: memberA),
          isFalse);
    });

    test('a shared const [] is never marked for anyone', () {
      const shared = <Map<String, dynamic>>[];
      final a = ownedBy('a', shared);
      final b = ownedBy('b', shared);
      expect(ownerOfHeld(const AsyncData(shared)), isNull);
      expect(ownerOfHeld(AsyncData(a)), 'a', reason: "B's mark replaced A's");
      expect(ownerOfHeld(AsyncData(b)), 'b');
    });
  });

  group('whose failure it is', () {
    Future<Object> failureOf(String uid, [Object? thrown]) async {
      try {
        await ownedRead<int>(uid, () async => throw thrown ?? Exception('off'));
      } catch (e) {
        return e;
      }
      throw StateError('did not fail');
    }

    AsyncValue<_Rows> held(Object e, {required bool loading, _Rows? rows}) {
      final failed = AsyncError<_Rows>(e, StackTrace.empty)
          .copyWithPrevious(rows == null
              ? const AsyncLoading<_Rows>()
              : AsyncData(rows));
      return loading
          ? const AsyncLoading<_Rows>().copyWithPrevious(failed)
          : failed;
    }

    test("A's, over A's rows, is not B's: B's is still being read, whatever "
        'state it is in', () async {
      final e = await failureOf(memberA);
      await signInAs(memberB);
      for (final loading in [true, false]) {
        final v = held(e, loading: loading, rows: ownedBy(memberA, _rows()));
        expect(v, isA<AsyncError<_Rows>>(), reason: 'premise');
        expect(leftBehind(v), isTrue);
        expect(stillReading(v, uid: memberB), isTrue);
        expect(heldFor(memberB, v), isA<AsyncLoading<_Rows>>());
        expect(heldFor(memberB, v, keepUnmarked: true),
            isA<AsyncLoading<_Rows>>());
      }
    });

    test("B's, over A's rows, is B's; read again it stays and is busy",
        () async {
      await signInAs(memberB);
      for (final thrown in [Exception('off'), StateError('signed out')]) {
        final e = await failureOf(memberB, thrown);
        for (final loading in [true, false]) {
          final v = heldFor(memberB,
              held(e, loading: loading, rows: ownedBy(memberA, _rows())));
          expect(v.error, same(e));
          expect(v.hasValue, isFalse, reason: "A's rows");
          expect(v.isLoading, loading, reason: 'its retry is busy');
          expect(leftBehind(v), isFalse);
        }
      }
    });

    test('control: their own failed refresh keeps their own rows', () async {
      final rows = ownedBy(memberA, _rows());
      final v = held(await failureOf(memberA), loading: false, rows: rows);
      expect(heldFor(memberA, v).value, same(rows));
      expect(heldFor(memberA, v).hasError, isTrue);
      expect(stillReading(v, uid: memberA), isFalse);
    });

    test('a failure nobody marked is kept only when that is asked for, and a '
        'bare string cannot be marked', () async {
      final v = held('offline', loading: true);
      expect(heldFor(memberA, v).hasError, isFalse);
      expect(heldFor(memberA, v, keepUnmarked: true).error, 'offline');
      expect(await failureOf(memberA, 'offline'), 'offline');
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
