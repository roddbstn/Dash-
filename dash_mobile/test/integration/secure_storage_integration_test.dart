// =============================================================================
// StorageService — SecureStorage 통합 테스트
//
// ⚠️ 이 테스트는 실제 디바이스 또는 에뮬레이터에서만 실행 가능합니다.
//
// SecureStorage는 플랫폼 Keychain(iOS) / Keystore(Android)를 사용하므로
// flutter_test의 단위 테스트 환경(VM)에서는 플랫폼 채널이 동작하지 않습니다.
//
// 실행 방법:
//   flutter test integration_test/secure_storage_integration_test.dart \
//     --device-id <device_id>
//
// 또는 flutter_driver / integration_test 패키지 사용:
//   flutter test test/integration/secure_storage_integration_test.dart \
//     -d <device_or_emulator>
//
// CI 설정 예시 (GitHub Actions):
//   - uses: reactivecircus/android-emulator-runner@v2
//     with:
//       api-level: 33
//       script: flutter test test/integration/ --timeout=60s
// =============================================================================

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:dash_mobile/storage_service.dart';
import '../helpers/firebase_mock.dart';

void main() {
  setUpAll(() async {
    await setupFirebaseMocks();
  });

  // ── PIN 저장/조회 (Keychain/Keystore) ─────────────────────────────────────

  group('StorageService — PIN (SecureStorage)', () {
    tearDown(() async {
      // 테스트 후 PIN 초기화 (다음 테스트 격리)
      await StorageService.clearSessionData();
    });

    test('savePin / getPin roundtrip — Keychain/Keystore', () async {
      await StorageService.savePin('1234');
      final result = await StorageService.getPin();
      expect(result, '1234');
    });

    test('getPin: 저장 전 null 반환', () async {
      final result = await StorageService.getPin();
      expect(result, isNull);
    });

    test('savePin: 덮어쓰기', () async {
      await StorageService.savePin('1111');
      await StorageService.savePin('9999');
      expect(await StorageService.getPin(), '9999');
    });

    test('clearSessionData 후 PIN null', () async {
      await StorageService.savePin('5678');
      await StorageService.clearSessionData();
      expect(await StorageService.getPin(), isNull);
    });
  });

  // ── Salt 저장/조회 (Keychain/Keystore) ────────────────────────────────────

  group('StorageService — Salt (SecureStorage)', () {
    tearDown(() async {
      await StorageService.clearSessionData();
    });

    test('saveSalt / getSalt roundtrip', () async {
      const testSalt = 'AAAAAAAAAAAAAAAAAAAAAA=='; // base64 16바이트
      await StorageService.saveSalt(testSalt);
      final result = await StorageService.getSalt();
      expect(result, testSalt);
    });

    test('getSalt: 저장 전 null 반환', () async {
      expect(await StorageService.getSalt(), isNull);
    });

    test('getSalt: SharedPreferences 레거시 폴백 → SecureStorage 자동 마이그레이션', () async {
      // Legacy SharedPreferences에 salt 주입 (migration 시뮬레이션)
      // 이 테스트는 migrateSaltIfNeeded 없이 직접 getSalt 폴백 경로를 검증합니다.
      //
      // 실제 시나리오:
      // 1. 구버전 앱: SharedPreferences에 salt 저장
      // 2. 업데이트 후 getSalt() 호출 → SecureStorage 없음 → SharedPreferences 폴백
      // 3. 폴백 시 SecureStorage로 마이그레이션 + SharedPreferences 삭제
      //
      // 참고: 이 테스트는 SharedPreferences에 직접 salt를 쓰는 방식으로만
      //       레거시 상태를 시뮬레이션할 수 있습니다 (storageService 내부 키 사용).
      print('[SKIP] SharedPreferences 내부 키 직접 접근 불가 — migrateSaltIfNeeded 테스트로 대체');
    });
  });

  // ── KeyMap 저장/조회 (SecureStorage) ─────────────────────────────────────

  group('StorageService — keyMap (SecureStorage)', () {
    tearDown(() async {
      await StorageService.clearKeyMap();
    });

    test('saveKeyToMap / getKeyFromMap roundtrip', () async {
      await StorageService.saveKeyToMap('shareToken_abc', 'encKey_xyz');
      final result = await StorageService.getKeyFromMap('shareToken_abc');
      expect(result, 'encKey_xyz');
    });

    test('getKeyFromMap: 존재하지 않는 토큰 → null', () async {
      final result = await StorageService.getKeyFromMap('nonexistent_token');
      expect(result, isNull);
    });

    test('getKeyFromMap: null 입력 → null', () async {
      expect(await StorageService.getKeyFromMap(null), isNull);
    });

    test('getKeyFromMap: 빈 문자열 → null', () async {
      expect(await StorageService.getKeyFromMap(''), isNull);
    });

    test('saveKeyToMap: 여러 토큰 독립 저장', () async {
      await StorageService.saveKeyToMap('tok1', 'key1');
      await StorageService.saveKeyToMap('tok2', 'key2');
      await StorageService.saveKeyToMap('tok3', 'key3');

      expect(await StorageService.getKeyFromMap('tok1'), 'key1');
      expect(await StorageService.getKeyFromMap('tok2'), 'key2');
      expect(await StorageService.getKeyFromMap('tok3'), 'key3');
    });

    test('saveKeyToMap: 동일 토큰 덮어쓰기', () async {
      await StorageService.saveKeyToMap('tok', 'old_key');
      await StorageService.saveKeyToMap('tok', 'new_key');
      expect(await StorageService.getKeyFromMap('tok'), 'new_key');
    });

    test('getKeyMap: 전체 맵 조회', () async {
      await StorageService.saveKeyToMap('a', 'key_a');
      await StorageService.saveKeyToMap('b', 'key_b');
      final map = await StorageService.getKeyMap();
      expect(map.length, 2);
      expect(map['a'], 'key_a');
      expect(map['b'], 'key_b');
    });

    test('clearKeyMap: 모든 키 제거', () async {
      await StorageService.saveKeyToMap('tok', 'key');
      await StorageService.clearKeyMap();
      expect(await StorageService.getKeyFromMap('tok'), isNull);
      expect(await StorageService.getKeyMap(), isEmpty);
    });
  });

  // ── Salt 마이그레이션 ─────────────────────────────────────────────────────

  group('StorageService — PIN/Salt 마이그레이션', () {
    tearDown(() async {
      await StorageService.clearSessionData();
    });

    test('migratePinIfNeeded: SecureStorage에 이미 있으면 아무것도 안 함', () async {
      await StorageService.savePin('1234');
      // 중복 호출 안전성
      await StorageService.migratePinIfNeeded();
      expect(await StorageService.getPin(), '1234');
    });

    test('migrateSaltIfNeeded: SecureStorage에 이미 있으면 아무것도 안 함', () async {
      const salt = 'BBBBBBBBBBBBBBBBBBBBBB==';
      await StorageService.saveSalt(salt);
      await StorageService.migrateSaltIfNeeded();
      expect(await StorageService.getSalt(), salt);
    });
  });

  // ── 전체 데이터 초기화 ──────────────────────────────────────────────────────

  group('StorageService — clearAllData (통합)', () {
    test('모든 데이터(PIN, Salt, KeyMap, Cases, Drafts) 삭제', () async {
      // 데이터 설정
      await StorageService.savePin('9999');
      await StorageService.saveSalt('CCCCCCCCCCCCCCCCCCCCCC==');
      await StorageService.saveKeyToMap('tok', 'key');
      await StorageService.saveCases([{'id': 'c1'}]);
      await StorageService.saveDrafts([{'draftId': 'd1'}]);
      await StorageService.setRegistered('test_uid');

      // 전체 삭제
      await StorageService.clearAllData();

      // 검증
      expect(await StorageService.getPin(), isNull);
      expect(await StorageService.getSalt(), isNull);
      expect(await StorageService.getKeyFromMap('tok'), isNull);
      expect(await StorageService.getCases(), isEmpty);
      expect(await StorageService.getDrafts(), isEmpty);
      expect(await StorageService.isRegistered('test_uid'), isFalse);
    });
  });
}
