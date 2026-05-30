// ================================================================
// DASH Backend API — E2E / Integration 테스트
// 대상: dash_mobile/server/index.js (Express + MySQL)
// 시나리오: 헬스체크 → 인증 → 케이스 CRUD → 레코드 공유 → 볼트
//
// 실행: BASE_URL=https://dash.qpon npx playwright test tests/api.spec.ts
//   또는 로컬: BASE_URL=http://localhost:3000
// ================================================================

import { test, expect, request, APIRequestContext } from '@playwright/test';
import { ENV } from '../fixtures/test-data';

// ── 공통: API 클라이언트 설정 ───────────────────────────────
let apiContext: APIRequestContext;

test.beforeAll(async ({ playwright }) => {
  apiContext = await playwright.request.newContext({
    baseURL: ENV.API_BASE_URL,
    extraHTTPHeaders: {
      'Content-Type': 'application/json',
      ...(ENV.TEST_ID_TOKEN ? { Authorization: `Bearer ${ENV.TEST_ID_TOKEN}` } : {}),
    },
    // 자체 서명 인증서 허용 (스테이징 환경)
    ignoreHTTPSErrors: true,
  });
});

test.afterAll(async () => {
  await apiContext.dispose();
});

// ── 헬스체크 ────────────────────────────────────────────────
test.describe('서버 헬스체크', () => {
  test('TC-API-001: GET /health → 200 OK', async () => {
    const res = await apiContext.get('/health');
    expect(res.status()).toBe(200);

    const body = await res.json();
    expect(body).toHaveProperty('status');
    expect(body.status).toMatch(/ok|healthy|up/i);
  });

  test('TC-API-002: 응답 헤더 — 보안 헤더(Helmet) 적용 확인', async () => {
    const res = await apiContext.get('/health');

    // Helmet 기본 헤더 확인
    expect(res.headers()['x-content-type-options']).toBe('nosniff');
    expect(res.headers()['x-frame-options']).toBeTruthy();
    expect(res.headers()['x-xss-protection']).toBeTruthy();
  });

  test('TC-API-003: 응답 헤더 — X-Powered-By 제거 확인', async () => {
    const res = await apiContext.get('/health');
    // Express 기본 헤더가 노출되면 안 됨
    expect(res.headers()['x-powered-by']).toBeUndefined();
  });
});

// ── 인증 미들웨어 ────────────────────────────────────────────
test.describe('인증 미들웨어', () => {
  test('TC-API-004: 인증 없이 보호 엔드포인트 접근 → 401', async () => {
    const noAuthCtx = await request.newContext({
      baseURL: ENV.API_BASE_URL,
      ignoreHTTPSErrors: true,
    });

    const res = await noAuthCtx.get(`/api/cases/user/${ENV.TEST_UID}`);
    expect([401, 403]).toContain(res.status());

    await noAuthCtx.dispose();
  });

  test('TC-API-005: 유효하지 않은 토큰 → 401', async () => {
    const badAuthCtx = await request.newContext({
      baseURL: ENV.API_BASE_URL,
      extraHTTPHeaders: { Authorization: 'Bearer invalid.token.here' },
      ignoreHTTPSErrors: true,
    });

    const res = await badAuthCtx.get(`/api/cases/user/${ENV.TEST_UID}`);
    expect([401, 403]).toContain(res.status());

    await badAuthCtx.dispose();
  });

  test('TC-API-006: 인증된 요청 → 200 (토큰이 주입된 경우)', async () => {
    if (!ENV.TEST_ID_TOKEN) {
      test.skip();
      return;
    }

    const res = await apiContext.get(`/api/cases/user/${ENV.TEST_UID}`);
    expect(res.status()).toBe(200);
  });
});

