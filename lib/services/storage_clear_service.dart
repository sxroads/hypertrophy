import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:hypertrophy/services/database/event_queue_db.dart';
import 'package:hypertrophy/services/database/templates_db.dart';
import 'package:hypertrophy/services/database/ai_reports_db.dart';

/// Service to clear all local storage (SharedPreferences and SQLite databases)
class StorageClearService {
  /// Clear all local storage data
  /// This includes:
  /// - All SharedPreferences (auth tokens, user IDs, anonymous user IDs, device IDs)
  /// - All SQLite databases (event_queue.db, templates.db)
  static Future<void> clearAllLocalData() async {
    try {
      // Clear SharedPreferences
      await _clearSharedPreferences();

      // Clear SQLite databases
      await _clearSqliteDatabases();
    } catch (e) {
      debugPrint('❌ Error clearing local storage: $e');
      rethrow;
    }
  }

  /// Clear all SharedPreferences
  static Future<void> _clearSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // List of all keys that might be stored
      final keysToRemove = [
        'auth_token',
        'user_id',
        'user_email',
        'anonymous_user_id',
        'device_id',
      ];

      for (final key in keysToRemove) {
        await prefs.remove(key);
      }

      // Also clear all preferences (more thorough)
      await prefs.clear();
    } catch (e) {
      debugPrint('⚠️ Error clearing SharedPreferences: $e');
      rethrow;
    }
  }

  /// Clear all SQLite databases
  static Future<void> _clearSqliteDatabases() async {
    try {
      // Clear event_queue database
      try {
        final eventDb = await EventQueueDb.database;
        await eventDb.execute('DELETE FROM event_queue');
      } catch (e) {
        debugPrint('⚠️ Error clearing event_queue: $e');
        // Try to delete the database file directly
        try {
          final dbPath = await getDatabasesPath();
          final path = join(dbPath, 'event_queue.db');
          await databaseFactory.deleteDatabase(path);
        } catch (e2) {
          debugPrint('⚠️ Could not delete event_queue.db: $e2');
        }
      }

      // Clear templates database (delete in order due to foreign keys)
      try {
        final templatesDb = await TemplatesDb.database;
        // Delete sets first (has foreign key to exercises)
        await templatesDb.execute('DELETE FROM template_sets');
        // Delete exercises (has foreign key to templates)
        await templatesDb.execute('DELETE FROM template_exercises');
        // Delete templates
        await templatesDb.execute('DELETE FROM workout_templates');
      } catch (e) {
        debugPrint('⚠️ Error clearing templates: $e');
        // Try to delete the database file directly
        try {
          final dbPath = await getDatabasesPath();
          final path = join(dbPath, 'templates.db');
          await databaseFactory.deleteDatabase(path);
        } catch (e2) {
          debugPrint('⚠️ Could not delete templates.db: $e2');
        }
      }

      // Clear AI reports database
      try {
        final aiReportsDb = await AiReportsDb.database;
        await aiReportsDb.execute('DELETE FROM ai_reports');
      } catch (e) {
        debugPrint('⚠️ Error clearing ai_reports: $e');
        // Try to delete the database file directly
        try {
          final dbPath = await getDatabasesPath();
          final path = join(dbPath, 'ai_reports.db');
          await databaseFactory.deleteDatabase(path);
        } catch (e2) {
          debugPrint('⚠️ Could not delete ai_reports.db: $e2');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error clearing SQLite databases: $e');
      rethrow;
    }
  }
}
