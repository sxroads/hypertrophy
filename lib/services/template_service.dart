import 'package:hypertrophy/services/database/templates_db.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class WorkoutTemplate {
  final String templateId;
  final String name;
  final String? description;
  final int createdAt;
  final int? lastUsedAt;
  List<TemplateExercise> exercises = [];

  WorkoutTemplate({
    required this.templateId,
    required this.name,
    this.description,
    required this.createdAt,
    this.lastUsedAt,
    required this.exercises,
  });

  Map<String, dynamic> toMap() {
    return {
      'template_id': templateId,
      'name': name,
      'description': description,
      'created_at': createdAt,
      'last_used_at': lastUsedAt,
    };
  }

  factory WorkoutTemplate.fromMap(Map<String, dynamic> map) {
    return WorkoutTemplate(
      templateId: map['template_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      createdAt: map['created_at'] as int,
      lastUsedAt: map['last_used_at'] as int?,
      exercises: [],
    );
  }
}

class TemplateExercise {
  final int? id;
  final String templateId;
  final String exerciseId;
  final String exerciseName;
  final int orderIndex;
  List<TemplateSet> sets = [];

  TemplateExercise({
    this.id,
    required this.templateId,
    required this.exerciseId,
    required this.exerciseName,
    required this.orderIndex,
    required this.sets,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'template_id': templateId,
      'exercise_id': exerciseId,
      'exercise_name': exerciseName,
      'order_index': orderIndex,
    };
  }

  factory TemplateExercise.fromMap(Map<String, dynamic> map) {
    return TemplateExercise(
      id: map['id'] as int?,
      templateId: map['template_id'] as String,
      exerciseId: map['exercise_id'] as String,
      exerciseName: map['exercise_name'] as String,
      orderIndex: map['order_index'] as int,
      sets: [],
    );
  }
}

class TemplateSet {
  final int? id;
  final int templateExerciseId;
  final int? targetReps;
  final double? targetWeight;
  final int orderIndex;

  TemplateSet({
    this.id,
    required this.templateExerciseId,
    this.targetReps,
    this.targetWeight,
    required this.orderIndex,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'template_exercise_id': templateExerciseId,
      'target_reps': targetReps,
      'target_weight': targetWeight,
      'order_index': orderIndex,
    };
  }

  factory TemplateSet.fromMap(Map<String, dynamic> map) {
    return TemplateSet(
      id: map['id'] as int?,
      templateExerciseId: map['template_exercise_id'] as int,
      targetReps: map['target_reps'] as int?,
      targetWeight: (map['target_weight'] as num?)?.toDouble(),
      orderIndex: map['order_index'] as int,
    );
  }
}

class TemplateService {
  static final TemplateService _instance = TemplateService._internal();
  factory TemplateService() => _instance;
  TemplateService._internal();

