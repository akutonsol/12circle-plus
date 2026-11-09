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
    _sub?.cancel();
    _seen.clear();
    _primed = false;
    try {
      _sub = Supabase.instance.client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('recipient_id', uid)
          .listen((rows) {
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
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
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
