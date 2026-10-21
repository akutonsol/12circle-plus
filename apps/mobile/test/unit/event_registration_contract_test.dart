// I-COM-01 / DAT-4 — the event registration handler may not fabricate success.
//
// `_EventTicketScreenState._register()` used to catch any failure from the
// `event_registrations` insert, invent a demo ticket code, and set
// `_registered = true`, so a failed write rendered the same `_TicketView` a
// real registration renders. `QA_CLOSURE_STANDARD.md` §9 invariant **I-1**
// names that shape exactly:
//
//     "No user-facing success state may be displayed unless authoritative
//      evidence confirms the underlying operation succeeded. … Not 'You're
//      registered' on a failed registration. … And never demo data presented
//      as the user's own."
//
// PD-B27 required the fabricating catch deleted "regardless of the answer".
//
// This is a NARROW guard, not a ratchet. It asserts three things about the
// failure path of ONE handler in ONE file; it counts nothing, and it does not
// constrain how the failure is surfaced — only that success is not invented.
// It reads committed source and contacts nothing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screen =
    'lib/features/classes/presentation/event_ticket_screen.dart';

/// The Flutter package root, located the way this repository's other source
/// guards locate it, so the guard does not depend on the caller's cwd.
Directory _mobileRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate the Flutter package root');
    }
    dir = parent;
  }
  return dir;
}

/// Source with `//` comments removed, the way this repository's other source
/// guards read a file. Without this the guard would trip over its own
/// documentation: the comment that records what was removed necessarily names
/// the prohibited pattern.
String _withoutLineComments(String source) => source
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

/// The body of `_register()`, from its signature to the closing brace of the
/// method, found by brace matching rather than by line number so the guard
/// survives ordinary edits above it.
String _registerBody(String source) {
  const sig = 'Future<void> _register() async {';
  final start = source.indexOf(sig);
  if (start < 0) {
    fail('$_screen no longer declares `$sig` — I-COM-01\'s handler was renamed '
        'or removed. Update this guard deliberately; do not delete it.');
  }
  var depth = 0;
  final open = source.indexOf('{', start);
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  fail('$_screen: could not brace-match the body of _register()');
}

/// Everything from the handler's `catch` to the end of the method — the
/// failure path.
String _failurePath(String body) {
  final c = body.indexOf('catch');
  if (c < 0) {
    // No catch at all is a legitimate way to satisfy I-1: the failure
    // propagates instead of being presented as success.
    return '';
  }
  return body.substring(c);
}

void main() {
  late final String source = _withoutLineComments(
      File('${_mobileRoot().path}/$_screen').readAsStringSync());

  group('I-COM-01 the registration handler cannot fabricate a ticket', () {
    test('the guard is reading the real handler', () {
      // A guard that silently parsed nothing would pass forever. The success
      // path is the positive anchor: it must still exist and must still be the
      // thing that sets the registered state.
      final body = _registerBody(source);
      expect(body.contains("from('event_registrations')"), isTrue,
          reason: 'the parsed body is not the registration handler');
      expect(body.contains('_registered = true'), isTrue,
          reason: 'the success path no longer marks the user registered — the '
              'guard would be asserting against the wrong method');
    });

    test('no demo ticket code is generated anywhere in the screen', () {
      expect(source.contains('TKT-DEMO'), isFalse,
          reason: 'a demo ticket code was reintroduced into $_screen. I-1: '
              'never demo data presented as the user\'s own.');
    });

    test('the failure path does not mark the user registered', () {
      expect(_failurePath(_registerBody(source)).contains('_registered = true'),
          isFalse,
          reason: 'the failure path of _register() sets _registered = true. '
              'I-1: no user-facing success state without authoritative '
              'evidence that the write succeeded.');
    });

    test('the failure path does not populate the ticket code', () {
      expect(_failurePath(_registerBody(source)).contains('_ticketCode ='),
          isFalse,
          reason: 'the failure path of _register() assigns a ticket code, so '
              'the ticket view can render after a failed registration.');
    });
  });
}
