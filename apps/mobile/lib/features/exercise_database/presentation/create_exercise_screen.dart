import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/custom_exercise_provider.dart';
import '../../auth/domain/auth_provider.dart';
import '../../workout/data/models/video_variant_model.dart';
import '../../../core/widgets/named_icon_button.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
class _C {
  static const bg       = Color(0xFF030303);
  static const card     = Color(0xFF0E0B16);
  static const brd      = Color(0xFF1A1020);
  static const brand    = Color(0xFFA855F7);
  static const primary  = Color(0xFFDDB7FF);
  static const tertiary = Color(0xFF6FFBBE);
  static const amber    = Color(0xFFFFD580);
  static const error    = Color(0xFFFFB4AB);
  static const wht      = Colors.white;
  static const mut      = Color(0xFFCFC2D6);
}

const _categories  = ['Strength', 'Hypertrophy', 'Powerlifting', 'Olympic', 'Cardio', 'Conditioning', 'Functional', 'Mobility', 'Flexibility', 'Core', 'Lower Body', 'Upper Body', 'Full Body', 'Push', 'Pull', 'Rehab'];
const _muscles     = ['Chest', 'Upper Back', 'Lats', 'Traps', 'Shoulders', 'Front Delts', 'Side Delts', 'Rear Delts', 'Biceps', 'Triceps', 'Forearms', 'Quadriceps', 'Hamstrings', 'Glutes', 'Adductors', 'Abductors', 'Calves', 'Core', 'Obliques', 'Lower Back', 'Hip Flexors', 'Full Body'];
const _equipmentOptions = ['Barbell', 'Dumbbell', 'Kettlebell', 'Machine', 'Cable', 'Bodyweight', 'Resistance Band', 'Smith Machine', 'Trap Bar', 'EZ Bar', 'Squat Rack', 'Power Rack', 'Bench', 'Pull-up Bar', 'Dip Bars', 'Box', 'Medicine Ball', 'Battle Ropes', 'Sled', 'Landmine', 'TRX', 'None'];
const _difficulties = ['Beginner', 'Intermediate', 'Advanced', 'Elite'];
const _videoLabels  = ['Tutorial', 'Beginner', 'Intermediate', 'Advanced', 'Form Correction', 'Warm-up'];
const _visibilities = ['private', 'team', 'global'];
const _movementPatterns = ['Squat', 'Hinge', 'Lunge', 'Push', 'Pull', 'Carry', 'Rotation', 'Core', 'Gait', 'Isometric'];
const _exerciseTypes = ['Compound', 'Isolation', 'Plyometric', 'Isometric', 'Cardio'];
const _kNone = '— Not set —';

/// Label + subtitle + switch row.
Widget _toggleRow(String label, String subtitle, bool value, ValueChanged<bool> onChanged) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: _C.wht, fontSize: 13, fontWeight: FontWeight.w600)),
        Text(subtitle, style: const TextStyle(color: _C.mut, fontSize: 11)),
      ])),
      Switch(value: value, onChanged: onChanged, activeThumbColor: _C.primary),
    ]),
  );
}

/// Preset options + any selected values not in the presets (so imported values
/// always show). Order: presets first, then extras.
List<String> _mergeOpts(List<String> preset, List<String> selected) {
  final out = List<String>.from(preset);
  for (final s in selected) {
    if (s.trim().isNotEmpty && !out.contains(s)) out.add(s);
  }
  return out;
}

/// Multi-select chip picker bound to [selected] (mutated in place). Includes any
/// already-selected values not in [options] (chip rendered as active).
Widget _chipMulti(String label, List<String> options, List<String> selected,
    VoidCallback onChanged) {
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: _C.mut, fontSize: 12, fontWeight: FontWeight.w600)),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 6, children: options.map((o) {
      final active = selected.contains(o);
      return GestureDetector(
        onTap: () {
          if (active) {
            selected.remove(o);
          } else {
            selected.add(o);
          }
          onChanged();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? _C.brand.withValues(alpha: 0.15) : _C.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? _C.brand.withValues(alpha: 0.5) : _C.brd)),
          child: Text(o, style: TextStyle(color: active ? _C.primary : _C.mut, fontSize: 12))),
      );
    }).toList()),
  ]);
}

class CreateExerciseScreen extends ConsumerStatefulWidget {
  const CreateExerciseScreen({super.key});
  @override
  ConsumerState<CreateExerciseScreen> createState() => _CreateExerciseScreenState();
}

