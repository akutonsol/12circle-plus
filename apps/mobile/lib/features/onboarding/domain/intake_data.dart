class IntakeData {
  // ── Profile Info ─────────────────────────────────────────────────────────────
  String firstName;
  String lastName;
  String gender;
  DateTime? dateOfBirth;

  String primaryGoal;
  List<String> activities;
  String activityLevel;
  int trainingDays;
  String trainingLocation;
  String nutritionGoal;
  String proteinConfidence;
  List<String> biggestChallenges;
  bool progressPhotosSkipped;
  int heightCm;
  double weightKg;
  double weightGoalKg;
  String coachingMode;

  // Health Assessment — PAR-Q
  Map<int, bool> parqAnswers;

  // Health Assessment — Medical History
  List<String> medicalConditions;

  // Health Assessment — Injuries
  bool hasInjuries;
  List<String> injuryLocations;
  String injuryDescription;

  // Health Assessment — Experience
  String experienceLevel;
  bool workedWithCoachBefore;

  // Health Assessment — Lifestyle
  String sleepHours;
  int stressLevel;
  String occupation;

  // Health Assessment — Dietary
  List<String> dietaryRestrictions;
  String foodAllergies;

  // Health Assessment — Timeline & Consent
  String targetTimeline;
  bool consentAgreed;

  IntakeData({
    this.firstName = '',
    this.lastName = '',
    this.gender = '',
    this.dateOfBirth,
    this.primaryGoal = '',
    this.activities = const [],
    this.activityLevel = '',
    this.trainingDays = 0,
    this.trainingLocation = '',
    this.nutritionGoal = '',
    this.proteinConfidence = '',
    this.biggestChallenges = const [],
    this.progressPhotosSkipped = false,
    this.heightCm = 0,
    this.weightKg = 0.0,
    this.weightGoalKg = 0.0,
    this.coachingMode = 'self_guided',
    this.parqAnswers = const {},
    this.medicalConditions = const [],
    this.hasInjuries = false,
    this.injuryLocations = const [],
    this.injuryDescription = '',
    this.experienceLevel = '',
    this.workedWithCoachBefore = false,
    this.sleepHours = '',
    this.stressLevel = 0,
    this.occupation = '',
    this.dietaryRestrictions = const [],
    this.foodAllergies = '',
    this.targetTimeline = '',
    this.consentAgreed = false,
  });

  // ── Risk Engine ──────────────────────────────────────────────────────────────

  int get riskScore => parqAnswers.values.where((v) => v).length;

  String get riskLevel {
    // Q1=heart condition, Q2=chest pain during exercise, Q3=chest pain at rest,
    // Q4=fainting/dizziness, Q7=doctor advised no unsupervised exercise
    if ([1, 2, 3, 4, 7].any((q) => parqAnswers[q] == true)) return 'high';
    if (parqAnswers.values.any((v) => v) ||
        medicalConditions.contains('Pregnancy') ||
        medicalConditions.contains('Heart Disease') ||
        medicalConditions.contains('High Blood Pressure')) {
      return 'moderate';
    }
    return 'low';
  }

  List<String> get riskFlags {
    const labels = {
      1: 'heart_condition',
      2: 'chest_pain_exercise',
      3: 'chest_pain_rest',
      4: 'fainting_dizziness',
      5: 'orthopedic_condition',
      6: 'bp_heart_medication',
      7: 'doctor_advised_no_exercise',
      8: 'other_medical_reason',
    };
    return [
      for (final e in labels.entries)
        if (parqAnswers[e.key] == true) e.value,
      if (medicalConditions.contains('Pregnancy')) 'pregnancy',
      if (medicalConditions.contains('Postpartum')) 'postpartum',
      if (hasInjuries && injuryLocations.isNotEmpty) 'active_injuries',
    ];
  }

  // ── Serialisation ────────────────────────────────────────────────────────────

  static List<String> _splitList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    return raw.split(',');
  }

  factory IntakeData.fromSupabase(Map<String, dynamic> d) {
    final parqRaw = d['parq_answers'] as Map<String, dynamic>? ?? {};
    final parqMap = <int, bool>{};
    parqRaw.forEach((k, v) {
      final ki = int.tryParse(k);
      if (ki != null) parqMap[ki] = v as bool? ?? false;
    });

    final dobStr = d['date_of_birth'] as String?;

    return IntakeData(
      firstName: d['first_name'] as String? ?? '',
      lastName: d['last_name'] as String? ?? '',
      gender: d['gender'] as String? ?? '',
      dateOfBirth: dobStr != null ? DateTime.tryParse(dobStr) : null,
      primaryGoal: d['fitness_goal'] as String? ?? '',
      activities: d['activities'] is List
          ? List<String>.from((d['activities'] as List).map((e) => '$e'))
          : _splitList(d['activities'] as String?),
      activityLevel: d['activity_level'] as String? ?? '',
      trainingDays: (d['training_days_per_week'] as num?)?.toInt() ?? 0,
      trainingLocation: d['training_location'] as String? ?? '',
      nutritionGoal: d['nutrition_goal'] as String? ?? '',
      proteinConfidence: d['protein_confidence'] as String? ?? '',
      biggestChallenges: _splitList(d['biggest_challenges'] as String?),
      progressPhotosSkipped: false,
      heightCm: (d['height_cm'] as num?)?.toInt() ?? 0,
      weightKg: (d['weight_kg'] as num?)?.toDouble() ?? 0.0,
      weightGoalKg: (d['weight_goal_kg'] as num?)?.toDouble() ?? 0.0,
      coachingMode: d['coaching_mode'] as String? ?? 'self_guided',
      parqAnswers: parqMap,
      medicalConditions: _splitList(d['medical_conditions'] as String?),
      hasInjuries: d['has_injuries'] as bool? ?? false,
      injuryLocations: _splitList(d['injury_locations'] as String?),
      injuryDescription: d['injury_description'] as String? ?? '',
      experienceLevel: d['experience_level'] as String? ?? '',
      workedWithCoachBefore: d['worked_with_coach_before'] as bool? ?? false,
      sleepHours: d['sleep_hours'] as String? ?? '',
      stressLevel: (d['stress_level'] as num?)?.toInt() ?? 0,
      occupation: d['occupation'] as String? ?? '',
      dietaryRestrictions: d['dietary_restrictions'] is List
          ? List<String>.from((d['dietary_restrictions'] as List).map((e) => '$e'))
          : _splitList(d['dietary_restrictions'] as String?),
      foodAllergies: d['food_allergies'] as String? ?? '',
      targetTimeline: d['target_timeline'] as String? ?? '',
      consentAgreed: d['consent_agreed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toSupabasePartial(int step) {
    final m = <String, dynamic>{'onboarding_step': step};
    if (firstName.isNotEmpty) m['first_name'] = firstName;
    if (lastName.isNotEmpty) m['last_name'] = lastName;
    if (gender.isNotEmpty) m['gender'] = gender;
    if (dateOfBirth != null) m['date_of_birth'] = dateOfBirth!.toIso8601String().split('T')[0];
    if (primaryGoal.isNotEmpty) m['fitness_goal'] = primaryGoal;
    if (activities.isNotEmpty) m['activities'] = activities.toList();
    if (activityLevel.isNotEmpty) m['activity_level'] = activityLevel;
    if (trainingDays > 0) m['training_days_per_week'] = trainingDays;
    if (trainingLocation.isNotEmpty) m['training_location'] = trainingLocation;
    if (nutritionGoal.isNotEmpty) m['nutrition_goal'] = nutritionGoal;
    if (proteinConfidence.isNotEmpty) m['protein_confidence'] = proteinConfidence;
    if (biggestChallenges.isNotEmpty) m['biggest_challenges'] = biggestChallenges.join(',');
    if (heightCm > 0) m['height_cm'] = heightCm;
    if (weightKg > 0) m['weight_kg'] = weightKg;
    if (weightGoalKg > 0) m['weight_goal_kg'] = weightGoalKg;
    if (coachingMode.isNotEmpty) m['coaching_mode'] = coachingMode;

    if (parqAnswers.isNotEmpty) {
      m['parq_answers'] = {for (final e in parqAnswers.entries) '${e.key}': e.value};
      m['risk_score'] = riskScore;
      m['risk_level'] = riskLevel;
      m['risk_flags'] = riskFlags.join(',');
    }
    if (medicalConditions.isNotEmpty) m['medical_conditions'] = medicalConditions.join(',');
    m['has_injuries'] = hasInjuries;
    if (injuryLocations.isNotEmpty) m['injury_locations'] = injuryLocations.join(',');
    if (injuryDescription.isNotEmpty) m['injury_description'] = injuryDescription;
    if (experienceLevel.isNotEmpty) m['experience_level'] = experienceLevel;
    m['worked_with_coach_before'] = workedWithCoachBefore;
    if (sleepHours.isNotEmpty) m['sleep_hours'] = sleepHours;
    if (stressLevel > 0) m['stress_level'] = stressLevel;
    if (occupation.isNotEmpty) m['occupation'] = occupation;
    if (dietaryRestrictions.isNotEmpty) {
      // Live column is text[] — send a real array, not a comma-joined string.
      m['dietary_restrictions'] = dietaryRestrictions.toList();
    }
    if (foodAllergies.isNotEmpty) m['food_allergies'] = foodAllergies;
    if (targetTimeline.isNotEmpty) m['target_timeline'] = targetTimeline;
    if (consentAgreed) {
      m['consent_agreed'] = true;
      m['consent_date'] = DateTime.now().toUtc().toIso8601String();
    }

    return m;
  }

  Map<String, dynamic> toSupabase() => {
    'first_name': firstName,
    'last_name': lastName,
    'gender': gender,
    if (dateOfBirth != null) 'date_of_birth': dateOfBirth!.toIso8601String().split('T')[0],
    'fitness_goal': primaryGoal,
    'activities': activities.toList(),
    'activity_level': activityLevel,
    'training_days_per_week': trainingDays,
    'training_location': trainingLocation,
    'nutrition_goal': nutritionGoal,
    'protein_confidence': proteinConfidence,
    'biggest_challenges': biggestChallenges.join(','),
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'weight_goal_kg': weightGoalKg,
    'coaching_mode': coachingMode,
    'parq_answers': {for (final e in parqAnswers.entries) '${e.key}': e.value},
    'medical_conditions': medicalConditions.join(','),
    'has_injuries': hasInjuries,
    'injury_locations': injuryLocations.join(','),
    'injury_description': injuryDescription,
    'experience_level': experienceLevel,
    'worked_with_coach_before': workedWithCoachBefore,
    'sleep_hours': sleepHours,
    'stress_level': stressLevel,
    'occupation': occupation,
    'dietary_restrictions': dietaryRestrictions.join(','),
    'food_allergies': foodAllergies,
    'target_timeline': targetTimeline,
    'consent_agreed': consentAgreed,
    'consent_date': consentAgreed ? DateTime.now().toUtc().toIso8601String() : null,
    'risk_score': riskScore,
    'risk_level': riskLevel,
    'risk_flags': riskFlags.join(','),
    'onboarding_complete': true,
    'onboarding_step': 0,
  };
}