// ── Rate Limiting ────────────────────────────────────────────
test.describe('Rate Limiting', () => {
  test('TC-API-007: /health 엔드포인트 — 연속 요청 Rate Limit 없음(공개)', async () => {
    // /health는 속도 제한이 없어야 함
    const requests = Array.from({ length: 10 }, () => apiContext.get('/health'));
    const responses = await Promise.all(requests);

    const tooManyRequests = responses.filter(r => r.status() === 429);
    expect(tooManyRequests.length).toBe(0);
  });

  test('TC-API-008: 보호 엔드포인트 — 과도한 요청 시 429 반환', async () => {
    // 실제 Rate Limit 테스트는 CI에서만 (프로덕션 제한 방지)
    if (ENV.API_BASE_URL.includes('dash.qpon') && !process.env.CI) {
      test.skip();
      return;
    }

    // 31회 이상 요청 (서버 설정: Auth 엔드포인트 30/15min)
    const loginAttempts = Array.from({ length: 35 }, (_, i) =>
      request.newContext({ baseURL: ENV.API_BASE_URL, ignoreHTTPSErrors: true })
        .then(ctx => ctx.post('/api/users/update_profile', {
          data: { uid: `fake-uid-${i}`, name: 'test' },
        }))
    );

    const responses = await Promise.allSettled(loginAttempts);
    const statuses = responses
      .filter(r => r.status === 'fulfilled')
      .map(r => (r as PromiseFulfilledResult<any>).value.status());

    // 35번 중 적어도 1번은 429여야 함
    expect(statuses.some(s => s === 429)).toBe(true);
  });
});

// ── 공유 레코드 API (인증 불필요) ──────────────────────────
test.describe('공유 레코드 API', () => {
  const TEST_TOKEN = 'qa-share-token-00001';

  test('TC-API-009: GET /api/records/share/:token — 없는 토큰 → 404', async () => {
    const res = await apiContext.get('/api/records/share/nonexistent-token-xyz');
    expect(res.status()).toBe(404);
  });

  test('TC-API-010: GET /api/records/share/:token — 유효한 토큰 → 200 + 필수 필드', async () => {
    if (!ENV.TEST_ID_TOKEN) { test.skip(); return; }

    const res = await apiContext.get(`/api/records/share/${TEST_TOKEN}`);
    if (res.status() === 404) {
      // 테스트 데이터 없으면 스킵
      test.skip();
      return;
    }

    expect(res.status()).toBe(200);
    const body = await res.json();

    // 필수 필드 확인
    expect(body).toHaveProperty('share_token');
    expect(body).toHaveProperty('case_name');
    expect(body).toHaveProperty('status');
    expect(body).toHaveProperty('created_at');
  });

  test('TC-API-011: GET /api/shared-records/:token — 인증 없이 접근 가능', async () => {
    const noAuthCtx = await request.newContext({
      baseURL: ENV.API_BASE_URL,
      ignoreHTTPSErrors: true,
    });

    // 이 엔드포인트는 인증 없이 접근 가능 (reviewer용)
    const res = await noAuthCtx.get(`/api/shared-records/${TEST_TOKEN}`);
    // 404(토큰 없음) 또는 200(존재) 모두 허용. 401은 불허.
    expect(res.status()).not.toBe(401);
    expect(res.status()).not.toBe(403);

    await noAuthCtx.dispose();
  });

  test('TC-API-012: POST /api/records/auth/:token — name 검증', async () => {
    // 이름 인증 엔드포인트 (인증 불필요)
    const noAuthCtx = await request.newContext({
      baseURL: ENV.API_BASE_URL,
      ignoreHTTPSErrors: true,
    });

    const res = await noAuthCtx.post(`/api/records/auth/${TEST_TOKEN}`, {
      data: { name: '테스트이름' },
    });

    // 404(토큰 없음) 또는 200/403(이름 일치 여부) 반환
    expect([200, 403, 404]).toContain(res.status());

    await noAuthCtx.dispose();
  });
});

