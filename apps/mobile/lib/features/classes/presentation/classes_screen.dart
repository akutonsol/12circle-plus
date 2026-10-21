import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/named_icon_button.dart';
import '../../../shared/theme/app_background.dart';
import '../../auth/domain/auth_provider.dart';
import '../domain/class_provider.dart';
import 'create_class_screen.dart';
import 'whats_on_view.dart';

/// FIT-027 · "What's on" — `/classes · /events · /challenges under one list`.
///
/// ── WHAT THIS REPLACED ─────────────────────────────────────────────────────
/// Three tabs (Schedule / My Bookings / Live) over classes alone, while
/// `/events` and `/challenges` lived on their own routes. F-14 recorded those
/// two as stranded once the bottom nav went to five tabs; this is the anchor
/// that unstrands them.
///
/// ── WHAT WAS KEPT, AND WHY IT IS RECORDED RATHER THAN DROPPED ──────────────
/// FIT-027 does not draw a coach's "New Class" affordance. It also does not
/// draw a Bookings tab — but a booked class is still a class, so it appears in
/// the one list carrying "Booked", which is what "under one list" means.
///
/// The FAB is a different case: removing it would take away a coach's only way
/// to create a class. A locked screen not drawing something is not the same as
/// the design saying to delete it, so the FAB stays and the discrepancy is
/// recorded as **OD-15** rather than resolved by guessing.
class ClassesScreen extends ConsumerWidget {
  const ClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Coach-only affordance — see OD-15 above. `.valueOrNull` here is the read
    // that was already in this file; it is not a new one, so EC-G8 is unmoved.
    final isCoach =
        ref.watch(currentUserProfileProvider).valueOrNull?['role'] == 'coach';

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: isCoach
            ? FloatingActionButton.extended(
                backgroundColor: AppColors.purple,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('New Class',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                onPressed: () async {
                  final created = await Navigator.push<bool>(context,
                      MaterialPageRoute(builder: (_) => const CreateClassScreen()));
                  if (created == true) {
                    ref.read(refreshClassesProvider.notifier).state++;
                  }
                },
              )
            : null,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 20, 12),
              child: Row(children: [
                // FIT-027 declares a "Back" control. The word is the package's
                // own (138 declarations).
                NamedIconButton(
                  label: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Icon(Icons.arrow_back,
                      color: AppColors.white, size: 20),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text("What's on",
                      style: TextStyle(
                          color: AppColors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                ),
              ]),
            ),
            const Expanded(child: WhatsOnView()),
          ]),
        ),
      ),
    );
  }
}
