class WorkoutLog {
  final String? id;
  final String workoutId;
  final String workoutTitle;
  final String? userId;
  final int? durationMinutes;
  final int? durationSeconds;
  final int? caloriesBurned;
  final String? category;
  final String? notes;

  WorkoutLog({
    this.id,
    required this.workoutId,
    required this.workoutTitle,
    this.userId,
    this.durationMinutes,
    this.durationSeconds,
    this.caloriesBurned,
    this.category,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    'workout_id': workoutId,
    'workout_title': workoutTitle,
    'duration_minutes': durationMinutes,
    'calories_burned': caloriesBurned,
    'category': category,
    'notes': notes,
    'completed_at': DateTime.now().toUtc().toIso8601String(),
  };
}

class LoggedSet {
  final int setNumber;
  final int reps;
  final double weight;
  final double? rpe;
  final String? notes;
  final DateTime completedAt;

  LoggedSet({
    required this.setNumber,
    required this.reps,
    required this.weight,
    this.rpe,
    this.notes,
    required this.completedAt,
  });
}

class LoggedExercise {
  final String exerciseId;
  final String exerciseName;
  final List<LoggedSet> sets;

  LoggedExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.sets,
  });
}
