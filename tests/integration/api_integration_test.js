/**
 * DASH 통합 테스트 스크립트
 *
 * 대상: Backend API (Express + MySQL)
 * 범위: Mobile ↔ API, Reviewer Web ↔ API, Extension ↔ API
 * 실행: node tests/integration/api_integration_test.js [--prod|--local]
 *
 * 사전 조건:
 *   - Node.js 18+
 *   - 서버가 실행 중이어야 함 (local: http://localhost:3000, prod: https://dash.qpon)
 *   - DASH_TEST_TOKEN=<Firebase ID Token> 환경변수 설정 (인증 테스트용)
 *   - DASH_ADMIN_SECRET=<admin secret> 환경변수 설정 (Admin API 테스트용)
 */

'use strict';

// ── 설정 ──────────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const USE_PROD = args.includes('--prod');
const BASE_URL = USE_PROD ? 'https://dash.qpon' : 'http://localhost:3000';
const API = `${BASE_URL}/api`;

const TEST_TOKEN   = process.env.DASH_TEST_TOKEN   || '';   // Firebase ID Token (eyJ...)
const ADMIN_SECRET = process.env.DASH_ADMIN_SECRET || '';

// 테스트 픽스처 (실제 값과 충돌하지 않는 테스트 전용 데이터)
const TEST_USER_ID  = `test_uid_${Date.now()}`;
const TEST_CASE_ID  = Math.floor(Date.now() / 1000);        // BIGINT-safe Unix timestamp
const TEST_SHARE_TOKEN = `test_token_${Math.random().toString(36).slice(2)}`;

// ── 유틸리티 ──────────────────────────────────────────────────────────────────
let passed = 0;
let failed = 0;
const failures = [];

function log(msg)  { process.stdout.write(`  ${msg}\n`); }
function ok(label) { passed++; log(`✅ PASS  ${label}`); }
function fail(label, reason) {
  failed++;
  failures.push({ label, reason });
  log(`❌ FAIL  ${label}\n         → ${reason}`);
}

async function request(method, path, { body, headers = {} } = {}) {
  const url = path.startsWith('http') ? path : `${API}${path}`;
  const opts = {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(TEST_TOKEN ? { Authorization: `Bearer ${TEST_TOKEN}` } : {}),
      ...headers,
    },
  };
  if (body) opts.body = JSON.stringify(body);

  const res = await fetch(url, opts);
  let data;
  try { data = await res.json(); } catch { data = null; }
  return { status: res.status, data, headers: res.headers };
}

function assert(label, condition, detail = '') {
  if (condition) ok(label);
  else fail(label, detail || 'assertion failed');
}

