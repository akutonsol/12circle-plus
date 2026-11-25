import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final myEventsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(vendorServiceProvider).getMyEvents();
});

final eventRegistrationsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, eventId) async {
  return ref.watch(vendorServiceProvider).getRegistrations(eventId);
});
