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

/// Who read each list. Beside the list rather than inside it, so the providers
/// keep their types.
final _owners = Expando<String>('the account that read these rows');

/// Marks [rows] as read for [uid]; null (signed out) marks nothing.
List<T> ownedBy<T>(String? uid, List<T> rows) {
  if (uid != null) _owners[rows] = uid;
  return rows;
}

/// The account [list]'s held rows were read for, or null when it holds none
/// or they are not marked.
String? ownerOfHeld<T>(AsyncValue<List<T>> list) {
  final rows = list.hasValue ? list.value : null;
  return rows == null ? null : _owners[rows];
}

/// Whether [list] has nothing to say yet to [uid].
///
/// Rows marked for [uid] are an answer, empty or not, and a re-read of them
/// changes nothing on screen. Rows marked for another account are not: until
/// [uid]'s own read answers — or fails, which its caller says — this one is
/// still reading.
bool stillReading<T>(AsyncValue<List<T>> list, {String? uid}) {
  final owner = ownerOfHeld(list);
  if (owner != null) return owner != uid && list is! AsyncError;
  return list.isLoading && (list.valueOrNull?.isEmpty ?? true);
}

/// The signed-in account's id, for capturing an owner when a form opens.
String? signedInUid() => Supabase.instance.client.auth.currentUser?.id;

/// Whether [owner] is still the account signed in, read from the auth client
/// itself: a widget or provider may not have rebuilt yet when a write starts
/// or lands.
bool stillSignedIn(String? owner) => signedInUid() == owner;

/// Whether [owner] was known and is no longer the account signed in.
bool accountLeft(String? owner) => owner != null && !stillSignedIn(owner);

/// A sheet or dialog that belongs to the account that opened it (P0-FL-59f).
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
  final Widget child;
  const OpenedByAccount({super.key, required this.child});

  @override
  State<OpenedByAccount> createState() => _OpenedByAccountState();
}

class _OpenedByAccountState extends State<OpenedByAccount> {
  final String? _owner = signedInUid();
  bool _left = false;
  late final StreamSubscription<AuthState> _auth;

  @override
  void initState() {
    super.initState();
    // An error on this stream (a failed refresh) is not a change of account.
    _auth = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => _check(), onError: (_) {});
  }

  void _check() {
    if (_left || !mounted || stillSignedIn(_owner)) return;
    setState(() => _left = true);
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
    _auth.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _left ? const SizedBox.shrink() : widget.child;
}
