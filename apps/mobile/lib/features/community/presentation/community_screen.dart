import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/theme/app_background.dart';
import '../../../core/animations/app_animations.dart';
import '../domain/community_provider.dart';
import '../domain/post_type_choice.dart';
import 'widgets/create_post_sheet.dart';
import 'widgets/post_card.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height + 8;
  @override
  double get maxExtent => tabBar.preferredSize.height + 8;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.bgDark,
      padding: const EdgeInsets.only(bottom: 8),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) => tabBar != oldDelegate.tabBar;
}

class _CommunityScreenState extends ConsumerState<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _postController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _postController.dispose();
    super.dispose();
  }

  void _showCreatePost() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // FIT-067. The sheet's body is its own widget now: the chosen post type
      // needs state, and a `setState` here does not rebuild what
      // `showModalBottomSheet` has already handed to the overlay.
      builder: (_) => CreatePostSheet(
        onPost: (content, type) {
          // The type was never passed, so every post this app wrote went in
          // as the default 'general' whatever the user tapped.
          ref
              .read(postNotifierProvider.notifier)
              .addPost(content, postType: postTypeWire(type));
          AppAnimations.hapticSuccess();
        },
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(postNotifierProvider);
    final groups = ref.watch(groupNotifierProvider);

    return AppGradientBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Community', style: TextStyle(color: AppColors.white, fontSize: 28, fontWeight: FontWeight.bold))
                            .fadeSlideIn(),
                        ElevatedButton.icon(
                          onPressed: _showCreatePost,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Post'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(90, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                        ).fadeIn(delay: 200.ms),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _showCreatePost,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.surfaceDarkElevated),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.purple,
                              child: Icon(Icons.person, color: AppColors.white, size: 14),
                            ),
                            const SizedBox(width: 12),
                            const Text('Share your progress or motivation...', style: TextStyle(color: AppColors.textTertiary, fontSize: 14)),
                            const Spacer(),
                            const Icon(Icons.photo_camera_outlined, color: AppColors.purple, size: 20),
                          ],
                        ),
                      ),
                    ).fadeSlideIn(delay: 200.ms),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              floating: true,
              delegate: _StickyTabBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.purple,
                  labelColor: AppColors.white,
                  unselectedLabelColor: AppColors.textTertiary,
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: const [
                    Tab(text: 'Feed'),
                    Tab(text: 'Groups'),
                    Tab(text: 'Members'),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              postsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.purple)),
                error: (e, _) => Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.error_outline, color: AppColors.textTertiary, size: 48),
                    const SizedBox(height: 12),
                    Text('Could not load posts', style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(e.toString(), style: const TextStyle(color: AppColors.textTertiary, fontSize: 12), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.read(postNotifierProvider.notifier).reload(),
                      child: const Text('Retry'),
                    ),
                  ])),
                data: (posts) => posts.isEmpty
                  ? const Center(child: Text('No posts yet. Be the first to share!',
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 14)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: posts.length,
                      itemBuilder: (context, index) => PostCard(post: posts[index], index: index),
                    ),
              ),
              ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  ...groups.map((group) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.surfaceDarkElevated),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.purple.withValues(alpha:0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(child: Text(group.emoji, style: const TextStyle(fontSize: 24))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(group.name, style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(group.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text('${group.memberCount} members', style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            ref.read(groupNotifierProvider.notifier).toggleJoin(group.id);
                            AppAnimations.hapticLight();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: group.isJoined ? AppColors.surfaceDarkElevated : AppColors.purple,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              group.isJoined ? 'Joined' : 'Join',
                              style: TextStyle(
                                color: group.isJoined ? AppColors.textSecondary : AppColors.white,
                                fontSize: 13, fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate(delay: Duration(milliseconds: groups.indexOf(group) * 80))
                      .fadeIn(duration: 400.ms)
                      .slideX(begin: -0.2, end: 0, duration: 400.ms)),
                ],
              ),
              _MembersTab(),
            ],
          ),
        ),
      ),
    ));
  }
}

// ── Members Tab ───────────────────────────────────────────────────────────────
class _MembersTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(liveMembersProvider);
    return membersAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.purple)),
      error: (_, __) => const Center(
        child: Text('Could not load members',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 14))),
      data: (members) {
        if (members.isEmpty) {
          return const Center(
            child: Text('No members yet.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 14)));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          itemCount: members.length,
          itemBuilder: (context, i) {
            final m = members[i];
            final fn = m['first_name'] as String? ?? '';
            final ln = m['last_name'] as String? ?? '';
            final name = '$fn $ln'.trim().isEmpty ? 'Member' : '$fn $ln'.trim();
            final role = m['role'] as String? ?? 'client';
            final initials = '${fn.isEmpty ? '?' : fn[0]}${ln.isEmpty ? '' : ln[0]}'.toUpperCase();
            final isCoach = role == 'coach';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceDarkElevated)),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCoach
                        ? AppColors.purple.withValues(alpha: 0.3)
                        : AppColors.purple.withValues(alpha: 0.15)),
                  child: Center(
                    child: Text(initials,
                      style: TextStyle(
                        color: isCoach ? Colors.white : AppColors.purple,
                        fontSize: 16, fontWeight: FontWeight.w700)))),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                    style: const TextStyle(
                      color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(isCoach ? 'Coach' : 'Member',
                    style: TextStyle(
                      color: isCoach ? AppColors.purple : AppColors.textTertiary,
                      fontSize: 12)),
                ])),
                if (isCoach)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20)),
                    child: const Text('COACH',
                      style: TextStyle(
                        color: AppColors.purple,
                        fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
              ]),
            ).animate(delay: Duration(milliseconds: i * 40))
                .fadeIn(duration: 300.ms)
                .slideY(begin: 0.15, end: 0, duration: 300.ms, curve: Curves.easeOut);
          },
        );
      },
    );
  }
}
