import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/identity/account_scope.dart'
    show signOutFailedText, signOutOfDevice, signedInUid;
import '../../../core/observability/app_failure.dart';
import '../../auth/domain/auth_provider.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';
import '../domain/vendor_provider.dart';
import 'event_agenda_screen.dart';

const _bg     = Color(0xFF030303);
const _card   = Color(0xFF0E0B16);
const _border = Color(0xFF1A1020);
const _brand  = Color(0xFFA855F7);
const _white  = Colors.white;
const _muted  = Color(0xFFCFC2D6);
const _mint   = Color(0xFF6FFBBE);
const _amber  = Color(0xFFFFD479);

String _fmtDate(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return '—';
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${months[d.month - 1]} ${d.day} · $h:${d.minute.toString().padLeft(2, '0')} $ap';
}

// ── Whose it is (P0-FL-59a) ─────────────────────────────────────────────────
//
// Every row here was read for one account, and every action was drawn for one.
// The screens watch the signed-in uid themselves and draw only what was read
// for it: riverpod does not tell a screen when a refresh already in flight is
// restarted for another account, so the rows it held stay drawn otherwise. An
// action checks its account right before it writes, and again before it says
// anything; a tap can land after a switch with no frame between.

/// What [value] holds for [uid]: rows, and a failure, each only if its read was
/// started for [uid]. Neither: that account's read is still to answer.
({List<Map<String, dynamic>>? rows, Object? failure}) _heldFor(
    AsyncValue<VendorRows> value, String? uid) {
  final held = value.hasValue ? value.requireValue : null;
  return (
    rows: held != null && held.owner == uid ? held.rows : null,
    failure: value.hasError && vendorFailureOwner(value.error) == uid
        ? vendorFailureCause(value.error)
        : null,
  );
}

/// [owner] is still the account signed in; else records that [what] was not
/// done for the one that is.
bool _stillFor(String? owner, String origin, String what) {
  if (owner != null && signedInUid() == owner) return true;
  reportError(origin, StateError('$what: the signed-in account changed'));
  return false;
}

/// One write for [owner], started from [context]. What it needs afterwards is
/// taken before the first await: the widget may be gone by the answer, and
/// with an account change its container too.
class _OwnedWrite {
  _OwnedWrite(BuildContext context, this.owner, this.origin, this.what)
      : _messenger = ScaffoldMessenger.maybeOf(context),
        _container = ProviderScope.containerOf(context, listen: false);
  final String owner;
  final String origin;
  final String what;
  final ScaffoldMessengerState? _messenger;
  final ProviderContainer _container;

  /// Right before the write, with no await after it.
  bool get mayWrite => _stillFor(owner, origin, what);

  /// The write answered ([error]: it failed, and is recorded). Reads [refresh]
  /// again — the stored state, also after a failure — and says a failure, to
  /// [owner] only.
  void answered(ProviderOrFamily refresh, [Object? error]) {
    if (signedInUid() != owner) {
      reportError(origin,
          StateError('$what: answered after the signed-in account changed'));
      return;
    }
    final messenger = _messenger;
    // Its tree is still up, so its container is not disposed.
    if (messenger == null || !messenger.mounted) return;
    _container.invalidate(refresh);
    if (error != null) {
      messenger.showSnackBar(
          SnackBar(content: Text(couldntMessage(what, error))));
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Vendor Portal — a vendor's events + attendees (Module 15)
// ════════════════════════════════════════════════════════════════════════════
class VendorPortalScreen extends ConsumerWidget {
  const VendorPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(currentUserProvider.select((u) => u?.id));
    final uid = signedInUid();
    final eventsAsync = ref.watch(myEventsProvider);
    final held = _heldFor(eventsAsync, uid);
    final events = held.rows;
    final failure = held.failure;
    final failureCard = failure == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SectionLoadFailure(
              what: 'your events',
              error: failure,
              busy: eventsAsync.isLoading,
              onRetry: () => ref.invalidate(myEventsProvider),
              accent: _brand,
              mutedColor: _muted,
            ),
          );

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text('Vendor Portal',
            style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: _muted),
            onPressed: () async {
              // Drawn for another account, with no frame since: not this
              // one's sign-out.
              if (signedInUid() != uid) {
                reportError('VendorPortalScreen.signOut',
                    StateError('sign out: the signed-in account changed'));
                return;
              }
              final error = await signOutOfDevice('VendorPortalScreen.signOut',
                  Supabase.instance.client.auth.signOut);
              if (!context.mounted) return;
              if (error == null) {
                context.go('/login');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(signOutFailedText(error))));
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _brand,
        icon: const Icon(Icons.add, color: _white),
        label: const Text('New Event', style: TextStyle(color: _white)),
        onPressed: () => _openEventEditor(context, ref, uid),
      ),
      body: Builder(builder: (_) {
          if (events == null) {
            return failureCard ??
                const Center(
                    child: CircularProgressIndicator(color: _brand));
          }
          if (events.isEmpty) {
            if (failureCard != null) return failureCard;
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No events yet.\nTap “New Event” to create your first one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.4),
                ),
              ),
            );
          }
          // A failed refresh keeps what was shown, and says so above it.
          final list = RefreshIndicator(
            color: _brand,
            backgroundColor: _card,
            onRefresh: () async => ref.invalidate(myEventsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: events.length,
              itemBuilder: (_, i) => _EventCard(event: events[i], owner: uid!),
            ),
          );
          return failureCard == null
              ? list
              : Column(children: [failureCard, Expanded(child: list)]);
        }),
    );
  }

}

