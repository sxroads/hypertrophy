import 'package:flutter/material.dart';
import 'package:hypertrophy/services/api_service.dart';
import 'package:hypertrophy/services/auth_service.dart';
import 'package:hypertrophy/services/anonymous_user_service.dart';
import 'package:hypertrophy/services/event_queue_service.dart';
import 'package:hypertrophy/services/sync_service.dart';
import 'package:hypertrophy/services/progression_service.dart';
import 'package:hypertrophy/services/template_service.dart';
import 'package:hypertrophy/widgets/ai_thinking_overlay.dart';
import 'dart:math';
import 'dart:async';

class WorkoutPage extends StatefulWidget {
  const WorkoutPage({super.key});

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final AnonymousUserService _anonymousUserService = AnonymousUserService();
  final EventQueueService _eventQueue = EventQueueService();
  final SyncService _syncService = SyncService();
  final TemplateService _templateService = TemplateService();

  String? _workoutId;
  DateTime? _workoutStartedAt;
  List<Exercise> _exercises = [];
  List<Map<String, dynamic>> _availableExercises = [];
  bool _isLoadingExercises = false;
  int _sequenceNumber = 0;
  bool _isLoading = false;
  String? _error;
  String? _currentUserId;
  String? _deviceId;

  // Timer
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  // Sync status
  int _pendingEventsCount = 0;
  Timer? _syncStatusTimer;

  // Progression suggestions
  final Map<String, ProgressionSuggestion> _suggestions = {};
  bool _hasCheckedTemplate = false;

  @override
  void initState() {
    super.initState();
    _initializeIds();
    _loadExercises();
    _startSyncStatusTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check for template after dependencies are available (only once)
    if (!_hasCheckedTemplate) {
      _hasCheckedTemplate = true;
      _checkForTemplate();
    }
  }

