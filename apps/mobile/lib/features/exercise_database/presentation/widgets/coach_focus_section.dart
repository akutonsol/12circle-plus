// Coach Focus — the Phase 1 layered-media overlay. On any exercise, a coach can
// add their own coaching (a "Coach Focus Today" list, a note, and their own demo
// video by link). The client sees their coach's overlay above the official
// content — turning a certified library entry into that coach's teaching.
// Text is the highest-adoption path and ships now; voice recording is next.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/custom_exercise_service.dart';
import '../../../auth/domain/auth_provider.dart';
import '../../../payments/presentation/paywall_gate.dart' show confirmedRoleRead;
import '../../../workout/presentation/widgets/section_load_failure.dart';
import '../../../workout/presentation/widgets/youtube_embed.dart';
import 'coach_voice.dart';

const _panel  = Color(0xFF141019);
const _panel2 = Color(0xFF1B1526);
const _brand  = Color(0xFFB76DFF);
const _mint   = Color(0xFF6FFBBE);
const _text   = Color(0xFFEDE7F3);
const _muted  = Color(0xFFB6A9C4);

/// P0-FL-58 · a >= 44px target around [child], which keeps its own look.
/// [label] names the action and the item; [selected] (when given) says whether
/// it is the current choice; a null [onTap] is disabled.
class _FocusTarget extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool? selected;
  final bool liveRegion;
  final Widget child;
  const _FocusTarget({required this.label, required this.onTap, required this.child,
    this.selected, this.liveRegion = false});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onTap != null,
    selected: selected,
    inMutuallyExclusiveGroup: selected == null ? null : true,
    liveRegion: liveRegion,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Center(widthFactor: 1, heightFactor: 1, child: child))));
}

/// P0-FL-58 r2 · [field] under a [name] that stays once its hint is gone.
Widget _named(String name, Widget field) =>
    MergeSemantics(child: Semantics(label: name, child: field));

class CoachFocusSection extends ConsumerStatefulWidget {
  final String exerciseId;
  /// Lowercased searchable attributes of the exercise (name/muscle/equipment)
  /// used for deterministic pack suggestions. Optional.
  final String matchText;
  const CoachFocusSection({super.key, required this.exerciseId, this.matchText = ''});
  @override
  ConsumerState<CoachFocusSection> createState() => _CoachFocusSectionState();
}

/// Deterministic pack → exercise match: how many of a pack's name terms appear
/// in this exercise's attributes. No AI — just token overlap. Returns id→%.
Map<String, int> _packScores(List<Map<String, dynamic>> packs, String matchText) {
  final ex = matchText.toLowerCase();
  if (ex.trim().isEmpty) return const {};
  const stop = {'pack', 'packs', 'cue', 'cues', 'focus', 'coach', 'the', 'and', 'for'};
  final out = <String, int>{};
  for (final p in packs) {
    final tokens = (p['name']?.toString() ?? '').toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length > 2 && !stop.contains(t)).toList();
    if (tokens.isEmpty) continue;
    final matched = tokens.where((t) => ex.contains(t)).length;
    if (matched == 0) continue;
    out[p['id'].toString()] = (matched / tokens.length * 100).round();
  }
  return out;
}

class _CoachFocusSectionState extends ConsumerState<CoachFocusSection> {
  final _svc = CustomExerciseService();
  Map<String, dynamic>? _overlay; // client: resolved coach overlay; coach: own
  bool _loading = true;
  bool _isStaff = false;

  /// P0-FL-45b · which member + view the shown [_overlay] was loaded for.
  ///
  /// This read the role ONCE, in initState, with `ref.read(…).valueOrNull`:
  /// a coach whose profile was still loading got the CLIENT view until the
  /// screen was reopened, and after a sign-out/sign-in the previous member's
  /// role chose the view. The role is now WATCHED, confirmed for the member
  /// signed in now, and the section reloads whenever member or view changes.
  /// While the role is unknown nothing is shown (neither the editor nor
  /// another view's overlay).
  String? _loadedKey;

  /// P0-FL-53a · the last read of the overlay failed (the service recorded
  /// it). Null = the shown [_overlay] (or its absence) is what the server said.
  ///
  /// A failed read returned null — "no overlay" — so a coach was offered "Add
  /// your coaching" and could save a blank editor over their real overlay.
  /// While this is set nothing offers authoring; an overlay shown before a
  /// failed REFRESH stays on screen, but its Edit is held.
  Object? _loadError;
  bool _retrying = false;

