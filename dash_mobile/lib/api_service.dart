import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dash_mobile/storage_service.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  // --- Deployment Settings ---
  static const bool isProduction = true; // 🚀 Set to true for Final Launch!
  static const String prodUrl = 'https://dash.qpon';
  static const String localUrl = 'http://10.0.2.2:3000';
  static String get baseUrl => isProduction ? '$prodUrl/api' : '$localUrl/api';
  static String get serverUrl => isProduction ? prodUrl : localUrl;

  /// Firebase ID Token을 포함한 인증 헤더 반환 (JSON 요청용)
  /// [forceRefresh] true이면 캐시 토큰 무시하고 새 토큰 발급
  static Future<Map<String, String>> _authHeaders({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('⚠️ _authHeaders: currentUser is null (not logged in)');
      return {'Content-Type': 'application/json'};
    }
    try {
      final token = await user.getIdToken(forceRefresh);
      return {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
    } catch (e) {
      debugPrint('⚠️ _authHeaders: getIdToken failed ($e), retrying with forceRefresh...');
      try {
        final token = await user.getIdToken(true);
        return {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        };
      } catch (e2) {
        debugPrint('❌ _authHeaders: token refresh failed: $e2');
        return {'Content-Type': 'application/json'};
      }
    }
  }

  /// Firebase ID Token을 포함한 인증 헤더 반환 (GET/DELETE 요청용 — Content-Type 없음)
  static Future<Map<String, String>> _authGetHeaders({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};
    try {
      final token = await user.getIdToken(forceRefresh);
      return {if (token != null) 'Authorization': 'Bearer $token'};
    } catch (e) {
      try {
        final token = await user.getIdToken(true);
        return {if (token != null) 'Authorization': 'Bearer $token'};
      } catch (_) {
        return {};
      }
    }
  }

  static Future<void> checkHealth() async {
    try {
      final response = await http.get(Uri.parse('$serverUrl/health'));
      debugPrint('🚀 Health Check: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('❌ Health Check Error: $e');
    }
  }

  static Future<void> syncCase(Map<String, dynamic> caseData) async {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid;
    if (userId == null) return;

    // DASH 서버 프로필 이름 우선 사용 (Firebase displayName은 구글 계정 원래 이름이므로
    // 앱에서 닉네임을 바꿔도 반영 안 됨)
    final serverUser = await fetchUser(userId);
    final userName = serverUser?['name'] ?? user?.displayName;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/cases'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'id': caseData['id'],
          'user_id': userId,
          'user_email': user?.email,
          'user_name': userName,
          'case_name': caseData['maskedName'] ?? caseData['realName'],
          'dong': caseData['dong'],
          'target_system_code': 'NCADS_v2',
          if (caseData['counselor_id'] != null)
            'counselor_id': caseData['counselor_id'],
        }),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        debugPrint('✅ Case synchronized with server');
      } else {
        debugPrint('❌ Failed to sync case: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error syncing case: $e');
    }
  }

  static Future<String?> syncRecord(Map<String, dynamic> recordData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: await _authHeaders(),
        body: jsonEncode(recordData),
      ).timeout(const Duration(seconds: 8));

      debugPrint('📡 syncRecord status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Record synchronized with server');
        return data['share_token'];
      }

      // 401/403: 토큰이 만료됐을 수 있음 — 강제 갱신 후 1회 재시도
      if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('🔄 Auth error (${response.statusCode}), retrying with fresh token...');
        final retryResponse = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: await _authHeaders(forceRefresh: true),
          body: jsonEncode(recordData),
        ).timeout(const Duration(seconds: 8));
        debugPrint('📡 syncRecord retry status: ${retryResponse.statusCode}');
        if (retryResponse.statusCode == 200 || retryResponse.statusCode == 201) {
          final data = jsonDecode(retryResponse.body);
          debugPrint('✅ Record synchronized with server (after token refresh)');
          return data['share_token'];
        }
        debugPrint('❌ Auth retry failed: ${retryResponse.body}');
      } else {
        debugPrint('❌ Failed to sync record (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error syncing record: $e');
    }
    return null;
  }

  /// PIN 리셋 전용 — 서버의 해당 사용자 레코드 전체 삭제
  static Future<void> deleteAllRecords() async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/records/user/all'),
        headers: await _authHeaders(),
        body: jsonEncode({'confirmation': 'CONFIRM_RESET'}),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        debugPrint('🗑️ All records deleted from server (PIN reset)');
      } else {
        debugPrint('❌ Failed to delete all records: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error deleting all records: $e');
    }
  }

  static Future<void> deleteRecord(String token) async {
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/records/token/$token'),
        headers: await _authHeaders(),
        body: jsonEncode({'user_email': userEmail}),
      );
      if (response.statusCode == 200) {
        debugPrint('🗑️ Record deleted from server');
      } else {
        debugPrint('❌ Failed to delete record: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error deleting record: $e');
    }
  }

  static Future<bool> removeSharedRecord(String recordId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/records/shared/$recordId'),
        headers: await _authHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error removing shared record: $e');
      return false;
    }
  }

  static Future<void> syncActiveRecords(List<String> activeTokens) async {
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    if (userEmail == null) return;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/records/sync_active'),
        headers: await _authHeaders(),
        body: jsonEncode({'user_email': userEmail, 'active_tokens': activeTokens}),
      );
      if (response.statusCode == 200) {
        debugPrint('🔄 Active records sync complete');
      } else {
        debugPrint('❌ Active sync failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Active sync error: $e');
    }
  }

  static Future<List<dynamic>?> fetchRecords() async {
    final userId = await StorageService.getUserId();
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/records/user/$userId'),
        headers: await _authGetHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('❌ Error fetching records: $e');
    }
    return null; // null = 서버 통신 실패, [] = 서버 응답은 성공이나 레코드 없음
  }

  static Future<List<dynamic>?> fetchCases(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/cases/user/$userId'),
        headers: await _authGetHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('❌ Error fetching cases: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> fetchUser(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/$userId'),
        headers: await _authGetHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('❌ Error fetching user: $e');
    }
    return null;
  }

  static Future<bool> updateUserProfile(String userId, String name, String? email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/update_profile'),
        headers: await _authHeaders(),
        body: jsonEncode({'id': userId, 'name': name, 'email': email}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error updating profile: $e');
      return false;
    }
  }

  static Future<List<dynamic>> fetchNotifications(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/notifications/$userId'),
        headers: await _authGetHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('❌ Error fetching notifications: $e');
    }
    return [];
  }

  static Future<void> markNotificationRead(int notifId) async {
    try {
      await http.put(
        Uri.parse('$baseUrl/notifications/$notifId/read'),
        headers: await _authGetHeaders(),
      );
    } catch (e) {
      debugPrint('❌ Error marking notification read: $e');
    }
  }

  static Future<void> saveFcmToken(String userId, String token, String? email) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/users/fcm_token'),
        headers: await _authHeaders(),
        body: jsonEncode({'id': userId, 'token': token, 'email': email}),
      );
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }

  // [Security] Vault sync for E2EE keys
  static Future<Map<String, dynamic>?> fetchVault(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/vault/$userId'),
        headers: await _authGetHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('❌ Error fetching vault: $e');
    }
    return null;
  }

  static Future<void> saveVault(String userId, String encryptedVault, String? salt) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/users/vault'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'user_id': userId,
          'encrypted_vault': encryptedVault,
          'salt': salt,
        }),
      );
    } catch (e) {
      debugPrint('❌ Error saving vault: $e');
    }
  }

  // [Share] 공유 링크 만료 설정 (null = 무제한)
  static Future<bool> setShareExpiry(String recordId, int? expiresDays) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/records/$recordId/share-expiry'),
        headers: await _authHeaders(),
        body: jsonEncode({'expires_days': expiresDays}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error setting share expiry: $e');
      return false;
    }
  }

  // [Security] Delete user data (PIPL Compliance)
  static Future<bool> deleteUser(String userId, {String? email}) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$userId').replace(
        queryParameters: email != null ? {'email': email} : null,
      );
      final response = await http.delete(uri, headers: await _authGetHeaders());
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error deleting user: $e');
      return false;
    }
  }

  // [Counselors] 상담원 목록 조회
  static Future<List<dynamic>?> fetchCounselors(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/counselors/$userId'),
        headers: await _authGetHeaders(),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (e) {
      debugPrint('❌ Error fetching counselors: $e');
    }
    return null;
  }

  static Future<bool> syncCounselor(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/counselors'),
        headers: await _authHeaders(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 8));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('❌ Error syncing counselor: $e');
      return false;
    }
  }

  static Future<bool> deleteCounselor(String counselorId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/counselors/$counselorId'),
        headers: await _authGetHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error deleting counselor: $e');
      return false;
    }
  }

  static Future<void> reorderCounselors(List<dynamic> counselors) async {
    try {
      await http.put(
        Uri.parse('$baseUrl/counselors/reorder'),
        headers: await _authHeaders(),
        body: jsonEncode({'counselors': counselors.asMap().entries.map((e) => {'id': e.value['id'], 'sort_order': e.key}).toList()}),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('❌ Error reordering counselors: $e');
    }
  }

  // Real-time Event Listener (SSE) with Exponential Backoff
  static Stream<Map<String, dynamic>> streamEvents(String email) async* {
    int backoffSeconds = 2;
    const int maxBackoff = 60;

    while (true) {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse('$baseUrl/events?email=$email'));
        request.headers['Accept'] = 'text/event-stream';
        request.headers['Cache-Control'] = 'no-cache';
        request.headers['Connection'] = 'keep-alive';
        // 로그인 직후 토큰이 아직 준비 안 됐으면 최대 3초 대기
        String? token;
        for (int i = 0; i < 3 && token == null; i++) {
          token = await FirebaseAuth.instance.currentUser?.getIdToken();
          if (token == null) await Future.delayed(const Duration(seconds: 1));
        }
        if (token != null) request.headers['Authorization'] = 'Bearer $token';

        final response = await client.send(request).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          backoffSeconds = 2; // Reset on success
          await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
            if (line.startsWith('data: ')) {
              final jsonStr = line.substring(6).trim();
              if (jsonStr.isNotEmpty) {
                yield jsonDecode(jsonStr) as Map<String, dynamic>;
              }
            }
          }
        }
      } catch (e) {
        // Log more cleanly for frequent network errors
        if (e.toString().contains('Failed host lookup') || e.toString().contains('SocketException')) {
          // No need to print full stack trace for known offline/background state
        } else {
          debugPrint('🔔 SSE Reconnect loop: $e');
        }
      } finally {
        client.close();
      }

      // Exponential backoff
      await Future.delayed(Duration(seconds: backoffSeconds));
      backoffSeconds = (backoffSeconds * 2).clamp(2, maxBackoff);
      
      // Heartbeat pulse instead of noisy reconnect log
      if (backoffSeconds < 10) {
        debugPrint('🔄 SSE Reconnecting for: $email');
      }
    }
  }
}
