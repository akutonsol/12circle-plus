import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/animations/app_animations.dart';
import '../domain/class_provider.dart';
import 'widgets/cancel_booking_control.dart';

class ClassDetailScreen extends ConsumerWidget {
  const ClassDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fitnessClass = ref.watch(selectedClassProvider);
    if (fitnessClass == null) {
      return const Scaffold(backgroundColor: AppColors.bgDark,
          body: Center(child: Text('No class selected', style: TextStyle(color: AppColors.white))));
    }

    final service = ref.watch(classServiceProvider);
    final emoji = service.getCategoryEmoji(fitnessClass.category);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.bgDark,
            expandedHeight: 220,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.white),
              tooltip: 'Back',
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.purple.withValues(alpha: 0.8), AppColors.bgDark],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Text(emoji, style: const TextStyle(fontSize: 56))
                          .animate().scale(duration: 400.ms, curve: Curves.elasticOut),
                      const SizedBox(height: 8),
                      if (fitnessClass.isLive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(20)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, color: Colors.white, size: 8),
                              SizedBox(width: 6),
                              Text('LIVE NOW', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(duration: 800.ms),
                      const SizedBox(height: 8),
                      Text(fitnessClass.title,
                          style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      Text(fitnessClass.instructor.name,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildStat(_formatTime(fitnessClass.startTime), Icons.access_time),
                      const SizedBox(width: 12),
                      _buildStat('${fitnessClass.durationMinutes} min', Icons.timer_outlined),
                      // Online group calls are unlimited — only show seats for in-person.
                      if (!fitnessClass.isVirtual) ...[
                        const SizedBox(width: 12),
                        _buildStat('${fitnessClass.spotsLeft} left', Icons.people_outline),
                      ] else ...[
                        const SizedBox(width: 12),
                        _buildStat('Online', Icons.videocam_outlined),
                      ],
                    ],
                  ).animate(delay: 200.ms).fadeIn(duration: 400.ms),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_outline, color: AppColors.purple, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fitnessClass.instructor.name,
                              style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                          Text(fitnessClass.instructor.role,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Color(0xFFFFD700), size: 16),
                          const SizedBox(width: 4),
                          Text('${fitnessClass.instructor.rating}',
                              style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ).animate(delay: 300.ms).fadeIn(duration: 400.ms),
                  const SizedBox(height: 20),
                  const Text('About', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(fitnessClass.description,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.6))
                      .animate(delay: 400.ms).fadeIn(duration: 400.ms),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: AppColors.textTertiary, size: 16),
                      const SizedBox(width: 6),
                      Text(fitnessClass.location,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                      if (fitnessClass.isVirtual) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF60A5FA).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Virtual Class',
                              style: TextStyle(color: Color(0xFF60A5FA), fontSize: 11)),
                        ),
                      ],
                    ],
                  ).animate(delay: 500.ms).fadeIn(duration: 400.ms),
                  // Online meeting link — revealed only to registered users.
                  if (fitnessClass.isVirtual) ...[
                    const SizedBox(height: 12),
                    if (fitnessClass.isBooked && (fitnessClass.streamUrl?.isNotEmpty ?? false))
                      GestureDetector(
                        onTap: () => launchUrl(Uri.parse(fitnessClass.streamUrl!),
                            mode: LaunchMode.externalApplication),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF60A5FA).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF60A5FA).withValues(alpha: 0.4)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.videocam, color: Color(0xFF60A5FA), size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(fitnessClass.streamUrl!,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 13, fontWeight: FontWeight.w600))),
                            const Icon(Icons.open_in_new, color: Color(0xFF60A5FA), size: 16),
                          ]),
                        ),
                      )
                    else
                      Row(children: const [
                        Icon(Icons.lock_outline, color: AppColors.textTertiary, size: 14),
                        SizedBox(width: 6),
                        Text('Register to get the meeting link',
                            style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                      ]),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: fitnessClass.tags.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.surfaceDarkElevated),
                      ),
                      child: Text(tag, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    )).toList(),
                  ).animate(delay: 600.ms).fadeIn(duration: 400.ms),
                  const SizedBox(height: 20),
                  // Capacity bar only matters for in-person classes (limited seats).
                  if (!fitnessClass.isVirtual)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.surfaceDarkElevated),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Capacity', style: TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                              Text('${fitnessClass.bookedCount}/${fitnessClass.capacity}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: fitnessClass.fillPercent,
                              backgroundColor: AppColors.surfaceDarkElevated,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                fitnessClass.isFull ? AppColors.error : AppColors.success,
                              ),
                              minHeight: 10,
                            ),
                          ),
                          if (fitnessClass.isFull) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.schedule, color: AppColors.warning, size: 14),
                                const SizedBox(width: 6),
                                Text('${fitnessClass.waitlistCount} people on waitlist',
                                    style: const TextStyle(color: AppColors.warning, fontSize: 12)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ).animate(delay: 700.ms).fadeIn(duration: 400.ms),
                  const SizedBox(height: 24),
                  if (fitnessClass.isBooked) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.qr_code, color: AppColors.success, size: 32),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('You\'re booked!', style: TextStyle(color: AppColors.success, fontSize: 15, fontWeight: FontWeight.w600)),
                                Text('Show QR code at check-in', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              minimumSize: const Size(80, 36),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: const Text('QR Code', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ).animate(delay: 800.ms).fadeIn(duration: 400.ms).scaleIn(),
                    const SizedBox(height: 12),
                    // FIT-088. This was a single unguarded tap: it cancelled,
                    // refreshed and popped, with no confirmation on an action
                    // that hands the seat to the next person on the waitlist,
                    // and no failure path at all.
                    CancelBookingControl(
                      onCancel: () => ref
                          .read(liveClassServiceProvider)
                          .cancelBooking(fitnessClass.id),
                      onCancelled: () {
                        ref.read(refreshClassesProvider.notifier).state++;
                        if (context.mounted) context.pop();
                      },
                    ),
                  ] else if (fitnessClass.isWaitlisted) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.schedule, color: AppColors.warning, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('You\'re on the waitlist', style: TextStyle(color: AppColors.warning, fontSize: 15, fontWeight: FontWeight.w600)),
                                Text('We\'ll notify you if a spot opens', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    ElevatedButton(
                      onPressed: () async {
                        await ref.read(liveClassServiceProvider).bookClass(fitnessClass.id);
                        AppAnimations.hapticSuccess();
                        ref.read(refreshClassesProvider.notifier).state++;
                        if (context.mounted) context.pop();
                      },
                      style: ElevatedButton.styleFrom(
                        // Virtual classes are unlimited → always a straight register.
                        backgroundColor: (!fitnessClass.isVirtual && fitnessClass.isFull)
                            ? AppColors.warning : AppColors.purple,
                      ),
                      child: Text((!fitnessClass.isVirtual && fitnessClass.isFull)
                          ? 'Join Waitlist'
                          : (fitnessClass.isVirtual ? 'Register' : 'Book Class')),
                    ).animate(delay: 800.ms).fadeIn(duration: 400.ms),
                  ],
                  if (fitnessClass.isLive && fitnessClass.isBooked && fitnessClass.isVirtual)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: ElevatedButton.icon(
                        onPressed: (fitnessClass.streamUrl?.isNotEmpty ?? false)
                            ? () => launchUrl(Uri.parse(fitnessClass.streamUrl!),
                                mode: LaunchMode.externalApplication)
                            : null,
                        icon: const Icon(Icons.videocam, size: 18),
                        label: const Text('Join Live Class'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                      ).animate(onPlay: (c) => c.repeat(reverse: true))
                          .shimmer(duration: 1500.ms, color: Colors.white24),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceDarkElevated),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.purple, size: 18),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: AppColors.white, fontSize: 12, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final isToday = time.day == now.day && time.month == now.month;
    final isTomorrow = time.day == now.day + 1 && time.month == now.month;
    final prefix = isToday ? 'Today' : isTomorrow ? 'Tomorrow' : '${time.day}/${time.month}';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$prefix $hour:$minute';
  }
}
