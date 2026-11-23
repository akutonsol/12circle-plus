import 'package:flutter/material.dart';

import 'section_load_failure.dart';

/// The substitutes in the active-workout swap sheet.
///
/// [librarySubs] (the built-in library's same-muscle matches) are shown when
/// there are any; otherwise the approved global custom exercises are read via
/// [loadGlobal].
///
/// P0-FL-50a · that read returned `[]` on ANY failure, so a client mid-workout
/// was told "No substitutes found." when the list simply hadn't loaded. A
/// failure (recorded by the service) now reads "Couldn't load substitutes"
/// with a busy-aware retry; only a read that answered with nothing is "none".
class SwapSubstitutesList extends StatefulWidget {
  const SwapSubstitutesList({
    super.key,
    required this.librarySubs,
    required this.loadGlobal,
    required this.onPick,
    required this.text,
    required this.muted,
    required this.accent,
  });

  final List<Map<String, dynamic>> librarySubs;
  final Future<List<Map<String, dynamic>>> Function() loadGlobal;
  final void Function(Map<String, dynamic> sub) onPick;

  /// The sheet's own palette (handed in, so this widget adds none — H-D2).
  final Color text;
  final Color muted;
  final Color accent;

  @override
  State<SwapSubstitutesList> createState() => _SwapSubstitutesListState();
}

class _SwapSubstitutesListState extends State<SwapSubstitutesList> {
  List<Map<String, dynamic>>? _subs;
  Object? _error;

  /// A retry of a failed read is in flight: the notice stays, busy.
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    if (widget.librarySubs.isNotEmpty) {
      _subs = widget.librarySubs;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final subs = await widget.loadGlobal();
      if (mounted) setState(() { _subs = subs; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await _load();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SectionLoadFailure(
          what: 'substitutes',
          error: error,
          busy: _retrying,
          onRetry: _retry,
          accent: widget.accent,
          textColor: widget.text,
          mutedColor: widget.muted,
        ),
      );
    }
    final subs = _subs;
    if (subs == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
            child: Semantics(
                liveRegion: true,
                label: 'Loading substitutes',
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: widget.accent)))),
      );
    }
    if (subs.isEmpty) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('No substitutes found.', style: TextStyle(color: widget.muted)));
    }
    // Scrollable so a long substitute list never overflows the sheet.
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: subs
          .map((s) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s['name']?.toString() ?? '',
                  style: TextStyle(
                      color: widget.text, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('${s['equipment'] ?? ''} · ${s['difficulty'] ?? ''}',
                  style: TextStyle(color: widget.muted.withValues(alpha: 0.6), fontSize: 11)),
              trailing: Icon(Icons.swap_horizontal_circle_rounded,
                  color: widget.accent, size: 22),
              onTap: () => widget.onPick(s)))
          .toList(),
    );
  }
}
