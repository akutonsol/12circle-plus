import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/coach_relationship_service.dart';
import '../domain/coach_provider.dart';
import '../../auth/domain/auth_provider.dart';
import '../../../shared/theme/app_background.dart';
import '../domain/package_provider.dart';
import 'choose_package_screen.dart';

const _bg    = Color(0xFF030303);
const _card  = Color(0xFF0E0B16);
const _brd   = Color(0xFF1A1020);
const _brand = Color(0xFFA855F7);
const _pri   = Color(0xFFDDB7FF);
const _tert  = Color(0xFF6FFBBE);
const _wht   = Colors.white;
const _mut   = Color(0xFFCFC2D6);
const _err   = Color(0xFFFFB4AB);

// ── Providers ─────────────────────────────────────────────────────────────────
final _relSvc = CoachRelationshipService();

final coachMarketplaceProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = Supabase.instance.client;
  // Ranked server-side: Elite/Growth coaches get a boost, blended with rating &
  // review volume (see marketplace_coaches()).
  try {
    final data = await db.rpc('marketplace_coaches');
    return List<Map<String, dynamic>>.from(data as List);
  } catch (_) {
    // Fallback if the ranking function isn't deployed yet.
    final data = await db
        .from('public_profiles')
        .select('id, first_name, last_name, avatar_url, coach_title, tagline, bio, specialties, certifications, pricing_monthly, years_experience, rating_avg, review_count')
        .eq('role', 'coach')
        .order('rating_avg', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }
});

// Set of "status:coachId" for the client's active/pending relationships, so a
// client can hold relationships with multiple coaches at once.
final _myRelationshipStatusProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(currentUserProvider);
  final rows = await Supabase.instance.client
      .from('coach_client_relationships')
      .select('coach_id, status')
      .eq('client_id', Supabase.instance.client.auth.currentUser?.id ?? '')
      .inFilter('status', ['active', 'pending']);
  return {for (final r in rows as List) '${r['status']}:${r['coach_id']}'};
});

// ── Screen ────────────────────────────────────────────────────────────────────
class CoachMarketplaceScreen extends ConsumerStatefulWidget {
  const CoachMarketplaceScreen({super.key});
  @override
  ConsumerState<CoachMarketplaceScreen> createState() => _CoachMarketplaceScreenState();
}

class _CoachMarketplaceScreenState extends ConsumerState<CoachMarketplaceScreen> {
  String? _filterSpecialty;
  final _search = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _searchQuery = _search.text.toLowerCase()));
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final coachesAsync = ref.watch(coachMarketplaceProvider);
    final relStatus   = ref.watch(_myRelationshipStatusProvider).valueOrNull ?? <String>{};

    return AppGradientBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _wht, size: 20),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context)),
        title: const Text('Find a Coach',
          style: TextStyle(color: _wht, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _search,
            style: const TextStyle(color: _wht, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search by name or specialty…',
              hintStyle: const TextStyle(color: _mut, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: _mut, size: 20),
              filled: true, fillColor: _card,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _brd)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _brd)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _brand))),
            onTapOutside: (_) => FocusScope.of(context).unfocus()),
        ),
        const SizedBox(height: 12),

        // Specialty filter chips
        coachesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (coaches) {
            final allSpecialties = <String>{};
            for (final c in coaches) {
              final sp = c['specialties'] as List? ?? [];
              allSpecialties.addAll(sp.cast<String>());
            }
            if (allSpecialties.isEmpty) return const SizedBox.shrink();
            return SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterChip(label: 'All', selected: _filterSpecialty == null,
                    onTap: () => setState(() => _filterSpecialty = null)),
                  ...allSpecialties.map((s) => _FilterChip(
                    label: s,
                    selected: _filterSpecialty == s,
                    onTap: () => setState(() =>
                      _filterSpecialty = _filterSpecialty == s ? null : s))),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // Coach list
        Expanded(
          child: coachesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: _brand)),
            // ERR-2: `Could not load [noun]` is the pattern this repository
            // renders in fifteen places.
            error: (e, _) => const Center(
                child: Text('Could not load coaches',
                    style: TextStyle(color: _mut))),
            data: (coaches) {
              var filtered = coaches.where((c) {
                final name = '${c['first_name'] ?? ''} ${c['last_name'] ?? ''}'.toLowerCase();
                final specialties = (c['specialties'] as List? ?? []).cast<String>();
                final matchesSearch = _searchQuery.isEmpty
                    || name.contains(_searchQuery)
                    || specialties.any((s) => s.toLowerCase().contains(_searchQuery));
                final matchesFilter = _filterSpecialty == null
                    || specialties.contains(_filterSpecialty);
                return matchesSearch && matchesFilter;
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_search_outlined, color: _mut, size: 48),
                    SizedBox(height: 12),
                    Text('No coaches found', style: TextStyle(color: _mut, fontSize: 14)),
                  ]));
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _CoachCard(
                  coach: filtered[i],
                  relStatus: relStatus,
                  onRequest: (coachId) => _requestCoach(coachId),
                ),
              );
            },
          ),
        ),
      ]),
    ));
  }

  Future<void> _requestCoach(String coachId) async {
    try {
      await _relSvc.requestCoach(coachId);
      ref.invalidate(_myRelationshipStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Request sent! Your coach will be notified.'),
          backgroundColor: _brand));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to send request. Try again.'),
          backgroundColor: _err));
      }
    }
  }
}