  /// P0-FL-53a (S-53a-1) · numbers each read; only the newest one is applied.
  /// Two reads can overlap (a background reload after an edit and a retry):
  /// an older SUCCESS landing after a newer FAILURE cleared the failure and
  /// gave Edit back over a copy the newest read could not confirm.
  int _loadSeq = 0;

  /// Loads the overlay for [key] (`uid|staff` or `uid|client`); a response
  /// that lands after the member or view changed, or after a newer read
  /// started, is dropped.
  Future<void> _loadFor(String key, bool staff) async {
    _loadedKey = key;
    final seq = ++_loadSeq;
    try {
      final data = staff
          ? await _svc.getCoachOverlay(widget.exerciseId)
          : await _svc.resolveExerciseMedia(widget.exerciseId);
      if (!mounted || _loadedKey != key || seq != _loadSeq) return;
      setState(() {
        _isStaff = staff; _overlay = data; _loadError = null; _loading = false;
      });
    } catch (e) {
      if (!mounted || _loadedKey != key || seq != _loadSeq) return;
      // Keep whatever was shown for this member + view; say the read failed.
      setState(() { _isStaff = staff; _loadError = e; _loading = false; });
    }
  }

  /// Re-reads for the member and view currently shown (after an edit).
  void _load() {
    final key = _loadedKey;
    if (key == null) return;
    _loadFor(key, key.endsWith('|staff'));
  }

  Future<void> _retry() async {
    final key = _loadedKey;
    if (_retrying || key == null) return;
    setState(() => _retrying = true);
    await _loadFor(key, key.endsWith('|staff'));
    if (mounted) setState(() => _retrying = false);
  }

  Widget _failure() => SectionLoadFailure(
        what: _isStaff ? 'your coaching for this exercise' : "your coach's focus",
        error: _loadError,
        busy: _retrying,
        accent: _brand,
        textColor: _text,
        mutedColor: _muted,
        detail: _isStaff ? 'Editing is paused until it loads.' : null,
        onRetry: _retry,
      );