class _CreateExerciseScreenState extends ConsumerState<CreateExerciseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _savedId;
  // Edit mode: id of the exercise being edited (null = creating new).
  String? _editingId;
  String? _editingCoachId;
  String? _existingImageUrl;

  // Basic info
  final _nameCtrl    = TextEditingController();
  final _descCtrl    = TextEditingController();
  String _category   = 'Strength';
  String _muscle     = 'Chest';
  String _equipment  = 'Barbell';
  String _difficulty = 'Intermediate';
  String _visibility = 'private';
  final List<String> _secondaryMuscles = [];
  // Richer metadata (e.g. from JSON import).
  final List<String> _primaryMuscles = [];
  final List<String> _equipmentList = [];
  String? _movementPattern;
  String? _exerciseType;
  bool _beginnerFriendly = false;
  bool _videoRequired = false;
  bool _supportsPr = true;
  bool _supportsRpe = true;
  // Rich master-schema fields captured on JSON import (no visible editor) —
  // merged into the save so nothing is dropped.
  Map<String, dynamic> _importedExtra = {};
  // The full imported master JSON, used to populate the normalized child tables.
  Map<String, dynamic>? _importedRaw;

  // Instructions / cues / mistakes / alternatives
  final List<TextEditingController> _instructionCtrls  = [TextEditingController()];
  final List<TextEditingController> _cueCtrls          = [TextEditingController()];
  final List<TextEditingController> _mistakeCtrls      = [TextEditingController()];
  final List<TextEditingController> _alternativeCtrls  = [TextEditingController()];
  final _beginnerCtrl   = TextEditingController();
  final _advancedCtrl   = TextEditingController();
  final _tagsCtrl       = TextEditingController();

  // Media (bytes-based so it works on web + native)
  Uint8List? _imageBytes;
  String _imageExt = 'jpg';
  final List<_VideoEntry> _videoEntries = [];
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    final editId = ref.read(editingExerciseProvider);
    if (editId != null) {
      _editingId = editId;
      // Clearing the provider must happen outside the build lifecycle.
      Future.microtask(() {
        if (mounted) ref.read(editingExerciseProvider.notifier).state = null;
      });
      _loadForEdit(editId);
    }
  }

  /// Load an existing exercise into the form for editing.
  Future<void> _loadForEdit(String id) async {
    final row = await ref.read(customExerciseSvcProvider).getRawById(id);
    if (row == null || !mounted) return;
    // Reuse the import normalizer (map the row's `name` to `exercise_name`).
    _applyNormalized(_normalizeImport({...row, 'exercise_name': row['name']}));
    setState(() {
      _editingCoachId = row['coach_id'] as String?;
      _visibility = (row['visibility'] as String?) ?? _visibility;
      _existingImageUrl = row['image_url'] as String?;
      _beginnerCtrl.text = (row['beginner_modification'] as String?) ?? '';
      _advancedCtrl.text = (row['advanced_progression'] as String?) ?? '';
      // Prefill existing video variants as editable URL entries.
      final vv = row['video_variants'];
      if (vv is List && vv.isNotEmpty) {
        _videoEntries.clear();
        for (final v in vv) {
          if (v is Map && (v['url'] as String?)?.isNotEmpty == true) {
            final entry = _VideoEntry()
              ..label = (v['label'] as String?) ?? 'Tutorial';
            entry.urlCtrl.text = v['url'] as String;
            _videoEntries.add(entry);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose(); _descCtrl.dispose();
    _beginnerCtrl.dispose(); _advancedCtrl.dispose(); _tagsCtrl.dispose();
    for (final c in [..._instructionCtrls, ..._cueCtrls, ..._mistakeCtrls, ..._alternativeCtrls]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Make a tab read-only (locked) for coach media-only edits.
  Widget _lockable(Widget child, bool locked) => locked
      ? AbsorbPointer(child: Opacity(opacity: 0.5, child: child))
      : child;

  /// True when a coach is editing an exercise they don't own (media-only).
  bool _isCoachMediaOnly() {
    if (_editingId == null) return false;
    final role = ref.read(currentUserProfileProvider).valueOrNull?['role'];
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    return role != 'admin' &&
        !(_editingCoachId != null && _editingCoachId == myUid);
  }

  List<String> _listFrom(List<TextEditingController> ctrls) =>
      ctrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();

  List<String> _strList(dynamic v) =>
      (v is List) ? v.map((e) => e.toString()).toList() : <String>[];

  // 'lower_body' -> 'Lower Body' (for matching title-case dropdown options).
  String _humanize(dynamic v) => v
      .toString()
      .split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  /// Replace a dynamic controller-list's contents with [values] (reusing
  /// controllers; deferring disposal of removed ones to avoid use-after-dispose).
  void _setCtrls(List<TextEditingController> ctrls, List<String> values) {
    final vals = values.isEmpty ? [''] : values;
    final removed = <TextEditingController>[];
    while (ctrls.length > vals.length) {
      removed.add(ctrls.removeLast());
    }
    while (ctrls.length < vals.length) {
      ctrls.add(TextEditingController());
    }
    for (var i = 0; i < vals.length; i++) {
      ctrls[i].text = vals[i];
    }
    if (removed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in removed) { c.dispose(); }
      });
    }
  }

  List<String> _flattenMistakes(dynamic cm) {
    if (cm is! List) return [];
    return cm.map((e) {
      if (e is Map) {
        final mistake = e['mistake']?.toString() ?? '';
        final correction = e['correction']?.toString();
        return (correction != null && correction.isNotEmpty)
            ? '$mistake → $correction' : mistake;
      }
      return e.toString();
    }).where((s) => s.isNotEmpty).toList();
  }

  /// Array of {step, instruction} | {text} | strings -> instruction strings.
  List<String> _instrList(dynamic v) {
    if (v is! List) return [];
    return v.map((e) => e is Map
        ? (e['instruction'] ?? e['text'] ?? e['step'] ?? '').toString()
        : e.toString()).where((s) => s.isNotEmpty).toList();
  }

  /// Array of {exercise|name: …} | strings -> names.
  List<String> _nameList(dynamic v) {
    if (v is! List) return [];
    return v.map((e) => e is Map
        ? (e['exercise'] ?? e['name'] ?? '').toString()
        : e.toString()).where((s) => s.isNotEmpty).toList();
  }

  /// Accepts any of the import shapes (flat master, exercise_overview wrapper,
  /// object-form instructions/cues/mistakes/alternatives, leveled cues, the
  /// breathing + ai_exercise_tips coaching sections) and returns one canonical
  /// map the form prefill, _buildMasterExtra, and the relations sync all read.
  Map<String, dynamic> _normalizeImport(Map<String, dynamic> raw) {
    // Flatten the exercise_overview wrapper, if present.
    final m = <String, dynamic>{...raw};
    if (raw['exercise_overview'] is Map) {
      m.addAll(Map<String, dynamic>.from(raw['exercise_overview']));
    }
    final n = <String, dynamic>{};

    // Scalars passed straight through.
    for (final k in ['exercise_name', 'slug', 'description', 'difficulty',
        'movement_pattern', 'exercise_type', 'status', 'visibility',
        'default_rest_seconds', 'beginner_friendly', 'video_required',
        'supports_pr_tracking', 'supports_rpe_tracking', 'supports_volume_tracking',
        'estimated_calories_per_set', 'space_requirements',
        'estimated_setup_time_seconds', 'estimated_execution_time_seconds']) {
      if (m[k] != null) n[k] = m[k];
    }
    // body_region may be a string or array; category falls back to it.
    final region = m['body_region'];
    n['body_region'] = region is List ? region : (region != null ? [region] : []);
    n['category'] = m['category'] ?? (region is List ? (region.isNotEmpty ? region.first : null) : region);

    n['primary_muscles'] = _strList(m['primary_muscles']);
    n['secondary_muscles'] = _strList(m['secondary_muscles']);
    n['equipment_required'] = _strList(m['equipment_required']).isNotEmpty
        ? _strList(m['equipment_required']) : _strList(m['equipment']);
    n['equipment_optional'] = _strList(m['equipment_optional']);

    // Instructions: objects {step, instruction} or strings.
    n['step_by_step_instructions'] =
        _instrList(m['step_by_step_instructions'] ?? m['instructions']);

    // Coaching cues: leveled object or flat array.
    final cues = m['coaching_cues'];
    if (cues is Map) {
      n['coaching_cues_by_level'] = cues;
      n['coaching_cues'] = cues.values.whereType<List>()
          .expand((l) => l).map((e) => e.toString()).toList();
    } else {
      n['coaching_cues'] = _strList(cues);
    }

    // Common mistakes: {mistake, problem, fix} | {mistake, correction} | strings.
    final cm = m['common_mistakes'];
    if (cm is List) {
      n['common_mistakes'] = cm.map((e) => e is Map ? {
        'mistake': e['mistake'],
        'correction': e['fix'] ?? e['correction'],
        if (e['problem'] != null) 'problem': e['problem'],
      } : {'mistake': e.toString()}).toList();
    }

    // Alternatives / substitutions.
    if (m['alternative_exercises'] is List) {
      final names = _nameList(m['alternative_exercises']);
      n['substitutions'] = {'same_movement': names};
      n['alternatives'] = names;
    } else if (m['substitutions'] != null) {
      n['substitutions'] = m['substitutions'];
      n['alternatives'] = _strList(m['alternatives']);
    }
    n['beginner_modifications'] = _nameList(m['beginner_modifications']);
    n['progressions'] = _nameList(m['advanced_progressions'] ?? m['progressions']);
    n['regressions'] = _nameList(m['regressions']);

    // Rich structured coaching content (no form editor — preserved as-is).
    for (final k in ['breathing', 'ai_exercise_tips', 'goal_tags', 'sports_tags',
        'sports_relevance', 'subcategories', 'experience_levels', 'joint_actions',
        'movement_tags', 'search_keywords', 'contraindications',
        'warmup_recommendations', 'cooldown_recommendations', 'mobility_requirements',
        'tempo_options', 'supports_tracking', 'recommended_rep_ranges',
        'recommended_rpe', 'recommended_frequency', 'ai_metadata', 'video_assets',
        'image_assets', 'form_correction_videos', 'voiceover_assets', 'youtube_links',
        'vimeo_links', 'related_exercises', 'injury_modifications', 'equipment_category',
        'exercise_scoring', 'achievement_triggers']) {
      if (m[k] != null) n[k] = m[k];
    }
    return n;
  }

  /// Rich master-schema fields (excludes the core form-editable ones, which come
  /// from the named insert fields so manual edits win).
  Map<String, dynamic> _buildMasterExtra(Map<String, dynamic> m) {
    final ai = m['ai_metadata'] is Map ? Map<String, dynamic>.from(m['ai_metadata']) : null;
    final extra = <String, dynamic>{};
    void put(String k, dynamic v) { if (v != null) extra[k] = v; }
    final eqReq = _strList(m['equipment_required']).isNotEmpty
        ? _strList(m['equipment_required']) : _strList(m['equipment']);

    put('slug', m['slug']);
    put('status', m['status']);
    put('exercise_type', m['exercise_type']);
    put('movement_pattern', m['movement_pattern']);
    extra['subcategories']      = _strList(m['subcategories']);
    extra['primary_muscles']    = _strList(m['primary_muscles']);
    extra['secondary_muscles']  = _strList(m['secondary_muscles']);
    extra['equipment_required'] = eqReq;
    extra['equipment_optional'] = _strList(m['equipment_optional']);
    extra['equipment_list']     = eqReq;
    extra['body_region']        = _strList(m['body_region']);
    extra['goal_tags']          = _strList(m['goal_tags']);
    extra['experience_levels']  = _strList(m['experience_levels']);
    extra['sports_relevance']   = _strList(m['sports_relevance']);
    extra['contraindications']  = _strList(m['contraindications']);
    extra['beginner_modifications']   = _strList(m['beginner_modifications']);
    extra['advanced_progressions']    = _strList(m['advanced_progressions']);
    extra['warmup_recommendations']   = _strList(m['warmup_recommendations']);
    extra['cooldown_recommendations'] = _strList(m['cooldown_recommendations']);
    extra['tempo_options']      = _strList(m['tempo_options']);
    extra['badges']             = _strList(m['badges']);
    put('default_rest_seconds', m['default_rest_seconds']);
    put('estimated_calories_per_set', m['estimated_calories_per_set']);
    put('supports_volume_tracking', m['supports_volume_tracking']);
    if (m['supports_tracking'] is Map) extra['supports_tracking'] = m['supports_tracking'];
    if (m['substitutions'] != null) extra['substitutions'] = m['substitutions'];
    if (m['common_mistakes'] is List &&
        (m['common_mistakes'] as List).isNotEmpty &&
        (m['common_mistakes'] as List).first is Map) {
      extra['common_mistakes_detailed'] = m['common_mistakes'];
    }
    put('video_assets', m['video_assets']);
    put('image_assets', m['image_assets']);
    put('form_correction_videos', m['form_correction_videos']);
    put('mobility_videos', m['mobility_videos']);
    if (ai != null) {
      extra['ai_metadata'] = ai;
      put('fatigue_score', ai['fatigue_score']);
      put('complexity_score', ai['complexity_score']);
      put('recovery_demand', ai['recovery_demand']);
      if (ai['training_effect'] != null) extra['training_effect'] = _strList(ai['training_effect']);
    }
    put('recommended_frequency', m['recommended_frequency']);
    put('recommended_rep_ranges', m['recommended_rep_ranges']);
    put('recommended_rpe', m['recommended_rpe']);
    put('analytics', m['analytics']);
    // Structured coaching content (migration 060).
    put('breathing', m['breathing']);
    put('ai_exercise_tips', m['ai_exercise_tips']);
    put('coaching_cues_by_level', m['coaching_cues_by_level']);
    put('exercise_scoring', m['exercise_scoring']);
    if (m['achievement_triggers'] != null) extra['achievement_triggers'] = _strList(m['achievement_triggers']);
    if (m['space_requirements'] != null) extra['space_requirements'] = m['space_requirements'];
    return extra;
  }

  /// Paste an exercise JSON (e.g. AI-generated) to prefill the form.
  Future<void> _importJson() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1B1C),
        title: const Text('Paste exercise JSON',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl, maxLines: 12,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: const InputDecoration(
              hintText: '{ "exercise_name": "Barbell Squat", ... }',
              hintStyle: TextStyle(color: Color(0xFF968E99)),
              filled: true, fillColor: Color(0xFF0E0E0F)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFFCDC3D0)))),
          TextButton(onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Import', style: TextStyle(color: _C.primary, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      _applyNormalized(_normalizeImport(jsonDecode(ctrl.text) as Map<String, dynamic>));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Imported — review the fields, add a video, and save.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invalid JSON — check the format and try again.')));
      }
    }
  }

  /// Populate the form from a normalized exercise map (shared by Import + Edit).
  void _applyNormalized(Map<String, dynamic> m) {
    setState(() {
      _importedRaw = m;
      if (m['exercise_name'] != null) _nameCtrl.text = m['exercise_name'].toString();
      if (m['description'] != null) _descCtrl.text = m['description'].toString();
      if (m['category'] != null) _category = _humanize(m['category']);
      if (m['difficulty'] != null) _difficulty = _humanize(m['difficulty']);
      final eq = _strList(m['equipment_required']).isNotEmpty
          ? _strList(m['equipment_required']) : _strList(m['equipment']);
      _equipmentList..clear()..addAll(eq);
      if (eq.isNotEmpty) _equipment = eq.first;
      final pm = _strList(m['primary_muscles']);
      _primaryMuscles..clear()..addAll(pm);
      if (pm.isNotEmpty) _muscle = pm.first;
      _secondaryMuscles..clear()..addAll(_strList(m['secondary_muscles']));
      _setCtrls(_instructionCtrls, _strList(m['step_by_step_instructions']).isNotEmpty
          ? _strList(m['step_by_step_instructions']) : _strList(m['instructions']));
      _setCtrls(_cueCtrls, _strList(m['coaching_cues']));
      _setCtrls(_mistakeCtrls, _flattenMistakes(m['common_mistakes']));
      final subs = m['substitutions'];
      final altList = (subs is Map)
          ? subs.values.whereType<List>().expand((l) => l).map((e) => e.toString()).toList()
          : _strList(m['alternatives']);
      if (altList.isNotEmpty) _setCtrls(_alternativeCtrls, altList);
      _movementPattern = m['movement_pattern']?.toString();
      _exerciseType = m['exercise_type']?.toString();
      _beginnerFriendly = m['beginner_friendly'] == true ||
          _strList(m['experience_levels']).map((e) => e.toLowerCase()).contains('beginner');
      _videoRequired = m['video_required'] == true;
      _supportsPr = m['supports_pr_tracking'] != false;
      final st = m['supports_tracking'];
      _supportsRpe = (st is Map) ? st['rpe'] != false : (m['supports_rpe_tracking'] != false);
      _importedExtra = _buildMasterExtra(m);
    });
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageExt = _extOf(picked.name, 'jpg');
      });
    }
  }

  String _extOf(String name, String fallback) {
    final i = name.lastIndexOf('.');
    return (i >= 0 && i < name.length - 1) ? name.substring(i + 1).toLowerCase() : fallback;
  }

  Future<void> _pickVideo(int index) async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _videoEntries[index].bytes = bytes;
        _videoEntries[index].ext = _extOf(picked.name, 'mp4');
      });
    }
  }

  /// JSON used to populate the normalized child tables — the full imported
  /// master JSON if present, else assembled from the form state so manually
  /// created exercises also get normalized rows.
  Map<String, dynamic> _relationsJson() {
    if (_importedRaw != null) return _importedRaw!;
    final alts = _listFrom(_alternativeCtrls);
    return {
      'primary_muscles': _primaryMuscles,
      'secondary_muscles': _secondaryMuscles,
      'equipment_required': _equipmentList,
      if (_advancedCtrl.text.trim().isNotEmpty) 'progressions': [_advancedCtrl.text.trim()],
      if (_beginnerCtrl.text.trim().isNotEmpty) 'beginner_modifications': [_beginnerCtrl.text.trim()],
      if (alts.isNotEmpty) 'substitutions': {'same_movement': alts},
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      _tabs.animateTo(0);
      return;
    }
    setState(() => _saving = true);

    final svc = ref.read(customExerciseSvcProvider);
    // We need an ID to upload media, so create first with text data
    final variants = <VideoVariant>[];
    for (final entry in _videoEntries) {
      if (entry.urlCtrl.text.trim().isNotEmpty) {
        final url = entry.urlCtrl.text.trim();
        variants.add(VideoVariant(url: url, label: entry.label, type: VideoVariant.detectType(url)));
      }
    }

    final fields = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'category': _category,
      'muscle_group': _primaryMuscles.isNotEmpty ? _primaryMuscles.first : _muscle,
      'secondary_muscles': _secondaryMuscles,
      'equipment': _equipmentList.isNotEmpty ? _equipmentList.first : _equipment,
      'difficulty': _difficulty,
      'description': _descCtrl.text.trim(),
      'instructions': _listFrom(_instructionCtrls),
      'coaching_cues': _listFrom(_cueCtrls),
      'common_mistakes': _listFrom(_mistakeCtrls),
      'alternatives': _listFrom(_alternativeCtrls),
      'beginner_modification': _beginnerCtrl.text.trim().isEmpty ? null : _beginnerCtrl.text.trim(),
      'advanced_progression': _advancedCtrl.text.trim().isEmpty ? null : _advancedCtrl.text.trim(),
      'tags': _tagsCtrl.text.trim().isEmpty ? <String>[] : _tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      'video_variants': variants,
      'image_url': null,
      'visibility': _visibility,
      'extra': {
        'equipment_list': _equipmentList,
        'primary_muscles': _primaryMuscles,
        if (_movementPattern != null) 'movement_pattern': _movementPattern,
        if (_exerciseType != null) 'exercise_type': _exerciseType,
        'beginner_friendly': _beginnerFriendly,
        'video_required': _videoRequired,
        'supports_pr_tracking': _supportsPr,
        'supports_rpe_tracking': _supportsRpe,
        // Rich imported fields (slug, goal_tags, substitutions, ai_metadata,
        // recommended_*, video_assets, analytics, …) override/extend the above.
        ..._importedExtra,
      },
    };

    // Coaches can edit their OWN exercises fully; on platform/other exercises
    // they may only add media (the AI text content is admin-managed).
    final role = ref.read(currentUserProfileProvider).valueOrNull?['role'];
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    final mediaOnly = _editingId != null && role != 'admin' &&
        !(_editingCoachId != null && _editingCoachId == myUid);

    String? id;
    if (_editingId == null) {
      id = await ref.read(myExercisesNotifierProvider.notifier).create(fields: fields);
    } else if (mediaOnly) {
      id = _editingId; // skip text update — media handled below
    } else {
      final f = Map<String, dynamic>.from(fields);
      final extra = f.remove('extra') as Map<String, dynamic>;
      f..remove('image_url')..remove('video_variants');
      final upd = {...f, ...extra};
      if (_visibility == 'global') upd['submission_status'] = 'approved';
      final ok = await svc.updateExercise(_editingId!, upd);
      id = ok ? _editingId : null;
    }

    if (id != null) {
      // Upload picked image + video files.
      String? imageUrl;
      if (_imageBytes != null) imageUrl = await svc.uploadImage(_imageBytes!, _imageExt, id);
      final uploadedVariants = List<VideoVariant>.from(variants);
      for (int i = 0; i < _videoEntries.length; i++) {
        final entry = _videoEntries[i];
        if (entry.bytes != null) {
          final url = await svc.uploadVideo(entry.bytes!, entry.ext, id, entry.label);
          if (url != null) {
            uploadedVariants.add(VideoVariant(url: url, label: entry.label, type: 'upload'));
          }
        }
      }

      if (mediaOnly) {
        // Coach attaching media to an admin/platform exercise (privileged RPC).
        await svc.updateExerciseMedia(id,
          imageUrl: imageUrl,
          videoVariants: uploadedVariants.map((v) => v.toJson()).toList());
      } else {
        if (imageUrl != null) await svc.updateExercise(id, {'image_url': imageUrl});
        if (uploadedVariants.length != variants.length || _editingId != null) {
          await svc.updateExercise(id, {
            'video_variants': uploadedVariants.map((v) => v.toJson()).toList(),
          });
        }
        await svc.syncRelations(id, _relationsJson());
      }
      _savedId = id;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (!mounted) return;
    if (id != null) {
      _showSuccess();
    } else {
      final err = svc.lastError;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(err != null
            ? 'Save failed: ${_friendlyError(err)}'
            : 'Failed to save exercise. Try again.')));
    }
  }

  /// Pull a readable message out of a Postgrest/Storage exception.
  String _friendlyError(Object err) {
    final s = err.toString();
    final msg = RegExp(r'message: ([^,)]+)').firstMatch(s)?.group(1);
    return (msg ?? s).trim();
  }

  void _showSuccess() {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: _C.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Exercise Saved!', style: TextStyle(color: _C.wht, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded, color: _C.tertiary, size: 48),
          const SizedBox(height: 12),
          Text('Your exercise has been saved as $_visibility.',
            style: const TextStyle(color: _C.mut, fontSize: 13), textAlign: TextAlign.center),
        ]),
        actions: [
          TextButton(
            // Pop the dialog via its own context (root navigator), then leave the screen.
            onPressed: () { Navigator.of(dctx).pop(); if (mounted) context.pop(); },
            child: const Text('Back to Library', style: TextStyle(color: _C.primary))),
          if (_savedId != null)
            TextButton(
              onPressed: () {
                Navigator.of(dctx).pop();
                ref.read(myExercisesNotifierProvider.notifier).submitForGlobal(_savedId!).then((_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Published to the Global Library!')));
                  context.pop();
                });
              },
              child: const Text('Submit to Global Library', style: TextStyle(color: _C.amber))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final locked = _isCoachMediaOnly();
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(children: [
        // App bar
        Container(
          padding: EdgeInsets.only(top: topPad + 12, left: 16, right: 16, bottom: 0),
          color: _C.card,
          child: Column(children: [
            Row(children: [
              NamedIconButton(
                label: 'Back',
                onTap: () => context.pop(),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: _C.primary, size: 20)),
              const SizedBox(width: 14),
              Expanded(child: Text(_editingId != null ? 'Edit Exercise' : 'Create Exercise',
                style: const TextStyle(color: _C.wht, fontSize: 20, fontWeight: FontWeight.w700))),
              if (locked) const SizedBox() else GestureDetector(
                onTap: _importJson,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _C.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _C.primary.withValues(alpha: 0.4))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.data_object_rounded, color: _C.primary, size: 16),
                    SizedBox(width: 5),
                    Text('Import JSON', style: TextStyle(color: _C.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]))),
              GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _C.brand,
                    borderRadius: BorderRadius.circular(20)),
                  child: _saving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: _C.wht, strokeWidth: 2))
                      : const Text('Save', style: TextStyle(color: _C.wht, fontSize: 13, fontWeight: FontWeight.w700))),
              ),
            ]),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              labelColor: _C.primary,
              unselectedLabelColor: _C.mut,
              indicatorColor: _C.brand,
              indicatorWeight: 2,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              tabs: const [Tab(text: 'BASICS'), Tab(text: 'COACHING'), Tab(text: 'MEDIA'), Tab(text: 'SETTINGS')],
            ),
          ]),
        ),

        // Coaches editing an admin/platform exercise can only add media.
        if (_isCoachMediaOnly())
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _C.amber.withValues(alpha: 0.12),
            child: const Text(
              'This is a library exercise — you can add images & videos on the Media tab. '
              'Text content is managed by admins.',
              style: TextStyle(color: _C.amber, fontSize: 12)),
          ),

        // Content
        Expanded(
          child: Form(
            key: _formKey,
            child: TabBarView(controller: _tabs, children: [
              _lockable(_BasicsTab(this), locked),
              _lockable(_CoachingTab(this), locked),
              _MediaTab(this), // always editable — media is what coaches add
              _lockable(_SettingsTab(this), locked),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── Tab 1: Basics ─────────────────────────────────────────────────────────────
class _BasicsTab extends StatefulWidget {
  final _CreateExerciseScreenState s;
  const _BasicsTab(this.s);
  @override State<_BasicsTab> createState() => _BasicsTabState();
}
class _BasicsTabState extends State<_BasicsTab> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return ListView(padding: const EdgeInsets.all(20), children: [
      _field('Exercise Name *', s._nameCtrl, required: true),
      const SizedBox(height: 16),
      _field('Description', s._descCtrl, maxLines: 3),
      const SizedBox(height: 20),
      _row('Category', _mergeOpts(_categories, [s._category]), s._category, (v) => setState(() => s._category = v!)),
      const SizedBox(height: 14),
      _row('Difficulty', _mergeOpts(_difficulties, [s._difficulty]), s._difficulty, (v) => setState(() => s._difficulty = v!)),
      const SizedBox(height: 20),
      _chipMulti('Primary Muscles', _mergeOpts(_muscles, s._primaryMuscles), s._primaryMuscles, () => setState(() {})),
      const SizedBox(height: 16),
      _chipMulti('Secondary Muscles', _mergeOpts(_muscles, s._secondaryMuscles), s._secondaryMuscles, () => setState(() {})),
      const SizedBox(height: 16),
      _chipMulti('Equipment', _mergeOpts(_equipmentOptions, s._equipmentList), s._equipmentList, () => setState(() {})),
      const SizedBox(height: 22),
      const Text('ATTRIBUTES & TRACKING',
        style: TextStyle(color: _C.mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      const SizedBox(height: 12),
      _row('Movement Pattern',
        _mergeOpts([_kNone, ..._movementPatterns], [s._movementPattern ?? _kNone]),
        s._movementPattern ?? _kNone,
        (v) => setState(() => s._movementPattern = (v == null || v == _kNone) ? null : v)),
      const SizedBox(height: 14),
      _row('Exercise Type',
        _mergeOpts([_kNone, ..._exerciseTypes], [s._exerciseType ?? _kNone]),
        s._exerciseType ?? _kNone,
        (v) => setState(() => s._exerciseType = (v == null || v == _kNone) ? null : v)),
      const SizedBox(height: 14),
      _toggleRow('Beginner Friendly', 'Suitable for beginners', s._beginnerFriendly,
        (v) => setState(() => s._beginnerFriendly = v)),
      _toggleRow('Video Required', 'A form video is recommended', s._videoRequired,
        (v) => setState(() => s._videoRequired = v)),
      _toggleRow('Track PRs', 'Detect personal records (weight-based)', s._supportsPr,
        (v) => setState(() => s._supportsPr = v)),
      _toggleRow('Track RPE', 'Show the RPE field when logging sets', s._supportsRpe,
        (v) => setState(() => s._supportsRpe = v)),
    ]);
  }
}

// ── Tab 2: Coaching ───────────────────────────────────────────────────────────
class _CoachingTab extends StatefulWidget {
  final _CreateExerciseScreenState s;
  const _CoachingTab(this.s);
  @override State<_CoachingTab> createState() => _CoachingTabState();
}
class _CoachingTabState extends State<_CoachingTab> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return ListView(padding: const EdgeInsets.all(20), children: [
      _section('Step-by-Step Instructions', s._instructionCtrls, () => setState(() => s._instructionCtrls.add(TextEditingController()))),
      const SizedBox(height: 20),
      _section('Coaching Cues', s._cueCtrls, () => setState(() => s._cueCtrls.add(TextEditingController()))),
      const SizedBox(height: 20),
      _section('Common Mistakes', s._mistakeCtrls, () => setState(() => s._mistakeCtrls.add(TextEditingController()))),
      const SizedBox(height: 20),
      _section('Alternatives / Substitutes', s._alternativeCtrls, () => setState(() => s._alternativeCtrls.add(TextEditingController()))),
      const SizedBox(height: 20),
      const Text('MODIFICATIONS', style: TextStyle(color: _C.mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      const SizedBox(height: 10),
      _field('Beginner Modification', s._beginnerCtrl, maxLines: 2),
      const SizedBox(height: 12),
      _field('Advanced Progression', s._advancedCtrl, maxLines: 2),
    ]);
  }

  Widget _section(String title, List<TextEditingController> ctrls, VoidCallback onAdd) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(title.toUpperCase(), style: const TextStyle(color: _C.mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        const Spacer(),
        GestureDetector(onTap: onAdd, child: const Icon(Icons.add_circle_outline, color: _C.brand, size: 20)),
      ]),
      const SizedBox(height: 8),
      ...ctrls.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: _C.brand.withValues(alpha: 0.1), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('${e.key + 1}', style: const TextStyle(color: _C.brand, fontSize: 11, fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Expanded(child: _field(null, e.value)),
          if (ctrls.length > 1)
            GestureDetector(
              onTap: () => setState(() { e.value.dispose(); ctrls.removeAt(e.key); }),
              child: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.remove_circle_outline, color: _C.error, size: 18))),
        ]))),
    ]);
  }
}

