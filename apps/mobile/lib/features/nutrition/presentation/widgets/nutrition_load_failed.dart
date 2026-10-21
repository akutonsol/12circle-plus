import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../meals_dashboard_screen.dart' show nutritionTotalsProvider;

/// FIT-022 · "Loading & failure — the two patterns every data screen inherits",
/// drawn on Nutrition.
///
/// ── THE RULE, IN THE BOARD'S OWN WORDS ─────────────────────────────────────
/// *"The failure state names what did **not** happen — 'everything you've
/// logged is saved' — because the fear a failed screen creates is data loss,
/// not inconvenience."*
///
/// Every string below is the board's, verbatim:
///
///   "Couldn't load today"
///   "Everything you've already logged is saved. Only today's totals failed to
///    load."
///   "Try again"
///
/// ── WHAT IT REPLACES ───────────────────────────────────────────────────────
/// `totals.valueOrNull?['calories'] ?? 0.0`. A failed read rendered **zero
/// calories, zero protein, zero carbs, zero fat** to a client who had logged
/// three meals — who might reasonably log them again. The same class as
/// `/train`'s "0 workouts", `/home`'s "0%" and `/challenges`' "0 active
/// challenges", and a tenth instance beyond the nine in the F-15 inventory.
class NutritionLoadFailed extends ConsumerWidget {
  const NutritionLoadFailed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _error.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.cloud_off_rounded, color: _error, size: 18),
            const SizedBox(width: 8),
            Semantics(
              header: true,
              container: true,
              child: const Text("Couldn't load today",
                style: TextStyle(
                  color: _error, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          // The sentence the board's annotation is about: it names what did
          // NOT happen first.
          const Text(
            "Everything you've already logged is saved. Only today's totals "
            'failed to load.',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.5)),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            child: GestureDetector(
              onTap: () => ref.invalidate(nutritionTotalsProvider),
              behavior: HitTestBehavior.opaque,
              child: Container(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
                child: const Text('Try again',
                  style: TextStyle(
                    color: _white, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      );
}

const _card  = Color(0xFF0E0B16);
const _white = Colors.white;
const _muted = Color(0xFFCFC2D6);
const _error = Color(0xFFFFB4AB);
