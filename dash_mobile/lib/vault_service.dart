import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart' as pkg_crypto;
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/crash_service.dart';
import 'package:dash_mobile/analytics_service.dart';

/// E2EE 키 Vault 동기화 서비스
/// PIN + PBKDF2(100,000 iterations, SHA-256)로 암호화된 키 맵을 서버 Vault에 저장
class VaultService {
  /// PBKDF2-HMAC-SHA256 (RFC 2898) — Web Crypto API와 동일한 출력 보장
  /// PointyCastle의 PBKDF2 구현이 Web Crypto와 호환되지 않아 직접 구현
  static Uint8List _deriveKey(String pin, String saltB64) {
    final password = Uint8List.fromList(utf8.encode(pin));
    final saltBytes = base64Decode(saltB64);
    final hmac = pkg_crypto.Hmac(pkg_crypto.sha256, password);

    // Block 1: salt || INT_BE(1)
    final saltBlock = Uint8List(saltBytes.length + 4);
    saltBlock.setRange(0, saltBytes.length, saltBytes);
    saltBlock[saltBytes.length + 3] = 1; // big-endian block index 1

    // U_1 = HMAC(P, S || INT(1))
    var u = Uint8List.fromList(hmac.convert(saltBlock).bytes);
    final result = Uint8List.fromList(u);

    // U_i = HMAC(P, U_{i-1}), result ^= U_i for i = 2..100000
    for (int i = 1; i < 100000; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (int j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  /// 랜덤 16바이트 salt 생성 (base64 반환)
  static String _generateSalt() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// recordId(share_token)에 해당하는 암호화 키를 Vault에 저장합니다.
  /// 실패 시 예외를 throw — 호출부에서 큐에 적재하세요.
  static Future<void> syncKey(
    String userId,
    String shareToken,
    String encryptionKey,
    String pin,
  ) async {
    final vaultResponse = await ApiService.fetchVault(userId);

    // fetchVault가 null이면 서버/네트워크 오류 → throw해서 재시도 큐가 처리
    // fetchVault가 {} (빈 맵, 404)이면 볼트 미존재 → 아래 로직에서 새 salt 생성 후 초기화
    // null과 {} 구분: null = 기존 볼트가 있을 수 있으므로 salt 생성 금지
    //               {} = 볼트 없음 확인 → 안전하게 새 salt 생성 가능
    if (vaultResponse == null) {
      throw Exception('fetchVault failed — aborting syncKey to preserve vault integrity');
    }

    Map<String, dynamic> keyMap = {};

    // 기존 Vault salt 사용, 없으면 새로 생성 (새 vault 최초 초기화 시에만 해당)
    String salt;
    if (vaultResponse['salt'] != null &&
        (vaultResponse['salt'] as String).length > 10) {
      salt = vaultResponse['salt'] as String;
    } else {
      salt = _generateSalt();
    }

    // 기존 Vault 복호화해서 기존 키 보존 (여기까지 오면 vaultResponse는 non-null 보장)
    if (vaultResponse['encrypted_vault'] != null) {
      try {
        final derivedKey = _deriveKey(pin, salt);
        final vaultKey = enc.Key(derivedKey);
        final encrypter = enc.Encrypter(enc.AES(vaultKey, mode: enc.AESMode.cbc));
        final parts = (vaultResponse['encrypted_vault'] as String).split(':');
        final decrypted = encrypter.decrypt(
          enc.Encrypted.fromBase64(parts[1]),
          iv: enc.IV.fromBase64(parts[0]),
        );
        keyMap = jsonDecode(decrypted) as Map<String, dynamic>;
      } catch (_) {
        debugPrint('🔒 Vault: 기존 키 복호화 실패 — 새 Vault 생성');
      }
    }

    // 새 키 추가
    keyMap[shareToken] = encryptionKey;

    // SecureStorage keyMap도 동기화
    await StorageService.saveKeyToMap(shareToken, encryptionKey);

    // 새 Vault 암호화 후 저장
    final derivedKey = _deriveKey(pin, salt);
    final vaultKey = enc.Key(derivedKey);
    final iv = enc.IV.fromLength(16);
    final encrypter = enc.Encrypter(enc.AES(vaultKey, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(jsonEncode(keyMap), iv: iv);
    await ApiService.saveVault(userId, '${iv.base64}:${encrypted.base64}', salt);
  }

  /// PIN 설정 시 keyMap이 비어있어도 salt를 확립하기 위해 빈 Vault를 서버에 초기화합니다.
  /// [force] = true 이면 기존 Vault가 있어도 새 PIN으로 덮어씁니다.
  /// keyMap이 비어있는 상태에서 재설정 시에는 force:true를 사용해야 PIN-Vault 일관성이 보장됩니다.
  /// 실패 시 예외를 throw — 호출부에서 반드시 try-catch로 처리하세요.
  static Future<void> initEmptyVault(String userId, String pin, {bool force = false}) async {
    // force가 아닐 때만 기존 Vault 보존 (salt 유지 목적)
    if (!force) {
      final existing = await ApiService.fetchVault(userId);
      if (existing != null && existing['encrypted_vault'] != null) return;
    }

    final salt = _generateSalt();
    final derivedKey = _deriveKey(pin, salt);
    final vaultKey = enc.Key(derivedKey);
    final iv = enc.IV.fromLength(16);
    final encrypter = enc.Encrypter(enc.AES(vaultKey, mode: enc.AESMode.cbc));
    // 빈 keyMap을 암호화
    final encrypted = encrypter.encrypt(jsonEncode({}), iv: iv);
    await ApiService.saveVault(userId, '${iv.base64}:${encrypted.base64}', salt);
    debugPrint('✅ VaultService: empty Vault initialized with new salt');
  }

  /// Vault 동기화 실패 항목을 큐에 적재합니다.
  static Future<void> enqueueFailedKey({
    required String userId,
    required String recordId,
    required String encryptionKey,
  }) async {
    await StorageService.addPendingVaultKey(
      userId: userId,
      recordId: recordId,
      encryptionKey: encryptionKey,
    );
    debugPrint('⏳ Vault key queued for retry: $recordId');
  }

  /// 앱 포그라운드 복귀 시 실패했던 Vault 키 동기화를 재시도합니다.
  static Future<void> retryPendingKeys() async {
    final pending = await StorageService.getPendingVaultKeys();
    if (pending.isEmpty) return;

    final pin = await StorageService.getPin();
    if (pin == null) return;

    final remaining = <Map<String, String>>[];
    int successCount = 0;

    for (final item in pending) {
      try {
        await syncKey(
          item['userId']!,
          item['recordId']!,
          item['encryptionKey']!,
          pin,
        );
        successCount++;
        debugPrint('✅ Vault key retry success: ${item['recordId']}');
      } catch (e, stack) {
        CrashService.recordError(e, stack, reason: 'vaultKeyRetry');
        remaining.add(item);
      }
    }

    await StorageService.savePendingVaultKeys(remaining);

    if (successCount > 0 || remaining.isNotEmpty) {
      AnalyticsService.vaultKeyRetried(
        successCount: successCount,
        failureCount: remaining.length,
      );
    }
  }

  /// SecureStorage keyMap ↔ Vault 양방향 동기화.
  /// - SecureStorage에 있는 키 중 Vault에 없는 것 → Vault에 추가
  /// - Vault에 있는 키 중 SecureStorage에 없는 것 → SecureStorage에 복원
  /// 앱 실행 시 1회 호출 — PIN 변경/재설치 후 누락된 키를 복구합니다.
  static Future<void> backfillMissingKeys(String userId, String pin) async {
    try {
      final vaultResponse = await ApiService.fetchVault(userId);
      if (vaultResponse == null) return; // 서버 오류 → 재시도하지 않음

      Map<String, dynamic> vaultKeyMap = {};
      String salt;

      if (vaultResponse['salt'] != null &&
          (vaultResponse['salt'] as String).length > 10 &&
          vaultResponse['encrypted_vault'] != null) {
        salt = vaultResponse['salt'] as String;
        try {
          final derivedKey = _deriveKey(pin, salt);
          final vaultKey = enc.Key(derivedKey);
          final encrypter = enc.Encrypter(enc.AES(vaultKey, mode: enc.AESMode.cbc));
          final parts = (vaultResponse['encrypted_vault'] as String).split(':');
          final decrypted = encrypter.decrypt(
            enc.Encrypted.fromBase64(parts[1]),
            iv: enc.IV.fromBase64(parts[0]),
          );
          vaultKeyMap = jsonDecode(decrypted) as Map<String, dynamic>;
        } catch (_) {
          // PIN 불일치 등으로 복호화 실패 → 중단 (덮어쓰면 안 됨)
          debugPrint('⚠️ VaultService.backfillMissingKeys: vault 복호화 실패 — 중단');
          return;
        }
      } else {
        // Vault 미존재 → 전체 localKeyMap으로 초기화
        salt = _generateSalt();
      }

      final localKeyMap = await StorageService.getKeyMap();
      debugPrint('🔑 backfill: vault 키 수=${vaultKeyMap.length}, local 키 수=${localKeyMap.length}');

      // ① vault → SecureStorage 복원 (vault에 있지만 local에 없는 키)
      int restoredCount = 0;
      for (final entry in vaultKeyMap.entries) {
        if (!localKeyMap.containsKey(entry.key)) {
          await StorageService.saveKeyToMap(entry.key, entry.value as String);
          restoredCount++;
        }
      }
      if (restoredCount > 0) {
        debugPrint('✅ backfill: vault → SecureStorage 복원 $restoredCount개');
      }

      // ② SecureStorage → vault 추가 (local에 있지만 vault에 없는 키)
      bool vaultChanged = false;
      for (final entry in localKeyMap.entries) {
        if (!vaultKeyMap.containsKey(entry.key)) {
          vaultKeyMap[entry.key] = entry.value;
          vaultChanged = true;
        }
      }
      if (!vaultChanged && restoredCount == 0) {
        debugPrint('✅ VaultService.backfillMissingKeys: 누락 키 없음');
        return;
      }
      if (vaultChanged) {
        final derivedKey = _deriveKey(pin, salt);
        final vaultKey = enc.Key(derivedKey);
        final iv = enc.IV.fromLength(16);
        final encrypter = enc.Encrypter(enc.AES(vaultKey, mode: enc.AESMode.cbc));
        final encrypted = encrypter.encrypt(jsonEncode(vaultKeyMap), iv: iv);
        await ApiService.saveVault(userId, '${iv.base64}:${encrypted.base64}', salt);
        debugPrint('✅ backfill: SecureStorage → vault 추가 완료');
      }
    } catch (e) {
      debugPrint('❌ VaultService.backfillMissingKeys failed: $e');
    }
  }

  /// PIN으로 Vault를 복호화하여 keyMap 반환. 실패 시 null.
  static Future<Map<String, dynamic>?> decryptVault(String pin, String userId) async {
    try {
      final vaultResponse = await ApiService.fetchVault(userId);
      if (vaultResponse == null || vaultResponse['encrypted_vault'] == null) return null;
      final salt = vaultResponse['salt'] as String?;
      if (salt == null || salt.length <= 10) return null;

      final derivedKey = _deriveKey(pin, salt);
      final vaultKey = enc.Key(derivedKey);
      final encrypter = enc.Encrypter(enc.AES(vaultKey, mode: enc.AESMode.cbc));
      final parts = (vaultResponse['encrypted_vault'] as String).split(':');
      final decrypted = encrypter.decrypt(
        enc.Encrypted.fromBase64(parts[1]),
        iv: enc.IV.fromBase64(parts[0]),
      );
      return jsonDecode(decrypted) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ VaultService.decryptVault failed: $e');
      return null;
    }
  }
}
