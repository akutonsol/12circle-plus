import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/admin/domain/admin_metrics.dart';
import 'package:circle_fitness/features/admin/domain/admin_provider.dart';
import 'package:circle_fitness/features/admin/presentation/admin_ecosystem_screen.dart';
import 'package:circle_fitness/features/admin/presentation/admin_tokens.dart';

/// V5 §184 — P5 · Ecosystem. The page is a ListView, so the harness uses a tall surface
/// to build every section (§183.3) rather than relaxing the finders.
Future<void> _pump(WidgetTester t, List<Override> overrides) async {
  await t.binding.setSurfaceSize(const Size(500, 4000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: AdminEcosystemScreen()),
  ));
  // Several frames, not one. The capability providers are async, so on the first frame
  // `valueOrNull` is still null and a gated action renders its read-only state — which is
  // correct behaviour and a wrong moment to assert on.
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

final _denied = <Override>[
  adminCommunityOverviewProvider.overrideWith((_) async => null),
  adminEventsOverviewProvider.overrideWith((_) async => null),
  adminTrainingOverviewProvider.overrideWith((_) async => null),
  adminRevenueOverviewProvider.overrideWith((_) async => null),
  adminWearableConnectionsProvider.overrideWith((_) async => null),
  adminOpenReportsProvider.overrideWith((_) async => null),
  adminCanModerateProvider.overrideWith((_) async => false),
  adminCanCreateEventsProvider.overrideWith((_) async => false),
  // EVERY provider the screen reads is overridden, including the two added in §189. A
  // provider left unmocked does not fail the test — it makes a REAL network call to QA,
  // which is how the EC-04 job went from 2 minutes to a 25-minute cancellation.
  adminEventDirectoryProvider.overrideWith((_) async => null),
  adminCanUpdateEventsProvider.overrideWith((_) async => false),
];

/// One directory row, built from a map so the test exercises the same `fromRow` parser the
/// service uses rather than a hand-built object the parser never sees.
List<Override> _withEvents(List<Map<String, Object?>> rows, {bool canEdit = false}) => [
      adminEventDirectoryProvider.overrideWith(
          (_) async => [for (final r in rows) AdminEventRow.fromRow(r)]),
      adminCanUpdateEventsProvider.overrideWith((_) async => canEdit),
    ];

String _allText(WidgetTester t) =>
    t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').join(' | ');

