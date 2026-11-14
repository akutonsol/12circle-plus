/// The one place that knows `weekly_checkins` carries two column families.
///
/// ── WHAT THE TABLE ACTUALLY HAS ────────────────────────────────────────────
/// Migration 000 (baseline) created `energy` and `sleep_hours_avg`. Migration
/// 001 added `energy_level`, `sleep_hours`, `stress_level`, `hunger_level`,
/// `compliance_percent`, `weight_kg` and `notes`. Both sets are real columns, so
/// nothing was ever "missing" — the application simply disagreed with itself.
/// The one writer sent `energy` and `sleep_hours_avg`; the readers that matter
/// (`ai-coach`, `insights_provider`, the coach review queue) read `energy_level`
/// and `sleep_hours`. A check-in that saved fine therefore reached the AI as
/// `Energy: undefined/5`.
///
/// ── THE RULING (PD-B02, option: the 001 family) ────────────────────────────
/// `energy_level` and `sleep_hours` are canonical. New rows are written to
/// them. This file is the only code that reads the legacy names, and only as a
/// FALLBACK, so a row written before the ruling is still readable without a
/// data migration. That is the pattern `coach_review_queue.dart` already used
/// (`row['energy_level'] ?? row['energy']`); it is now shared rather than
/// re-implemented at each reader.
///
/// `mood` has no counterpart in the 001 family and stays as it is.
library;

/// Canonical column names — the ones the writer sends.
const kEnergyColumn = 'energy_level';
const kSleepColumn = 'sleep_hours';

/// Legacy baseline names. Read-only fallbacks; nothing writes them any more.
const kLegacyEnergyColumn = 'energy';
const kLegacySleepColumn = 'sleep_hours_avg';

/// Energy for a `weekly_checkins` row, canonical first. `null` means the row
/// carries neither — unknown, not zero.
num? checkinEnergy(Map<String, dynamic> row) =>
    _asNum(row[kEnergyColumn] ?? row[kLegacyEnergyColumn]);

/// Average sleep hours for a row, canonical first. `null` means unknown.
num? checkinSleepHours(Map<String, dynamic> row) =>
    _asNum(row[kSleepColumn] ?? row[kLegacySleepColumn]);

/// A number, a numeric string, or `null`. A cast (`as num?`) would throw on a
/// string, and `coach_review_queue` — the reader this helper replaces — already
/// accepted both, so a tighter helper would have been a regression.
num? _asNum(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

/// Energy and stress are asked on a 1–5 scale: the form's `NumberPicker` has
/// five tiles, the hub prints "of 5", and the form itself raises the coach
/// notice at stress 4. These are `needsCoachAttention`'s thresholds.
const kCheckinScaleMax = 5;

/// Stress at or above the level the form flags for the coach (4 of 5).
bool isHighStress(num? stress) => stress != null && stress >= 4;

/// The flags the coach's client page raises from a client's check-in averages.
///
/// They were judged as if the scales ran to 10: "High chronic stress" needed an
/// average above 7, which a 1–5 answer can never reach, so a client reporting
/// 5 of 5 every week was shown "✓ No flags — client trending well".
List<String> checkinInsights({
  required int count,
  required double avgEnergy,
  required double avgStress,
  required double avgMood,
}) {
  final out = <String>[];
  if (count == 0) return out;
  if (avgEnergy < 3) out.add('⚠ Consistently low energy — review sleep and recovery');
  if (isHighStress(avgStress)) out.add('⚠ High chronic stress — consider deload week');
  if (count >= 4 && avgMood < 3) out.add('⚠ Low mood pattern — check in via call');
  if (out.isEmpty) out.add('✓ No flags — client trending well');
  return out;
}
