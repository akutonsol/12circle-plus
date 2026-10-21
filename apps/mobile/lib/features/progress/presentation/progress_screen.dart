import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math' as math;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../features/coach/data/score_service.dart';
import '../../../features/scoring/data/score_engine.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../core/observability/app_failure.dart';
import '../data/baseline_photo_replace.dart';

class _C {
  static const surface             = Color(0xFF131314);
  static const surfaceContainer    = Color(0xFF201F20);
  static const surfaceContainerHigh= Color(0xFF2A2A2B);
  static const glassCard           = Color(0x99201F20);
  static const primary             = Color(0xFFDDB7FF);
  static const primaryContainer    = Color(0xFFB76DFF);
  static const inversePrimary      = Color(0xFF842BD2);
  static const onPrimary           = Color(0xFF490080);
  static const onSurface           = Color(0xFFE5E2E3);
  static const onSurfaceVar        = Color(0xFFCDC3D0);
  static const outline             = Color(0xFF968E99);
  static const outlineVar          = Color(0xFF4B444F);
  static const tertiary            = Color(0xFF4EDEA3);
  static const secondary           = Color(0xFFADC6FF);
  static const error               = Color(0xFFFFB4AB);
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // ── Loaded data ──
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _weightLogs = [];
  Map<String, dynamic>? _latestMeasurements;
  List<Map<String, dynamic>> _measurementHistory = [];
  List<Map<String, dynamic>> _photoLogs = [];
  Map<String, String> _galleryUrls = {};
  String? _frontUrl, _sideUrl, _backUrl;
  bool _loading = true;
  /// F-15: a failed load is not an empty history. This screen used to end
  /// `catch (_) { _loading = false; }` and then render "Log your first weight
  /// to see your chart", "No entries yet" and "No check-ins yet" — **all at
  /// once** — to a client whose six reads had simply failed. Three definite
  /// statements about their history, none of which the screen could support.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loadFailed = false);
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('weight_kg, weight_goal_kg, height_cm')
          .eq('id', uid).maybeSingle();

      final logs = await Supabase.instance.client
          .from('weight_logs')
          .select()
          .eq('user_id', uid)
          .order('logged_at', ascending: false)
          .limit(30);

      final measurementHistory = await Supabase.instance.client
          .from('body_measurements')
          .select()
          .eq('user_id', uid)
          .order('logged_at', ascending: true)
          .limit(24);
      final measurements = (measurementHistory as List).isNotEmpty
          ? (measurementHistory as List).last as Map<String, dynamic>
          : null;

      final photoLogs = await Supabase.instance.client
          .from('progress_photo_logs')
          .select()
          .eq('user_id', uid)
          .order('logged_at', ascending: false)
          .limit(10);

      // Signed URLs for onboarding photos (1 hr expiry; silent fail = no photo yet).
      // Probe EVERY extension the onboarding upload may have written (iOS=heic,
      // web=png/webp), not just one — otherwise a non-jpg photo never shows.
      String? frontUrl, sideUrl, backUrl;
      const exts = ['jpg', 'jpeg', 'png', 'heic', 'webp'];
      for (final entry in [
        ('front', (String u) => frontUrl = u),
        ('side',  (String u) => sideUrl  = u),
        ('back',  (String u) => backUrl  = u),
      ]) {
        for (final ext in exts) {
          try {
            final url = await Supabase.instance.client.storage
                .from('progress-photos')
                .createSignedUrl('$uid/${entry.$1}.$ext', 3600);
            entry.$2(url);
            break; // found this side — stop trying extensions
          } catch (_) {}
        }
      }

