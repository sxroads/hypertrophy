/// Integration tests for sync flow.
///
/// Tests offline/online sync scenarios.

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:hypertrophy/services/event_queue_service.dart';
import 'package:hypertrophy/test/integration/test_helpers.dart';

void main() {
  // Initialize database factory once for all tests
  setUpAll(() {
    initializeTestDatabase();
  });

  group('Sync Flow Integration Tests', () {
    late EventQueueService eventQueue;
    late MockApiService mockApiService;
    late TestableSyncService syncService;
    late String testDeviceId;
    late String testUserId;
    late String testAnonymousUserId;

    setUp(() async {
      // Initialize fresh services for each test
      eventQueue = EventQueueService();
      mockApiService = MockApiService();
      syncService = TestableSyncService(
        eventQueue: eventQueue,
        mockApiService: mockApiService,
      );

      testDeviceId = const Uuid().v4();
      testUserId = const Uuid().v4();
      testAnonymousUserId = const Uuid().v4();
    });

    tearDown(() async {
      // Clean up database after each test - clear all events
      await cleanupTestDatabase();
      mockApiService.reset();
    });

    test('test_offline_workout_creation', () async {
      // Simulate offline state
      mockApiService.setOnline(false);

      // Create workout events
      final workoutId = const Uuid().v4();
      final exerciseId = const Uuid().v4();
      final setId = const Uuid().v4();

      final events = createTestWorkoutEvents(
        workoutId: workoutId,
        exerciseId: exerciseId,
        setId: setId,
      );

      // Queue events (this should succeed even when offline)
      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Verify events are queued with status "pending"
      await verifyEventsInQueue(
        eventQueue: eventQueue,
        expectedCount: 4,
        status: 'pending',
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Verify API was not called (we're offline)
      expect(mockApiService.callCount, 0);
    });

    test('test_online_sync_success', () async {
      // First, queue events while offline
      mockApiService.setOnline(false);

      final workoutId = const Uuid().v4();
      final exerciseId = const Uuid().v4();
      final setId = const Uuid().v4();

      final events = createTestWorkoutEvents(
        workoutId: workoutId,
        exerciseId: exerciseId,
        setId: setId,
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Verify events are queued
      await verifyEventsInQueue(
        eventQueue: eventQueue,
        expectedCount: 4,
        status: 'pending',
      );

      // Now switch to online and sync
      mockApiService.setOnline(true);
      final syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Verify sync succeeded
      expect(syncResult.isSuccess, true);
      expect(syncResult.synced, 4);
      expect(syncResult.failed, 0);

      // Verify events were sent to API
      expect(mockApiService.callCount, 1);
      expect(mockApiService.capturedEvents.length, 4);
      expect(mockApiService.capturedDeviceId, testDeviceId);
      expect(mockApiService.capturedUserId, testUserId);

      // Verify queue is now empty
      await verifyQueueEmpty(eventQueue);
    });

    test('test_sync_retry_on_failure', () async {
      // Queue events
      final workoutId = const Uuid().v4();
      final exerciseId = const Uuid().v4();
      final setId = const Uuid().v4();

      final events = createTestWorkoutEvents(
        workoutId: workoutId,
        exerciseId: exerciseId,
        setId: setId,
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // First sync attempt fails
      mockApiService.setOnline(true);
      mockApiService.setNextError(Exception('Network timeout'));

      var syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Verify sync failed
      expect(syncResult.isSuccess, false);
      expect(syncResult.failed, 4);

      // Verify events are still in queue with retry count incremented
      final pendingEvents = await eventQueue.getPendingEvents();
      expect(pendingEvents.length, 4);
      expect(pendingEvents.first.retryCount, 1);

      // Now retry with success (clear error)
      mockApiService.setNextError(null);
      syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Verify sync succeeded on retry
      expect(syncResult.isSuccess, true);
      expect(syncResult.synced, 4);

      // Verify queue is empty
      await verifyQueueEmpty(eventQueue);
    });

    test('test_sync_idempotency', () async {
      // Queue and sync events successfully
      final workoutId = const Uuid().v4();
      final exerciseId = const Uuid().v4();
      final setId = const Uuid().v4();

      final events = createTestWorkoutEvents(
        workoutId: workoutId,
        exerciseId: exerciseId,
        setId: setId,
      );

      // Store event IDs for idempotency test
      final eventIds = events.map((e) => e['event_id'] as String).toList();

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // First sync
      mockApiService.setOnline(true);
      var syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      expect(syncResult.isSuccess, true);
      expect(syncResult.synced, 4);
      await verifyQueueEmpty(eventQueue);

      // Queue same events again (same event_ids)
      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Attempt to sync same events again
      syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Verify sync was attempted (API called)
      expect(mockApiService.callCount, 2);

      // Verify events were sent (backend should handle idempotency)
      expect(mockApiService.capturedEvents.length, 4);

      // Verify same event IDs were sent
      final capturedEventIds = mockApiService.capturedEvents
          .map((e) => e['event_id'] as String)
          .toList();
      expect(capturedEventIds, eventIds);
    });

    test('test_sync_after_login', () async {
      // Create events as anonymous user
      final workoutId = const Uuid().v4();
      final exerciseId = const Uuid().v4();
      final setId = const Uuid().v4();

      final events = createTestWorkoutEvents(
        workoutId: workoutId,
        exerciseId: exerciseId,
        setId: setId,
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: testAnonymousUserId,
      );

      // Verify events are queued with anonymous user_id
      await verifyEventsInQueue(
        eventQueue: eventQueue,
        expectedCount: 4,
        status: 'pending',
        userId: testAnonymousUserId,
      );

      // Simulate login: update user_id for all events
      final updatedCount = await eventQueue.updateUserIdForEvents(
        oldUserId: testAnonymousUserId,
        newUserId: testUserId,
      );

      expect(updatedCount, 4);

      // Verify events now have new user_id
      await verifyEventsInQueue(
        eventQueue: eventQueue,
        expectedCount: 4,
        status: 'pending',
        userId: testUserId,
      );

      // Sync with new user_id
      mockApiService.setOnline(true);
      final syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Verify sync succeeded with new user_id
      expect(syncResult.isSuccess, true);
      expect(syncResult.synced, 4);
      expect(mockApiService.capturedUserId, testUserId);

      // Verify queue is empty
      await verifyQueueEmpty(eventQueue);
    });

    test('test_multiple_offline_workouts', () async {
      // Create multiple workouts while offline
      mockApiService.setOnline(false);

      final workout1Id = const Uuid().v4();
      final workout2Id = const Uuid().v4();
      final exercise1Id = const Uuid().v4();
      final exercise2Id = const Uuid().v4();
      final set1Id = const Uuid().v4();
      final set2Id = const Uuid().v4();

      // First workout
      final events1 = createTestWorkoutEvents(
        workoutId: workout1Id,
        exerciseId: exercise1Id,
        setId: set1Id,
        startSequence: 1,
      );

      await eventQueue.queueEvents(
        events: events1,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Second workout
      final events2 = createTestWorkoutEvents(
        workoutId: workout2Id,
        exerciseId: exercise2Id,
        setId: set2Id,
        startSequence: 5, // Continue sequence
      );

      await eventQueue.queueEvents(
        events: events2,
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Verify all events are queued
      await verifyEventsInQueue(
        eventQueue: eventQueue,
        expectedCount: 8,
        status: 'pending',
      );

      // Verify sequence numbers are correct
      final pendingEvents = await eventQueue.getPendingEvents();
      final sequenceNumbers = pendingEvents
          .map((e) => e.sequenceNumber)
          .toList();

      // Verify sequence is monotonic
      for (int i = 1; i < sequenceNumbers.length; i++) {
        expect(
          sequenceNumbers[i],
          greaterThan(sequenceNumbers[i - 1]),
          reason: 'Sequence numbers must be monotonic',
        );
      }

      // Come back online and sync
      mockApiService.setOnline(true);
      final syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Verify all events synced
      expect(syncResult.isSuccess, true);
      expect(syncResult.synced, 8);

      // Verify events were sent in correct order
      expect(mockApiService.capturedEvents.length, 8);
      final syncedSequenceNumbers = mockApiService.capturedEvents
          .map((e) => e['sequence_number'] as int)
          .toList();

      // Verify synced events maintain sequence order
      for (int i = 1; i < syncedSequenceNumbers.length; i++) {
        expect(
          syncedSequenceNumbers[i],
          greaterThan(syncedSequenceNumbers[i - 1]),
          reason: 'Synced events must maintain sequence order',
        );
      }

      // Verify queue is empty
      await verifyQueueEmpty(eventQueue);
    });
  });
}
