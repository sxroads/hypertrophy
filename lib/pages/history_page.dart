import 'package:flutter/material.dart';
import 'package:hypertrophy/services/api_service.dart';
import 'package:hypertrophy/services/auth_service.dart';
import 'package:hypertrophy/pages/workout_detail_page.dart';
import 'package:hypertrophy/widgets/ai_thinking_overlay.dart';
import 'package:intl/intl.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _apiService = ApiService();
  final _authService = AuthService();
  List<Map<String, dynamic>> _workouts = [];
  bool _isLoading = true;
  String? _error;

  // AI Report state
  bool _isGeneratingReport = false;
  Map<String, dynamic>? _aiReport;
  String? _reportError;

  @override
  void initState() {
    super.initState();
    _authService.addListener(_onAuthChange);
    _loadWorkoutHistory();
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() {
    // Reload history when auth state changes (e.g., after merge completes)
    if (_authService.isAuthenticated) {
      _loadWorkoutHistory();
    }
  }

  Future<void> _loadWorkoutHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = await _authService.getCurrentUserId();
      final workouts = await _apiService.getWorkoutHistory(
        userId: userId,
        token: _authService.token,
      );

      setState(() {
        _workouts = workouts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy • HH:mm').format(date);
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
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  Future<void> _generateAIReport() async {
    if (_authService.token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to generate AI reports'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isGeneratingReport = true;
      _reportError = null;
      _aiReport = null;
    });

    try {
      final userId = await _authService.getCurrentUserId();
      final report = await _apiService.getWeeklyReport(
        userId: userId,
        token: _authService.token,
      );

      setState(() {
        _aiReport = report;
        _isGeneratingReport = false;
      });

      // Show report dialog
      _showReportDialog();
    } catch (e) {
      setState(() {
        _reportError = e.toString().replaceAll('Exception: ', '');
        _isGeneratingReport = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: ${_reportError}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showReportDialog() {
    if (_aiReport == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.psychology,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'AI Workout Report',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ],
                ),
              ),
              // Report content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Week info
                      if (_aiReport!['week_start'] != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Week of ${_formatWeekStart(_aiReport!['week_start'] as String)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Report text
                      Text(
                        _aiReport!['report_text'] as String? ??
                            'No report available',
                        style: const TextStyle(fontSize: 15, height: 1.6),
                      ),
                      if (_aiReport!['generated_at'] != null) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Generated: ${_formatDate(_aiReport!['generated_at'] as String)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Footer buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        // Regenerate report
                        setState(() {
                          _isGeneratingReport = true;
                          _reportError = null;
                        });
                        try {
                          final userId = await _authService.getCurrentUserId();
                          final report = await _apiService
                              .regenerateWeeklyReport(
                                userId: userId,
                                token: _authService.token,
                              );
                          setState(() {
                            _aiReport = report;
                            _isGeneratingReport = false;
                          });
                          _showReportDialog();
                        } catch (e) {
                          setState(() {
                            _reportError = e.toString();
                            _isGeneratingReport = false;
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to regenerate: ${_reportError}',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      child: const Text('Regenerate'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatWeekStart(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Workout History'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              if (_isGeneratingReport)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.psychology),
                  // The button appears disabled if _authService.token is null (user not logged in).
                  // If you want to always enable the button for debugging/testing, use:
                  // onPressed: _generateAIReport,
                  // To enable only for logged-in users, ensure your auth logic is correct.
                  onPressed: (_authService.token == null || _isGeneratingReport)
                      ? null
                      : _generateAIReport,
                  tooltip: 'Generate AI Report',
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadWorkoutHistory,
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
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadWorkoutHistory,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _workouts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.fitness_center,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No workouts yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start a workout to see it here',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadWorkoutHistory,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _workouts.length,
                    itemBuilder: (context, index) {
                      final workout = _workouts[index];
                      final status = workout['status'] as String;
                      final isCompleted = status == 'completed';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => WorkoutDetailPage(
                                  workoutId: workout['workout_id'] as String,
                                  workout: workout,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          isCompleted
                                              ? 'Completed'
                                              : 'In Progress',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isCompleted
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (workout['ended_at'] != null)
                                      Text(
                                        _formatDuration(
                                          DateTime.parse(
                                            workout['started_at'] as String,
                                          ),
                                          DateTime.parse(
                                            workout['ended_at'] as String,
                                          ),
                                        ),
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _formatDate(workout['started_at'] as String),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (workout['ended_at'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Ended: ${_formatDate(workout['ended_at'] as String)}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _StatChip(
                                      icon: Icons.fitness_center,
                                      label:
                                          '${workout['sets_count'] ?? 0} sets',
                                    ),
                                    const SizedBox(width: 8),
                                    _StatChip(
                                      icon: Icons.scale,
                                      label:
                                          '${(workout['total_volume'] ?? 0.0).toStringAsFixed(1)} kg',
                                    ),
                                    if (workout.containsKey('exercises') &&
                                        workout['exercises'] != null) ...[
                                      const SizedBox(width: 8),
                                      _StatChip(
                                        icon: Icons.sports_gymnastics,
                                        label:
                                            '${(workout['exercises'] as List).length} exercises',
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
        AiThinkingOverlay(
          isVisible: _isGeneratingReport,
          message: 'Generating your workout report...',
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ),
    );
  }
}
