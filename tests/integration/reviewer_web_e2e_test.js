/**
 * DASH Reviewer Web E2E 테스트
 *
 * 대상: dash_mobile/server/reviewer_site/ (app.js, index.html, admin.html)
 * 범위: 공유 링크 조회, E2EE 복호화, 리뷰어 저장, 편집 히스토리, Admin 대시보드
 * 의존성: Playwright (npx playwright test) 또는 순수 fetch (Node.js 18+)
 *
 * 실행 방법 A (Playwright 설치 시):
 *   npx playwright test tests/integration/reviewer_web_e2e_test.js
 *
 * 실행 방법 B (fetch 기반, Playwright 없이):
 *   node tests/integration/reviewer_web_e2e_test.js [--prod|--local]
 *
 * 사전 조건:
 *   - DASH_TEST_TOKEN 환경변수: Firebase ID Token
 *   - DASH_TEST_SHARE_TOKEN 환경변수: 유효한 share_token (있으면 우선 사용)
 */

'use strict';

const args = process.argv.slice(2);
const USE_PROD   = args.includes('--prod');
const BASE_URL   = USE_PROD ? 'https://dash.qpon' : 'http://localhost:3000';
const API        = `${BASE_URL}/api`;
const TEST_TOKEN = process.env.DASH_TEST_TOKEN || '';
const ADMIN_SECRET = process.env.DASH_ADMIN_SECRET || '';

// 테스트 공유 토큰: 환경변수 제공 시 사용, 없으면 직접 생성
const PRESET_SHARE_TOKEN = process.env.DASH_TEST_SHARE_TOKEN || '';

let passed = 0, failed = 0;
const failures = [];

function ok(label)   { passed++; process.stdout.write(`  ✅ PASS  ${label}\n`); }
function fail(label, reason) {
  failed++;
  failures.push({ label, reason });
  process.stdout.write(`  ❌ FAIL  ${label}\n         → ${reason}\n`);
}
function assert(label, cond, detail = '') {
  cond ? ok(label) : fail(label, detail || 'assertion failed');
}
function log(msg) { process.stdout.write(`  ${msg}\n`); }

async function req(method, path, { body, headers = {}, auth = false } = {}) {
  const url = path.startsWith('http') ? path : `${API}${path}`;
  const h = {
    'Content-Type': 'application/json',
    ...(auth && TEST_TOKEN ? { Authorization: `Bearer ${TEST_TOKEN}` } : {}),
    ...headers,
  };
  const opts = { method, headers: h };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(url, opts);
  let data;
  try { data = await res.json(); } catch { data = await res.text().catch(() => null); }
  return { status: res.status, data, headers: res.headers };
}

// ── AES-256-CBC 복호화 헬퍼 (Node.js crypto, 브라우저와 동일 로직) ──────────
const crypto = require('crypto');

function decryptBlob(encryptedBlob, encKey) {
  const parts = encryptedBlob.split(':');
  if (parts.length !== 2) throw new Error(`잘못된 blob 포맷: ${encryptedBlob.slice(0, 30)}`);

  const iv = Buffer.from(parts[0], 'base64');
  const ciphertext = Buffer.from(parts[1], 'base64');
  // 키를 32바이트로 맞춤 (app.js와 동일: padEnd(32).substring(0,32))
  const keyBuf = Buffer.alloc(32);
  const keyStr = (encKey + ' '.repeat(32)).substring(0, 32);
  keyBuf.write(keyStr, 'utf8');

  const decipher = crypto.createDecipheriv('aes-256-cbc', keyBuf, iv);
  const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  return JSON.parse(decrypted.toString('utf8'));
}

