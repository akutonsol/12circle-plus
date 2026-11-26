import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'two_member_postgrest.dart';

// P0-FL-59c · what the owner tests share: the real auth transitions, with and
// without a frame, over the two-member fakes.

GoTrueClient get _auth => Supabase.instance.client.auth;

Future<void> settleReal(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// [uid] signs in with NO frame drawn: what a hidden tab does.
Future<void> switchNoFrame(WidgetTester t, String uid) async {
  await t.runAsync(() => signInAs(uid));
  expect(_auth.currentUser?.id, uid, reason: 'premise');
}

Future<void> signOutNoFrame(WidgetTester t) async {
  await t.runAsync(signOut);
  expect(_auth.currentUser, isNull, reason: 'premise');
}

/// A profile edit by the member signed in: a REAL `userUpdated`, asserted to
/// have arrived, with a different `User` for the same uid.
Future<void> editUser(WidgetTester t) async {
  final before = _auth.currentUser!;
  final events = <AuthChangeEvent>[];
  final sub = _auth.onAuthStateChange.listen((s) => events.add(s.event));
  await t.runAsync(() async {
    await _auth.updateUser(UserAttributes(data: {'x': 1}));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  });
  await t.runAsync(sub.cancel);
  expect(events, contains(AuthChangeEvent.userUpdated), reason: 'premise');
  expect(_auth.currentUser?.id, before.id, reason: 'premise');
  expect(_auth.currentUser == before, isFalse, reason: 'premise');
}

/// A token refresh for the member signed in, asserted to have arrived.
Future<void> refreshToken(WidgetTester t) async {
  final events = <AuthChangeEvent>[];
  final sub = _auth.onAuthStateChange.listen((s) => events.add(s.event));
  await t.runAsync(() async {
    await refreshSession();
    await Future<void>.delayed(const Duration(milliseconds: 5));
  });
  await t.runAsync(sub.cancel);
  expect(events, contains(AuthChangeEvent.tokenRefreshed), reason: 'premise');
}

/// Ctrl+Z in the focused field. Run under `TargetPlatform.linux`.
Future<void> undo(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump(const Duration(seconds: 1));
}

void tallView(WidgetTester t) {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(900, 3200);
  addTearDown(t.view.reset);
}

/// Unmounts, and runs out SnackBar and scaffold timers.
Future<void> closeApp(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 7));
}

Finder liveRegion(String label) => find.byWidgetPredicate((w) =>
    w is Semantics &&
    (w.properties.liveRegion ?? false) &&
    (w.properties.label == null || w.properties.label!.contains(label)));
