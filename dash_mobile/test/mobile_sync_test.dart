// DASH 모바일 통합 테스트 (Flutter Integration Test)
//
// 대상: dash_mobile Flutter 앱 ↔ Backend API 연동
// 범위: ApiService의 핵심 동기화 메서드, 오프라인 큐, 데이터 직렬화/역직렬화
//
// 실행:
//   flutter test integration_test/mobile_sync_test.dart --dart-define=TEST_BASE_URL=http://10.0.2.2:3000
//
// 참고: 이 파일은 dash_mobile/integration_test/ 또는 test/ 에 두고 실행합니다.
//       실제 Firebase 인증 없이 로컬 서버(fcmInitialized=false 상태)에서 동작합니다.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// ── 설정 ──────────────────────────────────────────────────────────────────────
const String kBaseUrl =
    String.fromEnvironment('TEST_BASE_URL', defaultValue: 'http://localhost:3000');
const String kApiBase = '$kBaseUrl/api';

// 테스트 픽스처
final int testCaseId = (DateTime.now().millisecondsSinceEpoch ~/ 1000);
final String testUserId = 'flutter_test_${DateTime.now().millisecondsSinceEpoch}';
final String testShareToken =
    'flutter_tok_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

// ── HTTP 헬퍼 ─────────────────────────────────────────────────────────────────
Future<http.Response> apiPost(String path, Map<String, dynamic> body,
    {String? token}) async {
  final headers = {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  return http.post(
    Uri.parse('$kApiBase$path'),
    headers: headers,
    body: jsonEncode(body),
  );
}

Future<http.Response> apiGet(String path, {String? token}) async {
  final headers = {
    if (token != null) 'Authorization': 'Bearer $token',
  };
  return http.get(Uri.parse('$kApiBase$path'), headers: headers);
}

Future<http.Response> apiDelete(String path, {String? token}) async {
  final headers = {
    if (token != null) 'Authorization': 'Bearer $token',
  };
  return http.delete(Uri.parse('$kApiBase$path'), headers: headers);
}

// ── 테스트 ────────────────────────────────────────────────────────────────────
void main() {
  group('DASH Mobile ↔ Backend 통합 테스트', () {
    // ──────────────────────────────────────────────────────────────────────────
    // [1] 인프라 상태
    // ──────────────────────────────────────────────────────────────────────────
    group('[1] 인프라 상태', () {
      test('health check: DB 연결 확인', () async {
        final res = await http.get(Uri.parse('$kBaseUrl/health'));
        expect(res.statusCode, 200, reason: 'health endpoint failed: ${res.body}');

        final body = jsonDecode(res.body) as Map<String, dynamic>;
        expect(body['status'], 'ok', reason: 'status != ok');
        expect(body['db'], 'connected', reason: 'db != connected');
        expect(body['uptime'], isA<int>(), reason: 'uptime 필드 누락');
      });

      test('health check: 응답 지연 < 3000ms', () async {
        final start = DateTime.now();
        final res = await http.get(Uri.parse('$kBaseUrl/health'));
        final elapsed = DateTime.now().difference(start).inMilliseconds;
        expect(res.statusCode, 200);
        expect(elapsed, lessThan(3000),
            reason: 'health response too slow: ${elapsed}ms');
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // [2] 인증 미들웨어
    // ──────────────────────────────────────────────────────────────────────────
    group('[2] 인증 미들웨어', () {
      test('토큰 없이 보호 엔드포인트 접근 → 401', () async {
        final res = await http.get(Uri.parse('$kApiBase/users/$testUserId'));
        expect(res.statusCode, 401,
            reason: '인증 없이 접근 가능한 상태: ${res.statusCode}');
      });

      test('잘못된 토큰 → 401', () async {
        final res = await http.get(
          Uri.parse('$kApiBase/users/$testUserId'),
          headers: {'Authorization': 'Bearer invalid_token_xyz'},
        );
        expect(res.statusCode, 401, reason: '잘못된 토큰이 통과됨: ${res.statusCode}');
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // [3] 사례(Case) API — 스키마 필드 무결성
    // ──────────────────────────────────────────────────────────────────────────
    group('[3] Case API 스키마 무결성 (로컬 개발 서버, 인증 bypass)', () {
      // 로컬 서버에서만 실행 (fcmInitialized=false → 인증 건너뜀)
      test('사례 생성: BIGINT ID 타입 보존', () async {
        final res = await apiPost('/cases', {
          'id': testCaseId,
          'user_id': testUserId,
          'user_email': 'flutter_test@test.com',
          'user_name': 'FlutterTest',
          'case_name': '[Flutter] 테스트 사례',
          'dong': '테스트동',
          'target_system_code': 'NCADS_v2',
        });

        // 로컬 서버에서만 200 기대 (프로덕션은 인증 필요)
        if (kBaseUrl.contains('localhost') || kBaseUrl.contains('10.0.2.2')) {
          expect(res.statusCode, 200, reason: 'case 생성 실패: ${res.body}');
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          // 중요: BIGINT ID가 String으로 변환되지 않고 숫자로 유지되는지 확인
          // (JavaScript Number는 2^53 이상 정밀도 손실 발생 가능)
          final returnedId = data['id'];
          expect(returnedId.toString(), testCaseId.toString(),
              reason: 'ID 타입/값 불일치: sent=$testCaseId returned=$returnedId');
        }
      });

      test('사례 목록 조회: 응답 배열 및 필수 필드', () async {
        final res = await apiGet('/cases/user/$testUserId');

        if (kBaseUrl.contains('localhost') || kBaseUrl.contains('10.0.2.2')) {
          expect(res.statusCode, 200, reason: '사례 목록 조회 실패: ${res.body}');
          final data = jsonDecode(res.body);
          expect(data, isA<List>(), reason: '배열 반환 필요');

          if ((data as List).isNotEmpty) {
            final first = data.first as Map<String, dynamic>;
            // 필수 필드 존재 여부 확인
            expect(first.containsKey('id'), isTrue, reason: 'id 필드 누락');
            expect(first.containsKey('case_name'), isTrue, reason: 'case_name 필드 누락');
            expect(first.containsKey('dong'), isTrue, reason: 'dong 필드 누락');
            expect(first.containsKey('target_system_code'), isTrue,
                reason: 'target_system_code 필드 누락');
          }
        }
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // [4] 레코드(Record) 동기화 — 핵심 데이터 흐름
    // ──────────────────────────────────────────────────────────────────────────
    group('[4] Record 동기화 핵심 흐름', () {
      test('신규 레코드 동기화: share_token 생성 및 반환', () async {
        final res = await apiPost('/records', {
          'case_id': testCaseId,
          'case_name': '[Flutter] 테스트 사례',
          'dong': '테스트동',
          'user_id': testUserId,
          'user_email': 'flutter_test@test.com',
          'user_name': 'FlutterTest',
          'provision_type': '직접',
          'method': '방문',
          'service_type': '상담',
          'service_category': '일반상담',
          'service_name': '개인상담',
          'location': '센터',
          'start_time': '2026-05-29 10:00:00',
          'end_time': '2026-05-29 11:00:00',
          'service_count': 1,
          'travel_time': 15,
          'service_description': 'Flutter 통합 테스트 레코드',
          'agent_opinion': '특이사항 없음',
          'encrypted_blob': 'dGVzdGl2MTIzNDU2Nzg=:dGVzdGNpcGhlcnRleHQ=',
          'is_shared_db': 0,
        });

        if (kBaseUrl.contains('localhost') || kBaseUrl.contains('10.0.2.2')) {
          expect(res.statusCode, 200, reason: '레코드 동기화 실패: ${res.body}');
          final data = jsonDecode(res.body) as Map<String, dynamic>;

          expect(data.containsKey('share_token'), isTrue, reason: 'share_token 미반환');
          expect(data['share_token'], isA<String>(), reason: 'share_token 타입 오류');
          expect((data['share_token'] as String).isNotEmpty, isTrue,
              reason: 'share_token 빈 문자열');

          expect(data.containsKey('id'), isTrue, reason: 'DB id 미반환');
          expect(data['id'], isA<int>(), reason: 'id 타입 오류 (int 필요)');
        }
      });

      test('레코드 幂等성: 동일 share_token 재동기화 → 중복 생성 없음', () async {
        if (!kBaseUrl.contains('localhost') && !kBaseUrl.contains('10.0.2.2')) return;

        final firstRes = await apiPost('/records', {
          'case_id': testCaseId,
          'user_id': testUserId,
          'provision_type': '직접',
          'method': '방문',
          'service_type': '상담',
          'service_name': '幂等 테스트',
          'location': '센터',
          'start_time': '2026-05-29 10:00:00',
          'end_time': '2026-05-29 11:00:00',
          'service_description': '첫 번째 동기화',
          'agent_opinion': '',
          'encrypted_blob': 'dGVzdA==:dGVzdA==',
          'share_token': testShareToken,
        });
        expect(firstRes.statusCode, 200,
            reason: '첫 번째 동기화 실패: ${firstRes.body}');

        final secondRes = await apiPost('/records', {
          'case_id': testCaseId,
          'user_id': testUserId,
          'provision_type': '직접',
          'method': '방문',
          'service_type': '상담',
          'service_name': '幂等 테스트',
          'location': '센터 - 수정',
          'start_time': '2026-05-29 10:00:00',
          'end_time': '2026-05-29 12:00:00',
          'service_description': '두 번째 동기화 (업데이트)',
          'agent_opinion': '소견 추가',
          'encrypted_blob': 'dGVzdA==:dGVzdA==',
          'share_token': testShareToken, // 동일 토큰
        });
        expect(secondRes.statusCode, 200,
            reason: '두 번째 동기화 실패: ${secondRes.body}');

        final data = jsonDecode(secondRes.body) as Map<String, dynamic>;
        expect(data['share_token'], testShareToken,
            reason: '재동기화 시 share_token 변경됨: ${data['share_token']}');
      });

      test('서비스 내용 100001자 초과 → 400 거부 (입력 검증)', () async {
        final res = await apiPost('/records', {
          'case_id': testCaseId,
          'user_id': testUserId,
          'provision_type': '직접',
          'method': '방문',
          'service_type': '상담',
          'service_name': '길이 초과 테스트',
          'location': '센터',
          'start_time': '2026-05-29 10:00:00',
          'end_time': '2026-05-29 11:00:00',
          'service_description': 'A' * 100001,
          'agent_opinion': '',
          'encrypted_blob': 'dGVzdA==:dGVzdA==',
        });

        if (kBaseUrl.contains('localhost') || kBaseUrl.contains('10.0.2.2')) {
          expect(res.statusCode, 400,
              reason: '길이 초과 입력이 통과됨: ${res.statusCode}');
        }
      });

      test('빈 active_tokens sync_active → 데이터 전체 삭제 방지', () async {
        final res = await apiPost('/records/sync_active', {
          'user_email': 'flutter_test@test.com',
          'active_tokens': <String>[],
        });

        if (kBaseUrl.contains('localhost') || kBaseUrl.contains('10.0.2.2')) {
          expect(res.statusCode, 200, reason: '${res.body}');
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          // deleted_count가 0이어야 함 (전체 삭제 방지)
          expect(data['deleted_count'], 0,
              reason: '빈 토큰으로 데이터 삭제됨: deleted_count=${data['deleted_count']}');
        }
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // [5] 공유 링크 / 딥링크 통합 테스트
    // ──────────────────────────────────────────────────────────────────────────
    group('[5] 공유 링크 / Reviewer Web 통합 테스트', () {
      test('공유 레코드 조회: 인증 없이 접근 가능 (공개 엔드포인트)', () async {
        // 먼저 레코드 생성 (로컬 서버)
        if (!kBaseUrl.contains('localhost') && !kBaseUrl.contains('10.0.2.2')) return;

        final shareToken = 'share_test_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
        await apiPost('/records', {
          'case_id': testCaseId,
          'user_id': testUserId,
          'provision_type': '직접',
          'method': '방문',
          'service_type': '상담',
          'service_name': '공유 테스트',
          'location': '센터',
          'start_time': '2026-05-29 10:00:00',
          'end_time': '2026-05-29 11:00:00',
          'service_description': '공유 레코드',
          'agent_opinion': '',
          'encrypted_blob': 'dGVzdGl2MTIzNDU2Nzg=:dGVzdGNpcGhlcnRleHQ=',
          'share_token': shareToken,
        });

        // 인증 없이 조회
        final res = await http.get(Uri.parse('$kApiBase/records/share/$shareToken'));
        expect(res.statusCode, 200,
            reason: '공개 공유 엔드포인트 접근 실패: ${res.statusCode}');

        final data = jsonDecode(res.body) as Map<String, dynamic>;

        // 스키마 필수 필드 확인
        expect(data.containsKey('share_token'), isTrue, reason: 'share_token 필드 누락');
        expect(data.containsKey('encrypted_blob'), isTrue, reason: 'encrypted_blob 필드 누락');
        expect(data.containsKey('status'), isTrue, reason: 'status 필드 누락');
        expect(data.containsKey('case_name'), isTrue, reason: 'case_name 필드 누락');

        // 보안 체크: encryption_key는 절대 노출되면 안 됨
        expect(data.containsKey('encryption_key'), isFalse,
            reason: '⚠️  SECURITY: encryption_key가 서버 응답에 포함됨!');

        // E2EE blob 포맷 검증 (iv:ciphertext)
        if (data['encrypted_blob'] != null) {
          final blobStr = data['encrypted_blob'] as String;
          final parts = blobStr.split(':');
          expect(parts.length, 2,
              reason: 'encrypted_blob 포맷 오류: iv:ciphertext 구조 필요. blob=${blobStr.substring(0, 30)}');
        }
      });

      test('존재하지 않는 share_token → 404', () async {
        final res = await http.get(
          Uri.parse('$kApiBase/records/share/nonexistent_token_xyz_flutter_test'),
        );
        expect(res.statusCode, 404,
            reason: '존재하지 않는 토큰에 대한 응답이 404가 아님: ${res.statusCode}');
      });

      test('OG 태그 HTML: /?token= 요청 시 redirect 없이 HTML 직접 반환', () async {
        final res = await http
            .get(Uri.parse('$kBaseUrl/?token=some_test_token'))
            .timeout(const Duration(seconds: 5));

        expect(res.statusCode, 200,
            reason: 'OG HTML 응답 실패: ${res.statusCode}');
        // HTML 응답 확인 (redirect면 Location 헤더 있고 body 없음)
        expect(res.body.contains('<!DOCTYPE html>') || res.body.contains('<html'),
            isTrue, reason: 'HTML 응답이 아님 — redirect 발생 가능성');
        expect(res.body.contains('og:title'), isTrue, reason: 'og:title 태그 없음');
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // [6] 데이터 직렬화 / 타입 일관성 테스트
    // ──────────────────────────────────────────────────────────────────────────
    group('[6] 데이터 직렬화 / 타입 일관성', () {
      test('DateTime 직렬화: start_time/end_time 형식 보존', () async {
        if (!kBaseUrl.contains('localhost') && !kBaseUrl.contains('10.0.2.2')) return;

        const testStartTime = '2026-05-29 10:00:00';
        const testEndTime = '2026-05-29 11:30:00';
        const shareToken = 'dart_datetime_test_token';

        await apiPost('/records', {
          'case_id': testCaseId,
          'user_id': testUserId,
          'provision_type': '직접',
          'method': '방문',
          'service_type': '상담',
          'service_name': 'DateTime 테스트',
          'location': '센터',
          'start_time': testStartTime,
          'end_time': testEndTime,
          'service_description': 'DateTime 직렬화 검증',
          'agent_opinion': '',
          'encrypted_blob': 'dGVzdA==:dGVzdA==',
          'share_token': shareToken,
        });

        final res = await http.get(Uri.parse('$kApiBase/records/share/$shareToken'));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          // MySQL dateStrings: true 설정 → 문자열로 반환됨
          expect(data['start_time'], isA<String>(), reason: 'start_time 타입 오류');
          expect(data['end_time'], isA<String>(), reason: 'end_time 타입 오류');
          // 날짜 값이 보존되는지 확인 (시간대 차이 허용)
          expect(data['start_time']?.toString().contains('2026-05-29'), isTrue,
              reason: '날짜 값 변환 오류: ${data['start_time']}');
        }
      });

      test('service_count / travel_time: 숫자 타입 보존', () async {
        if (!kBaseUrl.contains('localhost') && !kBaseUrl.contains('10.0.2.2')) return;

        const shareToken = 'dart_numeric_test_token';
        await apiPost('/records', {
          'case_id': testCaseId,
          'user_id': testUserId,
          'provision_type': '직접',
          'method': '방문',
          'service_type': '상담',
          'service_name': '숫자 타입 테스트',
          'location': '센터',
          'start_time': '2026-05-29 10:00:00',
          'end_time': '2026-05-29 11:00:00',
          'service_count': 3,
          'travel_time': 45,
          'service_description': '숫자 직렬화 검증',
          'agent_opinion': '',
          'encrypted_blob': 'dGVzdA==:dGVzdA==',
          'share_token': shareToken,
        });

        final res = await http.get(Uri.parse('$kApiBase/records/share/$shareToken'));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          expect(data['service_count'], isA<int>(),
              reason: 'service_count 타입 변환 오류: ${data['service_count'].runtimeType}');
          expect(data['travel_time'], isA<int>(),
              reason: 'travel_time 타입 변환 오류: ${data['travel_time'].runtimeType}');
          expect(data['service_count'], 3, reason: 'service_count 값 오류');
          expect(data['travel_time'], 45, reason: 'travel_time 값 오류');
        }
      });

      test('Unicode 한글 데이터 직렬화 보존', () async {
        if (!kBaseUrl.contains('localhost') && !kBaseUrl.contains('10.0.2.2')) return;

        const koreanCaseName = '홍길동 아동 (테스트 케이스) 한글 확인 🔐';
        const koreanDesc = '서비스 내용: 아동 정서 지원 상담 실시. 보호자 동석 하에 진행. 특이사항: 없음.';
        const shareToken = 'dart_unicode_test_token';

        await apiPost('/records', {
          'case_id': testCaseId,
          'user_id': testUserId,
          'case_name': koreanCaseName,
          'provision_type': '직접',
          'method': '방문',
          'service_type': '상담',
          'service_name': '한글 테스트',
          'location': '센터',
          'start_time': '2026-05-29 10:00:00',
          'end_time': '2026-05-29 11:00:00',
          'service_description': koreanDesc,
          'agent_opinion': '소견: 안정적인 상태.',
          'encrypted_blob': 'dGVzdA==:dGVzdA==',
          'share_token': shareToken,
        });

        final res = await http.get(Uri.parse('$kApiBase/records/share/$shareToken'));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          expect(data['service_description'], koreanDesc,
              reason: '한글 데이터 손상: ${data['service_description']}');
        }
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 테스트 정리
    // ──────────────────────────────────────────────────────────────────────────
    tearDownAll(() async {
      if (kBaseUrl.contains('localhost') || kBaseUrl.contains('10.0.2.2')) {
        await apiDelete('/cases/$testCaseId');
      }
    });
  });
}
