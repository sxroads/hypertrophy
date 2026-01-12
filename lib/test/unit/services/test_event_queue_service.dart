/// Unit tests for EventQueueService.

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:hypertrophy/services/event_queue_service.dart';
import 'package:hypertrophy/test/integration/test_helpers.dart';

void main() {
  // Initialize database factory once for all tests
  setUpAll(() {
    initializeTestDatabase();
  });

  group('EventQueueService Unit Tests', () {
    late EventQueueService eventQueue;
    late String testDeviceId;
    late String testUserId;

    setUp(() async {
      // Clean up database before each test to ensure clean state
      await cleanupTestDatabase();

      eventQueue = EventQueueService();
      testDeviceId = const Uuid().v4();
      testUserId = const Uuid().v4();
    });

    tearDown(() async {
      // Clean up database after each test - clear all events
      await cleanupTestDatabase();
    });

    test('test_queue_single_event', () async {
      final eventId = const Uuid().v4();
      final workoutId = const Uuid().v4();

      await eventQueue.queueEvents(
        events: [
          {
            'event_id': eventId,
            'event_type': 'WorkoutStarted',
            'payload': {
              'workout_id': workoutId,
              'started_at': DateTime.now().toIso8601String(),
            },
            'sequence_number': 1,
          },
        ],
        deviceId: testDeviceId,
        userId: testUserId,
      );

      final pendingEvents = await eventQueue.getPendingEvents();
      expect(pendingEvents.length, 1);
      expect(pendingEvents.first.eventId, eventId);
      expect(pendingEvents.first.eventType, 'WorkoutStarted');
      expect(pendingEvents.first.status, 'pending');
      expect(pendingEvents.first.retryCount, 0);
    });

    test('test_queue_batch_events', () async {
      final events = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      final pendingEvents = await eventQueue.getPendingEvents();
      expect(pendingEvents.length, 4);

      // Verify all events are queued
      final eventIds = events.map((e) => e['event_id'] as String).toList();
      final queuedEventIds = pendingEvents.map((e) => e.eventId).toList();

      for (final eventId in eventIds) {
        expect(queuedEventIds, contains(eventId));
      }
    });

    test('test_get_pending_events', () async {
      // Queue multiple events
      final events1 = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
        startSequence: 1,
      );

      await eventQueue.queueEvents(
        events: events1,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      final pendingEvents = await eventQueue.getPendingEvents();
      expect(pendingEvents.length, 4);

      // Verify events are ordered by sequence number
      for (int i = 1; i < pendingEvents.length; i++) {
        expect(
          pendingEvents[i].sequenceNumber,
          greaterThan(pendingEvents[i - 1].sequenceNumber),
        );
      }
    });

    test('test_mark_events_syncing', () async {
      final events = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      final eventIds = events.map((e) => e['event_id'] as String).toList();
      await eventQueue.markEventsSyncing(eventIds);

      // Verify events are marked as syncing
      final stats = await eventQueue.getQueueStats();
      expect(stats['syncing'], 4);
      expect(stats['pending'], 0);
    });

    test('test_mark_events_synced', () async {
      final events = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      final eventIds = events.map((e) => e['event_id'] as String).toList();
      await eventQueue.markEventsSynced(eventIds);

      // Verify events are removed from queue
      final pendingEvents = await eventQueue.getPendingEvents();
      expect(pendingEvents.length, 0);

      final stats = await eventQueue.getQueueStats();
      expect(stats['total'], 0);
    });

    test('test_mark_events_failed', () async {
      final events = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      final eventIds = events.map((e) => e['event_id'] as String).toList();

      // Mark as failed (should increment retry count)
      await eventQueue.markEventsFailed(eventIds);

      final pendingEvents = await eventQueue.getPendingEvents();
      expect(pendingEvents.length, 4);
      expect(pendingEvents.first.retryCount, 1);
      expect(
        pendingEvents.first.status,
        'pending',
      ); // Still pending if retry count < 5

      // Mark as failed multiple times
      for (int i = 0; i < 5; i++) {
        await eventQueue.markEventsFailed(eventIds);
      }

      // After 5+ failures, events should be marked as failed
      final stats = await eventQueue.getQueueStats();
      expect(stats['failed'], 4);
      expect(stats['pending'], 0);
    });

    test('test_update_user_id_for_events', () async {
      final oldUserId = const Uuid().v4();
      final newUserId = const Uuid().v4();

      // Queue events with old user_id
      final events = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: oldUserId,
      );

      // Update user_id
      final updatedCount = await eventQueue.updateUserIdForEvents(
        oldUserId: oldUserId,
        newUserId: newUserId,
      );

      expect(updatedCount, 4);

      // Verify events now have new user_id
      final pendingEvents = await eventQueue.getPendingEvents();
      for (final event in pendingEvents) {
        expect(event.userId, newUserId);
        expect(event.userId, isNot(oldUserId));
      }
    });

    test('test_reset_failed_events', () async {
      final events = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      final eventIds = events.map((e) => e['event_id'] as String).toList();

      // Mark as failed multiple times to get to failed status
      for (int i = 0; i < 6; i++) {
        await eventQueue.markEventsFailed(eventIds);
      }

      // Verify events are failed
      var stats = await eventQueue.getQueueStats();
      expect(stats['failed'], 4);

      // Reset failed events
      final resetCount = await eventQueue.resetFailedEvents(userId: testUserId);
      expect(resetCount, 4);

      // Verify events are back to pending with retry count reset
      stats = await eventQueue.getQueueStats();
      expect(stats['pending'], 4);
      expect(stats['failed'], 0);

      final pendingEvents = await eventQueue.getPendingEvents();
      for (final event in pendingEvents) {
        expect(event.retryCount, 0);
        expect(event.status, 'pending');
      }
    });

    test('test_get_queue_stats', () async {
      // Initially empty
      var stats = await eventQueue.getQueueStats();
      expect(stats['pending'], 0);
      expect(stats['syncing'], 0);
      expect(stats['failed'], 0);
      expect(stats['total'], 0);

      // Queue some events
      final events = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      stats = await eventQueue.getQueueStats();
      expect(stats['pending'], 4);
      expect(stats['total'], 4);

      // Mark as syncing
      final eventIds = events.map((e) => e['event_id'] as String).toList();
      await eventQueue.markEventsSyncing(eventIds);

      stats = await eventQueue.getQueueStats();
      expect(stats['syncing'], 4);
      expect(stats['pending'], 0);
      expect(stats['total'], 4);
    });

    test('test_queue_events_idempotency', () async {
      // Queue same events twice (same event_ids)
      final events = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Queue same events again
      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Should still have only 4 events (idempotent)
      final pendingEvents = await eventQueue.getPendingEvents();
      expect(pendingEvents.length, 4);
    });

    test('test_queue_events_different_devices', () async {
      final device1Id = const Uuid().v4();
      final device2Id = const Uuid().v4();

      // Queue events for device 1
      final events1 = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
        startSequence: 1,
      );

      await eventQueue.queueEvents(
        events: events1,
        deviceId: device1Id,
        userId: testUserId,
      );

      // Queue events for device 2
      final events2 = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
        startSequence: 1, // Can have same sequence for different device
      );

      await eventQueue.queueEvents(
        events: events2,
        deviceId: device2Id,
        userId: testUserId,
      );

      // Should have 8 events total
      final pendingEvents = await eventQueue.getPendingEvents();
      expect(pendingEvents.length, 8);

      // Verify device separation
      final device1Events = pendingEvents
          .where((e) => e.deviceId == device1Id)
          .toList();
      final device2Events = pendingEvents
          .where((e) => e.deviceId == device2Id)
          .toList();
      expect(device1Events.length, 4);
      expect(device2Events.length, 4);
    });
  });
}
