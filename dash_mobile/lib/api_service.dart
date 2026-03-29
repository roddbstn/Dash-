import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dash_mobile/storage_service.dart';

class ApiService {
  // --- Deployment Settings ---
  static const bool isProduction = true; // 🚀 Set to true for Final Launch!

  // Production: Enter your Cloud Domain here (e.g. railway/supabase url)
  static const String prodUrl = 'https://dash-production-3aba.up.railway.app';
  
  // Local (Android Emulator 10.0.2.2 points to localhost:3000)
  static const String localUrl = 'http://10.0.2.2:3000';

  static String get baseUrl => isProduction ? '$prodUrl/api' : '$localUrl/api';
  static String get serverUrl => isProduction ? prodUrl : localUrl;

  static Future<void> checkHealth() async {
    try {
      final response = await http.get(Uri.parse('$serverUrl/health'));
      print('🚀 Health Check: ${response.statusCode} - ${response.body}');
    } catch (e) {
      print('❌ Health Check Error: $e');
    }
  }

  static Future<void> syncCase(Map<String, dynamic> caseData) async {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid;
    if (userId == null) return;
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/cases'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': caseData['id'],
          'user_id': userId,
          'user_email': user?.email,
          'user_name': user?.displayName,
          'case_name': caseData['maskedName'] ?? caseData['realName'],
          'dong': caseData['dong'],
          'target_system_code': 'NCADS_v2',
        }),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        print('✅ Case synchronized with server');
      } else {
        print('❌ Failed to sync case: ${response.body}');
      }
    } catch (e) {
      print('❌ Error syncing case: $e');
    }
  }

  static Future<String?> syncRecord(Map<String, dynamic> recordData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(recordData),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Record synchronized with server');
        return data['share_token'];
      } else {
        print('❌ Failed to sync record: ${response.body}');
      }
    } catch (e) {
      print('❌ Error syncing record: $e');
    }
    return null;
  }

  static Future<void> deleteRecord(String token) async {
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/records/token/$token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_email': userEmail}),
      );
      if (response.statusCode == 200) {
        print('🗑️ Record deleted from server');
      } else {
        print('❌ Failed to delete record: ${response.body}');
      }
    } catch (e) {
      print('❌ Error deleting record: $e');
    }
  }

  static Future<void> syncActiveRecords(List<String> activeTokens) async {
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    if (userEmail == null) return;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/records/sync_active'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_email': userEmail, 'active_tokens': activeTokens}),
      );
      if (response.statusCode == 200) {
        print('🔄 Active records sync complete');
      } else {
        print('❌ Active sync failed: ${response.body}');
      }
    } catch (e) {
      print('❌ Active sync error: $e');
    }
  }

  static Future<List<dynamic>> fetchRecords() async {
    final userId = await StorageService.getUserId();
    if (userId == null) return [];
    try {
      final response = await http.get(Uri.parse('$baseUrl/records/user/$userId'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('❌ Error fetching records: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> fetchUser(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/users/$userId'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('❌ Error fetching user: $e');
    }
    return null;
  }

  static Future<bool> updateUserProfile(String userId, String name, String? email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/update_profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': userId, 'name': name, 'email': email}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Error updating profile: $e');
      return false;
    }
  }

  static Future<List<dynamic>> fetchNotifications(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/notifications/$userId'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('❌ Error fetching notifications: $e');
    }
    return [];
  }

  static Future<void> markNotificationRead(int notifId) async {
    try {
      await http.put(Uri.parse('$baseUrl/notifications/$notifId/read'));
    } catch (e) {
      print('❌ Error marking notification read: $e');
    }
  }

  static Future<void> saveFcmToken(String userId, String token, String? email) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/users/fcm_token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': userId, 'token': token, 'email': email}),
      );
    } catch (e) {
      print('❌ Error saving FCM token: $e');
    }
  }

  // [Security] Vault sync for E2EE keys
  static Future<Map<String, dynamic>?> fetchVault(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/users/vault/$userId'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('❌ Error fetching vault: $e');
    }
    return null;
  }

  static Future<void> saveVault(String userId, String encryptedVault, String? salt) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/users/vault'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'encrypted_vault': encryptedVault,
          'salt': salt,
        }),
      );
    } catch (e) {
      print('❌ Error saving vault: $e');
    }
  }

  // [Security] Delete user data (PIPL Compliance)
  static Future<bool> deleteUser(String userId, {String? email}) async {
    try {
      final uri = Uri.parse('$baseUrl/users/$userId').replace(
        queryParameters: email != null ? {'email': email} : null,
      );
      final response = await http.delete(uri);
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Error deleting user: $e');
      return false;
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
          print('🔔 SSE Reconnect loop: $e');
        }
      } finally {
        client.close();
      }

      // Exponential backoff
      await Future.delayed(Duration(seconds: backoffSeconds));
      backoffSeconds = (backoffSeconds * 2).clamp(2, maxBackoff);
      
      // Heartbeat pulse instead of noisy reconnect log
      if (backoffSeconds < 10) {
        print('🔄 SSE Reconnecting for: $email');
      }
    }
  }
}
