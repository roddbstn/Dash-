// =============================================================================
// SharedDbPreviewScreen 위젯 테스트
//
// 테스트 대상:
//   - 로딩 상태 초기 표시
//   - API 404 → 에러 화면 표시
//   - 네트워크 예외 → 에러 화면 표시
//   - 정상 데이터 → 레코드 정보 표시
//   - fallbackKey 파라미터 전달 시 충돌 없음
//
// own-record check (owner_user_id == currentUser.uid → pop) 테스트는
// FirebaseAuth.instance에 특정 uid를 주입할 수 없어 통합 테스트 대상.
// =============================================================================

import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dash_mobile/screens/shared_db_preview_screen.dart';

// ── 테스트용 공유 레코드 샘플 데이터 ───────────────────────────────────────
Map<String, dynamic> _sampleRecord({String ownerUid = 'other_user'}) => {
      'share_token': 'test_token',
      'case_name': '홍길동 사례',
      'dong': '관악동',
      'author_name': '이상담',
      'provision_type': '직접',
      'method': '방문',
      'service_type': '아동보호',
      'service_category': '복지',
      'service_name': '긴급지원',
      'target': '아동',
      'location': '서울 관악구',
      'start_time': '2025-03-17T10:00:00',
      'end_time': '2025-03-17T11:00:00',
      'service_count': 1,
      'travel_time': 15,
      'service_description': '서비스 내용 테스트',
      'agent_opinion': '소견 테스트',
      'created_at': '2025-03-17T09:00:00',
      'owner_user_id': ownerUid,
      'encrypted_blob': null,
    };

// ── HTTP Mock 헬퍼 ────────────────────────────────────────────────────────────

// UTF-8 인코딩 명시 — http.Response 기본값(latin-1)으로 한글이 깨지는 것 방지
http.Response _jsonResponse(Map<String, dynamic> body, int statusCode) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.Response.bytes(
    bytes,
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

MockClient _mockClientSuccess({Map<String, dynamic>? record}) {
  final data = record ?? _sampleRecord();
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/key')) {
      return _jsonResponse({'error': 'key_not_found'}, 404);
    }
    if (path.contains('/shared-records/')) {
      return _jsonResponse(data, 200);
    }
    return http.Response('{}', 404);
  });
}

MockClient _mockClient404() =>
    MockClient((_) async => http.Response('{}', 404));

MockClient _mockClientException() =>
    MockClient((_) async => throw Exception('네트워크 오류'));

