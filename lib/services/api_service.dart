import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost:8000';

  Future<Map<String, dynamic>> healthCheck() async {
    final response = await http.get(Uri.parse('$baseUrl/health'));
    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }
    debugPrint('❌ Health check failed: ${response.statusCode}');
    throw Exception('Health check failed');
  }

  Future<Map<String, dynamic>> syncEvents({
    required String deviceId,
    required String userId,
    required List<Map<String, dynamic>> events,
  }) async {
    final requestBody = {
      'device_id': deviceId,
      'user_id': userId,
      'events': events,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/sync'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    debugPrint('❌ Sync failed: ${response.statusCode} - ${response.body}');
    throw Exception('Sync failed: ${response.body}');
  }

  Future<Map<String, dynamic>> rebuildProjections() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/projections/rebuild'),
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    debugPrint('❌ Rebuild failed: ${response.statusCode} - ${response.body}');
    throw Exception('Rebuild failed: ${response.body}');
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
  }) async {
    final requestBody = {'email': email, 'password': password};

    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(requestBody),
    );

    if (response.statusCode == 201) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Register failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Registration failed');
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final requestBody = {'email': email, 'password': password};

    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Login failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Login failed');
  }

  Future<Map<String, dynamic>> createAnonymousUser() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/users/anonymous'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 201) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Create anonymous user failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to create anonymous user');
  }

  Future<Map<String, dynamic>> mergeUser({
    required String anonymousUserId,
    required String token,
  }) async {
    final requestBody = {'anonymous_user_id': anonymousUserId};

    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/users/merge'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Merge failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Merge failed');
  }

  Future<List<Map<String, dynamic>>> getWorkoutHistory({
    required String userId,
    String? token,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/workouts?user_id=$userId'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body) as List;
      return result.cast<Map<String, dynamic>>();
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Get workout history failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to get workout history');
  }

  Future<List<Map<String, dynamic>>> getWorkoutSets({
    required String workoutId,
    String? token,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/workouts/$workoutId/sets'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body) as List;
      return result.cast<Map<String, dynamic>>();
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Get workout sets failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to get workout sets');
  }

  Future<List<Map<String, dynamic>>> getWorkoutSetsBatch({
    required List<String> workoutIds,
    required String userId,
    String? token,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    // Build query string with multiple workout_ids
    final workoutIdsParam = workoutIds.map((id) => 'workout_ids=$id').join('&');
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/workouts/sets/batch?$workoutIdsParam&user_id=$userId'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body) as List;
      return result.cast<Map<String, dynamic>>();
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Get workout sets batch failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to get workout sets batch');
  }

  Future<List<Map<String, dynamic>>> getLastSetsForExercise({
    required String exerciseId,
    required String userId,
    String? token,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final uri = Uri.parse(
      '$baseUrl/api/v1/exercises/$exerciseId/last-sets?user_id=$userId',
    );

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final result = json.decode(response.body) as List;
      return result.cast<Map<String, dynamic>>();
    }

    if (response.statusCode == 404) {
      return [];
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Get last sets failed: ${errorBody['detail']}');
    return [];
  }

  Future<List<Map<String, dynamic>>> getExercises({
    String? muscleCategory,
  }) async {
    final uri = muscleCategory != null
        ? Uri.parse('$baseUrl/api/v1/exercises?muscle_category=$muscleCategory')
        : Uri.parse('$baseUrl/api/v1/exercises');

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body) as List;
      return result.cast<Map<String, dynamic>>();
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Get exercises failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to get exercises');
  }

  Future<Map<String, dynamic>> chatAI({
    required String question,
    required String token,
  }) async {
    final requestBody = {'question': question};

    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/ai/chat'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ AI chat failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to get AI response');
  }

  Future<Map<String, dynamic>> workoutExerciseChat({
    required String exerciseId,
    required String exerciseName,
    required String question,
    required String token,
  }) async {
    final requestBody = {
      'exercise_id': exerciseId,
      'exercise_name': exerciseName,
      'question': question,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/ai/workout-exercise/chat'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Workout exercise chat failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to get AI response');
  }

  Future<Map<String, dynamic>> getWeeklyReport({
    required String userId,
    String? token,
    String? weekStart,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final uri = weekStart != null
        ? Uri.parse(
            '$baseUrl/api/v1/reports/weekly?user_id=$userId&week_start=$weekStart',
          )
        : Uri.parse('$baseUrl/api/v1/reports/weekly?user_id=$userId');

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Get weekly report failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to get weekly report');
  }

  Future<Map<String, dynamic>> regenerateWeeklyReport({
    required String userId,
    String? token,
    String? weekStart,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final uri = weekStart != null
        ? Uri.parse(
            '$baseUrl/api/v1/reports/weekly/regenerate?user_id=$userId&week_start=$weekStart',
          )
        : Uri.parse(
            '$baseUrl/api/v1/reports/weekly/regenerate?user_id=$userId',
          );

    final response = await http.post(uri, headers: headers);

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Regenerate weekly report failed: ${errorBody['detail']}');
    throw Exception(
      errorBody['detail'] ?? 'Failed to regenerate weekly report',
    );
  }

  Future<Map<String, dynamic>> getCurrentUserInfo({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/users/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Get user info failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to get user info');
  }

  Future<Map<String, dynamic>> updateUserProfile({
    required String token,
    String? gender,
    int? age,
  }) async {
    final requestBody = <String, dynamic>{};
    if (gender != null) requestBody['gender'] = gender;
    if (age != null) requestBody['age'] = age;

    final response = await http.put(
      Uri.parse('$baseUrl/api/v1/users/me/profile'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Update user profile failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to update user profile');
  }

  Future<Map<String, dynamic>> createBodyMeasurement({
    required String token,
    required DateTime measuredAt,
    required double heightCm,
    required double weightKg,
    required double neckCm,
    required double waistCm,
    double? hipCm,
    double? chestCm,
    double? shoulderCm,
    double? bicepCm,
    double? forearmCm,
    double? thighCm,
    double? calfCm,
  }) async {
    final requestBody = {
      'measured_at': measuredAt.toIso8601String(),
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'neck_cm': neckCm,
      'waist_cm': waistCm,
      if (hipCm != null) 'hip_cm': hipCm,
      if (chestCm != null) 'chest_cm': chestCm,
      if (shoulderCm != null) 'shoulder_cm': shoulderCm,
      if (bicepCm != null) 'bicep_cm': bicepCm,
      if (forearmCm != null) 'forearm_cm': forearmCm,
      if (thighCm != null) 'thigh_cm': thighCm,
      if (calfCm != null) 'calf_cm': calfCm,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/measurements'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode == 201) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Create body measurement failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to create body measurement');
  }

  Future<List<Map<String, dynamic>>> getBodyMeasurements({
    required String userId,
    String? token,
    int? limit,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final uri = limit != null
        ? Uri.parse('$baseUrl/api/v1/measurements?user_id=$userId&limit=$limit')
        : Uri.parse('$baseUrl/api/v1/measurements?user_id=$userId');

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final result = json.decode(response.body) as List;
      return result.cast<Map<String, dynamic>>();
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Get body measurements failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to get body measurements');
  }

  Future<Map<String, dynamic>> getLatestBodyMeasurement({
    required String userId,
    String? token,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final uri = Uri.parse(
      '$baseUrl/api/v1/measurements/latest?user_id=$userId',
    );

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    if (response.statusCode == 404) {
      throw Exception('No measurements found');
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Get latest body measurement failed: ${errorBody['detail']}');
    throw Exception(
      errorBody['detail'] ?? 'Failed to get latest body measurement',
    );
  }

  Future<Map<String, dynamic>> updateBodyMeasurement({
    required String measurementId,
    required String token,
    DateTime? measuredAt,
    double? heightCm,
    double? weightKg,
    double? neckCm,
    double? waistCm,
    double? hipCm,
    double? chestCm,
    double? shoulderCm,
    double? bicepCm,
    double? forearmCm,
    double? thighCm,
    double? calfCm,
  }) async {
    final requestBody = <String, dynamic>{};
    if (measuredAt != null)
      requestBody['measured_at'] = measuredAt.toIso8601String();
    if (heightCm != null) requestBody['height_cm'] = heightCm;
    if (weightKg != null) requestBody['weight_kg'] = weightKg;
    if (neckCm != null) requestBody['neck_cm'] = neckCm;
    if (waistCm != null) requestBody['waist_cm'] = waistCm;
    if (hipCm != null) requestBody['hip_cm'] = hipCm;
    if (chestCm != null) requestBody['chest_cm'] = chestCm;
    if (shoulderCm != null) requestBody['shoulder_cm'] = shoulderCm;
    if (bicepCm != null) requestBody['bicep_cm'] = bicepCm;
    if (forearmCm != null) requestBody['forearm_cm'] = forearmCm;
    if (thighCm != null) requestBody['thigh_cm'] = thighCm;
    if (calfCm != null) requestBody['calf_cm'] = calfCm;

    final response = await http.put(
      Uri.parse('$baseUrl/api/v1/measurements/$measurementId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Update body measurement failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to update body measurement');
  }

  Future<void> deleteBodyMeasurement({
    required String measurementId,
    required String token,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/measurements/$measurementId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 204) {
      return;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Delete body measurement failed: ${errorBody['detail']}');
    throw Exception(errorBody['detail'] ?? 'Failed to delete body measurement');
  }

  Future<Map<String, dynamic>> getBodyMeasurementReport({
    required String measurementId,
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/measurements/$measurementId/report'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      return result;
    }

    final errorBody = json.decode(response.body);
    debugPrint('❌ Get body measurement report failed: ${errorBody['detail']}');
    throw Exception(
      errorBody['detail'] ?? 'Failed to get body measurement report',
    );
  }
}