/// The editor, for [owner] (the account the portal was drawn for). Its draft
/// is saved for [owner] only, stamped with [owner], and never for an account
/// that signed in while it was open.
Future<void> _openEventEditor(BuildContext context, WidgetRef ref,
    String? owner, {Map<String, dynamic>? existing}) async {
  final origin = existing == null
      ? 'VendorPortalScreen.createEvent'
      : 'VendorPortalScreen.updateEvent';
  if (!_stillFor(owner, origin, 'open the event editor')) return;
  final write = _OwnedWrite(context, owner!, origin,
      existing == null ? 'create the event' : 'save the event');
  final svc = ref.read(vendorServiceProvider);
  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) =>
        _OwnedSheet(owner: owner, child: _EventEditorSheet(existing: existing)),
  );
  if (result == null) return;
  if (!write.mayWrite) return;
  try {
    if (existing == null) {
      await svc.createEvent(result, vendorId: owner);
    } else {
      await svc.updateEvent(existing['id'] as String, result);
    }
  } catch (e, st) {
    reportError(origin, e, st);
    write.answered(myEventsProvider, e);
    return;
  }
  write.answered(myEventsProvider);
}

/// [child], drawn only while [owner] is signed in, and closed when another
/// account (or none) is: what [owner] typed is not the next account's.
///
/// P0-FL-63a · the sheet is pushed for [owner] and built a frame later. When
/// the account changed in between, its listener (registered in that first
/// build, after the change) never fires: it closes its own route after that
/// frame instead, so the next account is not left an empty sheet. Either way
/// it is closed, and recorded, once — and only its own route is removed.
class _OwnedSheet extends ConsumerStatefulWidget {
  const _OwnedSheet({required this.owner, required this.child});
  final String owner;
  final Widget child;

  @override
  ConsumerState<_OwnedSheet> createState() => _OwnedSheetState();
}

class _OwnedSheetState extends ConsumerState<_OwnedSheet> {
  bool _closing = false;

  /// RM-2 (C15-63a-01) · the routes this sheet opened over itself (its date
  /// and time pickers). They are [owner]'s too, and go with the sheet: on the
  /// root navigator they outlived it, over the next account's portal.
  final _opened = <Route<dynamic>>{};

  /// Called from inside a route this sheet's child pushed, so it is closed
  /// with the sheet. Only routes registered here are ever removed.
  void _ownRoute(Route<dynamic>? route) {
    if (route != null && route.isActive) _opened.add(route);
  }