  List<String> _focusOf(Map<String, dynamic>? m) {
    final f = m?['focus'];
    return f is List ? f.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList() : const [];
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final role =
        confirmedRoleRead(ref.watch(currentUserProfileProvider), user);
    if (role == null || user == null) {
      // Unknown: forget what was shown for whoever was confirmed before.
      if (_loadedKey != null) {
        _loadedKey = null;
        _overlay = null;
        _loadError = null;
        _loading = true;
      }
      return const SizedBox.shrink();
    }
    final staff = role.role == 'coach' || role.role == 'admin';
    final key = '${user.id}|${staff ? 'staff' : 'client'}';
    if (key != _loadedKey) {
      _overlay = null;
      _loadError = null;
      _loading = true;
      _loadFor(key, staff); // async: its setState lands after this build
    }
    if (_loading) return const SizedBox.shrink();
    final failed = _loadError != null;

    // Coach/admin: always show the editor entry (add or edit their overlay)
    // — unless the read failed: then no authoring is offered.
    if (_isStaff) {
      final has = _overlay != null;
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (failed) _failure(),
          if (failed && has) const SizedBox(height: 8),
          if (has) _card(_overlay!, editable: !failed)
          else if (!failed) _addPrompt(),
        ]),
      );
    }

    // Client: only show when their coach has an overlay for this exercise.
    final shows = _overlay?['has_coach_overlay'] == true;
    if (!failed && !shows) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (failed) _failure(),
        if (failed && shows) const SizedBox(height: 8),
        if (shows) _card(_overlay!, editable: false),
      ]));
  }

  Widget _addPrompt() => Semantics(
    container: true,
    button: true,
    label: 'Add your coaching for this exercise — a focus, a note, your own video',
    onTap: _openEditor,
    excludeSemantics: true,
    child: GestureDetector(
    onTap: _openEditor,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _panel, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brand.withValues(alpha: 0.35))),
      child: Row(children: [
        const Icon(Icons.add_comment_rounded, color: _brand, size: 18),
        const SizedBox(width: 10),
        const Expanded(child: Text('Add your coaching — a focus, a note, your own video',
            style: TextStyle(color: _text, fontSize: 13.5, fontWeight: FontWeight.w600))),
        const Icon(Icons.chevron_right_rounded, color: _muted, size: 18),
      ]),
    ),
  ));

  Widget _card(Map<String, dynamic> m, {required bool editable}) {
    final focus = _focusOf(m);
    final note = m['note']?.toString();
    final video = m['video_ref']?.toString();
    final coachName = m['coach_name']?.toString();
    final player = (video != null && video.trim().isNotEmpty) ? buildInAppVideo(video) : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_brand.withValues(alpha: 0.14), _panel2],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16), border: Border.all(color: _brand.withValues(alpha: 0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.sports_rounded, color: _brand, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(editable ? 'YOUR COACHING' : 'COACH FOCUS TODAY',
              style: const TextStyle(color: _brand, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1))),
          if (editable)
            _FocusTarget(label: 'Edit your coaching for this exercise', onTap: _openEditor,
              child: const Text('Edit', style: TextStyle(color: _brand, fontSize: 12, fontWeight: FontWeight.w800))),
        ]),
        if (!editable && coachName != null) Padding(padding: const EdgeInsets.only(top: 2),
          child: Text(coachName, style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600))),
        // Order: voice → focus → note → video. Voice first creates connection.
        if ((m['voice_url']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          CoachVoicePlayer(
            url: m['voice_url'].toString(),
            durationMs: (m['voice_duration_ms'] as num?)?.toInt(),
            coachName: editable ? null : coachName),
        ],
        if (focus.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...focus.map((f) => Padding(padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_rounded, color: _mint, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(f, style: const TextStyle(color: _text, fontSize: 13.5, height: 1.4))),
            ]))),
        ],
        if (note != null && note.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(note, style: const TextStyle(color: _muted, fontSize: 13, height: 1.45)),
        ],
        if (player != null) ...[
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(12),
            child: AspectRatio(aspectRatio: 16 / 9, child: player)),
        ],
        if (editable) Padding(padding: const EdgeInsets.only(top: 6),
          child: Text('Only your active clients see this.', style: TextStyle(color: _muted.withValues(alpha: 0.7), fontSize: 10.5))),
      ]),
    );
  }

  Future<void> _openEditor() async {
    final focusCtl = TextEditingController(text: _focusOf(_overlay).join('\n'));
    final noteCtl = TextEditingController(text: _overlay?['note']?.toString() ?? '');
    final videoCtl = TextEditingController(text: _overlay?['video_ref']?.toString() ?? '');
    // P0-FL-50a · a failed packs read is not "no packs": the editor says it
    // couldn't load them and offers a retry (the service has recorded it).
    var packs = const <Map<String, dynamic>>[];
    Object? packsError;
    var packsRetrying = false;
    Future<void> loadPacks() async {
      try {
        packs = await _svc.getCoachingPacks();
        packsError = null;
      } catch (e) {
        packsError = e;
      }
    }
    await loadPacks();
    var sheetOverlay = _overlay;
    // P0-FL-53a · a failed re-read of the overlay inside the sheet (after a
    // voice note was cleared or recorded) is said in place of the voice note
    // — never shown as "no voice note" — with a retry.
    Object? sheetReadError;
    var sheetRetrying = false;
    Future<void> rereadSheet() async {
      try {
        sheetOverlay = await _svc.getCoachOverlay(widget.exerciseId);
        sheetReadError = null;
      } catch (e) {
        sheetReadError = e;
      }
    }
    // P0-FL-53a · a pack save that failed is said in the sheet, and the name
    // typed is kept for the next try (the cues stay in the focus field).
    final packNameCtl = TextEditingController();
    String? packSaveError;
    var savingPack = false;
    // P0-FL-53a · a failed save keeps the sheet open with what was typed and
    // says so; a failed voice-note removal is said too (both recorded by the
    // service). They were ignored: the sheet closed / the note just stayed.
    String? saveError;
    String? voiceClearError;
    var expiry = 'never';
    var saving = false;
    if (!mounted) return;
    DateTime? expiryDate() => switch (expiry) {
      'today' => DateTime.now().add(const Duration(hours: 18)),
      'week' => DateTime.now().add(const Duration(days: 7)),
      _ => null,
    };
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Future<void> saveAsPack() async {
          if (savingPack) return;
          final nameCtl = packNameCtl;
          final name = await showDialog<String>(context: ctx, builder: (dctx) => AlertDialog(
            backgroundColor: _panel2,
            title: const Text('Save cue pack', style: TextStyle(color: _text, fontSize: 16)),
            content: _named('Pack name', TextField(controller: nameCtl, autofocus: true,
              style: const TextStyle(color: _text),
              decoration: const InputDecoration(hintText: 'e.g. Squat cues', hintStyle: TextStyle(color: _muted)))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel', style: TextStyle(color: _muted))),
              TextButton(onPressed: () => Navigator.pop(dctx, nameCtl.text.trim()),
                child: const Text('Save', style: TextStyle(color: _brand, fontWeight: FontWeight.w800))),
            ],
          ));
          final cues = focusCtl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          if (name != null && name.isNotEmpty && cues.isNotEmpty) {
            setSheet(() { savingPack = true; packSaveError = null; });
            final ok = await _svc.createCoachingPack(name, cues);
            if (!ok) {
              savingPack = false;
              packSaveError = couldntMessage('save your cue pack', _svc.lastError);
              if (ctx.mounted) setSheet(() {});
              return;
            }
            packNameCtl.clear();
            await loadPacks();
            savingPack = false;
            if (ctx.mounted) setSheet(() {});
          }
        }
        // A failure said in the sheet: announced when it appears.
        Widget inlineError(String m) => Padding(padding: const EdgeInsets.only(bottom: 14),
          child: Semantics(liveRegion: true, container: true,
            child: Text(m, style: const TextStyle(color: _text, fontSize: 12.5, height: 1.4))));
        // Editing the cues makes an earlier pack-save failure stale.
        void cuesEdited() {
          if (packSaveError != null) setSheet(() => packSaveError = null);
        }
        Widget field(String label, String name, TextEditingController c, String hint,
            {int min = 1, ValueChanged<String>? onChanged}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 6),
            _named(name, TextField(controller: c, minLines: min, maxLines: min == 1 ? 1 : null, onChanged: onChanged,
              style: const TextStyle(color: _text, fontSize: 14),
              decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: _muted),
                filled: true, fillColor: _panel2,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(12)))),
            const SizedBox(height: 14),
          ]);
        // P0-FL-53a · the body scrolls: with failure notices, large text, a
        // narrow screen or the keyboard up it overflowed and Save was lost.
        return SingleChildScrollView(child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Coach this exercise',
                style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Overlay your coaching on the official content. One focus per line.',
                style: TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 16),
            if (packsError != null) ...[
              SectionLoadFailure(
                what: 'your cue packs',
                error: packsError,
                busy: packsRetrying,
                accent: _brand,
                textColor: _text,
                mutedColor: _muted,
                onRetry: () async {
                  if (packsRetrying) return;
                  setSheet(() => packsRetrying = true);
                  await loadPacks();
                  packsRetrying = false;
                  if (ctx.mounted) setSheet(() {});
                }),
              const SizedBox(height: 14),
            ] else if (packs.isNotEmpty) ...[
              Builder(builder: (_) {
                final scores = _packScores(packs, widget.matchText);
                final sorted = [...packs]..sort((a, b) =>
                    (scores[b['id'].toString()] ?? -1).compareTo(scores[a['id'].toString()] ?? -1));
                final anyMatch = scores.isNotEmpty;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(anyMatch ? 'SUGGESTED PACKS' : 'APPLY A PACK',
                      style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: [
                    for (final p in sorted) _FocusTarget(
                      label: 'Apply pack ${p['name']?.toString() ?? 'Pack'}'
                          '${scores[p['id'].toString()] == null ? '' : ', ${scores[p['id'].toString()]}% match'}',
                      onTap: () {
                        final cues = (p['cues'] as List?)?.map((e) => e.toString()).toList() ?? [];
                        setSheet(() { focusCtl.text = cues.join('\n'); packSaveError = null; });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: scores.containsKey(p['id'].toString()) ? _brand.withValues(alpha: 0.18) : _panel2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _brand.withValues(alpha: 0.3))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (scores.containsKey(p['id'].toString()))
                            const Padding(padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.star_rounded, color: _brand, size: 13)),
                          Flexible(child: Text(p['name']?.toString() ?? 'Pack',
                              style: const TextStyle(color: _brand, fontSize: 12, fontWeight: FontWeight.w700))),
                          if (scores[p['id'].toString()] != null)
                            Text('  ${scores[p['id'].toString()]}%',
                                style: TextStyle(color: _brand.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                ]);
              }),
            ],
            field('COACH FOCUS TODAY', 'Coach focus today', focusCtl, 'Control the descent\nPush through your heels\nIgnore weight today',
                min: 3, onChanged: (_) => cuesEdited()),
            // P0-FL-53a · a save in flight is visible (and announced).
            Align(alignment: Alignment.centerRight, child: _FocusTarget(
              label: savingPack ? 'Saving pack…' : 'Save these as a pack',
              onTap: savingPack ? null : saveAsPack,
              liveRegion: savingPack,
              child: Text(savingPack ? 'Saving pack…' : '＋ Save these as a pack',
                style: TextStyle(color: savingPack ? _brand.withValues(alpha: 0.5) : _brand,
                    fontSize: 12, fontWeight: FontWeight.w700)))),
            if (packSaveError != null) inlineError(packSaveError!),
            field('NOTE (optional)', 'Note (optional)', noteCtl, 'A short message to your clients…', min: 2),
            field('YOUR VIDEO (optional — YouTube link or id)',
                'Your video (optional — YouTube link or id)', videoCtl, 'https://youtu.be/…'),
            // ── Voice note ──
            const Text('VOICE NOTE (optional)',
                style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 6),
            if (sheetReadError != null)
              Padding(padding: const EdgeInsets.only(bottom: 8),
                child: SectionLoadFailure(
                  what: 'your voice note',
                  error: sheetReadError,
                  busy: sheetRetrying,
                  accent: _brand,
                  textColor: _text,
                  mutedColor: _muted,
                  onRetry: () async {
                    if (sheetRetrying) return;
                    setSheet(() => sheetRetrying = true);
                    await rereadSheet();
                    sheetRetrying = false;
                    if (ctx.mounted) setSheet(() {});
                  }))
            else if ((sheetOverlay?['voice_url']?.toString() ?? '').isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(child: CoachVoicePlayer(
                    url: sheetOverlay!['voice_url'].toString(),
                    durationMs: (sheetOverlay?['voice_duration_ms'] as num?)?.toInt())),
                  IconButton(tooltip: 'Remove your voice note',
                    icon: const Icon(Icons.delete_outline_rounded, color: _muted, size: 20),
                    onPressed: () async {
                      voiceClearError = null;
                      final cleared = await _svc.clearCoachVoice(widget.exerciseId);
                      if (!cleared) {
                        voiceClearError = couldntMessage('remove your voice note', _svc.lastError);
                      }
                      await rereadSheet();
                      _load(); if (ctx.mounted) setSheet(() {});
                    }),
                ])),
            if (voiceClearError != null) inlineError(voiceClearError!),
            Wrap(spacing: 6, children: [
              for (final e in const [('today', 'Today'), ('week', 'This week'), ('never', 'Never')])
                _FocusTarget(
                  label: 'Voice note expires: ${e.$2}',
                  selected: expiry == e.$1,
                  onTap: () => setSheet(() => expiry = e.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: expiry == e.$1 ? _brand : _panel2, borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _brand.withValues(alpha: 0.25))),
                    child: Text(e.$2, style: TextStyle(
                        color: expiry == e.$1 ? Colors.white : _muted, fontSize: 11, fontWeight: FontWeight.w700))),
                ),
            ]),
            const SizedBox(height: 8),
            // P0-FL-58 · the recorder's own bar is 42px at 1×: 44px at least.
            ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: CoachVoiceRecorder(
              exerciseId: widget.exerciseId,
              resolveExpiry: expiryDate,
              onRecorded: () async {
                // P0-FL-53a r3 · a new note replaces the one that couldn't be
                // removed, so that message no longer describes what is there.
                voiceClearError = null;
                await rereadSheet();
                _load(); if (ctx.mounted) setSheet(() {});
              })),
            const SizedBox(height: 16),
            if (saveError != null) inlineError(saveError!),
            SizedBox(width: double.infinity, child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _brand, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: saving ? null : () async {
                setSheet(() { saving = true; saveError = null; });
                final focus = focusCtl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                final ok = await _svc.upsertCoachOverlay(widget.exerciseId,
                    note: noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
                    focus: focus,
                    videoRef: videoCtl.text.trim().isEmpty ? null : videoCtl.text.trim());
                if (!ok) {
                  // Keep the sheet and what was typed; say it (recorded).
                  saving = false;
                  saveError = couldntMessage('save your coaching', _svc.lastError);
                  if (ctx.mounted) setSheet(() {});
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) { setState(() => _loading = true); _load(); }
              },
              child: Text(saving ? 'Saving…' : 'Save coaching',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)))),
          ]),
        ));
      }),
    );
  }
}
