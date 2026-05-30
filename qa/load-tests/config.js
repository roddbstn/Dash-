// ============================================================
// Dash QA - k6 Load Test Global Configuration
// ============================================================

export const BASE_URL = __ENV.BASE_URL || 'https://dash.qpon';
export const API_BASE  = `${BASE_URL}/api`;

// 테스트용 계정 (환경변수로 주입 or 기본값)
// k6 run -e TEST_TOKEN=<firebase_id_token> <script.js>
export const TEST_TOKEN   = __ENV.TEST_TOKEN   || '';
export const TEST_USER_ID = __ENV.TEST_USER_ID || '';
export const TEST_EMAIL   = __ENV.TEST_EMAIL   || '';

// 공통 인증 헤더
export function authHeaders() {
  return {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${TEST_TOKEN}`,
  };
}

// 공통 임계값 (SLA 기준)
export const THRESHOLDS = {
  // HTTP 에러율 1% 미만
  http_req_failed: [{ threshold: 'rate<0.01', abortOnFail: false }],
  // 95th percentile 응답시간 2초 미만
  http_req_duration: [
    { threshold: 'p(95)<2000', abortOnFail: false },
    { threshold: 'p(99)<5000', abortOnFail: false },
  ],
};