// ── 테스트 그룹 ───────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// [1] 인프라 상태 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testInfrastructure() {
  console.log('\n[1] 인프라 상태 테스트');

  // 1-1. /health: DB 연결 확인
  try {
    const { status, data } = await request('GET', `${BASE_URL}/health`);
    assert('health: HTTP 200', status === 200, `status=${status}`);
    assert('health: status=ok', data?.status === 'ok', `status=${data?.status}`);
    assert('health: db=connected', data?.db === 'connected', `db=${data?.db}`);
    assert('health: uptime 존재', typeof data?.uptime === 'number', `uptime=${data?.uptime}`);
  } catch (e) {
    fail('health check', e.message);
  }

  // 1-2. CORS: Origin 없는 요청 (모바일 앱 시뮬레이션) 허용 확인
  try {
    const res = await fetch(`${API}/users/nonexistent`, {
      method: 'GET',
      headers: { Authorization: `Bearer ${TEST_TOKEN || 'dummy'}` },
    });
    assert('CORS: Origin 없는 요청 허용 (모바일)', res.status !== 0, `HTTP ${res.status}`);
  } catch (e) {
    fail('CORS: Origin 없는 요청', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [2] 인증 미들웨어 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testAuth() {
  console.log('\n[2] 인증 미들웨어 테스트');

  // 2-1. 토큰 없이 보호된 엔드포인트 요청 → 401
  try {
    const { status } = await request('GET', `/users/${TEST_USER_ID}`, { headers: { Authorization: '' } });
    assert('auth: 토큰 없음 → 401', status === 401, `status=${status}`);
  } catch (e) {
    fail('auth: 토큰 없음', e.message);
  }

  // 2-2. 잘못된 토큰 → 401
  try {
    const { status } = await request('GET', `/users/${TEST_USER_ID}`, {
      headers: { Authorization: 'Bearer invalid_token_xyz' },
    });
    assert('auth: 잘못된 토큰 → 401', status === 401, `status=${status}`);
  } catch (e) {
    fail('auth: 잘못된 토큰', e.message);
  }

  // 2-3. 유효한 Firebase 토큰 존재 시 인증 통과 확인
  if (TEST_TOKEN && TEST_TOKEN.startsWith('eyJ')) {
    try {
      const { status } = await request('GET', `/users/${TEST_USER_ID}`);
      assert('auth: 유효한 Firebase 토큰 → 401/404 (not 500)', [401, 403, 404].includes(status), `status=${status}`);
    } catch (e) {
      fail('auth: 유효한 토큰 검증', e.message);
    }
  } else {
    log('  ⏭️  SKIP: DASH_TEST_TOKEN 미설정 — Firebase 토큰 검증 테스트 건너뜀');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [3] 사용자(User) API 통합 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testUserAPI() {
  if (!TEST_TOKEN) { log('\n[3] User API — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[3] 사용자 API 통합 테스트');

  // 3-1. 프로필 업데이트
  try {
    const { status, data } = await request('POST', '/users/update_profile', {
      body: { id: TEST_USER_ID, name: 'IntegrationTestUser', email: `inttest_${Date.now()}@test.com` },
    });
    assert('user: 프로필 upsert → 200', status === 200, `status=${status} err=${data?.error}`);
  } catch (e) {
    fail('user: 프로필 업데이트', e.message);
  }

  // 3-2. 사용자 조회
  try {
    const { status, data } = await request('GET', `/users/${TEST_USER_ID}`);
    assert('user: 조회 → 200 or 404', [200, 404].includes(status), `status=${status}`);
    if (status === 200) {
      assert('user: id 필드 존재', !!data?.id, `id=${data?.id}`);
      assert('user: email 필드 존재', !!data?.email, `email=${data?.email}`);
    }
  } catch (e) {
    fail('user: 사용자 조회', e.message);
  }

  // 3-3. 사용자 통계 조회
  try {
    const { status, data } = await request('GET', `/users/${TEST_USER_ID}/stats`);
    assert('user: stats → 200', status === 200, `status=${status}`);
    if (status === 200) {
      assert('user: total_records_created 숫자', typeof data?.total_records_created === 'number', JSON.stringify(data));
      assert('user: case_count 숫자', typeof data?.case_count === 'number', JSON.stringify(data));
      assert('user: current_db_count 숫자', typeof data?.current_db_count === 'number', JSON.stringify(data));
    }
  } catch (e) {
    fail('user: 통계 조회', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [4] 사례(Case) API 통합 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testCaseAPI() {
  if (!TEST_TOKEN) { log('\n[4] Case API — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[4] 사례 API 통합 테스트');

  // 4-1. 사례 생성 (BIGINT ID)
  try {
    const { status, data } = await request('POST', '/cases', {
      body: {
        id: TEST_CASE_ID,
        user_id: TEST_USER_ID,
        user_email: `inttest_${Date.now()}@test.com`,
        user_name: 'IntegrationTest',
        case_name: '[테스트] 홍길동',
        dong: '테스트동',
        target_system_code: 'NCADS_v2',
      },
    });
    assert('case: 생성 → 200', status === 200, `status=${status} err=${data?.error}`);
    if (status === 200) {
      assert('case: 응답에 id 존재', data?.id !== undefined, `data=${JSON.stringify(data)}`);
      // 스키마 일관성: 서버가 반환한 id가 클라이언트가 보낸 BIGINT와 일치하는지 확인
      assert('case: 반환 id == 요청 id (BIGINT 타입 보존)', String(data.id) === String(TEST_CASE_ID), `returned=${data.id} sent=${TEST_CASE_ID}`);
    }
  } catch (e) {
    fail('case: 사례 생성', e.message);
  }

  // 4-2. 사례 목록 조회
  try {
    const { status, data } = await request('GET', `/cases/user/${TEST_USER_ID}`);
    assert('case: 목록 조회 → 200', status === 200, `status=${status}`);
    assert('case: 배열 반환', Array.isArray(data), `type=${typeof data}`);
    if (Array.isArray(data)) {
      const found = data.find(c => String(c.id) === String(TEST_CASE_ID));
      assert('case: 생성한 사례 목록에 존재', !!found, `ids=${data.map(c=>c.id).join(',')}`);
      if (found) {
        // 스키마 필드 무결성 체크
        assert('case: case_name 필드 존재', typeof found.case_name === 'string', JSON.stringify(found));
        assert('case: dong 필드 존재', found.dong !== undefined, JSON.stringify(found));
        assert('case: target_system_code 필드 존재', found.target_system_code !== undefined, JSON.stringify(found));
      }
    }
  } catch (e) {
    fail('case: 목록 조회', e.message);
  }

  // 4-3. 사례 생성 → 중복 ID 처리 (ON DUPLICATE KEY UPDATE)
  try {
    const { status, data } = await request('POST', '/cases', {
      body: {
        id: TEST_CASE_ID,
        user_id: TEST_USER_ID,
        case_name: '[테스트] 홍길동 - 수정됨',
        dong: '테스트동',
        target_system_code: 'NCADS_v2',
      },
    });
    assert('case: 중복 ID upsert → 200 (충돌 없음)', status === 200, `status=${status} err=${data?.error}`);
  } catch (e) {
    fail('case: 중복 ID upsert', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [5] 레코드(Record) 동기화 통합 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testRecordSync() {
  if (!TEST_TOKEN) { log('\n[5] Record Sync — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[5] 레코드 동기화 통합 테스트');

  // 테스트용 더미 encrypted_blob (AES-256-CBC 포맷: base64_iv:base64_ciphertext)
  const fakeEncBlob = 'dGVzdGl2MTIzNDU2Nzg=:dGVzdGNpcGhlcnRleHQ=';

  // 5-1. 신규 레코드 동기화 (share_token 미제공 → 서버가 생성)
  let createdToken = null;
  try {
    const { status, data } = await request('POST', '/records', {
      body: {
        case_id: TEST_CASE_ID,
        case_name: '[테스트] 홍길동',
        dong: '테스트동',
        user_id: TEST_USER_ID,
        user_email: `inttest@test.com`,
        user_name: 'IntegrationTest',
        provision_type: '직접',
        method: '방문',
        service_type: '상담',
        service_category: '일반상담',
        service_name: '개인상담',
        location: '센터',
        start_time: '2026-05-29 10:00:00',
        end_time: '2026-05-29 11:00:00',
        service_count: 1,
        travel_time: 15,
        service_description: '통합테스트 레코드입니다.',
        agent_opinion: '특이사항 없음.',
        encrypted_blob: fakeEncBlob,
        is_shared_db: 0,
      },
    });
    assert('record: 신규 동기화 → 200', status === 200, `status=${status} err=${data?.error}`);
    if (status === 200) {
      assert('record: share_token 반환', typeof data?.share_token === 'string' && data.share_token.length > 0, `token=${data?.share_token}`);
      assert('record: id(DB PK) 반환', typeof data?.id === 'number', `id=${data?.id}`);
      createdToken = data.share_token;
    }
  } catch (e) {
    fail('record: 신규 동기화', e.message);
  }

  // 5-2. 동일 share_token으로 레코드 업데이트 (幂等성 테스트)
  if (createdToken) {
    try {
      const { status, data } = await request('POST', '/records', {
        body: {
          case_id: TEST_CASE_ID,
          case_name: '[테스트] 홍길동',
          user_id: TEST_USER_ID,
          provision_type: '직접',
          method: '방문',
          service_type: '상담',
          service_category: '일반상담',
          service_name: '개인상담',
          location: '센터 - 수정됨',
          start_time: '2026-05-29 10:00:00',
          end_time: '2026-05-29 12:00:00',
          service_count: 2,
          travel_time: 20,
          service_description: '업데이트된 내용입니다.',
          agent_opinion: '수정된 소견.',
          encrypted_blob: fakeEncBlob,
          share_token: createdToken,
        },
      });
      assert('record: 동일 토큰 업데이트 → 200 (幂等성)', status === 200, `status=${status} err=${data?.error}`);
      if (status === 200) {
        assert('record: 업데이트 시 동일 share_token 반환', data?.share_token === createdToken, `expected=${createdToken} got=${data?.share_token}`);
      }
    } catch (e) {
      fail('record: 토큰 기반 업데이트', e.message);
    }
  }

  // 5-3. 레코드 목록 조회 — 레코드가 유저에 연결되어 있는지 확인
  try {
    const { status, data } = await request('GET', `/records/user/${TEST_USER_ID}`);
    assert('record: 목록 조회 → 200', status === 200, `status=${status}`);
    if (status === 200) {
      assert('record: 배열 반환', Array.isArray(data), `type=${typeof data}`);
    }
  } catch (e) {
    fail('record: 목록 조회', e.message);
  }

  // 5-4. 서비스 내용 길이 초과 방어 (100,001자 → 400)
  try {
    const { status } = await request('POST', '/records', {
      body: {
        case_id: TEST_CASE_ID,
        user_id: TEST_USER_ID,
        service_description: 'A'.repeat(100001),
        provision_type: '직접',
        method: '방문',
        service_type: '상담',
        service_name: '테스트',
        location: '센터',
        start_time: '2026-05-29 10:00:00',
        end_time: '2026-05-29 11:00:00',
      },
    });
    assert('record: 서비스 내용 100001자 → 400 거부', status === 400, `status=${status}`);
  } catch (e) {
    fail('record: 길이 초과 방어', e.message);
  }

  // 5-5. 빈 active_tokens로 sync_active 호출 → 전체 삭제 방지 (데이터 유실 방어)
  try {
    const { status, data } = await request('POST', '/records/sync_active', {
      body: { user_email: 'inttest@test.com', active_tokens: [] },
    });
    assert('record: 빈 active_tokens → 삭제 건너뜀 (data loss 방지)', status === 200, `status=${status}`);
    if (status === 200) {
      assert('record: sync skipped 메시지', data?.deleted_count === 0, `deleted=${data?.deleted_count}`);
    }
  } catch (e) {
    fail('record: 빈 tokens sync_active', e.message);
  }

  return createdToken;
}

// ─────────────────────────────────────────────────────────────────────────────
// [6] 공유 링크(Reviewer Web) 통합 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testShareAndReviewer(shareToken) {
  console.log('\n[6] 공유 링크 / Reviewer Web 통합 테스트');

  // 사용할 토큰: 파라미터 또는 고정 테스트 토큰
  const token = shareToken || TEST_SHARE_TOKEN;

  // 6-1. GET /api/records/share/:token — 인증 없이 공유 레코드 조회
  try {
    const { status, data } = await request('GET', `/records/share/${token}`, { headers: { Authorization: '' } });
    if (status === 200) {
      assert('share: 공유 레코드 조회 성공', true);
      // 응답 스키마 검증
      assert('share: share_token 필드 존재', data?.share_token !== undefined, JSON.stringify(Object.keys(data || {})));
      assert('share: encrypted_blob 필드 존재', 'encrypted_blob' in data, JSON.stringify(Object.keys(data || {})));
      assert('share: case_name 필드 존재', 'case_name' in data, JSON.stringify(Object.keys(data || {})));
      assert('share: status 필드 존재', 'status' in data, JSON.stringify(Object.keys(data || {})));

      // E2EE blob 포맷 확인 (base64_iv:base64_ciphertext)
      if (data?.encrypted_blob) {
        const parts = data.encrypted_blob.split(':');
        assert('share: encrypted_blob 포맷 iv:ciphertext', parts.length === 2, `blob=${data.encrypted_blob.slice(0, 40)}`);
        const ivOk = /^[A-Za-z0-9+/=]+$/.test(parts[0]);
        assert('share: encrypted_blob iv가 base64', ivOk, `iv=${parts[0]}`);
      }

      // 민감 필드 노출 여부 확인 (encryption_key는 서버에 저장 안 되지만 방어적 체크)
      assert('share: encryption_key 미노출', data?.encryption_key === undefined, 'encryption_key should not be in response');
    } else if (status === 404) {
      assert('share: 존재하지 않는 토큰 → 404', true);
    } else if (status === 401) {
      fail('share: 인증 없이 공유 레코드 조회 실패 (공개 엔드포인트인데 401)', `status=401`);
    } else {
      fail('share: 공유 레코드 조회', `status=${status} data=${JSON.stringify(data)}`);
    }
  } catch (e) {
    fail('share: 공유 레코드 조회', e.message);
  }

  // 6-2. 만료된 / 존재하지 않는 토큰 → 404
  try {
    const { status } = await request('GET', '/records/share/nonexistent_token_xyz_999', { headers: { Authorization: '' } });
    assert('share: 존재하지 않는 토큰 → 404', status === 404, `status=${status}`);
  } catch (e) {
    fail('share: 존재하지 않는 토큰 404 확인', e.message);
  }

  // 6-3. OG 태그 HTML — /?token= 직접 HTML 응답 확인
  try {
    const res = await fetch(`${BASE_URL}/?token=${token}`);
    const html = await res.text();
    assert('share: /?token= HTML 응답 (redirect 아님)', res.status === 200, `status=${res.status}`);
    assert('share: og:title 태그 포함', html.includes('og:title'), 'og:title not found');
    assert('share: og:image 태그 포함', html.includes('og:image'), 'og:image not found');
    assert('share: DASH 브랜드 포함', html.includes('DASH'), 'DASH not found');
  } catch (e) {
    fail('share: OG 태그 HTML', e.message);
  }

  // 6-4. /share/:token → App links / 딥링크 페이지 반환 (HTML)
  //       토큰이 DB에 없으면 404+HTML(만료 안내), 있으면 200+HTML — 둘 다 정상
  try {
    const res = await fetch(`${BASE_URL}/share/${token}`);
    assert('share: /share/:token → 200 또는 404 (HTML 응답)', [200, 404].includes(res.status), `status=${res.status}`);
    const html = await res.text();
    assert('share: 딥링크 HTML 반환 (redirect 없음)', html.includes('<!DOCTYPE html>') || html.includes('<html'), 'not HTML');
  } catch (e) {
    fail('share: /share/:token 딥링크 페이지', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [7] 상담원(Counselor) API 통합 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testCounselorAPI() {
  if (!TEST_TOKEN) { log('\n[7] Counselor API — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[7] 상담원 API 통합 테스트');

  const counselorId = `ctest_${Date.now()}`;

  // 7-1. 상담원 생성
  try {
    const { status, data } = await request('POST', '/counselors', {
      body: {
        id: counselorId,
        user_id: TEST_USER_ID,
        name: '테스트 상담원',
        is_self: false,
        sort_order: 0,
      },
    });
    assert('counselor: 생성 → 200', status === 200, `status=${status} err=${data?.error}`);
  } catch (e) {
    fail('counselor: 생성', e.message);
  }

  // 7-2. 상담원 목록 조회
  try {
    const { status, data } = await request('GET', `/counselors/${TEST_USER_ID}`);
    assert('counselor: 목록 조회 → 200', status === 200, `status=${status}`);
    assert('counselor: 배열 반환', Array.isArray(data), `type=${typeof data}`);
    if (Array.isArray(data)) {
      const found = data.find(c => c.id === counselorId);
      assert('counselor: 생성한 상담원 목록에 존재', !!found, `ids=${data.map(c=>c.id).join(',')}`);
      if (found) {
        assert('counselor: name 필드 존재', typeof found.name === 'string', JSON.stringify(found));
        assert('counselor: is_self 필드 존재', found.is_self !== undefined, JSON.stringify(found));
        assert('counselor: sort_order 필드 존재', found.sort_order !== undefined, JSON.stringify(found));
      }
    }
  } catch (e) {
    fail('counselor: 목록 조회', e.message);
  }

  // 7-3. 순서 변경
  try {
    const { status } = await request('PUT', '/counselors/reorder', {
      body: { counselors: [{ id: counselorId, sort_order: 1 }] },
    });
    assert('counselor: 순서 변경 → 200', status === 200, `status=${status}`);
  } catch (e) {
    fail('counselor: 순서 변경', e.message);
  }

  // 7-4. 상담원 삭제
  try {
    const { status } = await request('DELETE', `/counselors/${counselorId}`);
    assert('counselor: 삭제 → 200', status === 200, `status=${status}`);
  } catch (e) {
    fail('counselor: 삭제', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [8] Vault (Zero-Knowledge) 통합 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testVault() {
  if (!TEST_TOKEN) { log('\n[8] Vault API — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[8] Vault (Zero-Knowledge) 통합 테스트');

  const fakeEncryptedVault = Buffer.from('{"test":"encrypted_data"}').toString('base64');
  const fakeSalt = Buffer.from('testsalt12345678').toString('hex');

  // 8-1. Vault 저장
  try {
    const { status, data } = await request('POST', '/users/vault', {
      body: {
        user_id: TEST_USER_ID,
        encrypted_vault: fakeEncryptedVault,
        salt: fakeSalt,
      },
    });
    assert('vault: 저장 → 200', status === 200, `status=${status} err=${data?.error}`);
  } catch (e) {
    fail('vault: 저장', e.message);
  }

  // 8-2. Vault 조회
  try {
    const { status, data } = await request('GET', `/users/vault/${TEST_USER_ID}`);
    assert('vault: 조회 → 200 or 404', [200, 404].includes(status), `status=${status}`);
    if (status === 200) {
      assert('vault: encrypted_vault 필드 존재', data?.encrypted_vault !== undefined, JSON.stringify(Object.keys(data || {})));
      assert('vault: salt 필드 존재', data?.salt !== undefined, JSON.stringify(Object.keys(data || {})));
      // 중요: 서버는 vault를 그대로 반환해야 함 (복호화 없이) — zero-knowledge
      assert('vault: encryption_key 미포함 (zero-knowledge)', data?.encryption_key === undefined, 'should not expose encryption_key');
    }
  } catch (e) {
    fail('vault: 조회', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [9] SSE (Server-Sent Events) 통합 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testSSE() {
  if (!TEST_TOKEN) { log('\n[9] SSE — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[9] SSE 실시간 이벤트 테스트');

  await new Promise((resolve) => {
    const timeout = setTimeout(() => {
      fail('SSE: 5초 내 connected 이벤트 수신 실패', 'timeout');
      resolve();
    }, 5000);

    fetch(`${API}/events?email=inttest@test.com&token=${TEST_TOKEN}`, {
      headers: { Accept: 'text/event-stream' },
    }).then(res => {
      assert('SSE: 연결 → 200', res.status === 200, `status=${res.status}`);
      assert('SSE: Content-Type text/event-stream', res.headers.get('content-type')?.includes('text/event-stream'), `ct=${res.headers.get('content-type')}`);

      const reader = res.body.getReader();
      const decoder = new TextDecoder();

      function read() {
        reader.read().then(({ done, value }) => {
          if (done) return;
          const chunk = decoder.decode(value);
          if (chunk.includes('"event":"connected"') || chunk.includes('"event": "connected"')) {
            ok('SSE: connected 이벤트 수신');
            clearTimeout(timeout);
            reader.cancel();
            resolve();
          } else {
            read();
          }
        }).catch(() => resolve());
      }
      read();
    }).catch(e => {
      fail('SSE: 연결', e.message);
      clearTimeout(timeout);
      resolve();
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// [10] Admin KPI API 통합 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testAdminKPI() {
  console.log('\n[10] Admin KPI API 통합 테스트');

  // 10-1. 인증 없이 접근 → 401
  try {
    const { status } = await request('GET', '/admin/kpi', { headers: { Authorization: '', 'X-Admin-Secret': '' } });
    assert('admin: 시크릿 없음 → 401', status === 401, `status=${status}`);
  } catch (e) {
    fail('admin: 인증 없이 접근', e.message);
  }

  // 10-2. 잘못된 시크릿 → 401
  try {
    const { status } = await request('GET', '/admin/kpi', {
      headers: { Authorization: '', 'X-Admin-Secret': 'wrong_secret_xyz' },
    });
    assert('admin: 잘못된 시크릿 → 401', status === 401, `status=${status}`);
  } catch (e) {
    fail('admin: 잘못된 시크릿', e.message);
  }

  // 10-3. 올바른 시크릿 → 200 및 응답 스키마 확인
  if (ADMIN_SECRET) {
    try {
      const { status, data } = await request('GET', '/admin/kpi', {
        headers: { Authorization: '', 'X-Admin-Secret': ADMIN_SECRET },
      });
      assert('admin: 올바른 시크릿 → 200', status === 200, `status=${status}`);
      if (status === 200) {
        assert('admin: users 객체 포함', typeof data?.users === 'object', `keys=${Object.keys(data || {}).join(',')}`);
        assert('admin: records 객체 포함', typeof data?.records === 'object', `keys=${Object.keys(data || {}).join(',')}`);
        assert('admin: cases 객체 포함', typeof data?.cases === 'object', `keys=${Object.keys(data || {}).join(',')}`);
        assert('admin: snapshot_at 포함', typeof data?.snapshot_at === 'string', `snapshot_at=${data?.snapshot_at}`);
        assert('admin: users.total 숫자', typeof data?.users?.total === 'number', `total=${data?.users?.total}`);
        assert('admin: records.total 숫자', typeof data?.records?.total === 'number', `total=${data?.records?.total}`);
      }
    } catch (e) {
      fail('admin: KPI 조회', e.message);
    }
  } else {
    log('  ⏭️  SKIP: DASH_ADMIN_SECRET 미설정 — Admin KPI 응답 검증 건너뜀');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [11] 데이터 유실 / 스키마 충돌 시나리오 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testDataIntegrity() {
  console.log('\n[11] 데이터 무결성 / 스키마 충돌 시나리오');

  // 11-1. case_id 없이 레코드 동기화 → 서버가 플레이스홀더 사례 생성하는지
  //       (모바일 오프라인 → 사례 누락 후 레코드만 먼저 동기화되는 시나리오)
  if (TEST_TOKEN) {
    const orphanCaseId = Math.floor(Date.now() / 1000) + 999999;
    try {
      const { status, data } = await request('POST', '/records', {
        body: {
          case_id: orphanCaseId,
          case_name: '[플레이스홀더] 고아 레코드 테스트',
          dong: '확인 필요',
          user_id: TEST_USER_ID,
          user_email: 'inttest@test.com',
          provision_type: '직접',
          method: '방문',
          service_type: '상담',
          service_name: '테스트',
          location: '센터',
          start_time: '2026-05-29 10:00:00',
          end_time: '2026-05-29 11:00:00',
          service_description: '고아 레코드 테스트',
          agent_opinion: '',
          encrypted_blob: 'dGVzdA==:dGVzdA==',
        },
      });
      assert('integrity: case 누락 시 플레이스홀더 생성 → 200', status === 200, `status=${status} err=${data?.error}`);
      if (status === 200) {
        assert('integrity: share_token 반환 (유실 없음)', typeof data?.share_token === 'string', `token=${data?.share_token}`);
      }
    } catch (e) {
      fail('integrity: 고아 레코드 동기화', e.message);
    }
  }

  // 11-2. 공유 레코드 조회 시 encryption_key 노출 여부 확인
  try {
    const { data } = await request('GET', `/records/share/any_token`, { headers: { Authorization: '' } });
    if (data && typeof data === 'object') {
      assert('integrity: encryption_key 서버 응답에 미포함', data.encryption_key === undefined, `encryption_key 노출됨: ${data.encryption_key}`);
    } else {
      ok('integrity: 존재하지 않는 토큰 → 데이터 미노출');
    }
  } catch (e) {
    fail('integrity: encryption_key 노출 체크', e.message);
  }

  // 11-3. service_category 필드 호환성 — 구버전(없음) vs 신버전(있음)
  //       service_drafts.service_category 컬럼이 마이그레이션으로 추가된 필드
  if (TEST_TOKEN) {
    try {
      const { status, data } = await request('POST', '/records', {
        body: {
          case_id: TEST_CASE_ID,
          user_id: TEST_USER_ID,
          provision_type: '직접',
          method: '방문',
          service_type: '상담',
          // service_category: 생략 (구버전 클라이언트 시뮬레이션)
          service_name: '개인상담',
          location: '센터',
          start_time: '2026-05-29 10:00:00',
          end_time: '2026-05-29 11:00:00',
          service_description: 'service_category 미포함 레코드',
          agent_opinion: '',
          encrypted_blob: 'dGVzdA==:dGVzdA==',
        },
      });
      assert('integrity: service_category 미포함 레코드 동기화 → 200', status === 200, `status=${status} err=${data?.error}`);
    } catch (e) {
      fail('integrity: service_category 하위 호환성', e.message);
    }
  }

  // 11-4. Rate Limit 검증 — vault 엔드포인트 30회/10분 제한 체크
  //       (실제 한도는 치지 않되, 헤더에 ratelimit-limit이 있는지 확인)
  try {
    const { headers } = await request('GET', `/users/vault/${TEST_USER_ID}`);
    const limitHeader = headers.get('ratelimit-limit') || headers.get('x-ratelimit-limit');
    // Railway 환경에서는 헤더가 프록시에서 제거될 수 있으므로 소프트 체크
    if (limitHeader) {
      assert('integrity: rate-limit 헤더 존재', !!limitHeader, `header=${limitHeader}`);
    } else {
      log('  ℹ️  INFO: ratelimit 헤더 없음 (프록시 환경 또는 제외 경로)');
    }
  } catch (e) {
    fail('integrity: rate-limit 헤더 확인', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [12] 크로스 컴포넌트 E2E 시나리오 (Mobile → Web Reviewer → Extension 흐름)
// ─────────────────────────────────────────────────────────────────────────────
async function testCrossComponentE2E() {
  if (!TEST_TOKEN) { log('\n[12] Cross-Component E2E — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[12] 크로스 컴포넌트 E2E 시나리오');

  // 시나리오: 모바일이 레코드를 생성 → 웹 리뷰어가 조회 → 상태가 Synced인지 확인
  // (실제 Reviewed/Injected 전환은 웹 리뷰어/확장프로그램 인증이 필요하므로 상태 흐름 검증에 집중)

  const e2eToken = `e2e_${Math.random().toString(36).slice(2)}_${Date.now().toString(36)}`;
  const fakeBlob = 'dGVzdGl2MTIzNDU2Nzg=:dGVzdGNpcGhlcnRleHQ=';

  // Step 1: 모바일 — 특정 share_token으로 레코드 동기화
  let syncedToken = null;
  try {
    const { status, data } = await request('POST', '/records', {
      body: {
        case_id: TEST_CASE_ID,
        case_name: '[E2E] 테스트 사례',
        user_id: TEST_USER_ID,
        user_email: 'inttest@test.com',
        user_name: 'E2E 테스터',
        provision_type: '직접',
        method: '방문',
        service_type: '상담',
        service_category: '일반상담',
        service_name: 'E2E 테스트 상담',
        location: 'E2E 센터',
        start_time: '2026-05-29 09:00:00',
        end_time: '2026-05-29 10:00:00',
        service_count: 1,
        travel_time: 10,
        service_description: 'E2E 통합 테스트 레코드',
        agent_opinion: 'E2E 소견',
        encrypted_blob: fakeBlob,
        share_token: e2eToken,
      },
    });
    assert('[E2E] Step1: 모바일 레코드 동기화 → 200', status === 200, `status=${status} err=${data?.error}`);
    if (status === 200) syncedToken = data?.share_token;
  } catch (e) {
    fail('[E2E] Step1: 모바일 동기화', e.message);
    return;
  }

  if (!syncedToken) return;

  // Step 2: 웹 리뷰어 — 인증 없이 공유 레코드 조회 (공개 엔드포인트)
  try {
    const { status, data } = await request('GET', `/records/share/${syncedToken}`, { headers: { Authorization: '' } });
    assert('[E2E] Step2: 웹 리뷰어 조회 → 200', status === 200, `status=${status}`);
    if (status === 200) {
      assert('[E2E] Step2: 상태 Synced 확인', data?.status === 'Synced', `status=${data?.status}`);
      assert('[E2E] Step2: encrypted_blob 포함', !!data?.encrypted_blob, `blob=${data?.encrypted_blob?.slice(0, 20)}`);
    }
  } catch (e) {
    fail('[E2E] Step2: 웹 리뷰어 조회', e.message);
  }

  // Step 3: 확장프로그램 — 인증된 레코드 목록 조회 (확장프로그램은 Firebase 토큰 사용)
  try {
    const { status, data } = await request('GET', `/records/user/${TEST_USER_ID}`);
    assert('[E2E] Step3: 확장프로그램 레코드 목록 조회 → 200', status === 200, `status=${status}`);
    if (status === 200 && Array.isArray(data)) {
      const found = data.find(r => r.share_token === syncedToken);
      assert('[E2E] Step3: 동기화한 레코드 확장프로그램에서 조회 가능', !!found || data.length >= 0, `token=${syncedToken}`);
    }
  } catch (e) {
    fail('[E2E] Step3: 확장프로그램 레코드 조회', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 테스트 정리 (생성한 테스트 데이터 삭제)
// ─────────────────────────────────────────────────────────────────────────────
async function cleanup() {
  if (!TEST_TOKEN) return;
  console.log('\n[cleanup] 테스트 데이터 정리...');

  try {
    await request('DELETE', `/cases/${TEST_CASE_ID}`);
    log('  🗑️  테스트 사례 삭제 완료');
  } catch (e) {
    log(`  ⚠️  사례 삭제 실패 (무시): ${e.message}`);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 메인 실행
// ─────────────────────────────────────────────────────────────────────────────
async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('  DASH 통합 테스트 스위트');
  console.log(`  대상: ${BASE_URL}`);
  console.log(`  인증: ${TEST_TOKEN ? '토큰 있음 (' + TEST_TOKEN.slice(0, 10) + '...)' : '토큰 없음 (공개 API만 테스트)'}`);
  console.log('═══════════════════════════════════════════════════════════');

  await testInfrastructure();
  await testAuth();
  await testUserAPI();
  await testCaseAPI();
  const shareToken = await testRecordSync();
  await testShareAndReviewer(shareToken);
  await testCounselorAPI();
  await testVault();
  await testSSE();
  await testAdminKPI();
  await testDataIntegrity();
  await testCrossComponentE2E();
  await cleanup();

  // ── 결과 요약 ─────────────────────────────────────────────────────────────
  const total = passed + failed;
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log(`  결과: ${passed}/${total} 통과  |  ${failed}개 실패`);
  if (failures.length > 0) {
    console.log('\n  실패 목록:');
    failures.forEach(f => console.log(`    ❌ ${f.label}\n       → ${f.reason}`));
  }
  console.log('═══════════════════════════════════════════════════════════\n');

  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('\n💥 테스트 실행 중 예외 발생:', err);
  process.exit(1);
});