// Small tier badge (Elite / Featured) shown beside a boosted coach's name.
Widget _tierBadge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.workspace_premium_rounded, color: color, size: 11),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ]),
    );

// ── Coach Card ────────────────────────────────────────────────────────────────
class _CoachCard extends StatelessWidget {
  final Map<String, dynamic> coach;
  final Set<String> relStatus;
  final void Function(String) onRequest;
  const _CoachCard({required this.coach, required this.relStatus, required this.onRequest});

  @override
  Widget build(BuildContext context) {
    final name = '${coach['first_name'] ?? ''} ${coach['last_name'] ?? ''}'.trim();
    final title = coach['coach_title'] as String? ?? 'Fitness Coach';
    final tagline = coach['tagline'] as String?;
    final bio = coach['bio'] as String?;
    final specialties = (coach['specialties'] as List? ?? []).cast<String>();
    final rating = (coach['rating_avg'] as num?)?.toDouble() ?? 0.0;
    final reviewCount = coach['review_count'] as int? ?? 0;
    final pricing = (coach['pricing_monthly'] as num?)?.toDouble() ?? 0;
    final years = coach['years_experience'] as int? ?? 0;
    final coachId = coach['id'] as String;

    // Multi-coach: only this coach's own status matters; holding other coaches
    // no longer blocks connecting with a new one.
    final isActive  = relStatus.contains('active:$coachId');
    final isPending = relStatus.contains('pending:$coachId');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? _tert : _brd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _brand.withValues(alpha: 0.15),
              border: Border.all(color: _brand.withValues(alpha: 0.3), width: 1.5)),
            alignment: Alignment.center,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C',
              style: const TextStyle(color: _brand, fontSize: 22, fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name.isEmpty ? 'Coach' : name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700))),
              if (coach['plan_tier'] == 'elite') ...[
                const SizedBox(width: 6), _tierBadge('ELITE', _brand),
              ] else if (coach['is_featured'] == true) ...[
                const SizedBox(width: 6), _tierBadge('FEATURED', _tert),
              ],
            ]),
            Text(title, style: const TextStyle(color: _pri, fontSize: 12)),
            if (rating > 0) Row(children: [
              Icon(Icons.star_rounded, color: _brand, size: 14),
              const SizedBox(width: 3),
              Text('${rating.toStringAsFixed(1)} ($reviewCount)',
                style: const TextStyle(color: _mut, fontSize: 12)),
            ]),
          ])),
          if (pricing > 0) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$${pricing.toStringAsFixed(0)}',
              style: const TextStyle(color: _tert, fontSize: 18, fontWeight: FontWeight.w800)),
            const Text('/mo', style: TextStyle(color: _mut, fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 10),

        // Tagline
        if (tagline != null && tagline.isNotEmpty) ...[
          Text('"$tagline"',
            style: const TextStyle(color: _mut, fontSize: 13, fontStyle: FontStyle.italic, height: 1.4)),
          const SizedBox(height: 8),
        ],

        // Bio snippet
        if (bio != null && bio.isNotEmpty) ...[
          Text(bio.length > 100 ? '${bio.substring(0, 100)}…' : bio,
            style: const TextStyle(color: _mut, fontSize: 13, height: 1.4)),
          const SizedBox(height: 8),
        ],

        // Specialties
        if (specialties.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 4, children: specialties.take(4).map((s) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _brand.withValues(alpha: 0.25))),
            child: Text(s, style: const TextStyle(color: _pri, fontSize: 10, fontWeight: FontWeight.w600)))).toList()),
          const SizedBox(height: 10),
        ],

        // Stats row
        Row(children: [
          if (years > 0) _Stat(label: 'YRS EXP', value: '$years'),
          if (years > 0) const SizedBox(width: 16),
          _Stat(label: 'REVIEWS', value: '$reviewCount'),
          const Spacer(),
          TextButton.icon(
            onPressed: () => showCoachReviewsSheet(context, coachId, name.isEmpty ? 'Coach' : name),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            icon: const Icon(Icons.reviews_outlined, size: 16, color: _pri),
            label: const Text('Read reviews',
              style: TextStyle(color: _pri, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 12),

        // Pricing summary (investment range from the coach's packages)
        _PricingSummary(coachId: coachId),

        // View packages
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ChoosePackageScreen(coachId: coachId, coachName: name.isEmpty ? 'Coach' : name))),
            style: OutlinedButton.styleFrom(
              foregroundColor: _pri, side: const BorderSide(color: _brd),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            icon: const Icon(Icons.sell_outlined, size: 16),
            label: const Text('View Packages', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),

        // CTA button
        if (isActive)
          _StatusBadge(label: 'Your Coach', color: _tert)
        else if (isPending)
          _StatusBadge(label: 'Request Sent', color: _mut)
        else
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => onRequest(coachId),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF842BD2), Color(0xFFA855F7)]),
                  borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: const Text(
                  'Request to Connect',
                  style: TextStyle(
                    color: _wht,
                    fontSize: 14, fontWeight: FontWeight.w700))))),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: _mut, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
    Text(value, style: const TextStyle(color: _wht, fontSize: 16, fontWeight: FontWeight.w700)),
  ]);
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.3))),
    alignment: Alignment.center,
    child: Text(label,
      style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)));
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? _brand : _card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? _brand : _brd)),
      child: Text(label,
        style: TextStyle(
          color: selected ? _wht : _mut,
          fontSize: 12, fontWeight: FontWeight.w600))));
}

