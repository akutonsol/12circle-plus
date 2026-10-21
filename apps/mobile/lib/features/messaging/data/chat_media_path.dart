/// The chat-media storage contract, as one pure, testable value.
///
/// Migration 130 (DEC-3A-10, Option C) authorizes `chat-media` objects by the
/// path they are stored under:
///
///     messages/<conversation_id>/<uploader_uid>/<epoch>.<ext>
///
/// Segment `[2]` — the conversation — is the authorization identity: only a
/// participant of that conversation may read the object, and only a participant
/// may upload into it. Segment `[3]` — the uploader — scopes mutation: only that
/// user may delete the object, and nothing may overwrite it (there is no UPDATE
/// policy, so uploads must never upsert).
///
/// The bucket is PRIVATE. Nothing in the app may call `getPublicUrl()` on it;
/// display goes through `createSignedUrl()` at render time, and a message row
/// stores the object PATH (`metadata[mediaPathKey]`), never a URL.
///
/// Pure Dart on purpose: no Supabase import, so the contract is unit-testable
/// without a client and the guard that pins it can parse this file directly.
class ChatMediaPath {
  ChatMediaPath._();

  /// The private bucket. Spelled once.
  static const String bucket = 'chat-media';

  /// Namespace segment the storage policies assert as `[1]`.
  static const String namespace = 'messages';

  /// `messages.metadata` key carrying the storage object path of an image
  /// message. A path, never a URL — signed URLs expire and would bake a dead
  /// link (and a time-limited credential) into the row.
  static const String mediaPathKey = 'media_path';

  /// `messages.metadata` key naming the attachment kind.
  static const String typeKey = 'type';
  static const String imageType = 'image';

  /// Builds the canonical object path.
  ///
  /// Throws [ArgumentError] rather than producing a path the policies would
  /// refuse: an empty conversation or uploader id can only come from a caller
  /// that has lost its context, and uploading under it would fail at the
  /// storage boundary anyway — better to fail here, before bytes move.
  ///
  /// An id containing the path delimiter is refused for the same reason: it
  /// would change the segment count, so the policies would deny it (they
  /// assert exact depth), but a pure builder must not emit a path whose
  /// segments do not mean what its parameters say they mean.
  static String build({
    required String conversationId,
    required String uploaderId,
    required int epochMillis,
    required String extension,
  }) {
    if (conversationId.isEmpty) {
      throw ArgumentError.value(conversationId, 'conversationId', 'must not be empty');
    }
    if (conversationId.contains('/')) {
      throw ArgumentError.value(conversationId, 'conversationId', 'must not contain "/"');
    }
    if (uploaderId.isEmpty) {
      throw ArgumentError.value(uploaderId, 'uploaderId', 'must not be empty');
    }
    if (uploaderId.contains('/')) {
      throw ArgumentError.value(uploaderId, 'uploaderId', 'must not contain "/"');
    }
    final ext = extension.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    if (ext.isEmpty || !RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
      throw ArgumentError.value(extension, 'extension', 'must be alphanumeric');
    }
    return '$namespace/$conversationId/$uploaderId/$epochMillis.$ext';
  }

  /// Number of FOLDER segments the policies assert via
  /// `array_length(storage.foldername(name), 1) = 3`. The filename is not a
  /// folder segment.
  static const int folderDepth = 3;
}
