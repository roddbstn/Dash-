// =============================================================================
// SharedDbPreviewScreen — 순수 포매팅 함수 단위 테스트
//
// 테스트 대상 (@visibleForTesting 함수):
//   - formatProvisionDate(startStr, endStr)  제공일시 포매팅
//   - formatSharedDbDate(dateStr)            날짜 문자열 포매팅
//
// UI/ApiService 의존 부분은 Widget 테스트 또는 Integration 테스트 대상.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:dash_mobile/screens/shared_db_preview_screen.dart';

void main() {
  // ── formatSharedDbDate ────────────────────────────────────────────────────

  group('formatSharedDbDate — 날짜 포매팅', () {
    test('표준 ISO 8601 → yyyy.MM.dd HH:mm', () {
      expect(formatSharedDbDate('2025-03-15T09:30:00'), '2025.03.15 09:30');
    });

    test('자정(00:00) 경계값', () {
      expect(formatSharedDbDate('2025-01-01T00:00:00'), '2025.01.01 00:00');
    });

    test('23:59 경계값', () {
      expect(formatSharedDbDate('2025-12-31T23:59:00'), '2025.12.31 23:59');
    });

    test('월/일 한 자리 → 두 자리 패딩', () {
      expect(formatSharedDbDate('2025-06-05T08:05:00'), '2025.06.05 08:05');
    });

    test('유효하지 않은 날짜 문자열 → 원본 반환', () {
      expect(formatSharedDbDate('not-a-date'), 'not-a-date');
    });

    test('빈 문자열 → 빈 문자열 반환', () {
      expect(formatSharedDbDate(''), '');
    });

    test('밀리초 포함 ISO 형식 파싱', () {
      expect(formatSharedDbDate('2025-07-20T14:30:00.000Z'), '2025.07.20 14:30');
    });

    test('윤년 2월 29일', () {
      expect(formatSharedDbDate('2024-02-29T12:00:00'), '2024.02.29 12:00');
    });
  });

  // ── formatProvisionDate — 같은 날 ────────────────────────────────────────

  group('formatProvisionDate — 같은 날 (start ~ 종료시간)', () {
    test('같은 날: "M.d (요일) HH:mm ~ HH:mm" 형식', () {
      final result = formatProvisionDate(
        '2025-03-17T10:00:00', // 월요일
        '2025-03-17T11:30:00',
      );
      expect(result, '3.17 (월) 10:00 ~ 11:30');
    });

    test('토요일 요일 표기', () {
      final result = formatProvisionDate(
        '2025-03-15T14:00:00', // 토요일
        '2025-03-15T15:00:00',
      );
      expect(result, '3.15 (토) 14:00 ~ 15:00');
    });

    test('일요일 요일 표기', () {
      final result = formatProvisionDate(
        '2025-03-16T09:00:00', // 일요일
        '2025-03-16T10:00:00',
      );
      expect(result, '3.16 (일) 09:00 ~ 10:00');
    });

    test('자정~자정 경계', () {
      final result = formatProvisionDate(
        '2025-06-01T00:00:00', // 일요일
        '2025-06-01T00:00:00',
      );
      expect(result, contains('00:00 ~ 00:00'));
    });
  });

  // ── formatProvisionDate — 다른 날 ────────────────────────────────────────

  group('formatProvisionDate — 다른 날 (전체 날짜 포함)', () {
    test('다른 날: 종료에도 "M.d (요일) HH:mm" 포함', () {
      final result = formatProvisionDate(
        '2025-03-17T10:00:00', // 월
        '2025-03-18T11:00:00', // 화
      );
      expect(result, '3.17 (월) 10:00 ~ 3.18 (화) 11:00');
    });

    test('월 경계 초과 (3월 → 4월)', () {
      final result = formatProvisionDate(
        '2025-03-31T23:00:00', // 월
        '2025-04-01T01:00:00', // 화
      );
      expect(result, contains('3.31'));
      expect(result, contains('4.1'));
    });
  });

  // ── formatProvisionDate — 엣지케이스 ─────────────────────────────────────

  group('formatProvisionDate — 엣지케이스', () {
    test('start만 있고 end 없음 → start만 반환', () {
      final result = formatProvisionDate('2025-03-17T10:00:00', '');
      expect(result, '3.17 (월) 10:00');
    });

    test('start 없고 end만 있음 → formatSharedDbDate(end) 반환', () {
      final result = formatProvisionDate('', '2025-03-17T10:00:00');
      expect(result, '2025.03.17 10:00');
    });

    test('둘 다 빈 문자열 → 빈 문자열', () {
      expect(formatProvisionDate('', ''), '');
    });

    test('유효하지 않은 start → start 원본 반환', () {
      final result = formatProvisionDate('invalid-date', '2025-03-17T10:00:00');
      expect(result, 'invalid-date');
    });

    test('유효하지 않은 end (start는 유효) → start 포맷만 반환', () {
      // endStr이 비어있지 않지만 파싱 실패 → catch에서 startStr 반환
      final result = formatProvisionDate('2025-03-17T10:00:00', 'bad-end');
      // DateTime.parse('bad-end') 예외 → catch → 'invalid-date' 대신 startStr
      expect(result, '2025-03-17T10:00:00'); // catch(_) return startStr
    });

    test('윤년 2월 29일 처리', () {
      final result = formatProvisionDate('2024-02-29T09:00:00', '2024-02-29T10:00:00');
      expect(result, contains('2.29'));
      expect(result, contains('09:00 ~ 10:00'));
    });
  });
}
