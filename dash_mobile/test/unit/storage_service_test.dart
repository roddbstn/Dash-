// =============================================================================
// StorageService 단위 테스트
// SharedPreferences 기반 메서드를 중심으로 커버
// FlutterSecureStorage는 플랫폼 채널 의존 → 별도 통합 테스트 필요
// =============================================================================

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dash_mobile/storage_service.dart';

void main() {
  // FlutterSecureStorage 플랫폼 채널 모킹 (clearSessionData / clearKeyMap 등에서 사용)
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 각 테스트 전 SharedPreferences 초기화
    SharedPreferences.setMockInitialValues({});
    // SecureStorage 채널 mock 핸들러 등록
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      // read → null, write/delete → null (성공)
      if (methodCall.method == 'read') return null;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // ── Cases ──────────────────────────────────────────────────────────────────

  group('StorageService — cases', () {
    test('getCases: 초기 상태에서 빈 리스트 반환', () async {
      final result = await StorageService.getCases();
      expect(result, isEmpty);
    });

    test('saveCases / getCases: 정상 저장 및 조회 (roundtrip)', () async {
      final testCases = [
        {'id': 'c1', 'maskedName': '홍**', 'dong': '종로구'},
        {'id': 'c2', 'maskedName': '김**', 'dong': '강남구'},
      ];
      await StorageService.saveCases(testCases);
      final result = await StorageService.getCases();
      expect(result.length, 2);
      expect(result[0]['id'], 'c1');
      expect(result[1]['maskedName'], '김**');
    });

    test('saveCases: 기존 데이터를 덮어씀', () async {
      await StorageService.saveCases([{'id': 'old'}]);
      await StorageService.saveCases([{'id': 'new1'}, {'id': 'new2'}]);
      final result = await StorageService.getCases();
      expect(result.length, 2);
      expect(result[0]['id'], 'new1');
    });

    test('saveCases: 빈 리스트 저장 가능', () async {
      await StorageService.saveCases([{'id': 'x'}]);
      await StorageService.saveCases([]);
      final result = await StorageService.getCases();
      expect(result, isEmpty);
    });

    test('saveCases: 중첩 구조 보존', () async {
      final complex = [
        {'id': 'c1', 'meta': {'counselor': '홍길동', 'tags': ['아동', '긴급']}}
      ];
      await StorageService.saveCases(complex);
      final result = await StorageService.getCases();
      expect((result[0]['meta'] as Map)['counselor'], '홍길동');
      expect((result[0]['meta'] as Map)['tags'], containsAll(['아동', '긴급']));
    });
  });

  // ── Drafts ─────────────────────────────────────────────────────────────────

  group('StorageService — drafts', () {
    test('getDrafts: 초기 상태에서 빈 리스트 반환', () async {
      final result = await StorageService.getDrafts();
      expect(result, isEmpty);
    });

    test('saveDrafts / getDrafts: roundtrip', () async {
      final drafts = [
        {'draftId': 'd1', 'content': '상담내용1'},
        {'draftId': 'd2', 'content': '상담내용2'},
      ];
      await StorageService.saveDrafts(drafts);
      final result = await StorageService.getDrafts();
      expect(result.length, 2);
      expect(result[0]['draftId'], 'd1');
    });

    test('saveDrafts: 빈 리스트 저장', () async {
      await StorageService.saveDrafts([{'draftId': 'x'}]);
      await StorageService.saveDrafts([]);
      expect(await StorageService.getDrafts(), isEmpty);
    });
  });

  // ── Counselors ─────────────────────────────────────────────────────────────

  group('StorageService — counselors', () {
    test('getCounselors: 초기 상태에서 빈 리스트 반환', () async {
      expect(await StorageService.getCounselors(), isEmpty);
    });

    test('saveCounselors / getCounselors: roundtrip', () async {
      final counselors = [
        {'id': 'co1', 'name': '상담원A', 'sort_order': 0},
        {'id': 'co2', 'name': '상담원B', 'sort_order': 1},
      ];
      await StorageService.saveCounselors(counselors);
      final result = await StorageService.getCounselors();
      expect(result.length, 2);
      expect(result[1]['name'], '상담원B');
    });
  });

  // ── Pending Vault Keys ─────────────────────────────────────────────────────

  group('StorageService — pendingVaultKeys', () {
    test('getPendingVaultKeys: 초기 상태에서 빈 리스트 반환', () async {
      expect(await StorageService.getPendingVaultKeys(), isEmpty);
    });

    test('addPendingVaultKey: 새 키 추가', () async {
      await StorageService.addPendingVaultKey(
        userId: 'u1',
        recordId: 'r1',
        encryptionKey: 'k1',
      );
      final keys = await StorageService.getPendingVaultKeys();
      expect(keys.length, 1);
      expect(keys[0]['userId'], 'u1');
      expect(keys[0]['recordId'], 'r1');
      expect(keys[0]['encryptionKey'], 'k1');
    });

    test('addPendingVaultKey: 동일 recordId는 덮어씀 (중복 방지)', () async {
      await StorageService.addPendingVaultKey(
          userId: 'u1', recordId: 'r1', encryptionKey: 'key_old');
      await StorageService.addPendingVaultKey(
          userId: 'u1', recordId: 'r1', encryptionKey: 'key_new');
      final keys = await StorageService.getPendingVaultKeys();
      expect(keys.length, 1);
      expect(keys[0]['encryptionKey'], 'key_new');
    });

    test('addPendingVaultKey: 다른 recordId는 별도 항목', () async {
      await StorageService.addPendingVaultKey(
          userId: 'u1', recordId: 'r1', encryptionKey: 'k1');
      await StorageService.addPendingVaultKey(
          userId: 'u1', recordId: 'r2', encryptionKey: 'k2');
      expect((await StorageService.getPendingVaultKeys()).length, 2);
    });

    test('addPendingVaultKey: 다수 항목 후 덮어쓰기 검증', () async {
      await StorageService.addPendingVaultKey(
          userId: 'u1', recordId: 'r1', encryptionKey: 'k1');
      await StorageService.addPendingVaultKey(
          userId: 'u1', recordId: 'r2', encryptionKey: 'k2');
      await StorageService.addPendingVaultKey(
          userId: 'u1', recordId: 'r1', encryptionKey: 'k1_updated');
      final keys = await StorageService.getPendingVaultKeys();
      expect(keys.length, 2);
      final r1 = keys.firstWhere((k) => k['recordId'] == 'r1');
      expect(r1['encryptionKey'], 'k1_updated');
    });

    test('savePendingVaultKeys: 전체 교체', () async {
      await StorageService.addPendingVaultKey(
          userId: 'u1', recordId: 'r1', encryptionKey: 'k1');
      await StorageService.savePendingVaultKeys([]);
      expect(await StorageService.getPendingVaultKeys(), isEmpty);
    });

    test('savePendingVaultKeys: 부분 목록으로 교체 (재시도 큐 시뮬레이션)', () async {
      await StorageService.addPendingVaultKey(
          userId: 'u1', recordId: 'r1', encryptionKey: 'k1');
      await StorageService.addPendingVaultKey(
          userId: 'u1', recordId: 'r2', encryptionKey: 'k2');
      // r1 성공, r2 실패 → r2만 남김
      await StorageService.savePendingVaultKeys(
          [{'userId': 'u1', 'recordId': 'r2', 'encryptionKey': 'k2'}]);
      final remaining = await StorageService.getPendingVaultKeys();
      expect(remaining.length, 1);
      expect(remaining[0]['recordId'], 'r2');
    });
  });

  // ── Pending Syncs ──────────────────────────────────────────────────────────

  group('StorageService — pendingSyncs', () {
    test('getPendingSyncs: 초기 상태에서 빈 리스트', () async {
      expect(await StorageService.getPendingSyncs(), isEmpty);
    });

    test('savePendingSyncs / getPendingSyncs: roundtrip', () async {
      final syncs = [
        {'id': 's1', 'data': '{}'},
        {'id': 's2', 'data': '{}'},
      ];
      await StorageService.savePendingSyncs(syncs);
      final result = await StorageService.getPendingSyncs();
      expect(result.length, 2);
      expect(result[0]['id'], 's1');
    });
  });

  // ── Registration ───────────────────────────────────────────────────────────

  group('StorageService — registration', () {
    test('isRegistered: 신규 uid는 false', () async {
      expect(await StorageService.isRegistered('brand_new_uid'), isFalse);
    });

    test('setRegistered / isRegistered: roundtrip', () async {
      await StorageService.setRegistered('uid_abc');
      expect(await StorageService.isRegistered('uid_abc'), isTrue);
    });

    test('isRegistered: UID별로 독립적', () async {
      await StorageService.setRegistered('uid_a');
      expect(await StorageService.isRegistered('uid_a'), isTrue);
      expect(await StorageService.isRegistered('uid_b'), isFalse);
    });

    test('setRegistered: 동일 uid 중복 호출 안전', () async {
      await StorageService.setRegistered('uid_x');
      await StorageService.setRegistered('uid_x'); // 중복 호출
      expect(await StorageService.isRegistered('uid_x'), isTrue);
    });
  });

  // ── Nickname ───────────────────────────────────────────────────────────────

  group('StorageService — nickname', () {
    test('getUserNickname: 미설정 시 null 반환', () async {
      expect(await StorageService.getUserNickname(), isNull);
    });

    test('saveUserNickname / getUserNickname: roundtrip', () async {
      await StorageService.saveUserNickname('홍길동');
      expect(await StorageService.getUserNickname(), '홍길동');
    });

    test('saveUserNickname: 덮어쓰기', () async {
      await StorageService.saveUserNickname('이름1');
      await StorageService.saveUserNickname('이름2');
      expect(await StorageService.getUserNickname(), '이름2');
    });

    test('saveUserNickname: 빈 문자열 허용', () async {
      await StorageService.saveUserNickname('');
      expect(await StorageService.getUserNickname(), '');
    });

    test('saveUserNickname: 유니코드/특수문자 보존', () async {
      const special = '홍길동 🎈 (테스트)';
      await StorageService.saveUserNickname(special);
      expect(await StorageService.getUserNickname(), special);
    });
  });

  // ── clearSessionData ───────────────────────────────────────────────────────

  group('StorageService — clearSessionData', () {
    test('cases, drafts, counselors, pendingSyncs, pendingVaultKeys 초기화', () async {
      await StorageService.saveCases([{'id': 'c1'}]);
      await StorageService.saveDrafts([{'draftId': 'd1'}]);
      await StorageService.saveCounselors([{'id': 'co1'}]);
      await StorageService.savePendingSyncs([{'id': 's1'}]);
      await StorageService.addPendingVaultKey(
          userId: 'u1', recordId: 'r1', encryptionKey: 'k1');
      await StorageService.saveUserNickname('홍길동');

      await StorageService.clearSessionData();

      expect(await StorageService.getCases(), isEmpty);
      expect(await StorageService.getDrafts(), isEmpty);
      expect(await StorageService.getCounselors(), isEmpty);
      expect(await StorageService.getPendingSyncs(), isEmpty);
      expect(await StorageService.getPendingVaultKeys(), isEmpty);
      expect(await StorageService.getUserNickname(), isNull);
    });
  });
}
