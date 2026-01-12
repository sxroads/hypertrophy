import 'dart:math';

class ProgressionSuggestion {
  final String type; // 'weight', 'reps', 'maintain'
  final double? weightDelta; // e.g., 2.5
  final int? repDelta; // e.g., 1
  final String message; // "Try +2.5kg" or "Add 1 rep"

  ProgressionSuggestion({
    required this.type,
    this.weightDelta,
    this.repDelta,
    required this.message,
  });

  static ProgressionSuggestion none() {
    return ProgressionSuggestion(
      type: 'none',
      message: 'No suggestion available',
    );
  }
}
//TODO: Add more sophisticated progression suggestion logic with ai

class ProgressionService {
  /// Calculate progression suggestion based on last workout sets
  ///
  /// Logic:
  /// - If they did 12 or more reps → suggest to increase weight
  /// - If they did less than 3 reps → suggest to decrease weight
  /// - Otherwise → suggest to add a rep with the same weight
  static ProgressionSuggestion calculateSuggestion({
    required List<Map<String, dynamic>> lastSets,
    DateTime? lastWorkoutDate,
  }) {
    if (lastSets.isEmpty) {
      return ProgressionSuggestion.none();
    }

    // Extract weights and reps from last sets
    final weights = lastSets
        .map((s) => (s['weight'] as num?)?.toDouble() ?? 0.0)
        .where((w) => w > 0)
        .toList();
    final reps = lastSets
        .map((s) => (s['reps'] as int?) ?? 0)
        .where((r) => r > 0)
        .toList();

    if (weights.isEmpty || reps.isEmpty) {
      return ProgressionSuggestion.none();
    }

    final maxWeight = weights.reduce(max);
    final maxReps = reps.reduce(max);

    // If they did 12 or more reps → suggest to increase weight
    if (maxReps >= 12) {
      return ProgressionSuggestion(
        type: 'weight',
        weightDelta: 2.5,
        message: 'Try upping your weight you got 12 or more reps last time',
      );
    }

    // If they did less than 3 reps → suggest to decrease weight
    if (maxReps < 3) {
      return ProgressionSuggestion(
        type: 'weight',
        weightDelta: -2.5,
        message: 'Try lowering your weight you did less than 3 reps last time',
      );
    }

    // Otherwise → suggest to add a rep with the same weight
    return ProgressionSuggestion(
      type: 'reps',
      repDelta: 1,
      message:
          'Try +1 rep (${maxWeight.toStringAsFixed(1)}kg × ${maxReps + 1})',
    );
  }
}
