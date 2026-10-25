// Dynamic Program Builder — the Program Intelligence Engine's coach surface.
// The coach sets a strategy; the deterministic planner lays out mesocycles and
// per-week targets (the visual roadmap). Creating the program persists the plan
// (versioned); each week's workouts are materialized just-in-time by reusing
// build_workout. The engine plans; the LLM only explains. Coaches/admins only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/coach_program_service.dart';
import '../domain/coach_ecosystem_provider.dart';
import '../domain/engine_generation.dart';
import '../../auth/domain/auth_provider.dart';
import '../../../core/observability/app_failure.dart';

const _bg     = Color(0xFF0A0A0B);
const _panel  = Color(0xFF14101E);
const _panel2 = Color(0xFF1B1526);
const _brand  = Color(0xFFB76DFF);
const _text   = Color(0xFFEDE7F3);
const _muted  = Color(0xFF9A93A6);
const _pass   = Color(0xFF10B981);
const _warn   = Color(0xFFF59E0B);
const _fail   = Color(0xFFEF4444);

class DynamicProgramBuilderScreen extends ConsumerStatefulWidget {
  const DynamicProgramBuilderScreen({
    super.key,
    this.engineWeekGeneration = kEngineWeekGeneration,
  });

  /// Shows the "Generate week 1" step. Defaults to the build-time flag, which is
  /// OFF until the target database has migration 186 (engine_generation.dart).
  final bool engineWeekGeneration;

  @override
  ConsumerState<DynamicProgramBuilderScreen> createState() => _State();
}

class _State extends ConsumerState<DynamicProgramBuilderScreen> {
  // Through the provider (not `CoachProgramService()`) so the screen can be
  // exercised in a widget test with a fake service.
  CoachProgramService get _svc => ref.read(coachProgramServiceProvider);
  String _type = 'Hypertrophy';
  int _duration = 12;
  int _frequency = 4;
  String _progression = 'linear';
  String _focus = 'Full Body';
  bool _busy = false, _saving = false;
  Map<String, dynamic>? _plan;
  String? _status;

  // "Generate week 1" — only after the programme is saved.
  String? _programId;
  // The programme type the saved programme was CREATED with. The chips stay
  // editable after saving, so generation must not read the live selection.
  String? _programType;
  bool _generating = false;
  String? _genStatus;
  bool _genOk = false;

  static const _types = ['Strength', 'Hypertrophy', 'Fat Loss', 'General Fitness', 'Athletic'];
  static const _durations = [4, 8, 12, 16, 24];
  static const _progressions = ['linear', 'undulating', 'block', 'hybrid'];
  static const _focuses = ['Full Body', 'Upper Body', 'Glutes', 'Mobility', 'Conditioning'];

  Map<String, dynamic> get _strategy => {
    'program_type': _type, 'duration_weeks': _duration, 'frequency': _frequency,
    'primary_focus': _focus, 'progression_model': _progression, 'deload_strategy': 'every_4th',
  };

  Future<void> _planIt() async {
    setState(() { _busy = true; _status = null; });
    final p = await _svc.planProgram(_strategy);
    if (!mounted) return;
    setState(() { _busy = false; _plan = p; });
  }

