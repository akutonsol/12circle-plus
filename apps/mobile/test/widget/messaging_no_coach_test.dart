import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/messaging/domain/messaging_provider.dart';
import 'package:circle_fitness/features/messaging/presentation/messaging_screen.dart';

/// FIT-028 — "/messages · the state that sells the plan honestly".
///
/// The anchor asks for a *fourth* state on an otherwise three-state screen:
/// loading, failed, empty, and now "you have no coach, here is how to get one".
/// The interesting part is not that the pitch renders — it is that it renders
/// **only on proof**, because the two ways of getting it wrong are both
/// user-visible harms:
///
///  * showing "No coach yet · Browse coaches" to a member who already pays a
///    coach, because the coach lookup happened to fail (the error-to-empty
///    collapse recorded as F-15); and
///  * showing it to a coach who simply has no client messages yet.
///
/// So every assertion below is about a state that must NOT become the pitch.
/// The tests are written against the real widget tree with only the three data
/// providers overridden, so they fail if the branch is rewired — unlike the
/// simulated-logic tests `QA_CLOSURE_STANDARD` §4 warns about.
void main() {
  const pitch = 'No coach yet';
  const neutral = 'No conversations yet';

  Widget harness({
    required AsyncValue<List<Map<String, dynamic>>> convs,
    required AsyncValue<List<Map<String, dynamic>>> coaches,
    required AsyncValue<Map<String, dynamic>?> profile,
  }) {
    Override pin<T>(ProviderBase<AsyncValue<T>> p, AsyncValue<T> v) =>
        (p as FutureProvider<T>).overrideWith((ref) => v.when(
              data: (d) => d,
              error: (e, s) => Future<T>.error(e, s),
              loading: () => Completer<T>().future,
            ));

    return ProviderScope(
      overrides: [
        pin(conversationsProvider, convs),
        pin(myCoachesProvider, coaches),
        pin(currentUserProfileProvider, profile),
      ],
      child: const MaterialApp(home: MessagingScreen()),
    );
  }

  const member = AsyncData<Map<String, dynamic>?>({'role': 'client'});
  const noConversations = AsyncData<List<Map<String, dynamic>>>([]);

  testWidgets('FIT-028 a member with no coach is offered the marketplace',
      (t) async {
    await t.pumpWidget(harness(
      convs: noConversations,
      coaches: const AsyncData([]),
      profile: member,
    ));
    await t.pump();

    expect(find.text(pitch), findsOneWidget);
    expect(find.text(neutral), findsNothing);
    // `Browse coaches`, not `Find a coach`. FIT-028 declares BOTH and the
    // board draws them as different controls — a header compass
    // (`aria-label="Find a coach"`) and the primary button (`fc-btn2`,
    // `Browse coaches`). This screen had `Find a coach` on the primary and no
    // `Browse coaches` anywhere; see QA_EVIDENCE §3aq.
    expect(find.text('Browse coaches'), findsOneWidget);
    // And the header control the board also declares.
    expect(find.bySemanticsLabel('Find a coach'), findsOneWidget);
  });

  testWidgets('FIT-028 a FAILED coach lookup does not become "no coach"',
      (t) async {
    await t.pumpWidget(harness(
      convs: noConversations,
      coaches: AsyncError(Exception('offline'), StackTrace.empty),
      profile: member,
    ));
    await t.pump();

    // This is the assertion that matters: a paying member whose coach list
    // failed to load must not be told they have no coach and sold a plan.
    expect(find.text(pitch), findsNothing);
    expect(find.text(neutral), findsOneWidget);
  });

  testWidgets('FIT-028 a still-loading coach lookup does not become "no coach"',
      (t) async {
    await t.pumpWidget(harness(
      convs: noConversations,
      coaches: const AsyncLoading(),
      profile: member,
    ));
    await t.pump();

    expect(find.text(pitch), findsNothing);
    expect(find.text(neutral), findsOneWidget);
  });

  testWidgets('FIT-028 a member who HAS a coach sees the neutral empty state',
      (t) async {
    await t.pumpWidget(harness(
      convs: noConversations,
      coaches: const AsyncData([
        {'id': 'c1', 'first_name': 'Ada'}
      ]),
      profile: member,
    ));
    await t.pump();

    expect(find.text(pitch), findsNothing);
    expect(find.text(neutral), findsOneWidget);
  });

  testWidgets('FIT-028 a coach with no client messages is not sold a coach',
      (t) async {
    await t.pumpWidget(harness(
      convs: noConversations,
      coaches: const AsyncData([]),
      profile: const AsyncData<Map<String, dynamic>?>({'role': 'coach'}),
    ));
    await t.pump();

    expect(find.text(pitch), findsNothing);
    expect(find.text(neutral), findsOneWidget);
  });

  testWidgets('FIT-028 an unknown role is not sold a coach', (t) async {
    // Profile still loading, or absent. We do not know they are a member, so
    // we do not assert anything about their coach.
    await t.pumpWidget(harness(
      convs: noConversations,
      coaches: const AsyncData([]),
      profile: const AsyncLoading(),
    ));
    await t.pump();

    expect(find.text(pitch), findsNothing);
    expect(find.text(neutral), findsOneWidget);
  });

  testWidgets('FIT-028 a failed conversation load is still its own state',
      (t) async {
    // Pre-existing behaviour that FIT-028 must not have flattened: the screen
    // distinguishes "could not load" from "nothing here".
    await t.pumpWidget(harness(
      convs: AsyncError(Exception('offline'), StackTrace.empty),
      coaches: const AsyncData([]),
      profile: member,
    ));
    await t.pump();

    expect(find.text("Couldn't load messages"), findsOneWidget);
    expect(find.text(pitch), findsNothing);
    expect(find.text(neutral), findsNothing);
  });

  testWidgets('FIT-028 the marketplace CTA clears the 44dp target floor',
      (t) async {
    await t.pumpWidget(harness(
      convs: noConversations,
      coaches: const AsyncData([]),
      profile: member,
    ));
    await t.pump();

    final size = t.getSize(find.ancestor(
      of: find.text('Browse coaches'),
      matching: find.byType(Container),
    ).first);
    expect(size.height, greaterThanOrEqualTo(44.0));
    expect(size.width, greaterThanOrEqualTo(44.0));
  });

  testWidgets('FIT-005 a conversation row keeps its CONTENT as its name and '
      'takes the design\'s phrase as a hint', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(harness(
      convs: const AsyncData<List<Map<String, dynamic>>>([
        {
          'id': 'c1',
          'participant': {'first_name': 'Priya', 'last_name': 'N', 'role': 'coach'},
          'last_message': 'Hi there',
        }
      ]),
      coaches: const AsyncData([
        {'id': 'c1'}
      ]),
      profile: member,
    ));
    await t.pump();

    // The row announces WHO and WHAT — a client choosing between threads needs
    // that, and WCAG 2.5.3 requires the name to contain the visible label.
    final node = t.getSemantics(find.text('Priya N'));
    expect(node.label, contains('Priya N'));
    expect(node.label, contains('Hi there'));
    // FIT-005's "Open message" describes the ACTION, so it is the hint. Naming
    // the row with it would have replaced the content and scored a coverage
    // point at the client's expense.
    expect(node.hint, 'Open message');
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    handle.dispose();
  });
}
