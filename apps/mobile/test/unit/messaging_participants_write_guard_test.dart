import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MSG-G1 (RM-2, client side of C14-MIG-01) — the app never writes who is in
/// a conversation, nor moves a message to another sender or conversation.
///
/// C14-MIG-01 is SERVER-SIDE: the `conversations` / `messages` policies still
/// let a signed-in account rewrite `participant_1` / `participant_2`, or a
/// message's `sender_id` / `conversation_id`, with a direct PostgREST call.
/// THIS GUARD DOES NOT CLOSE THAT HOLE. It only keeps this app from becoming
/// a way to use it: a conversation is created ONLY through the
/// `get_or_create_conversation` RPC (which takes `participant_1` from
/// `auth.uid()`), the conversation preview update writes ONLY the
/// `last_message` fields, and no update to `messages` touches `sender_id` or
/// `conversation_id`.
///
/// Static, over `lib/`: these writes are spread across features, and a write
/// added anywhere must trip it. Each rule also has a self-test on a sample, so
/// the detector cannot silently stop matching.

/// Comment-free Dart source.
String _code(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

/// The text of the balanced `( … )` that opens at [open].
String _parens(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')' && --depth == 0) return s.substring(open, i + 1);
  }
  return s.substring(open);
}

/// Every write found on [table]: `(method, argument text)`. A write is the
/// first `.insert(` / `.update(` / `.upsert(` / `.delete(` chained on a
/// `.from('<table>')` before the statement ends.
List<(String, String)> _writesOn(String code, String table) {
  final out = <(String, String)>[];
  final from = RegExp("\\.from\\(\\s*'${RegExp.escape(table)}'\\s*\\)");
  for (final m in from.allMatches(code)) {
    final end = code.indexOf(';', m.end);
    final chain = code.substring(m.end, end < 0 ? code.length : end);
    final w = RegExp(r'\.\s*(insert|update|upsert|delete)\s*\(').firstMatch(chain);
    if (w == null) continue;
    out.add((w.group(1)!, _parens(chain, w.end - 1)));
  }
  return out;
}

/// The quoted keys of a literal map argument; null when it is not one (a
/// payload passed by variable cannot be checked, so it is refused).
Set<String>? _literalKeys(String arg) {
  final inner = arg.substring(1, arg.length - 1).trim();
  if (!inner.startsWith('{')) return null;
  return RegExp(r"'([a-z_0-9]+)'\s*:")
      .allMatches(inner)
      .map((m) => m.group(1)!)
      .toSet();
}

/// What breaks the rules in [code] (one Dart file, comments in).
List<String> _violations(String path, String src) {
  final code = _code(src);
  final out = <String>[];
  // 1. participant_1 / participant_2 written as a map key anywhere.
  for (final m in RegExp(r"'(participant_[12])'\s*:").allMatches(code)) {
    out.add('$path: writes ${m.group(1)} (only get_or_create_conversation may)');
  }
  // 2. conversations: only the preview update, only the last_message fields.
  for (final (method, arg) in _writesOn(code, 'conversations')) {
    if (method != 'update') {
      out.add('$path: conversations.$method (create through the RPC only)');
      continue;
    }
    final keys = _literalKeys(arg);
    if (keys == null) {
      out.add('$path: conversations.update with a non-literal payload');
    } else if (!keys.every({'last_message', 'last_message_at'}.contains)) {
      out.add('$path: conversations.update writes ${keys.toList()..sort()}');
    }
  }
  // 3. messages: no update/upsert may set sender_id or conversation_id.
  for (final (method, arg) in _writesOn(code, 'messages')) {
    if (method == 'upsert') {
      out.add('$path: messages.upsert (can rewrite an existing message)');
    }
    if (method != 'update') continue;
    final keys = _literalKeys(arg);
    if (keys == null) {
      out.add('$path: messages.update with a non-literal payload');
    } else {
      for (final k in keys.intersection({'sender_id', 'conversation_id'})) {
        out.add('$path: messages.update writes $k');
      }
    }
  }
  return out;
}

void main() {
  late Map<String, String> sources;

  setUpAll(() {
    sources = {
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        f.path: f.readAsStringSync(),
    };
  });

  test('no Dart code under lib/ writes conversation membership or re-homes a '
      'message (the server-side hole C14-MIG-01 remains)', () {
    final found = [
      for (final e in sources.entries) ..._violations(e.key, e.value),
    ];
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('conversations are created through get_or_create_conversation only',
      () {
    final svc = sources.entries
        .firstWhere((e) => e.key.endsWith('messaging/data/messaging_service.dart'));
    expect(_code(svc.value), contains("'get_or_create_conversation'"),
        reason: 'the RPC is the one way a conversation is made');
    final creates = [
      for (final e in sources.entries)
        for (final (method, _) in _writesOn(_code(e.value), 'conversations'))
          if (method != 'update') '${e.key}: $method',
    ];
    expect(creates, isEmpty);
  });

  test('the preview update writes only last_message / last_message_at, and '
      'is the only conversations write', () {
    final writes = [
      for (final e in sources.entries)
        for (final w in _writesOn(_code(e.value), 'conversations'))
          (e.key, w),
    ];
    expect(writes, hasLength(1), reason: '$writes');
    final (path, (method, arg)) = writes.single;
    expect(path, endsWith('messaging/data/messaging_service.dart'));
    expect(method, 'update');
    expect(_literalKeys(arg), {'last_message', 'last_message_at'});
  });

  // ── Self-tests: the detector finds each shape it is meant to ─────────────

  group('detector self-test', () {
    List<String> on(String src) => _violations('sample.dart', src);

    test('a participant written in an insert or update', () {
      expect(on("x.from('conversations').insert({'participant_1': a, "
          "'participant_2': b});"), hasLength(3));
      expect(on("db.from('conversations').update({'participant_2': b})"
          ".eq('id', id);"), hasLength(2));
      expect(on("final row = {'participant_1': me};"), hasLength(1),
          reason: 'built by variable still names the column');
    });

    test('a conversations upsert/delete or a wider preview update', () {
      expect(on("db.from('conversations').upsert({'id': i});"), hasLength(1));
      expect(on("db.from('conversations').delete().eq('id', i);"),
          hasLength(1));
      expect(on("db.from('conversations').update({'last_message': m, "
          "'title': t}).eq('id', i);"), hasLength(1));
      expect(on("db.from('conversations').update(payload).eq('id', i);"),
          hasLength(1), reason: 'a payload by variable cannot be checked');
    });

    test('a message moved to another sender or conversation', () {
      expect(on("db.from('messages').update({'sender_id': u}).eq('id', i);"),
          hasLength(1));
      expect(on("db.from('messages')\n  .update({'conversation_id': c, "
          "'is_read': true})\n  .eq('id', i);"), hasLength(1));
      expect(on("db.from('messages').upsert(row);"), hasLength(1));
    });

    test('controls: what the app does today is allowed', () {
      expect(on("db.from('conversations').update({'last_message': m, "
          "'last_message_at': n}).eq('id', c).select('id');"), isEmpty);
      expect(on("db.from('messages').update({'is_read': true})"
          ".eq('conversation_id', c).neq('sender_id', u);"), isEmpty,
          reason: 'a filter on sender_id is not a write of it');
      expect(on("db.from('messages').insert(row);"), isEmpty,
          reason: 'a new message carries its own sender (the server checks)');
      expect(on("db.from('conversations').select('id, participant_1, "
          "participant_2').or('participant_1.eq.\$u');"), isEmpty);
      expect(on("// db.from('conversations').insert({'participant_1': a});"),
          isEmpty, reason: 'comments are not code');
    });
  });
}
