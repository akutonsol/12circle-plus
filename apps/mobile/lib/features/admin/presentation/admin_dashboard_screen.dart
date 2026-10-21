import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/admin_provider.dart';
import '../data/platform_settings_service.dart';

const _bg       = Color(0xFF030303);
const _card     = Color(0xFF0E0B16);
const _border   = Color(0xFF1A1020);
const _brand    = Color(0xFFA855F7);
const _white    = Colors.white;
const _muted    = Color(0xFFCFC2D6);
const _mint     = Color(0xFF6FFBBE);
const _lilac    = Color(0xFFDDB7FF);
const _blue     = Color(0xFFADC6FF);
const _amber    = Color(0xFFFFD479);

/// Module 25 — Admin Dashboard. Org-wide platform oversight for role='admin'.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(platformStatsProvider);
    final usersAsync = ref.watch(recentUsersProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final wide = w >= 900;
            final cols = w >= 1200 ? 4 : (w >= 640 ? 3 : 2);

            final statsSection = statsAsync.when(
              loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child:
                      Center(child: CircularProgressIndicator(color: _brand))),
              error: (e, _) => _errorCard(e),
              data: (stats) => _StatsGrid(stats: stats, crossAxisCount: cols),
            );

            final membersSection = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Newest Members',
                    style: TextStyle(
                        color: _white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                usersAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (users) => users.isEmpty
                      ? const Text('No members yet.',
                          style: TextStyle(color: _muted))
                      : Column(
                          children:
                              users.map((u) => _UserRow(user: u)).toList()),
                ),
              ],
            );

            return RefreshIndicator(
              color: _brand,
              backgroundColor: _card,
              onRefresh: () async {
                ref.invalidate(platformStatsProvider);
                ref.invalidate(recentUsersProvider);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                    horizontal: wide ? 32 : 16, vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(context),
                        const SizedBox(height: 20),
                        _CommissionCard(),
                        const SizedBox(height: 16),
                        // V5 §167 · the way in to the owner-approved metric
                        // surfaces (migrations 171-174). A route with no entry
                        // point is not UI consumption, which ROUTE-G1 caught when
                        // /admin-metrics was first registered.
                        // V5 §183 · the way in to Trust. ROUTE-G1 fails on a route
                        // with no entry point, and it is right to.
                        _AdminActionTile(
                          icon: Icons.settings_outlined,
                          title: 'Settings',
                          subtitle: 'Administrators, roles & permissions, platform',
                          onTap: () => context.push('/admin-settings'),
                        ),
                        const SizedBox(height: 12),
                        _AdminActionTile(
                          icon: Icons.people_outline,
                          title: 'People',
                          subtitle: 'Users, coaches, clients, wellness partners',
                          onTap: () => context.push('/admin-people'),
                        ),
                        const SizedBox(height: 12),
                        _AdminActionTile(
                          icon: Icons.build_outlined,
                          title: 'Operations',
                          subtitle: 'Releases, integrations, system events',
                          onTap: () => context.push('/admin-operations'),
                        ),
                        const SizedBox(height: 12),
                        _AdminActionTile(
                          icon: Icons.hub_outlined,
                          title: 'Ecosystem',
                          subtitle: 'Community, events, training, monetization, wearables',
                          onTap: () => context.push('/admin-ecosystem'),
                        ),
                        const SizedBox(height: 12),
                        _AdminActionTile(
                          icon: Icons.verified_user_outlined,
                          title: 'Trust',
                          subtitle: 'AI Guardian, security, incidents, audit logs',
                          onTap: () => context.push('/admin-trust'),
                        ),
                        const SizedBox(height: 12),
                        _AdminActionTile(
                          icon: Icons.query_stats_rounded,
                          title: 'Platform Metrics',
                          subtitle: 'Activity, people, community, events, revenue, release',
                          onTap: () => context.push('/admin-metrics'),
                        ),
                        const SizedBox(height: 12),
                        _AdminActionTile(
                          icon: Icons.rule_folder_rounded,
                          title: 'Global Library Review',
                          subtitle: 'Approve or reject coach exercise submissions',
                          onTap: () => context.push('/admin-exercise-review'),
                        ),
                        const SizedBox(height: 12),
                        _AdminActionTile(
                          icon: Icons.auto_awesome_rounded,
                          title: 'Exercise Content Center',
                          subtitle: 'AI-enrich instructions, cues & media for the library',
                          onTap: () => context.push('/content-center'),
                        ),
                        const SizedBox(height: 12),
                        _AdminActionTile(
                          icon: Icons.insights_rounded,
                          title: 'Coaching Observability',
                          subtitle: 'Is the platform delivering coaching value?',
                          onTap: () => context.push('/observability'),
                        ),
                        const SizedBox(height: 24),
                        if (wide)
                          // Desktop: stats on the left, members panel on the right.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: statsSection),
                              const SizedBox(width: 24),
                              Expanded(flex: 2, child: membersSection),
                            ],
                          )
                        else ...[
                          statsSection,
                          const SizedBox(height: 28),
                          membersSection,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1A4E), Color(0xFF160E26), _card],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_brand, Color(0xFF6D28D9)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: _brand.withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 3))
              ],
            ),
            child: const Icon(Icons.shield_moon_rounded, color: _white),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Admin Console',
                    style: TextStyle(
                        color: _white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Platform health at a glance',
                    style: TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout_rounded, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(Object e) {
    // ERR-2: the exception is PARSED here and deliberately not displayed. The
    // card used to end `'Could not load platform stats.\n$e'`, and the
    // `denied` branch exists precisely because non-admins reach this screen —
    // so any error that was NOT 42501 showed raw Postgres text, table and
    // column names included, to exactly the audience that branch is for.
    final denied = '$e'.toLowerCase().contains('not authorized') ||
        '$e'.contains('42501');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Text(
        denied
            ? 'This account is not an admin. Admin tools are restricted.'
            : 'Could not load platform stats.',
        style: const TextStyle(color: _muted, height: 1.4),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final Map<String, dynamic> stats;
  final int crossAxisCount;
  const _StatsGrid({required this.stats, this.crossAxisCount = 2});

  int _v(String k) => (stats[k] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _Stat('Total Users', _v('total_users'), Icons.people_alt_rounded, _brand),
      _Stat('Coaches', _v('coaches'), Icons.sports_rounded, _lilac),
      _Stat('Clients', _v('clients'), Icons.person_rounded, _mint),
      _Stat('New this week', _v('new_signups_week'), Icons.trending_up_rounded, _amber),
      _Stat('Active Coaching', _v('active_relationships'), Icons.handshake_rounded, _blue),
      _Stat('Programs', _v('programs_created'), Icons.library_books_rounded, _lilac),
      _Stat('Assigned Plans', _v('active_assignments'), Icons.assignment_turned_in_rounded, _mint),
      _Stat('Workouts Logged', _v('workouts_logged'), Icons.fitness_center_rounded, _brand),
      _Stat('Check-ins (wk)', _v('checkins_week'), Icons.fact_check_rounded, _amber),
      _Stat('Challenges', _v('total_challenges'), Icons.emoji_events_rounded, _lilac),
      _Stat('Events', _v('total_events'), Icons.event_rounded, _blue),
      _Stat('Vendors', _v('vendors'), Icons.storefront_rounded, _mint),
    ];
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: tiles.map((t) => _StatCard(stat: t)).toList(),
    );
  }
}

