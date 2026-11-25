/// D4: a coach list that is still being read has nothing to say yet.
///
/// The coach dashboard reads its lists with `.valueOrNull ?? []`. F-15 kept a
/// failed read apart from that empty list, but not a read still in flight, so
/// until the roster arrived a coach with clients was told "No clients found".
///
/// A reload that already holds rows keeps showing them (a realtime tick or a
/// token refresh re-reads the roster; it should not blank it). A reload holding
/// an EMPTY previous value is still reading: signing out leaves the roster at
/// `[]`, and the next coach to sign in would otherwise be told they have none.
///
/// P0-FL-59f: nor may rows another account read. Riverpod keeps the previous
/// value through a sign-in switch, and through the next account's failed read,
/// so holding rows does not say WHOSE they are. [ownedBy] records that, and
/// the rest of this file (and the sheets a coach opens) decide by it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, Supabase;

import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';

/// Who read each list. Beside the list rather than inside it, so the providers
/// keep their types.
final _owners = Expando<String>('the account that read these rows');

/// [rows], marked as read for [uid]; null (signed out) marks nothing.
///
/// The RETURNED list carries the mark, never [rows] itself: a shared instance
/// (a `const []`) marked for one account would be marked for all who hold it.
/// The mark does not survive `.toList()` or `.map()`, so mark last.
List<T> ownedBy<T>(String? uid, List<T> rows) {
  if (uid == null) return rows;
  final marked = List<T>.of(rows);
  _owners[marked] = uid;
  return marked;
}

/// The owner of rows nobody marked: no account's id, so nobody's to see.
const unknownOwner = '';

/// The account [list]'s held rows were read for.
///
/// Null when there is nothing to own (no value, or an empty list nobody
/// marked). Rows that ARE there and are not marked fail CLOSED while anybody
/// is signed in ([unknownOwner], which is nobody's id): every read marks its
/// rows, so such a list was rebuilt after [ownedBy] and its account is lost.
String? ownerOfHeld<T>(AsyncValue<List<T>> list) {
  final rows = list.hasValue ? list.value : null;
  if (rows == null) return null;
  final owner = _owners[rows];
  if (owner != null || rows.isEmpty) return owner;
  return signedInUid() == null ? null : unknownOwner;
}

/// Whose read failed, beside the error as [ownedBy] is beside the rows.
final _failedFor = Expando<String>('the account whose read failed');

/// [read], its rows marked as [uid]'s ([ownedBy]) and so is its failure:
/// Riverpod carries both into the next account's read.
Future<List<T>> ownedRead<T>(
    String? uid, Future<List<T>> Function() read) async {
  try {
    return ownedBy(uid, await read());
  } catch (e) {
    // (An Expando takes objects only; nothing here throws a bare string.)
    if (uid != null && (e is Exception || e is Error)) _failedFor[e] = uid;
    rethrow;
  }
}

String? _ownerOfFailure(Object? error) =>
    error is Exception || error is Error ? _failedFor[error!] : null;

/// Whether the failure [read] holds is that of an account that has left:
/// nothing of it is the next one's to be told. One nobody marked is not.
bool leftBehind(AsyncValue<Object?> read) =>
    accountLeft(_ownerOfFailure(read.error));

/// What [list] says to [uid], judged by whose rows and whose failure it holds
/// and by nothing else: an AsyncLoading, AsyncData or AsyncError each may carry
/// the previous account's. Another account's rows are dropped, the failure of
/// [uid]'s own read is kept, and otherwise it is still being read.
///
/// [keepUnmarked]: rows and failures nobody marked stay as they came (a read
/// replaced in a widget test); only those marked for another account go.
AsyncValue<List<T>> heldFor<T>(String? uid, AsyncValue<List<T>> list,
    {bool keepUnmarked = false}) {
  final error = list.error;
  final failedFor = _ownerOfFailure(error);
  final myFailure = error != null &&
      (failedFor != null
          ? failedFor == uid
          : keepUnmarked || !list.isLoading || uid == null);
  final owner = ownerOfHeld(list);
  // An unmarked empty list still being re-read is nobody's answer.
  final mine = list.hasValue &&
      (owner == uid ||
          (owner == null && (keepUnmarked || !list.isLoading)) ||
          (keepUnmarked && owner == unknownOwner));
  if (mine) {
    return error == null || myFailure ? list : AsyncData(list.requireValue);
  }
  if (!myFailure) return AsyncLoading<List<T>>();
  final failed = AsyncError<List<T>>(error, list.stackTrace ?? StackTrace.empty);
  // Read again meanwhile: still the last word, and its retry is busy.
  return list.isLoading
      ? AsyncLoading<List<T>>().copyWithPrevious(failed)
      : failed;
}

/// Whether [list] has nothing to say yet to [uid].
///
/// Rows marked for [uid] are an answer, empty or not, and a re-read of them
/// changes nothing on screen. Rows marked for another account are not: until
/// [uid]'s own read answers — or fails, which its caller says — this one is
/// still reading.
bool stillReading<T>(AsyncValue<List<T>> list, {String? uid}) {
  final owner = ownerOfHeld(list);
  if (owner != null) {
    return owner != uid && (list is! AsyncError || leftBehind(list));
  }
  return list.isLoading && (list.valueOrNull?.isEmpty ?? true);
}

/// Whether there is an auth client to ask. Always, in the running app: `main`
/// awaits `Supabase.initialize` before `runApp`. A widget test that replaces
/// every read mounts these screens with none, and then nobody is signed in.
/// (Only the debug assertion is caught: a release build without a client
/// throws at the first use, so this cannot read as "nobody" there.)
bool get hasAuthClient {
  try {
    Supabase.instance;
    return true;
  } on AssertionError {
    return false;
  }
}

