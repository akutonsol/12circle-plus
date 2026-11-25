import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/observability/app_failure.dart';
import '../../workout/presentation/widgets/section_load_failure.dart';

const _bg   = Color(0xFF0E0E0F);
const _pri  = Color(0xFFDDB7FF);
const _priC = Color(0xFFB76DFF);
const _tert = Color(0xFF6FFBBE);
const _onS  = Color(0xFFE5E2E3);
const _onSV = Color(0xFFCDC3D0);
const _out  = Color(0xFF968E99);
const _outV = Color(0xFF4B444F);
const _err  = Color(0xFFFFB4AB);

/// P0-FL-59d · a route's content, for the account [owner] only. For anyone else
/// nothing of it is drawn — not even the first frame of a route pushed just
/// before a switch — and the route closes. It listens for itself: whatever
/// opened the route may be gone by then.
class _OwnedRoute extends StatefulWidget {
  final String? owner;
  final Widget child;
  const _OwnedRoute({required this.owner, required this.child});
  @override
  State<_OwnedRoute> createState() => _OwnedRouteState();
}

class _OwnedRouteState extends State<_OwnedRoute> {
  StreamSubscription<AuthState>? _authSub;

  bool get _mine =>
      Supabase.instance.client.auth.currentUser?.id == widget.owner;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (!mounted || _mine) return;
      setState(() {}); // (one already closing stops showing it, too)
      _close();
    }, onError: (Object e, StackTrace s) =>
        reportError('IntegrationsScreen._OwnedRoute', e, s));
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _close() {
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    if (_mine) return widget.child;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_mine) _close();
    });
    return const SizedBox.shrink();
  }
}

