import 'package:flutter/material.dart';
import 'package:hypertrophy/services/api_service.dart';
import 'dart:convert';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _deviceIdController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  Map<String, dynamic>? _response;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _deviceIdController.text = '550e8400-e29b-41d4-a716-446655440000';
    _userIdController.text = '660e8400-e29b-41d4-a716-446655440000';
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _syncEvents() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _response = null;
    });

    try {
      final events = [
        {
          'event_id': '770e8400-e29b-41d4-a716-446655440001',
          'event_type': 'WorkoutStarted',
          'payload': {
            'workout_id': '880e8400-e29b-41d4-a716-446655440000',
            'started_at': DateTime.now().toIso8601String(),
          },
          'sequence_number': 1,
        },
        {
          'event_id': '770e8400-e29b-41d4-a716-446655440002',
          'event_type': 'WorkoutEnded',
          'payload': {
            'workout_id': '880e8400-e29b-41d4-a716-446655440000',
            'ended_at': DateTime.now().toIso8601String(),
          },
          'sequence_number': 2,
        },
      ];

      final result = await _apiService.syncEvents(
        deviceId: _deviceIdController.text,
        userId: _userIdController.text,
        events: events,
      );

      setState(() {
        _response = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync Events')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _deviceIdController,
              decoration: const InputDecoration(
                labelText: 'Device ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _userIdController,
              decoration: const InputDecoration(
                labelText: 'User ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _syncEvents,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sync Events'),
            ),
            const SizedBox(height: 24),
            if (_response != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Response:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        const JsonEncoder.withIndent('  ').convert(_response),
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Error:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
