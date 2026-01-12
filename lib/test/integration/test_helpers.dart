/// Test helper utilities for offline sync flow tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:hypertrophy/services/event_queue_service.dart';
import 'package:hypertrophy/services/api_service.dart';
import 'package:hypertrophy/services/database/event_queue_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initialize database factory for testing
/// This must be called before any database operations in tests
void initializeTestDatabase() {
  // Initialize FFI for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Create test workout events
List<Map<String, dynamic>> createTestWorkoutEvents({
  required String workoutId,
  required String exerciseId,
  required String setId,
  int startSequence = 1,
  DateTime? startedAt,
  DateTime? endedAt,
  DateTime? completedAt,
}) {
  final uuid = const Uuid();
  final now = DateTime.now();
  final start = startedAt ?? now.subtract(const Duration(hours: 1));
  final end = endedAt ?? now;
  final completed = completedAt ?? start.add(const Duration(minutes: 5));

  int sequence = startSequence;

  return [
    {
      'event_id': uuid.v4(),
      'event_type': 'WorkoutStarted',
      'payload': {
        'workout_id': workoutId,
        'started_at': start.toIso8601String(),
      },
      'sequence_number': sequence++,
    },
    {
      'event_id': uuid.v4(),
      'event_type': 'ExerciseAdded',
      'payload': {
        'workout_id': workoutId,
        'exercise_id': exerciseId,
        'exercise_name': 'Bench Press',
      },
      'sequence_number': sequence++,
    },
    {
      'event_id': uuid.v4(),
      'event_type': 'SetCompleted',
      'payload': {
        'workout_id': workoutId,
        'exercise_id': exerciseId,
        'set_id': setId,
        'reps': 10,
        'weight': 100.0,
        'completed_at': completed.toIso8601String(),
      },
      'sequence_number': sequence++,
    },
    {
      'event_id': uuid.v4(),
      'event_type': 'WorkoutEnded',
      'payload': {'workout_id': workoutId, 'ended_at': end.toIso8601String()},
      'sequence_number': sequence++,
    },
  ];
}

/// Verify events are in queue with correct status
Future<void> verifyEventsInQueue({
  required EventQueueService eventQueue,
  required int expectedCount,
  String status = 'pending',
  String? deviceId,
  String? userId,
}) async {
  final pendingEvents = await eventQueue.getPendingEvents();

  if (status == 'pending') {
    expect(
      pendingEvents.length,
      expectedCount,
      reason:
          'Expected $expectedCount pending events, got ${pendingEvents.length}',
    );

    if (deviceId != null) {
      final deviceEvents = pendingEvents
          .where((e) => e.deviceId == deviceId)
          .toList();
      expect(
        deviceEvents.length,
        expectedCount,
        reason: 'Expected $expectedCount events for device $deviceId',
      );
    }

    if (userId != null) {
      final userEvents = pendingEvents
          .where((e) => e.userId == userId)
          .toList();
      expect(
        userEvents.length,
        expectedCount,
        reason: 'Expected $expectedCount events for user $userId',
      );
    }

    // Verify all events have correct status
    for (final event in pendingEvents) {
      expect(
        event.status,
        status,
        reason: 'Event ${event.eventId} should have status $status',
      );
    }
  } else {
    // For non-pending status, check queue stats
    final stats = await eventQueue.getQueueStats();
    if (status == 'syncing') {
      expect(
        stats['syncing'],
        expectedCount,
        reason: 'Expected $expectedCount syncing events',
      );
    } else if (status == 'failed') {
      expect(
        stats['failed'],
        expectedCount,
        reason: 'Expected $expectedCount failed events',
      );
    }
  }
}

/// Verify queue is empty
Future<void> verifyQueueEmpty(EventQueueService eventQueue) async {
  final stats = await eventQueue.getQueueStats();
  expect(stats['total'], 0, reason: 'Queue should be empty');
}

/// Mock ApiService that can simulate offline/online states
class MockApiService extends ApiService {
  bool _isOnline = true;
  Exception? _nextError;
  Map<String, dynamic>? _nextResponse;
  int _callCount = 0;
  List<Map<String, dynamic>> _capturedEvents = [];
  String? _capturedDeviceId;
  String? _capturedUserId;

  bool get isOnline => _isOnline;
  int get callCount => _callCount;
  List<Map<String, dynamic>> get capturedEvents =>
      List.unmodifiable(_capturedEvents);
  String? get capturedDeviceId => _capturedDeviceId;
  String? get capturedUserId => _capturedUserId;

  void setOnline(bool online) {
    _isOnline = online;
  }

  void setNextError(Exception? error) {
    _nextError = error;
  }

  void setNextResponse(Map<String, dynamic> response) {
    _nextResponse = response;
  }

  void reset() {
    _callCount = 0;
    _capturedEvents = [];
    _capturedDeviceId = null;
    _capturedUserId = null;
    _nextError = null;
    _nextResponse = null;
  }

  @override
  Future<Map<String, dynamic>> syncEvents({
    required String deviceId,
    required String userId,
    required List<Map<String, dynamic>> events,
  }) async {
    _callCount++;
    _capturedDeviceId = deviceId;
    _capturedUserId = userId;
    _capturedEvents = List.from(events);

    if (!_isOnline || _nextError != null) {
      throw _nextError ?? Exception('Network error: Offline');
    }

    if (_nextResponse != null) {
      return _nextResponse!;
    }

    // Default successful response
    return {
      'accepted_count': events.length,
      'rejected_count': 0,
      'last_acked_sequence': events.isNotEmpty
          ? events
                .map((e) => e['sequence_number'] as int)
                .reduce((a, b) => a > b ? a : b)
          : null,
      'rejected_event_ids': <String>[],
    };
  }
}

/// Testable SyncService that accepts a mock ApiService
class TestableSyncService {
  final EventQueueService eventQueue;
  final MockApiService mockApiService;
  bool _isSyncing = false;

  TestableSyncService({required this.eventQueue, required this.mockApiService});

  bool get isSyncing => _isSyncing;

  Future<SyncResult> syncPendingEvents({
    required String deviceId,
    required String userId,
  }) async {
    if (_isSyncing) {
      return SyncResult(
        synced: 0,
        failed: 0,
        isSuccess: false,
        message: 'Sync already in progress',
      );
    }

    _isSyncing = true;

    try {
      final pendingEvents = await eventQueue.getPendingEvents();

      if (pendingEvents.isEmpty) {
        _isSyncing = false;
        return SyncResult(
          synced: 0,
          failed: 0,
          isSuccess: true,
          message: 'No pending events',
        );
      }

      final deviceEvents = pendingEvents
          .where((e) => e.deviceId == deviceId && e.userId == userId)
          .toList();

      if (deviceEvents.isEmpty) {
        _isSyncing = false;
        return SyncResult(
          synced: 0,
          failed: 0,
          isSuccess: true,
          message: 'No pending events for this device',
        );
      }

      final eventsToSync = deviceEvents.map((e) => e.toSyncFormat()).toList();
      final eventIds = deviceEvents.map((e) => e.eventId).toList();

      await eventQueue.markEventsSyncing(eventIds);

      try {
        await mockApiService.syncEvents(
          deviceId: deviceId,
          userId: userId,
          events: eventsToSync,
        );

        await eventQueue.markEventsSynced(eventIds);
        _isSyncing = false;

        return SyncResult(
          synced: eventIds.length,
          failed: 0,
          isSuccess: true,
          message: 'Synced ${eventIds.length} events',
        );
      } catch (e) {
        await eventQueue.markEventsFailed(eventIds);
        _isSyncing = false;

        return SyncResult(
          synced: 0,
          failed: eventIds.length,
          isSuccess: false,
          message: 'Sync failed: $e',
        );
      }
    } catch (e) {
      _isSyncing = false;
      return SyncResult(
        synced: 0,
        failed: 0,
        isSuccess: false,
        message: 'Sync error: $e',
      );
    }
  }
}

/// SyncResult class for testing
class SyncResult {
  final int synced;
  final int failed;
  final bool isSuccess;
  final String message;

  SyncResult({
    required this.synced,
    required this.failed,
    required this.isSuccess,
    required this.message,
  });
}

/// Clean up test database - clears all events and resets the database
Future<void> cleanupTestDatabase() async {
  try {
    // First, try to clear all events if database exists
    try {
      final db = await EventQueueDb.database;
      // Delete all events from the queue (execute DELETE without WHERE deletes all rows)
      await db.execute('DELETE FROM event_queue');
    } catch (e) {
      // Database might not exist yet, that's fine
    }

    // Close and reset the database to ensure clean state for next test
    try {
      await EventQueueDb.close();
    } catch (e) {
      // Ignore if already closed or doesn't exist
    }
  } catch (e) {
    // Ignore all cleanup errors
  }
}
