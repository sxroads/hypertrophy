import 'package:flutter/material.dart';
import 'package:hypertrophy/services/api_service.dart';
import 'package:hypertrophy/services/auth_service.dart';
import 'package:intl/intl.dart';

class WorkoutDetailPage extends StatefulWidget {
  final String workoutId;
  final Map<String, dynamic> workout;

  const WorkoutDetailPage({
    super.key,
    required this.workoutId,
    required this.workout,
  });

  @override
  State<WorkoutDetailPage> createState() => _WorkoutDetailPageState();
}

class _WorkoutDetailPageState extends State<WorkoutDetailPage> {
  final _apiService = ApiService();
  final _authService = AuthService();
  List<Map<String, dynamic>> _sets = [];
  Map<String, String> _exerciseNames = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWorkoutDetails();
  }

  Future<void> _loadWorkoutDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch sets for this workout
      final sets = await _apiService.getWorkoutSets(
        workoutId: widget.workoutId,
        token: _authService.token,
      );

      // Use exercises from workout object if available (from new API)
      final exerciseMap = <String, String>{};
      if (widget.workout.containsKey('exercises') &&
          widget.workout['exercises'] != null) {
        final exercises = widget.workout['exercises'] as List;
        for (final exercise in exercises) {
          final exerciseId = exercise['exercise_id'] as String;
          final exerciseName = exercise['name'] as String;
          exerciseMap[exerciseId] = exerciseName;
        }
      } else {
        // Fallback: fetch exercise names if not in workout object
        final exerciseIds = <String>{};
        for (final set in sets) {
          exerciseIds.add(set['exercise_id'] as String);
        }

        final exercises = await _apiService.getExercises();
        for (final exercise in exercises) {
          final exerciseId = exercise['exercise_id'] as String;
          if (exerciseIds.contains(exerciseId)) {
            exerciseMap[exerciseId] = exercise['name'] as String;
          }
        }
      }

      setState(() {
        _sets = sets;
        _exerciseNames = exerciseMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  String _getExerciseName(String exerciseId) {
    return _exerciseNames[exerciseId] ?? 'Unknown Exercise';
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy • HH:mm').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatTime(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('HH:mm:ss').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatDuration(DateTime? start, DateTime? end) {
    if (start == null || end == null) {
      return 'N/A';
    }
    final duration = end.difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  Map<String, List<Map<String, dynamic>>> _groupSetsByExercise() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final set in _sets) {
      final exerciseId = set['exercise_id'] as String;
      if (!grouped.containsKey(exerciseId)) {
        grouped[exerciseId] = [];
      }
      grouped[exerciseId]!.add(set);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = widget.workout['status'] as String;
    final isCompleted = status == 'completed';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Details'),
        backgroundColor: colorScheme.inversePrimary,
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
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadWorkoutDetails,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadWorkoutDetails,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Workout info card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isCompleted
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: isCompleted
                                      ? Colors.green
                                      : Colors.orange,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isCompleted ? 'Completed' : 'In Progress',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isCompleted
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _InfoRow(
                              icon: Icons.calendar_today,
                              label: 'Started',
                              value: _formatDate(
                                widget.workout['started_at'] as String,
                              ),
                            ),
                            if (widget.workout['ended_at'] != null) ...[
                              const SizedBox(height: 8),
                              _InfoRow(
                                icon: Icons.check_circle_outline,
                                label: 'Ended',
                                value: _formatDate(
                                  widget.workout['ended_at'] as String,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _InfoRow(
                                icon: Icons.timer,
                                label: 'Duration',
                                value: _formatDuration(
                                  DateTime.parse(
                                    widget.workout['started_at'] as String,
                                  ),
                                  DateTime.parse(
                                    widget.workout['ended_at'] as String,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    icon: Icons.fitness_center,
                                    label: 'Sets',
                                    value: '${_sets.length}',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatCard(
                                    icon: Icons.scale,
                                    label: 'Volume',
                                    value:
                                        '${_calculateTotalVolume().toStringAsFixed(1)} kg',
                                  ),
                                ),
                                if (widget.workout.containsKey('exercises') &&
                                    widget.workout['exercises'] != null) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _StatCard(
                                      icon: Icons.sports_gymnastics,
                                      label: 'Exercises',
                                      value:
                                          '${(widget.workout['exercises'] as List).length}',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Exercises section
                    Text(
                      'Exercises',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_sets.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.fitness_center,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No sets recorded',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._buildExerciseCards(),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _buildExerciseCards() {
    final grouped = _groupSetsByExercise();
    final cards = <Widget>[];

    for (final entry in grouped.entries) {
      final exerciseId = entry.key;
      final sets = entry.value;
      final exerciseName = _getExerciseName(exerciseId);

      cards.add(
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exerciseName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                // Sets table
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1),
                    3: FlexColumnWidth(1.5),
                  },
                  children: [
                    // Header
                    TableRow(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                      ),
                      children: const [
                        _TableHeaderCell('Set'),
                        _TableHeaderCell('Reps'),
                        _TableHeaderCell('Weight'),
                        _TableHeaderCell('Time'),
                      ],
                    ),
                    // Data rows
                    ...sets.asMap().entries.map((entry) {
                      final index = entry.key;
                      final set = entry.value;
                      final isLast = index == sets.length - 1;
                      return TableRow(
                        decoration: BoxDecoration(
                          border: isLast
                              ? null
                              : Border(
                                  bottom: BorderSide(
                                    color: Colors.grey[300]!,
                                    width: 1,
                                  ),
                                ),
                        ),
                        children: [
                          _TableCell('${index + 1}'),
                          _TableCell('${set['reps'] ?? 0}'),
                          _TableCell(
                            '${(set['weight'] ?? 0.0).toStringAsFixed(1)} kg',
                          ),
                          _TableCell(
                            _formatTime(set['completed_at'] as String),
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return cards;
  }

  double _calculateTotalVolume() {
    double total = 0.0;
    for (final set in _sets) {
      final reps = set['reps'] as int? ?? 0;
      final weight = set['weight'] as double? ?? 0.0;
      total += reps * weight;
    }
    return total;
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: Colors.grey[700]),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  final String text;

  const _TableHeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;

  const _TableCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(text),
    );
  }
}
