import 'package:flutter/material.dart';
import 'package:hypertrophy/services/api_service.dart';
import 'package:hypertrophy/services/auth_service.dart';
import 'package:hypertrophy/services/database/ai_reports_db.dart';
import 'package:hypertrophy/widgets/ai_thinking_overlay.dart';
import 'package:intl/intl.dart';

class MeasurementPage extends StatefulWidget {
  const MeasurementPage({super.key});

  @override
  State<MeasurementPage> createState() => _MeasurementPageState();
}

class _MeasurementPageState extends State<MeasurementPage> {
  final _apiService = ApiService();
  final _authService = AuthService();

  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Form controllers
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _neckController = TextEditingController();
  final _waistController = TextEditingController();
  final _hipController = TextEditingController();
  final _chestController = TextEditingController();
  final _shoulderController = TextEditingController();
  final _bicepController = TextEditingController();
  final _forearmController = TextEditingController();
  final _thighController = TextEditingController();
  final _calfController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _userGender;
  int? _userAge;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isLoadingReport = false;

  List<Map<String, dynamic>> _measurements = [];
  Map<String, dynamic>? _latestMeasurement;
  Map<String, dynamic>? _aiReport;
  String? _newMeasurementId;
  bool _isHistoryExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _neckController.dispose();
    _waistController.dispose();
    _hipController.dispose();
    _chestController.dispose();
    _shoulderController.dispose();
    _bicepController.dispose();
    _forearmController.dispose();
    _thighController.dispose();
    _calfController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final token = _authService.token;

      // Load user profile
      if (token != null) {
        try {
          final userInfo = await _apiService.getCurrentUserInfo(token: token);
          setState(() {
            _userGender = userInfo['gender'] as String?;
            _userAge = userInfo['age'] as int?;
          });
        } catch (e) {
          debugPrint('Failed to load user info: $e');
        }
      }

      // Load measurements
      try {
        final userId = await _authService.getCurrentUserId();
        final measurements = await _apiService.getBodyMeasurements(
          userId: userId,
          token: token,
        );
        setState(() {
          _measurements = measurements;
        });
      } catch (e) {
        debugPrint('Failed to load measurements: $e');
      }

