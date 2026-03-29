import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StorageService {
  static const String _casesKey = 'dash_cases';
  static const String _draftsKey = 'dash_drafts';

  static Future<void> initInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('dash_v1_2_init')) {
      await prefs.setString(_casesKey, jsonEncode([]));
      await prefs.setBool('dash_v1_2_init', true);
    }
  }

  static Future<String> getUserId() async {
    // Firebase Auth에서 현재 로그인한 유저의 UID를 직접 가져옴
    return FirebaseAuth.instance.currentUser?.uid ?? 'GUEST_USER';
  }

  static Future<List<dynamic>> getCases() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_casesKey);
    if (data == null) return [];
    return jsonDecode(data);
  }

  static Future<List<dynamic>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_draftsKey);
    if (data == null) return [];
    return jsonDecode(data);
  }

  static Future<void> saveCases(List<dynamic> cases) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_casesKey, jsonEncode(cases));
  }

  static Future<void> saveDrafts(List<dynamic> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftsKey, jsonEncode(drafts));
  }
  static const String _pendingSyncKey = 'dash_pending_sync';

  static Future<List<dynamic>> getPendingSyncs() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_pendingSyncKey);
    if (data == null) return [];
    return jsonDecode(data);
  }

  static Future<void> savePendingSyncs(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingSyncKey, jsonEncode(data));
  }

  // 로그아웃 또는 계정 탈퇴 시 로컬 캐시 초기화 (다른 계정 로그인 시 데이터 섞임 방지)
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_casesKey);
    await prefs.remove(_draftsKey);
    await prefs.remove(_pendingSyncKey);
    await prefs.remove(_pinKey);
    await prefs.remove(_saltKey);
  }

  // [Security] PIN and Vault Salt Management
  static const String _pinKey = 'dash_user_pin';
  static const String _saltKey = 'dash_user_salt';

  static Future<String?> getPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pinKey);
  }

  static Future<void> savePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, pin);
  }

  static Future<String?> getSalt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_saltKey);
  }

  static Future<void> saveSalt(String salt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saltKey, salt);
  }
}
