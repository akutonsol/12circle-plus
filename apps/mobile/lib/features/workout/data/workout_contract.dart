/// The canonical workout-domain JSON contract, as defined in
/// `docs/WORKOUT_DOMAIN_CONTRACT.md`.
///
/// `program_workouts.exercises` is untyped `jsonb`, and six writers historically
/// disagreed about both the key names (`rest` vs `rest_seconds`, `weight` vs
/// `weight_kg`) and the value types (`reps` as `int` in one writer and `String`
/// in another). One reader had to guess, and a guess that misses turns into a
/// client with no program at all.
///
/// This file is the single place that turns a stored row into canonical form
/// and says so out loud. It has two halves and the split is the point:
///
///  * [WorkoutContract.normalizeExercises] accepts the *documented* historical
///    dialects and converts them, recording every conversion it makes as a
///    [ContractDeviation]. Nothing here is silent.
///  * the strict readers ([requireInt], [optionalNum], …) accept only the
///    canonical type and raise [WorkoutContractViolation] otherwise, naming the
///    workout, the exercise, the field and the offending value.
///
/// What it deliberately does *not* do is repair ambiguity. `reps: "8-12"` is not
/// a rep range the product supports; it is a violation. Coercing it to `8`, to
/// `12`, or to the codec's old `?? 10` default would invent a prescription, and
/// a fabricated prescription is worse than a named failure.
library;

/// A stored value that does not satisfy the canonical contract.
///
/// Raised rather than defaulted. The caller's job is to surface it — a decode
/// failure that becomes an empty workout is indistinguishable from "you have no
/// program", which is the defect this whole contract exists to end.
class WorkoutContractViolation implements Exception {
  /// Canonical field name, e.g. `reps`, `exercises`, `set_details[0].id`.
  final String field;

  /// Where in the document, e.g. `workout "w-1" · exercise 2 "Bench Press"`.
  final String location;

  /// Why it is not acceptable, in a sentence a human can act on.
  final String reason;

  /// The offending value, as stored.
  final Object? value;

  const WorkoutContractViolation({
    required this.field,
    required this.location,
    required this.reason,
    this.value,
  });

  @override
  String toString() => 'WorkoutContractViolation: $location · $field — $reason '
      '(got ${value == null ? 'null' : '${value.runtimeType} $value'})';
}

/// A legacy shape that was converted to canonical form on the way in.
///
/// Deviations are reported, not hidden: they are what tells us a writer is
/// still emitting a pre-contract dialect, and they are what the forward
/// migration exists to eliminate.
class ContractDeviation {
  final String location;
  final String field;

  /// The legacy shape found, e.g. `rest`, `String "10"`.
  final String found;

  /// What it was read as.
  final String appliedAs;

  const ContractDeviation({
    required this.location,
    required this.field,
    required this.found,
    required this.appliedAs,
  });

  @override
  String toString() => '$location · $field: $found → $appliedAs';
}

/// Canonical form plus the record of what had to be converted to get there.
class NormalizedExercises {
  final List<Map<String, dynamic>> exercises;
  final List<ContractDeviation> deviations;
  const NormalizedExercises(this.exercises, this.deviations);

  bool get isCanonical => deviations.isEmpty;
}

/// Canonical key names, types and the legacy-dialect translation.
abstract final class WorkoutContract {
  /// Bumped when the canonical shape changes. Written into snapshots so a
  /// reader can tell what it is looking at.
  static const version = 2;

  // ── Canonical keys ────────────────────────────────────────────────────────
  static const kInstanceId = 'exercise_instance_id';
  static const kExerciseId = 'exercise_id';
  static const kName = 'name';
  static const kPosition = 'position';
  static const kSets = 'sets';
  static const kReps = 'reps';
  static const kWeightKg = 'weight_kg';
  static const kRestSeconds = 'rest_seconds';
  static const kRpe = 'rpe';
  static const kTempo = 'tempo';
  static const kDurationSeconds = 'duration_seconds';
  static const kNotes = 'notes';
  static const kSetDetails = 'set_details';
  static const kSetId = 'id';
  static const kSetNumber = 'set_number';

