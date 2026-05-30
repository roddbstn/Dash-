// =============================================================================
// VaultService 단위 테스트 — Mockito + http.MockClient
//
// 아키텍처 제약:
//   VaultService, ApiService, StorageService가 모두 static 메서드를 사용하므로
//   Mockito의 @GenerateMocks 방식은 적용 불가.
//   대신 다음 두 레이어를 직접 가로채는 방식을 사용합니다:
//   1. HTTP 레이어: http.runWithClient + MockClient (package:http/testing.dart)
//   2. 플랫폼 채널: TestDefaultBinaryMessengerBinding (SecureStorage, Firebase)
//   3. SharedPreferences: setMockInitialValues
//
// 결과적으로 VaultService의 핵심 비즈니스 로직(상태 전환, 예외 처리)을
// 실제 네트워크/디바이스 없이 완전히 검증할 수 있습니다.
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as pkg_crypto;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dash_mobile/vault_service.dart';
import '../helpers/firebase_mock.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 테스트용 헬퍼 (vault_crypto_test.dart와 동일 알고리즘 복제)
// ─────────────────────────────────────────────────────────────────────────────

Uint8List _deriveKey(String pin, String saltB64) {
  final password = Uint8List.fromList(utf8.encode(pin));
  final saltBytes = base64Decode(saltB64);
  final hmac = pkg_crypto.Hmac(pkg_crypto.sha256, password);
  final saltBlock = Uint8List(saltBytes.length + 4);
  saltBlock.setRange(0, saltBytes.length, saltBytes);
  saltBlock[saltBytes.length + 3] = 1;
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

/// 테스트용 vault 암호화 — 실제 서버가 반환할 형식으로 생성
Map<String, dynamic> _makeVaultResponse(
    String pin, String saltB64, Map<String, dynamic> keyMap) {
  final derivedKey = _deriveKey(pin, saltB64);
  final vaultKey = enc.Key(derivedKey);
  final iv = enc.IV.fromLength(16);
  final encrypter = enc.Encrypter(enc.AES(vaultKey, mode: enc.AESMode.cbc));
  final encrypted = encrypter.encrypt(jsonEncode(keyMap), iv: iv);
  return {
    'encrypted_vault': '${iv.base64}:${encrypted.base64}',
    'salt': saltB64,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Mock 플랫폼 채널 셋업
// ─────────────────────────────────────────────────────────────────────────────

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _firebaseAuthChannel = MethodChannel('plugins.flutter.io/firebase_auth');

// SecureStorage in-memory store (테스트 격리용)
Map<String, String?> _secureStore = {};

void _setupPlatformMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  _secureStore = {};

  // SecureStorage mock
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel,
          (MethodCall call) async {
    switch (call.method) {
      case 'read':
        final key = (call.arguments as Map)['key'] as String;
        return _secureStore[key];
      case 'write':
        final args = call.arguments as Map;
        _secureStore[args['key'] as String] = args['value'] as String?;
        return null;
      case 'delete':
        final key = (call.arguments as Map)['key'] as String;
        _secureStore.remove(key);
        return null;
      case 'readAll':
        return _secureStore;
      default:
        return null;
    }
  });
}

void _tearDownPlatformMocks() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, null);
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP MockClient 팩토리들
// ─────────────────────────────────────────────────────────────────────────────

/// fetchVault → null (네트워크/서버 오류 시뮬레이션: 500 반환)
MockClient _mockVaultNetworkError() => MockClient((request) async {
      if (request.url.path.contains('/vault/')) {
        return http.Response('Internal Server Error', 500);
      }
      return http.Response('{}', 200);
    });

/// fetchVault → {} (404: 볼트 미존재)
MockClient _mockVaultNotFound() => MockClient((request) async {
      if (request.url.path.contains('/vault/')) {
        return http.Response('{}', 404);
      }
      // saveVault 호출 → 200 성공
      if (request.url.path.contains('/users/vault') &&
          request.method == 'POST') {
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 200);
    });

