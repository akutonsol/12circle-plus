import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../../core/observability/app_failure.dart';
import '../../../workout/presentation/widgets/section_load_failure.dart';
import '../../data/nutrition_service.dart';

const _card    = Color(0xFF0D0D1E);
const _brand   = Color(0xFFA855F7);
const _white   = Colors.white;
const _muted   = Color(0xFF888898);
const _green   = Color(0xFF6FFBBE);
const _redChip = Color(0xFFFFB4AB);

class ScanItem {
  final String name;
  /// Null = the analysis did not give it (not 0).
  final double? calories, protein, carbs, fat;
  const ScanItem({required this.name, required this.calories,
    required this.protein, required this.carbs, required this.fat});
}

class ScanResult {
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  /// Null = the analysis did not give it. Not part of the saved meal.
  final int? confidence;
  final List<ScanItem> items;

  const ScanResult({
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.confidence,
    this.items = const [],
  });

  /// Scales the whole estimate by a portion multiplier (for the slider).
  ScanResult scaled(double f) => ScanResult(
        name: name, confidence: confidence, items: items,
        calories: calories * f, protein: protein * f,
        carbs: carbs * f, fat: fat * f,
      );
}

/// What the analysis answered. A value it did not give is null — not 0, which
/// is an answer of its own (P0-FL-61). Only [whole] makes a [ScanResult], so a
/// meal with an invented 0 cannot reach `onAccept`.
class _Estimate {
  final String name;
  final double? calories, protein, carbs, fat;
  final int? confidence;
  final List<ScanItem> items;

  const _Estimate({
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.confidence,
    this.items = const [],
  });

  _Estimate.of(ScanResult r) : this(
        name: r.name, calories: r.calories, protein: r.protein,
        carbs: r.carbs, fat: r.fat, confidence: r.confidence, items: r.items);

  /// The values it did not give, as one phrase; null when it gave all of them.
  String? get missing {
    final names = [
      if (calories == null) 'calories',
      if (protein == null) 'protein',
      if (carbs == null) 'carbs',
      if (fat == null) 'fat',
    ];
    if (names.length < 2) return names.firstOrNull;
    return '${names.take(names.length - 1).join(', ')} and ${names.last}';
  }

  /// The meal to save; null while any of its values is not known.
  ScanResult? get whole {
    final cal = calories, p = protein, c = carbs, f = fat;
    if (cal == null || p == null || c == null || f == null) return null;
    return ScanResult(name: name, calories: cal, protein: p, carbs: c, fat: f,
        confidence: confidence, items: items);
  }
}

/// FIT-020 · the scan result's portion control — `Smaller` / `As shown` /
/// `Larger`.
///
/// ── WHY THESE ARE RELATIVE AND NOT THREE FIXED MULTIPLIERS ─────────────────
/// The anchor gives three words and no numbers. "Smaller" means *smaller than
/// what the scan estimated*, which is a relative operation; inventing absolute
/// values (0.75×, 1.5×) would be deciding, on the owner's behalf, how much food
/// a client just ate — and that number goes into their day's calories and to
/// their coach.
///
/// So the step is taken from the control this screen ALREADY ships: a slider
/// over 0.25–3.0 with 11 divisions. One division is
/// `(3.0 - 0.25) / 11 = 0.25`. The granularity is the product's own, not a
/// figure chosen here.
///
/// `As shown` returns to 1.0 — the scan's own estimate, which is the one value
/// in this control that is not a judgement.
const scanPortionMin = 0.25;
const scanPortionMax = 3.0;
const scanPortionDivisions = 11;

/// One slider division: the granularity the shipped control already defines.
const scanPortionStep =
    (scanPortionMax - scanPortionMin) / scanPortionDivisions;

/// `Smaller` — one step down, never below the control's own floor.
double portionSmaller(double current) =>
    ((current - scanPortionStep).clamp(scanPortionMin, scanPortionMax)).toDouble();

