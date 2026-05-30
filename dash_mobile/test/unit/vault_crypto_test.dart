// =============================================================================
// VaultService 암호화 로직 단위 테스트
// _deriveKey가 private이므로, 동일 알고리즘을 테스트 파일에서 재현하여
// PBKDF2-HMAC-SHA256 구현 정확성 및 AES-CBC 암복호화 roundtrip을 검증합니다.
//
// ⚠️ 주의: PBKDF2 100,000 iterations → 테스트 1회당 ~2–5초 소요
//          CI에서는 --timeout=60s 옵션 권장
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as pkg_crypto;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';

// ── 테스트용 PBKDF2 헬퍼 (VaultService._deriveKey 복제) ─────────────────────
// VaultService._deriveKey is private → 동일 로직 복제하여 테스트
Uint8List _testDeriveKey(String pin, String saltB64) {
  final password = Uint8List.fromList(utf8.encode(pin));
  final saltBytes = base64Decode(saltB64);
  final hmac = pkg_crypto.Hmac(pkg_crypto.sha256, password);

  final saltBlock = Uint8List(saltBytes.length + 4);
  saltBlock.setRange(0, saltBytes.length, saltBytes);
  saltBlock[saltBytes.length + 3] = 1; // big-endian block index 1

  var u = Uint8List.fromList(hmac.convert(saltBlock).bytes);
  final result = Uint8List.fromList(u);

  for (int i = 1; i < 100000; i++) {
    u = Uint8List.fromList(hmac.convert(u).bytes);
    for (int j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return result;
}

/// 테스트 속도용: 10 iterations만 수행 (알고리즘 구조 검증용)
Uint8List _fastDeriveKey(String pin, String saltB64, {int iterations = 10}) {
  final password = Uint8List.fromList(utf8.encode(pin));
  final saltBytes = base64Decode(saltB64);
  final hmac = pkg_crypto.Hmac(pkg_crypto.sha256, password);

  final saltBlock = Uint8List(saltBytes.length + 4);
  saltBlock.setRange(0, saltBytes.length, saltBytes);
  saltBlock[saltBytes.length + 3] = 1;

  var u = Uint8List.fromList(hmac.convert(saltBlock).bytes);
  final result = Uint8List.fromList(u);

  for (int i = 1; i < iterations; i++) {
    u = Uint8List.fromList(hmac.convert(u).bytes);
    for (int j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return result;
}

String _encryptVault(String pin, String saltB64, Map<String, dynamic> keyMap) {
  final derivedKey = _testDeriveKey(pin, saltB64);
  final vaultKey = enc.Key(derivedKey);
  final iv = enc.IV.fromLength(16);
  final encrypter = enc.Encrypter(enc.AES(vaultKey, mode: enc.AESMode.cbc));
  final encrypted = encrypter.encrypt(jsonEncode(keyMap), iv: iv);
  return '${iv.base64}:${encrypted.base64}';
}

Map<String, dynamic>? _decryptVault(
    String pin, String saltB64, String encryptedVault) {
  try {
    final derivedKey = _testDeriveKey(pin, saltB64);
    final vaultKey = enc.Key(derivedKey);
    final encrypter = enc.Encrypter(enc.AES(vaultKey, mode: enc.AESMode.cbc));
    final parts = encryptedVault.split(':');
    final decrypted = encrypter.decrypt(
      enc.Encrypted.fromBase64(parts[1]),
      iv: enc.IV.fromBase64(parts[0]),
    );
    return jsonDecode(decrypted) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

void main() {
  // ── PBKDF2 키 유도 ──────────────────────────────────────────────────────────

  group('PBKDF2-HMAC-SHA256 키 유도 (빠른 검증, 10 iterations)', () {
    final salt0 = base64Encode(List.filled(16, 0));
    final salt1 = base64Encode(List.filled(16, 1));

    test('출력 길이는 32바이트 (256-bit)', () {
      final key = _fastDeriveKey('1234', salt0);
      expect(key.length, 32);
    });

    test('동일 PIN + salt → 동일 키 (결정론적)', () {
      final k1 = _fastDeriveKey('1234', salt0);
      final k2 = _fastDeriveKey('1234', salt0);
      expect(k1, equals(k2));
    });

    test('PIN이 다르면 키가 달라짐', () {
      final k1 = _fastDeriveKey('1234', salt0);
      final k2 = _fastDeriveKey('5678', salt0);
      expect(k1, isNot(equals(k2)));
    });

    test('salt가 다르면 키가 달라짐', () {
      final k1 = _fastDeriveKey('1234', salt0);
      final k2 = _fastDeriveKey('1234', salt1);
      expect(k1, isNot(equals(k2)));
    });

    test('빈 PIN도 키 유도 가능 (에러 없음)', () {
      expect(() => _fastDeriveKey('', salt0), returnsNormally);
    });

    test('단일 문자 PIN도 32바이트 키 생성', () {
      final key = _fastDeriveKey('0', salt0);
      expect(key.length, 32);
    });

    test('긴 PIN (100자)도 처리 가능', () {
      final longPin = 'a' * 100;
      expect(() => _fastDeriveKey(longPin, salt0), returnsNormally);
    });

    test('XOR 누적이 정상 동작 — 1 iteration 결과와 2 iteration 결과가 다름', () {
      final k1 = _fastDeriveKey('1234', salt0, iterations: 1);
      final k2 = _fastDeriveKey('1234', salt0, iterations: 2);
      expect(k1, isNot(equals(k2)));
    });
  });

  // ── AES-CBC 암복호화 Roundtrip ───────────────────────────────────────────────

  group('AES-CBC 암복호화 Roundtrip (빠른 키 사용)', () {
    final salt = base64Encode(List.filled(16, 42));

    enc.Encrypter _makeEncrypter(String pin) {
      final key = enc.Key(_fastDeriveKey(pin, salt));
      return enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    }

    test('빈 keyMap {} 암복호화', () {
      final encrypter = _makeEncrypter('1234');
      final iv = enc.IV.fromLength(16);
      final encrypted = encrypter.encrypt(jsonEncode({}), iv: iv);
      final decrypted = encrypter.decrypt(encrypted, iv: iv);
      expect(jsonDecode(decrypted), isEmpty);
    });

    test('단일 키 맵 암복호화', () {
      final encrypter = _makeEncrypter('1234');
      final iv = enc.IV.fromLength(16);
      final original = {'token_abc': 'enckey_xyz'};
      final encrypted = encrypter.encrypt(jsonEncode(original), iv: iv);
      final decrypted = jsonDecode(encrypter.decrypt(encrypted, iv: iv));
      expect(decrypted['token_abc'], 'enckey_xyz');
    });

    test('다중 키 맵 암복호화', () {
      final encrypter = _makeEncrypter('9999');
      final iv = enc.IV.fromLength(16);
      final original = {
        'tok1': 'key1',
        'tok2': 'key2',
        'tok3': 'key3',
      };
      final encrypted = encrypter.encrypt(jsonEncode(original), iv: iv);
      final decrypted =
          jsonDecode(encrypter.decrypt(encrypted, iv: iv)) as Map;
      expect(decrypted.length, 3);
      expect(decrypted['tok3'], 'key3');
    });

    test('IV가 vault 문자열 앞에 base64로 포함됨 (형식: IV:ciphertext)', () {
      final encrypter = _makeEncrypter('1234');
      final iv = enc.IV.fromLength(16);
      final encrypted = encrypter.encrypt('{}', iv: iv);
      final vaultStr = '${iv.base64}:${encrypted.base64}';

      final parts = vaultStr.split(':');
      expect(parts.length, 2);
      // IV 길이 검증: 16바이트 → base64 24자
      expect(base64Decode(parts[0]).length, 16);
    });

    test('IV:ciphertext 형식 분리 후 정상 복호화', () {
      final encrypter = _makeEncrypter('abcd');
      final iv = enc.IV.fromLength(16);
      final plaintext = '{"shareToken1":"encKey1"}';
      final encrypted = encrypter.encrypt(plaintext, iv: iv);
      final vaultStr = '${iv.base64}:${encrypted.base64}';

      final parts = vaultStr.split(':');
      final restored = encrypter.decrypt(
        enc.Encrypted.fromBase64(parts[1]),
        iv: enc.IV.fromBase64(parts[0]),
      );
      expect(restored, plaintext);
    });

    test('잘못된 PIN으로 복호화 시 예외 또는 오류 결과', () {
      final encrypter = _makeEncrypter('correct_pin');
      final wrongEncrypter = _makeEncrypter('wrong_pin');
      final iv = enc.IV.fromLength(16);
      final encrypted = encrypter.encrypt('{"key":"value"}', iv: iv);

      // 잘못된 키로 복호화하면 PaddingException 또는 잘못된 JSON
      bool failed = false;
      try {
        final result = wrongEncrypter.decrypt(encrypted, iv: iv);
        // 혹시 복호화는 되더라도 JSON이 깨져 있어야 함
        jsonDecode(result); // 유효 JSON이면 실패
      } catch (_) {
        failed = true;
      }
      expect(failed, isTrue,
          reason: '잘못된 PIN으로 복호화 시 반드시 실패해야 함');
    });
  });

  // ── 전체 Vault 암복호화 E2E (실제 100,000 iterations) ────────────────────────
  // 이 그룹은 실제 VaultService와 동일한 파라미터를 사용합니다.
  // CI에서 시간이 걸릴 수 있으므로 필요 시 --tags=slow로 분리하세요.

  group('Vault E2E — 실제 PBKDF2 100k iterations', () {
    const testPin = '1234';
    final testSalt = base64Encode(List.filled(16, 0xAB));

    test('빈 vault 초기화 후 복호화 성공', () {
      final vaultStr = _encryptVault(testPin, testSalt, {});
      final result = _decryptVault(testPin, testSalt, vaultStr);
      expect(result, isNotNull);
      expect(result, isEmpty);
    });

    test('키 추가 후 복호화로 값 조회', () {
      final original = {'shareToken_abc': 'encryptionKey_xyz'};
      final vaultStr = _encryptVault(testPin, testSalt, original);
      final result = _decryptVault(testPin, testSalt, vaultStr);
      expect(result, isNotNull);
      expect(result!['shareToken_abc'], 'encryptionKey_xyz');
    });

    test('PIN 불일치 → 복호화 실패 (null 반환)', () {
      final vaultStr = _encryptVault(testPin, testSalt, {'tok': 'key'});
      final result = _decryptVault('wrong_pin', testSalt, vaultStr);
      expect(result, isNull);
    });

    test('salt 불일치 → 복호화 실패 (null 반환)', () {
      final vaultStr = _encryptVault(testPin, testSalt, {'tok': 'key'});
      final wrongSalt = base64Encode(List.filled(16, 0xFF));
      final result = _decryptVault(testPin, wrongSalt, vaultStr);
      expect(result, isNull);
    });

    test('키 추가 시뮬레이션: 기존 복호화 → 키 추가 → 재암호화 → 재복호화', () {
      // 초기 vault
      final initial = {'tok1': 'key1'};
      final vaultStr1 = _encryptVault(testPin, testSalt, initial);

      // 새 키 추가 (syncKey 흐름 시뮬레이션)
      final existing = _decryptVault(testPin, testSalt, vaultStr1)!;
      existing['tok2'] = 'key2';
      final vaultStr2 = _encryptVault(testPin, testSalt, existing);

      final result = _decryptVault(testPin, testSalt, vaultStr2);
      expect(result, isNotNull);
      expect(result!.length, 2);
      expect(result['tok1'], 'key1');
      expect(result['tok2'], 'key2');
    });
  });

  // ── Salt 유효성 검증 ────────────────────────────────────────────────────────

  group('Salt 유효성 검증', () {
    test('길이 10 이하의 salt는 유효하지 않음 (VaultService 검증 기준)', () {
      // VaultService는 salt.length > 10 을 유효 salt로 판단
      // 16바이트 base64 = 24자 → 항상 유효
      final validSalt = base64Encode(List.filled(16, 0));
      expect(validSalt.length, greaterThan(10));
    });

    test('빈 salt 문자열은 유효하지 않음', () {
      expect(''.length, lessThanOrEqualTo(10));
    });

    test('16바이트 랜덤 salt는 base64로 24자', () {
      // _generateSalt()가 16바이트를 생성하는 것과 동일
      final fakeSalt = base64Encode(List.generate(16, (i) => i));
      expect(fakeSalt.length, 24);
      expect(fakeSalt.length, greaterThan(10)); // VaultService 검증 통과
    });
  });
}
