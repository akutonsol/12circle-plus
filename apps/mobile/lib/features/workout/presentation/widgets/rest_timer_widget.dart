import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/rest_alarm.dart';

/// Wall-clock rest countdown with an overtime alarm. Counts down to 0 (spoken
/// cues), then — if the user hasn't started the next set — counts UP in flashing
/// red with a siren until dismissed (the active screen clears it when a weight
/// field is focused). [totalSeconds] is the original duration for the ring.
class RestTimerWidget extends StatefulWidget {
  final DateTime endTime;
  final int totalSeconds;
  final VoidCallback onComplete; // skip / dismiss
  /// FIT-017 declares two controls on this state: "Skip rest, start set" and
  /// "Add 30 seconds". The second one did not exist — a client who needed
  /// longer could only watch the clock run into overtime and start draining
  /// points. Null hides it rather than rendering a control that does nothing.
  final VoidCallback? onExtend;
  final ValueChanged<int>? onTick; // remaining seconds (0 in overtime)
  final VoidCallback? onOvertime; // fired once when the rest runs into overtime
  // Fired again for every [penaltyIntervalSeconds] the user stays in overtime, so
  // points keep draining until they start the next set (ongoing accountability).
  final VoidCallback? onOvertimePenaltyTick;
  final int penaltyIntervalSeconds;

  const RestTimerWidget({
    super.key,
    required this.endTime,
    required this.totalSeconds,
    required this.onComplete,
    this.onExtend,
    this.onTick,
    this.onOvertime,
    this.onOvertimePenaltyTick,
    this.penaltyIntervalSeconds = 20,
  });

  @override
  State<RestTimerWidget> createState() => _RestTimerWidgetState();
}

class _RestTimerWidgetState extends State<RestTimerWidget> {
  int _remaining = 0;
  int _overtime = 0;
  int _intervalsPenalized = 0; // how many overtime intervals have drained points
  int? _lastSpoken;
  bool _warned30 = false;
  bool _sirenOn = false;
  bool _flash = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final diff = widget.endTime.difference(DateTime.now()).inMilliseconds / 1000.0;
    _remaining = diff > 0 ? diff.ceil() : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTick?.call(_remaining);
    });
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final diff = widget.endTime.difference(DateTime.now()).inMilliseconds / 1000.0;
    if (diff > 0) {
      final rem = diff.ceil();
      if (rem != _remaining) {
        setState(() => _remaining = rem);
        widget.onTick?.call(rem);
        if (rem == 30 && widget.totalSeconds > 30 && !_warned30) {
          _warned30 = true;
          speakRest('30 seconds left');
        }
        if (rem <= 12 && rem >= 1 && rem != _lastSpoken) {
          _lastSpoken = rem;
          speakRest('$rem');
        }
      }
    } else {
      // ── Overtime ──
      if (!_sirenOn) {
        _sirenOn = true;
        speakRest('Rest over. Get moving.');
        startRestSiren();
        widget.onTick?.call(0);
        widget.onOvertime?.call(); // -5 idle penalty
      }
      final over = (-diff).floor();
      // Drain points on every further interval spent in overtime.
      final due = widget.penaltyIntervalSeconds > 0
          ? over ~/ widget.penaltyIntervalSeconds
          : 0;
      if (due > _intervalsPenalized) {
        _intervalsPenalized = due;
        widget.onOvertimePenaltyTick?.call();
      }
      setState(() {
        _remaining = 0;
        _overtime = over;
        _flash = !_flash; // ~250ms blink
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    stopRestSiren(); // clearing the timer (dismiss/skip/navigate) stops the siren
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overtime = _overtime > 0;
    final ending = _remaining <= 12;
    final accent = overtime ? AppColors.error : (ending ? AppColors.error : AppColors.purple);

    if (overtime) {
      final m = _overtime ~/ 60;
      final s = _overtime % 60;
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _flash ? AppColors.error.withValues(alpha: 0.30) : AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error, width: _flash ? 2 : 1),
        ),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('OVERTIME', style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(width: 8),
              Text('+${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
                style: const TextStyle(color: AppColors.error, fontSize: 18, fontWeight: FontWeight.w900)),
            ]),
            const Text('Start your next set to stop the siren',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ]),
          const Spacer(),
          if (widget.onExtend != null)
            _RestAction(
              text: '+30s',
              label: 'Add 30 seconds',
              color: AppColors.textSecondary,
              onTap: widget.onExtend!),
          _RestAction(
            text: 'STOP',
            label: 'Skip rest, start set',
            color: AppColors.error,
            onTap: widget.onComplete),
        ]),
      );
    }

    final minutes = _remaining ~/ 60;
    final seconds = _remaining % 60;
    final progress = widget.totalSeconds > 0
        ? (_remaining / widget.totalSeconds).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(Icons.timer_outlined, color: accent, size: 18),
        const SizedBox(width: 8),
        const Text('Rest', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text('${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
          style: TextStyle(color: ending ? AppColors.error : AppColors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        const SizedBox(width: 14),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress, minHeight: 6,
              backgroundColor: AppColors.surfaceDarkElevated,
              valueColor: AlwaysStoppedAnimation<Color>(accent)),
          ),
        ),
        const SizedBox(width: 4),
        if (widget.onExtend != null)
          _RestAction(
            text: '+30s',
            label: 'Add 30 seconds',
            color: AppColors.textSecondary,
            onTap: widget.onExtend!),
        _RestAction(
          text: 'SKIP',
          label: 'Skip rest, start set',
          color: AppColors.purple,
          onTap: widget.onComplete),
      ]),
    );
  }
}

/// A control in the rest banner.
///
/// Two things it does that the bare `GestureDetector` + `Text` it replaced did
/// not. It carries an **accessible name in the design's own wording** — the
/// banner is too narrow for "Skip rest, start set" as visible text, so the
/// short label is drawn and the full phrase is what a screen reader announces,
/// rather than the nothing an icon-only or abbreviated control announces today
/// (see F-22 / A-G8). And it reserves a 44 dp target around a 12 pt label that
/// would otherwise be about 30 dp tall — the floor F-6 was raised about.
class _RestAction extends StatelessWidget {
  final String text;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _RestAction({
    required this.text,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        // `excludeSemantics` drops the child's ACTIONS too, so the tap has to be
        // handed to the Semantics as well — otherwise the node announces as a
        // button a screen reader cannot activate. Measured on-device on the
        // intake back button before it was caught here as well.
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(text,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
          ),
        ),
      );
}