  void _close(Route<dynamic>? route) {
    // Already closing, or already off the stack (dismissed): nothing to do.
    if (_closing || route == null || !route.isActive) return;
    final navigator = route.navigator;
    if (navigator == null) return;
    _closing = true;
    reportError('VendorPortalScreen.eventEditor',
        StateError('event editor closed: the signed-in account changed'));
    // Its own pickers first (each on whichever navigator holds it), then the
    // sheet. Nothing else above or below it is touched.
    for (final picker in _opened.toList().reversed) {
      if (picker.isActive) picker.navigator?.removeRoute(picker);
    }
    _opened.clear();
    navigator.removeRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    ref.listen(currentUserProvider.select((u) => u?.id), (_, __) {
      if (signedInUid() != widget.owner) _close(route);
    });
    if (signedInUid() == widget.owner) return widget.child;
    if (!_closing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close(route);
      });
    }
    return const SizedBox.shrink();
  }
}

Future<void> _deleteEvent(BuildContext context, WidgetRef ref, String owner,
    Map<String, dynamic> event) async {
  const origin = 'VendorPortalScreen.deleteEvent';
  final write = _OwnedWrite(context, owner, origin, 'delete the event');
  final svc = ref.read(vendorServiceProvider);
  if (!write.mayWrite) return;
  try {
    await svc.deleteEvent(event['id'] as String);
  } catch (e, st) {
    reportError(origin, e, st);
    write.answered(myEventsProvider, e);
    return;
  }
  write.answered(myEventsProvider);
}

class _EventCard extends ConsumerWidget {
  final Map<String, dynamic> event;

  /// The account this event was listed for.
  final String owner;
  const _EventCard({required this.event, required this.owner});

  int get _regCount {
    final r = event['event_registrations'];
    if (r is List && r.isNotEmpty && r.first is Map) {
      return (r.first['count'] as int?) ?? 0;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = (event['max_capacity'] as int?);
    final isFree = event['is_free'] as bool? ?? true;
    final price = (event['price'] as num?)?.toDouble() ?? 0;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (!_stillFor(owner, 'VendorPortalScreen.openAttendees',
            'open attendees')) {
          return;
        }
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    EventAttendeesScreen(event: event, owner: owner)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF160E26), _card]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(event['title'] ?? 'Untitled event',
                      style: const TextStyle(
                          color: _white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
                PopupMenuButton<String>(
                  color: _card,
                  icon: const Icon(Icons.more_horiz, color: _muted),
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await _openEventEditor(context, ref, owner,
                          existing: event);
                    } else if (v == 'agenda') {
                      if (!_stillFor(owner, 'VendorPortalScreen.openAgenda',
                          'open the agenda')) {
                        return;
                      }
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              // The portal's account, not whoever is signed
                              // in when the page is first built (P0-FL-63a).
                              builder: (_) => EventAgendaScreen(
                                  event: event,
                                  canManage: true,
                                  owner: owner)));
                    } else if (v == 'delete') {
                      await _deleteEvent(context, ref, owner, event);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit', style: TextStyle(color: _white))),
                    PopupMenuItem(
                        value: 'agenda',
                        child: Text('Manage Agenda',
                            style: TextStyle(color: _white))),
                    PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete',
                            style: TextStyle(color: Color(0xFFFFB4AB)))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.event, size: 14, color: _muted),
              const SizedBox(width: 6),
              Text(_fmtDate(event['event_date'] as String?),
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ]),
            if (event['location'] != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.place_outlined, size: 14, color: _muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${event['location']}',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                ),
              ]),
            ],
            const SizedBox(height: 12),
            Row(children: [
              _pill(Icons.people_alt_rounded,
                  cap == null ? '$_regCount registered' : '$_regCount / $cap', _brand),
              const SizedBox(width: 8),
              _pill(isFree ? Icons.celebration_rounded : Icons.sell_rounded,
                  isFree ? 'Free' : '\$${price.toStringAsFixed(0)}',
                  isFree ? _mint : _amber),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

// ── Attendees screen ─────────────────────────────────────────────────────────
class EventAttendeesScreen extends ConsumerWidget {
  final Map<String, dynamic> event;

  /// The account the event was listed for: the page is its, and nobody else's
  /// — another account signed in sees none of it, and nothing is read for it.
  final String owner;
  const EventAttendeesScreen(
      {super.key, required this.event, required this.owner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(currentUserProvider.select((u) => u?.id));
    if (signedInUid() != owner) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            iconTheme: const IconThemeData(color: _white)),
      );
    }
    final key = (eventId: event['id'] as String, owner: owner);
    final regsAsync = ref.watch(eventRegistrationsProvider(key));
    final held = _heldFor(regsAsync, owner);
    final regs = held.rows;
    final failure = held.failure;
    final failureCard = failure == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SectionLoadFailure(
              what: 'attendees',
              error: failure,
              busy: regsAsync.isLoading,
              onRetry: () => ref.invalidate(eventRegistrationsProvider(key)),
              accent: _brand,
              mutedColor: _muted,
            ),
          );

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _white),
        title: Text(event['title'] ?? 'Attendees',
            style: const TextStyle(color: _white, fontWeight: FontWeight.w700)),
      ),
      body: Builder(builder: (_) {
          if (regs == null) {
            return failureCard ??
                const Center(
                    child: CircularProgressIndicator(color: _brand));
          }
          final checkedIn =
              regs.where((r) => r['checked_in_at'] != null).length;
          return Column(
            children: [
              if (failureCard != null) failureCard,
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF160E26), _card]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Registered', '${regs.length}', _brand),
                    _stat('Checked In', '$checkedIn', _mint),
                    _stat('Pending', '${regs.length - checkedIn}', _amber),
                  ],
                ),
              ),
              Expanded(
                child: regs.isEmpty
                    ? const Center(
                        child: Text('No registrations yet.',
                            style: TextStyle(color: _muted)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: regs.length,
                        itemBuilder: (_, i) => _AttendeeRow(
                          reg: regs[i],
                          onToggle: (checked) => _setCheckedIn(
                              context, ref, key, regs[i], checked),
                        ),
                      ),
              ),
            ],
          );
        }),
    );
  }

  /// For the account the row was read for ([key]'s owner) only.
  static Future<void> _setCheckedIn(
      BuildContext context,
      WidgetRef ref,
      ({String eventId, String owner}) key,
      Map<String, dynamic> reg,
      bool checked) async {
    const origin = 'EventAttendeesScreen.setCheckedIn';
    final write = _OwnedWrite(context, key.owner, origin, 'save the check-in');
    final svc = ref.read(vendorServiceProvider);
    if (!write.mayWrite) return;
    try {
      await svc.setCheckedIn(reg['id'] as String, checked);
    } catch (e, st) {
      reportError(origin, e, st);
      write.answered(eventRegistrationsProvider(key), e);
      return;
    }
    write.answered(eventRegistrationsProvider(key));
  }

  Widget _stat(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      );
}

