import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/observability/app_failure.dart';
import '../../../shared/theme/app_background.dart';
import '../../auth/domain/auth_provider.dart';
import '../../nutrition/domain/nutrition_provider.dart' show ownRead;
import '../../workout/presentation/widgets/section_load_failure.dart'
    show couldntMessage;
import '../data/models/action_item.dart';
import '../domain/action_item_provider.dart';
import '../../../core/widgets/back_leading.dart';

/// Client-facing "Action Center" — the tasks the coach (or AI) assigned.
class ActionCenterScreen extends ConsumerWidget {
  const ActionCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The rows are redrawn for whoever is signed in, whatever the read is doing.
    ref.watch(currentUserProvider.select((u) => u?.id));
    final own = ownRead(ref.watch(myActionItemsProvider));
    // Theirs is kept through a refresh that fails, and that is said.
    ref.listen(myActionItemsProvider, (_, next) {
      final now = ownRead(next);
      final e = now.error;
      if (e == null || now.value == null || now.busy || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(couldntMessage('refresh your action items', e))));
    });
    return AppGradientBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: backLeading(context),
        title: const Text('Action Items',
            style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      body: switch (own.value) {
        null when own.error == null => const Center(
            child: CircularProgressIndicator(color: AppColors.purple)),
        null => const Center(
            child: Text('Could not load your action items',
                style: TextStyle(color: AppColors.textTertiary))),
        final items => Builder(builder: (_) {
          if (items.isEmpty) return const _EmptyState();
          final pending = items.where((i) => !i.isCompleted).toList();
          final completed = items.where((i) => i.isCompleted).toList();
          final overdue = pending.where((i) => i.isOverdue).toList();
          final active = pending.where((i) => !i.isOverdue).toList();
          final rate = items.isEmpty ? 0.0 : completed.length / items.length;

          return RefreshIndicator(
            color: AppColors.purple,
            onRefresh: () async => ref.invalidate(myActionItemsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _ProgressHeader(
                    completed: completed.length, total: items.length, rate: rate),
                if (overdue.isNotEmpty) ...[
                  const _SectionLabel('⚠️  Overdue', AppColors.error),
                  ...overdue.map((i) => _ActionTile(item: i)),
                ],
                if (active.isNotEmpty) ...[
                  const _SectionLabel('To Do', AppColors.purple),
                  ...active.map((i) => _ActionTile(item: i)),
                ],
                if (completed.isNotEmpty) ...[
                  const _SectionLabel('Completed', AppColors.success),
                  ...completed.map((i) => _ActionTile(item: i)),
                ],
              ],
            ),
          );
        }),
      },
    ));
  }
}

class _ProgressHeader extends StatelessWidget {
  final int completed, total;
  final double rate;
  const _ProgressHeader(
      {required this.completed, required this.total, required this.rate});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.purple.withValues(alpha: 0.25),
          AppColors.purple.withValues(alpha: 0.08)
        ]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
              value: rate,
              strokeWidth: 6,
              backgroundColor: AppColors.surfaceDarkElevated,
              valueColor: const AlwaysStoppedAnimation(AppColors.purple),
            ),
            Text('${(rate * 100).round()}%',
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Today's Progress",
                style: TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('$completed of $total action items complete',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, this.color);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      );
}

class _ActionTile extends ConsumerWidget {
  final ActionItem item;
  const _ActionTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: item.isOverdue
                ? AppColors.error.withValues(alpha: 0.4)
                : AppColors.surfaceDarkElevated),
      ),
      child: Row(children: [
        Text(item.emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title,
                style: TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration:
                        item.isCompleted ? TextDecoration.lineThrough : null)),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
            const SizedBox(height: 4),
            Text(
                item.isOverdue
                    ? 'Overdue'
                    : item.dueDate != null
                        ? 'Due ${item.dueDate!.month}/${item.dueDate!.day}'
                        : '+${item.points} pts',
                style: TextStyle(
                    color: item.isOverdue
                        ? AppColors.error
                        : AppColors.textTertiary,
                    fontSize: 11)),
          ]),
        ),
        GestureDetector(
          onTap: () => _toggle(context, ref),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.isCompleted
                  ? AppColors.success
                  : Colors.transparent,
              border: Border.all(
                  color: item.isCompleted
                      ? AppColors.success
                      : AppColors.textTertiary,
                  width: 2),
            ),
            child: item.isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        ),
      ]),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final auth = Supabase.instance.client.auth;
    final svc = ref.read(actionItemServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    // The tile can be gone (the list re-read, or another member's) by the time
    // this answers; the container is not.
    final container = ProviderScope.containerOf(context, listen: false);
    // The member whose task this is. A tile still up is not anyone else's.
    final owner = item.clientId;
    if (auth.currentUser?.id != owner) {
      reportError('ActionCenter.identity',
          StateError('action item: the signed-in account changed'));
      return;
    }
    final reopening = item.isCompleted;
    String? failed;
    try {
      final saved = reopening
          ? await svc.reopen(item.id)
          : await svc.completeActionItem(item.id);
      if (!saved) {
        failed = "Couldn't ${reopening ? 'reopen that action item' : 'mark that '
            'action item done'} — it may already have changed. Pull down to "
            'refresh.';
      }
    } catch (e, st) {
      reportError('ActionCenter.toggle', e, st);
      failed = couldntMessage(
          reopening ? 'reopen that action item' : 'mark that action item done',
          e);
    }
    // Another member's by now: theirs to read, and nothing to say to them.
    if (auth.currentUser?.id != owner) return;
    try {
      container.invalidate(myActionItemsProvider);
    } on StateError {
      // Disposed (the same member signed out and in again meanwhile): nothing
      // of it is drawn any more, and its successor reads for itself.
    }
    if (failed != null && messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.checklist_rounded,
              color: AppColors.purple.withValues(alpha: 0.4), size: 56),
          const SizedBox(height: 16),
          const Text('No action items yet',
              style: TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Your coach will assign tasks here.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
        ]),
      );
}