/// `Larger` — one step up, never above the ceiling.
double portionLarger(double current) =>
    ((current + scanPortionStep).clamp(scanPortionMin, scanPortionMax)).toDouble();

/// `As shown` — the scan's own estimate.
const portionAsShown = 1.0;

/// FIT-020's save label: `Save to lunch`.
///
/// The meal type is the chip the client selected on the sheet, so the word is
/// real data rather than the anchor's example. Lower-cased to match the way the
/// design writes it in a sentence.
String scanSaveLabel(String mealType) {
  final m = mealType.trim();
  if (m.isEmpty) return 'Save';
  return 'Save to ${m.replaceAll('_', ' ').toLowerCase()}';
}

class AiScanView extends StatefulWidget {
  final void Function(ScanResult result) onAccept;
  /// The meal chip currently selected on the sheet — FIT-020 names the save
  /// button after it.
  final String mealType;
  /// FIT-020 declares "Search instead": leave the scan and go to the search
  /// tab. Null hides the control rather than drawing one that does nothing.
  final VoidCallback? onSearchInstead;
  /// Visible for testing. The result state is only reachable by running a real
  /// scan — a camera, an upload and a model call — so the wiring below it
  /// (FIT-020's three portion words, the save label, "Search instead") could
  /// not otherwise be asserted at all. Same seam as
  /// `WorkoutCompleteDialog.submit`.
  final ScanResult? initialResult;

  const AiScanView({
    super.key,
    required this.onAccept,
    this.mealType = 'lunch',
    this.onSearchInstead,
    this.initialResult,
  });

  @override
  State<AiScanView> createState() => _AiScanViewState();
}

enum _ScanStage { idle, scanning, result }

class _AiScanViewState extends State<AiScanView> {
  final _picker = ImagePicker();
  final _descCtrl = TextEditingController();
  XFile? _image;
  _ScanStage _stage = _ScanStage.idle;
  _Estimate? _result;
  /// The member [_result] was read for, and the one who typed the description.
  String? _resultUid, _descUid;
  double _portion = 1.0; // serving multiplier applied before logging
  /// A picker is open (or its file is being read): no second one opens.
  bool _picking = false;
  /// What the last photo attempt's failure says (null = none). Inline, not a
  /// SnackBar: this view lives in the Log Meal bottom sheet, and a SnackBar
  /// belongs to the page BEHIND it — it was drawn under the sheet, unseen
  /// (P0-FL-56a).
  String? _notice;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  _Estimate _parse(Map<String, dynamic> r) {
    double? d(dynamic v) => (v as num?)?.toDouble();
    final rawItems = (r['items'] as List?) ?? const [];
    final estimate = _Estimate(
      name: (r['name'] as String?)?.trim().isNotEmpty == true
          ? r['name'] as String : 'Scanned meal',
      calories: d(r['calories']),
      protein: d(r['protein_g']),
      carbs: d(r['carbs_g']),
      fat: d(r['fat_g']),
      confidence: (r['confidence'] as num?)?.toInt(),
      items: rawItems.whereType<Map>().map((m) => ScanItem(
        name: (m['name'] as String?) ?? 'Item',
        calories: d(m['calories']), protein: d(m['protein_g']),
        carbs: d(m['carbs_g']), fat: d(m['fat_g']),
      )).toList(),
    );
    final missing = estimate.missing;
    if (missing != null) {
      reportError('nutrition.scan.incomplete',
          StateError('the analysis gave no $missing'));
    }
    return estimate;
  }

  String? _signedInUid() => Supabase.instance.client.auth.currentUser?.id;

  /// True (recorded; the view goes back to its start without that member's
  /// photo, words or result, and nothing is said) when [uid] — whose meal this
  /// is — is no longer the member signed in.
  bool _memberChanged(String? uid) {
    if (_signedInUid() == uid) return false;
    reportError('nutrition.scan.identity',
        StateError('the member changed during a scan'));
    if (mounted) {
      _descCtrl.clear();
      setState(() {
        _image = null;
        _result = null;
        _resultUid = null;
        _descUid = null;
        _notice = null;
        _stage = _ScanStage.idle;
      });
    }
    return true;
  }