// ── Tab 3: Media ──────────────────────────────────────────────────────────────
class _MediaTab extends StatefulWidget {
  final _CreateExerciseScreenState s;
  const _MediaTab(this.s);
  @override State<_MediaTab> createState() => _MediaTabState();
}
class _MediaTabState extends State<_MediaTab> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return ListView(padding: const EdgeInsets.all(20), children: [
      // Encourage adding real media.
      Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            _C.brand.withValues(alpha: 0.18), _C.brand.withValues(alpha: 0.06)]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.brand.withValues(alpha: 0.35))),
        child: Row(children: [
          const Icon(Icons.auto_awesome_motion_rounded, color: _C.primary, size: 22),
          const SizedBox(width: 12),
          const Expanded(child: Text(
            'Add a cover photo and a form video — exercises with media get used far '
            'more and help your clients train with correct technique.',
            style: TextStyle(color: _C.wht, fontSize: 12, height: 1.4))),
        ]),
      ),
      // Image
      const Text('EXERCISE IMAGE', style: TextStyle(color: _C.mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () async { await s._pickImage(); if (mounted) setState(() {}); },
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: _C.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.brd),
            image: s._imageBytes != null
                ? DecorationImage(image: MemoryImage(s._imageBytes!), fit: BoxFit.cover)
                : (s._existingImageUrl != null
                    ? DecorationImage(image: NetworkImage(s._existingImageUrl!), fit: BoxFit.cover)
                    : null)),
          child: (s._imageBytes == null && s._existingImageUrl == null)
              ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_photo_alternate_outlined, color: _C.brand, size: 36),
                  SizedBox(height: 8),
                  Text('Tap to add image', style: TextStyle(color: _C.mut, fontSize: 12)),
                ])
              : null)),
      const SizedBox(height: 24),

      // Video variants
      Row(children: [
        const Text('VIDEO VARIANTS', style: TextStyle(color: _C.mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => s._videoEntries.add(_VideoEntry())),
          child: const Icon(Icons.add_circle_outline, color: _C.brand, size: 20)),
      ]),
      const SizedBox(height: 4),
      const Text('Add YouTube links, Vimeo links, or upload videos from your device.',
        style: TextStyle(color: _C.mut, fontSize: 11)),
      const SizedBox(height: 12),
      if (s._videoEntries.isEmpty)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.brd)),
          child: const Column(children: [
            Icon(Icons.videocam_outlined, color: _C.mut, size: 28),
            SizedBox(height: 8),
            Text('No videos yet. Tap + to add.', style: TextStyle(color: _C.mut, fontSize: 12)),
          ]))
      else
        ...s._videoEntries.asMap().entries.map((e) {
          final i = e.key;
          final entry = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.brd)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _C.brand.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: entry.label,
                      dropdownColor: _C.card,
                      style: const TextStyle(color: _C.primary, fontSize: 11, fontWeight: FontWeight.w700),
                      items: _videoLabels.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                      onChanged: (v) => setState(() => entry.label = v!),
                    ))),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => s._videoEntries.removeAt(i)),
                  child: const Icon(Icons.remove_circle_outline, color: _C.error, size: 18)),
              ]),
              const SizedBox(height: 10),
              // URL input
              _field('YouTube or Vimeo URL', entry.urlCtrl),
              const SizedBox(height: 8),
              const Row(children: [
                Expanded(child: Divider(color: Color(0xFF1A1020))),
                Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('OR', style: TextStyle(color: _C.mut, fontSize: 10))),
                Expanded(child: Divider(color: Color(0xFF1A1020))),
              ]),
              const SizedBox(height: 8),
              // File upload
              GestureDetector(
                onTap: () async { await s._pickVideo(i); if (mounted) setState(() {}); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: entry.bytes != null ? _C.tertiary.withValues(alpha: 0.08) : _C.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: entry.bytes != null ? _C.tertiary.withValues(alpha: 0.4) : _C.brd)),
                  child: Row(children: [
                    Icon(entry.bytes != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                      color: entry.bytes != null ? _C.tertiary : _C.mut, size: 18),
                    const SizedBox(width: 8),
                    Text(entry.bytes != null ? 'Video selected' : 'Upload from device',
                      style: TextStyle(color: entry.bytes != null ? _C.tertiary : _C.mut, fontSize: 12)),
                  ]))),
            ]));
        }),
    ]);
  }
}

