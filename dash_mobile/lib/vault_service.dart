import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/crash_service.dart';
import 'package:dash_mobile/analytics_service.dart';

/// E2EE 키 Vault 동기화 서비스
/// PIN으로 암호화된 키 맵을 서버 Vault에 저장 / 재시도 큐를 관리합니다.
class VaultService {
  /// recordId에 해당하는 암호화 키를 Vault에 저장합니다.
  /// 실패 시 예외를 throw — 호출부에서 큐에 적재하세요.
  static Future<void> syncKey(
    String userId,
    String recordId,
    String encryptionKey,
    String pin,
  ) async {
    final vaultResponse = await ApiService.fetchVault(userId);
    Map<String, dynamic> keyMap = {};
    final String? salt = vaultResponse?['salt'] ?? userId;

    if (vaultResponse != null && vaultResponse['encrypted_vault'] != null) {
      try {
        final vaultKey = enc.Key.fromUtf8(pin.padRight(32).substring(0, 32));
        final encrypter = enc.Encrypter(enc.AES(vaultKey, mode: enc.AESMode.cbc));
        final parts = (vaultResponse['encrypted_vault'] as String).split(':');
        final decrypted = encrypter.decrypt(
          enc.Encrypted.fromBase64(parts[1]),
          iv: enc.IV.fromBase64(parts[0]),
        );
        keyMap = jsonDecode(decrypted) as Map<String, dynamic>;
      } catch (_) {
        debugPrint('🔒 Vault: PIN 불일치 — 새 Vault 생성');
      }
    }

    keyMap[recordId] = encryptionKey;
    final vaultKey = enc.Key.fromUtf8(pin.padRight(32).substring(0, 32));
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
}