      // Generate signed URLs for each gallery photo upload
      final galleryUrls = <String, String>{};
      for (final log in (photoLogs as List)) {
        final path = log['storage_path'] as String?;
        if (path != null && path.isNotEmpty && path.contains('gallery_')) {
          try {
            final url = await Supabase.instance.client.storage
                .from('progress-photos')
                .createSignedUrl(path, 3600);
            galleryUrls[path] = url;
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _profile = profile;
          _weightLogs = List<Map<String, dynamic>>.from(logs);
          _latestMeasurements = measurements;
          _measurementHistory = List<Map<String, dynamic>>.from(measurementHistory);
          _photoLogs = List<Map<String, dynamic>>.from(photoLogs);
          _galleryUrls = galleryUrls;
          _frontUrl = frontUrl;
          _sideUrl  = sideUrl;
          _backUrl  = backUrl;
          _loading  = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadFailed = true; });
    }
  }

  double get _currentWeightKg {
    if (_weightLogs.isNotEmpty) {
      return ((_weightLogs.first['weight_kg']) as num).toDouble();
    }
    return ((_profile?['weight_kg'] ?? 0) as num).toDouble();
  }

  double get _goalWeightKg =>
      ((_profile?['weight_goal_kg'] ?? 0) as num).toDouble();

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'PERFORMANCE',
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : _loadFailed
          // NOT three empty states. The screen knows nothing about this
          // client's history, so it says that and offers a retry instead of
          // telling them to log their first weight.
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_rounded,
                      color: Color(0xFFFFB4AB), size: 40),
                  const SizedBox(height: 14),
                  // Follows the `Could not load [noun]` pattern this
                  // repository renders in fifteen files.
                  const Text('Could not load your progress',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFFFFB4AB),
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      onTap: _loadData,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 44, minHeight: 44),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12))),
                        // The package's own label, 16 declarations.
                        child: const Text('Try again',
                            style: TextStyle(
                                color: _C.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ]),
              ),
            )
          : Column(
              children: [
                // ── Tab bar ──
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _C.surfaceContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _C.outlineVar.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: ['Weight', 'Measurements', 'Photos'].asMap().entries.map((e) {
                      final active = _tabCtrl.index == e.key;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => _tabCtrl.animateTo(e.key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: active ? _C.primaryContainer : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: active ? [
                                const BoxShadow(color: Color(0x44842BD2), blurRadius: 10)
                              ] : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(e.value,
                              style: TextStyle(
                                color: active ? _C.onPrimary : _C.outline,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              )),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Tab content ──
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _WeightTab(
                        currentKg: _currentWeightKg,
                        goalKg: _goalWeightKg,
                        logs: _weightLogs,
                        onLogWeight: () => _showLogWeightSheet(context),
                      ),
                      _MeasurementsTab(
                        measurements: _latestMeasurements,
                        history: _measurementHistory,
                        frontPhotoUrl: _frontUrl,
                        latestGalleryUrl: _galleryUrls.values.lastOrNull,
                        onLog: () => _showLogMeasurementSheet(context),
                      ),
                      _PhotosTab(
                        frontUrl: _frontUrl,
                        sideUrl: _sideUrl,
                        backUrl: _backUrl,
                        photoLogs: _photoLogs,
                        galleryUrls: _galleryUrls,
                        onRefresh: _loadData,
                        onAddPhoto: () => _pickAndUploadPhoto(context),
                        onSetBaseline: (side) => _setBaselinePhoto(context, side),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  void _showLogWeightSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LogWeightSheet(
        initialKg: _currentWeightKg,
        onSaved: _loadData,
      ),
    );
  }

  void _showLogMeasurementSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LogMeasurementSheet(
        initial: _latestMeasurements,
        onSaved: _loadData,
      ),
    );
  }

  Future<void> _pickAndUploadPhoto(BuildContext context) async {
    final source = await _showPhotoSourceSheet();
    if (source == null) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.path.split('.').last.toLowerCase();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final storagePath = '$uid/gallery_${ts}.$ext';
      await Supabase.instance.client.storage
          .from('progress-photos')
          .uploadBinary(storagePath, bytes,
            fileOptions: FileOptions(contentType: 'image/$ext', upsert: false));
      await Supabase.instance.client.from('progress_photo_logs').insert({
        'user_id': uid,
        'storage_path': storagePath,
        'side': 'gallery',
        'logged_at': DateTime.now().toIso8601String(),
      });
      ScoreService().addCheckinPoints();
      ScoreEngine().progressPhotos();
      _loadData();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload photo'), backgroundColor: Colors.red));
      }
    }
  }

  // Sets one of the baseline (start) photos — front / side / back — writing to
  // the SAME `<uid>/<side>.<ext>` path the onboarding step uses, so it shows in
  // the Comparison Tool here and in the coach's client view.
  Future<void> _setBaselinePhoto(BuildContext context, String side) async {
    var source = await _showPhotoSourceSheet();
    if (source == null) return;
    // The browser can't open a native camera — fall back to the file picker.
    if (kIsWeb && source == ImageSource.camera) source = ImageSource.gallery;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final bytes = await picked.readAsBytes();
      final ext = _baselineExt(picked);
      final mime = ext == 'png' ? 'image/png'
          : ext == 'webp' ? 'image/webp'
          : ext == 'heic' ? 'image/heic' : 'image/jpeg';
      final storage = Supabase.instance.client.storage.from('progress-photos');
      // Upload first, then clear other-extension copies (QAX-COR-07): the
      // bucket grants the owner UPDATE (migration 029), so upsert replaces in
      // place and a failed upload can no longer delete the existing photo.
      await replaceBaselinePhoto(
        uid: uid, side: side, ext: ext,
        upload: (path) => storage.uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true)),
        remove: (paths) => storage.remove(paths),
        onCleanupError: (e, s) =>
            reportError('ProgressScreen._setBaselinePhoto.cleanup', e, s),
      );
      _loadData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${side[0].toUpperCase()}${side.substring(1)} photo updated')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed.'), backgroundColor: Colors.red));
      }
    }
  }

  String _baselineExt(XFile f) {
    const known = ['jpg', 'jpeg', 'png', 'heic', 'webp'];
    final name = f.name.toLowerCase();
    if (name.contains('.')) {
      final e = name.split('.').last;
      if (known.contains(e)) return e;
    }
    final m = (f.mimeType ?? '').toLowerCase();
    if (m.contains('png')) return 'png';
    if (m.contains('webp')) return 'webp';
    if (m.contains('heic')) return 'heic';
    return 'jpg';
  }

  Future<ImageSource?> _showPhotoSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _C.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
            decoration: BoxDecoration(color: _C.outlineVar,
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.camera_alt_outlined, color: _C.primary),
            title: Text('Take Photo', style: TextStyle(color: _C.onSurface)),
            onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: _C.primary),
            title: Text('Choose from Gallery', style: TextStyle(color: _C.onSurface)),
            onTap: () => Navigator.pop(context, ImageSource.gallery)),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ── Weight Tab ────────────────────────────────────────────────────────────────
class _WeightTab extends StatelessWidget {
  final double currentKg;
  final double goalKg;
  final List<Map<String, dynamic>> logs;
  final VoidCallback onLogWeight;
  const _WeightTab({
    required this.currentKg, required this.goalKg,
    required this.logs, required this.onLogWeight,
  });

  double get _delta {
    if (logs.length < 2) return 0;
    final prev = (logs[1]['weight_kg'] as num).toDouble();
    return currentKg - prev;
  }