/// The signed-in account's id, for capturing an owner when a form opens.
String? signedInUid() =>
    hasAuthClient ? Supabase.instance.client.auth.currentUser?.id : null;

/// Whether [owner] is still the account signed in, read from the auth client
/// itself: a widget or provider may not have rebuilt yet when a write starts
/// or lands.
bool stillSignedIn(String? owner) => signedInUid() == owner;

/// Whether [owner] was known and is no longer the account signed in.
bool accountLeft(String? owner) => owner != null && !stillSignedIn(owner);

/// Whether [owner] is no longer the account signed in — and then it is recorded
/// that [what] stopped there. Ask before every write and every message.
bool stoppedFor(String? owner, String origin, String what) {
  if (stillSignedIn(owner)) return false;
  reportError(origin, StateError('$what: the signed-in account changed'));
  return true;
}

/// Whether [owner] is a known account and the one signed in. A null [owner] is
/// nobody, and a signed-out device is not theirs either.
bool isSignedIn(String? owner) => owner != null && stillSignedIn(owner);

/// The client pages open on this device, and whose each one is (P0-FL-59f).
///
/// A page stops watching its client's reads when its coach leaves, but only in
/// its next build, and Riverpod re-reads what is still watched BEFORE that
/// build: the next account would ask for a client whose page it never opened,
/// and for the assessment that is a logged read. So the reads ask [admits].
class OpenClientPages {
  final _open = <String, List<String?>>{};

  /// The reads refused: to whom, and how to ask again.
  final _refused = <({String clientId, String? uid, void Function() again})>{};

  void opened(String clientId, String? owner) {
    (_open[clientId] ??= []).add(owner);
    // What was refused to them before they had a page is no answer to it.
    for (final r in _refused.toList()) {
      if (r.clientId == clientId && r.uid == owner) r.again();
    }
  }

  /// Remembers that [uid] was refused a read of [clientId]'s; calling what it
  /// returns forgets it.
  void Function() refused(String clientId, String? uid, void Function() again) {
    final r = (clientId: clientId, uid: uid, again: again);
    _refused.add(r);
    return () => _refused.remove(r);
  }

  void closed(String clientId, String? owner) {
    final owners = _open[clientId]?..remove(owner);
    if (owners != null && owners.isEmpty) _open.remove(clientId);
  }

  /// False when the pages open on [clientId] are all other accounts'.
  bool admits(String clientId, String? uid) {
    final owners = _open[clientId];
    return owners == null || owners.contains(uid);
  }
}

final openClientPagesProvider = Provider((_) => OpenClientPages());

/// Watches the account asking for something of [clientId]'s, by id only: a
/// refreshed token is the same coach and reads nothing again. Throws, instead
/// of asking, for an account whose page this is not.
///
/// What it returns goes around EVERY await of a read of more than one step: it
/// passes the answer on, or throws before the next step could go out as anyone
/// but the account that asked.
T Function<T>(T answer) readAsClientPageOwner(Ref ref, String clientId) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.id));
  final pages = ref.read(openClientPagesProvider);
  if (!pages.admits(clientId, uid)) {
    ref.onDispose(pages.refused(clientId, uid, ref.invalidateSelf));
    throw const ClientPageLeft();
  }
  return <T>(T answer) =>
      accountLeft(uid) ? throw const ClientPageLeft() : answer;
}

/// What [read] says on a page: a refusal is not its failure. It was asked again
/// as the page opened ([OpenClientPages.opened]), and is still being read.
AsyncValue<T> pageRead<T>(AsyncValue<T> read) =>
    read.error is ClientPageLeft ? AsyncLoading<T>() : read;

/// Nothing was read: the open page about the client is another account's, and
/// it shows nothing any more. Reaches no screen.
class ClientPageLeft implements Exception {
  const ClientPageLeft();
  @override
  String toString() => 'the coach whose client page this is has left';
}

/// A sheet or dialog that belongs to the account that opened it (P0-FL-59f).
///
/// [owner] is that account, captured by the opener: the route is built a frame
/// after it is pushed, and whoever signed in between must not be taken for it.
///
/// When another account signs in, or it signs out, [child] — and the draft or
/// prefill inside it — is dropped before the next frame is drawn, and the
/// route closes. Nothing is said to the next account. The same account
/// refreshing its token changes nothing.
///
/// The child is dropped FIRST and the route closed after that frame, so a
/// write of the child's that lands in between finds its own context unmounted
/// instead of popping the page underneath.
class OpenedByAccount extends StatefulWidget {
  final String? owner;
  final Widget child;
  const OpenedByAccount({super.key, required this.owner, required this.child});

  @override
  State<OpenedByAccount> createState() => _OpenedByAccountState();
}

class _OpenedByAccountState extends State<OpenedByAccount> {
  bool _left = false;
  StreamSubscription<AuthState>? _auth;

  @override
  void initState() {
    super.initState();
    if (!stillSignedIn(widget.owner)) {
      _leave();
      return;
    }
    if (!hasAuthClient) return;
    // An error on this stream (a failed refresh) is not a change of account.
    _auth = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => _check(), onError: (_) {});
  }

  void _check() {
    if (_left || !mounted || stillSignedIn(widget.owner)) return;
    setState(_leave);
  }

  void _leave() {
    _left = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive || route.isFirst) return;
      // Whatever it opened over itself (a date picker) is the same account's.
      Navigator.of(context)
        ..popUntil((r) => r == route)
        ..pop();
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _left ? const SizedBox.shrink() : widget.child;
}
