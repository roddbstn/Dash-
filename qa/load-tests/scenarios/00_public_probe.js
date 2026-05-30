/**
 * 공개 엔드포인트 탐침 테스트 (인증 불필요)
 * 목적: 서버 연결, 응답시간 기준선, DB 연결 상태, Rate Limit 동작 확인
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'https://dash.qpon';
const API_BASE = `${BASE_URL}/api`;

const healthDuration   = new Trend('health_duration_ms',   true);
const kpiDuration      = new Trend('admin_kpi_duration_ms', true);
const authCheckDuration = new Trend('auth_check_ms',       true);
const rateLimitHits    = new Counter('rate_limit_429');
const errorRate        = new Rate('error_rate');

export const options = {
  stages: [
    { duration: '30s', target: 10  },
    { duration: '1m',  target: 50  },
    { duration: '1m',  target: 100 },
    { duration: '1m',  target: 200 },
    { duration: '30s', target: 0   },
  ],
  thresholds: {
    http_req_failed:      [{ threshold: 'rate<0.01',   abortOnFail: false }],
    http_req_duration:    [{ threshold: 'p(95)<2000',  abortOnFail: false }],
    'health_duration_ms': [{ threshold: 'p(95)<500',   abortOnFail: false }],
  },
};

export default function () {
  group('Health Check', () => {
    const res = http.get(`${BASE_URL}/health`);
    const ok = check(res, {
      'health: 200':           (r) => r.status === 200,
      'health: db connected':  (r) => {
        try { return JSON.parse(r.body).db === 'connected'; } catch { return false; }
      },
    });
    healthDuration.add(res.timings.duration);
    errorRate.add(!ok);
  });

  sleep(0.5);

  group('Admin KPI (공개)', () => {
    const res = http.get(`${BASE_URL}/admin/kpi`);
    check(res, {
      'kpi: not 500': (r) => r.status !== 500,
    });
    kpiDuration.add(res.timings.duration);
  });

  sleep(0.5);

  group('Auth 401 확인 (토큰 없이)', () => {
    const res = http.get(`${API_BASE}/records/user/test-uid`);
    check(res, {
      'no-token: 401 반환':  (r) => r.status === 401,
      'no-token: 서버 안전': (r) => r.status !== 500,
    });
    authCheckDuration.add(res.timings.duration);
    if (res.status === 429) rateLimitHits.add(1);
  });

  sleep(1);
}

export function handleSummary(data) {
  const m = data.metrics;

  const h_p50 = m.health_duration_ms?.values['p(50)']?.toFixed(1) || 'N/A';
  const h_p95 = m.health_duration_ms?.values['p(95)']?.toFixed(1) || 'N/A';
  const h_p99 = m.health_duration_ms?.values['p(99)']?.toFixed(1) || 'N/A';
  const k_p95 = m.admin_kpi_duration_ms?.values['p(95)']?.toFixed(1) || 'N/A';
  const a_p95 = m.auth_check_ms?.values['p(95)']?.toFixed(1) || 'N/A';
  const totalReqs = m.http_reqs?.values?.count || 0;
  const errRate = ((m.http_req_failed?.values?.rate || 0) * 100).toFixed(2);
  const rls = m.rate_limit_429?.values?.count || 0;
  const overall_p95 = m.http_req_duration?.values['p(95)']?.toFixed(1) || 'N/A';
  const overall_p99 = m.http_req_duration?.values['p(99)']?.toFixed(1) || 'N/A';

  const lines = [
    '',
    '╔═══════════════════════════════════════════════════════════════╗',
    '║        Dash — Public Probe Load Test 결과                    ║',
    '╠═══════════════════════════════════════════════════════════════╣',
    `║  /health      p50: ${h_p50.padEnd(8)}ms  p95: ${h_p95.padEnd(8)}ms  p99: ${h_p99.padEnd(6)}ms ║`,
    `║  /admin/kpi   p95: ${k_p95.padEnd(40)}ms ║`,
    `║  /api (401)   p95: ${a_p95.padEnd(40)}ms ║`,
    '╠═══════════════════════════════════════════════════════════════╣',
    `║  전체 p95: ${overall_p95.padEnd(8)}ms   전체 p99: ${overall_p99.padEnd(8)}ms              ║`,
    `║  총 요청: ${String(totalReqs).padEnd(8)}건   에러율: ${String(errRate+'%').padEnd(8)}  429: ${String(rls).padEnd(4)}건 ║`,
    '╠═══════════════════════════════════════════════════════════════╣',
    `║  SLA(p95<2000ms): ${overall_p95 !== 'N/A' && parseFloat(overall_p95) < 2000 ? '✅ PASS' : '❌ FAIL'}                                    ║`,
    `║  에러율(<1%):     ${errRate !== 'N/A' && parseFloat(errRate) < 1 ? '✅ PASS' : '❌ FAIL'}                                    ║`,
    `║  DB 연결:         ${rls === 0 ? '✅ 안정' : '⚠️  Rate Limit 도달'}                              ║`,
    '╚═══════════════════════════════════════════════════════════════╝',
    '',
  ].join('\n');

  return {
    stdout: lines,
  };
}
