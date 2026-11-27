import 'package:flutter/foundation.dart' show AsyncValueGetter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../data/notification_model.dart';
import '../domain/notification_provider.dart';
import '../domain/notification_groups.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';
import '../../../core/widgets/named_icon_button.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
class _C {
  static const bg          = Color(0xFF060E20);
  static const surfDim     = Color(0xFF0A0A0B);
  static const surfCont    = Color(0xFF171F33);
  static const primary     = Color(0xFFDDB7FF);
  static const brand       = Color(0xFFA855F7);
  static const secondary   = Color(0xFFDEB7FF);
  static const onSurface   = Color(0xFFDAE2FD);
  static const onSurfVar   = Color(0xFFCFC2D6);
  static const outline     = Color(0xFF988D9F);
  static const error       = Color(0xFFFFB4AB);
  static const errCont     = Color(0xFF93000A);
}

/// Runs [change] (one of [notifier]'s three) and says it when the server did
/// not take it — to the member whose list the control was drawn for, not to
/// whoever is signed in by the tap or by the answer (P0-FL-60c). [notifier] is
/// the one the control was BUILT with: read at the tap, it would be the next
/// member's, and act for them.
Future<bool> _saySo(BuildContext context, String doWhat,
    NotificationsNotifier notifier, AsyncValueGetter<bool> change) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await change();
  if (!ok && Supabase.instance.client.auth.currentUser?.id == notifier.owner) {
    messenger?.showSnackBar(
        SnackBar(content: Text(couldntMessage(doWhat, notifier.lastError))));
  }
  return ok;
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  // No `initState` marking everything read.
  //
  // This screen ran `Future.delayed(2s) → markAllRead()` on open. Two seconds
  // after it appeared, every notification became read — whether the client had
  // read anything or not. That made `Mark all read`, which FIT-062 draws as a
  // **control**, pointless because it had already happened; it destroyed the
  // state the board's three unread signals exist to convey; and it wrote on
  // the client's behalf without being asked.
  //
  // The board draws marking-read as something the client does, so it is.

  /// The list whose "Mark all read" is on its way; that one takes no second tap.
  NotificationsNotifier? _markingAll;

  Future<void> _markAll(NotificationsNotifier notifier) async {
    if (identical(_markingAll, notifier)) return;
    setState(() => _markingAll = notifier);
    await _saySo(context, 'mark them read', notifier, notifier.markAllRead);
    if (!mounted || !identical(_markingAll, notifier)) return;
    setState(() => _markingAll = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final notifier = ref.watch(notificationsProvider.notifier);
    final marking = identical(_markingAll, notifier);
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(children: [
        // Background glow
        Positioned(top: -40, right: -40,
          child: Container(width: 300, height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.primary.withValues(alpha: 0.06)),)),
        Positioned(bottom: -20, left: -20,
          child: Container(width: 280, height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.secondary.withValues(alpha: 0.05)),)),

        Column(children: [
          // ── App Bar ─────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.only(
              top: topPad + 12, left: 16, right: 16, bottom: 14),
            decoration: BoxDecoration(
              color: _C.surfDim.withValues(alpha: 0.9),
              border: Border(bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.08)))),
            child: Row(children: [
              // FIT-062 declares `Back` as a named control
              // (`aria-label="Back"`). It shipped as an unnamed 38 px circle —
              // an A-G8 site, and `NamedIconButton` also lifts it to the 44 dp
              // floor it was two pixels under.
              NamedIconButton(
                label: 'Back',
                onTap: () => context.canPop() ? context.pop() : context.go('/home'),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
                  child: const Icon(Icons.arrow_back, color: _C.primary, size: 20)),
              ),
              const SizedBox(width: 14),
              const Text('Notifications',
                style: TextStyle(color: _C.onSurface, fontSize: 22,
                  fontWeight: FontWeight.w700)),
              const Spacer(),
              NamedIconButton(
                label: marking ? 'Marking all read' : markAllReadLabel,
                onTap: marking ? null : () => _markAll(notifier),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _C.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _C.brand.withValues(alpha: 0.25))),
                  child: Text(markAllReadLabel,
                    style: TextStyle(
                      color: _C.primary.withValues(alpha: marking ? 0.5 : 1),
                      fontSize: 11, fontWeight: FontWeight.w600)))),
            ]),
          ),

          // ── Content ──────────────────────────────────────────────────────
          Expanded(
            child: state.when(
              // A failed refresh keeps the list that was read.
              skipError: true,
              loading: () => const Center(
                child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2)),
              error: (e, _) => Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _LoadFailure(state: state, notifier: notifier))),
              data: (list) => Column(children: [
                if (state.hasError)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _LoadFailure(state: state, notifier: notifier)),
                Expanded(child: list.isEmpty
                    ? _EmptyState()
                    : _NotificationList(list: list, notifier: notifier)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  final AsyncValue<List<AppNotification>> state;
  final NotificationsNotifier notifier;
  const _LoadFailure({required this.state, required this.notifier});
  @override
  Widget build(BuildContext context) => SectionLoadFailure(
        what: state.hasValue ? 'your latest notifications' : 'your notifications',
        error: state.error,
        busy: state.isLoading,
        onRetry: notifier.refresh,
        accent: _C.primary,
        textColor: _C.onSurface,
        mutedColor: _C.onSurfVar);
}

// ── Notification List ─────────────────────────────────────────────────────────
class _NotificationList extends StatelessWidget {
  final List<AppNotification> list;
  final NotificationsNotifier notifier;
  const _NotificationList({required this.list, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDate(list);
    return RefreshIndicator(
      color: _C.primary,
      backgroundColor: _C.surfCont,
      onRefresh: notifier.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        itemCount: _countItems(groups),
        itemBuilder: (_, i) {
          final item = _itemAt(groups, i);
          if (item is String) return _GroupHeader(label: item, count: _unreadInGroup(groups, item));
          final n = item as AppNotification;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _NotificationCard(notification: n,
              onTap: () => _saySo(context, 'mark that read', notifier, () => notifier.markRead(n.id)),
              onDismiss: () => _saySo(context, 'delete that', notifier, () => notifier.delete(n.id))));
        },
      ),
    );
  }

  Map<String, List<AppNotification>> _groupByDate(List<AppNotification> list) {
    final groups = <String, List<AppNotification>>{};
    for (final n in list) {
      // FIT-062's two headings, plus one for anything older — see
      // `groupFor`. The scheme this replaces produced `Yesterday`,
      // `3 days ago` and `Sep 17` in the same list.
      groups
          .putIfAbsent(groupFor(n.createdAt).label, () => [])
          .add(n);
    }
    return groups;
  }


  int _countItems(Map<String, List<AppNotification>> g) =>
      g.entries.fold(0, (sum, e) => sum + 1 + e.value.length);

  Object _itemAt(Map<String, List<AppNotification>> g, int i) {
    var cur = 0;
    for (final e in g.entries) {
      if (i == cur) return e.key;
      cur++;
      if (i < cur + e.value.length) return e.value[i - cur];
      cur += e.value.length;
    }
    return '';
  }

  int _unreadInGroup(Map<String, List<AppNotification>> g, String key) =>
      g[key]?.where((n) => !n.read).length ?? 0;
}

