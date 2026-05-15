import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StorageService {
  static const String _casesKey = 'dash_cases';
  static const String _draftsKey = 'dash_drafts';
  static const String _counselorsKey = 'dash_counselors';

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

  static Future<List<dynamic>> getCounselors() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_counselorsKey);
    if (data == null) return [];
    return jsonDecode(data);
  }

  static Future<void> saveCounselors(List<dynamic> counselors) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_counselorsKey, jsonEncode(counselors));
  }

  static Future<void> saveDrafts(List<dynamic> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftsKey, jsonEncode(drafts));
  }
  static const String _pendingSyncKey = 'dash_pending_sync';
  static const String _pendingVaultKeysKey = 'dash_pending_vault_keys';

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

  static Future<List<Map<String, String>>> getPendingVaultKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_pendingVaultKeysKey);
    if (data == null) return [];
    final raw = jsonDecode(data) as List<dynamic>;
    return raw.map((e) => Map<String, String>.from(e as Map)).toList();
  }

  static Future<void> savePendingVaultKeys(List<Map<String, String>> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingVaultKeysKey, jsonEncode(keys));
  }

  static Future<void> addPendingVaultKey({
    required String userId,
    required String recordId,
    required String encryptionKey,
  }) async {
    final pending = await getPendingVaultKeys();
    // 동일 recordId가 이미 큐에 있으면 덮어씀 (중복 방지)
    pending.removeWhere((k) => k['recordId'] == recordId);
    pending.add({'userId': userId, 'recordId': recordId, 'encryptionKey': encryptionKey});
    await savePendingVaultKeys(pending);
  }

  // 이 기기에서 직접 로그아웃 중임을 표시하는 플래그
  // authStateChanges 리스너가 정상 로그아웃을 원격 계정삭제로 오해하지 않도록 사용
  static bool intentionalLogout = false;

  // 로그아웃 시 인증 세션만 초기화 (사례·드래프트·PIN·Salt는 보존)
  // - PIN/Salt: 재로그인 후에도 보관함이 그대로 유지되어야 하므로 삭제하지 않음
  // - cases/drafts: 재로그인 시 서버 동기화로 최신 상태를 복원하므로 유지
  static Future<void> clearSessionDataForLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nicknameKey);
    await prefs.remove(_pinKey); // legacy SharedPreferences PIN 잔존 시만 제거 (secure storage는 유지)
    // _saltKey, _secureStorage PIN, _casesKey, _draftsKey 등은 유지
  }

  // [Security] Encryption Key Map — SecureStorage에 보관 ({ share_token: encryption_key })
  static const String _keyMapKey = 'dash_key_map';

  static Future<Map<String, String>> getKeyMap() async {
    final data = await _secureStorage.read(key: _keyMapKey);
    if (data == null) return {};
    return Map<String, String>.from(jsonDecode(data));
  }

  static Future<void> saveKeyToMap(String shareToken, String encryptionKey) async {
    final map = await getKeyMap();
    map[shareToken] = encryptionKey;
    await _secureStorage.write(key: _keyMapKey, value: jsonEncode(map));
  }

  static Future<String?> getKeyFromMap(String? shareToken) async {
    if (shareToken == null || shareToken.isEmpty) return null;
    final map = await getKeyMap();
    return map[shareToken];
  }

  static Future<void> clearKeyMap() async {
    await _secureStorage.delete(key: _keyMapKey);
  }

  // 로그아웃 시 로컬 캐시 초기화 (온보딩·동의 플래그는 유지)
  static Future<void> clearSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_casesKey);
    await prefs.remove(_draftsKey);
    await prefs.remove(_counselorsKey);
    await prefs.remove(_pendingSyncKey);
    await prefs.remove(_pendingVaultKeysKey);
    await prefs.remove(_nicknameKey);
    await prefs.remove(_pinKey); // legacy 잔존 시 제거
    await prefs.remove(_saltKey);
    await _secureStorage.delete(key: _pinKey);
    await clearKeyMap();
  }

  // 계정 탈퇴 시 모든 데이터 초기화 (온보딩·동의 플래그 포함)
  static Future<void> clearAllData() async {
    await clearSessionData();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('consent_v1_completed');
    await prefs.remove('consent_marketing');
    await prefs.remove('onboarding_v1_completed');
    await prefs.remove('fcm_permission_asked');
  }

  static const String _nicknameKey = 'dash_user_nickname';

  static Future<String?> getUserNickname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nicknameKey);
  }

  static Future<void> saveUserNickname(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nicknameKey, nickname);
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
