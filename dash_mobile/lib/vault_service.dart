import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/crash_service.dart';
import 'package:dash_mobile/analytics_service.dart';

/// E2EE 키 Vault 동기화 서비스
/// PIN + PBKDF2(100,000 iterations, SHA-256)로 암호화된 키 맵을 서버 Vault에 저장
class VaultService {
  /// PBKDF2로 PIN에서 32바이트 AES 키 파생
  static Uint8List _deriveKey(String pin, String saltB64) {
    final saltBytes = base64Decode(saltB64);
    final params = Pbkdf2Parameters(saltBytes, 100000, 32);
    final keyDerivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    keyDerivator.init(params);
    return keyDerivator.process(Uint8List.fromList(utf8.encode(pin)));
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
    Map<String, dynamic> keyMap = {};

    // 기존 Vault salt 사용, 없으면 새로 생성
    String salt;
    if (vaultResponse != null && vaultResponse['salt'] != null &&
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
