import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/identity/account_scope.dart' show signedInUid;
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/vendor_service.dart';
import '../data/session_service.dart';

final vendorServiceProvider = Provider<VendorService>((ref) => VendorService());

final sessionServiceProvider = Provider<SessionService>((ref) => SessionService());

/// An event's agenda (sessions). Used by both the vendor manager and the
/// client-facing agenda view.
final eventSessionsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, eventId) async {
  return ref.watch(sessionServiceProvider).getSessions(eventId);
});

/// Rows, and the account whose read they answered (P0-FL-59a): taken when the
/// read starts, never inferred from the provider's state. riverpod keeps a
/// previous value through a reload, and does not tell a screen when a refresh
/// already in flight is restarted for another account, so a screen draws
/// these only for the account signed in when it draws.
class VendorRows {
  const VendorRows(this.owner, this.rows);
  final String? owner;
  final List<Map<String, dynamic>> rows;
}

/// A vendor read that failed, and the account it was started for.
class VendorReadFailure implements Exception {
  const VendorReadFailure(this.owner, this.error);
  final String? owner;
  final Object error;
  @override
  String toString() => 'VendorReadFailure($error)';
}

/// The account [error] (a provider's) was a failure for; null if unknown.
String? vendorFailureOwner(Object? error) =>
    error is VendorReadFailure ? error.owner : null;

/// The cause behind [error], for the hint said with it.
Object? vendorFailureCause(Object? error) =>
    error is VendorReadFailure ? error.error : error;

Future<VendorRows> _ownedRead(String origin, String? owner,
    Future<List<Map<String, dynamic>>> Function() read) async {
  try {
    if (signedInUid() != owner) {
      throw StateError('$origin: the signed-in account changed');
    }
    final rows = await read();
    // Answered on whichever token was current when it was sent.
    if (signedInUid() != owner) {
      throw StateError('$origin: the signed-in account changed');
    }
    return VendorRows(owner, rows);
  } catch (e, st) {
    reportError(origin, e, st);
    throw VendorReadFailure(owner, e);
  }
}

final myEventsProvider = FutureProvider<VendorRows>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final owner = signedInUid();
  final svc = ref.watch(vendorServiceProvider);
  return _ownedRead('myEventsProvider', owner, () => svc.getMyEvents(owner));
});

/// One event's attendees, read for [owner] only (the account the event was
/// listed for): for anyone else nothing is asked.
final eventRegistrationsProvider =
    FutureProvider.family<VendorRows, ({String eventId, String owner})>(
        (ref, key) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final svc = ref.watch(vendorServiceProvider);
  return _ownedRead('eventRegistrationsProvider', key.owner,
      () => svc.getRegistrations(key.eventId, owner: key.owner));
});