function encryptToBlob(plainObj, encKey) {
  const iv = crypto.randomBytes(16);
  const keyBuf = Buffer.alloc(32);
  const keyStr = (encKey + ' '.repeat(32)).substring(0, 32);
  keyBuf.write(keyStr, 'utf8');

  const cipher = crypto.createCipheriv('aes-256-cbc', keyBuf, iv);
  const data = JSON.stringify(plainObj);
  const encrypted = Buffer.concat([cipher.update(data, 'utf8'), cipher.final()]);
  return `${iv.toString('base64')}:${encrypted.toString('base64')}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// 테스트 픽스처 생성 (실제 공유 레코드를 서버에 생성)
// ─────────────────────────────────────────────────────────────────────────────
const TEST_ENC_KEY = 'test_enc_key_reviewer_web_2026';
const TEST_PAYLOAD = {
  case_name: '[Reviewer] 테스트 사례',
  target: '홍길동',
  service_type: '상담',
  service_description: '리뷰어 웹 통합 테스트 레코드입니다.',
  agent_opinion: '특이사항 없음.',
};

async function createTestRecord() {
  const encBlob = encryptToBlob(TEST_PAYLOAD, TEST_ENC_KEY);
  const shareToken = PRESET_SHARE_TOKEN ||
    `reviewer_test_${Math.random().toString(36).slice(2)}`;
  const caseId = Math.floor(Date.now() / 1000);
  const userId = `reviewer_test_uid_${Date.now()}`;

  const { status, data } = await req('POST', '/records', {
    auth: true,
    body: {
      case_id: caseId,
      case_name: '[Reviewer] 테스트 사례',
      dong: '테스트동',
      user_id: userId,
      user_email: 'reviewer_test@test.com',
      user_name: 'ReviewerTest',
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
      service_description: TEST_PAYLOAD.service_description,
      agent_opinion: TEST_PAYLOAD.agent_opinion,
      encrypted_blob: encBlob,
      share_token: shareToken,
      is_shared_db: 0,
    },
  });

  return { status, shareToken: data?.share_token || shareToken, encBlob, caseId, userId };
}

// ─────────────────────────────────────────────────────────────────────────────
// [1] Reviewer Web 공유 레코드 조회 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testReviewerFetch(shareToken, encBlob) {
  console.log('\n[1] Reviewer Web — 공유 레코드 조회');

  // 1-1. 인증 없이 공유 레코드 조회
  try {
    const { status, data } = await req('GET', `/records/share/${shareToken}`);
    assert('reviewer: 공유 레코드 조회 → 인증 불필요 (200/404)', [200, 404].includes(status), `status=${status} data=${JSON.stringify(data)}`);

    if (status === 404) {
      log(`  ℹ️  INFO: 토큰 미존재(404) — 실제 레코드로 테스트하려면 DASH_TEST_SHARE_TOKEN 설정`);
    }
    if (status === 200 && typeof data === 'object') {
      // 응답 스키마 전체 검증
      const requiredFields = ['share_token', 'encrypted_blob', 'status', 'case_name',
        'provision_type', 'method', 'service_type', 'service_name',
        'location', 'start_time', 'end_time', 'service_count', 'travel_time'];
      for (const field of requiredFields) {
        assert(`reviewer: 응답 필드 '${field}' 존재`, field in data, `keys=${Object.keys(data).join(',')}`);
      }

      // 보안: encryption_key 미노출
      assert('reviewer: encryption_key 서버 응답 미노출 (보안)', !('encryption_key' in data),
        '⚠️  SECURITY ISSUE: encryption_key exposed in API response');

      // 상태 확인
      assert(`reviewer: 상태가 'Synced'`, data.status === 'Synced', `status=${data.status}`);

      // E2EE blob 포맷
      if (data.encrypted_blob) {
        const parts = data.encrypted_blob.split(':');
        assert('reviewer: encrypted_blob iv:ciphertext 구조', parts.length === 2,
          `blob=${data.encrypted_blob.slice(0, 40)}`);
        const b64Re = /^[A-Za-z0-9+/=]+$/;
        assert('reviewer: iv가 valid base64', b64Re.test(parts[0]), `iv=${parts[0]}`);
        assert('reviewer: ciphertext가 valid base64', b64Re.test(parts[1]),
          `ct_len=${parts[1].length}`);
      }
    }
  } catch (e) {
    fail('reviewer: 공유 레코드 조회', e.message);
  }

  // 1-2. E2EE 복호화 검증 (Node.js crypto — 브라우저 CryptoJS와 동일 알고리즘)
  try {
    const { data } = await req('GET', `/records/share/${shareToken}`);
    if (data?.encrypted_blob) {
      const decrypted = decryptBlob(data.encrypted_blob, TEST_ENC_KEY);
      assert('reviewer: E2EE 복호화 성공', typeof decrypted === 'object', `type=${typeof decrypted}`);
      assert('reviewer: 복호화 후 service_description 보존',
        decrypted.service_description === TEST_PAYLOAD.service_description,
        `expected="${TEST_PAYLOAD.service_description}" got="${decrypted.service_description}"`);
    }
  } catch (e) {
    fail('reviewer: E2EE 복호화', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [2] 리뷰어 저장 (PUT) 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testReviewerSave(shareToken) {
  if (!TEST_TOKEN) { log('\n[2] Reviewer Save — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[2] Reviewer Web — 리뷰어 저장 (PUT)');

  const updatedDesc = '리뷰어가 수정한 서비스 내용입니다. (통합 테스트)';
  const updatedOpinion = '리뷰어 소견: 상태 양호. 후속 지원 불필요.';
  const updatedBlob = encryptToBlob({
    ...TEST_PAYLOAD,
    service_description: updatedDesc,
    agent_opinion: updatedOpinion,
  }, TEST_ENC_KEY);

  // 2-1. 리뷰어가 레코드 저장 (PUT /api/records/share/:token)
  try {
    const { status, data } = await req('PUT', `/records/share/${shareToken}`, {
      auth: true,
      body: {
        service_description: updatedDesc,
        agent_opinion: updatedOpinion,
        encrypted_blob: updatedBlob,
        reviewer_name: '테스트 리뷰어',
      },
    });
    assert('reviewer-save: PUT → 200', status === 200, `status=${status} err=${JSON.stringify(data)}`);
  } catch (e) {
    fail('reviewer-save: PUT', e.message);
  }

  // 2-2. 저장 후 레코드 재조회 → 내용 반영 확인
  try {
    const { status, data } = await req('GET', `/records/share/${shareToken}`);
    assert('reviewer-save: 저장 후 재조회 → 200', status === 200, `status=${status}`);
    if (status === 200 && data) {
      // service_description이 업데이트되었는지 확인
      assert('reviewer-save: service_description 업데이트 반영',
        data.service_description === updatedDesc,
        `expected="${updatedDesc}" got="${data.service_description}"`);
      assert('reviewer-save: agent_opinion 업데이트 반영',
        data.agent_opinion === updatedOpinion,
        `expected="${updatedOpinion}" got="${data.agent_opinion}"`);
    }
  } catch (e) {
    fail('reviewer-save: 저장 후 재조회', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [3] 편집 히스토리 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testEditHistory(shareToken) {
  console.log('\n[3] 편집 히스토리 (record_edit_history)');

  // 3-1. 히스토리 조회 엔드포인트 (인증 필요)
  try {
    const { status, data } = await req('GET', `/records/history/${shareToken}`, { auth: true });
    assert('history: 조회 → 200/401/404', [200, 401, 404].includes(status), `status=${status}`);
    if (status === 200) {
      assert('history: 배열 반환', Array.isArray(data), `type=${typeof data}`);
      if (Array.isArray(data) && data.length > 0) {
        const first = data[0];
        assert('history: action 필드 존재', 'action' in first, `keys=${Object.keys(first).join(',')}`);
        assert('history: created_at 필드 존재', 'created_at' in first, `keys=${Object.keys(first).join(',')}`);
        // before/snapshot 필드가 있으면 검증 (마이그레이션 완료 확인)
        if ('service_description_before' in first) {
          assert('history: before 필드가 문자열', typeof first.service_description_before === 'string' || first.service_description_before === null, `type=${typeof first.service_description_before}`);
        }
      }
    }
  } catch (e) {
    fail('history: 편집 히스토리 조회', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [4] 공유 링크 만료 설정 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testShareExpiry(shareToken) {
  if (!TEST_TOKEN) { log('\n[4] Share Expiry — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[4] 공유 링크 만료 설정');

  // 4-1. 만료 기간 설정 (7일)
  try {
    const { status, data } = await req('PATCH', `/records/${shareToken}/share-expiry`, {
      auth: true,
      body: { expires_days: 7 },
    });
    assert('expiry: 만료 기간 설정 → 200', status === 200, `status=${status} err=${JSON.stringify(data)}`);
  } catch (e) {
    fail('expiry: 만료 기간 설정', e.message);
  }

  // 4-2. 만료 설정 후 레코드 조회 — share_expires_at 필드 확인
  try {
    const { status, data } = await req('GET', `/records/share/${shareToken}`);
    if (status === 200 && data && 'share_expires_at' in data) {
      assert('expiry: share_expires_at 필드 반환', data.share_expires_at !== undefined, `val=${data.share_expires_at}`);
    } else {
      log('  ℹ️  INFO: share_expires_at 필드가 공개 응답에 미포함 (정상 — 만료 확인은 서버 내부에서)');
    }
  } catch (e) {
    fail('expiry: 만료 후 레코드 조회', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [5] Admin 대시보드 통합 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testAdminDashboard() {
  console.log('\n[5] Admin 대시보드 통합 테스트');

  // 5-1. Admin HTML 페이지 접근 가능 여부
  try {
    const res = await fetch(`${BASE_URL}/admin`);
    assert('admin-web: /admin HTML → 200', res.status === 200, `status=${res.status}`);
    const html = await res.text();
    assert('admin-web: HTML 응답', html.includes('<!DOCTYPE html>') || html.includes('<html'), 'not HTML');
  } catch (e) {
    fail('admin-web: /admin 페이지 접근', e.message);
  }

  // 5-2. KPI API — 인증 없이 → 401
  try {
    const { status } = await req('GET', '/admin/kpi', { headers: { 'X-Admin-Secret': '' } });
    assert('admin-kpi: 시크릿 없음 → 401', status === 401, `status=${status}`);
  } catch (e) {
    fail('admin-kpi: 인증 없이 접근', e.message);
  }

  // 5-3. KPI API — 올바른 시크릿 → 응답 스키마 검증
  if (ADMIN_SECRET) {
    try {
      const { status, data } = await req('GET', '/admin/kpi', {
        headers: { 'X-Admin-Secret': ADMIN_SECRET },
      });
      assert('admin-kpi: 올바른 시크릿 → 200', status === 200, `status=${status}`);
      if (status === 200 && typeof data === 'object') {
        // KPI 응답 스키마
        assert('admin-kpi: snapshot_at 존재', typeof data.snapshot_at === 'string', `keys=${Object.keys(data).join(',')}`);
        assert('admin-kpi: users.total >= 0', typeof data.users?.total === 'number' && data.users.total >= 0, `users.total=${data.users?.total}`);
        assert('admin-kpi: records.total >= 0', typeof data.records?.total === 'number' && data.records.total >= 0, `records.total=${data.records?.total}`);
        assert('admin-kpi: cases.total >= 0', typeof data.cases?.total === 'number' && data.cases.total >= 0, `cases.total=${data.cases?.total}`);
        assert('admin-kpi: monthly_records 배열', Array.isArray(data.monthly_records), `type=${typeof data.monthly_records}`);
        assert('admin-kpi: user_list 배열', Array.isArray(data.user_list), `type=${typeof data.user_list}`);

        // KPI 숫자 일관성 체크
        const { synced, reviewed, injected } = data.records;
        const totalCheck = (synced + reviewed + injected) <= data.records.total + 1; // 허용 오차 1
        assert('admin-kpi: synced+reviewed+injected <= total', totalCheck,
          `synced=${synced} reviewed=${reviewed} injected=${injected} total=${data.records.total}`);

        // injection_rate 퍼센트 형식 확인
        assert('admin-kpi: injection_rate 퍼센트 형식', /^\d+\.\d+%$/.test(data.records.injection_rate),
          `injection_rate=${data.records.injection_rate}`);
      }
    } catch (e) {
      fail('admin-kpi: KPI 응답 검증', e.message);
    }
  } else {
    log('  ⏭️  SKIP: DASH_ADMIN_SECRET 미설정');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [6] 공유 레코드 → 내 DB 저장 (save-to-my-db) 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testSaveToMyDb(shareToken) {
  if (!TEST_TOKEN) { log('\n[6] Save-to-My-DB — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[6] Save-to-My-DB 통합 테스트');

  // 6-1. 자기 자신이 작성한 DB를 저장 시도 → 400 (own_record)
  //      (테스트 레코드는 reviewer_test@test.com 소유 → 동일 계정이면 거부)
  //      실제 다른 계정 토큰이 없으므로 에러 코드 패턴만 확인
  try {
    const { status, data } = await req('POST', `/records/save-to-my-db/${shareToken}`, {
      auth: true,
      body: {},
    });
    // 가능한 응답: 400(own_record), 403(not_registered), 200(성공)
    assert('save-to-my-db: 응답 상태 정상 (400/403/200)', [200, 400, 403].includes(status),
      `status=${status} data=${JSON.stringify(data)}`);
    if (status === 400) {
      assert('save-to-my-db: own_record 오류 코드', data?.error === 'own_record',
        `error=${data?.error}`);
    }
  } catch (e) {
    fail('save-to-my-db: 저장 시도', e.message);
  }

  // 6-2. 존재하지 않는 토큰으로 저장 시도 → 404
  try {
    const { status, data } = await req('POST', '/records/save-to-my-db/nonexistent_xyz_test', {
      auth: true,
      body: {},
    });
    assert('save-to-my-db: 존재하지 않는 토큰 → 404', status === 404, `status=${status}`);
  } catch (e) {
    fail('save-to-my-db: 존재하지 않는 토큰 404', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [7] 정적 파일 및 Web Assets 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testStaticAssets() {
  console.log('\n[7] 정적 파일 / Web Assets 테스트');

  const assets = [
    { path: '/', label: '리뷰어 메인 페이지', required: true },
    { path: '/public/og_image.png', label: 'OG 이미지 (소셜 공유용)', required: true },
    { path: '/.well-known/assetlinks.json', label: 'Android App Links 검증', required: false },
    { path: '/.well-known/apple-app-site-association', label: 'iOS Universal Links 검증', required: false },
  ];

  for (const asset of assets) {
    try {
      const res = await fetch(`${BASE_URL}${asset.path}`);
      if (asset.required) {
        assert(`assets: ${asset.label} → 200`, res.status === 200, `status=${res.status} path=${asset.path}`);
      } else {
        // 선택적 파일: 없으면 경고로 기록
        if (res.status === 200) {
          ok(`assets: ${asset.label} → 200`);
        } else {
          fail(`assets: ${asset.label} → 배포 누락 (status=${res.status})`, `⚠️  딥링크 검증 파일 미배포 — ${asset.path}`);
        }
      }

      // apple-app-site-association Content-Type 검증 (iOS 필수)
      if (asset.path.includes('apple-app-site-association') && res.status === 200) {
        const ct = res.headers.get('content-type') || '';
        assert('assets: apple-app-site-association Content-Type=application/json',
          ct.includes('application/json'),
          `content-type=${ct} — iOS Universal Links 인증 실패 가능`);
      }
    } catch (e) {
      fail(`assets: ${asset.label}`, e.message);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 메인 실행
// ─────────────────────────────────────────────────────────────────────────────
async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('  DASH Reviewer Web E2E 테스트');
  console.log(`  대상: ${BASE_URL}`);
  console.log(`  인증: ${TEST_TOKEN ? '있음' : '없음'}`);
  console.log('═══════════════════════════════════════════════════════════');

  // 테스트 레코드 생성 (로컬 서버 전용, 프로덕션은 PRESET 토큰 사용)
  let shareToken = PRESET_SHARE_TOKEN;
  let encBlob = null;
  let testCaseId = null;

  if (!shareToken && TEST_TOKEN) {
    log('\n[setup] 테스트 레코드 생성 중...');
    try {
      const result = await createTestRecord();
      if (result.status === 200) {
        shareToken = result.shareToken;
        encBlob = result.encBlob;
        testCaseId = result.caseId;
        log(`  ✔ 생성 완료 — share_token: ${shareToken}`);
      } else {
        log(`  ⚠️  테스트 레코드 생성 실패 (status=${result.status}) — 공유 링크 테스트 제한`);
      }
    } catch (e) {
      log(`  ⚠️  테스트 레코드 생성 오류: ${e.message}`);
    }
  } else if (shareToken) {
    log(`\n[setup] 환경변수 share_token 사용: ${shareToken}`);
  } else {
    log('\n[setup] 토큰 없음 — 공개 엔드포인트만 테스트');
  }

  await testReviewerFetch(shareToken || 'nonexistent_for_test');
  await testReviewerSave(shareToken);
  await testEditHistory(shareToken || 'nonexistent_for_test');
  await testShareExpiry(shareToken);
  await testAdminDashboard();
  await testSaveToMyDb(shareToken);
  await testStaticAssets();

  // 테스트 데이터 정리
  if (testCaseId && TEST_TOKEN) {
    try {
      await req('DELETE', `/cases/${testCaseId}`, { auth: true });
      log('\n[cleanup] 테스트 사례 삭제 완료');
    } catch (e) {
      log(`\n[cleanup] 사례 삭제 실패 (무시): ${e.message}`);
    }
  }

  // 결과 요약
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
  console.error('\n💥 테스트 실행 중 예외:', err);
  process.exit(1);
});