  /// Legacy key → canonical key. Applied once, on the way in, and reported.
  static const _keyAliases = {
    'rest': kRestSeconds,
    'weight': kWeightKg,
    'load_kg': kWeightKg,
    'duration': kDurationSeconds,
  };

  /// Normalizes a stored `exercises` array into canonical form.
  ///
  /// Throws [WorkoutContractViolation] when the value is not an array of
  /// objects at all — that is structural, not dialectal, and there is nothing
  /// to convert.
  static NormalizedExercises normalizeExercises(
    Object? raw, {
    required String workoutLocation,
  }) {
    if (raw == null) return const NormalizedExercises([], []);
    if (raw is! List) {
      throw WorkoutContractViolation(
        field: 'exercises',
        location: workoutLocation,
        reason: 'must be a JSON array of exercise prescriptions',
        value: raw,
      );
    }

    final deviations = <ContractDeviation>[];
    final out = <Map<String, dynamic>>[];

    for (var i = 0; i < raw.length; i++) {
      final element = raw[i];
      if (element is! Map) {
        throw WorkoutContractViolation(
          field: 'exercises[$i]',
          location: workoutLocation,
          reason: 'must be a JSON object',
          value: element,
        );
      }
      final e = Map<String, dynamic>.from(element);
      final name = e[kName]?.toString().trim();
      final where = '$workoutLocation · exercise $i'
          '${(name == null || name.isEmpty) ? '' : ' "$name"'}';

      _applyKeyAliases(e, where, deviations);
      _coerceNumericStrings(e, where, deviations,
          intKeys: const [kSets, kReps, kRestSeconds, kDurationSeconds, kPosition],
          numKeys: const [kWeightKg, kRpe]);

      // Absent load means "not prescribed", which is `null` — never 0. A
      // fabricated 0 kg reads to a client as an instruction to lift nothing,
      // and that is exactly what every pre-contract writer produced.
      if (!e.containsKey(kWeightKg)) {
        e[kWeightKg] = null;
        deviations.add(ContractDeviation(
          location: where,
          field: kWeightKg,
          found: 'absent',
          appliedAs: 'null (no prescribed load)',
        ));
      }

      // Position is derived from the array, never trusted from the row: the
      // array *is* the ordering authority.
      e[kPosition] = i;

      final details = e[kSetDetails];
      if (details != null) {
        if (details is! List) {
          throw WorkoutContractViolation(
            field: kSetDetails,
            location: where,
            reason: 'must be a JSON array of set prescriptions when present',
            value: details,
          );
        }
        e[kSetDetails] = [
          for (var s = 0; s < details.length; s++)
            _normalizeSet(details[s], '$where · set $s', deviations),
        ];
      }

      out.add(e);
    }

    return NormalizedExercises(out, deviations);
  }

  static Map<String, dynamic> _normalizeSet(
    Object? raw,
    String where,
    List<ContractDeviation> deviations,
  ) {
    if (raw is! Map) {
      throw WorkoutContractViolation(
        field: 'set_details[]',
        location: where,
        reason: 'must be a JSON object',
        value: raw,
      );
    }
    final s = Map<String, dynamic>.from(raw);
    _applyKeyAliases(s, where, deviations);
    _coerceNumericStrings(s, where, deviations,
        intKeys: const [kReps, kSetNumber, kRestSeconds, kDurationSeconds],
        numKeys: const [kWeightKg, kRpe]);
    if (!s.containsKey(kWeightKg)) s[kWeightKg] = null;
    return s;
  }

