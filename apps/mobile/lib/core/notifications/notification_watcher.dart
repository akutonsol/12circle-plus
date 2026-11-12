import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/checkins/domain/checkin_provider.dart'
    show coachSubmittedCheckinsProvider;
import '../../features/checkins/presentation/checkin_hub_sections.dart'
    show checkinHistoryProvider;
import '../../features/coach/domain/coach_ecosystem_provider.dart'
    show
        myAssignedProgramProvider,
        myHabitsProvider,
        myNutritionPlanProvider,
        todaysWorkoutProvider;
import '../../features/coach/domain/coach_provider.dart'
    show
        assignedCoachProvider,
        clientRelationshipProvider,
        myCoachesProvider,
        pendingCoachProvider;
import '../../features/payments/domain/entitlements.dart' show clientPlanProvider;
import '../../features/habits/domain/habit_provider.dart'
    show liveHabitNotifierProvider;
import '../../features/nutrition/domain/nutrition_provider.dart'
    show nutritionGoalsProvider;
import '../../features/workout/domain/workout_provider.dart' show assignedWorkoutsProvider;
import 'browser_push.dart';

/// Re-reads what a new notification says has changed.
///
/// What a coach assigns reaches the client as a notification, and nothing else
/// tells these providers: they don't dispose and no table ticks them, so the
/// client read "assigned you a program" over a Home that still said there was
/// none until the app restarted.
///
/// `weekly_checkins` goes only to the coach, from `trg_notify_coach_on_checkin`
/// (004), when a client submits: the review queue, if it is open, gains one.
/// `checkin` goes only to the client, from `submitCoachFeedback`, when the
/// coach replies: the history and an open week then show the reply.
void refreshForNotification(
    String? type, void Function(ProviderOrFamily) invalidate) {
  switch (type) {
    case 'program_assigned':
      invalidate(assignedWorkoutsProvider);
      invalidate(myAssignedProgramProvider);
      invalidate(todaysWorkoutProvider);
    case 'nutrition_assigned':
      invalidate(myNutritionPlanProvider);
      // What the client's Nutrition, Meals and Meal plan screens show.
      invalidate(nutritionGoalsProvider);
    case 'habits_assigned':
      invalidate(myHabitsProvider);
      // The Habits screen.
      invalidate(liveHabitNotifierProvider);
    case 'weekly_checkins':
      invalidate(coachSubmittedCheckinsProvider);
    case 'checkin':
      invalidate(checkinHistoryProvider);
    // `request_approved` / `request_declined` go only to the client, from
    // `approveRequest` / `declineRequest`. An active relationship is also a
    // plan: `client_plan()` answers coach_guided for one.
    case 'request_approved':
      invalidate(assignedCoachProvider);
      invalidate(myCoachesProvider);
      invalidate(pendingCoachProvider);
      invalidate(clientRelationshipProvider);
      invalidate(clientPlanProvider);
    case 'request_declined':
      invalidate(pendingCoachProvider);
      invalidate(clientRelationshipProvider);
  }
}

/// Wraps the app and surfaces every new in-app notification as a native
/// browser notification (web). Subscribes to the signed-in user's
/// notifications in realtime; the first batch only primes the "seen" set so we
/// don't replay history on load.
class NotificationWatcher extends ConsumerStatefulWidget {
  final Widget child;
  const NotificationWatcher({super.key, required this.child});

  @override
  ConsumerState<NotificationWatcher> createState() => _NotificationWatcherState();
}

class _NotificationWatcherState extends ConsumerState<NotificationWatcher> {
  final Set<String> _seen = {};
  bool _primed = false;
  StreamSubscription? _sub;
  String? _uid;
  Timer? _retry;
  Duration _retryDelay = _firstRetry;

  static const _firstRetry = Duration(seconds: 2);
  static const _maxRetry = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    ensurePermission();
    _subscribe();
  }

  void _subscribe() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid == _uid) return;
    _uid = uid;
    _retry?.cancel();
    _retryDelay = _firstRetry;
    _sub?.cancel();
    _seen.clear();
    _primed = false;
    _listen(uid);
  }

  void _listen(String uid) {
    try {
      _sub = Supabase.instance.client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('recipient_id', uid)
          .listen((rows) {
        _retryDelay = _firstRetry;
        for (final r in rows) {
          final id = r['id']?.toString();
          if (id == null || _seen.contains(id)) continue;
          _seen.add(id);
          if (_primed) {
            refreshForNotification(r['type'] as String?, ref.invalidate);
            if (r['read'] == false) {
              showBrowserNotification(
                r['title'] as String? ?? '12 Circle',
                r['body'] as String? ?? '',
              );
            }
          }
        }
        _primed = true;
      }, onError: (_) {}, onDone: () => _listenAgainLater(uid));
    } catch (_) {}
  }

  /// The stream ends for good when one of its reads fails — supabase's stream
  /// builder unsubscribes and closes on a failed fetch, at start or on any
  /// reconnect — and `uid == _uid` kept [_subscribe] from ever opening another.
  /// One offline moment left this tab with no notifications and none of the
  /// refreshes above until it was reloaded. Listen again, backing off while it
  /// keeps failing. [_seen] and [_primed] are kept, so whatever arrived while
  /// it was down is new and is acted on.
  void _listenAgainLater(String uid) {
    if (!mounted || _uid != uid) return;
    _retry?.cancel();
    final delay = _retryDelay;
    _retryDelay = delay * 2 > _maxRetry ? _maxRetry : delay * 2;
    _retry = Timer(delay, () {
      if (!mounted || _uid != uid) return;
      if (Supabase.instance.client.auth.currentUser?.id != uid) return;
      _sub?.cancel();
      _listen(uid);
    });
  }

  @override
  void dispose() {
    _retry?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-subscribe if the signed-in user changed (login after logout).
    _subscribe();
    return widget.child;
  }
}