      // Load latest measurement
      try {
        final userId = await _authService.getCurrentUserId();
        final latest = await _apiService.getLatestBodyMeasurement(
          userId: userId,
          token: token,
        );
        setState(() {
          _latestMeasurement = latest;
        });

        // Load AI report from local DB if available
        // Skip if we just loaded a report for this measurement (to avoid overwriting fresh data)
        final measurementId = latest['measurement_id'] as String?;
        if (measurementId != null && !_isLoadingReport) {
          // Don't overwrite if we just loaded this measurement's report
          if (measurementId != _newMeasurementId) {
            final cachedReport = await AiReportsDb.getReport(measurementId);
            if (cachedReport != null && mounted) {
              setState(() {
                _aiReport = cachedReport;
              });
            }
          }
        }
      } catch (e) {
        // No measurements yet
        debugPrint('No measurements found');
      }
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

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitMeasurement() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }

    // Check if gender is set
    if (_userGender == null) {
      _showGenderAgeDialog();
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final token = _authService.token;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final measurement = await _apiService.createBodyMeasurement(
        token: token,
        measuredAt: _selectedDate,
        heightCm: double.parse(_heightController.text),
        weightKg: double.parse(_weightController.text),
        neckCm: double.parse(_neckController.text),
        waistCm: double.parse(_waistController.text),
        hipCm: _hipController.text.isNotEmpty
            ? double.parse(_hipController.text)
            : null,
        chestCm: _chestController.text.isNotEmpty
            ? double.parse(_chestController.text)
            : null,
        shoulderCm: _shoulderController.text.isNotEmpty
            ? double.parse(_shoulderController.text)
            : null,
        bicepCm: _bicepController.text.isNotEmpty
            ? double.parse(_bicepController.text)
            : null,
        forearmCm: _forearmController.text.isNotEmpty
            ? double.parse(_forearmController.text)
            : null,
        thighCm: _thighController.text.isNotEmpty
            ? double.parse(_thighController.text)
            : null,
        calfCm: _calfController.text.isNotEmpty
            ? double.parse(_calfController.text)
            : null,
      );

      setState(() {
        _newMeasurementId = measurement['measurement_id'] as String;
      });

      // Generate AI report
      await _loadAIReport(_newMeasurementId!);

      // Reload measurements
      await _loadData();

      // Clear form
      _heightController.clear();
      _weightController.clear();
      _neckController.clear();
      _waistController.clear();
      _hipController.clear();
      _chestController.clear();
      _shoulderController.clear();
      _bicepController.clear();
      _forearmController.clear();
      _thighController.clear();
      _calfController.clear();

      // Scroll to report
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Measurement saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _loadAIReport(String measurementId) async {
    setState(() {
      _isLoadingReport = true;
      // Keep old report visible while loading new one
    });

    try {
      final token = _authService.token;
      if (token == null) {
        if (mounted) {
          setState(() {
            _isLoadingReport = false;
          });
        }
        return;
      }

      final report = await _apiService.getBodyMeasurementReport(
        measurementId: measurementId,
        token: token,
      );

      // Save report to local database
      final reportText = report['report_text'] as String?;
      if (reportText != null) {
        await AiReportsDb.saveReport(
          measurementId: measurementId,
          reportText: reportText,
        );
      }

      if (mounted) {
        setState(() {
          _aiReport = report;
          _isLoadingReport = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load AI report: $e');
      if (mounted) {
        setState(() {
          _isLoadingReport = false;
        });
      }
    }
  }

  void _showGenderAgeDialog() {
    String? selectedGender = _userGender;
    final ageController = TextEditingController(
      text: _userAge?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Profile Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Gender and age are required for body fat calculation.'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedGender,
              decoration: const InputDecoration(
                labelText: 'Gender',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
              ],
              onChanged: (value) {
                selectedGender = value;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: ageController,
              decoration: const InputDecoration(
                labelText: 'Age',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selectedGender == null || ageController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please fill in all fields'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                final token = _authService.token;
                if (token != null) {
                  await _apiService.updateUserProfile(
                    token: token,
                    gender: selectedGender,
                    age: int.parse(ageController.text),
                  );
                  await _loadData();
                  if (context.mounted) {
                    Navigator.pop(context);
                    _submitMeasurement();
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('Body Measurements')),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Profile info banner
                          if (_userGender == null || _userAge == null)
                            Card(
                              color: Colors.orange.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.orange.shade700,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Profile Information Required',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange.shade900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Set your gender and age to calculate body fat percentage.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.orange.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _showGenderAgeDialog,
                                      child: const Text('Set Now'),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Latest measurement summary
                          if (_latestMeasurement != null) ...[
                            const SizedBox(height: 16),
                            _buildLatestMeasurementCard(),
                          ],

                          // Form section
                          const SizedBox(height: 24),
                          _buildFormSection(),

                          // Results section (shown after submission)
                          if (_newMeasurementId != null &&
                              _latestMeasurement != null)
                            ..._buildResultsSection(),

                          // AI Report section
                          if (_aiReport != null) ...[
                            const SizedBox(height: 24),
                            _buildAIReportCard(),
                          ],

                          // History section
                          if (_measurements.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildHistorySection(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        AiThinkingOverlay(
          isVisible: _isLoadingReport,
          message: 'Analyzing your measurements...',
        ),
      ],
    );
  }

  Widget _buildLatestMeasurementCard() {
    final m = _latestMeasurement!;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Latest Measurement',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem(
                  'Weight',
                  '${m['weight_kg']?.toStringAsFixed(1)} kg',
                ),
                _buildMetricItem(
                  'Body Fat',
                  '${m['body_fat_percentage']?.toStringAsFixed(1)}%',
                ),
                _buildMetricItem(
                  'Lean Mass',
                  '${m['lean_mass_kg']?.toStringAsFixed(1)} kg',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Date: ${DateFormat('yyyy-MM-dd').format(DateTime.parse(m['measured_at']))}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildFormSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'New Measurement',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Date picker
            InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Measurement Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
              ),
            ),
            const SizedBox(height: 16),
            // Required measurements section
            Text(
              'Required Measurements',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _heightController,
              label: 'Height (cm) *',
              icon: Icons.height,
              hint: _latestMeasurement?['height_cm']?.toStringAsFixed(1),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _weightController,
              label: 'Weight (kg) *',
              icon: Icons.monitor_weight,
              hint: _latestMeasurement?['weight_kg']?.toStringAsFixed(1),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _neckController,
              label: 'Neck (cm) *',
              icon: Icons.circle,
              hint: _latestMeasurement?['neck_cm']?.toStringAsFixed(1),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _waistController,
              label: 'Waist (cm) *',
              icon: Icons.circle,
              hint: _latestMeasurement?['waist_cm']?.toStringAsFixed(1),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _hipController,
              label: 'Hip (cm) ${_userGender == "female" ? "*" : ""}',
              icon: Icons.circle,
              hint: _latestMeasurement?['hip_cm']?.toStringAsFixed(1),
            ),
            const SizedBox(height: 24),
            // Optional measurements
            Text(
              'Optional Measurements',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _chestController,
              label: 'Chest (cm)',
              icon: Icons.circle,
              hint: _latestMeasurement?['chest_cm']?.toStringAsFixed(1),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _shoulderController,
              label: 'Shoulder (cm)',
              icon: Icons.circle,
              hint: _latestMeasurement?['shoulder_cm']?.toStringAsFixed(1),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _bicepController,
              label: 'Bicep (cm)',
              icon: Icons.circle,
              hint: _latestMeasurement?['bicep_cm']?.toStringAsFixed(1),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _forearmController,
              label: 'Forearm (cm)',
              icon: Icons.circle,
              hint: _latestMeasurement?['forearm_cm']?.toStringAsFixed(1),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _thighController,
              label: 'Thigh (cm)',
              icon: Icons.circle,
              hint: _latestMeasurement?['thigh_cm']?.toStringAsFixed(1),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _calfController,
              label: 'Calf (cm)',
              icon: Icons.circle,
              hint: _latestMeasurement?['calf_cm']?.toStringAsFixed(1),
            ),
            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitMeasurement,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Measurement'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint != null ? 'Previous: $hint' : null,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (label.contains('*') && (value == null || value.isEmpty)) {
          return 'This field is required';
        }
        if (value != null && value.isNotEmpty) {
          final num = double.tryParse(value);
          if (num == null || num <= 0) {
            return 'Please enter a valid positive number';
          }
        }
        return null;
      },
    );
  }

  List<Widget> _buildResultsSection() {
    final m = _latestMeasurement!;
    return [
      Card(
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calculate, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Calculated Results',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricItem(
                    'Body Fat',
                    '${m['body_fat_percentage']?.toStringAsFixed(1)}%',
                  ),
                  _buildMetricItem(
                    'Fat Mass',
                    '${m['fat_mass_kg']?.toStringAsFixed(1)} kg',
                  ),
                  _buildMetricItem(
                    'Lean Mass',
                    '${m['lean_mass_kg']?.toStringAsFixed(1)} kg',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildAIReportCard() {
    return Card(
      elevation: 2,
      child: ExpansionTile(
        leading: Icon(Icons.psychology, color: Colors.purple.shade700),
        title: const Text(
          'AI Analysis Report',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: _isLoadingReport
            ? const Text('Generating report...')
            : const Text('Tap to expand'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _isLoadingReport
                ? const Center(child: CircularProgressIndicator())
                : Text(
                    _aiReport?['report_text'] ?? 'No report available',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Card(
      elevation: 2,
      child: ExpansionTile(
        leading: Icon(Icons.history, color: Colors.blue.shade700),
        title: Text(
          'Measurement History',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${_measurements.length} measurement${_measurements.length != 1 ? 's' : ''}',
        ),
        initiallyExpanded: _isHistoryExpanded,
        onExpansionChanged: (expanded) {
          setState(() {
            _isHistoryExpanded = expanded;
          });
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _measurements.map((m) => _buildHistoryItem(m)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> measurement) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat(
                        'yyyy-MM-dd',
                      ).format(DateTime.parse(measurement['measured_at'])),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Measurement?'),
                        content: const Text('This action cannot be undone.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      try {
                        final token = _authService.token;
                        if (token != null) {
                          final measurementId =
                              measurement['measurement_id'] as String;
                          await _apiService.deleteBodyMeasurement(
                            measurementId: measurementId,
                            token: token,
                          );
                          // Delete cached AI report
                          await AiReportsDb.deleteReport(measurementId);
                          await _loadData();
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Key metrics row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildHistoryMetric(
                  'Weight',
                  '${measurement['weight_kg']?.toStringAsFixed(1)} kg',
                ),
                _buildHistoryMetric(
                  'Body Fat',
                  '${measurement['body_fat_percentage']?.toStringAsFixed(1)}%',
                ),
                _buildHistoryMetric(
                  'Lean Mass',
                  '${measurement['lean_mass_kg']?.toStringAsFixed(1)} kg',
                ),
              ],
            ),
            // Additional measurements if available
            if (measurement['height_cm'] != null ||
                measurement['neck_cm'] != null ||
                measurement['waist_cm'] != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  if (measurement['height_cm'] != null)
                    _buildHistoryDetail(
                      'Height',
                      '${measurement['height_cm']?.toStringAsFixed(1)} cm',
                    ),
                  if (measurement['neck_cm'] != null)
                    _buildHistoryDetail(
                      'Neck',
                      '${measurement['neck_cm']?.toStringAsFixed(1)} cm',
                    ),
                  if (measurement['waist_cm'] != null)
                    _buildHistoryDetail(
                      'Waist',
                      '${measurement['waist_cm']?.toStringAsFixed(1)} cm',
                    ),
                  if (measurement['hip_cm'] != null)
                    _buildHistoryDetail(
                      'Hip',
                      '${measurement['hip_cm']?.toStringAsFixed(1)} cm',
                    ),
                  if (measurement['chest_cm'] != null)
                    _buildHistoryDetail(
                      'Chest',
                      '${measurement['chest_cm']?.toStringAsFixed(1)} cm',
                    ),
                  if (measurement['shoulder_cm'] != null)
                    _buildHistoryDetail(
                      'Shoulder',
                      '${measurement['shoulder_cm']?.toStringAsFixed(1)} cm',
                    ),
                  if (measurement['bicep_cm'] != null)
                    _buildHistoryDetail(
                      'Bicep',
                      '${measurement['bicep_cm']?.toStringAsFixed(1)} cm',
                    ),
                  if (measurement['forearm_cm'] != null)
                    _buildHistoryDetail(
                      'Forearm',
                      '${measurement['forearm_cm']?.toStringAsFixed(1)} cm',
                    ),
                  if (measurement['thigh_cm'] != null)
                    _buildHistoryDetail(
                      'Thigh',
                      '${measurement['thigh_cm']?.toStringAsFixed(1)} cm',
                    ),
                  if (measurement['calf_cm'] != null)
                    _buildHistoryDetail(
                      'Calf',
                      '${measurement['calf_cm']?.toStringAsFixed(1)} cm',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryMetric(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
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

  Widget _buildHistoryDetail(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