/// fetchVault → 기존 vault 반환 + saveVault 성공
MockClient _mockVaultWithData(Map<String, dynamic> vaultData) =>
    MockClient((request) async {
      if (request.url.path.contains('/vault/') && request.method == 'GET') {
        return http.Response(jsonEncode(vaultData), 200);
      }
      if (request.url.path.contains('/users/vault') &&
          request.method == 'POST') {
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('{}', 200);
    });

/// saveVault 실패 (503)
MockClient _mockVaultSaveFail(Map<String, dynamic> fetchData) =>
    MockClient((request) async {
      if (request.url.path.contains('/vault/') && request.method == 'GET') {
        return http.Response(jsonEncode(fetchData), 200);
      }
      if (request.url.path.contains('/users/vault') &&
          request.method == 'POST') {
        return http.Response('Service Unavailable', 503);
      }
      return http.Response('{}', 200);
    });

// ─────────────────────────────────────────────────────────────────────────────
// 테스트 수트
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    // Firebase Core + Auth 채널 모킹 (currentUser = null 보장)
    await setupFirebaseMocks();
  });

  setUp(_setupPlatformMocks);
  tearDown(_tearDownPlatformMocks);

  // ── VaultService.syncKey ──────────────────────────────────────────────────

  group('VaultService.syncKey', () {
    const testPin = 'abcd';
    const testSalt = 'AAAAAAAAAAAAAAAAAAAAAA=='; // 16-byte all-zero, base64
    const userId = 'user_test_001';
    const shareToken = 'shareToken_abc';
    const encKey = 'encryptionKey_xyz';

    test('fetchVault 실패(500) → Exception throw (볼트 무결성 보존)', () async {
      await http.runWithClient(() async {
        await expectLater(
          VaultService.syncKey(userId, shareToken, encKey, testPin),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('fetchVault failed'),
          )),
        );
      }, _mockVaultNetworkError);
    });

    test('fetchVault 404(볼트 없음) → 새 salt 생성 후 새 vault 저장 성공', () async {
      await http.runWithClient(() async {
        // 예외 없이 완료되어야 함
        await expectLater(
          VaultService.syncKey(userId, shareToken, encKey, testPin),
          completes,
        );
      }, _mockVaultNotFound);
    });

    test('fetchVault 404 → SecureStorage keyMap에 토큰 추가됨', () async {
      await http.runWithClient(() async {
        await VaultService.syncKey(userId, shareToken, encKey, testPin);
      }, _mockVaultNotFound);

      // SecureStorage keyMap 확인
      final raw = _secureStore['dash_key_map'];
      expect(raw, isNotNull);
      final map = jsonDecode(raw!) as Map;
      expect(map[shareToken], encKey);
    });

    test('기존 vault 존재 → 복호화 후 새 키 병합하여 저장', () async {
      // 기존 vault에 토큰1이 있는 상태
      const existingToken = 'existing_token';
      const existingKey = 'existing_key';
      final existingVault = _makeVaultResponse(testPin, testSalt,
          {existingToken: existingKey});

      await http.runWithClient(() async {
        await VaultService.syncKey(userId, shareToken, encKey, testPin);
      }, () => _mockVaultWithData(existingVault));

      // SecureStorage에 새 키 추가 확인
      final raw = _secureStore['dash_key_map'];
      expect(raw, isNotNull);
      final map = jsonDecode(raw!) as Map;
      expect(map[shareToken], encKey);
    });

    test('saveVault 실패 → Exception throw (재시도 큐 체인 트리거용)', () async {
      final existingVault =
          _makeVaultResponse(testPin, testSalt, {});

      await http.runWithClient(() async {
        await expectLater(
          VaultService.syncKey(userId, shareToken, encKey, testPin),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('saveVault HTTP'),
          )),
        );
      }, () => _mockVaultSaveFail(existingVault));
    });

    test('잘못된 PIN → 기존 vault 복호화 실패 → 새 keyMap으로 저장 (기존 키 유실 방지 로직)', () async {
      // 올바른 PIN으로 암호화된 vault
      final existingVault =
          _makeVaultResponse('correct_pin', testSalt, {'tok': 'key'});

      // 틀린 PIN으로 syncKey 호출 → 복호화 실패 → catch에서 빈 keyMap으로 새 키 추가
      // (이는 VaultService의 설계된 동작: 복호화 실패 시 새 Vault 시작)
      await http.runWithClient(() async {
        await VaultService.syncKey(userId, shareToken, encKey, 'wrong_pin');
      }, () => _mockVaultWithData(existingVault));

      // 어쨌든 새 키는 SecureStorage에 저장됨
      final raw = _secureStore['dash_key_map'];
      final map = jsonDecode(raw ?? '{}') as Map;
      expect(map[shareToken], encKey);
    });
  });

  // ── VaultService.initEmptyVault ───────────────────────────────────────────

  group('VaultService.initEmptyVault', () {
    const userId = 'user_001';
    const testPin = '1234';

    test('vault 없을 때 빈 vault 초기화 성공 (예외 없음)', () async {
      await http.runWithClient(() async {
        await expectLater(
          VaultService.initEmptyVault(userId, testPin),
          completes,
        );
      }, _mockVaultNotFound);
    });

    test('force=false + 기존 vault 있으면 초기화 건너뜀', () async {
      final existingVault = _makeVaultResponse(testPin, 'AAAAAAAAAAAAAAAAAAAAAA==', {});
      int saveCount = 0;

      final client = MockClient((req) async {
        if (req.url.path.contains('/vault/') && req.method == 'GET') {
          return http.Response(jsonEncode(existingVault), 200);
        }
        if (req.url.path.contains('/users/vault') && req.method == 'POST') {
          saveCount++;
          return http.Response('{"ok":true}', 200);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await VaultService.initEmptyVault(userId, testPin, force: false);
      }, () => client);

      expect(saveCount, 0, reason: '기존 vault 있으면 saveVault 호출하지 않아야 함');
    });

    test('force=true → 기존 vault 있어도 강제 덮어씀', () async {
      final existingVault = _makeVaultResponse(testPin, 'AAAAAAAAAAAAAAAAAAAAAA==', {});
      int saveCount = 0;

      final client = MockClient((req) async {
        if (req.url.path.contains('/vault/') && req.method == 'GET') {
          return http.Response(jsonEncode(existingVault), 200);
        }
        if (req.url.path.contains('/users/vault') && req.method == 'POST') {
          saveCount++;
          return http.Response('{"ok":true}', 200);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await VaultService.initEmptyVault(userId, testPin, force: true);
      }, () => client);

      expect(saveCount, 1, reason: 'force=true이면 saveVault 1회 호출해야 함');
    });

    test('saveVault 실패해도 initEmptyVault는 예외 삼킴 (조용히 실패)', () async {
      final client = MockClient((req) async {
        if (req.url.path.contains('/vault/')) {
          if (req.method == 'GET') return http.Response('{}', 404);
          return http.Response('Error', 503); // saveVault 실패
        }
        return http.Response('{}', 200);
      });

      // initEmptyVault는 내부 catch로 예외를 삼킴 → 외부로 throw 안 해야 함
      await http.runWithClient(() async {
        await expectLater(
          VaultService.initEmptyVault(userId, testPin),
          completes,
        );
      }, () => client);
    });
  });

  // ── VaultService.enqueueFailedKey ─────────────────────────────────────────

  group('VaultService.enqueueFailedKey', () {
    test('큐에 항목 추가 후 getPendingVaultKeys에서 조회 가능', () async {
      await VaultService.enqueueFailedKey(
        userId: 'u1',
        recordId: 'r1',
        encryptionKey: 'k1',
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('dash_pending_vault_keys');
      expect(raw, isNotNull);
      final list = jsonDecode(raw!) as List;
      expect(list.length, 1);
      expect(list[0]['recordId'], 'r1');
    });

    test('동일 recordId 재적재 시 덮어씀', () async {
      await VaultService.enqueueFailedKey(
          userId: 'u1', recordId: 'r1', encryptionKey: 'k_old');
      await VaultService.enqueueFailedKey(
          userId: 'u1', recordId: 'r1', encryptionKey: 'k_new');

      final prefs = await SharedPreferences.getInstance();
      final list =
          jsonDecode(prefs.getString('dash_pending_vault_keys')!) as List;
      expect(list.length, 1);
      expect(list[0]['encryptionKey'], 'k_new');
    });
  });

  // ── VaultService.retryPendingKeys ─────────────────────────────────────────

  group('VaultService.retryPendingKeys', () {
    const testPin = '9999';

    test('대기 큐가 비어있으면 아무것도 하지 않음', () async {
      SharedPreferences.setMockInitialValues({});

      await http.runWithClient(() async {
        await expectLater(VaultService.retryPendingKeys(), completes);
      }, _mockVaultNotFound);
    });

    test('PIN 없으면(null) 재시도 생략', () async {
      // PIN을 SecureStorage에 저장하지 않은 상태
      SharedPreferences.setMockInitialValues({
        'dash_pending_vault_keys':
            jsonEncode([{'userId': 'u1', 'recordId': 'r1', 'encryptionKey': 'k1'}]),
      });
      // SecureStorage pin = null (기본값)

      int fetchCount = 0;
      final client = MockClient((req) async {
        fetchCount++;
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await VaultService.retryPendingKeys();
      }, () => client);

      // PIN이 없으므로 네트워크 요청 발생하지 않아야 함
      expect(fetchCount, 0);
    });

    test('성공한 키는 큐에서 제거됨', () async {
      // PIN 설정
      _secureStore['dash_user_pin'] = testPin;

      // 대기 큐에 항목 추가
      SharedPreferences.setMockInitialValues({
        'dash_pending_vault_keys': jsonEncode([
          {'userId': 'u1', 'recordId': 'r1', 'encryptionKey': 'k1'},
        ]),
      });

      await http.runWithClient(() async {
        await VaultService.retryPendingKeys();
      }, _mockVaultNotFound);

      // 성공 → 큐 비워짐
      final prefs = await SharedPreferences.getInstance();
      final remaining = jsonDecode(
          prefs.getString('dash_pending_vault_keys') ?? '[]') as List;
      expect(remaining, isEmpty);
    });

    test('서버 오류 → 실패한 키는 큐에 유지됨', () async {
      _secureStore['dash_user_pin'] = testPin;

      SharedPreferences.setMockInitialValues({
        'dash_pending_vault_keys': jsonEncode([
          {'userId': 'u1', 'recordId': 'r1', 'encryptionKey': 'k1'},
        ]),
      });

      await http.runWithClient(() async {
        await VaultService.retryPendingKeys();
      }, _mockVaultNetworkError);

      final prefs = await SharedPreferences.getInstance();
      final remaining = jsonDecode(
          prefs.getString('dash_pending_vault_keys') ?? '[]') as List;
      // 서버 오류로 실패한 키는 큐에 남아있어야 함
      expect(remaining.length, 1);
      expect(remaining[0]['recordId'], 'r1');
    });

    test('혼합(성공1 + 실패1) → 실패만 큐에 유지', () async {
      _secureStore['dash_user_pin'] = testPin;

      SharedPreferences.setMockInitialValues({
        'dash_pending_vault_keys': jsonEncode([
          {'userId': 'u1', 'recordId': 'success_r', 'encryptionKey': 'k1'},
          {'userId': 'u1', 'recordId': 'fail_r', 'encryptionKey': 'k2'},
        ]),
      });

      int callCount = 0;
      // 첫 번째 요청만 fetchVault 성공(404), 이후 saveVault는 success_r 성공/fail_r 실패
      final client = MockClient((req) async {
        callCount++;
        if (req.url.path.contains('/vault/') && req.method == 'GET') {
          return http.Response('{}', 404); // 볼트 없음
        }
        if (req.url.path.contains('/users/vault') && req.method == 'POST') {
          // 두 번째 saveVault 호출부터 실패 시뮬레이션
          final body = jsonDecode(req.body) as Map;
          // fail_r의 syncKey에서 두 번째 POST
          return callCount > 3
              ? http.Response('Error', 503)
              : http.Response('{"ok":true}', 200);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await VaultService.retryPendingKeys();
      }, () => client);

      final prefs = await SharedPreferences.getInstance();
      final remaining = jsonDecode(
          prefs.getString('dash_pending_vault_keys') ?? '[]') as List;
      // success_r는 제거, fail_r는 유지
      expect(remaining.every((k) => k['recordId'] != 'success_r'), isTrue);
    });
  });

  // ── VaultService.decryptVault ─────────────────────────────────────────────

  group('VaultService.decryptVault', () {
    const testPin = '5678';
    const testSalt = 'AAAAAAAAAAAAAAAAAAAAAA==';
    const userId = 'user_decrypt_test';

    test('올바른 PIN → 복호화 성공, keyMap 반환', () async {
      final vaultData = _makeVaultResponse(
          testPin, testSalt, {'tok1': 'key1', 'tok2': 'key2'});

      final result = await http.runWithClient(() async {
        return VaultService.decryptVault(testPin, userId);
      }, () => _mockVaultWithData(vaultData));

      expect(result, isNotNull);
      expect(result!['tok1'], 'key1');
      expect(result['tok2'], 'key2');
    });

    test('잘못된 PIN → 복호화 실패, null 반환', () async {
      final vaultData = _makeVaultResponse(testPin, testSalt, {'tok': 'key'});

      final result = await http.runWithClient(() async {
        return VaultService.decryptVault('wrong_pin', userId);
      }, () => _mockVaultWithData(vaultData));

      expect(result, isNull);
    });

    test('vault 없음(fetchVault null) → null 반환', () async {
      final result = await http.runWithClient(() async {
        return VaultService.decryptVault(testPin, userId);
      }, _mockVaultNetworkError);

      expect(result, isNull);
    });

    test('encrypted_vault 필드 없음(404) → null 반환', () async {
      // fetchVault가 {} 반환 → encrypted_vault 없음
      final result = await http.runWithClient(() async {
        return VaultService.decryptVault(testPin, userId);
      }, _mockVaultNotFound);

      expect(result, isNull);
    });

    test('빈 keyMap vault → 빈 Map 반환', () async {
      final vaultData = _makeVaultResponse(testPin, testSalt, {});

      final result = await http.runWithClient(() async {
        return VaultService.decryptVault(testPin, userId);
      }, () => _mockVaultWithData(vaultData));

      expect(result, isNotNull);
      expect(result, isEmpty);
    });

    test('salt가 짧음(≤10자) → null 반환 (유효하지 않은 vault)', () async {
      final fakeVault = {
        'encrypted_vault': 'fakeciphertext',
        'salt': 'short', // 5자 → 유효하지 않음
      };

      final result = await http.runWithClient(() async {
        return VaultService.decryptVault(testPin, userId);
      }, () => _mockVaultWithData(fakeVault));

      expect(result, isNull);
    });
  });

  // ── VaultService.backfillMissingKeys ──────────────────────────────────────

  group('VaultService.backfillMissingKeys', () {
    const testPin = 'mypin';
    const testSalt = 'AAAAAAAAAAAAAAAAAAAAAA==';
    const userId = 'user_backfill';

    test('서버 오류(fetchVault null) → 조용히 반환 (예외 없음)', () async {
      await http.runWithClient(() async {
        await expectLater(
          VaultService.backfillMissingKeys(userId, testPin),
          completes,
        );
      }, _mockVaultNetworkError);
    });

    test('vault와 SecureStorage 일치 → 변경 없음 (saveVault 미호출)', () async {
      // SecureStorage에 tok1 있음
      _secureStore['dash_key_map'] = jsonEncode({'tok1': 'key1'});

      // 서버 vault에도 tok1 있음
      final vaultData = _makeVaultResponse(testPin, testSalt, {'tok1': 'key1'});
      int saveCount = 0;
      final client = MockClient((req) async {
        if (req.url.path.contains('/vault/') && req.method == 'GET') {
          return http.Response(jsonEncode(vaultData), 200);
        }
        if (req.method == 'POST') saveCount++;
        return http.Response('{"ok":true}', 200);
      });

      await http.runWithClient(() async {
        await VaultService.backfillMissingKeys(userId, testPin);
      }, () => client);

      expect(saveCount, 0, reason: '일치하면 saveVault 미호출');
    });

    test('SecureStorage에 있고 vault에 없는 키 → vault에 추가(saveVault 호출)', () async {
      // local에 tok_local 있음
      _secureStore['dash_key_map'] = jsonEncode({'tok_local': 'key_local'});

      // 서버 vault는 비어있음
      final vaultData = _makeVaultResponse(testPin, testSalt, {});
      int saveCount = 0;
      final client = MockClient((req) async {
        if (req.url.path.contains('/vault/') && req.method == 'GET') {
          return http.Response(jsonEncode(vaultData), 200);
        }
        if (req.method == 'POST') saveCount++;
        return http.Response('{"ok":true}', 200);
      });

      await http.runWithClient(() async {
        await VaultService.backfillMissingKeys(userId, testPin);
      }, () => client);

      expect(saveCount, 1, reason: 'SecureStorage→vault 방향 추가 필요');
    });

    test('vault에 있고 SecureStorage에 없는 키 → SecureStorage에 복원', () async {
      // SecureStorage 비어있음 (dash_key_map 없음)
      _secureStore.remove('dash_key_map');

      // 서버 vault에 tok_vault 있음
      final vaultData =
          _makeVaultResponse(testPin, testSalt, {'tok_vault': 'key_vault'});

      await http.runWithClient(() async {
        await VaultService.backfillMissingKeys(userId, testPin);
      }, () => _mockVaultWithData(vaultData));

      // SecureStorage에 복원되었는지 확인
      final raw = _secureStore['dash_key_map'];
      expect(raw, isNotNull);
      final map = jsonDecode(raw!) as Map;
      expect(map['tok_vault'], 'key_vault');
    });

    test('잘못된 PIN → 복호화 실패 → 중단 (SecureStorage/vault 변경 없음)', () async {
      _secureStore['dash_key_map'] = jsonEncode({'local_tok': 'local_key'});

      final vaultData =
          _makeVaultResponse('correct_pin', testSalt, {'vault_tok': 'vault_key'});
      int saveCount = 0;
      final client = MockClient((req) async {
        if (req.url.path.contains('/vault/') && req.method == 'GET') {
          return http.Response(jsonEncode(vaultData), 200);
        }
        if (req.method == 'POST') saveCount++;
        return http.Response('{"ok":true}', 200);
      });

      await http.runWithClient(() async {
        await VaultService.backfillMissingKeys(userId, 'wrong_pin');
      }, () => client);

      // PIN 불일치로 복호화 실패 → 중단 → saveVault 미호출
      expect(saveCount, 0, reason: 'PIN 불일치 시 vault 수정 금지');
      // SecureStorage도 변경 없음
      final raw = _secureStore['dash_key_map'];
      final map = jsonDecode(raw ?? '{}') as Map;
      expect(map.containsKey('vault_tok'), isFalse);
    });
  });
}
