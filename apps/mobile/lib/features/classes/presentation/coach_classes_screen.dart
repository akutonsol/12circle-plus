import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/theme/app_background.dart';
import '../data/models/class_model.dart';
import '../domain/class_provider.dart';
import 'create_class_screen.dart';

/// Coach: manage the group classes they offer — list, add, and cancel.
class CoachClassesScreen extends ConsumerWidget {
  const CoachClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(myCreatedClassesProvider);
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.white),
          title: const Text('My Classes',
              style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.purple,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('New Class', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          onPressed: () async {
            final created = await Navigator.push<bool>(context,
                MaterialPageRoute(builder: (_) => const CreateClassScreen()));
            if (created == true) ref.read(refreshClassesProvider.notifier).state++;
          },
        ),
        body: classesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.purple)),
          error: (e, _) => Center(child: Text('Could not load classes.',
              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary))),
          data: (classes) {
            if (classes.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('🧘', style: TextStyle(fontSize: 44)),
                  SizedBox(height: 12),
                  Text('No classes yet',
                      style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text('Tap “New Class” to offer an online group call or an in-person class.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ])));
            }
            return RefreshIndicator(
              onRefresh: () async => ref.read(refreshClassesProvider.notifier).state++,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: classes.length,
                itemBuilder: (_, i) => _ClassRow(c: classes[i], ref: ref),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ClassRow extends StatelessWidget {
  final FitnessClass c;
  final WidgetRef ref;
  const _ClassRow({required this.c, required this.ref});

  @override
  Widget build(BuildContext context) {
    final priceLabel = (c.price == null || c.price == 0) ? 'Free' : '\$${c.price!.toStringAsFixed(0)}';
    final when = '${c.startTime.day}/${c.startTime.month} · '
        '${c.startTime.hour.toString().padLeft(2, '0')}:${c.startTime.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceDarkElevated),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(c.isVirtual ? Icons.videocam_outlined : Icons.location_on_outlined,
              color: c.isVirtual ? const Color(0xFF60A5FA) : AppColors.purple, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(c.title,
              style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w700))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: priceLabel == 'Free'
                  ? AppColors.success.withValues(alpha: 0.15)
                  : AppColors.purple.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20)),
            child: Text(priceLabel, style: TextStyle(
                color: priceLabel == 'Free' ? AppColors.success : AppColors.purple,
                fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.schedule_rounded, color: AppColors.textTertiary, size: 14),
          const SizedBox(width: 4),
          Text(when, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(width: 12),
          Icon(c.isVirtual ? Icons.public : Icons.people_outline, color: AppColors.textTertiary, size: 14),
          const SizedBox(width: 4),
          Text(c.isVirtual ? 'Online · unlimited' : '${c.bookedCount}/${c.capacity} booked',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _confirmCancel(context),
            icon: const Icon(Icons.cancel_outlined, color: AppColors.error, size: 16),
            label: const Text('Cancel', style: TextStyle(color: AppColors.error, fontSize: 13)),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
        ),
      ]),
    );
  }

  void _confirmCancel(BuildContext context) {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Cancel class?', style: TextStyle(color: AppColors.white, fontSize: 16)),
        content: Text('“${c.title}” will be removed from listings and any registered members freed up.',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx),
              child: const Text('Keep', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () async {
              Navigator.pop(dctx);
              await ref.read(liveClassServiceProvider).cancelClass(c.id);
              ref.read(refreshClassesProvider.notifier).state++;
            },
            child: const Text('Cancel class', style: TextStyle(color: AppColors.error))),
        ]),
    );
  }
}
