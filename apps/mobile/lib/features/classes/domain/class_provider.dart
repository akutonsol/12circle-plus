import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/class_service.dart';
import '../data/live_class_service.dart';
import '../data/models/class_model.dart';

final classServiceProvider = Provider<ClassService>((ref) => ClassService());
final liveClassServiceProvider = Provider<LiveClassService>((ref) => LiveClassService());
final selectedClassProvider = StateProvider<FitnessClass?>((ref) => null);
final selectedClassTabProvider = StateProvider<int>((ref) => 0);
final classFilterProvider = StateProvider<ClassCategory?>((ref) => null);

// ── Classes from Supabase with sample fallback ────────────────────────────────
// `refreshClassesProvider` is bumped after a booking/creation to re-fetch.
final refreshClassesProvider = StateProvider<int>((ref) => 0);

final liveClassesFromDbProvider = FutureProvider<List<FitnessClass>>((ref) async {
  ref.watch(currentUserProvider);
  ref.watch(refreshClassesProvider);
  final svc = ref.watch(liveClassServiceProvider);
  final live = await svc.getUpcomingClasses();
  // Real classes only — no fake/sample fallback (avoids showing demo coaches
  // like "Coach Sarah" in production). Empty DB → empty list → empty state.
  return live.where((c) => c.status != ClassStatus.completed).toList();
});

// Schedule tab: everything not yet finished, soonest first.
final scheduleClassesProvider = Provider<List<FitnessClass>>((ref) {
  final all = ref.watch(liveClassesFromDbProvider).valueOrNull ?? [];
  final list = all.where((c) => c.status != ClassStatus.completed).toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  return list;
});

// Live tab: classes happening right now.
final liveNowClassesProvider = Provider<List<FitnessClass>>((ref) {
  final all = ref.watch(liveClassesFromDbProvider).valueOrNull ?? [];
  return all.where((c) => c.status == ClassStatus.live).toList();
});

// My Bookings tab: classes the user registered for (real DB query).
final myClassBookingsProvider = FutureProvider<List<FitnessClass>>((ref) async {
  ref.watch(currentUserProvider);
  ref.watch(refreshClassesProvider);
  return ref.watch(liveClassServiceProvider).getMyBookings();
});

// Coach: classes I created.
final myCreatedClassesProvider = FutureProvider<List<FitnessClass>>((ref) async {
  ref.watch(currentUserProvider);
  ref.watch(refreshClassesProvider);
  return ref.watch(liveClassServiceProvider).getMyCreatedClasses();
});

class ClassNotifier extends StateNotifier<List<FitnessClass>> {
  final LiveClassService _liveSvc;

  ClassNotifier(List<FitnessClass> initial, this._liveSvc) : super(initial);

  Future<void> bookClass(String classId) async {
    // The server's answer, not this list's (possibly stale) idea of "full".
    final status = await _liveSvc.bookClass(classId);
    state = state.map((c) {
      if (c.id != classId) return c;
      if (status == 'waitlisted') return _withWaitlist(c);
      return FitnessClass(
        id: c.id, title: c.title, description: c.description,
        category: c.category, status: c.status, startTime: c.startTime,
        durationMinutes: c.durationMinutes, capacity: c.capacity,
        bookedCount: c.bookedCount + 1, waitlistCount: c.waitlistCount,
        instructor: c.instructor, location: c.location, isVirtual: c.isVirtual,
        streamUrl: c.streamUrl, isBooked: true, isWaitlisted: false,
        tags: c.tags, price: c.price,
      );
    }).toList();
  }

  FitnessClass _withWaitlist(FitnessClass c) => FitnessClass(
    id: c.id, title: c.title, description: c.description,
    category: c.category, status: c.status, startTime: c.startTime,
    durationMinutes: c.durationMinutes, capacity: c.capacity,
    bookedCount: c.bookedCount, waitlistCount: c.waitlistCount + 1,
    instructor: c.instructor, location: c.location, isVirtual: c.isVirtual,
    streamUrl: c.streamUrl, isBooked: false, isWaitlisted: true,
    tags: c.tags, price: c.price,
  );

  Future<void> cancelBooking(String classId) async {
    await _liveSvc.cancelBooking(classId);
    state = state.map((c) {
      if (c.id != classId) return c;
      return FitnessClass(
        id: c.id, title: c.title, description: c.description,
        category: c.category, status: c.status, startTime: c.startTime,
        durationMinutes: c.durationMinutes, capacity: c.capacity,
        bookedCount: c.isBooked ? c.bookedCount - 1 : c.bookedCount,
        waitlistCount: c.isWaitlisted ? c.waitlistCount - 1 : c.waitlistCount,
        instructor: c.instructor, location: c.location, isVirtual: c.isVirtual,
        streamUrl: c.streamUrl, isBooked: false, isWaitlisted: false,
        tags: c.tags, price: c.price,
      );
    }).toList();
  }
}

final classNotifierProvider = StateNotifierProvider<ClassNotifier, List<FitnessClass>>((ref) {
  final svc = ref.watch(classServiceProvider);
  final liveSvc = ref.watch(liveClassServiceProvider);
  return ClassNotifier(svc.getSampleClasses(), liveSvc);
});

final upcomingClassesProvider = Provider<List<FitnessClass>>((ref) {
  return ref.watch(classNotifierProvider).where((c) => c.status == ClassStatus.upcoming).toList();
});

final myBookingsProvider = Provider<List<FitnessClass>>((ref) {
  return ref.watch(classNotifierProvider).where((c) => c.isBooked || c.isWaitlisted).toList();
});
