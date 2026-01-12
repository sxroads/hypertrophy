/// Unit tests for SyncService.

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:hypertrophy/services/event_queue_service.dart';
import 'package:hypertrophy/test/integration/test_helpers.dart';

void main() {
  // Initialize database factory once for all tests
  setUpAll(() {
    initializeTestDatabase();
  });

  group('SyncService Unit Tests', () {
    late EventQueueService eventQueue;
    late MockApiService mockApiService;
    late TestableSyncService syncService;
    late String testDeviceId;
    late String testUserId;

    setUp(() async {
      // Clean up database before each test to ensure clean state
      await cleanupTestDatabase();

      eventQueue = EventQueueService();
      mockApiService = MockApiService();
      syncService = TestableSyncService(
        eventQueue: eventQueue,
        mockApiService: mockApiService,
      );

      testDeviceId = const Uuid().v4();
      testUserId = const Uuid().v4();
    });

    tearDown(() async {
      // Clean up database after each test - clear all events
      await cleanupTestDatabase();
      mockApiService.reset();
    });

    test('test_sync_when_no_pending_events', () async {
      mockApiService.setOnline(true);

      final syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      expect(syncResult.isSuccess, true);
      expect(syncResult.synced, 0);
      expect(syncResult.failed, 0);
      expect(syncResult.message, 'No pending events');
      expect(mockApiService.callCount, 0);
    });

    test('test_sync_when_already_syncing', () async {
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

      mockApiService.setOnline(true);

      // Start first sync (will be async)
      final sync1 = syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Immediately try to sync again (should be blocked)
      final sync2 = syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      final results = await Future.wait([sync1, sync2]);

      // One should succeed, one should be blocked
      final successCount = results.where((r) => r.isSuccess).length;
      final blockedCount = results
          .where(
            (r) => !r.isSuccess && r.message.contains('already in progress'),
          )
          .length;

      expect(successCount, 1);
      expect(blockedCount, 1);
    });

    test('test_filtering_events_by_device_and_user', () async {
      final otherDeviceId = const Uuid().v4();
      final otherUserId = const Uuid().v4();

      // Queue events for test device/user
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

      // Queue events for different device/user
      final events2 = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
        startSequence: 5,
      );

      await eventQueue.queueEvents(
        events: events2,
        deviceId: otherDeviceId,
        userId: otherUserId,
      );

      // Verify 8 events total in queue
      final allPending = await eventQueue.getPendingEvents();
      expect(allPending.length, 8);

      // Sync only for test device/user
      mockApiService.setOnline(true);
      final syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Should only sync 4 events (for test device/user)
      expect(syncResult.isSuccess, true);
      expect(syncResult.synced, 4);
      expect(mockApiService.capturedDeviceId, testDeviceId);
      expect(mockApiService.capturedUserId, testUserId);

      // Verify other device/user events are still pending
      final remainingPending = await eventQueue.getPendingEvents();
      expect(remainingPending.length, 4);
      expect(remainingPending.first.deviceId, otherDeviceId);
      expect(remainingPending.first.userId, otherUserId);
    });

    test('test_error_handling_during_sync', () async {
      // Queue events
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

      // Simulate API error
      mockApiService.setOnline(true);
      mockApiService.setNextError(Exception('Server error 500'));

      final syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      // Verify sync failed
      expect(syncResult.isSuccess, false);
      expect(syncResult.failed, 4);
      expect(syncResult.synced, 0);
      expect(syncResult.message, contains('Sync failed'));

      // Verify events are still in queue with retry count
      final pendingEvents = await eventQueue.getPendingEvents();
      expect(pendingEvents.length, 4);
      expect(pendingEvents.first.retryCount, 1);
    });

    test('test_sync_handles_empty_event_list', () async {
      mockApiService.setOnline(true);

      final syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      expect(syncResult.isSuccess, true);
      expect(syncResult.synced, 0);
      expect(mockApiService.callCount, 0);
    });

    test('test_sync_handles_different_user_events', () async {
      final otherUserId = const Uuid().v4();

      // Queue events for different user
      final events = createTestWorkoutEvents(
        workoutId: const Uuid().v4(),
        exerciseId: const Uuid().v4(),
        setId: const Uuid().v4(),
      );

      await eventQueue.queueEvents(
        events: events,
        deviceId: testDeviceId,
        userId: otherUserId,
      );

      // Try to sync for test user (should find no events)
      mockApiService.setOnline(true);
      final syncResult = await syncService.syncPendingEvents(
        deviceId: testDeviceId,
        userId: testUserId,
      );

      expect(syncResult.isSuccess, true);
      expect(syncResult.synced, 0);
      expect(syncResult.message, 'No pending events for this device');
      expect(mockApiService.callCount, 0);

      // Events should still be pending for other user
      final pendingEvents = await eventQueue.getPendingEvents();
      expect(pendingEvents.length, 4);
      expect(pendingEvents.first.userId, otherUserId);
    });
  });
}