/// Closes [context]'s own route with [result], if it is still open: once it
/// has been closed under a tap, popping would close the page beneath.
void _popRoute(BuildContext context, [Object? result]) {
  final route = context.mounted ? ModalRoute.of(context) : null;
  if (route == null || !route.isActive) return;
  route.isCurrent ? Navigator.pop(context, result) : route.navigator?.removeRoute(route);
}

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});
  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  /// The connected providers of [_owner], as the server last said.
  Set<String> _connected = {};
  bool _loading = true;

  /// P0-FL-59d · whose connections these are. They were read once and kept:
  /// the next member to sign in on this device saw the last one's, and their
  /// taps wrote from them.
  String? _owner;
  int _loadSeq = 0;
  StreamSubscription<AuthState>? _authSub;

  /// [_connected] is [_owner]'s. A failed read was shown as "not connected";
  /// until one succeeds nothing is claimed and every toggle is disabled.
  bool _loaded = false;
  Object? _loadError;
  bool _retrying = false;

  /// Providers whose connect / disconnect is in flight (no double fire).
  final Set<String> _busy = {};

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadConnected();
    // Same member (a token refresh, the stream's replay) changes nothing.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (_) => _followAccount(),
        onError: (Object e, StackTrace s) =>
            reportError('IntegrationsScreen.onAuthStateChange', e, s));
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Nothing of the previous member's stays: connections, messages. (The info
  /// sheet closes itself.)
  void _followAccount() {
    if (!mounted || _uid == _owner) return;
    ScaffoldMessenger.of(context)..clearSnackBars()..removeCurrentSnackBar();
    setState(() {
      _connected = {};
      _busy.clear();
      _loaded = false;
      _loadError = null;
      _retrying = false;
      _loading = true;
    });
    _loadConnected();
  }

  /// True when [owner] is no longer signed in: recorded, the page follows the
  /// new account, and the caller sends (and says) nothing.
  bool _accountChanged(String method, String what, String? owner) {
    if (owner != null && _uid == owner) return false;
    reportError('IntegrationsScreen.$method',
        StateError('$what: the signed-in account changed'));
    _followAccount();
    return true;
  }

  Future<void> _loadConnected() async {
    final uid = _uid;
    final seq = ++_loadSeq;
    _owner = uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    bool current() => seq == _loadSeq && _uid == uid;
    try {
      final rows = await Supabase.instance.client
          .from('user_integrations')
          .select('provider')
          .eq('user_id', uid)
          .eq('connected', true);
      if (!mounted || !current()) return;
      setState(() {
        _connected = {for (final r in (rows as List)) r['provider'] as String};
        _loaded = true;
        _loadError = null;
        _loading = false;
      });
    } catch (e, st) {
      reportError('IntegrationsScreen._loadConnected', e, st);
      if (!mounted || !current()) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    final owner = _owner;
    setState(() => _retrying = true);
    await _loadConnected();
    if (mounted && _owner == owner) setState(() => _retrying = false);
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Semantics(liveRegion: true,
          child: Text(message, style: const TextStyle(color: _bg))),
      backgroundColor: _err, behavior: SnackBarBehavior.floating));

  /// Connected / disconnected only when the server says the row changed: a
  /// 0-row write (RLS filters silently) answers like a saved one unless the
  /// row is asked back.
  ///
  /// [owner] is the member whose state the tapped row showed.
  Future<void> _toggleConnect(String provider, bool connect, String? owner) async {
    if (_accountChanged('_toggleConnect', 'Changing an integration', owner)) return;
    if (!_loaded || _busy.contains(provider)) return;
    bool mine() => _uid == owner && _owner == owner;
    setState(() => _busy.add(provider));
    try {
      final List<dynamic> rows;
      if (connect) {
        rows = await Supabase.instance.client.from('user_integrations').upsert({
          'user_id': owner,
          'provider': provider,
          'connected': true,
          'connected_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,provider').select('provider');
      } else {
        rows = await Supabase.instance.client.from('user_integrations')
            .update({'connected': false, 'disconnected_at': DateTime.now().toUtc().toIso8601String()})
            .eq('user_id', owner!)
            .eq('provider', provider)
            .select('provider');
      }
      if (rows.isEmpty) throw StateError('user_integrations write matched no row');
      if (!mounted || !mine()) return;
      setState(() {
        _busy.remove(provider);
        connect ? _connected.add(provider) : _connected.remove(provider);
      });
    } catch (e, st) {
      reportError('IntegrationsScreen._toggleConnect', e, st);
      if (!mounted || !mine()) return;
      setState(() => _busy.remove(provider));
      final name = _names[provider] ?? provider;
      _say(couldntMessage(connect ? 'connect $name' : 'disconnect $name', e));
    }
  }

  static const _names = {
    'apple_health': 'Apple Health', 'google_fit': 'Google Fit',
    'spotify': 'Spotify', 'strava': 'Strava',
    'myfitnesspal': 'MyFitnessPal', 'whoop': 'WHOOP',
    'garmin': 'Garmin Connect', 'polar': 'Polar',
  };

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
          : _owner == null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Semantics(liveRegion: true, child: const Text(
                "You're signed out — sign in again to see your integrations.",
                textAlign: TextAlign.center, style: TextStyle(color: _onS, fontSize: 15)))))
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 24, 20, bottom + 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 20),
                  child: Text(
                    'Connect your fitness apps and wearables to sync data automatically.',
                    style: TextStyle(color: _out, fontSize: 13, height: 1.5))),

                if (!_loaded) ...[
                  SectionLoadFailure(
                    what: 'your connected apps',
                    error: _loadError,
                    detail: 'Connecting is paused until it loads.',
                    busy: _retrying,
                    onRetry: _retry),
                  const SizedBox(height: 20),
                ],

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

  /// [owner] is the member the tapped row was drawn for.
  Future<void> _handleConnect(String id, String? owner) async {
    if (_accountChanged('_handleConnect', 'Connecting an app', owner)) return;
    if (_devicePermissionApps.contains(id)) {
      _showPermissionSheet(id, owner);
      return;
    }
    if (_oauthApps.contains(id)) {
      await _showOAuthSheet(id, owner);
      return;
    }
    await _toggleConnect(id, true, owner);
  }

  void _showPermissionSheet(String id, String? owner) {
    final name = id == 'apple_health' ? 'Apple Health' : 'Google Fit';
    final platform = id == 'apple_health' ? 'iOS' : 'Android';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _OwnedRoute(owner: owner, child: _IntegrationInfoSheet(
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
      )));
  }

  /// The connection is for [owner], the member this sheet was opened by.
  Future<void> _showOAuthSheet(String id, String? owner) async {
    const names = _names;
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
      builder: (_) => _OwnedRoute(owner: owner, child: _IntegrationInfoSheet(
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
              if (_accountChanged('_showOAuthSheet', 'Connecting an app', owner)) return;
              final uri = Uri.parse(oauthUrl);
              // A page that did not open did nothing and said nothing.
              var opened = false;
              Object? error;
              try {
                opened = await canLaunchUrl(uri) &&
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e, st) {
                error = e;
                reportError('IntegrationsScreen._showOAuthSheet', e, st);
              }
              if (!mounted) return;
              if (_accountChanged('_showOAuthSheet', 'Connecting an app', owner)) return;
              if (!opened) {
                if (error == null) {
                  reportError('IntegrationsScreen._showOAuthSheet',
                      StateError('the authorization page did not open'));
                }
                _say(couldntMessage('open ${names[id] ?? id}', error));
                return;
              }
              // In production, handle the deep link callback here to store tokens
              await _toggleConnect(id, true, owner);
            }
          : null,
      )));
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
    final owner = _owner;
    final isDevicePerm = _devicePermissionApps.contains(id);
    final webOnly = isDevicePerm && kIsWeb;

    final Widget pill;
    if (!_loaded) {
      // P0-FL-59d · unknown is not "not connected".
      pill = _statePill('Not loaded', label: '$name: connection not loaded',
        onTap: null, text: _out, fill: _outV, edge: _outV);
    } else if (_busy.contains(id)) {
      pill = Semantics(
        container: true, label: 'Updating $name', liveRegion: true,
        child: const SizedBox(width: 44, height: 44, child: Center(child: SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: _pri)))));
    } else if (isConnected) {
      pill = _statePill('Connected', label: 'Connected: disconnect $name',
        onTap: () => _toggleConnect(id, false, owner), text: _tert, fill: _tert, edge: _tert);
    } else if (webOnly) {
      pill = _statePill('Mobile only', label: '$name: mobile only',
        onTap: null, text: _out, fill: _outV, edge: _outV);
    } else {
      pill = _statePill('Connect', label: 'Connect $name',
        onTap: () => _handleConnect(id, owner), text: _pri, fill: _priC, edge: _priC);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(builder: (context, box) {
        // P0-FL-59d · the state goes under the app past 1.3× — and wherever
        // beside it the app's name would be broken mid-word.
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final stacked = scale > 1.3 || box.maxWidth < 260 * scale;
        final app = Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // The badges go under a name they do not fit beside.
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(name, style: const TextStyle(
                color: _onS, fontSize: 15, fontWeight: FontWeight.w500)),
              if (platform != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _outV.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text(platform, style: const TextStyle(
                    color: _out, fontSize: 9, fontWeight: FontWeight.w600))),
              if (isDevicePerm && !kIsWeb)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4)),
                  child: const Text('Permission', style: TextStyle(
                    color: Color(0xFF06B6D4), fontSize: 9, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: _out, fontSize: 12, height: 1.3)),
          ])),
          if (!stacked) ...[const SizedBox(width: 12), pill],
        ]);
        if (!stacked) return app;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          app, const SizedBox(height: 8), pill]);
      }));
  }

  /// A row's state, and (when [onTap] is set) the button that changes it: the
  /// pill keeps its look in a 44px target named for its app.
  Widget _statePill(String state, {required String label, required VoidCallback? onTap,
      required Color text, required Color fill, required Color edge}) => Semantics(
    container: true,
    button: onTap != null || !_loaded,
    enabled: onTap != null,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Center(widthFactor: 1, heightFactor: 1, child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: fill.withValues(alpha: onTap == null ? 0.3 : 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: edge.withValues(alpha: onTap == null ? 1 : 0.4))),
          child: Text(state, style: TextStyle(
            color: text, fontSize: 12, fontWeight: FontWeight.w600)))))));
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
                  _popRoute(context);
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
