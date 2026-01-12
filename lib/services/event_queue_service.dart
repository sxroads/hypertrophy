import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:hypertrophy/services/database/event_queue_db.dart';

class QueuedEvent {
  final int? id;
  final String eventId;
  final String eventType;
  final Map<String, dynamic> payload;
  final int sequenceNumber;
  final String deviceId;
  final String userId;
  final int createdAt;
  final int retryCount;
  final String status;

  QueuedEvent({
    this.id,
    required this.eventId,
    required this.eventType,
    required this.payload,
    required this.sequenceNumber,
    required this.deviceId,
    required this.userId,
    required this.createdAt,
    this.retryCount = 0,
    this.status = 'pending',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'event_id': eventId,
      'event_type': eventType,
      'payload': json.encode(payload),
      'sequence_number': sequenceNumber,
      'device_id': deviceId,
      'user_id': userId,
      'created_at': createdAt,
      'retry_count': retryCount,
      'status': status,
    };
  }

  factory QueuedEvent.fromMap(Map<String, dynamic> map) {
    return QueuedEvent(
      id: map['id'] as int?,
      eventId: map['event_id'] as String,
      eventType: map['event_type'] as String,
      payload: json.decode(map['payload'] as String) as Map<String, dynamic>,
      sequenceNumber: map['sequence_number'] as int,
      deviceId: map['device_id'] as String,
      userId: map['user_id'] as String,
      createdAt: map['created_at'] as int,
      retryCount: map['retry_count'] as int,
      status: map['status'] as String,
    );
  }

  Map<String, dynamic> toSyncFormat() {
    return {
      'event_id': eventId,
      'event_type': eventType,
      'payload': payload,
      'sequence_number': sequenceNumber,
    };
  }
}

class EventQueueService {
  static final EventQueueService _instance = EventQueueService._internal();
  factory EventQueueService() => _instance;
  EventQueueService._internal();

  /// Queue multiple events in a batch
  Future<void> queueEvents({
    required List<Map<String, dynamic>> events,
    required String deviceId,
    required String userId,
  }) async {
    final db = await EventQueueDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final batch = db.batch();

    for (final eventData in events) {
      final event = QueuedEvent(
        eventId: eventData['event_id'] as String,
        eventType: eventData['event_type'] as String,
        payload: eventData['payload'] as Map<String, dynamic>,
        sequenceNumber: eventData['sequence_number'] as int,
        deviceId: deviceId,
        userId: userId,
        createdAt: now,
      );

      batch.insert(
        'event_queue',
        event.toMap(),
        conflictAlgorithm: ConflictAlgorithm
            .replace, // Replace existing event if it exists (idempotency)
      );
    }

    await batch.commit(noResult: true);
  }

  /// Get all pending events ordered by device_id and sequence_number
  Future<List<QueuedEvent>> getPendingEvents() async {
    final db = await EventQueueDb.database;
    final maps = await db.query(
      'event_queue',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'device_id, sequence_number ASC',
    );

    return maps.map((map) => QueuedEvent.fromMap(map)).toList();
  }

  /// Get pending events for a specific device and user
  /// More efficient than getting all events and filtering in memory
  Future<List<QueuedEvent>> getPendingEventsForDevice({
    required String deviceId,
    required String userId,
  }) async {
    final db = await EventQueueDb.database;
    final maps = await db.query(
      'event_queue',
      where: 'status = ? AND device_id = ? AND user_id = ?',
      whereArgs: ['pending', deviceId, userId],
      orderBy: 'sequence_number ASC',
    );

    return maps.map((map) => QueuedEvent.fromMap(map)).toList();
  }

  /// Mark events as syncing (before attempting sync)
  Future<void> markEventsSyncing(List<String> eventIds) async {
    final db = await EventQueueDb.database;
    final batch = db.batch();

    for (final eventId in eventIds) {
      batch.update(
        'event_queue',
        {'status': 'syncing'},
        where: 'event_id = ?',
        whereArgs: [eventId],
      );
    }

    await batch.commit(noResult: true);
  }

  /// Mark events as synced (remove from queue)
  Future<void> markEventsSynced(List<String> eventIds) async {
    final db = await EventQueueDb.database;
    final batch = db.batch();

    for (final eventId in eventIds) {
      batch.delete('event_queue', where: 'event_id = ?', whereArgs: [eventId]);
    }

    await batch.commit(noResult: true);
  }

  /// Mark events as failed (increment retry count)
  Future<void> markEventsFailed(List<String> eventIds) async {
    if (eventIds.isEmpty) return;

    final db = await EventQueueDb.database;
    final batch = db.batch();

    // Batch query all events in one query (fixes N+1)
    final placeholders = eventIds.map((_) => '?').join(',');
    final events = await db.rawQuery(
      'SELECT event_id, retry_count FROM event_queue WHERE event_id IN ($placeholders)',
      eventIds,
    );

    // Create a map for quick lookup
    final eventMap = <String, int>{};
    for (final event in events) {
      eventMap[event['event_id'] as String] = event['retry_count'] as int;
    }

    // Update events in batch
    for (final eventId in eventIds) {
      final currentRetryCount = eventMap[eventId] ?? 0;
      final newStatus = currentRetryCount >= 5 ? 'failed' : 'pending';

      batch.update(
        'event_queue',
        {'status': newStatus, 'retry_count': currentRetryCount + 1},
        where: 'event_id = ?',
        whereArgs: [eventId],
      );
    }

    await batch.commit(noResult: true);
  }

  /// Update user_id for all events with the old user_id
  /// This is used when merging anonymous user to real user account
  /// Updates ALL events regardless of status (pending, syncing, failed)
  Future<int> updateUserIdForEvents({
    required String oldUserId,
    required String newUserId,
  }) async {
    final db = await EventQueueDb.database;

    // Update ALL events with old user_id to new user_id
    // Include all statuses to ensure no events are left orphaned
    final result = await db.update(
      'event_queue',
      {'user_id': newUserId},
      where: 'user_id = ?',
      whereArgs: [oldUserId],
    );

    return result;
  }

  /// Reset failed events back to pending status for retry
  /// Also resets retry_count to give them fresh attempts
  Future<int> resetFailedEvents({String? userId}) async {
    final db = await EventQueueDb.database;

    if (userId != null) {
      return await db.update(
        'event_queue',
        {'status': 'pending', 'retry_count': 0},
        where: 'status = ? AND user_id = ?',
        whereArgs: ['failed', userId],
      );
    } else {
      return await db.update(
        'event_queue',
        {'status': 'pending', 'retry_count': 0},
        where: 'status = ?',
        whereArgs: ['failed'],
      );
    }
  }

  /// Get queue statistics
  Future<Map<String, int>> getQueueStats() async {
    final db = await EventQueueDb.database;
    final pending =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM event_queue WHERE status = ?',
            ['pending'],
          ),
        ) ??
        0;

    final syncing =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM event_queue WHERE status = ?',
            ['syncing'],
          ),
        ) ??
        0;

    final failed =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM event_queue WHERE status = ?',
            ['failed'],
          ),
        ) ??
        0;

    return {
      'pending': pending,
      'syncing': syncing,
      'failed': failed,
      'total': pending + syncing + failed,
    };
  }
}