  // Describe a meal in words instead of a photo.
  Future<void> _describe() async {
    final text = _descCtrl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    // Whoever typed it: another member's tap does not send it.
    final uid = _descUid;
    if (_memberChanged(uid)) return;
    setState(() { _image = null; _notice = null; _stage = _ScanStage.scanning; });
    try {
      final r = await NutritionService().analyzeFood(description: text);
      if (!mounted || _memberChanged(uid)) return;
      setState(() {
        _result = _parse(r);
        _resultUid = uid;
        _portion = 1.0;
        _stage = _ScanStage.result;
      });
    } catch (e, st) {
      reportError('nutrition.scan.describe', e, st);
      if (!mounted || _memberChanged(uid)) return;
      setState(() => _stage = _ScanStage.idle);
      _say(couldntMessage('analyze that description', e));
    }
  }

  void _say(String message) {
    if (mounted) setState(() => _notice = message);
  }

  /// One photo, picked and read. Null is the person cancelling (silent) or a
  /// failure that was recorded and said here.
  Future<(XFile, Uint8List)?> _pickAndRead(
      ImageSource source, String? uid) async {
    if (_picking) return null;
    setState(() { _picking = true; _notice = null; });
    try {
      final XFile? file;
      try {
        file = await _picker.pickImage(source: source, imageQuality: 80);
      } catch (e, st) {
        reportError('nutrition.scan.pick.${source.name}', e, st);
        if (_memberChanged(uid)) return null;
        final camera = source == ImageSource.camera;
        final what = camera ? 'camera' : 'photos';
        // image_picker's permission codes end `_access_denied`.
        _say(e is PlatformException && e.code.endsWith('_access_denied')
            ? "Couldn't open your $what — allow ${camera ? 'camera' : 'photo'} "
                'access in Settings, then try again.'
            : couldntMessage('open your $what', e));
        return null;
      }
      if (file == null) return null;
      try {
        final bytes = await file.readAsBytes();
        // Another member signed in meanwhile: not their photo to analyze.
        return _memberChanged(uid) ? null : (file, bytes);
      } catch (e, st) {
        reportError('nutrition.scan.read', e, st);
        if (_memberChanged(uid)) return null;
        _say(couldntMessage('use that photo', e));
        return null;
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    // The member this photo belongs to, fixed before the pick.
    final uid = _signedInUid();
    final picked = await _pickAndRead(source, uid);
    if (picked == null || !mounted) return;
    final (file, bytes) = picked;
    setState(() {
      _image = file;
      _stage = _ScanStage.scanning;
    });
    await _analyze(file, bytes, uid);
  }

  Future<void> _analyze(XFile file, Uint8List bytes, String? uid) async {
    // Again: awaits lie between the last check and here.
    if (_memberChanged(uid)) return;
    try {
      final ext = file.name.toLowerCase().split('.').last;
      final mime = ext == 'png' ? 'image/png'
          : ext == 'webp' ? 'image/webp'
          : ext == 'heic' ? 'image/heic' : 'image/jpeg';
      final r = await NutritionService().analyzeFood(
        imageBytes: bytes, mediaType: mime);
      if (!mounted || _memberChanged(uid)) return;
      setState(() {
        _result = _parse(r);
        _resultUid = uid;
        _portion = 1.0;
        _stage = _ScanStage.result;
      });
    } catch (e, st) {
      reportError('nutrition.scan.analyze', e, st);
      if (!mounted || _memberChanged(uid)) return;
      setState(() {
        _stage = _ScanStage.idle;
        _notice = '${couldntMessage('analyze that photo', e)} '
            'You can also add the meal manually.';
      });
    }
  }

  void _save(ScanResult meal) {
    // Another member signed in with it on screen: not their meal to log.
    // (`initialResult`, the tests' seam, was read for nobody.)
    if (widget.initialResult == null && _memberChanged(_resultUid)) return;
    widget.onAccept(meal);
  }

  void _retake() {
    setState(() {
      _image = null;
      _result = null;
      _resultUid = null;
      _stage = _ScanStage.idle;
    });
  }

  @override
  void initState() {
    super.initState();
    final seed = widget.initialResult;
    if (seed != null) {
      _result = _Estimate.of(seed);
      _portion = portionAsShown;
      _stage = _ScanStage.result;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _ScanStage.idle:    return _buildIdle();
      case _ScanStage.scanning: return _buildScanning();
      case _ScanStage.result:  return _buildResult();
    }
  }

  /// Dimmed, and announced as disabled, while a picker is open or its file is
  /// being read: a tap then does nothing.
  Widget _pickButton({
    required String label,
    required ImageSource source,
    required Widget child,
  }) =>
      Semantics(
        container: true,
        button: true,
        enabled: !_picking,
        label: label,
        child: GestureDetector(
          onTap: _picking ? null : () => _pickImage(source),
          child: Opacity(
            opacity: _picking ? 0.45 : 1,
            child: ExcludeSemantics(child: child))),
      );

  Widget _failureNotice(String message) => Semantics(
        liveRegion: true,
        container: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const ExcludeSemantics(child: Icon(
            Icons.error_outline, color: _redChip, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
            style: const TextStyle(
              color: _redChip, fontSize: 13, height: 1.4))),
        ]),
      );