class _Stat {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  _Stat(this.label, this.value, this.icon, this.color);
}

class _AdminActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _AdminActionTile({
    required this.icon, required this.title,
    required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _brand.withValues(alpha: 0.22)),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: _brand, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: _muted),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final _Stat stat;
  const _StatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [stat.color.withValues(alpha: 0.13), _card],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: stat.color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(stat.icon, color: stat.color, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${stat.value}',
                  style: const TextStyle(
                      color: _white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              Text(stat.label,
                  style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final Map<String, dynamic> user;
  const _UserRow({required this.user});

  Color _roleColor(String role) => switch (role) {
        'coach' => _lilac,
        'admin' => _brand,
        'vendor' => _mint,
        _ => _blue,
      };

  @override
  Widget build(BuildContext context) {
    final name =
        '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
    final role = (user['role'] as String?) ?? 'client';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _roleColor(role).withValues(alpha: 0.18),
            child: Text(initial,
                style: TextStyle(
                    color: _roleColor(role), fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'Unnamed' : name,
                    style: const TextStyle(
                        color: _white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(user['email'] as String? ?? '',
                    style: const TextStyle(color: _muted, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _roleColor(role).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(role,
                style: TextStyle(
                    color: _roleColor(role),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// Admin: view + change the marketplace commission rate (stored in platform_settings).
class _CommissionCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(marketplaceCommissionProvider).valueOrNull ?? 0.10;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1A1020)),
      ),
      child: Row(children: [
        const Icon(Icons.percent_rounded, color: _brand, size: 26),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('MARKETPLACE COMMISSION',
              style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text('${(rate * 100).toStringAsFixed(1)}% on marketplace-acquired coaching sales',
              style: const TextStyle(color: _white, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          const Text('Coach-invited clients are always 0%.',
              style: TextStyle(color: _muted, fontSize: 11)),
        ])),
        TextButton(
          onPressed: () => _editCommission(context, ref, rate),
          child: const Text('Edit', style: TextStyle(color: _brand, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  void _editCommission(BuildContext context, WidgetRef ref, double current) {
    double pct = (current * 100).clamp(0, 50);
    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(builder: (dctx, setSt) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Marketplace Commission', style: TextStyle(color: _white, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${pct.toStringAsFixed(1)}%',
              style: const TextStyle(color: _brand, fontSize: 32, fontWeight: FontWeight.w900)),
          Slider(value: pct, min: 0, max: 50, divisions: 100, activeColor: _brand,
              label: '${pct.toStringAsFixed(1)}%', onChanged: (v) => setSt(() => pct = v)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx),
              child: const Text('Cancel', style: TextStyle(color: _muted))),
          TextButton(
            onPressed: () async {
              final ok = await ref.read(platformSettingsServiceProvider)
                  .setMarketplaceCommission(pct / 100.0);
              if (dctx.mounted) Navigator.pop(dctx);
              if (ok) ref.invalidate(marketplaceCommissionProvider);
            },
            child: const Text('Save', style: TextStyle(color: _brand, fontWeight: FontWeight.w700))),
        ],
      )),
    );
  }
}