  Future<void> _checkForTemplate() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args.containsKey('template_id')) {
      final templateId = args['template_id'] as String;
      await _loadTemplate(templateId);
    }
  }

  void _startSyncStatusTimer() {
    _syncStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateSyncStatus();
    });
    _updateSyncStatus();
  }

  Future<void> _updateSyncStatus() async {
    final stats = await _eventQueue.getQueueStats();
    if (mounted) {
      setState(() {
        _pendingEventsCount = stats['pending'] ?? 0;
      });
    }
  }

  Future<void> _initializeIds() async {
    _deviceId = await _anonymousUserService.getOrCreateDeviceId();
    _currentUserId = await _authService.getCurrentUserId();
    setState(() {});
  }

  Future<void> _loadExercises() async {
    setState(() => _isLoadingExercises = true);
    try {
      final exercises = await _apiService.getExercises();
      setState(() {
        _availableExercises = exercises;
        _isLoadingExercises = false;
      });
    } catch (e) {
      debugPrint('❌ Failed to load exercises: $e');
      setState(() => _isLoadingExercises = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _syncStatusTimer?.cancel();
    super.dispose();
  }

  void _startWorkout() {
    final workoutId = _generateUuid();
    final startedAt = DateTime.now();
    setState(() {
      _workoutId = workoutId;
      _workoutStartedAt = startedAt;
      _exercises = [];
      _sequenceNumber = 0;
      _error = null;
      _elapsed = Duration.zero;
      _suggestions.clear();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed = DateTime.now().difference(_workoutStartedAt!));
    });
  }

  Future<void> _loadTemplate(String templateId) async {
    try {
      final userId = _currentUserId ?? await _authService.getCurrentUserId();
      final template = await _templateService.getTemplate(
        templateId: templateId,
        userId: userId,
      );
      if (template == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Template not found'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Start workout first
      _startWorkout();

      // Load exercises from template
      final exercises = <Exercise>[];
      for (final templateExercise in template.exercises) {
        final sets = templateExercise.sets.map((templateSet) {
          return WorkoutSet(
            id: _generateUuid(),
            reps: templateSet.targetReps ?? 0,
            weight: templateSet.targetWeight ?? 0.0,
            previousReps: templateSet.targetReps ?? 0,
            previousWeight: templateSet.targetWeight ?? 0.0,
          );
        }).toList();

        if (sets.isEmpty) {
          sets.add(
            WorkoutSet(
              id: _generateUuid(),
              reps: 0,
              weight: 0.0,
              previousReps: 0,
              previousWeight: 0.0,
            ),
          );
        }

        exercises.add(
          Exercise(
            id: templateExercise.exerciseId,
            name: templateExercise.exerciseName,
            sets: sets,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _exercises = exercises;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load template: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveAsTemplate() async {
    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add exercises before saving as template'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save as Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Template Name',
                hintText: 'e.g., Push Day',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'e.g., Chest, Shoulders, Triceps',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      try {
        final exercisesData = _exercises.map((exercise) {
          return {
            'exercise_id': exercise.id,
            'exercise_name': exercise.name,
            'sets': exercise.sets.map((set) {
              return {
                'target_reps': set.reps > 0 ? set.reps : null,
                'target_weight': set.weight > 0 ? set.weight : null,
              };
            }).toList(),
          };
        }).toList();

        final userId = _currentUserId ?? await _authService.getCurrentUserId();
        await _templateService.saveTemplate(
          userId: userId,
          name: nameController.text.trim(),
          description: descriptionController.text.trim().isEmpty
              ? null
              : descriptionController.text.trim(),
          exercises: exercisesData,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Template saved!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save template: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _endWorkout() async {
    if (_workoutId == null) return;

    // Check if any sets are completed
    final hasCompletedSets = _exercises.any(
      (exercise) => exercise.sets.any((set) => set.isCompleted),
    );

    if (!hasCompletedSets) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please complete at least one set before finishing the workout',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final events = <Map<String, dynamic>>[];

      events.add({
        'event_id': _generateUuid(),
        'event_type': 'WorkoutStarted',
        'payload': {
          'workout_id': _workoutId,
          'started_at': _workoutStartedAt!.toIso8601String(),
        },
        'sequence_number': ++_sequenceNumber,
      });

      for (var exercise in _exercises) {
        events.add({
          'event_id': _generateUuid(),
          'event_type': 'ExerciseAdded',
          'payload': {
            'workout_id': _workoutId,
            'exercise_id': exercise.id,
            'exercise_name': exercise.name,
          },
          'sequence_number': ++_sequenceNumber,
        });

        for (var set in exercise.sets.where((s) => s.isCompleted)) {
          events.add({
            'event_id': _generateUuid(),
            'event_type': 'SetCompleted',
            'payload': {
              'workout_id': _workoutId,
              'exercise_id': exercise.id,
              'set_id': set.id,
              'reps': set.reps,
              'weight': set.weight,
              'completed_at': set.completedAt?.toIso8601String(),
            },
            'sequence_number': ++_sequenceNumber,
          });
        }
      }

      events.add({
        'event_id': _generateUuid(),
        'event_type': 'WorkoutEnded',
        'payload': {
          'workout_id': _workoutId,
          'ended_at': DateTime.now().toIso8601String(),
        },
        'sequence_number': ++_sequenceNumber,
      });

      final userId = _currentUserId ?? await _authService.getCurrentUserId();
      final deviceId =
          _deviceId ?? await _anonymousUserService.getOrCreateDeviceId();

      // Queue events instead of syncing directly
      await _eventQueue.queueEvents(
        events: events,
        deviceId: deviceId,
        userId: userId,
      );

      // Try to sync immediately (will queue if offline)
      try {
        final syncResult = await _syncService.syncPendingEvents(
          deviceId: deviceId,
          userId: userId,
        );

        _timer?.cancel();

        if (mounted) {
          Navigator.pop(context);
          if (syncResult.isSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(syncResult.message),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Workout saved locally. ${syncResult.message}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } catch (e) {
        // Events are queued, so workout is saved locally
        _timer?.cancel();

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Workout saved locally. Will sync when online.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }

      // Update sync status
      await _updateSyncStatus();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _addExercise() {
    if (_workoutId == null || _isLoadingExercises) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ExerciseSelectionSheet(
        exercises: _availableExercises,
        onSelect: (exerciseId, name) async {
          // Fetch last sets for this exercise
          List<WorkoutSet> initialSets = [];

          try {
            final userId =
                _currentUserId ?? await _authService.getCurrentUserId();
            final lastSets = await _apiService.getLastSetsForExercise(
              exerciseId: exerciseId,
              userId: userId,
              token: _authService.token,
            );

            if (lastSets.isNotEmpty) {
              // Create sets based on previous workout
              initialSets = lastSets.map((setData) {
                return WorkoutSet(
                  id: _generateUuid(),
                  reps: 0,
                  weight: 0,
                  previousReps: setData['reps'] as int? ?? 0,
                  previousWeight:
                      (setData['weight'] as num?)?.toDouble() ?? 0.0,
                );
              }).toList();
            } else {
              // No previous sets, create one empty set
              initialSets = [
                WorkoutSet(
                  id: _generateUuid(),
                  reps: 0,
                  weight: 0,
                  previousReps: 0,
                  previousWeight: 0.0,
                ),
              ];
            }

            // Calculate progression suggestion
            final suggestion = ProgressionService.calculateSuggestion(
              lastSets: lastSets,
              lastWorkoutDate: lastSets.isNotEmpty
                  ? DateTime.tryParse(
                      lastSets.first['completed_at'] as String? ?? '',
                    )
                  : null,
            );

            if (mounted) {
              setState(() {
                _exercises.add(
                  Exercise(id: exerciseId, name: name, sets: initialSets),
                );
                _suggestions[exerciseId] = suggestion;
              });
            }
          } catch (e) {
            debugPrint('⚠️ Failed to fetch last sets: $e');
            // Use default empty set on error
            initialSets = [
              WorkoutSet(
                id: _generateUuid(),
                reps: 0,
                weight: 0,
                previousReps: 0,
                previousWeight: 0.0,
              ),
            ];

            // No suggestion on error
            if (mounted) {
              setState(() {
                _exercises.add(
                  Exercise(id: exerciseId, name: name, sets: initialSets),
                );
              });
            }
          }
        },
      ),
    );
  }

  void _showExerciseQuestionSheet(int exerciseIndex) {
    if (exerciseIndex >= _exercises.length) return;

    final exercise = _exercises[exerciseIndex];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ExerciseQuestionSheet(
        exerciseId: exercise.id,
        exerciseName: exercise.name,
        apiService: _apiService,
        authService: _authService,
      ),
    );
  }

  void _addSet(int exerciseIndex) {
    setState(() {
      _exercises[exerciseIndex].sets.add(
        WorkoutSet(
          id: _generateUuid(),
          reps: 0,
          weight: 0,
          previousReps: 0,
          previousWeight: 0,
        ),
      );
    });
  }

  void _completeSet(int exerciseIndex, int setIndex) {
    final set = _exercises[exerciseIndex].sets[setIndex];
    if (set.reps > 0 && set.weight > 0) {
      setState(() {
        set.isCompleted = true;
        set.completedAt = DateTime.now();
      });
    }
  }

  void _applySuggestion(int exerciseIndex) {
    if (exerciseIndex >= _exercises.length) return;

    final exercise = _exercises[exerciseIndex];
    final suggestion = _suggestions[exercise.id];

    if (suggestion == null || suggestion.type == 'none') return;

    setState(() {
      // Apply suggestion to first set (or all sets if empty)
      if (exercise.sets.isEmpty) {
        exercise.sets.add(
          WorkoutSet(
            id: _generateUuid(),
            reps: 0,
            weight: 0,
            previousReps: 0,
            previousWeight: 0,
          ),
        );
      }

      final firstSet = exercise.sets.first;
      if (suggestion.type == 'weight' && suggestion.weightDelta != null) {
        final baseWeight = firstSet.previousWeight > 0
            ? firstSet.previousWeight
            : (firstSet.weight > 0 ? firstSet.weight : 0);
        firstSet.weight = baseWeight + suggestion.weightDelta!;
        if (firstSet.reps == 0 && firstSet.previousReps > 0) {
          firstSet.reps = firstSet.previousReps;
        }
      } else if (suggestion.type == 'reps' && suggestion.repDelta != null) {
        final baseReps = firstSet.previousReps > 0
            ? firstSet.previousReps
            : (firstSet.reps > 0 ? firstSet.reps : 0);
        firstSet.reps = baseReps + suggestion.repDelta!;
        if (firstSet.weight == 0 && firstSet.previousWeight > 0) {
          firstSet.weight = firstSet.previousWeight;
        }
      } else if (suggestion.type == 'maintain') {
        if (firstSet.previousWeight > 0) {
          firstSet.weight = firstSet.previousWeight;
        }
        if (firstSet.previousReps > 0) {
          firstSet.reps = firstSet.previousReps;
        }
      }
    });
  }

  String _generateUuid() {
    return '${_randomHex(8)}-${_randomHex(4)}-${_randomHex(4)}-${_randomHex(4)}-${_randomHex(12)}';
  }

  String _randomHex(int length) {
    return List.generate(
      length,
      (_) => Random().nextInt(16).toRadixString(16),
    ).join();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgColor = theme.scaffoldBackgroundColor;
    final cardColor = theme.cardColor;
    final accentColor = colorScheme.primary;

    if (_workoutId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Workout'),
          backgroundColor: colorScheme.inversePrimary,
        ),
        body: Center(
          child: ElevatedButton(
            onPressed: _startWorkout,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Start Workout',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with timer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(20),
                    color: cardColor,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        setState(() => _elapsed = Duration.zero);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatDuration(_elapsed),
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (_pendingEventsCount > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$_pendingEventsCount pending',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _endWorkout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: Colors.green.withOpacity(0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Finish',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.grey, height: 2),

            const SizedBox(height: 16),

            // Exercises list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ..._exercises.asMap().entries.map((entry) {
                    final exerciseIndex = entry.key;
                    final exercise = entry.value;
                    return _buildExerciseCard(
                      exercise,
                      exerciseIndex,
                      accentColor,
                      cardColor,
                      colorScheme,
                    );
                  }),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            backgroundColor: cardColor,
                            foregroundColor: accentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: accentColor),
                            ),
                          ),
                          onPressed: _addExercise,
                          icon: Icon(Icons.add, color: accentColor),
                          label: Text(
                            'Add Exercise',
                            style: TextStyle(color: accentColor, fontSize: 16),
                          ),
                        ),
                      ),
                      if (_authService.isAuthenticated) ...[
                        const SizedBox(width: 8),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            backgroundColor: cardColor,
                            foregroundColor: accentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: accentColor),
                            ),
                          ),
                          onPressed: _saveAsTemplate,
                          icon: Icon(Icons.bookmark, color: accentColor),
                          label: Text(
                            'Save Template',
                            style: TextStyle(color: accentColor, fontSize: 16),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),

            if (_error != null)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseCard(
    Exercise exercise,
    int exerciseIndex,
    Color accentColor,
    Color cardColor,
    ColorScheme colorScheme,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exercise header
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _showExerciseQuestionSheet(exerciseIndex),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.question_mark,
                    color: colorScheme.onPrimary,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          // Progression suggestion
          if (_suggestions.containsKey(exercise.id) &&
              _suggestions[exercise.id]!.type != 'none')
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: accentColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _suggestions[exercise.id]!.type == 'maintain'
                        ? Icons.arrow_forward
                        : Icons.trending_up,
                    color: accentColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _suggestions[exercise.id]!.message,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Table header
          Row(
            children: [
              SizedBox(
                width: 50,
                child: Text(
                  'Set',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Previous',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Center(
                  child: Text(
                    'kg',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Center(
                  child: Text(
                    'Reps',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(
                width: 50,
                child: Center(
                  child: Icon(Icons.check, color: Colors.grey, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Sets
          ...exercise.sets.asMap().entries.map((setEntry) {
            final setIndex = setEntry.key;
            final set = setEntry.value;
            return _AnimatedSetRow(
              key: ValueKey(set.id),
              set: set,
              setIndex: setIndex,
              exerciseIndex: exerciseIndex,
              cardColor: cardColor,
              colorScheme: colorScheme,
              onComplete: () => _completeSet(exerciseIndex, setIndex),
            );
          }),

          // Add set button
          const SizedBox(height: 8),
          Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(8),
            color: cardColor,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _addSet(exerciseIndex),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    '+ Add Set ',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedSetRow extends StatefulWidget {
  final WorkoutSet set;
  final int setIndex;
  final int exerciseIndex;
  final Color cardColor;
  final ColorScheme colorScheme;
  final VoidCallback onComplete;

  const _AnimatedSetRow({
    required Key key,
    required this.set,
    required this.setIndex,
    required this.exerciseIndex,
    required this.cardColor,
    required this.colorScheme,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<_AnimatedSetRow> createState() => _AnimatedSetRowState();
}

class _AnimatedSetRowState extends State<_AnimatedSetRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-0.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              // Set number
              Material(
                elevation: 1,
                borderRadius: BorderRadius.circular(8),
                color: widget.cardColor,
                child: Container(
                  width: 40,
                  height: 36,
                  child: Center(
                    child: Text(
                      '${widget.setIndex + 1}',
                      style: TextStyle(
                        color: widget.colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Previous
              Expanded(
                child: Text(
                  '${widget.set.previousWeight.toInt()} kg × ${widget.set.previousReps}',
                  style: TextStyle(
                    color: widget.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),

              // Weight input
              Material(
                elevation: 1,
                borderRadius: BorderRadius.circular(8),
                color: widget.cardColor,
                child: Container(
                  width: 60,
                  height: 36,
                  margin: const EdgeInsets.only(right: 8),
                  child: TextField(
                    textAlign: TextAlign.center,
                    style: TextStyle(color: widget.colorScheme.onSurface),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '${widget.set.previousWeight.toInt()}',
                      hintStyle: TextStyle(
                        color: widget.colorScheme.onSurface.withOpacity(0.4),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) {
                      widget.set.weight = double.tryParse(v) ?? 0;
                    },
                  ),
                ),
              ),

              // Reps input
              Material(
                elevation: 1,
                borderRadius: BorderRadius.circular(8),
                color: widget.cardColor,
                child: Container(
                  width: 60,
                  height: 36,
                  margin: const EdgeInsets.only(right: 8),
                  child: TextField(
                    textAlign: TextAlign.center,
                    style: TextStyle(color: widget.colorScheme.onSurface),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '${widget.set.previousReps}',
                      hintStyle: TextStyle(
                        color: widget.colorScheme.onSurface.withOpacity(0.4),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) {
                      widget.set.reps = int.tryParse(v) ?? 0;
                    },
                  ),
                ),
              ),

              // Check button
              Material(
                elevation: widget.set.isCompleted ? 3 : 1,
                borderRadius: BorderRadius.circular(8),
                color: widget.set.isCompleted ? Colors.green : widget.cardColor,
                shadowColor: widget.set.isCompleted
                    ? Colors.green.withOpacity(0.4)
                    : null,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onComplete,
                  child: Container(
                    width: 40,
                    height: 36,

                    child: Icon(
                      Icons.check,
                      color: widget.set.isCompleted
                          ? Colors.white
                          : Colors.green,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Exercise {
  final String id;
  final String name;
  final List<WorkoutSet> sets;

  Exercise({required this.id, required this.name, required this.sets});
}

class WorkoutSet {
  final String id;
  int reps;
  double weight;
  final int previousReps;
  final double previousWeight;
  bool isCompleted;
  DateTime? completedAt;

  WorkoutSet({
    required this.id,
    required this.reps,
    required this.weight,
    this.previousReps = 0,
    this.previousWeight = 0,
    this.isCompleted = false,
    this.completedAt,
  });
}

class _ExerciseSelectionSheet extends StatefulWidget {
  final List<Map<String, dynamic>> exercises;
  final Function(String, String) onSelect;

  const _ExerciseSelectionSheet({
    required this.exercises,
    required this.onSelect,
  });

  @override
  State<_ExerciseSelectionSheet> createState() =>
      _ExerciseSelectionSheetState();
}

class _ExerciseSelectionSheetState extends State<_ExerciseSelectionSheet> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, List<Map<String, dynamic>>> _groupExercises() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final query = _searchQuery.toLowerCase();

    for (var exercise in widget.exercises) {
      final name = exercise['name'] as String;
      final category = exercise['muscle_category'] as String;

      if (query.isEmpty ||
          name.toLowerCase().contains(query) ||
          category.toLowerCase().contains(query)) {
        grouped.putIfAbsent(category, () => []);
        grouped[category]!.add(exercise);
      }
    }

    grouped.forEach((key, value) {
      value.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );
    });

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupExercises();
    final categories = grouped.keys.toList()..sort();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = colorScheme.primary;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            'Select Exercise',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            style: TextStyle(color: colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Search exercises...',
              hintStyle: TextStyle(color: Colors.grey[600]),
              prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
              filled: true,
              fillColor: theme.cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final category = categories[i];
                final exercises = grouped[category]!;

                return Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(
                      category.toUpperCase(),
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    iconColor: accentColor,
                    collapsedIconColor: Colors.grey,
                    children: exercises.map((e) {
                      return ListTile(
                        title: Text(
                          e['name'] as String,
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                        onTap: () {
                          widget.onSelect(
                            e['exercise_id'] as String,
                            e['name'] as String,
                          );
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseQuestionSheet extends StatefulWidget {
  final String exerciseId;
  final String exerciseName;
  final ApiService apiService;
  final AuthService authService;

  const _ExerciseQuestionSheet({
    required this.exerciseId,
    required this.exerciseName,
    required this.apiService,
    required this.authService,
  });

  @override
  State<_ExerciseQuestionSheet> createState() => _ExerciseQuestionSheetState();
}

class _ExerciseQuestionSheetState extends State<_ExerciseQuestionSheet> {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  String? _error;
  String? _aiResponse;

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty || widget.authService.token == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _aiResponse = null;
    });

    try {
      final response = await widget.apiService.workoutExerciseChat(
        exerciseId: widget.exerciseId,
        exerciseName: widget.exerciseName,
        question: question,
        token: widget.authService.token!,
      );

      setState(() {
        _aiResponse = response['answer'] as String;
        _isLoading = false;
        _questionController.clear();
      });

      // Scroll to bottom to show response
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = colorScheme.primary;

    return Stack(
      children: [
        Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Ask about ${widget.exerciseName}',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Get real-time advice about this exercise',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_aiResponse != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: accentColor.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _aiResponse!,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_error != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _questionController,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Ask a question...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        filled: true,
                        fillColor: theme.cardColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendQuestion(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isLoading ? null : _sendQuestion,
                    icon: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                accentColor,
                              ),
                            ),
                          )
                        : Icon(Icons.send, color: accentColor),
                    style: IconButton.styleFrom(
                      backgroundColor: accentColor.withOpacity(0.1),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        AiThinkingOverlay(
          isVisible: _isLoading,
          message: 'Getting AI advice...',
        ),
      ],
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  final Color color;

  const _ThinkingDots({required this.color});

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final dots = <Widget>[];
        for (int i = 0; i < 3; i++) {
          final delay = i * 0.2;
          final value = (_controller.value + delay) % 1.0;
          final opacity = (value < 0.5) ? value * 2 : 2 - (value * 2);

          dots.add(
            Opacity(
              opacity: opacity,
              child: Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }
        return Row(mainAxisSize: MainAxisSize.min, children: dots);
      },
    );
  }
}