  static void _applyKeyAliases(
    Map<String, dynamic> m,
    String where,
    List<ContractDeviation> deviations,
  ) {
    for (final alias in _keyAliases.entries) {
      if (!m.containsKey(alias.key)) continue;
      final canonical = alias.value;
      // A row carrying both keys is not a dialect, it is a contradiction —
      // and silently preferring one is how a coach's 60 s rest became 90 s.
      if (m.containsKey(canonical) && m[canonical] != null) {
        if (m[alias.key] != null && m[alias.key] != m[canonical]) {
          throw WorkoutContractViolation(
            field: canonical,
            location: where,
            reason: 'row carries both "${alias.key}" and "$canonical" with '
                'different values; the intended prescription is ambiguous',
            value: {alias.key: m[alias.key], canonical: m[canonical]},
          );
        }
        m.remove(alias.key);
        continue;
      }
      m[canonical] = m.remove(alias.key);
      deviations.add(ContractDeviation(
        location: where,
        field: canonical,
        found: 'legacy key "${alias.key}"',
        appliedAs: canonical,
      ));
    }
  }

  /// Converts numeric strings that parse **exactly** back to numbers.
  ///
  /// `"10"` is unambiguously the integer 10 and is accepted (and reported).
  /// `"8-12"`, `"10 reps"` and `""` are left as they are, so the strict reader
  /// raises on them rather than this pass inventing a value.
  static void _coerceNumericStrings(
    Map<String, dynamic> m,
    String where,
    List<ContractDeviation> deviations, {
    required List<String> intKeys,
    required List<String> numKeys,
  }) {
    for (final k in intKeys) {
      final v = m[k];
      if (v is! String) continue;
      final parsed = int.tryParse(v.trim());
      if (parsed == null) continue;
      m[k] = parsed;
      deviations.add(ContractDeviation(
        location: where, field: k, found: 'String "$v"', appliedAs: 'int $parsed'));
    }
    for (final k in numKeys) {
      final v = m[k];
      if (v is! String) continue;
      final parsed = num.tryParse(v.trim());
      if (parsed == null) continue;
      m[k] = parsed;
      deviations.add(ContractDeviation(
        location: where, field: k, found: 'String "$v"', appliedAs: 'num $parsed'));
    }
  }

  // ── Strict readers ────────────────────────────────────────────────────────
  //
  // These run *after* normalization. Anything they reject is genuinely outside
  // the contract, and the caller gets a named failure rather than a default.

  static String requireText(Map<String, dynamic> m, String field,
      {required String location}) {
    final v = m[field];
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) {
      throw WorkoutContractViolation(
        field: field, location: location, value: v,
        reason: 'is required and must be a non-empty string',
      );
    }
    return s;
  }

  static int requireInt(Map<String, dynamic> m, String field,
      {required String location, int? min, int? max}) {
    final v = m[field];
    if (v is! int) {
      throw WorkoutContractViolation(
        field: field, location: location, value: v,
        reason: v is num
            ? 'must be a whole number'
            : 'is required and must be an integer '
                '(the canonical type — strings are not accepted)',
      );
    }
    return _bounded(v, field, location, min, max) as int;
  }

  static int? optionalInt(Map<String, dynamic> m, String field,
      {required String location, int? min, int? max}) {
    final v = m[field];
    if (v == null) return null;
    if (v is! int) {
      throw WorkoutContractViolation(
        field: field, location: location, value: v,
        reason: 'must be an integer or null',
      );
    }
    return _bounded(v, field, location, min, max) as int;
  }

  /// Optional numeric value. `null` means **not prescribed** and is a real,
  /// meaningful answer — distinct from `0`, which is a prescribed zero.
  static double? optionalNum(Map<String, dynamic> m, String field,
      {required String location, num? min, num? max}) {
    final v = m[field];
    if (v == null) return null;
    if (v is! num) {
      throw WorkoutContractViolation(
        field: field, location: location, value: v,
        reason: 'must be a number or null',
      );
    }
    return (_bounded(v, field, location, min, max)).toDouble();
  }

  static String? optionalText(Map<String, dynamic> m, String field) {
    final s = m[field]?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  static num _bounded(num v, String field, String location, num? min, num? max) {
    if (min != null && v < min) {
      throw WorkoutContractViolation(
        field: field, location: location, value: v,
        reason: 'must be at least $min',
      );
    }
    if (max != null && v > max) {
      throw WorkoutContractViolation(
        field: field, location: location, value: v,
        reason: 'must be at most $max',
      );
    }
    return v;
  }
}