  String _fmtDate(String iso) {
    final d = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today, ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    }
    return '${_month(d.month)} ${d.day}, ${d.year}';
  }

  String _month(int m) => const ['','Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'][m];

  @override
  Widget build(BuildContext context) {
    final remaining = (currentKg - goalKg).abs();
    final weeklyAvg = logs.length >= 7
        ? logs.take(7).map((l) => (l['weight_kg'] as num).toDouble()).reduce((a,b)=>a+b) / 7
        : currentKg;
    final delta = _delta;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Current weight card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _C.glassCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x0DFFFFFF)),
                ),
                child: Column(
                  children: [
                    const Text('CURRENT WEIGHT',
                      style: TextStyle(color: _C.primary, fontSize: 10,
                        fontWeight: FontWeight.w700, letterSpacing: 2)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(currentKg > 0 ? currentKg.toStringAsFixed(1) : '--',
                          style: const TextStyle(color: _C.onSurface, fontSize: 56,
                            fontWeight: FontWeight.w800, letterSpacing: -2)),
                        const SizedBox(width: 6),
                        const Text('kg', style: TextStyle(color: _C.outline, fontSize: 20,
                          fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (logs.length >= 2)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _C.tertiary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(delta <= 0 ? Icons.trending_down : Icons.trending_up,
                            color: delta <= 0 ? _C.tertiary : _C.error, size: 16),
                          const SizedBox(width: 6),
                          RichText(
                            text: TextSpan(children: [
                              TextSpan(
                                text: '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg',
                                style: TextStyle(
                                  color: delta <= 0 ? _C.tertiary : _C.error,
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                              TextSpan(text: ' since last entry',
                                style: TextStyle(color: _C.outline.withValues(alpha: 0.8),
                                  fontSize: 13)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Weight history chart
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Weight History',
                    style: TextStyle(color: _C.onSurface, fontSize: 20,
                      fontWeight: FontWeight.w700)),
                  Text('Last ${logs.length} ${logs.length == 1 ? 'Entry' : 'Entries'}',
                    style: const TextStyle(color: _C.primary, fontSize: 11,
                      fontWeight: FontWeight.w600, letterSpacing: 1)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 180,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                decoration: BoxDecoration(
                  color: _C.glassCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x0DFFFFFF)),
                ),
                child: logs.isEmpty
                  ? const Center(
                      child: Text('Log your first weight to see your chart',
                        style: TextStyle(color: _C.outline, fontSize: 13)))
                  : Column(
                      children: [
                        Expanded(
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _WeightChartPainter(logs: logs),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: _chartLabels(logs).map((l) => Text(l,
                            style: TextStyle(color: _C.outline.withValues(alpha: 0.5),
                              fontSize: 9, fontWeight: FontWeight.w600)))
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
              ),
              const SizedBox(height: 20),

              // Stats grid
              Row(children: [
                Expanded(child: _StatCard(
                  label: 'GOAL',
                  value: goalKg > 0 ? goalKg.toStringAsFixed(1) : '--',
                  unit: 'kg', color: _C.primary)),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(
                  label: 'REMAINING',
                  value: (currentKg > 0 && goalKg > 0) ? remaining.toStringAsFixed(1) : '--',
                  unit: 'kg', color: _C.tertiary, highlight: true)),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(
                  label: 'WEEKLY AVG',
                  value: logs.isNotEmpty ? weeklyAvg.toStringAsFixed(1) : '--',
                  unit: 'kg', color: _C.secondary)),
              ]),
              const SizedBox(height: 24),

              // Recent history
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent History',
                    style: TextStyle(color: _C.onSurface, fontSize: 20,
                      fontWeight: FontWeight.w700)),
                  Text('View All',
                    style: TextStyle(color: _C.primary, fontSize: 13,
                      fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
              if (logs.isEmpty)
                const Center(
                  child: Text('No entries yet — tap + to log your weight',
                    style: TextStyle(color: _C.outline, fontSize: 13)))
              else
                ...logs.take(10).toList().asMap().entries.map((e) => _HistoryRow(
                  weight: '${(e.value['weight_kg'] as num).toStringAsFixed(1)} kg',
                  date: _fmtDate(e.value['logged_at'] as String),
                  isToday: e.key == 0,
                )),
            ],
          ),
        ),

        // FAB
        Positioned(
          bottom: 110, right: 16,
          child: _ProgressFab(onTap: onLogWeight),
        ),
      ],
    );
  }
}

List<String> _chartLabels(List<Map<String, dynamic>> logs) {
  if (logs.isEmpty) return [];
  final indices = [logs.length - 1, (logs.length * 2 ~/ 3), (logs.length ~/ 3), 0]
      .where((i) => i >= 0 && i < logs.length).toSet().toList()..sort();
  return indices.map((i) {
    final d = DateTime.parse(logs[i]['logged_at'] as String).toLocal();
    return '${_monthShort(d.month)} ${d.day}';
  }).toList();
}

String _monthShort(int m) => const ['','Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'][m];

// ── Measurements Tab ──────────────────────────────────────────────────────────
class _MeasurementsTab extends StatelessWidget {
  final Map<String, dynamic>? measurements;
  final List<Map<String, dynamic>> history;
  final String? frontPhotoUrl;
  final String? latestGalleryUrl;
  final VoidCallback onLog;
  const _MeasurementsTab({
    this.measurements,
    required this.history,
    this.frontPhotoUrl,
    this.latestGalleryUrl,
    required this.onLog,
  });

  List<Widget> _buildHealthInsights() {
    final waist = (measurements?['waist_cm'] as num?)?.toDouble();
    final hips  = (measurements?['hips_cm']  as num?)?.toDouble();
    final chest = (measurements?['chest_cm'] as num?)?.toDouble();

    final insights = <Widget>[];

    if (waist != null && hips != null && hips > 0) {
      final whr = waist / hips;
      final whrLabel = whr.toStringAsFixed(2);
      final isHealthy = whr <= 0.85;
      insights.add(_InsightRow(
        icon: isHealthy ? Icons.check_circle_outline : Icons.warning_amber_outlined,
        color: isHealthy ? _C.tertiary : _C.error,
        text: 'Waist-to-hip ratio: $whrLabel — ${isHealthy ? 'within healthy athletic range (≤0.85).' : 'above recommended range. Reducing waist can improve this.'}',
      ));
      insights.add(const SizedBox(height: 8));
    }

    if (history.length >= 2) {
      final firstWaist = (history.first['waist_cm'] as num?)?.toDouble();
      final lastWaist  = (history.last['waist_cm']  as num?)?.toDouble();
      if (firstWaist != null && lastWaist != null) {
        final change = lastWaist - firstWaist;
        final improving = change < 0;
        insights.add(_InsightRow(
          icon: improving ? Icons.trending_down : Icons.trending_up,
          color: improving ? _C.primary : _C.outline,
          text: improving
            ? 'Waist reduced by ${change.abs().toStringAsFixed(1)} cm since your first measurement. Great progress!'
            : 'Waist has changed by +${change.toStringAsFixed(1)} cm. Focus on nutrition and cardio to see reduction.',
        ));
        insights.add(const SizedBox(height: 8));
      }
    }

    if (chest != null && waist != null && waist > 0) {
      final ratio = chest / waist;
      insights.add(_InsightRow(
        icon: Icons.straighten_outlined,
        color: _C.secondary,
        text: 'Chest-to-waist ratio: ${ratio.toStringAsFixed(2)}. ${ratio >= 1.2 ? 'Good hourglass proportion.' : 'Keep building upper body strength to improve this ratio.'}',
      ));
      insights.add(const SizedBox(height: 8));
    }

    if (insights.isEmpty) {
      insights.add(const _InsightRow(
        icon: Icons.info_outline,
        color: _C.outline,
        text: 'Log at least two measurements to see personalised health insights.',
      ));
    }

    return insights;
  }

  String _updatedAgo() {
    final raw = measurements?['logged_at'] as String?;
    if (raw == null) return 'No entries yet';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inDays >= 1) return 'Updated ${diff.inDays}d ago';
    if (diff.inHours >= 1) return 'Updated ${diff.inHours}h ago';
    return 'Updated just now';
  }

  @override
  Widget build(BuildContext context) {
    String _v(String key) {
      final v = measurements?[key];
      return v != null ? '${(v as num).toStringAsFixed(1)} cm' : '-- cm';
    }
    final rows = [
      ('Chest',  _v('chest_cm'),  false),
      ('Waist',  _v('waist_cm'),  true),
      ('Hips',   _v('hips_cm'),   false),
      ('Arms',   _v('arms_cm'),   false),
      ('Thighs', _v('thighs_cm'), false),
    ];
    final measurementDisplay = rows.map((r) => (r.$1, r.$2, '', r.$3)).toList();

    // Waist stats from history
    final waistValues = history
        .where((r) => r['waist_cm'] != null)
        .map((r) => (r['waist_cm'] as num).toDouble())
        .toList();
    final waistPeak   = waistValues.isNotEmpty ? waistValues.reduce(math.max) : 0.0;
    final waistLowest = waistValues.isNotEmpty ? waistValues.reduce(math.min) : 0.0;
    final waistTrend  = (waistValues.length >= 2)
        ? ((waistValues.last - waistValues.first) / waistValues.first * 100)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Body progress card
          Container(
            decoration: BoxDecoration(
              color: _C.glassCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x0DFFFFFF)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Body Progress',
                        style: TextStyle(color: _C.onSurface, fontSize: 16,
                          fontWeight: FontWeight.w700)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _C.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(_updatedAgo(),
                          style: const TextStyle(color: _C.primary, fontSize: 10,
                            fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                ...measurementDisplay.map((m) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(
                      color: _C.outlineVar.withValues(alpha: 0.2))),
                  ),
                  child: Row(children: [
                    Icon(Icons.straighten_outlined,
                      color: m.$4 ? _C.primary : _C.onSurfaceVar, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(m.$1,
                        style: TextStyle(
                          color: m.$4 ? _C.primary : _C.onSurface,
                          fontSize: 15,
                          fontWeight: m.$4 ? FontWeight.w700 : FontWeight.w400,
                        )),
                    ),
                    Text(m.$2,
                      style: TextStyle(
                        color: m.$4 ? _C.primary : _C.onSurface,
                        fontSize: 15, fontWeight: FontWeight.w700)),
                  ]),
                )),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GestureDetector(
                    onTap: onLog,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [_C.inversePrimary, _C.primaryContainer],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Log Measurement',
                            style: TextStyle(color: Colors.white, fontSize: 14,
                              fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tip card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _C.tertiary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _C.tertiary.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.lightbulb_outline, color: _C.tertiary, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Consistency is key! Try measuring at the same time each week.',
                  style: TextStyle(color: _C.onSurfaceVar, fontSize: 12,
                    fontStyle: FontStyle.italic, height: 1.4)),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Waist progress chart
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Waist Progress',
                    style: TextStyle(color: _C.onSurface, fontSize: 18,
                      fontWeight: FontWeight.w700)),
                  Text('Last 6 Months',
                    style: TextStyle(color: _C.outline, fontSize: 12)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _C.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('6M ▾',
                  style: TextStyle(color: _C.onSurface, fontSize: 12,
                    fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 160,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _C.glassCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x0DFFFFFF)),
            ),
            child: waistValues.length < 2
              ? const Center(child: Text('Log measurements to see your chart',
                  style: TextStyle(color: _C.outline, fontSize: 13)))
              : Column(
                  children: [
                    Expanded(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _WaistChartPainter(values: waistValues, history: history),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: _waistChartLabels(history),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(children: [
            Expanded(child: _StatCard(
              label: 'PEAK',
              value: waistPeak > 0 ? waistPeak.toStringAsFixed(1) : '--',
              unit: 'cm', color: _C.outline)),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(
              label: 'LOWEST',
              value: waistLowest > 0 ? waistLowest.toStringAsFixed(1) : '--',
              unit: 'cm', color: _C.tertiary)),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(
              label: 'TREND',
              value: waistValues.length >= 2
                ? '${waistTrend >= 0 ? '+' : ''}${waistTrend.toStringAsFixed(1)}%'
                : '--',
              unit: '', color: waistTrend <= 0 ? _C.tertiary : _C.error)),
          ]),
          const SizedBox(height: 24),

          // Visual comparison
          const Text('Visual Comparison',
            style: TextStyle(color: _C.onSurface, fontSize: 20,
              fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Side-by-side comparison from your first progress photo vs. your latest.',
            style: TextStyle(color: _C.onSurfaceVar, fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          _VisualComparison(
            firstUrl: frontPhotoUrl,
            latestUrl: latestGalleryUrl ?? frontPhotoUrl,
            history: history,
          ),
          const SizedBox(height: 16),

          // Health insights from real data
          const Text('Health Insights',
            style: TextStyle(color: _C.onSurface, fontSize: 18,
              fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ..._buildHealthInsights(),
        ],
      ),
    );
  }
}

// ── Photos Tab ────────────────────────────────────────────────────────────────
int _calcPhotoStreak(List<Map<String, dynamic>> logs) {
  final days = <String>{};
  for (final log in logs) {
    final raw = (log['logged_at'] ?? log['created_at']) as String?;
    if (raw == null) continue;
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) continue;
    days.add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }
  if (days.isEmpty) return 0;
  int streak = 0;
  var day = DateTime.now().toLocal();
  while (true) {
    final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    if (!days.contains(key)) break;
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}

class _PhotosTab extends StatelessWidget {
  final String? frontUrl, sideUrl, backUrl;
  final List<Map<String, dynamic>> photoLogs;
  final Map<String, String> galleryUrls;
  final VoidCallback onRefresh;
  final VoidCallback onAddPhoto;
  final void Function(String side) onSetBaseline;
  const _PhotosTab({
    this.frontUrl, this.sideUrl, this.backUrl,
    required this.photoLogs, required this.galleryUrls,
    required this.onRefresh, required this.onAddPhoto,
    required this.onSetBaseline,
  });

  // One baseline angle (front / side / back). Always tappable — empty shows an
  // "Add" placeholder; set shows the photo with an edit affordance.
  Widget _baselineSlot(String side, String label, String? url) => GestureDetector(
    onTap: () => onSetBaseline(side),
    child: Column(children: [
      AspectRatio(
        aspectRatio: 3 / 4,
        child: Container(
          decoration: BoxDecoration(
            color: _C.glassCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: url != null
                  ? _C.primary.withValues(alpha: 0.4)
                  : _C.outlineVar.withValues(alpha: 0.3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: url != null
              ? Stack(fit: StackFit.expand, children: [
                  Image.network(url, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _slotEmpty()),
                  Positioned(bottom: 6, right: 6, child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.edit, color: Colors.white, size: 13))),
                ])
              : _slotEmpty(),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: TextStyle(
        color: url != null ? _C.onSurface : _C.outline,
        fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _slotEmpty() => const Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.add_a_photo_outlined, color: _C.outline, size: 24),
      SizedBox(height: 4),
      Text('Add', style: TextStyle(color: _C.outline, fontSize: 11)),
    ],
  ));

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Start / baseline photos — front, side & back, each independently set
          const Text('Start Photos',
            style: TextStyle(color: _C.onSurface, fontSize: 20,
              fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Tap a slot to add or replace each angle. These are your Day 1 baseline.',
            style: TextStyle(color: _C.outline, fontSize: 12)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _baselineSlot('front', 'Front', frontUrl)),
              const SizedBox(width: 10),
              Expanded(child: _baselineSlot('side', 'Side', sideUrl)),
              const SizedBox(width: 10),
              Expanded(child: _baselineSlot('back', 'Back', backUrl)),
            ],
          ),
          const SizedBox(height: 16),

          // Streak + Add Photo side by side
          Row(
            children: [
              // Streak card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _C.glassCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x0DFFFFFF)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _C.tertiary.withValues(alpha: 0.15),
                        ),
                        child: Icon(Icons.emoji_events_outlined,
                          color: _C.tertiary, size: 24),
                      ),
                      const SizedBox(height: 8),
                      const Text('STREAK',
                        style: TextStyle(color: _C.outline, fontSize: 10,
                          fontWeight: FontWeight.w600, letterSpacing: 2)),
                      Text(_calcPhotoStreak(photoLogs).toString(),
                        style: const TextStyle(color: _C.tertiary, fontSize: 40,
                          fontWeight: FontWeight.w800, height: 1)),
                      const Text('Days Consistent',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _C.onSurfaceVar, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Add photo card
              Expanded(
                child: GestureDetector(
                  onTap: onAddPhoto,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _C.glassCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _C.outlineVar.withValues(alpha: 0.3)),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined, color: _C.primary, size: 32),
                        SizedBox(height: 8),
                        Text('Add Photo',
                          style: TextStyle(color: _C.onSurface, fontSize: 15,
                            fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text('Capture current form',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _C.onSurfaceVar, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Progress gallery (with working side-filter + grid/list toggle)
          _ProgressGallery(
            photoLogs: photoLogs,
            galleryUrls: galleryUrls,
            frontUrl: frontUrl,
            sideUrl: sideUrl,
            backUrl: backUrl,
          ),
        ],
      ),
    );
  }
}

// ── Log Measurement Bottom Sheet ─────────────────────────────────────────────
class LogMeasurementSheet extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final VoidCallback? onSaved;
  @visibleForTesting
  final ProgressRowWriter? writeRow;
  const LogMeasurementSheet({super.key, this.initial, this.onSaved, this.writeRow});

  @override
  State<LogMeasurementSheet> createState() => LogMeasurementSheetState();
}

class LogMeasurementSheetState extends State<LogMeasurementSheet> {
  late final Map<String, TextEditingController> _ctrls;
  bool _saving = false;
  String? _error;

  static const _fields = [
    ('Chest', 'chest_cm', Icons.straighten_outlined),
    ('Waist', 'waist_cm', Icons.accessibility_new_outlined),
    ('Hips',  'hips_cm',  Icons.straighten_outlined),
    ('Arms',  'arms_cm',  Icons.fitness_center_outlined),
    ('Thighs','thighs_cm',Icons.straighten_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final f in _fields)
        f.$2: TextEditingController(
          text: widget.initial?[f.$2] != null
              ? (widget.initial![f.$2] as num).toStringAsFixed(1)
              : ''),
    };
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final data = <String, dynamic>{
        'logged_at': DateTime.now().toIso8601String(),
      };
      for (final f in _fields) {
        final v = double.tryParse(_ctrls[f.$2]!.text.trim());
        if (v != null) data[f.$2] = v;
      }
      await (widget.writeRow ?? _supabaseProgressInsert)('body_measurements', data);
    } catch (e, s) {
      reportError('LogMeasurementSheet._save', e, s);
      if (mounted) setState(() { _saving = false; _error = progressSaveFailedMessage; });
      return;
    }
    // The row is stored. Points are a follow-up: their failure must not make a
    // saved entry look failed (a retry would insert a duplicate measurement).
    try {
      await ScoreService().addCheckinPoints();
    } catch (e, s) {
      reportError('LogMeasurementSheet._save.points', e, s);
    }
    if (mounted) {
      Navigator.pop(context);
      widget.onSaved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1B1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 40, height: 4,
              decoration: BoxDecoration(color: _C.outlineVar,
                borderRadius: BorderRadius.circular(2))),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Log Measurements',
                  style: TextStyle(color: _C.onSurface, fontSize: 22,
                    fontWeight: FontWeight.w700)),
                // F-22: "Close" is the design package's own word (declared on
                // its sheet frames), so naming this invents nothing. It was an
                // icon-only control reporting no name at all.
                Semantics(
                  button: true,
                  label: 'Close',
                  child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    alignment: Alignment.center,
                    child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: _C.surfaceContainerHigh),
                    child: const Icon(Icons.close, color: _C.onSurfaceVar, size: 18))))),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Enter measurements in centimetres',
              style: TextStyle(color: _C.outline, fontSize: 13)),
            const SizedBox(height: 20),
            ..._fields.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Icon(f.$3, color: _C.onSurfaceVar, size: 20),
                const SizedBox(width: 12),
                SizedBox(width: 80, child: Text(f.$1,
                  style: const TextStyle(color: _C.onSurface, fontSize: 15))),
                Expanded(
                  child: TextField(
                    controller: _ctrls[f.$2],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: _C.onSurface, fontSize: 15),
                    decoration: InputDecoration(
                      suffixText: 'cm',
                      suffixStyle: const TextStyle(color: _C.outline, fontSize: 13),
                      filled: true,
                      fillColor: _C.surfaceContainerHigh,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ]),
            )),
            const SizedBox(height: 8),
            if (_error != null) _ProgressSaveError(_error!),
            GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [_C.inversePrimary, _C.primaryContainer],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: const [BoxShadow(color: Color(0x55842BD2), blurRadius: 20)],
                ),
                alignment: Alignment.center,
                child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save Measurements',
                      style: TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown in a progress sheet when its save did not land (QAX-COR-06).