// ── Pricing summary (what clients see before opening packages) ────────────────
class _PricingSummary extends ConsumerWidget {
  final String coachId;
  const _PricingSummary({required this.coachId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkgs = ref.watch(coachPackagesProvider(coachId)).valueOrNull ?? [];
    if (pkgs.isEmpty) return const SizedBox.shrink();

    double? minOf(String type) {
      final prices = pkgs
          .where((p) => p['type'] == type)
          .map((p) => (p['price'] as num?)?.toDouble() ?? 0)
          .where((v) => v > 0)
          .toList();
      if (prices.isEmpty) return null;
      return prices.reduce((a, b) => a < b ? a : b);
    }

    final ses = minOf('per_session');
    final bulk = minOf('bulk');
    final mon = minOf('monthly');
    final parts = <String>[];
    if (ses != null) parts.add('Sessions from \$${ses.toStringAsFixed(0)}');
    if (bulk != null) parts.add('Packs from \$${bulk.toStringAsFixed(0)}');
    if (mon != null) parts.add('Monthly from \$${mon.toStringAsFixed(0)}/mo');
    if (parts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _tert.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _tert.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.sell_outlined, color: _tert, size: 14),
        const SizedBox(width: 8),
        Expanded(child: Text(parts.join('  ·  '),
            style: const TextStyle(color: _tert, fontSize: 11, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ── Coach reviews sheet ───────────────────────────────────────────────────────
void showCoachReviewsSheet(BuildContext context, String coachId, String coachName) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CoachReviewsSheet(coachId: coachId, coachName: coachName),
  );
}

class _CoachReviewsSheet extends ConsumerWidget {
  final String coachId, coachName;
  const _CoachReviewsSheet({required this.coachId, required this.coachName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(coachReviewsProvider(coachId));
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
      decoration: const BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: _brd))),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: _brd, borderRadius: BorderRadius.circular(2)))),
        Text('$coachName — Reviews',
          style: const TextStyle(color: _wht, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Flexible(child: reviewsAsync.when(
          loading: () => const Padding(padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: _brand))),
          error: (_, __) => const Padding(padding: EdgeInsets.all(24),
            child: Text('Could not load reviews.', style: TextStyle(color: _mut))),
          data: (reviews) {
            if (reviews.isEmpty) {
              return const Padding(padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No reviews yet. Be the first after you work together!',
                  style: TextStyle(color: _mut)));
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: reviews.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ReviewItem(review: reviews[i]),
            );
          },
        )),
      ]),
    );
  }
}

class _ReviewItem extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewItem({required this.review});

  @override
  Widget build(BuildContext context) {
    final reviewer = review['reviewer'] as Map<String, dynamic>? ?? {};
    final name = '${reviewer['first_name'] ?? ''} ${reviewer['last_name'] ?? ''}'.trim();
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final text = review['review_text'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 14, backgroundColor: _brand.withValues(alpha: 0.18),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: _pri, fontSize: 12, fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(child: Text(name.isEmpty ? 'Client' : name,
            style: const TextStyle(color: _wht, fontSize: 13, fontWeight: FontWeight.w600))),
          Row(children: List.generate(5, (i) => Icon(
            i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 14, color: i < rating ? const Color(0xFFFFD479) : _mut))),
        ]),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: _mut, fontSize: 13, height: 1.4)),
        ],
      ]),
    );
  }
}
