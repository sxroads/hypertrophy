import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hypertrophy/services/api_service.dart';
import 'package:hypertrophy/services/anonymous_user_service.dart';
import 'package:hypertrophy/services/event_queue_service.dart';
import 'package:hypertrophy/services/sync_service.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final ApiService _apiService = ApiService();
  final AnonymousUserService _anonymousUserService = AnonymousUserService();
  final EventQueueService _eventQueueService = EventQueueService();

  String? _token;
  String? _userId;
  String? _email;
  String? _anonymousUserId;
  bool _isAuthenticated = false;

  String? get token => _token;
  String? get userId => _userId;
  String? get email => _email;
  String? get anonymousUserId => _anonymousUserId;
  bool get isAuthenticated => _isAuthenticated;

  AuthService._internal() {
    _initializeAnonymousUser();
    _loadSavedAuth();
  }

  Future<void> _loadSavedAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('auth_token');
      final savedUserId = prefs.getString('user_id');
      final savedEmail = prefs.getString('user_email');

      if (savedToken != null && savedUserId != null) {
        _token = savedToken;
        _userId = savedUserId;
        _email = savedEmail;
        _isAuthenticated = true;

        // If email is missing, fetch it from backend
        if (_email == null && _token != null) {
          try {
            final userInfo = await _apiService.getCurrentUserInfo(
              token: _token!,
            );
            _email = userInfo['email'] as String?;
            if (_email != null) {
              // Save the fetched email
              await prefs.setString('user_email', _email!);
            }
          } catch (e) {
            debugPrint('⚠️ Failed to fetch email from backend: $e');
            // Continue without email - user can still use the app
          }
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load saved auth: $e');
    }
  }

  Future<void> _saveAuth(String token, String userId, String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      await prefs.setString('user_id', userId);
      await prefs.setString('user_email', email);
    } catch (e) {
      debugPrint('⚠️ Failed to save auth: $e');
    }
  }

  Future<void> _clearSavedAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('user_id');
      await prefs.remove('user_email');
    } catch (e) {
      debugPrint('⚠️ Failed to clear saved auth: $e');
    }
  }

  Future<void> _initializeAnonymousUser() async {
    try {
      _anonymousUserId = await _anonymousUserService
          .getOrCreateAnonymousUserId();
    } catch (e) {
      debugPrint('⚠️ Failed to initialize anonymous user: $e');
      // Continue without anonymous user (will retry on next sync)
    }
  }

  /// Get current user ID (authenticated or anonymous)
  Future<String> getCurrentUserId() async {
    if (_isAuthenticated && _userId != null) {
      return _userId!;
    }
    // Return anonymous user ID
    _anonymousUserId ??= await _anonymousUserService
        .getOrCreateAnonymousUserId();
    return _anonymousUserId!;
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiService.register(
        email: email,
        password: password,
      );

      _token = response['token'] as String;
      _userId = response['user_id'] as String;
      _email = email;
      _isAuthenticated = true;

      // Auto-merge anonymous user data if exists
      bool mergeSuccess = false;
      if (_anonymousUserId != null) {
        mergeSuccess = await _mergeAnonymousUser();
      }

      await _saveAuth(_token!, _userId!, _email!);
      notifyListeners();

      return {
        'success': true,
        'mergeSuccess': mergeSuccess,
        'hadAnonymousUser': _anonymousUserId != null,
      };
    } catch (e) {
      debugPrint('❌ Registration failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiService.login(
        email: email,
        password: password,
      );

      _token = response['token'] as String;
      _userId = response['user_id'] as String;
      _email = email;
      _isAuthenticated = true;

      // Auto-merge anonymous user data if exists
      bool mergeSuccess = false;
      final hadAnonymousUser = _anonymousUserId != null;
      if (_anonymousUserId != null) {
        mergeSuccess = await _mergeAnonymousUser();
      }

      await _saveAuth(_token!, _userId!, _email!);
      notifyListeners();

      return {
        'success': true,
        'mergeSuccess': mergeSuccess,
        'hadAnonymousUser': hadAnonymousUser,
      };
    } catch (e) {
      debugPrint('❌ Login failed: $e');
      rethrow;
    }
  }

  /// Merge anonymous user data to real account
  /// Returns true if merge succeeded, false if it failed
  ///
  /// The merge process:
  /// 1. Update local event queue user_ids (anonymous -> real) BEFORE syncing
  /// 2. Force sync all pending events with the new user_id
  /// 3. Call backend merge to transfer any events already on backend
  /// 4. Clear anonymous user ID
  Future<bool> _mergeAnonymousUser() async {
    if (_token == null || _anonymousUserId == null || _userId == null) {
      debugPrint(
        '⚠️ Cannot merge: missing token, anonymous user ID, or user ID',
      );
      return false;
    }

    final oldAnonymousUserId = _anonymousUserId!;
    final newUserId = _userId!;

    try {
      // STEP 1: Update local event queue user_ids BEFORE syncing
      // This ensures events will sync under the new user_id
      try {
        await _eventQueueService.updateUserIdForEvents(
          oldUserId: oldAnonymousUserId,
          newUserId: newUserId,
        );

        // Also reset any failed events so they get a fresh chance to sync
        await _eventQueueService.resetFailedEvents(userId: newUserId);
      } catch (e) {
        debugPrint('⚠️ Failed to update local event queue user_id: $e');
        // Continue - we'll try to merge what's on the backend
      }

      // STEP 2: Force sync all pending events with the new user_id
      // This ensures local workout data reaches the backend before merge
      try {
        final deviceId = await _anonymousUserService.getOrCreateDeviceId();
        final syncService = SyncService();
        await syncService.syncPendingEvents(
          deviceId: deviceId,
          userId: newUserId, // Use new user_id since we updated the queue
        );
      } catch (e) {
        debugPrint('⚠️ Pre-merge sync failed: $e');
        // Continue - we'll still try to merge what's on the backend
      }

      // STEP 3: Call backend merge to transfer any events already on backend
      // This handles events that were synced before login
      await _apiService.mergeUser(
        anonymousUserId: oldAnonymousUserId,
        token: _token!,
      );

      // STEP 4: Clear anonymous user ID after successful merge
      await _anonymousUserService.clearAnonymousUserId();
      _anonymousUserId = null;
      return true;
    } catch (e) {
      debugPrint('❌ Merge failed: $e');
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _userId = null;
    _email = null;
    _isAuthenticated = false;

    // Clear anonymous user ID on logout to ensure clean state
    // A new anonymous user will be created when needed by AuthWrapper
    await _anonymousUserService.clearAnonymousUserId();
    _anonymousUserId = null;

    await _clearSavedAuth();
    notifyListeners();
  }
}