const progressSaveFailedMessage = "Couldn't save — check your connection and try again.";

class _ProgressSaveError extends StatelessWidget {
  const _ProgressSaveError(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(message, textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFF6B8A), fontSize: 13)),
      );
}

/// Persists one progress row. Injected in tests; the default writes to Supabase.
typedef ProgressRowWriter = Future<void> Function(String table, Map<String, dynamic> row);

Future<void> _supabaseProgressInsert(String table, Map<String, dynamic> row) async {
  final db = Supabase.instance.client;
  final uid = db.auth.currentUser?.id;
  // Refuse rather than no-op: a silently discarded save looked like a hang.
  if (uid == null) throw StateError('Not signed in — the entry was not saved.');
  await db.from(table).insert({...row, 'user_id': uid});
}

// ── Log Weight Bottom Sheet ───────────────────────────────────────────────────
class LogWeightSheet extends StatefulWidget {
  final double initialKg;
  final VoidCallback? onSaved;
  @visibleForTesting
  final ProgressRowWriter? writeRow;
  const LogWeightSheet({super.key, this.initialKg = 80.0, this.onSaved, this.writeRow});

  @override
  State<LogWeightSheet> createState() => LogWeightSheetState();
}

class LogWeightSheetState extends State<LogWeightSheet> {
  bool _isLbs = false;
  late double _weight;
  bool _saving = false;
  String? _error;
  bool _showNote = false;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _weight = widget.initialKg;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final kg = _isLbs ? _weight / 2.20462 : _weight;
      await (widget.writeRow ?? _supabaseProgressInsert)('weight_logs', {
        'weight_kg': kg,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'logged_at': DateTime.now().toIso8601String(),
      });
    } catch (e, s) {
      reportError('LogWeightSheet._save', e, s);
      if (mounted) setState(() { _saving = false; _error = progressSaveFailedMessage; });
      return;
    }
    if (mounted) {
      Navigator.pop(context);
      widget.onSaved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1B1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: _C.outlineVar,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Log Weight',
                style: TextStyle(color: _C.onSurface, fontSize: 22,
                  fontWeight: FontWeight.w700)),
              Semantics(
                button: true,
                label: 'Close',
                child: GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  alignment: Alignment.center,
                  child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _C.surfaceContainerHigh,
                  ),
                  child: const Icon(Icons.close, color: _C.onSurfaceVar, size: 18),
                ),
                ),
              ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Date + unit toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _C.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                    color: _C.onSurfaceVar, size: 16),
                  const SizedBox(width: 8),
                  Text('Today, ${_monthShort(DateTime.now().month)} ${DateTime.now().day}',
                    style: const TextStyle(color: _C.onSurface, fontSize: 14,
                      fontWeight: FontWeight.w500)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _C.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(children: ['LBS', 'KG'].map((u) {
                  final active = (_isLbs && u == 'LBS') || (!_isLbs && u == 'KG');
                  return GestureDetector(
                    onTap: () => setState(() => _isLbs = u == 'LBS'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: active ? _C.primaryContainer : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(u,
                        style: TextStyle(
                          color: active ? _C.onPrimary : _C.outline,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        )),
                    ),
                  );
                }).toList()),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Weight display
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text((_isLbs ? _weight * 2.20462 : _weight).toStringAsFixed(1),
                style: const TextStyle(color: _C.onSurface, fontSize: 52,
                  fontWeight: FontWeight.w800, letterSpacing: -2)),
              const SizedBox(width: 6),
              Text(_isLbs ? 'lbs' : 'kg',
                style: const TextStyle(color: _C.outline, fontSize: 20,
                  fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),

          // Ruler slider (always kg internally, 30–250 kg)
          SizedBox(
            height: 64,
            child: _RulerSlider(
              value: _weight,
              min: 30,
              max: 250,
              onChanged: (v) => setState(() => _weight = v),
            ),
          ),
          const SizedBox(height: 8),

          // Add note
          GestureDetector(
            onTap: () => setState(() => _showNote = !_showNote),
            child: Row(children: [
              Icon(_showNote ? Icons.remove_circle_outline : Icons.add_circle_outline,
                color: _C.onSurfaceVar, size: 20),
              const SizedBox(width: 8),
              Text(_showNote ? 'Remove Note' : 'Add Note',
                style: const TextStyle(color: _C.onSurfaceVar, fontSize: 14,
                  fontWeight: FontWeight.w500)),
            ]),
          ),
          if (_showNote) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              style: const TextStyle(color: _C.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'How are you feeling today?',
                hintStyle: const TextStyle(color: _C.outlineVar, fontSize: 13),
                filled: true,
                fillColor: _C.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Save button
          if (_error != null) _ProgressSaveError(_error!),
          GestureDetector(
            onTap: _saving ? null : _save,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  colors: [_C.inversePrimary, _C.primaryContainer],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x55842BD2), blurRadius: 20),
                ],
              ),
              alignment: Alignment.center,
              child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('Save Entry',
                        style: TextStyle(color: Colors.white, fontSize: 15,
                          fontWeight: FontWeight.w700, letterSpacing: 1)),
                    ],
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final bool highlight;
  const _StatCard({required this.label, required this.value,
    required this.unit, required this.color, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: _C.glassCard,
        borderRadius: BorderRadius.circular(12),
        border: Border(top: BorderSide(color: color.withValues(alpha: 0.4), width: 2)),
      ),
      child: Column(children: [
        Text(label,
          style: const TextStyle(color: _C.outline, fontSize: 9,
            fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value,
          style: TextStyle(color: highlight ? color : _C.onSurface,
            fontSize: 18, fontWeight: FontWeight.w700)),
        if (unit.isNotEmpty)
          Text(unit, style: const TextStyle(color: _C.outline, fontSize: 10)),
      ]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final String weight;
  final String date;
  final bool isToday;
  const _HistoryRow({required this.weight, required this.date,
    required this.isToday});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.glassCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: _C.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.scale_outlined,
            color: isToday ? _C.primary : _C.onSurfaceVar, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(weight,
                style: const TextStyle(color: _C.onSurface, fontSize: 15,
                  fontWeight: FontWeight.w600)),
              Text(date,
                style: const TextStyle(color: _C.outline, fontSize: 13)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: _C.outline, size: 20),
      ]),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InsightRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
            style: const TextStyle(color: _C.onSurfaceVar,
              fontSize: 13, height: 1.4)),
        ),
      ],
    );
  }
}

