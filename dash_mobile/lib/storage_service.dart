import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    await prefs.remove(_pinKey); // legacy 잔존 시 제거
    await prefs.remove(_saltKey);
    // 온보딩·동의·FCM 플래그 초기화 — 재로그인 시 플로우가 다시 시작되어야 함
    await prefs.remove('consent_v1_completed');
    await prefs.remove('consent_marketing');
    await prefs.remove('onboarding_v1_completed');
    await prefs.remove('fcm_permission_asked');
    await _secureStorage.delete(key: _pinKey);
  }

  // [Security] PIN and Vault Salt Management
  static const String _pinKey = 'dash_user_pin';
  static const String _saltKey = 'dash_user_salt';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // 기존 SharedPreferences PIN → Secure Storage 1회 마이그레이션
  static Future<void> migratePinIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyPin = prefs.getString(_pinKey);
    if (legacyPin != null) {
      await _secureStorage.write(key: _pinKey, value: legacyPin);
      await prefs.remove(_pinKey);
    }
  }

  static Future<String?> getPin() async {
    return await _secureStorage.read(key: _pinKey);
  }

  static Future<void> savePin(String pin) async {
    await _secureStorage.write(key: _pinKey, value: pin);
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
