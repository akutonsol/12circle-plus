// ERR-1 / EC-01 + EC-23 — Workstream B Phase B0, the observability sink.
//
// Phase B0's gate, verbatim: "suites green; a deliberately-failed read appears
// in the sink." That is the first group below, and it is a BEHAVIOURAL
// assertion — it drives a read that throws, catches it the way a service does,
// and requires the failure to arrive at an installed sink with its origin and
// its unmodified error object intact.
//
// The second group is a SHRINKING SOURCE ALLOWLIST in the shape Workstream B
// established (EC-G1, EC-G5, EC-G6): EC-23's seven `print()` calls were the
// only diagnostics in `apps/mobile/lib`, and this guard fails the moment one
// comes back. It fails against the pre-fix tree by construction — there were
// seven matches before this change and there are none after.
//
// What is deliberately NOT asserted here: that all ~234 swallow sites report.
// Classifying them is Phase B4, and a guard that claimed it today would be
// claiming coverage the programme has not built.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/core/observability/app_failure.dart';

// ── Locating the tree ────────────────────────────────────────────────────────

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

String _withoutLineComments(String source) => source
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

List<File> _libDartFiles() => Directory('${_mobileRoot().path}/lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  group('EC-01 — a failure reaches the sink', () {
    final captured = <AppFailure>[];

    setUp(() {
      captured.clear();
      setFailureSink(captured.add);
    });

    tearDown(resetFailureSink);

    test('a deliberately-failed read appears in the sink', () async {
      // The shape every swallowing service in this tree has: a read that
      // throws, a catch, and an empty domain value returned to the caller.
      Future<List<String>> read() async =>
          throw StateError('PGRST205: relation "checkins" does not exist');

      List<String>? rows;
      try {
        rows = await read();
      } catch (e) {
        reportError('ExampleService.read', e);
        rows = <String>[];
      }

      // Behaviour is unchanged — the swallow still swallows...
      expect(rows, isEmpty);
      // ...and the operator can now see that it happened.
      expect(captured, hasLength(1));
      expect(captured.single.origin, 'ExampleService.read');
      expect(captured.single.error, isA<StateError>());
      expect(captured.single.toString(), contains('PGRST205'));
    });

    test('the error object is carried unmodified, not stringified early', () {
      final boom = ArgumentError('bad column');
      reportFailure(AppFailure(origin: 'X.y', error: boom));
      expect(identical(captured.single.error, boom), isTrue);
    });

    test('context is carried when the call site supplies it', () {
      reportError('ScoreEngine._award', 'rpc failed', null,
          <String, Object?>{'category': 'workouts', 'action': 'completed'});
      expect(captured.single.context, isNotNull);
      expect(captured.single.context!['category'], 'workouts');
      expect(captured.single.toString(), contains('category'));
    });

    test('reporting never throws, even when the sink itself is down', () {
      setFailureSink((AppFailure f) => throw StateError('sink is down'));
      // If this propagated, an observability call would become the outage it
      // exists to report.
      expect(() => reportError('X.y', 'boom'), returnsNormally);
    });

    test('resetFailureSink detaches the test sink', () {
      resetFailureSink();
      reportError('X.y', 'boom');
      expect(captured, isEmpty);
    });
  });

  group('EC-23 — print() is no longer the diagnostic layer', () {
    test('no print() call site remains in lib/', () {
      final offenders = <String>[];
      for (final f in _libDartFiles()) {
        final lines = _withoutLineComments(f.readAsStringSync()).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (RegExp(r'(^|[^\w.])print\s*\(').hasMatch(lines[i])) {
            offenders.add('${f.path.split('/lib/').last}:${i + 1}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'EC-23: print() was the only diagnostic in this tree and is '
            'replaced by reportFailure(). Seven call sites existed before '
            'Phase B0. Use reportError(origin, e) instead of reintroducing '
            'one: ${offenders.join(', ')}',
      );
    });

    test('the sanctioned swallows named by §5.1 report through the sink', () {
      final wired = <String, String>{
        'features/scoring/data/score_engine.dart': 'ScoreEngine._award',
        'features/checkins/data/checkin_service.dart':
            'CheckinService.saveDailyCheckin',
        'features/messaging/data/messaging_service.dart':
            'MessagingService.getConversations',
      };
      wired.forEach((relative, origin) {
        final source =
            File('${_mobileRoot().path}/lib/$relative').readAsStringSync();
        expect(source, contains("reportError('$origin'"),
            reason: '$relative must report $origin through the sink (rule O)');
      });
    });
  });
}