// ── Progress gallery with functional side-filter + grid/list toggle ──────────
class _ProgressGallery extends StatefulWidget {
  final List<Map<String, dynamic>> photoLogs;
  final Map<String, String> galleryUrls;
  final String? frontUrl, sideUrl, backUrl;
  const _ProgressGallery({
    required this.photoLogs, required this.galleryUrls,
    this.frontUrl, this.sideUrl, this.backUrl,
  });
  @override
  State<_ProgressGallery> createState() => _ProgressGalleryState();
}

class _ProgressGalleryState extends State<_ProgressGallery> {
  bool _grid = true;
  String _side = 'all'; // all | front | side | back

  List<Map<String, dynamic>> get _filtered => _side == 'all'
      ? widget.photoLogs
      : widget.photoLogs.where((l) => (l['side'] as String? ?? '') == _side).toList();

  String? _urlFor(Map<String, dynamic> log) {
    final side = log['side'] as String? ?? '';
    final path = log['storage_path'] as String?;
    if (path == null) {
      return side == 'front' ? widget.frontUrl : side == 'side' ? widget.sideUrl : widget.backUrl;
    }
    return widget.galleryUrls[path] ??
        (side == 'front' ? widget.frontUrl : side == 'side' ? widget.sideUrl : widget.backUrl);
  }

