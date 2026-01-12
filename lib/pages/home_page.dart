import 'package:flutter/material.dart';
import 'package:hypertrophy/pages/profile_page.dart';
import 'package:hypertrophy/pages/workout_page.dart';
import 'package:hypertrophy/pages/history_page.dart';
import 'package:hypertrophy/pages/records_page.dart';
import 'package:hypertrophy/pages/templates_page.dart';
import 'package:hypertrophy/services/api_service.dart';
import 'package:hypertrophy/services/auth_service.dart';
import 'package:hypertrophy/pages/measurement_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _apiService = ApiService();
  final _authService = AuthService();

  List<Map<String, dynamic>> _workouts = [];
  bool _isLoading = true;
  int _currentStreak = 0;
  int _bestStreak = 0;
  int _workoutsThisMonth = 0;
  Set<DateTime> _workoutDates = {};
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService.addListener(_onAuthChange);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authService.removeListener(_onAuthChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Reload data when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _loadData();
    }
  }

  void _onAuthChange() {
    // Clear data if user logged out
    if (!_authService.isAuthenticated) {
      setState(() {
        _workouts = [];
        _currentStreak = 0;
        _bestStreak = 0;
        _workoutsThisMonth = 0;
        _workoutDates = {};
        _isLoading = false;
      });
    } else {
      // Reload data if user logged in
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = await _authService.getCurrentUserId();
      final workouts = await _apiService.getWorkoutHistory(
        userId: userId,
        token: _authService.token,
      );

      _workouts = workouts;
      _calculateStats();
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _calculateStats() {
    final now = DateTime.now();
    final thisMonthStart = DateTime(now.year, now.month, 1);

    // Extract workout dates (only completed workouts)
    _workoutDates = {};
    _workoutsThisMonth = 0;
    for (var workout in _workouts) {
      if (workout['status'] == 'completed' && workout['started_at'] != null) {
        final date = DateTime.parse(workout['started_at']);
        _workoutDates.add(DateTime(date.year, date.month, date.day));

        // Count workouts this month
        if (date.isAfter(thisMonthStart.subtract(const Duration(days: 1)))) {
          _workoutsThisMonth++;
        }
      }
    }

    // Calculate current streak
    _currentStreak = _calculateCurrentStreak();

    // Calculate best streak
    _bestStreak = _calculateBestStreak();
  }

  int _calculateCurrentStreak() {
    if (_workoutDates.isEmpty) return 0;

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    var currentDate = todayDate;
    int streak = 0;

    // Check if today has a workou
    if (_workoutDates.contains(currentDate)) {
      streak = 1;
      currentDate = currentDate.subtract(const Duration(days: 1));
    } else {
      currentDate = currentDate.subtract(const Duration(days: 1));
    }

    while (_workoutDates.contains(currentDate)) {
      streak++;
      currentDate = currentDate.subtract(const Duration(days: 1));
    }

    return streak;
  }

  int _calculateBestStreak() {
    if (_workoutDates.isEmpty) return 0;

    final sortedDates = _workoutDates.toList()..sort();
    if (sortedDates.isEmpty) return 0;

    int bestStreak = 1;
    int currentStreak = 1;

    for (int i = 1; i < sortedDates.length; i++) {
      final prevDate = sortedDates[i - 1];
      final currDate = sortedDates[i];
      final daysDiff = currDate.difference(prevDate).inDays;

      if (daysDiff == 1) {
        currentStreak++;
        bestStreak = currentStreak > bestStreak ? currentStreak : bestStreak;
      } else {
        currentStreak = 1;
      }
    }

    return bestStreak;
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
        // Already on home
        break;

      case 1:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MeasurementPage()),
        );
        break;
      case 2:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ProfilePage()),
        );
        break;
    }

    // Reset to home after navigation
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _selectedIndex = 0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Page Title Block - Fixed at top
                _buildTitleBlock(),

                // Scrollable content
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Progress Calendar
                          _buildProgressCalendar(),

                          // Primary CTA
                          _buildStartWorkoutButton(),

                          // Secondary Action Cards
                          _buildSecondaryCards(),

                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),

          BottomNavigationBarItem(
            icon: Icon(Icons.monitor_weight),
            label: 'Measurements',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildTitleBlock() {
    final safeAreaTop = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, safeAreaTop + 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Track Your Gym Progress',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Stay consistent & reach your goals',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCalendar() {
    final weeks = 4;
    final today = DateTime.now();
    final startDate = today.subtract(Duration(days: weeks * 7 - 1));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Last $weeks Weeks',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              // Streak stats on the right
              Row(
                children: [
                  _buildStreakStat('Current', _currentStreak),
                  const SizedBox(width: 16),
                  _buildStreakStat('Best', _bestStreak),
                  const SizedBox(width: 16),
                  _buildStreakStat('This Month', _workoutsThisMonth),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Calendar Grid
          _buildCalendarGrid(startDate, today),
        ],
      ),
    );
  }

  Widget _buildStreakStat(String label, int value) {
    return Column(
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildCalendarGrid(DateTime startDate, DateTime endDate) {
    final days = <DateTime>[];
    var current = startDate;
    while (current.isBefore(endDate) || current.isAtSameMomentAs(endDate)) {
      days.add(DateTime(current.year, current.month, current.day));
      current = current.add(const Duration(days: 1));
    }

    // Group into weeks
    final weeks = <List<DateTime>>[];
    for (int i = 0; i < days.length; i += 7) {
      weeks.add(days.sublist(i, i + 7 > days.length ? days.length : i + 7));
    }

    // Day name abbreviations
    final dayNames = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Column(
      children: [
        // Day name headers
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: dayNames.map((dayName) {
              return Expanded(
                child: Center(
                  child: Text(
                    dayName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Calendar weeks
        ...weeks.map((week) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: week.map((date) {
                final hasWorkout = _workoutDates.contains(date);
                final isToday =
                    date.year == DateTime.now().year &&
                    date.month == DateTime.now().month &&
                    date.day == DateTime.now().day;

                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 40,
                    decoration: BoxDecoration(
                      color: hasWorkout
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                      border: isToday
                          ? Border.all(color: Colors.green[400]!, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isToday
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: hasWorkout ? Colors.white : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildStartWorkoutButton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ElevatedButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const WorkoutPage()),
          ).then((_) {
            // Reload data when returning from workout page
            _loadData();
          });
        },
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: const Text(
          'Start Workout',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildSecondaryCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildActionCard(
            icon: Icons.assessment,
            title: 'Statistics',
            subtitle: 'View your progress and PRs',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RecordsPage()),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            icon: Icons.history,
            title: 'Workout History',
            subtitle: 'Review past workouts',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryPage()),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            icon: Icons.bookmark,
            title: 'Exercise Plans',
            subtitle: 'Manage your routines',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TemplatesPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
