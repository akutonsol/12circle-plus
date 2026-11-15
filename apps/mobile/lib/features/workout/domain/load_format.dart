/// Loads are stored in kilograms (`workout_set_logs.weight_kg`) and entered in
/// the member's unit: 'metric' is kg, anything else -- the app's default -- is
/// lb (the workout screen's own rule). This shows a stored load the same way.
library;

const double kgPerLb = 0.45359237;

/// Whether the member's `unit_preference` is metric.
bool prefersMetric(String? unitPreference) => unitPreference == 'metric';

/// "135 lb" / "61.2 kg": converted to the member's unit and rounded to 0.1,
/// without a trailing ".0". A load entered as 135 lb is stored as 61.23496995 kg
/// and used to be shown exactly so -- "61.23496995kg" to a member who trains in lb.
String formatLoad(num kg, {required bool metric}) {
  final v = metric ? kg.toDouble() : kg / kgPerLb;
  final r = (v * 10).round() / 10;
  final s = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  return '$s ${metric ? 'kg' : 'lb'}';
}
