import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin-configurable platform settings (key/value), incl. the marketplace
/// commission rate that 12 Circle takes on marketplace-acquired coaching sales.
class PlatformSettingsService {
  final _db = Supabase.instance.client;

  Future<double> getMarketplaceCommission() async {
    try {
      final row = await _db.from('platform_settings')
          .select('value').eq('key', 'marketplace_commission_rate').maybeSingle();
      return double.tryParse('${row?['value'] ?? ''}') ?? 0.10;
    } catch (_) {
      return 0.10;
    }
  }

  Future<bool> setMarketplaceCommission(double rate) async {
    try {
      await _db.from('platform_settings').upsert({
        'key': 'marketplace_commission_rate',
        'value': rate.toStringAsFixed(4),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'key');
      return true;
    } catch (_) {
      return false;
    }
  }
}

final platformSettingsServiceProvider =
    Provider<PlatformSettingsService>((ref) => PlatformSettingsService());

final marketplaceCommissionProvider = FutureProvider<double>((ref) async {
  return ref.watch(platformSettingsServiceProvider).getMarketplaceCommission();
});
