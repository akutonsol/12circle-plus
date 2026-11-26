import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/router/app_router.dart';
import 'package:circle_fitness/features/ai_coach/presentation/ai_coach_screen.dart';
import 'package:circle_fitness/features/dashboard/presentation/client_detail_screen.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:circle_fitness/features/home/presentation/home_screen.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/progress/presentation/progress_screen.dart';
import 'package:circle_fitness/features/workout/presentation/resume_workout_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_app.dart';

// P0-FL-59a (f) — representative containment, on the app's REAL screens under
// the real root, router and shell: what A had on screen is not in B's tree, nor
// on the signed-out device, and the app asks for nothing with A's ids again.
//
// HOW TO SEE IT FAIL: make AccountScope._follow return before its setState (one
// container for the life of the process, as at a82f993).

const _client = 'acc7c000-0000-4000-8000-00000000c11e';
final _server = AccountServer();
final _realtime = FakeRealtime();

/// One of the app's real screens with something of A's on it.
class _Case {
  const _Case(this.name, this.secrets, this.open, {this.role = 'client'});
  final String name;
  final String role;

  /// On screen before the switch; nowhere after it.
  final List<Finder> secrets;
  final Future<void> Function(WidgetTester t) open;
}

Future<void> _go(WidgetTester t, String path) async {
  appRouter(t).go(path);
  await settleApp(t, 20);
}

Finder _text(String s) => find.textContaining(s, skipOffstage: false);

