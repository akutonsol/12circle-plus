import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _bg   = Color(0xFF0E0E0F);
const _pri  = Color(0xFFDDB7FF);
const _priC = Color(0xFFB76DFF);
const _tert = Color(0xFF6FFBBE);
const _onS  = Color(0xFFE5E2E3);
const _onSV = Color(0xFFCDC3D0);
const _out  = Color(0xFF968E99);
const _outV = Color(0xFF4B444F);
const _err  = Color(0xFFFFB4AB);

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});
  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  // Track which integrations are "connected" (stored in user_profiles or a separate table)
  // For now we track locally; a real implementation would persist this
  final Set<String> _connected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConnected();
  }

  Future<void> _loadConnected() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) { setState(() => _loading = false); return; }
      final row = await Supabase.instance.client
          .from('user_integrations')
          .select('provider')
          .eq('user_id', uid)
          .eq('connected', true);
      if (!mounted) return;
      setState(() {
        _connected.clear();
        for (final r in (row as List)) {
          _connected.add(r['provider'] as String);
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleConnect(String provider, bool connect) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      if (connect) {
        await Supabase.instance.client.from('user_integrations').upsert({
          'user_id': uid,
          'provider': provider,
          'connected': true,
          'connected_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,provider');
        if (!mounted) return;
        setState(() => _connected.add(provider));
      } else {
        await Supabase.instance.client.from('user_integrations')
            .update({'connected': false, 'disconnected_at': DateTime.now().toIso8601String()})
            .eq('user_id', uid)
            .eq('provider', provider);
        if (!mounted) return;
        setState(() => _connected.remove(provider));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not update integration'),
          backgroundColor: _err, behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header
        Container(
          padding: EdgeInsets.only(left: 8, right: 20, top: top),
          decoration: const BoxDecoration(
            color: Color(0x99201F20),
            border: Border(bottom: BorderSide(color: Color(0x1A4B444F)))),
          child: SizedBox(height: 56, child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: _pri, size: 20),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop()),
            const Expanded(child: Center(child: Text('INTEGRATIONS',
              style: TextStyle(color: _pri, fontSize: 16,
                fontWeight: FontWeight.w800, letterSpacing: 2)))),
            const SizedBox(width: 40),
          ])),
        ),

        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: _pri))
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 24, 20, bottom + 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 20),
                  child: Text(
                    'Connect your fitness apps and wearables to sync data automatically.',
                    style: TextStyle(color: _out, fontSize: 13, height: 1.5))),

                if (kIsWeb) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: _priC.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _priC.withValues(alpha: 0.18))),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded, color: _priC, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(child: Text(
                        'Health app integrations are available on the iOS and Android apps. '
                        'Connect your devices from the mobile app to sync data here.',
                        style: TextStyle(color: _onSV, fontSize: 12, height: 1.5))),
                    ])),
                ],

                // ── Health Platforms ──
                _sectionLabel('HEALTH PLATFORMS'),
                const SizedBox(height: 10),
                _card(Column(children: [
                  _integrationRow(
                    id: 'apple_health',
                    name: 'Apple Health',
                    subtitle: 'Sync steps, heart rate, workouts & sleep',
                    iconBg: Colors.white,
                    icon: Icons.favorite,
                    iconColor: Colors.red,
                    platform: 'iOS only',
                  ),
                  _divider(),
                  _integrationRow(
                    id: 'google_fit',
                    name: 'Google Fit',
                    subtitle: 'Sync activity, calories & heart rate',
                    iconBg: const Color(0xFF4285F4),
                    icon: Icons.directions_run,
                    iconColor: Colors.white,
                    platform: 'Android only',
                  ),
                ])),
                const SizedBox(height: 24),

                // ── Wearables ──
                _sectionLabel('WEARABLES'),
                const SizedBox(height: 10),
                _card(Column(children: [
                  _integrationRow(
                    id: 'whoop',
                    name: 'WHOOP',
                    subtitle: 'Recovery, strain & sleep data',
                    iconBg: const Color(0xFF00F2FF),
                    icon: Icons.watch_outlined,
                    iconColor: Colors.black,
                  ),
                  _divider(),
                  _integrationRow(
                    id: 'garmin',
                    name: 'Garmin Connect',
                    subtitle: 'GPS, performance & health metrics',
                    iconBg: const Color(0xFF007CC3),
                    icon: Icons.gps_fixed,
                    iconColor: Colors.white,
                  ),
                  _divider(),
                  _integrationRow(
                    id: 'polar',
                    name: 'Polar',
                    subtitle: 'Heart rate zones & training load',
                    iconBg: const Color(0xFFD40B0B),
                    icon: Icons.favorite_border,
                    iconColor: Colors.white,
                  ),
                ])),
                const SizedBox(height: 24),

                // ── Fitness Apps ──
                _sectionLabel('FITNESS APPS'),
                const SizedBox(height: 10),
                _card(Column(children: [
                  _integrationRow(
                    id: 'strava',
                    name: 'Strava',
                    subtitle: 'Import runs, rides & activities',
                    iconBg: const Color(0xFFFC4C02),
                    icon: Icons.directions_bike,
                    iconColor: Colors.white,
                  ),
                  _divider(),
                  _integrationRow(
                    id: 'myfitnesspal',
                    name: 'MyFitnessPal',
                    subtitle: 'Sync nutrition logs and macros',
                    iconBg: const Color(0xFF0073BB),
                    icon: Icons.restaurant_menu,
                    iconColor: Colors.white,
                  ),
                  _divider(),
                  _integrationRow(
                    id: 'spotify',
                    name: 'Spotify',
                    subtitle: 'Control workout playlists from the app',
                    iconBg: const Color(0xFF1DB954),
                    icon: Icons.music_note_rounded,
                    iconColor: Colors.black,
                  ),
                ])),
              ]),
            )),
      ]),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(label, style: const TextStyle(
      color: _onSV, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)));

  Widget _card(Widget child) => Container(
    decoration: BoxDecoration(
      color: const Color(0x99201F20),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x0DFFFFFF))),
    clipBehavior: Clip.antiAlias,
    child: child);

  Widget _divider() => const Divider(height: 1, color: Color(0x1A4B444F));

  // Determine how each integration connects
  static const _oauthApps = {
    'strava', 'myfitnesspal', 'spotify', 'whoop', 'garmin', 'polar',
  };
  static const _devicePermissionApps = {
    'apple_health', 'google_fit',
  };

  // OAuth authorization URLs (placeholder — real client_id needed per app)
  static const _oauthUrls = {
    'spotify'      : 'https://accounts.spotify.com/authorize?client_id=YOUR_CLIENT_ID&response_type=code&redirect_uri=com.12circle.app%3A%2F%2Fauth%2Fspotify&scope=user-read-playback-state+user-modify-playback-state+streaming',
    'strava'       : 'https://www.strava.com/oauth/authorize?client_id=YOUR_CLIENT_ID&response_type=code&redirect_uri=com.12circle.app%3A%2F%2Fauth%2Fstrava&scope=activity%3Aread_all',
    'myfitnesspal' : 'https://www.myfitnesspal.com/api/auth/token',
    'whoop'        : 'https://api.prod.whoop.com/oauth/oauth2/auth?client_id=YOUR_CLIENT_ID&response_type=code&redirect_uri=com.12circle.app%3A%2F%2Fauth%2Fwhoop&scope=read%3Arecovery+read%3Asleep+read%3Aworkout',
    'garmin'       : 'https://connect.garmin.com/oauthConfirm',
    'polar'        : 'https://flow.polar.com/oauth2/authorization?response_type=code&client_id=YOUR_CLIENT_ID',
  };

  Future<void> _handleConnect(String id) async {
    if (_devicePermissionApps.contains(id)) {
      _showPermissionSheet(id);
      return;
    }
    if (_oauthApps.contains(id)) {
      await _showOAuthSheet(id);
      return;
    }
    await _toggleConnect(id, true);
  }

  void _showPermissionSheet(String id) {
    final name = id == 'apple_health' ? 'Apple Health' : 'Google Fit';
    final platform = id == 'apple_health' ? 'iOS' : 'Android';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _IntegrationInfoSheet(
        name: name,
        type: 'Device Permission',
        typeColor: const Color(0xFF06B6D4),
        description: '$name integration uses your device\'s native health '
          'platform — it requires a device permission, not a web login.\n\n'
          'On $platform, open your device Settings → Privacy → Health → 12 Circle '
          'and grant the required permissions.',
        steps: [
          'Open your device Settings app',
          'Go to Privacy → Health (iOS) or Health Connect (Android)',
          'Find 12 Circle and grant read/write access',
          'Return to the app — data will sync automatically',
        ],
        onContinue: null, // No OAuth URL — handled natively
      ));
  }

  Future<void> _showOAuthSheet(String id) async {
    final names = {
      'spotify': 'Spotify', 'strava': 'Strava',
      'myfitnesspal': 'MyFitnessPal', 'whoop': 'WHOOP',
      'garmin': 'Garmin Connect', 'polar': 'Polar',
    };
    final descriptions = {
      'spotify': 'Connect Spotify to control your workout playlists directly from the 12 Circle app. You\'ll be able to play, pause, and switch tracks without leaving your session.',
      'strava' : 'Connect Strava to automatically import your runs, rides, and outdoor activities. Your activity data will count toward your weekly progress.',
      'myfitnesspal': 'Sync your MyFitnessPal food diary to automatically populate your nutrition logs. Calories and macros will sync in real time.',
      'whoop'  : 'Connect WHOOP to import your recovery score, HRV, sleep quality, and strain data. Your coach and AI will factor this into your programming.',
      'garmin' : 'Connect Garmin to import GPS routes, heart rate, VO2 max, and training load data from your Garmin device.',
      'polar'  : 'Connect Polar Flow to import heart rate zones, training load, and recovery status from your Polar device.',
    };
    final oauthUrl = _oauthUrls[id];
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _IntegrationInfoSheet(
        name: names[id] ?? id,
        type: 'OAuth 2.0',
        typeColor: _priC,
        description: descriptions[id] ?? 'Connect your $id account.',
        steps: [
          'Tap "Connect with ${names[id]}" below',
          'You\'ll be redirected to ${names[id]} to authorize access',
          'Grant the requested permissions',
          'You\'ll be returned to 12 Circle — connection is instant',
        ],
        onContinue: oauthUrl != null
          ? () async {
              final uri = Uri.parse(oauthUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                // In production, handle the deep link callback here to store tokens
                if (mounted) await _toggleConnect(id, true);
              }
            }
          : null,
      ));
  }

  Widget _integrationRow({
    required String id,
    required String name,
    required String subtitle,
    required Color iconBg,
    required IconData icon,
    required Color iconColor,
    String? platform,
  }) {
    final isConnected = _connected.contains(id);
    final isDevicePerm = _devicePermissionApps.contains(id);
    final webOnly = isDevicePerm && kIsWeb;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: iconColor, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(name, style: const TextStyle(
              color: _onS, fontSize: 15, fontWeight: FontWeight.w500)),
            if (platform != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _outV.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4)),
                child: Text(platform, style: const TextStyle(
                  color: _out, fontSize: 9, fontWeight: FontWeight.w600))),
            ],
            if (isDevicePerm && !kIsWeb) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4)),
                child: const Text('Permission', style: TextStyle(
                  color: Color(0xFF06B6D4), fontSize: 9, fontWeight: FontWeight.w600))),
            ],
          ]),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: _out, fontSize: 12, height: 1.3)),
        ])),
        const SizedBox(width: 12),
        if (isConnected)
          GestureDetector(
            onTap: () => _toggleConnect(id, false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _tert.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _tert.withValues(alpha: 0.4))),
              child: const Text('Connected',
                style: TextStyle(color: _tert, fontSize: 12, fontWeight: FontWeight.w600))))
        else if (webOnly)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _outV.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _outV)),
            child: const Text('Mobile only',
              style: TextStyle(color: _out, fontSize: 12, fontWeight: FontWeight.w600)))
        else
          GestureDetector(
            onTap: () => _handleConnect(id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _priC.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _priC.withValues(alpha: 0.4))),
              child: const Text('Connect',
                style: TextStyle(color: _pri, fontSize: 12, fontWeight: FontWeight.w600)))),
      ]));
  }
}