class _AttendeeRow extends StatelessWidget {
  final Map<String, dynamic> reg;
  final ValueChanged<bool> onToggle;
  const _AttendeeRow({required this.reg, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final profile = reg['user_profiles'] as Map<String, dynamic>?;
    final name = profile == null
        ? 'Attendee'
        : '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
    final checkedIn = reg['checked_in_at'] != null;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: checkedIn ? _mint.withValues(alpha: 0.4) : _border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _brand.withValues(alpha: 0.18),
            child: Text(initial,
                style: const TextStyle(
                    color: _brand, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'Attendee' : name,
                    style: const TextStyle(
                        color: _white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(profile?['email'] as String? ?? '',
                    style: const TextStyle(color: _muted, fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onToggle(!checkedIn),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: checkedIn
                    ? _mint.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: checkedIn ? _mint : _border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(checkedIn ? Icons.check_circle : Icons.circle_outlined,
                    size: 16, color: checkedIn ? _mint : _muted),
                const SizedBox(width: 6),
                Text(checkedIn ? 'In' : 'Check in',
                    style: TextStyle(
                        color: checkedIn ? _mint : _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Event editor sheet (create / edit) ───────────────────────────────────────
class _EventEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _EventEditorSheet({this.existing});
  @override
  State<_EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends State<_EventEditorSheet> {
  late TextEditingController _title;
  late TextEditingController _desc;
  late TextEditingController _location;
  late TextEditingController _capacity;
  late TextEditingController _price;
  late DateTime _date;
  bool _isFree = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?['title'] as String? ?? '');
    _desc = TextEditingController(text: e?['description'] as String? ?? '');
    _location = TextEditingController(text: e?['location'] as String? ?? '');
    _capacity =
        TextEditingController(text: e?['max_capacity']?.toString() ?? '');
    _price = TextEditingController(
        text: ((e?['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
    _date = DateTime.tryParse(e?['event_date'] as String? ?? '') ??
        DateTime.now().add(const Duration(days: 7));
    _isFree = e?['is_free'] as bool? ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _location.dispose();
    _capacity.dispose();
    _price.dispose();
    super.dispose();
  }

  /// The topmost route on [navigator] (the predicate is asked of it first,
  /// and answering true pops nothing).
  static Route<dynamic>? _topOf(NavigatorState navigator) {
    Route<dynamic>? top;
    navigator.popUntil((r) {
      top = r;
      return true;
    });
    return top;
  }

  /// [open] pushes one picker; that route is handed to the sheet holding this
  /// editor ([_OwnedSheetState._ownRoute]) at once — before it is ever built
  /// (no frame runs in a hidden tab) — so it is closed with the sheet (RM-2,
  /// C15-63a-01). Only the route [open] itself pushed: a dialog route that
  /// was not on top before and is on top right after.
  Future<T?> _ownPicker<T>(Future<T?> Function() open) {
    final sheet = context.findAncestorStateOfType<_OwnedSheetState>();
    // Both pickers go on the root navigator (their default).
    final navigator = Navigator.of(context, rootNavigator: true);
    final before = _topOf(navigator);
    final shown = open();
    final picker = _topOf(navigator);
    if (sheet != null &&
        picker is DialogRoute &&
        !identical(picker, before)) {
      sheet._ownRoute(picker);
      shown.whenComplete(() => sheet._opened.remove(picker));
    }
    return shown;
  }

  Future<void> _pickDate() async {
    final d = await _ownPicker(() => showDatePicker(
          context: context,
          initialDate: _date,
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 730)),
        ));
    if (d == null) return;
    if (!mounted) return;
    final t = await _ownPicker(() => showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_date)));
    if (!mounted) return;
    setState(() {
      _date = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: _border)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: _border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(widget.existing == null ? 'New Event' : 'Edit Event',
                  style: const TextStyle(
                      color: _white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              _field('Title', _title, hint: 'e.g. Saturday Bootcamp'),
              _field('Description', _desc, hint: 'What is it about?', maxLines: 2),
              _field('Location', _location, hint: 'Venue / address'),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.event, color: _brand, size: 18),
                    const SizedBox(width: 10),
                    Text(_fmtDate(_date.toIso8601String()),
                        style: const TextStyle(color: _white)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _field('Capacity (optional)', _capacity,
                  keyboard: TextInputType.number, hint: 'Max attendees'),
              Row(children: [
                const Text('Free event',
                    style: TextStyle(color: _muted, fontSize: 13)),
                const Spacer(),
                Switch(
                  value: _isFree,
                  activeThumbColor: _brand,
                  onChanged: (v) => setState(() => _isFree = v),
                ),
              ]),
              if (!_isFree)
                _field('Price (\$)', _price, keyboard: TextInputType.number),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (_title.text.trim().isEmpty) return;
                    Navigator.pop(context, {
                      'title': _title.text.trim(),
                      'description': _desc.text.trim(),
                      'location': _location.text.trim(),
                      'event_date': _date.toIso8601String(),
                      'max_capacity': int.tryParse(_capacity.text.trim()),
                      'is_free': _isFree,
                      'price': _isFree
                          ? 0
                          : (double.tryParse(_price.text.trim()) ?? 0),
                      'status': 'upcoming',
                    });
                  },
                  child: Text(
                      widget.existing == null ? 'Create event' : 'Save changes',
                      style: const TextStyle(
                          color: _white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _field(String label, TextEditingController c,
    {String? hint, int maxLines = 1, TextInputType? keyboard}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          maxLines: maxLines,
          keyboardType: keyboard,
          style: const TextStyle(color: _white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF6B6478)),
            isDense: true,
            filled: true,
            fillColor: _bg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _brand),
            ),
          ),
        ),
      ],
    ),
  );
}