// ── 테스트 헬퍼: 위젯을 MaterialApp으로 감싸 pump ──────────────────────────
Future<void> _pumpScreen(
  WidgetTester tester,
  Widget widget,
) async {
  await tester.pumpWidget(MaterialApp(home: widget));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Firebase Core Pigeon 채널을 모킹 (firebase_core_platform_interface/test.dart)
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  // ── 로딩 상태 ────────────────────────────────────────────────────────────
  group('SharedDbPreviewScreen — 로딩 상태', () {
    testWidgets('초기 로딩 시 CircularProgressIndicator 표시', (tester) async {
      // API 타임아웃(10s) 직전에 응답 → pump(11s)으로 모든 타이머 정리
      final mockClient = MockClient((req) async {
        await Future.delayed(const Duration(seconds: 9, milliseconds: 999));
        return http.Response('{}', 404);
      });
      await http.runWithClient(() async {
        await _pumpScreen(
            tester, const SharedDbPreviewScreen(token: 'test_token'));
        // 첫 프레임: 네트워크 응답 전 → 로딩 상태
        await tester.pump(Duration.zero);
        expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
        // 타이머 전부 소진 (9.999s mock 응답 + 10s API 타임아웃)
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
      }, () => mockClient);
    });
  });

  // ── 에러 상태 ─────────────────────────────────────────────────────────────
  group('SharedDbPreviewScreen — 에러 상태', () {
    testWidgets('fetchSharedRecord 404 → 에러 메시지 표시', (tester) async {
      await http.runWithClient(() async {
        await _pumpScreen(
            tester, const SharedDbPreviewScreen(token: 'not_found'));
        await tester.pumpAndSettle();
        expect(
            find.text('존재하지 않거나 만료된 공유 링크입니다.'), findsOneWidget);
      }, _mockClient404);
    });

    testWidgets('네트워크 예외 → 에러 화면 표시 (API가 예외를 catch → null 반환)', (tester) async {
      // ApiService.fetchSharedRecord 내부에서 예외를 catch하고 null 반환하므로
      // 404 응답과 동일한 에러 메시지('존재하지 않거나 만료된 공유 링크입니다.')가 표시됨.
      await http.runWithClient(() async {
        await _pumpScreen(
            tester, const SharedDbPreviewScreen(token: 'test_token'));
        await tester.pumpAndSettle();
        expect(find.text('존재하지 않거나 만료된 공유 링크입니다.'), findsOneWidget);
      }, _mockClientException);
    });

    testWidgets('에러 화면에 "돌아가기" 버튼 표시', (tester) async {
      await http.runWithClient(() async {
        await _pumpScreen(
            tester, const SharedDbPreviewScreen(token: 'not_found'));
        await tester.pumpAndSettle();
        expect(find.text('돌아가기'), findsOneWidget);
      }, _mockClient404);
    });
  });

  // ── 정상 데이터 표시 ─────────────────────────────────────────────────────
  group('SharedDbPreviewScreen — 정상 데이터 표시', () {
    testWidgets('사례명, 상담원명 표시', (tester) async {
      await http.runWithClient(() async {
        await _pumpScreen(
            tester, const SharedDbPreviewScreen(token: 'test_token'));
        await tester.pumpAndSettle();
        expect(find.text('홍길동 사례'), findsOneWidget);
        expect(find.textContaining('이상담'), findsOneWidget);
      }, _mockClientSuccess);
    });

    testWidgets('제공구분, 제공방법 메타정보 표시', (tester) async {
      await http.runWithClient(() async {
        await _pumpScreen(
            tester, const SharedDbPreviewScreen(token: 'test_token'));
        await tester.pumpAndSettle();
        expect(find.text('직접'), findsOneWidget);
        expect(find.text('방문'), findsOneWidget);
      }, _mockClientSuccess);
    });

    testWidgets('서비스 내용 표시', (tester) async {
      await http.runWithClient(() async {
        await _pumpScreen(
            tester, const SharedDbPreviewScreen(token: 'test_token'));
        await tester.pumpAndSettle();
        expect(find.text('서비스 내용 테스트'), findsOneWidget);
      }, _mockClientSuccess);
    });

    testWidgets('상담원 소견 표시', (tester) async {
      await http.runWithClient(() async {
        await _pumpScreen(
            tester, const SharedDbPreviewScreen(token: 'test_token'));
        await tester.pumpAndSettle();
        expect(find.text('소견 테스트'), findsOneWidget);
      }, _mockClientSuccess);
    });

    testWidgets('"내 DB로 저장" CTA 버튼 표시', (tester) async {
      await http.runWithClient(() async {
        await _pumpScreen(
            tester, const SharedDbPreviewScreen(token: 'test_token'));
        await tester.pumpAndSettle();
        expect(find.text('내 DB로 저장'), findsOneWidget);
      }, _mockClientSuccess);
    });

    testWidgets('소견 없는 레코드 → "(작성된 소견 없음)" 표시', (tester) async {
      final record = _sampleRecord();
      record['agent_opinion'] = '';
      await http.runWithClient(() async {
        await _pumpScreen(
            tester, const SharedDbPreviewScreen(token: 'test_token'));
        await tester.pumpAndSettle();
        expect(find.text('(작성된 소견 없음)'), findsOneWidget);
      }, () => _mockClientSuccess(record: record));
    });
  });

  // ── fallbackKey 파라미터 ──────────────────────────────────────────────────
  group('SharedDbPreviewScreen — fallbackKey 파라미터', () {
    testWidgets('fallbackKey 전달 시 오류 없이 정상 로드', (tester) async {
      await http.runWithClient(() async {
        await _pumpScreen(
          tester,
          const SharedDbPreviewScreen(
            token: 'test_token',
            fallbackKey: 'legacy_encryption_key_12345',
          ),
        );
        await tester.pumpAndSettle();
        // encrypted_blob이 없으므로 fallbackKey는 사용되지 않음 — 화면 정상 표시
        expect(find.text('홍길동 사례'), findsOneWidget);
      }, _mockClientSuccess);
    });

    testWidgets('fallbackKey null 전달 시 정상 로드', (tester) async {
      await http.runWithClient(() async {
        await _pumpScreen(
          tester,
          const SharedDbPreviewScreen(
            token: 'test_token',
            fallbackKey: null,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('홍길동 사례'), findsOneWidget);
      }, _mockClientSuccess);
    });
  });

  // ── onSaved 콜백 ──────────────────────────────────────────────────────────
  group('SharedDbPreviewScreen — onSaved 콜백', () {
    testWidgets('onSaved null 전달 시 오류 없음', (tester) async {
      await http.runWithClient(() async {
        await _pumpScreen(
          tester,
          const SharedDbPreviewScreen(
            token: 'test_token',
            onSaved: null,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('홍길동 사례'), findsOneWidget);
      }, _mockClientSuccess);
    });
  });
}
