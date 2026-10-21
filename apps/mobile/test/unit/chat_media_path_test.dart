// The chat-media storage contract (migration 130 / DEC-3A-10, Option C) as a
// pure value. These run without a Supabase client — ChatMediaPath is plain
// Dart on purpose — so the shape the storage policies authorize is pinned in
// the same terms the policies use: three folder segments, then a filename.
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/messaging/data/chat_media_path.dart';

void main() {
  const conv = '7d3f6e8a-1b2c-4d5e-8f90-123456789abc';
  const uid  = '3a1b2c3d-4e5f-4a6b-9c8d-0e1f2a3b4c5d';

  group('ChatMediaPath.build — canonical shape', () {
    test('messages/<conversation_id>/<uploader_uid>/<epoch>.<ext>', () {
      final p = ChatMediaPath.build(
          conversationId: conv, uploaderId: uid, epochMillis: 1757000000000, extension: 'jpg');
      expect(p, 'messages/$conv/$uid/1757000000000.jpg');
    });

    test('has exactly three folder segments — the depth the policies assert', () {
      final p = ChatMediaPath.build(
          conversationId: conv, uploaderId: uid, epochMillis: 1, extension: 'png');
      final folders = p.split('/')..removeLast();
      expect(folders.length, ChatMediaPath.folderDepth);
      expect(ChatMediaPath.folderDepth, 3);
    });

    test('segment [1] is the namespace, [2] the conversation, [3] the uploader', () {
      final p = ChatMediaPath.build(
          conversationId: conv, uploaderId: uid, epochMillis: 1, extension: 'jpg');
      final s = p.split('/');
      expect(s[0], ChatMediaPath.namespace);
      expect(s[0], 'messages');
      expect(s[1], conv, reason: 'the conversation is the authorization identity');
      expect(s[2], uid, reason: 'the uploader scopes mutation only');
    });

    test('the conversation id is never derived from the uploader id', () {
      final p = ChatMediaPath.build(
          conversationId: conv, uploaderId: uid, epochMillis: 1, extension: 'jpg');
      expect(p.split('/')[1], isNot(uid));
      expect(p.split('/')[1], isNot(contains(uid)));
    });

    test('is not the old two-segment messages/<uid>/<file> shape', () {
      final p = ChatMediaPath.build(
          conversationId: conv, uploaderId: uid, epochMillis: 1, extension: 'jpg');
      expect(p, isNot(startsWith('messages/$uid/')));
      expect(p.split('/').length, 4);
    });

    test('normalises the extension: lowercase, no leading dot', () {
      expect(ChatMediaPath.build(conversationId: conv, uploaderId: uid, epochMillis: 1, extension: '.JPG'),
          endsWith('/1.jpg'));
      expect(ChatMediaPath.build(conversationId: conv, uploaderId: uid, epochMillis: 1, extension: 'HEIC'),
          endsWith('/1.heic'));
    });

    test('two sends never collide — the epoch makes the path unique (no overwrite)', () {
      final a = ChatMediaPath.build(conversationId: conv, uploaderId: uid, epochMillis: 100, extension: 'jpg');
      final b = ChatMediaPath.build(conversationId: conv, uploaderId: uid, epochMillis: 101, extension: 'jpg');
      expect(a, isNot(b));
    });
  });

  group('ChatMediaPath.build — refuses a path the policies would refuse', () {
    test('empty conversation id', () {
      expect(() => ChatMediaPath.build(conversationId: '', uploaderId: uid, epochMillis: 1, extension: 'jpg'),
          throwsArgumentError);
    });
    test('empty uploader id', () {
      expect(() => ChatMediaPath.build(conversationId: conv, uploaderId: '', epochMillis: 1, extension: 'jpg'),
          throwsArgumentError);
    });

    // A "/" inside an id would add a folder segment, so the segments would no
    // longer mean what the parameters say. The policies deny that by depth;
    // the pure builder must refuse to emit it at all.
    test('conversation id containing "/" is rejected, not passed through', () {
      for (final bad in ['$conv/extra', '/$conv', '$conv/', 'a/b', '/']) {
        expect(() => ChatMediaPath.build(conversationId: bad, uploaderId: uid, epochMillis: 1, extension: 'jpg'),
            throwsArgumentError, reason: 'conversationId "$bad" must be refused');
      }
    });

    test('uploader id containing "/" is rejected, not passed through', () {
      for (final bad in ['$uid/extra', '/$uid', '$uid/', 'a/b', '/']) {
        expect(() => ChatMediaPath.build(conversationId: conv, uploaderId: bad, epochMillis: 1, extension: 'jpg'),
            throwsArgumentError, reason: 'uploaderId "$bad" must be refused');
      }
    });

    test('a delimiter-free id still builds exactly as before', () {
      expect(ChatMediaPath.build(conversationId: conv, uploaderId: uid, epochMillis: 42, extension: 'jpg'),
          'messages/$conv/$uid/42.jpg');
    });
    test('extension that would smuggle a path segment or a query', () {
      for (final bad in ['', 'jp/g', 'jpg?x=1', 'a b', '../jpg']) {
        expect(() => ChatMediaPath.build(conversationId: conv, uploaderId: uid, epochMillis: 1, extension: bad),
            throwsArgumentError, reason: 'extension "$bad" must be refused');
      }
    });
  });

  group('constants the client and the policies share', () {
    test('bucket is chat-media and stays private by contract', () {
      expect(ChatMediaPath.bucket, 'chat-media');
    });
    test('metadata carries a PATH under media_path, never a URL key', () {
      expect(ChatMediaPath.mediaPathKey, 'media_path');
      expect(ChatMediaPath.mediaPathKey, isNot(contains('url')));
      expect(ChatMediaPath.typeKey, 'type');
      expect(ChatMediaPath.imageType, 'image');
    });
  });
}
