// QAX-COR-07 — replacing a baseline progress photo must never lose the old one.
//
// Before the fix the old photo was deleted FIRST (every extension, failure
// swallowed) and the upload ran second, so a failed upload — network, size,
// MIME — left the user with no baseline photo at all. The bucket's owner
// UPDATE policy (migration 029) makes upload-with-upsert sufficient, so the
// fix uploads first and only then removes the other-extension copies.
import 'package:circle_fitness/features/progress/data/baseline_photo_replace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> calls;
  late List<List<String>> removed;

  Future<void> run({bool uploadFails = false, bool removeFails = false,
      List<Object>? cleanupErrors}) {
    return replaceBaselinePhoto(
      uid: 'u1', side: 'front', ext: 'png',
      upload: (p) async {
        calls.add('upload:$p');
        if (uploadFails) throw Exception('upload failed');
      },
      remove: (ps) async {
        calls.add('remove');
        removed.add(ps);
        if (removeFails) throw Exception('remove failed');
      },
      onCleanupError: (e, _) => cleanupErrors?.add(e),
    );
  }

  setUp(() {
    calls = [];
    removed = [];
  });

  test('a failed upload removes nothing — the old photo survives', () async {
    await expectLater(run(uploadFails: true), throwsA(isA<Exception>()));
    expect(removed, isEmpty, reason: 'nothing may be deleted before the new photo is stored');
  });

  test('upload happens before any removal', () async {
    await run();
    expect(calls.first, 'upload:u1/front.png');
  });

  test('cleanup removes only the OTHER extensions, never the new file', () async {
    await run();
    expect(removed, hasLength(1));
    expect(removed.single, isNot(contains('u1/front.png')));
    expect(removed.single.toSet(),
        {'u1/front.jpg', 'u1/front.jpeg', 'u1/front.heic', 'u1/front.webp'});
  });

  test('a failed cleanup is reported, not thrown — the new photo is stored', () async {
    final errors = <Object>[];
    await run(removeFails: true, cleanupErrors: errors);
    expect(calls.first, 'upload:u1/front.png');
    expect(errors, hasLength(1), reason: 'the stale copy must be visible to the sink');
  });
}
