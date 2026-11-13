import 'package:supabase_flutter/supabase_flutter.dart';

/// Coach revenue analytics, computed from the recorded payout split on
/// payments (one-time) + active subscriptions (recurring). Amounts in dollars.
class CoachRevenueService {
  final _db = Supabase.instance.client;

  Future<Map<String, double>> getMetrics() async {
    final coachId = _db.auth.currentUser?.id;
    if (coachId == null) return _empty;
    // **A failed read propagates (EC-14).** This ended `catch (_) { return
    // _empty; }` (every figure zero), so a coach on a bad connection read
    // "Lifetime 0" and "Active subscribers 0" as fact.
    {
      final payments = List<Map<String, dynamic>>.from(await _db
          .from('payments')
          .select('coach_payout, client_source, status, created_at')
          .eq('coach_id', coachId)
          .eq('status', 'paid'));
      final subs = List<Map<String, dynamic>>.from(await _db
          .from('subscriptions')
          .select('coach_payout, client_source, status')
          .eq('coach_id', coachId)
          .inFilter('status', ['active', 'trialing']));
      // Active packages: session credits the coach is still drawing down.
      final credits = List<Map<String, dynamic>>.from(await _db
          .from('client_session_credits')
          .select('sessions_total, sessions_used')
          .eq('coach_id', coachId));
      final activePackages = credits.where((c) =>
          ((c['sessions_used'] as num?)?.toInt() ?? 0) <
          ((c['sessions_total'] as num?)?.toInt() ?? 0)).length;

      double d(dynamic c) => ((c as num?)?.toDouble() ?? 0) / 100.0; // cents → $
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);

      double lifetime = 0, monthOneTime = 0, market = 0, direct = 0;
      for (final p in payments) {
        final v = d(p['coach_payout']);
        lifetime += v;
        if ((p['client_source'] as String?) == 'coach_invited') {
          direct += v;
        } else {
          market += v;
        }
        final ts = DateTime.tryParse(p['created_at'] as String? ?? '');
        if (ts != null && ts.isAfter(monthStart)) monthOneTime += v;
      }
      // Recurring (active subs) — counts toward monthly + lifetime + split.
      double mrr = 0;
      for (final s in subs) {
        final v = d(s['coach_payout']);
        mrr += v;
        lifetime += v;
        if ((s['client_source'] as String?) == 'coach_invited') {
          direct += v;
        } else {
          market += v;
        }
      }
      return {
        'monthly': monthOneTime + mrr,
        'lifetime': lifetime,
        'mrr': mrr,
        'active_subscribers': subs.length.toDouble(),
        'active_packages': activePackages.toDouble(),
        'marketplace': market,
        'direct': direct,
      };
    }
  }

  static const Map<String, double> _empty = {
    'monthly': 0, 'lifetime': 0, 'mrr': 0,
    'active_subscribers': 0, 'active_packages': 0, 'marketplace': 0, 'direct': 0,
  };
}
