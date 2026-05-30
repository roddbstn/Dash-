/**
 * ============================================================
 * [SCENARIO 5] Soak Test — 메모리 누수 & 장기 안정성 검증
 * ============================================================
 * 목적: 적당한 트래픽을 장시간 유지했을 때
 *       - 메모리 누수로 인한 점진적 응답 저하 감지
 *       - SSE 연결 누적으로 인한 fd(파일 디스크립터) 소진 탐지
 *       - DB 커넥션 풀 고갈 패턴 탐지
 *
 * ⏱️  권장 실행 시간: 2~4시간 (기본 30분 설정)
 *      장기 실행: -e DURATION=4h 로 변경
 *
 * 실행 방법:
 *   k6 run \
 *     -e BASE_URL=https://staging.dash.qpon \
 *     -e TEST_TOKEN=<token> \
 *     -e TEST_USER_ID=<uid> \
 *     -e TEST_EMAIL=<email> \
 *     -e DURATION=2h \
 *     scenarios/05_soak.js
 * ============================================================
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Rate } from 'k6/metrics';
import { API_BASE, authHeaders, TEST_USER_ID, TEST_EMAIL, THRESHOLDS } from '../config.js';

const SOAK_DURATION = __ENV.DURATION || '30m';

// ── 커스텀 메트릭 (시간 경과에 따른 drift 감지용) ───────
const earlyResponseTime = new Trend('early_phase_ms',  true); // 초반 응답
const lateResponseTime  = new Trend('late_phase_ms',   true); // 후반 응답
const dbQueryTime       = new Trend('db_query_ms',     true);
const errorRate         = new Rate('soak_error_rate');

let testStartTime = 0;

export const options = {
  stages: [
    { duration: '5m',          target: 50 }, // 워밍업
    { duration: SOAK_DURATION, target: 50 }, // 장기 유지
    { duration: '5m',          target: 0  }, // 종료
  ],
  thresholds: {
    ...THRESHOLDS,
    'early_phase_ms': ['p(95)<1500'],
    'late_phase_ms':  ['p(95)<2500'], // Soak 후반엔 약간 여유
    'soak_error_rate':['rate<0.01'],
  },
};

export function setup() {
  return { startTime: Date.now() };
}

export default function (data) {
  testStartTime = data.startTime;
  const headers = authHeaders();
  const uid     = TEST_USER_ID;
  const email   = TEST_EMAIL;
  const elapsed = Date.now() - testStartTime;
  const isEarly = elapsed < 10 * 60 * 1000; // 첫 10분 = early phase

  group('[Soak] Records Query (DB 주요 부하)', () => {
    const res = http.get(`${API_BASE}/records/user/${uid}`, { headers });
    const ok  = check(res, { 'records: 200': (r) => r.status === 200 });
    errorRate.add(!ok);
    dbQueryTime.add(res.timings.duration);
    if (isEarly) earlyResponseTime.add(res.timings.duration);
    else         lateResponseTime.add(res.timings.duration);
  });

  sleep(1);

  group('[Soak] Counselors Query', () => {
    const res = http.get(`${API_BASE}/counselors/${uid}`, { headers });
    check(res, { 'counselors: 200': (r) => r.status === 200 });
    dbQueryTime.add(res.timings.duration);
  });

  sleep(1);

  group('[Soak] Reviewer Ready Check (SSE 전 폴링)', () => {
    const res = http.get(
      `${API_BASE}/records/ready?email=${encodeURIComponent(email)}`,
      { headers }
    );
    check(res, { 'ready: 200': (r) => r.status === 200 });
  });

  sleep(1);

  group('[Soak] User Profile (캐시 히트 확인)', () => {
    const res = http.get(`${API_BASE}/users/${uid}`, { headers });
    check(res, { 'profile: 200': (r) => r.status === 200 });
    if (isEarly) earlyResponseTime.add(res.timings.duration);
    else         lateResponseTime.add(res.timings.duration);
  });

  sleep(3);
}

export function handleSummary(data) {
  const m = data.metrics;
  const earlyP95 = m.early_phase_ms?.values['p(95)']?.toFixed(0) || 'N/A';
  const lateP95  = m.late_phase_ms?.values['p(95)']?.toFixed(0)  || 'N/A';
  const drift    = earlyP95 !== 'N/A' && lateP95 !== 'N/A'
    ? ((lateP95 - earlyP95) / earlyP95 * 100).toFixed(1) + '%'
    : 'N/A';

  const memoryLeakSuspected = (
    lateP95 !== 'N/A' && earlyP95 !== 'N/A' &&
    (lateP95 - earlyP95) > earlyP95 * 0.3 // 초반 대비 30% 이상 느려지면 의심
  );

  const summary = {
    test: 'Soak Test',
    duration: SOAK_DURATION,
    timestamp: new Date().toISOString(),
    results: {
      total_requests:         m.http_reqs?.values?.count,
      error_rate:             ((m.http_req_failed?.values?.rate || 0) * 100).toFixed(2) + '%',
      early_phase_p95_ms:     earlyP95,
      late_phase_p95_ms:      lateP95,
      response_time_drift:    drift,
      db_query_p95_ms:        m.db_query_ms?.values['p(95)']?.toFixed(0),
    },
    diagnosis: {
      memory_leak_suspected:  memoryLeakSuspected,
      recommendation: memoryLeakSuspected
        ? '⚠️  응답시간 drift > 30% 감지. 서버 메모리 프로파일링(--inspect) 권장'
        : '✅  장기 안정성 양호. 응답시간 편차 정상 범위',
    },
  };

  return {
    'qa/load-tests/results/soak_summary.json': JSON.stringify(summary, null, 2),
    stdout: '\n📊 Soak Test 결과:\n' +
      `  초반 p95: ${earlyP95}ms | 후반 p95: ${lateP95}ms | drift: ${drift}\n` +
      `  메모리 누수 의심: ${memoryLeakSuspected ? '⚠️  YES' : '✅  NO'}\n`,
  };
}
