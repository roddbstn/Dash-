/**
 * ============================================================
 * [SCENARIO 3] Stress Test — 한계점(Breaking Point) 탐색
 * ============================================================
 * 목적: 서버가 버티지 못하는 임계 유저수를 찾아 병목 구간 확인
 *       Rate Limit(300 req/15min) 도달 시점, DB 커넥션 풀(5) 포화 시점 측정
 *
 * ⚠️  주의: 프로덕션 서버 대상 실행 금지. 스테이징 환경에서만 실행.
 *
 * 실행 방법:
 *   k6 run \
 *     -e BASE_URL=https://staging.dash.qpon \
 *     -e TEST_TOKEN=<token> \
 *     -e TEST_USER_ID=<uid> \
 *     scenarios/03_stress.js
 * ============================================================
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import { API_BASE, authHeaders, TEST_USER_ID, THRESHOLDS } from '../config.js';

// ── 커스텀 메트릭 ──────────────────────────────────────────
const p99Duration       = new Trend('p99_duration_ms', true);
const rateLimitHits     = new Counter('rate_limit_429');
const serverErrors      = new Counter('server_errors_5xx');
const dbTimeoutErrors   = new Counter('db_timeout_errors');
const errorRate         = new Rate('stress_error_rate');

// ── 테스트 설정 ────────────────────────────────────────────
export const options = {
  stages: [
    { duration: '2m', target: 50  },  // 워밍업
    { duration: '2m', target: 100 },  // 정상 부하
    { duration: '2m', target: 200 },  // 높은 부하
    { duration: '2m', target: 300 },  // Rate Limit 예상 도달 구간
    { duration: '2m', target: 400 },  // DB 커넥션 풀 포화 예상 구간
    { duration: '2m', target: 500 },  // 임계점 탐색
    { duration: '3m', target: 500 },  // 임계점 유지 (안정성 확인)
    { duration: '2m', target: 0   },  // 복구 관찰
  ],
  thresholds: {
    // 스트레스 테스트는 임계값 위반 허용 (관찰 목적)
    http_req_failed:      [{ threshold: 'rate<0.30', abortOnFail: false }],
    http_req_duration:    [{ threshold: 'p(95)<10000', abortOnFail: false }],
    'stress_error_rate':  [{ threshold: 'rate<0.30', abortOnFail: false }],
  },
};

// ── 핵심 API 혼합 요청 ─────────────────────────────────────
export default function () {
  const headers = authHeaders();
  const uid     = TEST_USER_ID;

  // ---- 가장 자주 호출되는 엔드포인트 집중 공격 ----
  group('[Stress] Records + Cases (DB 집중)', () => {
    const res = http.get(`${API_BASE}/records/user/${uid}`, { headers });
    const status = res.status;

    // 429: Rate Limit 도달
    if (status === 429) {
      rateLimitHits.add(1);
      check(res, { 'rate limit hit (429)': () => true });
    }
    // 5xx: 서버/DB 에러
    else if (status >= 500) {
      serverErrors.add(1);
      const body = res.body || '';
      if (body.includes('timeout') || body.includes('ETIMEDOUT') || body.includes('ER_CON_COUNT')) {
        dbTimeoutErrors.add(1);
      }
      check(res, { 'server error (5xx)': () => false });
      errorRate.add(1);
    }
    else {
      check(res, { 'records: 200': (r) => r.status === 200 });
      errorRate.add(res.status !== 200 ? 1 : 0);
    }

    p99Duration.add(res.timings.duration);
  });

  sleep(0.1); // think time 최소화 → 최대 압박

  group('[Stress] Cases (병렬 DB 쿼리)', () => {
    const res = http.get(`${API_BASE}/cases/user/${uid}`, { headers });
    if (res.status >= 500) serverErrors.add(1);
    if (res.status === 429) rateLimitHits.add(1);
    p99Duration.add(res.timings.duration);
  });

  sleep(0.1);

  group('[Stress] Notifications (빈도 높은 폴링)', () => {
    const res = http.get(`${API_BASE}/notifications/${uid}`, { headers });
    if (res.status >= 500) serverErrors.add(1);
    if (res.status === 429) rateLimitHits.add(1);
    p99Duration.add(res.timings.duration);
  });

  sleep(0.2);
}

// ── 테스트 완료 후 결과 요약 ──────────────────────────────
export function handleSummary(data) {
  const metrics = data.metrics;

  const summary = {
    test: 'Stress Test',
    timestamp: new Date().toISOString(),
    results: {
      max_vus_reached:         data.state.isFullIteration,
      http_req_failed_rate:    (metrics.http_req_failed?.values?.rate * 100).toFixed(2) + '%',
      p95_response_ms:         metrics.http_req_duration?.values['p(95)']?.toFixed(0),
      p99_response_ms:         metrics.p99_duration_ms?.values['p(95)']?.toFixed(0),
      rate_limit_hits:         metrics.rate_limit_429?.values?.count,
      server_errors_5xx:       metrics.server_errors_5xx?.values?.count,
      db_timeout_errors:       metrics.db_timeout_errors?.values?.count,
    },
    bottleneck_analysis: {
      rate_limit_triggered: (metrics.rate_limit_429?.values?.count || 0) > 0,
      db_pool_exhausted:    (metrics.db_timeout_errors?.values?.count || 0) > 0,
      server_unstable:      (metrics.http_req_failed?.values?.rate || 0) > 0.05,
    },
  };

  return {
    'qa/load-tests/results/stress_summary.json': JSON.stringify(summary, null, 2),
    stdout: '\n📊 Stress Test 완료 — qa/load-tests/results/stress_summary.json 확인\n',
  };
}