// ── Tab 4: Settings ───────────────────────────────────────────────────────────
class _SettingsTab extends StatefulWidget {
  final _CreateExerciseScreenState s;
  const _SettingsTab(this.s);
  @override State<_SettingsTab> createState() => _SettingsTabState();
}
class _SettingsTabState extends State<_SettingsTab> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('VISIBILITY', style: TextStyle(color: _C.mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      const SizedBox(height: 12),
      ..._visibilities.map((v) {
        final active = s._visibility == v;
        final (icon, label, desc) = switch(v) {
          'private' => (Icons.lock_outline_rounded,  'Private',      'Only you can see this exercise.'),
          'team'    => (Icons.group_outlined,         'Team',         'Shared with your active clients.'),
          _         => (Icons.language_rounded,       'Submit Global','Submitted for platform-wide approval.'),
        };
        return GestureDetector(
          onTap: () => setState(() => s._visibility = v),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: active ? _C.brand.withValues(alpha: 0.08) : _C.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: active ? _C.brand.withValues(alpha: 0.5) : _C.brd)),
            child: Row(children: [
              Icon(icon, color: active ? _C.primary : _C.mut, size: 22),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(color: active ? _C.wht : _C.mut, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(color: _C.mut.withValues(alpha: 0.6), fontSize: 11)),
              ])),
              if (active) const Icon(Icons.check_circle_rounded, color: _C.brand, size: 20),
            ])));
      }),
      const SizedBox(height: 24),
      const Text('TAGS', style: TextStyle(color: _C.mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      const SizedBox(height: 8),
      _field('e.g. compound, push, mobility', s._tagsCtrl),
      const SizedBox(height: 4),
      const Text('Separate tags with commas', style: TextStyle(color: _C.mut, fontSize: 10)),
      const SizedBox(height: 32),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _C.amber.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.amber.withValues(alpha: 0.25))),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, color: _C.amber, size: 18),
          SizedBox(width: 10),
          Expanded(child: Text(
            'Submitting to the Global Library allows all coaches on the platform to use your exercise after admin review. You retain credit.',
            style: TextStyle(color: _C.amber, fontSize: 12, height: 1.4))),
        ])),
    ]);
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────
class _VideoEntry {
  String label = 'Tutorial';
  final urlCtrl = TextEditingController();
  Uint8List? bytes;
  String ext = 'mp4';
}

Widget _field(String? hint, TextEditingController ctrl, {int maxLines = 1, bool required = false}) {
  return TextFormField(
    controller: ctrl,
    maxLines: maxLines,
    style: const TextStyle(color: _C.wht, fontSize: 14),
    validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _C.mut, fontSize: 13),
      filled: true,
      fillColor: _C.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.brd)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.brd)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.brand)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.error)),
    ));
}

Widget _row(String label, List<String> options, String value, ValueChanged<String?> onChanged) {
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label.toUpperCase(), style: const TextStyle(color: _C.mut, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
    const SizedBox(height: 6),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.brd)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: _C.card,
          style: const TextStyle(color: _C.wht, fontSize: 14),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: onChanged,
        ))),
  ]);
}
