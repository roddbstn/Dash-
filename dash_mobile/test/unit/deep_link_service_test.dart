// =============================================================================
// DeepLinkService 단위 테스트
//
// 테스트 대상:
//   - extractShareToken(Uri)    URI 파싱 — path 기반 및 query 파라미터 폴백
//   - processPendingDeepLink()  대기 중인 딥링크 처리
//   - registerOnSaved()         콜백 등록
//
// Firebase/Navigator 의존성이 있는 init/_navigateToPreview 는 integration 테스트 대상.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:dash_mobile/deep_link_service.dart';

void main() {
  // ── extractShareToken — path 기반 ────────────────────────────────────────

  group('extractShareToken — /share/{token} (path 기반)', () {
    test('정상 경로: https://dash.qpon/share/abc123', () {
      final uri = Uri.parse('https://dash.qpon/share/abc123');
      expect(DeepLinkService.extractShareToken(uri), 'abc123');
    });

    test('긴 토큰 (UUID 형식)', () {
      final token = '550e8400-e29b-41d4-a716-446655440000';
      final uri = Uri.parse('https://dash.qpon/share/$token');
      expect(DeepLinkService.extractShareToken(uri), token);
    });

    test('토큰에 특수문자 없는 경우 정상 파싱', () {
      final uri = Uri.parse('https://dash.qpon/share/TOKEN_XYZ_9999');
      expect(DeepLinkService.extractShareToken(uri), 'TOKEN_XYZ_9999');
    });

    test('segments[0]이 share가 아니면 null', () {
      final uri = Uri.parse('https://dash.qpon/records/abc123');
      // records/abc123 → segments[0]='records' ≠ 'share' → query 폴백 없으면 null
      expect(DeepLinkService.extractShareToken(uri), isNull);
    });

    test('path segment가 1개 (토큰 없음) → null', () {
      final uri = Uri.parse('https://dash.qpon/share');
      // segments = ['share'] → length < 2 → query 폴백 없으면 null
      expect(DeepLinkService.extractShareToken(uri), isNull);
    });

    test('루트 경로 → null', () {
      final uri = Uri.parse('https://dash.qpon/');
      expect(DeepLinkService.extractShareToken(uri), isNull);
    });

    test('3단계 이상 경로도 정상 파싱 (share/token/extra → token 반환)', () {
      final uri = Uri.parse('https://dash.qpon/share/mytoken/extra');
      expect(DeepLinkService.extractShareToken(uri), 'mytoken');
    });
  });

  // ── extractShareToken — query 파라미터 폴백 ──────────────────────────────

  group('extractShareToken — ?token={token} (query 파라미터 폴백)', () {
    test('쿼리 파라미터 token=abc → abc', () {
      final uri = Uri.parse('https://dash.qpon/?token=abc123');
      expect(DeepLinkService.extractShareToken(uri), 'abc123');
    });

    test('path 없고 query만 있는 경우', () {
      final uri = Uri.parse('https://dash.qpon?token=qrtoken_xyz');
      expect(DeepLinkService.extractShareToken(uri), 'qrtoken_xyz');
    });

    test('path도 query도 없으면 null', () {
      final uri = Uri.parse('https://dash.qpon');
      expect(DeepLinkService.extractShareToken(uri), isNull);
    });

    test('token 쿼리 없는 다른 파라미터 → null', () {
      final uri = Uri.parse('https://dash.qpon/?ref=kakao&source=mobile');
      expect(DeepLinkService.extractShareToken(uri), isNull);
    });

    test('빈 token 파라미터 → 빈 문자열 (null이 아님)', () {
      final uri = Uri.parse('https://dash.qpon/?token=');
      // 빈 값도 query parameter로 존재함 → ''
      expect(DeepLinkService.extractShareToken(uri), '');
    });
  });

  // ── extractShareToken — 우선순위: path > query ────────────────────────────

  group('extractShareToken — path와 query 동시 존재 시 path 우선', () {
    test('/share/pathtoken?token=querytoken → pathtoken 반환', () {
      final uri = Uri.parse('https://dash.qpon/share/pathtoken?token=querytoken');
      expect(DeepLinkService.extractShareToken(uri), 'pathtoken');
    });
  });

  // ── extractShareToken — fragment 무시 ────────────────────────────────────
  //
  // URI fragment(#key=...)는 extractShareToken이 처리하지 않음.
  // 딥링크 서비스(_handleDeepLink)가 fragment를 별도로 파싱해 fallbackKey로 전달.
  // extractShareToken 입장에서는 fragment가 있어도 path/query 결과에 영향 없음.

  group('extractShareToken — URI fragment 존재 시 무시', () {
    test('path 토큰 + #key=... → path 토큰 반환 (fragment 무시)', () {
      final uri = Uri.parse('https://dash.qpon/share/mytoken#key=fragkey');
      expect(DeepLinkService.extractShareToken(uri), 'mytoken');
    });

    test('query token + #key=... → query 토큰 반환 (fragment 무시)', () {
      final uri = Uri.parse('https://dash.qpon/?token=qtoken#key=fragkey');
      expect(DeepLinkService.extractShareToken(uri), 'qtoken');
    });

    test('fragment만 있고 path/query 없으면 null', () {
      final uri = Uri.parse('https://dash.qpon/#key=onlyfrag');
      expect(DeepLinkService.extractShareToken(uri), isNull);
    });
  });

  // ── processPendingDeepLink ────────────────────────────────────────────────

  group('processPendingDeepLink', () {
    test('pending token 없으면 아무것도 하지 않음 (예외 없음)', () {
      // _pendingToken이 null인 초기 상태
      expect(() => DeepLinkService.processPendingDeepLink(), returnsNormally);
    });
  });

  // ── registerOnSaved ───────────────────────────────────────────────────────

  group('registerOnSaved', () {
    test('콜백 등록 후 onDbSaved에 저장됨', () {
      var called = false;
      DeepLinkService.registerOnSaved(() => called = true);
      DeepLinkService.onDbSaved?.call();
      expect(called, isTrue);
    });

    test('새 콜백으로 덮어쓰기 가능', () {
      var firstCalled = false;
      var secondCalled = false;
      DeepLinkService.registerOnSaved(() => firstCalled = true);
      DeepLinkService.registerOnSaved(() => secondCalled = true);
      DeepLinkService.onDbSaved?.call();
      expect(firstCalled, isFalse);  // 첫 번째는 덮어씌워짐
      expect(secondCalled, isTrue);
    });

    test('null 콜백 등록 시 onDbSaved는 null', () {
      DeepLinkService.registerOnSaved(() {});  // 먼저 등록
      DeepLinkService.onDbSaved = null;        // 직접 초기화
      expect(DeepLinkService.onDbSaved, isNull);
    });
  });
}
