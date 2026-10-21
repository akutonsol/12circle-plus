// QAX-COR-07 — replacing a baseline (front / side / back) progress photo.
//
// Extracted from ProgressScreen._setBaselinePhoto so the ordering is testable.
const baselinePhotoExtensions = ['jpg', 'jpeg', 'png', 'heic', 'webp'];

Future<void> replaceBaselinePhoto({
  required String uid,
  required String side,
  required String ext,
  required Future<void> Function(String path) upload,
  required Future<void> Function(List<String> paths) remove,
  void Function(Object error, StackTrace stack)? onCleanupError,
}) async {
  final target = '$uid/$side.$ext';
  // 1. Store the new photo first (upsert). If this throws, nothing has been
  //    deleted and the previous photo is intact.
  await upload(target);
  // 2. Only then clear copies under the OTHER extensions, so exactly one file
  //    remains for this side. A failed cleanup leaves a stale extra copy, not a
  //    lost photo: report it, but the replacement itself succeeded.
  final others = baselinePhotoExtensions
      .map((e) => '$uid/$side.$e')
      .where((p) => p != target)
      .toList();
  try {
    await remove(others);
  } catch (e, s) {
    onCleanupError?.call(e, s);
  }
}