// ── 케이스 & 레코드 CRUD (인증 필요) ───────────────────────
test.describe('케이스 & 레코드 CRUD', () => {
  test.skip(!ENV.TEST_ID_TOKEN, '실제 Firebase 토큰 필요 (DASH_TEST_ID_TOKEN 환경변수 설정)');

  let createdCaseId: number;
  let createdRecordId: number;
  const TEST_CASE_NAME = `QA-테스트-케이스-${Date.now()}`;

  test('TC-API-013: POST /api/cases — 케이스 생성', async () => {
    const res = await apiContext.post('/api/cases', {
      data: {
        userId: ENV.TEST_UID,
        caseName: TEST_CASE_NAME,
        dong: '강남동',
        counselors: [{ uid: ENV.TEST_UID, name: 'QA상담원', masked_name: 'Q**원' }],
      },
    });

    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body).toHaveProperty('id');
    createdCaseId = body.id;
  });

  test('TC-API-014: GET /api/cases/user/:userId — 케이스 목록 조회', async () => {
    const res = await apiContext.get(`/api/cases/user/${ENV.TEST_UID}`);
    expect(res.status()).toBe(200);

    const body = await res.json();
    expect(Array.isArray(body)).toBe(true);

    // 방금 생성한 케이스가 목록에 포함
    if (createdCaseId) {
      const found = body.find((c: any) => c.id === createdCaseId);
      expect(found).toBeTruthy();
      expect(found.case_name).toBe(TEST_CASE_NAME);
    }
  });

  test('TC-API-015: POST /api/records — 레코드 생성 (encrypted_blob)', async () => {
    if (!createdCaseId) { test.skip(); return; }

    const { encryptBlob, FIXTURE_RECORD_PLAINTEXT, FIXTURE_ENC_KEY } = await import('../fixtures/test-data');
    const blob = encryptBlob(FIXTURE_RECORD_PLAINTEXT, FIXTURE_ENC_KEY);

    const res = await apiContext.post('/api/records', {
      data: {
        caseId: createdCaseId,
        userId: ENV.TEST_UID,
        encrypted_blob: blob,
        case_name: TEST_CASE_NAME,
        service_name: '사례관리',
        method: '방문',
        status: 'Synced',
      },
    });

    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body).toHaveProperty('id');
    expect(body).toHaveProperty('share_token');
    createdRecordId = body.id;
  });

  test('TC-API-016: GET /api/records/user/all — 전체 레코드 목록', async () => {
    const res = await apiContext.get(`/api/records/user/all`);
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(Array.isArray(body)).toBe(true);
  });

  test('TC-API-017: PUT /api/records/:id/review — 상태 업데이트', async () => {
    if (!createdRecordId) { test.skip(); return; }

    const res = await apiContext.put(`/api/records/${createdRecordId}/review`, {
      data: { status: 'Reviewed' },
    });

    expect([200, 204]).toContain(res.status());
  });

  test('TC-API-018: DELETE /api/records/id/:id — 레코드 삭제', async () => {
    if (!createdRecordId) { test.skip(); return; }

    const res = await apiContext.delete(`/api/records/id/${createdRecordId}`);
    expect([200, 204]).toContain(res.status());
  });

  test('TC-API-019: DELETE /api/cases/:caseId — 케이스 삭제', async () => {
    if (!createdCaseId) { test.skip(); return; }

    const res = await apiContext.delete(`/api/cases/${createdCaseId}`);
    expect([200, 204]).toContain(res.status());
  });
});

// ── 사용자 API ──────────────────────────────────────────────
test.describe('사용자 프로필 API', () => {
  test.skip(!ENV.TEST_ID_TOKEN, '실제 Firebase 토큰 필요');

  test('TC-API-020: GET /api/users/:id — 프로필 조회', async () => {
    const res = await apiContext.get(`/api/users/${ENV.TEST_UID}`);
    expect(res.status()).toBe(200);

    const body = await res.json();
    expect(body).toHaveProperty('uid');
    expect(body).toHaveProperty('email');
  });

  test('TC-API-021: GET /api/users/:id/stats — 통계 조회', async () => {
    const res = await apiContext.get(`/api/users/${ENV.TEST_UID}/stats`);
    expect([200, 404]).toContain(res.status());

    if (res.status() === 200) {
      const body = await res.json();
      expect(typeof body).toBe('object');
    }
  });

  test('TC-API-022: POST /api/users/update_profile — 닉네임 변경', async () => {
    const res = await apiContext.post('/api/users/update_profile', {
      data: {
        uid: ENV.TEST_UID,
        name: 'QA-테스트-상담원',
      },
    });

    expect([200, 204]).toContain(res.status());
  });

  test('TC-API-023: POST /api/users/fcm_token — FCM 토큰 등록', async () => {
    const res = await apiContext.post('/api/users/fcm_token', {
      data: {
        uid: ENV.TEST_UID,
        fcm_token: 'mock-fcm-token-qa-test-12345',
      },
    });

    expect([200, 204]).toContain(res.status());
  });
});

