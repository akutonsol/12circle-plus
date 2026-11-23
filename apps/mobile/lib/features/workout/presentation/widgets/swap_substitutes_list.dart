import 'package:flutter/material.dart';

import '../../../../core/widgets/load_failure_notice.dart';

const _white   = Colors.white;
const _muted   = Color(0xFFCFC2D6);
const _primary = Color(0xFFDDB7FF);
const _errorColor = Color(0xFFFFB4AB);

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
  });

  final List<Map<String, dynamic>> librarySubs;
  final Future<List<Map<String, dynamic>>> Function() loadGlobal;
  final void Function(Map<String, dynamic> sub) onPick;

  @override
  State<SwapSubstitutesList> createState() => _SwapSubstitutesListState();
}

class _SwapSubstitutesListState extends State<SwapSubstitutesList> {
  List<Map<String, dynamic>>? _subs;
  Object? _error;

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
    if (_error != null) setState(() => _error = null);
    try {
      final subs = await widget.loadGlobal();
      if (mounted) setState(() => _subs = subs);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LoadFailureNotice(
          message: couldntMessage('load substitutes', error),
          semanticLabel: 'Try loading substitutes again',
          textColor: _errorColor,
          accent: _primary,
          onRetry: _load,
        ),
      );
    }
    final subs = _subs;
    if (subs == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: _primary))),
      );
    }
    if (subs.isEmpty) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('No substitutes found.', style: TextStyle(color: _muted)));
    }
    // Scrollable so a long substitute list never overflows the sheet.
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: subs
          .map((s) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s['name']?.toString() ?? '',
                  style: const TextStyle(
                      color: _white, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('${s['equipment'] ?? ''} · ${s['difficulty'] ?? ''}',
                  style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 11)),
              trailing: const Icon(Icons.swap_horizontal_circle_rounded,
                  color: _primary, size: 22),
              onTap: () => widget.onPick(s)))
          .toList(),
    );
  }
}
