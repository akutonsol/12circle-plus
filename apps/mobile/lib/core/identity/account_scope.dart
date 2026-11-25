import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../observability/app_failure.dart';

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
    this.onOwnerLeft,
    this.overrides = const [],
  });

  final Widget child;

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
      (state) => _follow(state.session?.user.id),
      // A failed refresh ends no session; gotrue has logged it.
      onError: (Object _, StackTrace __) {},
    );
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
    _ownerLeft(left);
  }

  Future<void> _ownerLeft(String uid) async {
    try {
      await widget.onOwnerLeft?.call(uid);
    } catch (e, st) {
      reportError('AccountScope.onOwnerLeft', e, st);
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
