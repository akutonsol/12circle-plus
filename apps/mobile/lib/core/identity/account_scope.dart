import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../observability/app_failure.dart';
import '../observability/network_failure.dart';

// ── Who is signed in ────────────────────────────────────────────────────────

/// The account [session]'s access token was issued to: the one the server acts
/// for, whatever user the session carries. Null when the token cannot be read.
String? sessionSubject(Session session) {
  final parts = session.accessToken.split('.');
  if (parts.length != 3) return null;
  try {
    final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final sub = claims is Map ? claims['sub'] : null;
    return sub is String && sub.isNotEmpty ? sub : null;
  } on FormatException {
    return null;
  }
}

/// [session] carries one account's user on another's token. gotrue makes one
/// when `updateUser` answers after the account has changed: it copies the user
/// it was answered onto whatever session is current by then, and tells every
/// listener (and every other web tab). It says nothing about who is signed in.
bool isMixedSession(Session? session) {
  if (session == null) return false;
  final subject = sessionSubject(session);
  return subject != null && subject != session.user.id;
}

/// The uid signed in now, or null: the one requests are made as, also while the
/// session is a mixed one ([isMixedSession]).
String? signedInUid() {
  final session = Supabase.instance.client.auth.currentSession;
  return session == null ? null : sessionSubject(session) ?? session.user.id;
}

/// Ends a mixed session ([isMixedSession]): puts the user its token was issued
/// to back on it, as in [own] (the last session heard of with that user),
/// synchronously and with no network, so nothing else runs under the wrong name
/// and no account that arrives, or leaves, meanwhile is undone. Records failures.
///
/// In every other tab too (recoverSession tells them), unless another one told
/// this ([fromBroadcast]): such a message may be an old one, read by a tab that
/// was suspended, and telling the others again would put its account back over
/// the sign-out, or the next account, that they know of and this tab has yet to
/// hear. An expired token is left to gotrue, which renews it at its next tick or
/// request: asked for here, the answer would bring back an account that left
/// meanwhile.
///
/// Without [own] the server is asked: nothing here knows that user. That is a
/// mixed session an earlier run stored, at launch. Never for a broadcast.
Future<void> putBackOwnUser(Session? own, {bool fromBroadcast = false}) async {
  final auth = Supabase.instance.client.auth;
  final mixed = auth.currentSession;
  if (mixed == null || !isMixedSession(mixed)) return;
  try {
    if (own != null && sessionSubject(mixed) == own.user.id) {
      final json = jsonEncode(mixed.copyWith(user: own.user).toJson());
      // For an expired token recoverSession would first ask for a new one.
      if (fromBroadcast || mixed.isExpired) {
        await auth.setInitialSession(json);
      } else {
        await auth.recoverSession(json);
      }
    } else if (!fromBroadcast) {
      await auth.refreshSession();
    }
  } catch (e, st) {
    reportError('putBackOwnUser', e, st);
  }
}

/// Runs [signOut] and says whether this device is signed out: null when it is,
/// else the error that left the account's session on it. Records every failure,
/// never throws.
///
/// gotrue forgets the session in memory, then removes its stored PKCE code, and
/// only then tells anyone (which removes the stored session) and the server. A
/// refusal by the SERVER is therefore after the fact: the device is signed out.
/// But when that removal throws, nobody is told, and the stored session signs
/// the account back in at the next start. That is tried once more, unless an
/// account has arrived by then.
///
/// One that arrives DURING the second try cannot be kept out of it: gotrue
/// 2.21.0's `signOut` awaits the removal between forgetting the session and
/// announcing the sign-out, and takes no condition. The announcement then
/// carries the arrived session, so nobody signs it out and it is stored; but
/// realtime goes back to the anon key. So that session is announced once more.
Future<Object?> signOutOfDevice(
    String origin, Future<void> Function() signOut) async {
  final auth = Supabase.instance.client.auth;
  final uid = signedInUid();
  var told = false;
  final events = auth.onAuthStateChange.listen((state) {
    if (state.session == null) told = true;
  }, onError: (Object _, StackTrace __) {});
  try {
    await signOut();
    return null;
  } catch (e, st) {
    reportError(origin, e, st);
    if (told) return null;
    if (auth.currentSession != null) return signedInUid() == uid ? e : null;
    try {
      await auth.signOut(); // no token left: nothing is sent
      final arrived = auth.currentSession;
      if (arrived != null) {
        await auth.setInitialSession(jsonEncode(arrived.toJson()));
      }
      return null;
    } catch (e, st) {
      reportError(origin, e, st);
      // Not to be said to an account that has arrived meanwhile.
      return auth.currentSession == null ? e : null;
    }
  } finally {
    unawaited(events.cancel());
  }
}

/// What to say when [signOutOfDevice] answers [error].
String signOutFailedText(Object error) => isNetworkFailure(error)
    ? "Couldn't sign you out — check your connection and try again."
    : "Couldn't sign you out — try again in a moment. If it keeps happening, contact support.";