final _cases = [
  _Case("a coach's client page with the client's PAR-Q", [
    _text('Clara'),
    find.byType(ClientDetailScreen, skipOffstage: false),
  ], (t) async {
    await _go(t, '/coach-dashboard');
    unawaited(Navigator.push(
        t.element(find.byType(CoachDashboardScreen)),
        MaterialPageRoute<void>(
            builder: (_) => const ClientDetailScreen(
                clientId: _client, clientName: 'Clara OfA', owner: acctA))));
    await settleApp(t, 20);
    await t.tap(find.text('PAR-Q'));
    await settleApp(t, 10);
    expect(_text('PAR-Q SCREENING'), findsWidgets, reason: 'premise');
    expect(_server.of('get_client_assessment', by: acctA), isNotEmpty);
  }, role: 'coach'),
  _Case('the coach dashboard roster', [_text('Clara')], (t) async {
    await _go(t, '/coach-dashboard');
  }, role: 'coach'),
  _Case("A's open Rate Your Coach dialog, with what A typed", [
    _text('Rate Your Coach'),
    _text('typed by A'),
  ], (t) async {
    await _go(t, '/home');
    showRateCoachDialogForTest(t.element(find.byType(HomeScreen)), _client);
    await settleApp(t);
    await t.enterText(find.byType(TextField).last, 'typed by A');
    await t.pump();
  }),
  _Case("A's AI coach conversation", [
    _text('my knee hurts'),
    find.byType(AICoachScreen, skipOffstage: false),
  ], (t) async {
    await _go(t, '/ai-coach');
    final chat = find.text('Conversation');
    if (chat.evaluate().isNotEmpty) await t.tap(chat.first);
    await settleApp(t);
  }),
  _Case("A's Resume workout banner", [
    _text('Alba Leg Day'),
    _text('Resume Workout?'),
  ], (t) async {
    await _go(t, '/home');
    expect(find.byType(ResumeWorkoutBanner), findsOneWidget);
  }),
  _Case("A's progress photos", [
    find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is NetworkImage &&
            (w.image as NetworkImage).url.contains(acctA),
        skipOffstage: false),
  ], (t) async {
    await _go(t, '/progress');
    expect(find.byType(ProgressScreen), findsOneWidget);
    await t.tap(find.text('Photos').first);
    await settleApp(t);
  }),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initAccountSupabase(_server, _realtime, MemoryStore());
  });

  setUp(() {
    passwordRecoveryNotifier.value = null;
    accountReadFailureNotifier.value = null;
    _server.reset();
    setFailureSink((_) {});
    addTearDown(resetFailureSink);
  });

  void seed(String role) {
    Map<String, Object?> profile(String id, String as, String first, String last) => {
          'id': id,
          'role': as,
          'onboarding_complete': true,
          'first_name': first,
          'last_name': last,
          'coaching_mode': 'coach_guided',
          'created_at': '2026-01-02T10:00:00Z',
        };
    _server.rows['user_profiles:$acctA'] = [
      profile(acctA, role, 'Alba', 'Aye'),
      profile(_client, 'client', 'Clara', 'OfA'),
    ];
    _server.rows['user_profiles:$acctB'] = [
      profile(acctB, role, 'Bruno', 'Bee')
    ];
    _server.rows['coach_client_relationships:$acctA'] = [
      if (role == 'coach')
        {
          'id': 'rel-1',
          'coach_id': acctA,
          'client_id': _client,
          'status': 'active',
        }
    ];
    _server.rows['get_client_assessment:$acctA'] = [
      {
        'client_id': _client,
        'has_assessment': true,
        'first_name': 'Clara',
        'last_name': 'OfA',
        'risk_level': 'high',
        'risk_score': 5,
        'risk_flags': 'heart_condition',
        'parq_answers': {'1': true, '2': false},
        'medical_conditions': 'Clara hypertension',
      }
    ];
    _server.rows['ai_conversations:$acctA'] = [
      {
        'id': 'c1',
        'user_id': acctA,
        'user_message': 'my knee hurts',
        'ai_response': 'rest it',
        'created_at': '2026-01-02T10:00:00Z',
      }
    ];
    _server.rows['workout_sessions:$acctA'] = [
      {
        'id': 's1',
        'user_id': acctA,
        'workout_id': 'w1',
        'workout_title': 'Alba Leg Day',
        'status': 'in_progress',
        'started_at': DateTime.now()
            .subtract(const Duration(minutes: 12))
            .toUtc()
            .toIso8601String(),
        'elapsed_seconds': 60,
      }
    ];
    _server.rows['progress_photo_logs:$acctA'] = [
      {
        'id': 'p1',
        'user_id': acctA,
        'photo_type': 'front',
        'storage_path': '$acctA/gallery/p1.jpg',
        'logged_at': '2026-01-02T10:00:00Z',
      }
    ];
  }

  /// Layout overflow and image-fetch noise from whole real screens under the
  /// test font and no network is not what these are on. Reset in the test body
  /// (flutter_test checks it at the end).
  Future<void> quietly(Future<void> Function() body) async {
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = '${d.exception}';
      if (s.contains('overflowed') || s.contains('NetworkImage')) return;
      onError!(d);
    };
    try {
      await body();
    } finally {
      FlutterError.onError = onError;
    }
  }

  Future<void> change(WidgetTester t, Future<void> Function() f) async {
    await t.runAsync(f);
    await settleApp(t, 24);
  }

  Future<void> mountAs(WidgetTester t, _Case c) async {
    seed(c.role);
    await mountApp(t, as: acctA, overrides: [
      clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
    ]);
    await c.open(t);
    for (final f in c.secrets) {
      expect(f, findsWidgets, reason: 'premise: on screen');
    }
  }

  for (final c in _cases) {
    for (final toB in [true, false]) {
      testWidgets(
          '${c.name}: ${toB ? 'A -> B' : 'remote sign-out'} leaves nothing of it',
          (t) => quietly(() async {
                try {
                  await mountAs(t, c);
                  // B's reads are still out, then all fail.
                  if (toB) _server.holdAll[acctB] = Completer<void>();
                  final before = _server.sent.length;

                  await change(
                      t, toB ? () => signInAs(acctB) : () => expire(_server));

                  void nothingOfA(String when) {
                    for (final f in c.secrets) {
                      expect(f, findsNothing, reason: when);
                    }
                    expect(_text('Alba'), findsNothing, reason: when);
                  }

                  nothingOfA(toB ? "B's reads pending" : 'signed out');
                  expect(
                      appPath(t),
                      !toB
                          ? '/login'
                          : c.role == 'coach'
                              ? '/coach-dashboard'
                              : '/home');
                  if (toB) {
                    _server.failAll.add(acctB);
                    _server.holdAll.remove(acctB)!.complete();
                    await settleApp(t, 24);
                    nothingOfA("B's reads failed");
                  }
                  final withA = _server.sent.skip(before).where((s) =>
                      s.name != 'token' &&
                      ('${s.url}${s.body}'.contains(acctA) ||
                          '${s.url}${s.body}'.contains(_client)));
                  expect(withA, isEmpty,
                      reason: "nothing asked for with A's ids");
                  expect(_realtime.joinedFor(acctA), isEmpty);
                } finally {
                  await unmountApp(t, _server);
                }
              }));
    }

    testWidgets(
        'control: ${c.name}: A\'s own session renewed keeps it',
        (t) => quietly(() async {
              try {
                await mountAs(t, c);
                await change(t, renewToken);
                for (final f in c.secrets) {
                  expect(f, findsWidgets);
                }
              } finally {
                await unmountApp(t, _server);
              }
            }));
  }
}