  String _dateOf(Map<String, dynamic> log) {
    final raw = (log['logged_at'] ?? log['created_at']) as String?;
    final d = raw != null ? DateTime.tryParse(raw)?.toLocal() : null;
    return d != null ? '${_monthShort(d.month)} ${d.day}, ${d.year}' : '—';
  }

  String _labelOf(Map<String, dynamic> log) {
    final side = log['side'] as String? ?? '';
    return side.isNotEmpty ? '${side[0].toUpperCase()}${side.substring(1)} photo' : 'Progress photo';
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Progress Gallery',
                style: TextStyle(color: _C.onSurface, fontSize: 20, fontWeight: FontWeight.w700)),
            Row(children: [
              PopupMenuButton<String>(
                color: _C.surfaceContainer,
                tooltip: 'Filter',
                onSelected: (v) => setState(() => _side = v),
                itemBuilder: (_) => [
                  for (final s in const ['all', 'front', 'side', 'back'])
                    PopupMenuItem(
                      value: s,
                      child: Row(children: [
                        Icon(_side == s ? Icons.check : Icons.circle_outlined,
                            size: 16, color: _side == s ? _C.primary : _C.outline),
                        const SizedBox(width: 8),
                        Text(s == 'all' ? 'All photos' : '${s[0].toUpperCase()}${s.substring(1)}',
                            style: const TextStyle(color: _C.onSurface)),
                      ]),
                    ),
                ],
                child: Icon(Icons.filter_list,
                    color: _side == 'all' ? _C.onSurfaceVar : _C.primary, size: 20),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () => setState(() => _grid = !_grid),
                child: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                    color: _C.onSurfaceVar, size: 20),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 12),
        if (logs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.photo_library_outlined, color: _C.outline, size: 40),
              const SizedBox(height: 12),
              Text(_side == 'all' ? 'No check-ins yet' : 'No ${_side} photos',
                  style: const TextStyle(color: _C.outline, fontSize: 14)),
              const SizedBox(height: 4),
              const Text('Upload progress photos to start your gallery',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _C.outlineVar, fontSize: 12)),
            ]),
          )
        else if (_grid)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.8),
            itemCount: logs.length,
            itemBuilder: (_, i) => _GalleryCard(
                date: _dateOf(logs[i]), label: _labelOf(logs[i]), url: _urlFor(logs[i])),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final url = _urlFor(logs[i]);
              return Container(
                decoration: BoxDecoration(
                  color: _C.glassCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x0DFFFFFF))),
                clipBehavior: Clip.antiAlias,
                child: Row(children: [
                  SizedBox(
                    width: 84, height: 84,
                    child: url != null
                        ? Image.network(url, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(color: _C.surfaceContainer,
                                child: const Icon(Icons.image_outlined, color: _C.outline)))
                        : Container(color: _C.surfaceContainer,
                            child: const Icon(Icons.image_outlined, color: _C.outline)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_labelOf(logs[i]),
                        style: const TextStyle(color: _C.onSurface, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(_dateOf(logs[i]), style: const TextStyle(color: _C.onSurfaceVar, fontSize: 12)),
                  ])),
                  const Padding(
                    padding: EdgeInsets.only(right: 14),
                    child: Icon(Icons.chevron_right, color: _C.outline)),
                ]),
              );
            },
          ),
      ],
    );
  }
}

