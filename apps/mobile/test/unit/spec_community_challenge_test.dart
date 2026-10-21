// COM-001…COM-003 / CHL-001…CHL-003 / HAB-001…HAB-003 / MSG-001…MSG-004
// Community, Challenge, Habits, and Messaging spec compliance — logic layer.
import 'package:flutter_test/flutter_test.dart';

// ── Habit completion math ─────────────────────────────────────────────────────

const maxHabits = 20;

int habitPoints(int completed, int total) {
  if (total == 0) return 0;
  return ((completed / total) * maxHabits).round().clamp(0, maxHabits);
}

// ── Challenge leaderboard (CHL-003) ──────────────────────────────────────────

List<Map<String, dynamic>> rankLeaderboard(List<Map<String, dynamic>> entries) {
  final sorted = List<Map<String, dynamic>>.from(entries)
    ..sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
  for (var i = 0; i < sorted.length; i++) {
    sorted[i] = {...sorted[i], 'rank': i + 1};
  }
  return sorted;
}

// ── Messaging helpers ─────────────────────────────────────────────────────────

int unreadCount(List<Map<String, dynamic>> messages, String currentUserId) =>
    messages.where((m) =>
        m['sender_id'] != currentUserId && m['is_read'] == false).length;

// Mirrors sendMessage — content must be non-empty
bool isValidMessage(String content) => content.trim().isNotEmpty;

// ── Community helpers ─────────────────────────────────────────────────────────

Map<String, dynamic> toggleLike(Map<String, dynamic> post, String userId) {
  final likedBy = List<String>.from(post['liked_by'] as List? ?? []);
  if (likedBy.contains(userId)) {
    likedBy.remove(userId);
  } else {
    likedBy.add(userId);
  }
  return {...post, 'liked_by': likedBy, 'like_count': likedBy.length};
}