  /// Save a template from current workout exercises
  Future<String> saveTemplate({
    required String userId,
    required String name,
    String? description,
    required List<Map<String, dynamic>> exercises,
  }) async {
    final db = await TemplatesDb.database;
    final templateId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Insert template
      await txn.insert('workout_templates', {
        'template_id': templateId,
        'user_id': userId,
        'name': name,
        'description': description,
        'created_at': now,
      });

      // Insert exercises and sets
      for (
        int exerciseIndex = 0;
        exerciseIndex < exercises.length;
        exerciseIndex++
      ) {
        final exercise = exercises[exerciseIndex];
        final exerciseId = exercise['exercise_id'] as String;
        final exerciseName = exercise['exercise_name'] as String;
        final sets = exercise['sets'] as List<Map<String, dynamic>>;

        // Insert exercise
        final exerciseDbId = await txn.insert('template_exercises', {
          'template_id': templateId,
          'exercise_id': exerciseId,
          'exercise_name': exerciseName,
          'order_index': exerciseIndex,
        });

        // Insert sets
        for (int setIndex = 0; setIndex < sets.length; setIndex++) {
          final set = sets[setIndex];
          await txn.insert('template_sets', {
            'template_exercise_id': exerciseDbId,
            'target_reps': set['target_reps'] as int?,
            'target_weight': set['target_weight'] as double?,
            'order_index': setIndex,
          });
        }
      }
    });

    return templateId;
  }

  /// Get all templates for a specific user
  Future<List<WorkoutTemplate>> getAllTemplates({
    required String userId,
  }) async {
    final db = await TemplatesDb.database;
    final templates = await db.query(
      'workout_templates',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'last_used_at DESC, created_at DESC',
    );

    if (templates.isEmpty) return [];

    // Batch query all exercises for all templates (fixes N+1)
    final templateIds = templates.map((t) => t['template_id'] as String).toList();
    final placeholders = templateIds.map((_) => '?').join(',');
    final allExerciseMaps = await db.rawQuery(
      'SELECT * FROM template_exercises WHERE template_id IN ($placeholders) ORDER BY template_id, order_index ASC',
      templateIds,
    );

    // Group exercises by template_id
    final exercisesByTemplate = <String, List<Map<String, dynamic>>>{};
    for (final exerciseMap in allExerciseMaps) {
      final templateId = exerciseMap['template_id'] as String;
      if (!exercisesByTemplate.containsKey(templateId)) {
        exercisesByTemplate[templateId] = [];
      }
      exercisesByTemplate[templateId]!.add(exerciseMap);
    }

    // Batch query all sets for all exercises (fixes nested N+1)
    final exerciseIds = allExerciseMaps
        .where((e) => e['id'] != null)
        .map((e) => e['id'] as int)
        .toList();
    final setsByExercise = <int, List<Map<String, dynamic>>>{};
    if (exerciseIds.isNotEmpty) {
      final setPlaceholders = exerciseIds.map((_) => '?').join(',');
      final allSetMaps = await db.rawQuery(
        'SELECT * FROM template_sets WHERE template_exercise_id IN ($setPlaceholders) ORDER BY template_exercise_id, order_index ASC',
        exerciseIds,
      );

      for (final setMap in allSetMaps) {
        final exerciseId = setMap['template_exercise_id'] as int;
        if (!setsByExercise.containsKey(exerciseId)) {
          setsByExercise[exerciseId] = [];
        }
        setsByExercise[exerciseId]!.add(setMap);
      }
    }

    // Build result templates
    final result = <WorkoutTemplate>[];
    for (final templateMap in templates) {
      final template = WorkoutTemplate.fromMap(templateMap);
      final templateId = template.templateId;

      final exercises = <TemplateExercise>[];
      final templateExercises = exercisesByTemplate[templateId] ?? [];
      for (final exerciseMap in templateExercises) {
        final exercise = TemplateExercise.fromMap(exerciseMap);
        final exerciseSets = setsByExercise[exercise.id] ?? [];
        exercise.sets.addAll(exerciseSets.map((map) => TemplateSet.fromMap(map)));
        exercises.add(exercise);
      }

      result.add(
        WorkoutTemplate(
          templateId: template.templateId,
          name: template.name,
          description: template.description,
          createdAt: template.createdAt,
          lastUsedAt: template.lastUsedAt,
          exercises: exercises,
        ),
      );
    }

    return result;
  }

  /// Get a template with all exercises and sets (scoped to user)
  Future<WorkoutTemplate?> getTemplate({
    required String templateId,
    required String userId,
  }) async {
    final db = await TemplatesDb.database;

    // Get template (only if it belongs to the user)
    final templateMaps = await db.query(
      'workout_templates',
      where: 'template_id = ? AND user_id = ?',
      whereArgs: [templateId, userId],
      limit: 1,
    );

    if (templateMaps.isEmpty) return null;

    final template = WorkoutTemplate.fromMap(templateMaps.first);

    // Get exercises
    final exerciseMaps = await db.query(
      'template_exercises',
      where: 'template_id = ?',
      whereArgs: [templateId],
      orderBy: 'order_index ASC',
    );

    final exercises = <TemplateExercise>[];
    for (final exerciseMap in exerciseMaps) {
      final exercise = TemplateExercise.fromMap(exerciseMap);

      // Get sets for this exercise
      final setMaps = await db.query(
        'template_sets',
        where: 'template_exercise_id = ?',
        whereArgs: [exercise.id],
        orderBy: 'order_index ASC',
      );

      exercise.sets.addAll(setMaps.map((map) => TemplateSet.fromMap(map)));
      exercises.add(exercise);
    }

    final result = WorkoutTemplate(
      templateId: template.templateId,
      name: template.name,
      description: template.description,
      createdAt: template.createdAt,
      lastUsedAt: template.lastUsedAt,
      exercises: exercises,
    );
    return result;
  }

  /// Delete a template (scoped to user)
  Future<void> deleteTemplate({
    required String templateId,
    required String userId,
  }) async {
    final db = await TemplatesDb.database;
    await db.delete(
      'workout_templates',
      where: 'template_id = ? AND user_id = ?',
      whereArgs: [templateId, userId],
    );
  }

  /// Update last used timestamp (scoped to user)
  Future<void> updateLastUsed({
    required String templateId,
    required String userId,
  }) async {
    final db = await TemplatesDb.database;
    await db.update(
      'workout_templates',
      {'last_used_at': DateTime.now().millisecondsSinceEpoch},
      where: 'template_id = ? AND user_id = ?',
      whereArgs: [templateId, userId],
    );
  }
}