  Future<void> _create() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() { _saving = true; _status = null; });
    final id = await _svc.createEngineProgram(_strategy, plan);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _programId = id;
      _programType = id == null ? null : _type;
      _genStatus = null;
      _status = id == null
          ? 'Save failed — apply migration 093.'
          // This used to tell the coach to "materialize week 1 from Coach Copilot /
          // the client program view". No screen does that: the program is saved
          // with its plan and NO training days, and it cannot be assigned until it
          // has some (program_readiness.dart).
          : widget.engineWeekGeneration
              ? 'Program saved (v1) with its ${_duration}-week plan. Generate week 1 below to fill '
                'its training days, or add workouts by hand in Programs.'
              : 'Program saved (v1) with its ${_duration}-week plan. It has no training days yet — '
                'add workouts to it in Programs before assigning it to a client.';
    });
  }

  /// Asks the engine to fill week 1. Never replaces existing days without the
  /// coach confirming it in words (the engine itself refuses unless told to).
  Future<void> _generateWeek({bool replace = false}) async {
    final id = _programId;
    if (id == null || _generating) return;
    setState(() { _generating = true; _genStatus = null; });
    try {
      final res = await _svc.materializeWeek(
          id, 1, engineContextFor(programType: _programType ?? _type, replaceExisting: replace));
      if (!mounted) return;
      final summary = summarizeMaterialization(res);
      setState(() {
        _generating = false;
        _genOk = summary != null;
        _genStatus = summary == null
            ? coachMessageFor(EngineFailure.outdatedEngine)
            : 'Week 1 is ready — ${summary.days} training days, ${summary.exercises} exercises. '
              'Review or edit them in Programs before assigning the program.';
      });
    } catch (e, s) {
      final failure = classifyEngineError(e);
      if (failure == EngineFailure.unknown || failure == EngineFailure.noPlan) {
        reportError('DynamicProgramBuilder._generateWeek', e, s);
      }
      if (!mounted) return;
      setState(() { _generating = false; _genOk = false; _genStatus = coachMessageFor(failure); });
      if (failure == EngineFailure.weekExists && !replace) {
        final ok = await _confirmReplace();
        if (ok == true && mounted) await _generateWeek(replace: true);
      }
    }
  }

  Future<bool?> _confirmReplace() => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _panel,
      title: const Text('Replace week 1?', style: TextStyle(color: _text)),
      content: const Text(
        'Week 1 already has training days. Replacing it deletes all of them — including '
        'any changes you made by hand — and generates new ones. This cannot be undone.',
        style: TextStyle(color: _muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep week 1')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace', style: TextStyle(color: _fail))),
      ],
    ),
  );

  Widget _generateWeekCard() => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('WEEK 1', style: TextStyle(color: _muted, fontSize: 11,
          fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: ElevatedButton(
        key: const ValueKey('generate-week-1'),
        onPressed: _generating ? null : () => _generateWeek(),
        style: ElevatedButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: _generating
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Generate week 1', style: TextStyle(fontWeight: FontWeight.w800)),
      )),
      if (_genStatus != null) Padding(padding: const EdgeInsets.only(top: 10),
        child: Text(_genStatus!, style: TextStyle(color: _genOk ? _pass : _warn,
            fontSize: 13, fontWeight: FontWeight.w700))),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserProfileProvider).valueOrNull?['role'];
    if (role != 'coach' && role != 'admin') {
      return const Scaffold(backgroundColor: _bg,
        body: Center(child: Text('Coaches only.', style: TextStyle(color: _muted))));
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, foregroundColor: _text,
        title: const Text('Program Builder', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        _strategyCard(),
        const SizedBox(height: 12),
        _generateBtn(),
        if (_plan != null) ..._planView(_plan!),
        if (_status != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(_status!, style: TextStyle(
              color: _status!.contains('failed') ? _warn : _pass, fontSize: 13, fontWeight: FontWeight.w700))),
        if (widget.engineWeekGeneration && _programId != null) _generateWeekCard(),
      ]),
    );
  }

  Widget _strategyCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('STRATEGY', style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 10),
      _label('Program type'),
      _chips(_types, _type, (v) => setState(() => _type = v)),
      const SizedBox(height: 10),
      _label('Duration'),
      _chips(_durations.map((d) => '$d wk').toList(), '$_duration wk',
          (v) => setState(() => _duration = int.parse(v.split(' ').first))),
      const SizedBox(height: 10),
      Row(children: [
        _label('Sessions / week'),
        Expanded(child: Slider(value: _frequency.toDouble(), min: 2, max: 6, divisions: 4,
          activeColor: _brand, label: '$_frequency', onChanged: (v) => setState(() => _frequency = v.round()))),
        Text('$_frequency', style: const TextStyle(color: _brand, fontSize: 15, fontWeight: FontWeight.w900)),
      ]),
      _label('Progression model'),
      _chips(_progressions, _progression, (v) => setState(() => _progression = v)),
      const SizedBox(height: 10),
      _label('Primary focus'),
      _chips(_focuses, _focus, (v) => setState(() => _focus = v)),
    ]),
  );

  Widget _label(String s) => Padding(padding: const EdgeInsets.only(bottom: 6),
    child: Text(s, style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600)));

  Widget _chips(List<String> opts, String sel, ValueChanged<String> onTap) => Wrap(
    spacing: 6, runSpacing: 6,
    children: [for (final o in opts) GestureDetector(
      onTap: () => onTap(o),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: sel == o ? _brand : _panel2, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel == o ? _brand : _brand.withValues(alpha: 0.2))),
        child: Text(o, style: TextStyle(
            color: sel == o ? Colors.white : _text, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    )],
  );

  Widget _generateBtn() => GestureDetector(
    onTap: _busy ? null : _planIt,
    child: Container(
      width: double.infinity, alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(12)),
      child: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text('Plan program', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
    ),
  );

  List<Widget> _planView(Map<String, dynamic> plan) {
    final mesos = (plan['mesocycles'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final weeks = (plan['weeks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return [
      const SizedBox(height: 18),
      const Text('MESOCYCLES', style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      ...mesos.map((m) {
        final wk = (m['weeks'] as List?)?.cast<num>() ?? [0, 0];
        return Container(
          margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12),
              border: const Border(left: BorderSide(color: _brand, width: 3))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['name']?.toString() ?? '', style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w800)),
              Text('vol ${m['volume_target']} · intensity ${m['intensity_target']}',
                  style: const TextStyle(color: _muted, fontSize: 11.5)),
            ])),
            Text('wk ${wk.first}–${wk.last}', style: const TextStyle(color: _brand, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        );
      }),
      const SizedBox(height: 14),
      const Text('WEEK TIMELINE', style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      ...weeks.map(_weekRow),
      const SizedBox(height: 16),
      GestureDetector(
        onTap: _saving ? null : _create,
        child: Container(
          width: double.infinity, alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: _pass, borderRadius: BorderRadius.circular(12)),
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Create program (v1)', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      ),
    ];
  }

  Widget _weekRow(Map<String, dynamic> w) {
    final deload = w['is_deload'] == true;
    final vol = (w['volume_multiplier'] as num?)?.toDouble() ?? 1.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        SizedBox(width: 42, child: Text('W${w['week']}',
            style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w800))),
        Expanded(child: Text(w['phase']?.toString() ?? '',
            style: const TextStyle(color: _muted, fontSize: 12))),
        SizedBox(width: 70, child: ClipRRect(borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: (vol / 1.4).clamp(0, 1), minHeight: 6,
              backgroundColor: _panel2, color: deload ? _warn : _brand))),
        const SizedBox(width: 8),
        SizedBox(width: 44, child: Text('×$vol', textAlign: TextAlign.right,
            style: TextStyle(color: deload ? _warn : _text, fontSize: 11.5, fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        Text('RPE${w['intensity']}', style: const TextStyle(color: _muted, fontSize: 10.5)),
        if (deload) const Padding(padding: EdgeInsets.only(left: 6),
          child: Icon(Icons.bedtime_rounded, color: _warn, size: 13)),
      ]),
    );
  }
}
