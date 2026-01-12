import 'package:flutter/foundation.dart';
import 'package:hypertrophy/services/event_queue_service.dart';
import 'package:hypertrophy/services/api_service.dart';

/// Singleton service for syncing local events to backend
/// Handles idempotent event sync with retry logic and state management
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final EventQueueService _eventQueue = EventQueueService();
  final ApiService _apiService = ApiService();
  // Prevents concurrent sync operations
  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

  /// Sync all pending events to the backend
  /// Implements idempotent sync with retry logic and state tracking
  Future<SyncResult> syncPendingEvents({
    required String deviceId,
    required String userId,
  }) async {
    // Prevent concurrent sync operations
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
      // Get pending events for this device and user from local queue
      final deviceEvents = await _eventQueue.getPendingEventsForDevice(
        deviceId: deviceId,
        userId: userId,
      );

      if (deviceEvents.isEmpty) {
        _isSyncing = false;
        return SyncResult(
          synced: 0,
          failed: 0,
          isSuccess: true,
          message: 'No pending events for this device',
        );
      }

      // Convert events to sync format and extract IDs for tracking
      final eventsToSync = deviceEvents.map((e) => e.toSyncFormat()).toList();
      final eventIds = deviceEvents.map((e) => e.eventId).toList();

      // Mark events as syncing to prevent duplicate processing
      await _eventQueue.markEventsSyncing(eventIds);

      try {
        // Send events to backend API (idempotent on server side)
        await _apiService.syncEvents(
          deviceId: deviceId,
          userId: userId,
          events: eventsToSync,
        );

        // Remove successfully synced events from local queue
        await _eventQueue.markEventsSynced(eventIds);

        _isSyncing = false;

        return SyncResult(
          synced: eventIds.length,
          failed: 0,
          isSuccess: true,
          message: 'Synced ${eventIds.length} events',
        );
      } catch (e) {
        // Mark as failed for retry on next sync attempt
        await _eventQueue.markEventsFailed(eventIds);

        debugPrint('❌ Failed to sync events: $e');
        _isSyncing = false;

        return SyncResult(
          synced: 0,
          failed: eventIds.length,
          isSuccess: false,
          message: 'Sync failed: $e',
        );
      }
    } catch (e) {
      debugPrint('❌ Error during sync: $e');
      _isSyncing = false;
      return SyncResult(
        synced: 0,
        failed: 0,
        isSuccess: false,
        message: 'Sync error: $e',
      );
    }
  }

  /// Sync when app comes to foreground
  Future<SyncResult> syncOnForeground({
    required String deviceId,
    required String userId,
  }) async {
    return await syncPendingEvents(deviceId: deviceId, userId: userId);
  }
}

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
