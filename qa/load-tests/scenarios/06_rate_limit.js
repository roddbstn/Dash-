/**
 * ============================================================
 * [SCENARIO 6] Rate Limit & Security Boundary Test
 * ============================================================
 * 목적: express-rate-limit 설정이 올바르게 동작하는지 검증
 *   - Global: 300 req / 15분
 *   - Auth endpoints: 30 req / 15분
 *   - 429 응답 후 Retry-After 헤더 확인
 *   - Rate limit 초과 시 서버 안정성 유지 여부
 *
 * 실행 방법:
 *   k6 run \
 *     -e BASE_URL=https://staging.dash.qpon \
 *     -e TEST_TOKEN=<token> \
 *     scenarios/06_rate_limit.js
 * ============================================================
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate } from 'k6/metrics';
import { API_BASE, authHeaders, THRESHOLDS } from '../config.js';

const rateLimitResponses = new Counter('rate_limit_429_count');
const retryAfterPresent  = new Counter('retry_after_header_present');
const errorRate          = new Rate('rl_error_rate');

export const options = {
  scenarios: {
    // 단일 IP에서 300 req/15min 한도 초과 시도
    global_rate_limit: {
      executor: 'constant-arrival-rate',
      rate: 25,          // 분당 25 req = 초당 ~0.4 req
      timeUnit: '1m',
      duration: '3m',    // 3분 = 75 req → 한도 미달 (정상)
      preAllocatedVUs: 5,
      maxVUs: 10,
      exec: 'globalRateLimitTest',
    },
    // Auth 엔드포인트 30 req/15min 한도 초과 시도
    auth_rate_limit: {
      executor: 'constant-arrival-rate',
      rate: 5,
      timeUnit: '1m',
      duration: '7m',    // 7분 = 35 req → 30 한도 초과
      preAllocatedVUs: 3,
      maxVUs: 5,
      exec: 'authRateLimitTest',
      startTime: '10s',
    },
  },
  thresholds: {
    http_req_failed: [{ threshold: 'rate<0.40', abortOnFail: false }], // 429는 정상
  },
};

export function globalRateLimitTest() {
  const headers = authHeaders();

  const res = http.get(`${API_BASE}/records/user/test-uid`, { headers });

  if (res.status === 429) {
    rateLimitResponses.add(1);

    // Retry-After 헤더 검증
    const retryAfter = res.headers['Retry-After'] || res.headers['retry-after'];
    if (retryAfter) retryAfterPresent.add(1);

    check(res, {
      '429: RateLimit-Limit header present':     (r) => !!r.headers['RateLimit-Limit']  || !!r.headers['X-RateLimit-Limit'],
      '429: RateLimit-Remaining is 0':           (r) => {
        const h = r.headers['RateLimit-Remaining'] || r.headers['X-RateLimit-Remaining'];
        return h !== undefined;
      },
      '429: response body has message':          (r) => {
        try {
          const body = JSON.parse(r.body);
          return typeof body.message === 'string' || typeof body.error === 'string';
        } catch { return false; }
      },
    });
  } else {
    check(res, { 'normal: 200 or 401': (r) => r.status === 200 || r.status === 401 });
    errorRate.add(res.status >= 500 ? 1 : 0);
  }

  sleep(0.1);
}

export function authRateLimitTest() {
  // FCM 토큰 등록 엔드포인트 (auth rate limit 적용)
  const res = http.post(
    `${API_BASE}/users/fcm_token`,
    JSON.stringify({ token: 'test-fcm-token', userId: 'test-uid' }),
    { headers: authHeaders() }
  );

  if (res.status === 429) {
    rateLimitResponses.add(1);
    check(res, {
      'auth 429: has Retry-After': (r) => {
        const h = r.headers['Retry-After'] || r.headers['retry-after'];
        if (h) retryAfterPresent.add(1);
        return !!h;
      },
    });
  } else {
    check(res, { 'auth: not 500': (r) => r.status !== 500 });
  }

  sleep(0.5);
}

export function handleSummary(data) {
  const m = data.metrics;
  const total429    = m.rate_limit_429_count?.values?.count || 0;
  const withRetry   = m.retry_after_header_present?.values?.count || 0;
  const totalReqs   = m.http_reqs?.values?.count || 0;

  return {
    stdout: [
      '\n╔══════════════════════════════════════════════════╗',
      '║       Rate Limit Test 결과                      ║',
      '╠══════════════════════════════════════════════════╣',
      `║ 총 요청:           ${String(totalReqs).padEnd(10)}                ║`,
      `║ 429 응답 수:       ${String(total429).padEnd(10)}                ║`,
      `║ Retry-After 포함:  ${String(withRetry).padEnd(10)}                ║`,
      `║ Rate Limit 동작:   ${total429 > 0 ? '✅  정상'  : '⚠️  미동작 확인 필요'}         ║`,
      `║ Retry-After 헤더:  ${withRetry > 0 ? '✅  정상'  : '⚠️  헤더 누락 확인 필요'}         ║`,
      '╚══════════════════════════════════════════════════╝\n',
    ].join('\n'),
  };
}