// ── Integration Info Sheet ────────────────────────────────────────────────────
class _IntegrationInfoSheet extends StatelessWidget {
  final String name, type, description;
  final Color typeColor;
  final List<String> steps;
  final Future<void> Function()? onContinue;
  const _IntegrationInfoSheet({
    required this.name, required this.type, required this.typeColor,
    required this.description, required this.steps, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottom + 24),
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(children: [
            Text(name,
              style: const TextStyle(color: _onS, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6)),
              child: Text(type,
                style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 12),
          Text(description,
            style: const TextStyle(color: _onSV, fontSize: 13, height: 1.6)),
          const SizedBox(height: 20),
          const Text('HOW IT WORKS',
            style: TextStyle(color: _out, fontSize: 10, fontWeight: FontWeight.w700,
              letterSpacing: 1.5)),
          const SizedBox(height: 10),
          ...steps.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('${e.key + 1}',
                  style: TextStyle(color: typeColor, fontSize: 10,
                    fontWeight: FontWeight.w800))),
              const SizedBox(width: 10),
              Expanded(child: Text(e.value,
                style: const TextStyle(color: _onSV, fontSize: 13, height: 1.4))),
            ]))),
          const SizedBox(height: 20),
          if (onContinue != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  onContinue!();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _priC, foregroundColor: _onS,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text('Connect with $name',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))))
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: Text('Set up via device Settings',
                style: TextStyle(color: _out, fontSize: 14, fontWeight: FontWeight.w600))),
        ]));
  }
}