/// One line for the account an account change lands on, shown once by the
/// generation that begins with [uid] (null: signed out). It names nobody.
final accountNoticeNotifier =
    ValueNotifier<({String? uid, String text})?>(null);

// ── The scope ───────────────────────────────────────────────────────────────

/// Which account generation a provider container belongs to.
@immutable
class AccountGeneration {
  const AccountGeneration({this.number = 0, this.startedAs});

  /// 0 for the one the app launched with.
  final int number;

  /// The uid signed in when a LATER generation began. Null for the first, and
  /// for one that began signed out.
  final String? startedAs;

  bool get isFirst => number == 0;
}

/// The generation this container belongs to. [AccountScope] sets it.
final accountGenerationProvider =
    Provider<AccountGeneration>((_) => const AccountGeneration());

/// The app's state belongs to one account (P0-FL-59a, A-28).
///
/// Holds ONE provider container — and with it one router, one navigator stack,
/// one set of dialogs, timers and channels — per account generation. When the
/// account that owned a generation leaves (another account arrives, the session
/// ends, or the member signs out) the whole of it is unmounted and disposed and
/// a new one begins. A screen, a provider's held value or a root dialog of the
/// old account is therefore never shown to the next one.
///
/// * A generation with no owner takes the first account that signs in, without
///   remounting: sign-in, sign-up, intake, invites and OAuth keep their state.
/// * A mixed session ([isMixedSession]) is nobody's arrival: it is put right.
/// * The same uid (token refresh, profile edit, MFA, its own recovery) never
///   remounts. Neither does a failed token refresh that ends no session: gotrue
///   reports that as an error, not a sign-out.
///
/// It does NOT stop a request already sent, and it needs a frame: a hidden web
/// tab draws none until it is shown. Writes keep their own owner checks.
class AccountScope extends StatefulWidget {
  const AccountScope({
    super.key,
    required this.child,
    this.onLaunch,
    this.onOwnerLeft,
    this.overrides = const [],
  });

  final Widget child;

  /// Called once, when the app starts, for what an earlier run left on the
  /// device.
  final FutureOr<void> Function()? onLaunch;

  /// Called with the uid that left, as soon as it has (before any frame): for
  /// what the account put on the DEVICE, which no widget owns.
  final FutureOr<void> Function(String uid)? onOwnerLeft;

  /// Applied to every generation's container.
  final List<Override> overrides;

  @override
  State<AccountScope> createState() => _AccountScopeState();
}

class _AccountScopeState extends State<AccountScope> {
  late ProviderContainer _container;
  late final StreamSubscription<AuthState> _auth;
  final _retired = <ProviderContainer>[];
  String? _owner;

  /// The last one heard of (never a mixed one).
  Session? _session;
  int _number = 0;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _owner = auth.currentUser?.id;
    _container = _newContainer(const AccountGeneration());
    // Subscribed before any provider is, so it hears each change first.
    // By the EVENT's uid, not currentUser: for a rapid A -> B -> A both events
    // can be delivered after the second, when currentUser is A again.
    _auth = auth.onAuthStateChange.listen(
      (state) {
        if (isMixedSession(state.session)) {
          putBackOwnUser(_session, fromBroadcast: state.fromBroadcast);
          return;
        }
        _session = state.session;
        _follow(state.session?.user.id);
      },
      // A failed refresh ends no session; gotrue has logged it.
      onError: (Object _, StackTrace __) {},
    );
    _run('AccountScope.onLaunch', () => widget.onLaunch?.call());
  }

  ProviderContainer _newContainer(AccountGeneration generation) =>
      ProviderContainer(overrides: [
        accountGenerationProvider.overrideWithValue(generation),
        ...widget.overrides,
      ]);

  void _follow(String? uid) {
    final left = _owner;
    if (uid == left) return;
    _owner = uid;
    if (left == null) return; // the ownerless generation is now this account's
    setState(() {
      _retired.add(_container);
      _container =
          _newContainer(AccountGeneration(number: ++_number, startedAs: uid));
    });
    // After the frame that unmounts the old tree, never before: its widgets
    // still read from it until then.
    WidgetsBinding.instance.addPostFrameCallback((_) => _disposeRetired());
    _run('AccountScope.onOwnerLeft', () => widget.onOwnerLeft?.call(left));
  }

  Future<void> _run(String origin, FutureOr<void> Function() hook) async {
    try {
      await hook();
    } catch (e, st) {
      reportError(origin, e, st);
    }
  }

  void _disposeRetired() {
    for (final c in _retired) {
      c.dispose();
    }
    _retired.clear();
  }

  @override
  void dispose() {
    _auth.cancel();
    _disposeRetired();
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
        // A new key, so nothing below is updated in place.
        key: ObjectKey(_container),
        container: _container,
        child: widget.child,
      );
}
