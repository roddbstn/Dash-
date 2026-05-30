/**
 * ============================================================
 * [SCENARIO 2] Load Test — 핵심 유저 저니 시뮬레이션
 * ============================================================
 * 목적: 실제 사용 패턴과 유사한 혼합 트래픽으로 병목 구간 탐색
 *
 * 유저 유형별 시나리오:
 *   A) 모바일 앱 유저 (80%) — 기록 조회, 케이스 조회, 상담사 목록
 *   B) 리뷰어 (15%)        — ready 레코드 확인, 리뷰 제출
 *   C) 관리자/SSE (5%)     — SSE 연결 유지
 *
 * 동시 유저: 최대 200명
 *
 * 실행 방법:
 *   k6 run \
 *     -e BASE_URL=https://dash.qpon \
 *     -e TEST_TOKEN=<token> \
 *     -e TEST_USER_ID=<uid> \
 *     -e TEST_EMAIL=<email> \
 *     -e TEST_SHARE_TOKEN=<share_token> \
 *     scenarios/02_load.js
 * ============================================================
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';
import { API_BASE, authHeaders, TEST_USER_ID, TEST_EMAIL, THRESHOLDS } from '../config.js';

const SHARE_TOKEN = __ENV.TEST_SHARE_TOKEN || 'test-share-token';

// ── 커스텀 메트릭 ──────────────────────────────────────────
const mobileJourneyDuration   = new Trend('mobile_journey_ms',   true);
const reviewerJourneyDuration = new Trend('reviewer_journey_ms', true);
const sseDuration             = new Trend('sse_connect_ms',      true);
const totalErrors             = new Counter('total_errors');
const errorRate               = new Rate('error_rate');

// ── 테스트 설정 ────────────────────────────────────────────
export const options = {
  scenarios: {
    // ---- A: 모바일 앱 유저 (80%) ----
    mobile_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 80  },
        { duration: '5m', target: 160 },
        { duration: '3m', target: 160 },
        { duration: '2m', target: 0   },
      ],
      exec: 'mobileUserJourney',
    },
    // ---- B: 리뷰어 (15%) ----
    reviewer_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 15 },
        { duration: '5m', target: 30 },
        { duration: '3m', target: 30 },
        { duration: '2m', target: 0  },
      ],
      exec: 'reviewerJourney',
    },
    // ---- C: SSE 롱커넥션 (5%) ----
    sse_users: {
      executor: 'constant-vus',
      vus: 10,
      duration: '12m',
      exec: 'sseJourney',
    },
  },
  thresholds: {
    ...THRESHOLDS,
    'mobile_journey_ms':   ['p(95)<3000'],
    'reviewer_journey_ms': ['p(95)<2000'],
    'error_rate':          ['rate<0.02'],
  },
};

// ── A: 모바일 유저 여정 ────────────────────────────────────
export function mobileUserJourney() {
  const headers = authHeaders();
  const uid     = TEST_USER_ID;
  const start   = Date.now();

  group('[Mobile] Fetch Home Data', () => {
    // 홈 탭: 기록 목록 + 케이스 + 상담사 병렬 요청 시뮬레이션
    const responses = http.batch([
      ['GET', `${API_BASE}/records/user/${uid}`,     null, { headers }],
      ['GET', `${API_BASE}/cases/user/${uid}`,       null, { headers }],
      ['GET', `${API_BASE}/counselors/${uid}`,       null, { headers }],
      ['GET', `${API_BASE}/notifications/${uid}`,    null, { headers }],
    ]);

    responses.forEach((res, i) => {
      const names = ['records', 'cases', 'counselors', 'notifications'];
      const ok = check(res, {
        [`${names[i]}: status 200`]: (r) => r.status === 200,
        [`${names[i]}: not empty body`]: (r) => r.body.length > 0,
      });
      if (!ok) { totalErrors.add(1); errorRate.add(1); }
      else errorRate.add(0);
    });
  });

  sleep(2);

  group('[Mobile] User Stats', () => {
    const res = http.get(`${API_BASE}/users/${uid}/stats`, { headers });
    const ok = check(res, { 'stats: status 200': (r) => r.status === 200 });
    if (!ok) { totalErrors.add(1); errorRate.add(1); } else errorRate.add(0);
  });

  sleep(1);

  group('[Mobile] Share Record Preview', () => {
    // 공유 링크 미리보기 (인증 불필요 공개 엔드포인트)
    const res = http.get(`${API_BASE}/records/share/${SHARE_TOKEN}`);
    check(res, { 'share preview: not 500': (r) => r.status !== 500 });
  });

  mobileJourneyDuration.add(Date.now() - start);
  sleep(Math.random() * 3 + 1); // 1~4초 think time
}

// ── B: 리뷰어 여정 ────────────────────────────────────────
export function reviewerJourney() {
  const headers = authHeaders();
  const email   = TEST_EMAIL;
  const start   = Date.now();

  group('[Reviewer] Check Ready Records', () => {
    const res = http.get(
      `${API_BASE}/records/ready?email=${encodeURIComponent(email)}`,
      { headers }
    );
    const ok = check(res, {
      'ready: status 200':    (r) => r.status === 200,
      'ready: is array':      (r) => {
        try { return Array.isArray(JSON.parse(r.body)); } catch { return false; }
      },
    });
    if (!ok) { totalErrors.add(1); errorRate.add(1); } else errorRate.add(0);
  });

  sleep(1);

  group('[Reviewer] Fetch History', () => {
    const res = http.get(
      `${API_BASE}/records/history?email=${encodeURIComponent(email)}`,
      { headers }
    );
    check(res, { 'history: not 500': (r) => r.status !== 500 });
  });

  sleep(1);

  group('[Reviewer] Share Record Detail', () => {
    const res = http.get(`${API_BASE}/records/share/${SHARE_TOKEN}`, { headers });
    check(res, { 'share detail: not 500': (r) => r.status !== 500 });
  });

  reviewerJourneyDuration.add(Date.now() - start);
  sleep(Math.random() * 2 + 1);
}

// ── C: SSE 롱커넥션 ────────────────────────────────────────
export function sseJourney() {
  const email = TEST_EMAIL;
  const start = Date.now();

  // k6는 SSE를 직접 지원하지 않으므로 GET 요청으로 연결 시도 후 즉시 닫기
  // 실제 SSE 병목은 concurrent connection 수에서 발생
  const res = http.get(
    `${API_BASE}/events?email=${encodeURIComponent(email)}`,
    {
      headers: {
        'Authorization': `Bearer ${authHeaders().Authorization}`,
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
      timeout: '5s',
    }
  );

  check(res, {
    'SSE: connects (200 or keeps open)': (r) => r.status === 200 || r.status === 0,
  });

  sseDuration.add(Date.now() - start);
  sleep(30); // SSE는 30초마다 재연결 시뮬레이션
}
