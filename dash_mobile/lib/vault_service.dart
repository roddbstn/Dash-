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

    // fetchVault 실패(null) 시 새 salt 생성을 절대 하지 않는다.
    // 새 salt로 vault를 덮어쓰면 확장프로그램의 cachedDerivedKey가 무효화되어
    // 기존 모든 레코드를 복호화할 수 없게 되는 치명적 버그를 유발한다.
    // 대신 throw해서 호출부의 재시도 큐(_syncKeyToVault retry + enqueueFailedKey)가 처리하도록 한다.
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

    // 기존 Vault 복호화해서 기존 키 보존
    if (vaultResponse != null && vaultResponse['encrypted_vault'] != null) {
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
  static Future<void> initEmptyVault(String userId, String pin, {bool force = false}) async {
    try {
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
    } catch (e) {
      debugPrint('❌ VaultService.initEmptyVault failed: $e');
    }
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