// ── 볼트 API (E2EE 키 동기화) ──────────────────────────────
test.describe('키 볼트 API', () => {
  test.skip(!ENV.TEST_ID_TOKEN, '실제 Firebase 토큰 필요');

  test('TC-API-024: POST /api/vault — 볼트 저장', async () => {
    const res = await apiContext.post('/api/vault', {
      data: {
        userId: ENV.TEST_UID,
        encrypted_vault: 'mock-encrypted-vault-data',
        salt: 'mock-salt-base64',
      },
    });

    expect([200, 201, 204]).toContain(res.status());
  });

  test('TC-API-025: GET /api/vault/:userId — 볼트 조회', async () => {
    const res = await apiContext.get(`/api/vault/${ENV.TEST_UID}`);
    expect([200, 404]).toContain(res.status());

    if (res.status() === 200) {
      const body = await res.json();
      expect(body).toHaveProperty('encrypted_vault');
      expect(body).toHaveProperty('salt');
    }
  });
});

// ── 알림 API ────────────────────────────────────────────────
test.describe('알림 API', () => {
  test.skip(!ENV.TEST_ID_TOKEN, '실제 Firebase 토큰 필요');

  test('TC-API-026: GET /api/notifications/:userId — 알림 목록', async () => {
    const res = await apiContext.get(`/api/notifications/${ENV.TEST_UID}`);
    expect(res.status()).toBe(200);

    const body = await res.json();
    expect(Array.isArray(body)).toBe(true);
  });

  test('TC-API-027: PUT /api/notifications/:id/read — 알림 읽음 처리', async () => {
    // 알림이 없는 경우 404 허용
    const res = await apiContext.put('/api/notifications/99999/read');
    expect([200, 204, 404]).toContain(res.status());
  });
});

// ── 데이터 검증 (입력 유효성) ───────────────────────────────
test.describe('입력 유효성 검증', () => {
  test('TC-API-028: POST /api/cases — 필수 필드 누락 → 400', async () => {
    if (!ENV.TEST_ID_TOKEN) { test.skip(); return; }

    const res = await apiContext.post('/api/cases', {
      data: {
        // caseName 누락
        userId: ENV.TEST_UID,
      },
    });

    expect([400, 422]).toContain(res.status());
  });

  test('TC-API-029: POST /api/records — case_id 없이 생성 → 400', async () => {
    if (!ENV.TEST_ID_TOKEN) { test.skip(); return; }

    const res = await apiContext.post('/api/records', {
      data: {
        userId: ENV.TEST_UID,
        // caseId 누락
        encrypted_blob: 'some-blob',
      },
    });

    expect([400, 422]).toContain(res.status());
  });

  test('TC-API-030: SQL Injection 시도 — 오류 없이 처리', async () => {
    const sqlPayload = "'; DROP TABLE dash_users; --";

    const res = await apiContext.get(
      `/api/records/share/${encodeURIComponent(sqlPayload)}`
    );

    // SQL 실행 시도에도 서버가 500 없이 응답해야 함
    expect(res.status()).not.toBe(500);
    expect([400, 404]).toContain(res.status());
  });
});

// ── SSE (Server-Sent Events) ────────────────────────────────
test.describe('실시간 이벤트 (SSE)', () => {
  test('TC-API-031: GET /api/events — 연결 헤더 확인', async () => {
    if (!ENV.TEST_ID_TOKEN) { test.skip(); return; }

    // SSE는 스트리밍이므로 헤더만 확인하고 즉시 닫음
    const response = await apiContext.get(
      `/api/events?userId=${ENV.TEST_UID}`,
      { timeout: 3000 }
    ).catch(err => {
      // 타임아웃은 SSE에서 정상 (스트림이 열려있으므로)
      return null;
    });

    if (response) {
      const contentType = response.headers()['content-type'];
      expect(contentType).toMatch(/text\/event-stream/i);
    }
  });
});
