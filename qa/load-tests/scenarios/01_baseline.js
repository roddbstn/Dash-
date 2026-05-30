/**
 * ============================================================
 * [SCENARIO 1] Baseline Performance Test
 * ============================================================
 * 목적: 정상 트래픽(소수 유저) 기준 응답시간 측정 → 성능 기준선(Baseline) 확보
 * 유저수: 1→10명 점진적 증가 후 10명 유지 5분
 *
 * 실행 방법:
 *   k6 run \
 *     -e BASE_URL=https://dash.qpon \
 *     -e TEST_TOKEN=<firebase_id_token> \
 *     -e TEST_USER_ID=<uid> \
 *     -e TEST_EMAIL=<email> \
 *     scenarios/01_baseline.js
 * ============================================================
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Rate } from 'k6/metrics';
import { API_BASE, authHeaders, TEST_USER_ID, TEST_EMAIL, THRESHOLDS } from '../config.js';

// ── 커스텀 메트릭 ──────────────────────────────────────────
const userProfileDuration  = new Trend('user_profile_duration',  true);
const recordsListDuration  = new Trend('records_list_duration',  true);
const casesListDuration    = new Trend('cases_list_duration',    true);
const notifListDuration    = new Trend('notif_list_duration',    true);
const errorRate            = new Rate('custom_error_rate');

// ── 테스트 설정 ────────────────────────────────────────────
export const options = {
  stages: [
    { duration: '1m', target: 10  }, // 1분간 10명까지 증가
    { duration: '5m', target: 10  }, // 5분간 10명 유지 (Baseline 측정)
    { duration: '1m', target: 0   }, // 1분간 종료
  ],
  thresholds: {
    ...THRESHOLDS,
    'user_profile_duration':  ['p(95)<500'],
    'records_list_duration':  ['p(95)<1000'],
    'cases_list_duration':    ['p(95)<500'],
  },
};

// ── 메인 시나리오 ──────────────────────────────────────────
export default function () {
  const headers = authHeaders();
  const uid     = TEST_USER_ID;

  group('Health Check', () => {
    const res = http.get(`${API_BASE.replace('/api', '')}/health`);
    check(res, { 'health: status 200': (r) => r.status === 200 });
  });

  sleep(0.5);

  group('User Profile', () => {
    const res = http.get(`${API_BASE}/users/${uid}`, { headers });
    const ok  = check(res, {
      'profile: status 200':    (r) => r.status === 200,
      'profile: has id field':  (r) => {
        try { return JSON.parse(r.body).id !== undefined; } catch { return false; }
      },
    });
    userProfileDuration.add(res.timings.duration);
    errorRate.add(!ok);
  });

  sleep(0.5);

  group('Records List', () => {
    const res = http.get(`${API_BASE}/records/user/${uid}`, { headers });
    const ok  = check(res, {
      'records: status 200':     (r) => r.status === 200,
      'records: body is array':  (r) => {
        try { return Array.isArray(JSON.parse(r.body)); } catch { return false; }
      },
    });
    recordsListDuration.add(res.timings.duration);
    errorRate.add(!ok);
  });

  sleep(0.5);

  group('Cases List', () => {
    const res = http.get(`${API_BASE}/cases/user/${uid}`, { headers });
    const ok  = check(res, {
      'cases: status 200': (r) => r.status === 200,
    });
    casesListDuration.add(res.timings.duration);
    errorRate.add(!ok);
  });

  sleep(0.5);

  group('Notifications List', () => {
    const res = http.get(`${API_BASE}/notifications/${uid}`, { headers });
    const ok  = check(res, {
      'notif: status 200': (r) => r.status === 200,
    });
    notifListDuration.add(res.timings.duration);
    errorRate.add(!ok);
  });

  sleep(1);
}
