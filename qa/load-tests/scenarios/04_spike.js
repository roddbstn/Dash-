/**
 * ============================================================
 * [SCENARIO 4] Spike Test — 갑작스러운 트래픽 폭증 대응 확인
 * ============================================================
 * 목적: 이벤트/마케팅 등으로 갑자기 수백 명이 동시 접속할 때
 *       서버가 빠르게 회복(Recovery)하는지 확인
 *
 * 패턴: 소수 유지 → 순간 500명 급증 → 소수로 복귀 → 재급증
 *
 * 실행 방법:
 *   k6 run \
 *     -e BASE_URL=https://staging.dash.qpon \
 *     -e TEST_TOKEN=<token> \
 *     -e TEST_USER_ID=<uid> \
 *     scenarios/04_spike.js
 * ============================================================
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import { API_BASE, authHeaders, TEST_USER_ID, THRESHOLDS } from '../config.js';

// ── 커스텀 메트릭 ──────────────────────────────────────────
const spikeResponseTime  = new Trend('spike_response_ms',  true);
const recoveryTime       = new Trend('recovery_response_ms', true);
const errorsDuringSpike  = new Counter('errors_during_spike');
const spikePhase         = { current: 'normal' }; // 페이즈 추적용

export const options = {
  stages: [
    { duration: '1m',  target: 10  }, // 정상 트래픽
    { duration: '30s', target: 500 }, // ⚡ 스파이크 #1: 30초에 500명 급증
    { duration: '1m',  target: 500 }, // 스파이크 유지
    { duration: '30s', target: 10  }, // 복구 관찰
    { duration: '2m',  target: 10  }, // 정상 복귀 유지
    { duration: '30s', target: 300 }, // ⚡ 스파이크 #2
    { duration: '1m',  target: 300 }, // 스파이크 유지
    { duration: '30s', target: 0   }, // 종료
  ],
  thresholds: {
    http_req_failed:    [{ threshold: 'rate<0.20', abortOnFail: false }],
    http_req_duration:  [{ threshold: 'p(95)<8000', abortOnFail: false }],
    'spike_response_ms':    ['p(95)<8000'],
    'recovery_response_ms': ['p(95)<3000'],
  },
};

export default function () {
  const headers = authHeaders();
  const uid     = TEST_USER_ID;

  // 현재 활성 VU 수로 페이즈 판단 (임계: 50명 이상이면 spike)
  const isSpike = __VU > 50;

  group('[Spike] Health Probe', () => {
    const res = http.get(`${API_BASE.replace('/api', '')}/health`);
    const ok  = check(res, { 'health: alive': (r) => r.status === 200 });

    if (!ok && isSpike) errorsDuringSpike.add(1);
  });

  sleep(0.2);

  group('[Spike] Core API (Records)', () => {
    const res = http.get(`${API_BASE}/records/user/${uid}`, { headers });

    const ok = check(res, {
      'records: status 200 or 429': (r) => r.status === 200 || r.status === 429,
      'records: response time OK':  (r) => r.timings.duration < 8000,
    });

    if (isSpike) {
      spikeResponseTime.add(res.timings.duration);
      if (!ok) errorsDuringSpike.add(1);
    } else {
      recoveryTime.add(res.timings.duration);
    }
  });

  sleep(0.3);

  group('[Spike] Auth-Heavy Endpoint (Vault)', () => {
    // Firebase Admin SDK 검증 + DB 조회 → Auth 서버 병목 노출
    const res = http.get(`${API_BASE}/users/vault/${uid}`, { headers });
    check(res, { 'vault: not 500': (r) => r.status !== 500 });
    if (isSpike) spikeResponseTime.add(res.timings.duration);
  });

  sleep(isSpike ? 0.1 : 1); // 스파이크 중엔 think time 최소화
}

export function handleSummary(data) {
  const m = data.metrics;

  const report = [
    '╔══════════════════════════════════════════════════════╗',
    '║           Dash - Spike Test 결과 요약                ║',
    '╠══════════════════════════════════════════════════════╣',
    `║ 스파이크 중 p95 응답시간:  ${String(m.spike_response_ms?.values['p(95)']?.toFixed(0) || 'N/A').padEnd(8)} ms            ║`,
    `║ 복구 후  p95 응답시간:     ${String(m.recovery_response_ms?.values['p(95)']?.toFixed(0) || 'N/A').padEnd(8)} ms            ║`,
    `║ 전체 에러율:               ${String(((m.http_req_failed?.values?.rate || 0) * 100).toFixed(2)).padEnd(8)} %             ║`,
    `║ 스파이크 중 에러 건수:     ${String(m.errors_during_spike?.values?.count || 0).padEnd(8)}               ║`,
    `║ 총 요청 수:                ${String(m.http_reqs?.values?.count || 0).padEnd(8)}               ║`,
    '╚══════════════════════════════════════════════════════╝',
  ].join('\n');

  return {
    'qa/load-tests/results/spike_summary.txt': report,
    stdout: '\n' + report + '\n',
  };
}