class _GalleryCard extends StatelessWidget {
  final String date;
  final String label;
  final String? url;
  const _GalleryCard({required this.date, required this.label, this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: _C.surfaceContainer,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          url != null
            ? Image.network(url!, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: _C.surfaceContainer,
                  child: const Icon(Icons.broken_image_outlined, color: _C.outline, size: 32)))
            : Container(color: _C.surfaceContainer,
                child: const Icon(Icons.photo_outlined, color: _C.outline, size: 32)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xCC000000)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            bottom: 10, left: 10, right: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date,
                  style: const TextStyle(color: _C.primary, fontSize: 9,
                    fontWeight: FontWeight.w600, letterSpacing: 1)),
                Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Visual Comparison Widget ──────────────────────────────────────────────────
class _VisualComparison extends StatelessWidget {
  final String? firstUrl;
  final String? latestUrl;
  final List<Map<String, dynamic>> history;
  const _VisualComparison({this.firstUrl, this.latestUrl, required this.history});

  String _firstDate() {
    if (history.isEmpty) return 'Start';
    final raw = history.first['logged_at'] as String?;
    if (raw == null) return 'Start';
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return 'Start';
    return '${_monthShort(d.month)} ${d.year}';
  }

  Widget _photoCard(String? url, String label, bool isLatest) {
    final borderColor = isLatest ? _C.primary : Colors.white.withValues(alpha: 0.1);
    Widget image;
    if (url != null) {
      image = Image.network(url, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder());
    } else {
      image = _placeholder();
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          height: isLatest ? 150 : 130,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: isLatest ? 1.5 : 1),
            boxShadow: isLatest ? [BoxShadow(color: _C.primary.withValues(alpha: 0.2), blurRadius: 20)] : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: image,
        ),
        const SizedBox(height: 8),
        isLatest
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _C.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _C.primary.withValues(alpha: 0.4)),
              ),
              child: const Text('Today', style: TextStyle(color: _C.primary, fontSize: 11, fontWeight: FontWeight.w700)))
          : Text(label, style: TextStyle(color: _C.outline.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _placeholder() => Container(
    color: _C.surfaceContainer,
    child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.add_a_photo_outlined, color: _C.outline, size: 28),
      SizedBox(height: 4),
      Text('No photo', style: TextStyle(color: _C.outlineVar, fontSize: 10)),
    ])),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: _C.glassCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        if (latestUrl != null)
          Image.network(latestUrl!, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: _C.surfaceContainer)),
        Container(color: Colors.black.withValues(alpha: 0.45)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _photoCard(firstUrl, _firstDate(), false)),
            const SizedBox(width: 12),
            Expanded(child: _photoCard(latestUrl, 'Today', true)),
          ]),
        ),
      ]),
    );
  }
}

