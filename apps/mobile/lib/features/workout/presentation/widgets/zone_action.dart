import 'package:flutter/material.dart';

/// A control in the Workout Zone's top bar.
///
/// The two it draws — "End session" and "Pause session" — are both named from
/// FIT-002, and both reserve a 44 dp target around a 36 dp chip. Before this
/// the bar held a single unlabelled 36 dp cross.
class ZoneAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const ZoneAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            alignment: Alignment.center,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.3))),
              child: Icon(icon, color: color, size: 18),
            ),
          ),
        ),
      );
}
