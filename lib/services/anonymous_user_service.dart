import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:hypertrophy/services/api_service.dart';

const _uuid = Uuid();

class AnonymousUserService {
  static const String _anonymousUserIdKey = 'anonymous_user_id';
  static const String _deviceIdKey = 'device_id';

  final ApiService _apiService = ApiService();

  /// Get or create anonymous user ID (stored locally)
  Future<String> getOrCreateAnonymousUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? anonymousUserId = prefs.getString(_anonymousUserIdKey);

    if (anonymousUserId != null) {
      debugPrint('📱 Found existing anonymous user ID: $anonymousUserId');
      return anonymousUserId;
    }

    // Create new anonymous user
    debugPrint('📱 Creating new anonymous user...');
    try {
      final response = await _apiService.createAnonymousUser();
      anonymousUserId = response['user_id'] as String;

      // Store locally
      await prefs.setString(_anonymousUserIdKey, anonymousUserId);
      debugPrint('✅ Anonymous user created and stored: $anonymousUserId');

      return anonymousUserId;
    } catch (e) {
      debugPrint('❌ Failed to create anonymous user: $e');
      // Fallback: generate a UUID locally (will need to be created on server later)
      // For now, throw error - user needs network connection
      rethrow;
    }
  }

  /// Get or create device ID (stored locally)
  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId != null) {
      return deviceId;
    }

    // Generate new device ID (UUID v4 format)
    deviceId = _uuid.v4();
    await prefs.setString(_deviceIdKey, deviceId);
    debugPrint('📱 Generated new device ID: $deviceId');

    return deviceId;
  }

  /// Get stored anonymous user ID (returns null if not exists)
  Future<String?> getAnonymousUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_anonymousUserIdKey);
  }

  /// Clear anonymous user ID (after successful merge)
  Future<void> clearAnonymousUserId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_anonymousUserIdKey);
    debugPrint('🗑️ Cleared anonymous user ID');
  }
}

