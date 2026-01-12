import 'package:flutter/material.dart';
import 'package:hypertrophy/services/api_service.dart';
import 'package:hypertrophy/services/auth_service.dart';
import 'package:intl/intl.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  final _apiService = ApiService();
  final _authService = AuthService();

  Map<String, String> _exerciseNames = {};
  Map<String, ExerciseRecord> _records = {};
  bool _isLoading = true;
  String? _error;
  String _sortBy = 'name'; // 'name', 'maxWeight', 'maxVolume'

  @override
  void initState() {
    super.initState();
    _authService.addListener(_onAuthChange);
    _loadRecords();
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() {
    if (_authService.isAuthenticated) {
      _loadRecords();
    }
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = await _authService.getCurrentUserId();

      // Fetch all workouts
      final workouts = await _apiService.getWorkoutHistory(
        userId: userId,
        token: _authService.token,
      );

      // Only process completed workouts
      final completedWorkouts = workouts
          .where((w) => w['status'] == 'completed')
          .toList();

      // Fetch all sets for completed workouts in one batch query (fixes N+1)
      final allSets = <Map<String, dynamic>>[];
      if (completedWorkouts.isNotEmpty) {
        try {
          final workoutIds = completedWorkouts
              .map((w) => w['workout_id'] as String)
              .toList();
          final sets = await _apiService.getWorkoutSetsBatch(
            workoutIds: workoutIds,
            userId: userId,
            token: _authService.token,
          );

          // Create a map of workout_id to started_at for quick lookup
          final workoutDateMap = <String, String>{};
          for (final workout in completedWorkouts) {
            workoutDateMap[workout['workout_id'] as String] =
                workout['started_at'] as String;
          }

          // Add workout date to each set for PR tracking
          for (final set in sets) {
            final workoutId = set['workout_id'] as String?;
            if (workoutId != null && workoutDateMap.containsKey(workoutId)) {
              set['workout_date'] = workoutDateMap[workoutId];
            }
          }
          allSets.addAll(sets);
        } catch (e) {
          debugPrint('Error loading sets batch: $e');
        }
      }

      // Get all unique exercise IDs
      final exerciseIds = <String>{};
      for (final set in allSets) {
        exerciseIds.add(set['exercise_id'] as String);
      }

      // Fetch exercise names
      final exercises = await _apiService.getExercises();
      final exerciseMap = <String, String>{};
      for (final exercise in exercises) {
        final exerciseId = exercise['exercise_id'] as String;
        if (exerciseIds.contains(exerciseId)) {
          exerciseMap[exerciseId] = exercise['name'] as String;
        }
      }

      // Calculate records for each exercise
      final records = <String, ExerciseRecord>{};
      for (final exerciseId in exerciseIds) {
        final exerciseSets = allSets
            .where((s) => s['exercise_id'] == exerciseId)
            .toList();

        if (exerciseSets.isEmpty) continue;

        double? maxWeight;
        int? maxReps;
        double? maxVolume;
        DateTime? maxWeightDate;
        DateTime? maxRepsDate;
        DateTime? maxVolumeDate;
        Map<String, dynamic>? maxWeightSet;
        Map<String, dynamic>? maxRepsSet;
        Map<String, dynamic>? maxVolumeSet;

        for (final set in exerciseSets) {
          final weight = (set['weight'] as num?)?.toDouble();
          final reps = set['reps'] as int?;
          final dateStr = set['workout_date'] as String?;

          if (weight == null || reps == null || dateStr == null) continue;

          final date = DateTime.parse(dateStr);
          final volume = weight * reps;

          // Track max weight
          if (maxWeight == null || weight > maxWeight) {
            maxWeight = weight;
            maxWeightDate = date;
            maxWeightSet = set;
          }

          // Track max reps at any weight
          if (maxReps == null || reps > maxReps) {
            maxReps = reps;
            maxRepsDate = date;
            maxRepsSet = set;
          }

          // Track max volume
          if (maxVolume == null || volume > maxVolume) {
            maxVolume = volume;
            maxVolumeDate = date;
            maxVolumeSet = set;
          }
        }

        if (maxWeight != null || maxReps != null || maxVolume != null) {
          records[exerciseId] = ExerciseRecord(
            exerciseId: exerciseId,
            maxWeight: maxWeight,
            maxReps: maxReps,
            maxVolume: maxVolume,
            maxWeightDate: maxWeightDate,
            maxRepsDate: maxRepsDate,
            maxVolumeDate: maxVolumeDate,
            maxWeightSet: maxWeightSet,
            maxRepsSet: maxRepsSet,
            maxVolumeSet: maxVolumeSet,
          );
        }
      }

      setState(() {
        _exerciseNames = exerciseMap;
        _records = records;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return DateFormat('MMM dd, yyyy').format(date);
  }

  List<MapEntry<String, ExerciseRecord>> _getSortedRecords() {
    final entries = _records.entries.toList();

    switch (_sortBy) {
      case 'maxWeight':
        entries.sort((a, b) {
          final aWeight = a.value.maxWeight ?? 0.0;
          final bWeight = b.value.maxWeight ?? 0.0;
          return bWeight.compareTo(aWeight);
        });
        break;
      case 'maxVolume':
        entries.sort((a, b) {
          final aVolume = a.value.maxVolume ?? 0.0;
          final bVolume = b.value.maxVolume ?? 0.0;
          return bVolume.compareTo(aVolume);
        });
        break;
      case 'name':
      default:
        entries.sort((a, b) {
          final aName = _exerciseNames[a.key] ?? '';
          final bName = _exerciseNames[b.key] ?? '';
          return aName.compareTo(bName);
        });
        break;
    }

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Records'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() {
                _sortBy = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(Icons.sort_by_alpha, size: 20),
                    SizedBox(width: 8),
                    Text('Sort by Name'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'maxWeight',
                child: Row(
                  children: [
                    Icon(Icons.fitness_center, size: 20),
                    SizedBox(width: 8),
                    Text('Sort by Max Weight'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'maxVolume',
                child: Row(
                  children: [
                    Icon(Icons.trending_up, size: 20),
                    SizedBox(width: 8),
                    Text('Sort by Max Volume'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecords,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadRecords,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _records.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emoji_events, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No records yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete workouts to see your best lifts',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadRecords,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _getSortedRecords().length,
                itemBuilder: (context, index) {
                  final entry = _getSortedRecords()[index];
                  final exerciseId = entry.key;
                  final record = entry.value;
                  final exerciseName =
                      _exerciseNames[exerciseId] ?? 'Unknown Exercise';

                  return _RecordCard(
                    exerciseName: exerciseName,
                    record: record,
                    formatDate: _formatDate,
                  );
                },
              ),
            ),
    );
  }
}

class ExerciseRecord {
  final String exerciseId;
  final double? maxWeight;
  final int? maxReps;
  final double? maxVolume;
  final DateTime? maxWeightDate;
  final DateTime? maxRepsDate;
  final DateTime? maxVolumeDate;
  final Map<String, dynamic>? maxWeightSet;
  final Map<String, dynamic>? maxRepsSet;
  final Map<String, dynamic>? maxVolumeSet;

  ExerciseRecord({
    required this.exerciseId,
    this.maxWeight,
    this.maxReps,
    this.maxVolume,
    this.maxWeightDate,
    this.maxRepsDate,
    this.maxVolumeDate,
    this.maxWeightSet,
    this.maxRepsSet,
    this.maxVolumeSet,
  });
}

class _RecordCard extends StatelessWidget {
  final String exerciseName;
  final ExerciseRecord record;
  final String Function(DateTime?) formatDate;

  const _RecordCard({
    required this.exerciseName,
    required this.record,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exercise name
            Row(
              children: [
                Icon(Icons.emoji_events, color: colorScheme.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exerciseName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Records
            if (record.maxWeight != null)
              _RecordItem(
                icon: Icons.fitness_center,
                label: 'Max Weight',
                value: '${record.maxWeight!.toStringAsFixed(1)} kg',
                date: formatDate(record.maxWeightDate),
                color: Colors.blue,
              ),
            if (record.maxReps != null && record.maxRepsSet != null)
              _RecordItem(
                icon: Icons.repeat,
                label: 'Max Reps',
                value:
                    '${record.maxReps} reps @ ${(record.maxRepsSet!['weight'] as num?)?.toStringAsFixed(1) ?? '0'} kg',
                date: formatDate(record.maxRepsDate),
                color: Colors.green,
              ),
            if (record.maxVolume != null)
              _RecordItem(
                icon: Icons.trending_up,
                label: 'Max Volume',
                value: '${record.maxVolume!.toStringAsFixed(1)} kg',
                date: formatDate(record.maxVolumeDate),
                color: Colors.orange,
              ),
          ],
        ),
      ),
    );
  }
}

class _RecordItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String date;
  final Color color;

  const _RecordItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.date,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