  /// Equal widths in a row; one under the other when [stacked].
  Widget _sideBySide(List<Widget> children,
      {required bool stacked, required double gap}) {
    if (stacked) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          c,
        ],
      ]);
    }
    return Row(children: [
      for (final (i, c) in children.indexed) ...[
        if (i > 0) SizedBox(width: gap),
        Expanded(child: c),
      ],
    ]);
  }

  Widget _buildIdle() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          if (_notice != null) ...[
            _failureNotice(_notice!),
            const SizedBox(height: 16),
          ],
          // ── Camera placeholder ─────────────────────────────────────
          Container(
            width: double.infinity,
            // Grows with the text (it overflowed at large sizes).
            constraints: const BoxConstraints(minHeight: 230),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _brand.withValues(alpha: 0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: _brand.withValues(alpha: 0.08),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // subtle radial glow
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _brand.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _brand.withValues(alpha: 0.08),
                        border: Border.all(color: _brand.withValues(alpha: 0.2)),
                      ),
                      child: Icon(
                        Icons.camera_alt_outlined,
                        color: _muted.withValues(alpha: 0.6),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Take or upload a photo of your meal',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _muted.withValues(alpha: 0.6),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // ── Scan Meal button ───────────────────────────────────────
          _pickButton(
            label: 'Scan Meal',
            source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 54),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFB44CF0)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: _brand.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.camera_alt_rounded, color: _white, size: 20),
                  SizedBox(width: 10),
                  Flexible(child: Text(
                    'Scan Meal',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Choose from Gallery button ─────────────────────────────
          _pickButton(
            label: 'Choose from Gallery',
            source: ImageSource.gallery,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _brand.withValues(alpha: 0.4), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_outlined, color: _muted, size: 20),
                  const SizedBox(width: 10),
                  Flexible(child: Text(
                    'Choose from Gallery',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // ── Or describe your meal in words ─────────────────────────
          LayoutBuilder(builder: (_, box) => Row(children: [
            Expanded(child: Divider(color: _muted.withValues(alpha: 0.15))),
            Container(
              constraints: BoxConstraints(maxWidth: box.maxWidth - 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('or describe it', textAlign: TextAlign.center,
                style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 12))),
            Expanded(child: Divider(color: _muted.withValues(alpha: 0.15))),
          ])),
          const SizedBox(height: 14),
          // Named: the hint is its only name, and goes once something is typed.
          Semantics(label: 'Describe your meal', child: TextField(
            controller: _descCtrl,
            onChanged: (text) => _descUid =
                text.isEmpty ? null : _descUid ?? _signedInUid(),
            style: const TextStyle(color: _white, fontSize: 14),
            minLines: 1, maxLines: 2,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _describe(),
            decoration: InputDecoration(
              hintText: 'e.g. grilled chicken salad with avocado',
              hintStyle: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 13),
              filled: true, fillColor: _card,
              suffixIcon: IconButton(
                tooltip: 'Analyze description',
                icon: const Icon(Icons.auto_awesome, color: _brand, size: 20),
                onPressed: _describe),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: _brand.withValues(alpha: 0.25))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _brand)),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildScanning() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              width: double.infinity,
              height: 260,
              child: _image == null
                  ? Container(color: _card)
                  : (kIsWeb
                      ? Image.network(_image!.path, fit: BoxFit.cover)
                      : Image.file(File(_image!.path), fit: BoxFit.cover)),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFB44CF0)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: _white, strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Flexible(child: Text(
                  'Analyzing your meal...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    final meal = r.whole?.scaled(_portion); // after the portion multiplier
    final missing = r.missing;
    final cal = r.calories;
    // A macro after the portion multiplier; null stays null (not known).
    int? g(double? v) => v == null ? null : (v * _portion).toInt();
    // Large text: the side-by-side controls go one under the other.
    final stacked = MediaQuery.textScalerOf(context).scale(13) > 13 * 1.3;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Image preview ────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: double.infinity,
              height: 180,
              child: _image == null
                  ? Container(color: _card)
                  : (kIsWeb
                      ? Image.network(_image!.path, fit: BoxFit.cover)
                      : Image.file(File(_image!.path), fit: BoxFit.cover)),
            ),
          ),
          const SizedBox(height: 14),
          // ── Scan result card ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _brand.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: double.infinity, child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(
                        color: _white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _green.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        r.confidence == null
                            ? 'Match not known' : '${r.confidence}% match',
                        style: const TextStyle(
                          color: _green,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                )),
                const SizedBox(height: 4),
                Text(
                  cal == null
                      ? 'Calories not known' : '${(cal * _portion).toInt()} kcal',
                  style: const TextStyle(color: _white, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: Wrap(
                  alignment: WrapAlignment.spaceAround,
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    _MacroChip('Protein', g(r.protein), _brand),
                    _MacroChip('Carbs', g(r.carbs), _green),
                    _MacroChip('Fat', g(r.fat), _redChip),
                  ],
                )),
                const SizedBox(height: 12),
                // ── Portion adjuster ────────────────────────────────
                SizedBox(width: double.infinity, child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.tune_rounded, color: _muted.withValues(alpha: 0.7), size: 16),
                    const SizedBox(width: 6),
                    Flexible(child: Text('Portion', style: TextStyle(color: _muted.withValues(alpha: 0.7), fontSize: 12))),
                  ]),
                  Text('${_portion.toStringAsFixed(2)}×',
                    style: const TextStyle(color: _brand, fontSize: 13, fontWeight: FontWeight.w700)),
                ])),
                // FIT-020's three declared portion controls. The slider stays
                // below them: the anchor does not draw it, but removing a
                // finer control would take capability away, and a locked
                // screen not drawing something is not the design saying to
                // delete it (the OD-15 / OD-17 rule).
                _sideBySide(stacked: stacked, gap: 8, [
                  _PortionChoice(
                    label: 'Smaller',
                    selected: false,
                    onTap: () => setState(() => _portion = portionSmaller(_portion))),
                  _PortionChoice(
                    label: 'As shown',
                    selected: (_portion - portionAsShown).abs() < 0.001,
                    onTap: () => setState(() => _portion = portionAsShown)),
                  _PortionChoice(
                    label: 'Larger',
                    selected: false,
                    onTap: () => setState(() => _portion = portionLarger(_portion))),
                ]),
                const SizedBox(height: 4),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _brand, inactiveTrackColor: _brand.withValues(alpha: 0.2),
                    thumbColor: _brand, overlayColor: _brand.withValues(alpha: 0.15),
                    trackHeight: 3),
                  child: MergeSemantics(child: Semantics(
                    label: 'Portion',
                    child: Slider(
                      value: _portion, min: 0.25, max: 3.0, divisions: 11,
                      semanticFormatterCallback: (v) => '${v.toStringAsFixed(2)}×',
                      onChanged: (v) => setState(() => _portion = v)))),
                ),
                // ── Per-item breakdown ──────────────────────────────
                if (r.items.length > 1) ...[
                  Divider(color: _muted.withValues(alpha: 0.12)),
                  const SizedBox(height: 4),
                  Text('INCLUDES', style: TextStyle(color: _muted.withValues(alpha: 0.5),
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  ...r.items.map((it) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SizedBox(width: double.infinity, child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      children: [
                      Text(it.name,
                        style: TextStyle(color: _muted.withValues(alpha: 0.85), fontSize: 12)),
                      Text(it.calories == null
                          ? 'kcal not known' : '${(it.calories! * _portion).toInt()} kcal',
                        style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 12)),
                    ])),
                  )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // A value the analysis did not give is never saved as 0: say which,
          // and what to do instead (P0-FL-61).
          if (missing != null) ...[
            _failureNotice("Couldn't read the $missing for this meal — retake it"
                // The control below, by its own words, when it is there.
                "${widget.onSearchInstead == null ? '' : ', or tap Search instead to add it yourself'}. "
                'Saving is off for this scan.'),
            const SizedBox(height: 16),
          ],
          // ── Retake / Accept ──────────────────────────────────────
          _sideBySide(stacked: stacked, gap: 12, [
            _ResultButton(
              label: 'Retake',
              color: _muted,
              weight: FontWeight.w600,
              onTap: _retake,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _brand.withValues(alpha: 0.3), width: 1.5),
              ),
            ),
            _ResultButton(
              // FIT-020 names this after the meal being saved to.
              label: scanSaveLabel(widget.mealType),
              color: _white,
              weight: FontWeight.w700,
              onTap: meal == null ? null : () => _save(meal),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFB44CF0)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: _brand.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ]),
          // FIT-020 · "Search instead" — leave the scan and look the food up
          // by name. Null hides it rather than drawing a control that does
          // nothing.
          if (widget.onSearchInstead != null) ...[
            const SizedBox(height: 10),
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: widget.onSearchInstead,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  child: Text('Search instead',
                    style: TextStyle(
                      color: _muted.withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One of FIT-020's three portion words.
///
/// `As shown` is a state — the scan's own estimate — so it reports `selected`.
/// `Smaller` and `Larger` are steps, not states: they move the portion and
/// report nothing about where it ended up, because "smaller" is not a place.
class _PortionChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PortionChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        // `excludeSemantics` drops the child's actions with its labels — F-9.
        onTap: onTap,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? _brand.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? _brand
                    : Colors.white.withValues(alpha: 0.10)),
            ),
            child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? _white : _muted,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
          ),
        ),
      );
}

/// `Retake` / `Save to …`. Null [onTap] = dimmed and announced as disabled.
class _ResultButton extends StatelessWidget {
  final String label;
  final Color color;
  final FontWeight weight;
  final BoxDecoration decoration;
  final VoidCallback? onTap;
  const _ResultButton({
    required this.label,
    required this.color,
    required this.weight,
    required this.decoration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        enabled: onTap != null,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? 0.45 : 1,
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              alignment: Alignment.center,
              decoration: decoration,
              child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 14, fontWeight: weight)),
            ),
          ),
        ),
      );
}

class _MacroChip extends StatelessWidget {
  final String label;
  /// Null = not known.
  final int? value;
  final Color color;
  const _MacroChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value == null ? 'Not known' : '${value}g',
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(color: _muted.withValues(alpha: 0.5), fontSize: 10),
          ),
        ],
      );
}