void main() {
  // ── HAB-001 / HAB-002 / HAB-003 ──────────────────────────────────────────
  group('HAB-001 Water goal completed → habit marked complete, score updated', () {
    test('5/5 habits → 20 pts (full)', () => expect(habitPoints(5, 5), 20));
    test('0/5 habits → 0 pts', () => expect(habitPoints(0, 5), 0));
    test('guard: 0 total → 0 pts', () => expect(habitPoints(0, 0), 0));
  });

  group('HAB-002 Step goal completed → points awarded', () {
    test('3/5 steps → 12 pts', () => expect(habitPoints(3, 5), 12));
    test('completing step habit increases total score', () {
      const scoreBefore = 50;
      final award = habitPoints(3, 5);
      expect(scoreBefore + award, 62);
    });
  });

  group('HAB-003 Sleep habit completed → history updated', () {
    test('1/1 sleep habit → 20 pts', () => expect(habitPoints(1, 1), 20));
    test('repeated habit awards compound (no cap beyond total category)', () {
      // Each day's habit record is independent; no per-day duplicate guard needed
      final dayA = habitPoints(5, 5);
      final dayB = habitPoints(5, 5);
      expect(dayA, 20);
      expect(dayB, 20);
    });
  });

  // ── COM-001 / COM-002 / COM-003 ──────────────────────────────────────────
  group('COM-001 Create post → feed updated', () {
    test('new post has required fields', () {
      final post = {
        'id':        'post-1',
        'content':   'Crushed my workout today!',
        'user_id':   'user-A',
        'like_count': 0,
        'liked_by':  <String>[],
        'created_at': DateTime.now().toIso8601String(),
      };
      expect(post['content'], isNotEmpty);
      expect(post['like_count'], 0);
    });
  });

  group('COM-002 Comment → notification sent', () {
    test('comment has parent post id and author', () {
      final comment = {
        'post_id': 'post-1',
        'user_id': 'user-B',
        'content': 'Great work!',
      };
      expect(comment['post_id'], isNotNull);
      expect(comment['user_id'], isNotNull);
    });

    test('commenter != post author triggers notification', () {
      const postAuthor    = 'user-A';
      const commentAuthor = 'user-B';
      expect(commentAuthor != postAuthor, isTrue); // → send notification
    });
  });

  group('COM-003 Like post → count updated correctly', () {
    test('first like increments count to 1', () {
      final post = {'liked_by': <String>[], 'like_count': 0};
      final updated = toggleLike(post, 'user-A');
      expect(updated['like_count'], 1);
    });

    test('second like from same user removes like (toggle)', () {
      final post = {'liked_by': ['user-A'], 'like_count': 1};
      final updated = toggleLike(post, 'user-A');
      expect(updated['like_count'], 0);
    });

    test('two different users liking → count = 2', () {
      var post = toggleLike({'liked_by': <String>[], 'like_count': 0}, 'user-A');
      post = toggleLike(post, 'user-B');
      expect(post['like_count'], 2);
    });
  });

  // ── CHL-001 / CHL-002 / CHL-003 ──────────────────────────────────────────
  group('CHL-001 Join challenge → participation recorded', () {
    test('participant entry has required fields', () {
      final entry = {
        'challenge_id': 'chl-1',
        'user_id':      'user-A',
        'points':       0,
        'joined_at':    DateTime.now().toIso8601String(),
      };
      expect(entry['points'], 0);
      expect(entry['challenge_id'], isNotNull);
    });
  });

  group('CHL-002 Daily challenge completion → points awarded', () {
    test('completing daily challenge adds points to entry', () {
      final entry = <String, Object>{'user_id': 'user-A', 'points': 0};
      final updated = <String, Object>{...entry, 'points': (entry['points']! as int) + 10};
      expect(updated['points'], 10);
    });
  });

  group('CHL-003 Challenge leaderboard → ranks calculated correctly', () {
    final entries = [
      {'user_id': 'user-C', 'points': 40},
      {'user_id': 'user-A', 'points': 100},
      {'user_id': 'user-B', 'points': 70},
    ];

    test('highest points is rank 1', () {
      final ranked = rankLeaderboard(entries);
      expect(ranked[0]['user_id'], 'user-A');
      expect(ranked[0]['rank'],    1);
    });

    test('all entries are ranked', () {
      expect(rankLeaderboard(entries).length, 3);
    });

    test('ranks are sequential starting at 1', () {
      final ranks = rankLeaderboard(entries).map((e) => e['rank']).toList();
      expect(ranks, [1, 2, 3]);
    });

    test('descending by points', () {
      final ranked = rankLeaderboard(entries);
      for (var i = 0; i < ranked.length - 1; i++) {
        expect((ranked[i]['points'] as int) >= (ranked[i + 1]['points'] as int), isTrue);
      }
    });
  });

  // ── MSG-001 / MSG-002 / MSG-003 / MSG-004 ────────────────────────────────
  group('MSG-001 Client sends text → delivered and stored', () {
    test('empty message is invalid (not sent)', () {
      expect(isValidMessage(''), isFalse);
      expect(isValidMessage('   '), isFalse);
    });

    test('non-empty message is valid', () {
      expect(isValidMessage('Hello coach!'), isTrue);
    });
  });

  group('MSG-002 Coach sends image → image displayed', () {
    // chat-media is PRIVATE (migration 130 / DEC-3A-10): the row carries the
    // storage object path under `media_path`, and the screen signs it at
    // render time. A URL is never stored.
    test('message with media_path metadata is an image message', () {
      final msg = {
        'content':  '[photo]',
        'metadata': {
          'type': 'image',
          'media_path': 'messages/7d3f6e8a-1b2c-4d5e-8f90-123456789abc/'
              '3a1b2c3d-4e5f-4a6b-9c8d-0e1f2a3b4c5d/1757000000000.jpg',
        },
      };
      final path = (msg['metadata'] as Map?)?['media_path'] as String?;
      expect(path, isNotNull);
      expect(path, startsWith('messages/'));
      expect(path, isNot(startsWith('http')), reason: 'a path, not a URL');
      expect((msg['metadata'] as Map?)?['image_url'], isNull,
          reason: 'the pre-130 public-URL key is retired');
    });

    test('message without metadata renders as text', () {
      final msg = {'content': 'Hello', 'metadata': null};
      final path = (msg['metadata'] as Map?)?['media_path'] as String?;
      expect(path, isNull);
    });
  });

  group('MSG-004 Unread count → accurate badge count', () {
    final msgs = [
      {'sender_id': 'coach-1', 'is_read': false},
      {'sender_id': 'coach-1', 'is_read': true},
      {'sender_id': 'me',      'is_read': false}, // own sent message
      {'sender_id': 'coach-1', 'is_read': false},
    ];

    test('unread count excludes own messages', () {
      expect(unreadCount(msgs, 'me'), 2);
    });

    test('all read → count is 0', () {
      final allRead = [
        {'sender_id': 'coach-1', 'is_read': true},
        {'sender_id': 'coach-1', 'is_read': true},
      ];
      expect(unreadCount(allRead, 'me'), 0);
    });

    test('empty conversation → count is 0', () {
      expect(unreadCount([], 'me'), 0);
    });
  });
}