// ── Chart painters ────────────────────────────────────────────────────────────
class _WeightChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> logs;
  const _WeightChartPainter({this.logs = const []});

  @override
  void paint(Canvas canvas, Size size) {
    List<Offset> points;
    if (logs.length >= 2) {
      final weights = logs.map((l) => (l['weight_kg'] as num).toDouble()).toList();
      final minW = weights.reduce((a, b) => a < b ? a : b);
      final maxW = weights.reduce((a, b) => a > b ? a : b);
      final range = (maxW - minW).clamp(1.0, double.infinity);
      points = List.generate(weights.length, (i) {
        final x = size.width * i / (weights.length - 1);
        final y = size.height * (1 - (weights[i] - minW) / range) * 0.8 + size.height * 0.1;
        return Offset(x, y);
      });
    } else {
      points = [
        Offset(0, size.height * 0.8),
        Offset(size.width * 0.15, size.height * 0.6),
        Offset(size.width * 0.3, size.height * 0.7),
        Offset(size.width * 0.5, size.height * 0.4),
        Offset(size.width * 0.7, size.height * 0.5),
        Offset(size.width, size.height * 0.2),
      ];
    }

    final linePaint = Paint()
      ..color = const Color(0xFFDDB7FF)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFDDB7FF).withValues(alpha: 0.3),
          const Color(0xFFDDB7FF).withValues(alpha: 0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    path.moveTo(points[0].dx, points[0].dy);
    fillPath.moveTo(points[0].dx, size.height);
    fillPath.lineTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final cp1 = Offset((points[i].dx + points[i + 1].dx) / 2, points[i].dy);
      final cp2 = Offset((points[i].dx + points[i + 1].dx) / 2, points[i + 1].dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, points[i + 1].dx, points[i + 1].dy);
      fillPath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, points[i + 1].dx, points[i + 1].dy);
    }

    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // End dot
    canvas.drawCircle(points.last, 5, Paint()
      ..color = const Color(0xFFDDB7FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(points.last, 4, Paint()..color = const Color(0xFFDDB7FF));
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter old) => old.logs != logs;
}

List<Widget> _waistChartLabels(List<Map<String, dynamic>> history) {
  final withWaist = history.where((r) => r['waist_cm'] != null).toList();
  if (withWaist.isEmpty) return [];
  final count = withWaist.length;
  final indices = count <= 6
      ? List.generate(count, (i) => i)
      : [0, count ~/ 4, count ~/ 2, count * 3 ~/ 4, count - 1];
  return indices.map((i) {
    final raw = withWaist[i]['logged_at'] as String?;
    if (raw == null) return const SizedBox.shrink();
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return const SizedBox.shrink();
    return Text('${_monthShort(d.month)} ${d.day}',
      style: const TextStyle(color: _C.outline, fontSize: 9,
        fontWeight: FontWeight.w600, letterSpacing: 0.5));
  }).toList();
}

class _WaistChartPainter extends CustomPainter {
  final List<double> values;
  final List<Map<String, dynamic>> history;
  const _WaistChartPainter({required this.values, required this.history});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).clamp(1.0, double.infinity);

    final points = List.generate(values.length, (i) {
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - (values[i] - minV) / range) * 0.8 + size.height * 0.1;
      return Offset(x, y);
    });

    final linePaint = Paint()
      ..color = const Color(0xFF4EDEA3)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length - 1; i++) {
      final cp1 = Offset((points[i].dx + points[i + 1].dx) / 2, points[i].dy);
      final cp2 = Offset((points[i].dx + points[i + 1].dx) / 2, points[i + 1].dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, points[i + 1].dx, points[i + 1].dy);
    }
    canvas.drawPath(path, linePaint);

    final lastPt = points.last;
    final label = '${values.last.toStringAsFixed(1)}cm';
    final tooltipPaint = Paint()..color = const Color(0xFF2A2A2B)..style = PaintingStyle.fill;
    final tooltipRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(lastPt.dx - 28, lastPt.dy - 20), width: 56, height: 22),
      const Radius.circular(6));
    canvas.drawRRect(tooltipRect, tooltipPaint);

    final tp = TextPainter(
      text: TextSpan(text: label,
        style: const TextStyle(color: Color(0xFF4EDEA3), fontSize: 10, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(lastPt.dx - 28 - tp.width / 2, lastPt.dy - 29));

    canvas.drawCircle(lastPt, 4, Paint()..color = const Color(0xFF4EDEA3));
  }

  @override
  bool shouldRepaint(_WaistChartPainter old) =>
      old.values != values;
}

// ── Ruler Slider ──────────────────────────────────────────────────────────────
class _RulerSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  const _RulerSlider({required this.value, required this.min,
    required this.max, required this.onChanged});

  @override
  State<_RulerSlider> createState() => _RulerSliderState();
}

class _RulerSliderState extends State<_RulerSlider> {
  late ScrollController _scrollCtrl;
  static const double _tickSpacing = 8.0;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    final initialOffset = (widget.value - widget.min) * _tickSpacing;
    _scrollCtrl = ScrollController(initialScrollOffset: initialOffset);
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_isScrolling) return;
    final v = (_scrollCtrl.offset / _tickSpacing) + widget.min;
    widget.onChanged(v.clamp(widget.min, widget.max));
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalTicks = ((widget.max - widget.min) * 2).toInt();
    return Stack(
      alignment: Alignment.center,
      children: [
        // Scrollable ruler
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            _isScrolling = n is ScrollUpdateNotification;
            return false;
          },
          child: ListView.builder(
            controller: _scrollCtrl,
            scrollDirection: Axis.horizontal,
            itemCount: totalTicks,
            itemExtent: _tickSpacing,
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width / 2),
            itemBuilder: (_, i) {
              final val = widget.min + i * 0.5;
              final isMajor = val % 5 == 0 && val == val.roundToDouble();
              final isMid   = val == val.roundToDouble();
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 1.5,
                      height: isMajor ? 36 : isMid ? 24 : 14,
                      color: isMajor
                          ? _C.primary.withValues(alpha: 0.8)
                          : isMid
                              ? _C.onSurfaceVar.withValues(alpha: 0.5)
                              : _C.outlineVar.withValues(alpha: 0.3),
                    ),
                    if (isMajor) ...[
                      const SizedBox(height: 4),
                      Text('${val.toInt()}',
                        style: const TextStyle(
                          color: _C.outline, fontSize: 9,
                          fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              );
            },
          ),
        ),

        // Center indicator line
        Container(
          width: 2, height: 48,
          decoration: BoxDecoration(
            color: _C.primary,
            borderRadius: BorderRadius.circular(1),
            boxShadow: [
              BoxShadow(color: _C.primary.withValues(alpha: 0.6), blurRadius: 8),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Progress Premium FAB ──────────────────────────────────────────────────────
class _ProgressFab extends StatefulWidget {
  final VoidCallback onTap;
  const _ProgressFab({required this.onTap});
  @override
  State<_ProgressFab> createState() => _ProgressFabState();
}

class _ProgressFabState extends State<_ProgressFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _glowAnim = Tween<double>(begin: 0.3, end: 0.7)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Transform.scale(
          scale: _pulseAnim.value,
          child: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_C.inversePrimary, _C.primaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: _C.inversePrimary.withValues(alpha: _glowAnim.value),
                  blurRadius: 24, spreadRadius: 2),
                BoxShadow(color: _C.primary.withValues(alpha: _glowAnim.value * 0.4),
                  blurRadius: 40, spreadRadius: 4),
              ],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}