void main() {
  testWidgets('the six published sections are present, in the published order', (t) async {
    await _pump(t, _denied);
    final text = _allText(t);
    for (final s in ['OVERVIEW', 'COMMUNITY', 'MODERATION QUEUE', 'EVENTS', 'TRAINING',
                     'MONETIZATION', 'WEARABLES']) {
      expect(text.contains(s), isTrue, reason: 'missing section $s in: $text');
    }
  });

  testWidgets('an operator with no capability is told so per area, and sees no figure',
      (t) async {
    await _pump(t, _denied);
    expect(find.text('Not available to your role'), findsWidgets);
    final text = _allText(t);
    expect(RegExp(r'\b\d').hasMatch(text), isFalse, reason: text);
  });

  testWidgets('pods and groups are reported separately — METRIC-13 keeps them distinct',
      (t) async {
    await _pump(t, [
      ..._denied,
      adminCommunityOverviewProvider.overrideWith((_) async =>
          AdminCommunityOverview.fromRow(const {
            'pods_total': 7,
            'pods_active': 5,
            'community_groups_total': 3,
            'posts_total': 120,
            'posts_visible': 118,
            'reports_open': 0,
          })),
    ]);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('7'), findsWidgets);
    expect(find.text('3'), findsWidgets);
    // The moderation queue's zero uses the design's own wording.
    expect(find.text('none open'), findsOneWidget);
  });

  testWidgets('attendance with nothing to divide renders an A11 state, never 0%',
      (t) async {
    await _pump(t, [
      ..._denied,
      adminEventsOverviewProvider.overrideWith((_) async =>
          AdminEventsOverview.fromRow(const {
            'events_total': 3,
            'event_registrations_total': 0,
            'event_registrations_attended': 0,
            'event_attendance_rate_pct': null,
            'event_registrations_30d': 0,
          })),
    ]);
    expect(find.text('Attendance rate'), findsOneWidget);
    expect(find.text('Not recorded'), findsWidgets);
    expect(find.text('0.0%'), findsNothing);
  });

  testWidgets('training shows counts and states that NO completion rate is derived',
      (t) async {
    await _pump(t, [
      ..._denied,
      adminTrainingOverviewProvider.overrideWith((_) async =>
          AdminTrainingOverview.fromRow(const {
            'programs_total': 12,
            'workouts_total': 90,
            'sessions_total': 9,
            'logs_total': 4,
          })),
    ]);
    expect(find.text('12'), findsWidgets);
    expect(find.textContaining('No completion rate is derived'), findsOneWidget);
    // No invented percentage anywhere in the training card.
    expect(find.textContaining(RegExp(r'\d+(\.\d+)?% *completion')), findsNothing);
  });

  group('wearables · the connection half only', () {
    testWidgets('connections are counted per provider and the total agrees', (t) async {
      await _pump(t, [
        ..._denied,
        adminWearableConnectionsProvider.overrideWith((_) async =>
            AdminWearableConnections.fromRows(const [
              {'provider': 'whoop', 'connected': true},
              {'provider': 'whoop', 'connected': true},
              {'provider': 'garmin', 'connected': true},
              {'provider': 'strava', 'connected': false},
            ])),
      ]);
      expect(find.text('whoop'), findsOneWidget);
      expect(find.text('garmin'), findsOneWidget);
      // A disconnected row is not a connection.
      expect(find.text('strava'), findsNothing);
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('an unrecognised provider is still counted — provider has no CHECK, so '
        'dropping it would understate connections', (t) async {
      final m = AdminWearableConnections.fromRows(const [
        {'provider': null, 'connected': true},
        {'provider': 'whoop', 'connected': true},
      ]);
      expect(m.connectedTotal, 2);
      expect(m.byProvider['unrecognised'], 1);
    });

    testWidgets('the card STATES that sync health is absent by ruling, so the gap is not '
        'read as an oversight', (t) async {
      await _pump(t, [
        ..._denied,
        adminWearableConnectionsProvider
            .overrideWith((_) async => AdminWearableConnections.fromRows(const [])),
      ]);
      expect(find.textContaining('wait on PD-G01'), findsOneWidget);
      // THE PROPERTY IS THAT NO HEALTH FIGURE IS SHOWN — not that the words never
      // appear. A substring sweep for 'latency' fired on the very footnote that says
      // latency is absent, which is the assertion being wrong rather than the card. So
      // this checks for a LABELLED READING instead: a tile label is an exact string, and
      // an ingestion-health tile would have to carry one.
      for (final label in ['Latency', 'Sync status', 'Last sync', 'Ingestion errors',
                           'Sync health']) {
        expect(find.text(label), findsNothing,
            reason: 'no "$label" reading may be shown while WI-13 waits on PD-G01');
      }
    });
  });

  group('the Create event action · gated, and descriptive fields only', () {
    List<Override> events({required bool canCreate}) => [
          ..._denied,
          adminCanCreateEventsProvider.overrideWith((_) async => canCreate),
          adminEventsOverviewProvider.overrideWith((_) async =>
              AdminEventsOverview.fromRow(const {
                'events_total': 3,
                'event_registrations_total': 4,
                'event_registrations_attended': 1,
                'event_attendance_rate_pct': 25,
                'event_registrations_30d': 2,
              })),
        ];

    testWidgets('a role WITHOUT Events·create gets no action and is told why', (t) async {
      await _pump(t, events(canCreate: false));
      expect(find.text('Create event'), findsNothing);
      expect(find.textContaining('requires Events · create'), findsOneWidget);
    });

    testWidgets('a role WITH Events·create gets the action', (t) async {
      await _pump(t, events(canCreate: true));
      expect(find.text('Create event'), findsOneWidget);
    });

    testWidgets('the form offers DESCRIPTIVE fields only, and says what an Admin may not '
        'set — 165 accepts no price, status or vendor, so no field pretends otherwise',
        (t) async {
      await _pump(t, events(canCreate: true));
      await t.tap(find.text('Create event'));
      await t.pumpAndSettle();
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Capacity'), findsOneWidget);
      // None of these may be set by an Admin, so none is offered.
      for (final forbidden in ['Price', 'Free', 'Status', 'Publish', 'Vendor']) {
        expect(find.text(forbidden), findsNothing,
            reason: 'the governed path accepts no "$forbidden" — offering it would imply '
                'an authority that does not exist');
      }
      expect(find.textContaining('are not set here'), findsOneWidget);
    });

    testWidgets('a submission missing the title or date is refused with a message, not '
        'sent half-formed', (t) async {
      await _pump(t, events(canCreate: true));
      await t.tap(find.text('Create event'));
      await t.pumpAndSettle();
      await t.tap(find.text('Create'));
      await t.pumpAndSettle();
      expect(find.textContaining('needs a title and a date'), findsOneWidget);
      expect(find.textContaining('Nothing was created'), findsOneWidget);
    });

    testWidgets('the action meets the 44px touch target', (t) async {
      await _pump(t, events(canCreate: true));
      final box = t.getSize(find
          .ancestor(of: find.text('Create event'), matching: find.byType(SizedBox))
          .first);
      expect(box.height, AdminDims.sizeControl);
    });
  });

  group('the moderation queue · destructive actions, gated and confirmed', () {
    List<Override> withReport({required bool canModerate}) => [
          ..._denied,
          adminCanModerateProvider.overrideWith((_) async => canModerate),
          adminOpenReportsProvider.overrideWith((_) async => [
                AdminContentReport.fromRow(const {
                  'id': 'r1',
                  'target_type': 'post',
                  'target_id': 'p1',
                  'reason': 'this is harassment',
                  'created_at': '2026-10-07T03:00:00Z',
                }),
              ]),
        ];

    testWidgets('an empty queue uses the design\'s own zero wording', (t) async {
      await _pump(t, [
        ..._denied,
        adminOpenReportsProvider
            .overrideWith((_) async => const <AdminContentReport>[]),
      ]);
      expect(find.text('none open'), findsWidgets);
    });

    testWidgets('a role WITHOUT Community·update gets no action and is told why',
        (t) async {
      await _pump(t, withReport(canModerate: false));
      expect(find.text('Hide'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
      expect(find.textContaining('requires Community · update'), findsOneWidget);
    });

    testWidgets('a role WITH Community·update gets both actions', (t) async {
      await _pump(t, withReport(canModerate: true));
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets('the REPORTER is never named, and the reported text is not reproduced',
        (t) async {
      await _pump(t, withReport(canModerate: true));
      // The reporter's own words appear; the reporter does not, and neither does the post.
      expect(find.text('this is harassment'), findsOneWidget);
      final text = _allText(t);
      expect(RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}').hasMatch(text), isFalse,
          reason: 'no identifier may appear in the queue: $text');
      expect(find.textContaining('The reported text is not reproduced'), findsOneWidget);
    });

    testWidgets('no reason-code enum is offered — the list is owner vocabulary and is '
        'deferred', (t) async {
      await _pump(t, withReport(canModerate: true));
      expect(find.byType(DropdownButton<String>), findsNothing);
      final text = _allText(t);
      for (final invented in ['Spam', 'Harassment', 'Misinformation', 'Off-topic']) {
        expect(text.contains(invented), isFalse,
            reason: 'no invented reason code may appear: $invented');
      }
    });

    testWidgets('HIDE confirms destructively and says the text is NOT altered — 170 never '
        'writes content', (t) async {
      await _pump(t, withReport(canModerate: true));
      await t.tap(find.text('Hide'));
      await t.pumpAndSettle();
      expect(find.text('Hide this content?'), findsOneWidget);
      expect(find.textContaining('not altered or deleted'), findsOneWidget);
      expect(find.textContaining('audited'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('Hide this content?'), findsNothing);
    });

    testWidgets('DISMISS says the content is left exactly as it is, so the two actions '
        'cannot be confused', (t) async {
      await _pump(t, withReport(canModerate: true));
      await t.tap(find.text('Dismiss'));
      await t.pumpAndSettle();
      expect(find.text('Dismiss this report?'), findsOneWidget);
      expect(find.textContaining('left exactly as it is'), findsOneWidget);
    });

    testWidgets('each action meets the 44px touch target', (t) async {
      await _pump(t, withReport(canModerate: true));
      final box = t.getSize(find
          .ancestor(of: find.text('Hide'), matching: find.byType(SizedBox))
          .first);
      expect(box.height, AdminDims.sizeControl);
    });
  });

  testWidgets('monetization shows the recorded split and never derives it', (t) async {
    await _pump(t, [
      ..._denied,
      adminRevenueOverviewProvider.overrideWith((_) async =>
          AdminRevenueOverview.fromRow(const {
            'gross_coaching_cents': 13000,
            'platform_commission_cents': 500,
            'net_platform_cents': 12500,
            'source_currency': 'usd',
            'commission_rate_missing': 2,
            'coach_payout_cents': 0,
            'platform_fee_cents': 0,
            'payout_missing': 3,
          })),
    ]);
    expect(find.text('USD 130.00'), findsOneWidget);
    expect(find.text('Paid to coaches'), findsOneWidget);
    expect(find.text('USD 0.00'), findsWidgets);
    expect(find.text('Payments with no recorded split'), findsOneWidget);
    expect(find.text('Payments with no recorded rate'), findsOneWidget);
  });

  // ── §189 · the Events directory and its Edit action ──────────────────────
  testWidgets('a role without Events·view is told so — an empty directory is NEVER used '
      'to mean "not authorized"', (t) async {
    await _pump(t, _denied);
    // The card renders, and its body is the denial rather than the design's empty wording.
    expect(find.text('EVENTS DIRECTORY'), findsOneWidget);
    expect(_allText(t).contains('No events in this range.'), isFalse);
  });

  testWidgets('authorized with nothing to show uses the approved empty wording, which is '
      'only reachable AFTER the capability was confirmed', (t) async {
    await _pump(t, [..._denied, ..._withEvents(const [])]);
    expect(find.text('No events in this range.'), findsOneWidget);
  });

  testWidgets('a role with Events·view but not Events·update sees the rows and no Edit '
      'action, and is told which capability is missing', (t) async {
    await _pump(t, [
      ..._denied,
      ..._withEvents(const [
        {'id': 'e1', 'title': 'Autumn workshop', 'location': 'Studio 2',
         'event_date': '2027-03-01T10:00:00Z', 'max_capacity': 120,
         'current_registered': 88, 'status': 'upcoming'},
      ]),
    ]);
    expect(find.text('Autumn workshop'), findsOneWidget);
    expect(find.text('Edit event'), findsNothing);
    expect(_allText(t).contains('requires Events · update'), isTrue);
  });

  testWidgets('Events·update turns the action on', (t) async {
    await _pump(t, [
      ..._denied,
      ..._withEvents(const [
        {'id': 'e1', 'title': 'Autumn workshop', 'location': 'Studio 2',
         'event_date': '2027-03-01T10:00:00Z', 'max_capacity': 120,
         'current_registered': 88, 'status': 'upcoming'},
      ], canEdit: true),
    ]);
    expect(find.text('Edit event'), findsOneWidget);
    expect(_allText(t).contains('requires Events · update'), isFalse);
  });

  testWidgets('an unrecorded field is NAMED, never filled with a plausible blank — and a '
      'registration count without a capacity does not become an occupancy', (t) async {
    await _pump(t, [
      ..._denied,
      ..._withEvents(const [
        {'id': 'e2', 'title': 'Desk mobility', 'location': null,
         'event_date': null, 'max_capacity': null, 'current_registered': 0,
         'status': null},
      ]),
    ]);
    final text = _allText(t);
    for (final phrase in ['No date recorded', 'No location recorded',
                          'No status recorded', 'no capacity recorded']) {
      expect(text.contains(phrase), isTrue, reason: 'missing "$phrase" in: $text');
    }
    // 0 registered with no capacity must not render as an occupancy percentage.
    expect(RegExp(r'\d+\s*/\s*\d+').hasMatch(text), isFalse, reason: text);
    expect(AdminEventRow.fromRow(const {'current_registered': 0}).occupancy, isNull);
  });

  testWidgets('the directory states what is NOT editable and what it does not read, so '
      'the gaps are not read as missing fields', (t) async {
    await _pump(t, [
      ..._denied,
      ..._withEvents(const [
        {'id': 'e1', 'title': 'Autumn workshop', 'status': 'upcoming'},
      ], canEdit: true),
    ]);
    final text = _allText(t);
    expect(text.contains('Status is shown as recorded'), isTrue, reason: text);
    expect(text.contains('event type has no column at all'), isTrue, reason: text);
    expect(text.contains('Finance viewer role'), isTrue, reason: text);
  });

  // ── §189 · a pending capability check must not hide authorized data ───────
  //
  // THE DEFECT THESE TWO TESTS PIN. `adminCapabilityGate` renders an honest "Checking your
  // permissions…" while a check is in flight. Wrapped around a LIST, that sentence replaces
  // every row — so a pending answer about `·update` blanked records `·view` had already
  // authorized. The events directory shipped with it in §189 and the moderation queue had
  // carried it since §188. Each test keeps its capability permanently pending, which is
  // exactly the state the defect lived in.
  Future<void> pending(WidgetTester t, List<Override> o) async {
    await t.binding.setSurfaceSize(const Size(500, 4000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: o, child: const MaterialApp(home: AdminEcosystemScreen())));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('events · a pending Events·update check leaves the rows visible, offers no '
      'action, and claims no denial', (t) async {
    await pending(t, [
      ..._denied,
      adminEventDirectoryProvider.overrideWith((_) async => [
            AdminEventRow.fromRow(const {
              'id': 'e1', 'title': 'Autumn workshop', 'status': 'upcoming'}),
          ]),
      adminCanUpdateEventsProvider.overrideWith((_) => Completer<bool>().future),
    ]);
    expect(find.text('Autumn workshop'), findsOneWidget);
    expect(find.text('Edit event'), findsNothing);
    final text = _allText(t);
    expect(text.contains('requires Events · update'), isFalse, reason: text);
    expect(text.contains('Checking your permissions'), isFalse, reason: text);
  });

  testWidgets('moderation · a pending Community·update check leaves the queue and its '
      'count visible — the rows are read under Community·view', (t) async {
    await pending(t, [
      ..._denied,
      adminOpenReportsProvider.overrideWith((_) async => [
            AdminContentReport.fromRow(const {
              'id': 'r1', 'target_type': 'post', 'target_id': 'p1',
              'reason': 'QA probe reason'}),
          ]),
      adminCanModerateProvider.overrideWith((_) => Completer<bool>().future),
    ]);
    expect(find.text('Open reports'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    final text = _allText(t);
    expect(text.contains('requires Community · update'), isFalse, reason: text);
    expect(text.contains('Checking your permissions'), isFalse, reason: text);
  });

  // ── §199 · the Events search box, and the field it does NOT claim ─────────
  testWidgets('events · the search box states the ONE field it matches, because the '
      'approved placeholder does not name its fields the way People\'s does', (t) async {
    await _pump(t, [
      ..._denied,
      ..._withEvents(const [
        {'id': 'e1', 'title': 'Autumn workshop', 'status': 'upcoming'},
      ]),
    ]);
    final field = t
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((f) => f.decoration?.hintText == 'Search events');
    expect(field.controller?.text, isEmpty);
    final text = _allText(t);
    expect(text.contains('Searches the event title only'), isTrue, reason: text);
    // It must not imply it searched the other columns it renders.
    expect(text.contains('Location, host and status are not'), isTrue, reason: text);
  });

  testWidgets('events · an empty search result is worded differently from an empty range',
      (t) async {
    await _pump(t, [..._denied, ..._withEvents(const [])]);
    expect(find.text('No events in this range.'), findsOneWidget);
    expect(find.text('No event title matches that search'), findsNothing);
  });

  testWidgets('events · …and with a query active the zero says it is a non-match', (t) async {
    await _pump(t, [
      ..._denied,
      ..._withEvents(const []),
      adminEventSearchProvider.overrideWith((_) => 'zzz'),
    ]);
    expect(find.text('No event title matches that search'), findsOneWidget);
    expect(find.text('No events in this range.'), findsNothing);
  });
}