// ── Group Header ──────────────────────────────────────────────────────────────
class _GroupHeader extends StatelessWidget {
  final String label;
  final int count;
  const _GroupHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 10, left: 2),
    child: Row(children: [
      Text(label.toUpperCase(),
        style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.55),
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)),
      const Spacer(),
      if (count > 0)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _C.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
          child: Text('$count NEW',
            style: const TextStyle(color: _C.primary, fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 1))),
    ]),
  );
}

// ── Notification Card ─────────────────────────────────────────────────────────
class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  /// Deletes the notification, saying so when the server did not take it; true
  /// when it did.
  final AsyncValueGetter<bool> onDismiss;
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final cfg = _typeConfig(n.type);
    // All three at once, so a caller cannot ship one and forget the other two
    // — which is exactly what happened here.
    final signals = unreadSignals(read: n.read);

    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: _C.errCont.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline_rounded, color: _C.error, size: 24)),
      // Delete first, dismiss only if it was deleted: a row whose delete failed
      // slides back, still there, and the member is told.
      confirmDismiss: (_) => onDismiss(),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: n.read
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: n.read
                  ? Colors.white.withValues(alpha: 0.06)
                  : cfg.color.withValues(alpha: 0.2))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Icon circle
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cfg.color.withValues(alpha: 0.15),
                border: Border.all(color: cfg.color.withValues(alpha: 0.2))),
              child: Center(child: Icon(cfg.icon, color: cfg.color, size: 20))),
            const SizedBox(width: 14),
            // Text body
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(n.type.toUpperCase().replaceAll('_', ' '),
                    style: TextStyle(color: cfg.color.withValues(alpha: 0.7),
                      fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  const Spacer(),
                  // FIT-062: "Unread carries a dot AND the word 'Unread' AND
                  // full-strength ink — three signals, since a violet dot
                  // alone fails for a colour-blind member."
                  //
                  // This is the SECOND signal. The screen shipped with the dot
                  // and nothing else, which is the one the board names as
                  // insufficient on its own.
                  Text(notificationMeta(read: n.read, createdAt: n.createdAt),
                    style: TextStyle(
                      color: signals.word
                          ? _C.primary
                          : _C.onSurfVar.withValues(alpha: 0.4),
                      fontSize: 10,
                      fontWeight:
                          signals.word ? FontWeight.w700 : FontWeight.w400)),
                ]),
                const SizedBox(height: 4),
                // The THIRD signal: full-strength ink on unread, dimmed once
                // read. A member who distinguishes neither the dot nor the
                // word still sees which rows are new.
                Text(n.title,
                  style: TextStyle(
                    color: signals.fullStrengthInk
                        ? _C.onSurface
                        : _C.onSurface.withValues(alpha: 0.55),
                    fontSize: 14,
                    fontWeight: signals.fullStrengthInk
                        ? FontWeight.w700
                        : FontWeight.w600)),
                const SizedBox(height: 3),
                Text(n.body,
                  style: TextStyle(
                    color: _C.onSurfVar.withValues(
                        alpha: signals.fullStrengthInk ? 0.85 : 0.5),
                    fontSize: 13, height: 1.4),
                  maxLines: 3, overflow: TextOverflow.ellipsis),
              ]),
            ),
            // The FIRST signal.
            if (signals.dot) ...[
              const SizedBox(width: 10),
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _C.primary,
                  boxShadow: [BoxShadow(
                    color: _C.primary.withValues(alpha: 0.6),
                    blurRadius: 6)]),
              ),
            ],
          ]),
        ),
      ),
    );
  }


  static _TypeConfig _typeConfig(String type) {
    switch (type) {
      case 'message':
      case 'messages':
        return _TypeConfig(Icons.chat_bubble_outline_rounded, const Color(0xFF60A5FA));
      case 'weekly_checkins':
      case 'checkin':
        return _TypeConfig(Icons.check_circle_outline_rounded, const Color(0xFF34D399));
      case 'today_score':
      case 'score':
        return _TypeConfig(Icons.auto_awesome_rounded, const Color(0xFFFBBF24));
      case 'challenges':
      case 'challenge':
        return _TypeConfig(Icons.emoji_events_outlined, const Color(0xFFFB923C));
      case 'nutrition_assigned':
      case 'nutrition':
        return _TypeConfig(Icons.restaurant_outlined, const Color(0xFFA3E635));
      case 'user':
      case 'achievement':
        return _TypeConfig(Icons.local_fire_department_outlined, const Color(0xFFF87171));
      case 'coach_request':
      case 'coach':
        return _TypeConfig(Icons.person_outline_rounded, const Color(0xFFDDB7FF));
      case 'workout':
        return _TypeConfig(Icons.fitness_center_outlined, const Color(0xFF818CF8));
      default:
        return _TypeConfig(Icons.notifications_outlined, const Color(0xFFCFC2D6));
    }
  }
}

class _TypeConfig {
  final IconData icon;
  final Color color;
  const _TypeConfig(this.icon, this.color);
}

// ── Empty State ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07))),
        child: Icon(Icons.notifications_paused_outlined,
          color: _C.outline.withValues(alpha: 0.5), size: 36)),
      const SizedBox(height: 20),
      // FIT-062's own words. The copy this replaces — "All caught up!" /
      // "No more notifications for now." — says the list is empty twice and
      // never says what would appear in it. The board's names the categories
      // the app actually sends.
      Text(emptyNotificationsTitle,
        style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.7),
          fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(emptyNotificationsBody,
        style: TextStyle(color: _C.onSurfVar.withValues(alpha: 0.4),
          fontSize: 13)),
    ]),
  );
}
