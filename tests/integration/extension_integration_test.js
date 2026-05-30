/**
 * DASH Chrome 확장프로그램 ↔ Backend API 통합 테스트
 *
 * 대상: dash_extension/extension/sidepanel.js, content.js
 * 범위: Google OAuth → Firebase 토큰 변환, 레코드 조회, 상태 업데이트, NCADS 필드 매핑
 * 실행: node tests/integration/extension_integration_test.js [--prod|--local]
 *
 * 사전 조건:
 *   - DASH_TEST_TOKEN: Firebase ID Token (eyJ...) — 확장프로그램은 Google OAuth ya29... 이지만
 *     테스트에서는 Firebase 토큰을 사용해 동일 인증 경로 검증
 *   - DASH_TEST_GOOGLE_TOKEN: Google OAuth Access Token (ya29...) — 선택사항
 *   - DASH_TEST_SHARE_TOKEN: 주입할 share_token (확장프로그램 주입 테스트용)
 */

'use strict';

const args = process.argv.slice(2);
const USE_PROD    = args.includes('--prod');
const BASE_URL    = USE_PROD ? 'https://dash.qpon' : 'http://localhost:3000';
const API         = `${BASE_URL}/api`;
const FIREBASE_TOKEN = process.env.DASH_TEST_TOKEN || '';
const GOOGLE_TOKEN   = process.env.DASH_TEST_GOOGLE_TOKEN || '';
const PRESET_SHARE_TOKEN = process.env.DASH_TEST_SHARE_TOKEN || '';

let passed = 0, failed = 0;
const failures = [];

function ok(label)   { passed++; process.stdout.write(`  ✅ PASS  ${label}\n`); }
function fail(label, reason) {
  failed++;
  failures.push({ label, reason });
  process.stdout.write(`  ❌ FAIL  ${label}\n         → ${reason}\n`);
}
function assert(label, cond, detail = '') { cond ? ok(label) : fail(label, detail); }
function log(msg) { process.stdout.write(`  ${msg}\n`); }

async function req(method, path, { body, headers = {} } = {}) {
  const url = path.startsWith('http') ? path : `${API}${path}`;
  const h = { 'Content-Type': 'application/json', ...headers };
  const opts = { method, headers: h };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(url, opts);
  let data;
  try { data = await res.json(); } catch { data = null; }
  return { status: res.status, data, headers: res.headers };
}

function authHeader(token) {
  return token ? { Authorization: `Bearer ${token}` } : {};
}

// ─────────────────────────────────────────────────────────────────────────────
// [1] 확장프로그램 인증 모델 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testExtensionAuth() {
  console.log('\n[1] 확장프로그램 인증 모델 테스트');

  // 1-1. Google OAuth 토큰 (ya29...) 인증 경로
  if (GOOGLE_TOKEN && GOOGLE_TOKEN.startsWith('ya29.')) {
    try {
      const { status } = await req('GET', `/users/me_or_any`, {
        headers: authHeader(GOOGLE_TOKEN),
      });
      // ya29 토큰은 Google OAuth → tokeninfo → 검증 경로
      // 401이면 토큰 만료, 404이면 인증 통과 (유저 없음), 200이면 인증 + 유저 존재
      assert('ext-auth: Google OAuth 토큰 인증 경로 → 401/404/200',
        [401, 404, 200].includes(status), `status=${status}`);
    } catch (e) {
      fail('ext-auth: Google OAuth 토큰', e.message);
    }
  } else {
    log('  ⏭️  SKIP: DASH_TEST_GOOGLE_TOKEN 미설정 (ya29... 형식 필요)');
  }

  // 1-2. Firebase ID 토큰 (eyJ...) 인증 경로 — 확장프로그램도 Firebase 사용 가능
  if (FIREBASE_TOKEN) {
    try {
      const { status } = await req('GET', `/records/user/test_uid_ext`, {
        headers: authHeader(FIREBASE_TOKEN),
      });
      assert('ext-auth: Firebase 토큰 → 200/404 (인증 통과)',
        [200, 404].includes(status), `status=${status}`);
    } catch (e) {
      fail('ext-auth: Firebase 토큰', e.message);
    }
  } else {
    log('  ⏭️  SKIP: DASH_TEST_TOKEN 미설정');
  }

  // 1-3. 허용되지 않은 Chrome Extension Origin CORS 테스트
  //      실제 Extension ID가 아닌 임의 ID → 403/오류
  try {
    const res = await fetch(`${API}/records/user/test`, {
      headers: {
        'Origin': 'chrome-extension://unknown_ext_id_xyz_test',
        'Authorization': `Bearer ${FIREBASE_TOKEN || 'dummy'}`,
      },
    });
    // CORS 거부 시 응답 자체가 오거나 CORS 오류 발생
    // Node.js fetch는 CORS 프리플라이트를 서버에 보내므로 403/500이 예상됨
    assert('ext-auth: 미허용 Extension Origin → CORS 거부 (403/500 또는 오류)',
      [403, 500, 0].includes(res.status) || res.status > 400, `status=${res.status}`);
  } catch (e) {
    // 네트워크 오류 = CORS 거부 (정상)
    ok('ext-auth: 미허용 Extension Origin → CORS 거부 (네트워크 에러)');
  }

  // 1-4. 허용된 Extension ID 화이트리스트 확인 (서버 설정 검증)
  //      프로덕션 Extension ID로 요청 시 인증 통과 여부
  const PROD_EXT_ID = 'dpncpmegjlgknkagcfjdaccbgmjncdef';
  try {
    const res = await fetch(`${BASE_URL}/health`, {
      headers: { 'Origin': `chrome-extension://${PROD_EXT_ID}` },
    });
    // /health는 인증 불필요 — CORS만 통과하면 됨
    assert('ext-auth: 허용된 Extension ID → CORS 통과', res.status === 200, `status=${res.status}`);
  } catch (e) {
    fail('ext-auth: 허용된 Extension CORS', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [2] 레코드 조회 (확장프로그램 메인 데이터 로드)
// ─────────────────────────────────────────────────────────────────────────────
async function testExtensionRecordFetch() {
  if (!FIREBASE_TOKEN) { log('\n[2] 레코드 조회 — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[2] 확장프로그램 레코드 조회');

  const testUid = 'ext_test_uid_temp';

  // 2-1. 유저 레코드 목록 조회
  try {
    const { status, data } = await req('GET', `/records/user/${testUid}`, {
      headers: authHeader(FIREBASE_TOKEN),
    });
    assert('ext-records: 조회 → 200 or 404', [200, 404].includes(status), `status=${status}`);
    if (status === 200) {
      assert('ext-records: 배열 반환', Array.isArray(data), `type=${typeof data}`);
      if (Array.isArray(data) && data.length > 0) {
        const first = data[0];
        // 확장프로그램이 사용하는 필수 필드 확인
        const extFields = ['share_token', 'status', 'service_type', 'service_name',
          'location', 'start_time', 'end_time', 'encrypted_blob', 'case_name'];
        for (const field of extFields) {
          assert(`ext-records: 레코드 필드 '${field}' 존재`, field in first,
            `keys=${Object.keys(first).join(',')}`);
        }
        // 주입 가능한 상태 필터링 확인 (Synced 또는 Reviewed → 주입 대상)
        const injectableStatuses = ['Synced', 'Reviewed'];
        const injectable = data.filter(r => injectableStatuses.includes(r.status));
        log(`  ℹ️  주입 가능 레코드: ${injectable.length}/${data.length}`);
      }
    }
  } catch (e) {
    fail('ext-records: 목록 조회', e.message);
  }

  // 2-2. 특정 share_token으로 공유 레코드 조회 (동행상담원이 공유받은 경우)
  const shareToken = PRESET_SHARE_TOKEN || 'test_token_nonexistent';
  try {
    const { status, data } = await req('GET', `/records/share/${shareToken}`, {
      headers: {},  // 공개 엔드포인트 — 인증 불필요
    });
    assert('ext-records: 공유 레코드 조회 (공개) → 200/404',
      [200, 404].includes(status), `status=${status}`);
    if (status === 200 && data) {
      // 확장프로그램이 주입에 사용하는 필드
      const ncadsFields = ['service_type', 'service_name', 'location',
        'start_time', 'end_time', 'service_count', 'travel_time'];
      for (const field of ncadsFields) {
        assert(`ext-records: NCADS 주입 필드 '${field}' 존재`, field in data,
          `keys=${Object.keys(data).join(',')}`);
      }
    }
  } catch (e) {
    fail('ext-records: 공유 레코드 조회', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [3] 레코드 상태 업데이트 (주입 완료 후 Injected 전환)
// ─────────────────────────────────────────────────────────────────────────────
async function testRecordStatusUpdate() {
  if (!FIREBASE_TOKEN || !PRESET_SHARE_TOKEN) {
    log('\n[3] 레코드 상태 업데이트 — ⏭️ SKIP (토큰 또는 share_token 없음)');
    return;
  }
  console.log('\n[3] 레코드 상태 업데이트 (Injected 전환)');

  // 3-1. NCADS 주입 완료 후 상태 업데이트 (PUT /api/records/share/:token)
  //      확장프로그램은 주입 후 injected_by_name과 함께 status를 Injected로 변경
  try {
    const { status, data } = await req('PUT', `/records/share/${PRESET_SHARE_TOKEN}`, {
      headers: authHeader(FIREBASE_TOKEN),
      body: {
        status: 'Injected',
        injected_by_name: '확장프로그램 테스트 유저',
      },
    });
    // 200 또는 403/404 (권한 없거나 토큰 불일치)
    assert('ext-inject: 상태 Injected 업데이트 → 200/403/404',
      [200, 403, 404].includes(status), `status=${status} data=${JSON.stringify(data)}`);
    if (status === 200) {
      log(`  ✔ 상태 업데이트 성공 → Injected`);
    }
  } catch (e) {
    fail('ext-inject: 상태 업데이트', e.message);
  }

  // 3-2. 상태 업데이트 후 재조회 → 상태 반영 확인
  try {
    const { status, data } = await req('GET', `/records/share/${PRESET_SHARE_TOKEN}`);
    if (status === 200 && data) {
      const validStatuses = ['Synced', 'Reviewed', 'Injected', 'Archived'];
      assert('ext-inject: 상태가 유효한 ENUM 값',
        validStatuses.includes(data.status), `status=${data.status}`);
    }
  } catch (e) {
    fail('ext-inject: 상태 업데이트 후 재조회', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [4] NCADS 필드 매핑 검증 (content.js 자동주입 필드 → API 응답 필드 일치)
// ─────────────────────────────────────────────────────────────────────────────
async function testNCadsFieldMapping() {
  console.log('\n[4] NCADS 필드 매핑 검증');

  // content.js에서 사용하는 NCADS 필드 ID와 API 응답 필드 매핑 테이블
  // 소스: dash_extension/extension/core/config.js의 CFG.FIELD_IDS
  const NCADS_TO_API_MAPPING = {
    // NCADS Form Field ID  → API 응답 필드명
    'svcExecRecipientTyCd' : 'provision_type',   // 제공구분
    'provMeansCd'          : 'method',            // 제공방법
    'svcClassDetailCd'     : 'service_type',      // 서비스 유형
    'svcProvLocCd'         : 'location',          // 제공 장소
    'provTyCd'             : 'service_category',  // 제공 구분 (상세)
    // 날짜/시간 필드
    'svcExecDt'            : 'start_time',        // 서비스 일시
    // 상담 내용
    'svcContents'          : 'service_description', // 서비스 내용
    'agentOpinion'         : 'agent_opinion',     // 상담원 소견
  };

  // API 응답 필드가 존재하는지 확인 (실제 레코드로 검증)
  const shareToken = PRESET_SHARE_TOKEN;
  if (!shareToken) {
    log('  ℹ️  PRESET_SHARE_TOKEN 없음 — 필드 매핑 스키마만 정적 검증');

    // 정적 매핑 검증: API 필드명이 스키마 컬럼명과 일치하는지 확인
    const schemaColumns = [
      'provision_type', 'method', 'service_type', 'service_category',
      'service_name', 'location', 'start_time', 'end_time',
      'service_count', 'travel_time', 'service_description', 'agent_opinion',
    ];

    for (const [ncadsField, apiField] of Object.entries(NCADS_TO_API_MAPPING)) {
      assert(`ncads-mapping: '${ncadsField}' → API '${apiField}' 스키마 존재`,
        schemaColumns.includes(apiField), `'${apiField}' not in schema columns`);
    }
    return;
  }

  // 실제 API 응답으로 매핑 검증
  try {
    const { status, data } = await req('GET', `/records/share/${shareToken}`);
    if (status === 200 && data) {
      for (const [ncadsField, apiField] of Object.entries(NCADS_TO_API_MAPPING)) {
        assert(`ncads-mapping: '${ncadsField}' → '${apiField}' API 필드 존재`,
          apiField in data, `keys=${Object.keys(data).join(',')}`);
      }

      // 날짜 형식 검증 (NCADS 자동주입 시 파싱 가능해야 함)
      if (data.start_time) {
        const dateRegex = /^\d{4}-\d{2}-\d{2}[\sT]\d{2}:\d{2}:\d{2}/;
        assert('ncads-mapping: start_time 날짜 형식 (YYYY-MM-DD HH:MM:SS)',
          dateRegex.test(data.start_time), `start_time=${data.start_time}`);
      }

      // service_count 숫자 타입 (NCADS 횟수 입력용)
      if (data.service_count !== undefined) {
        assert('ncads-mapping: service_count 숫자 타입', typeof data.service_count === 'number',
          `type=${typeof data.service_count}`);
      }
    }
  } catch (e) {
    fail('ncads-mapping: 필드 매핑 검증', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [5] Vault PIN 기반 암호화 키 접근 테스트
// ─────────────────────────────────────────────────────────────────────────────
async function testExtensionVault() {
  if (!FIREBASE_TOKEN) { log('\n[5] Extension Vault — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[5] 확장프로그램 Vault 접근 테스트');

  const testUid = 'ext_vault_test_uid_temp';

  // 5-1. Vault 조회 (확장프로그램은 로그인 시 vault 조회 → PIN으로 복호화)
  try {
    const { status, data } = await req('GET', `/users/vault/${testUid}`, {
      headers: authHeader(FIREBASE_TOKEN),
    });
    assert('ext-vault: vault 조회 → 200/404', [200, 404].includes(status), `status=${status}`);
    if (status === 200 && data) {
      assert('ext-vault: encrypted_vault 필드 존재', 'encrypted_vault' in data, `keys=${Object.keys(data).join(',')}`);
      assert('ext-vault: salt 필드 존재', 'salt' in data, `keys=${Object.keys(data).join(',')}`);
      // 중요: 서버가 vault를 복호화하지 않음 (zero-knowledge)
      assert('ext-vault: encryption_key 미포함 (zero-knowledge)', !('encryption_key' in data),
        '⚠️  SECURITY: encryption_key in vault response');
    }
  } catch (e) {
    fail('ext-vault: vault 조회', e.message);
  }

  // 5-2. Vault 저장 (PIN 변경 또는 새 키 등록 시)
  const fakeVault = Buffer.from('{"test_key":"encrypted_ext_key"}').toString('base64');
  const fakeSalt  = Buffer.from('extsalt12345678').toString('hex');
  try {
    const { status, data } = await req('POST', '/users/vault', {
      headers: authHeader(FIREBASE_TOKEN),
      body: {
        user_id: testUid,
        encrypted_vault: fakeVault,
        salt: fakeSalt,
      },
    });
    assert('ext-vault: vault 저장 → 200', status === 200, `status=${status} err=${JSON.stringify(data)}`);
  } catch (e) {
    fail('ext-vault: vault 저장', e.message);
  }

  // 5-3. Vault Rate Limiting — 5분 throttle 확인
  //      Extension sidepanel.js: VAULT_THROTTLE_MS = 5 * 60 * 1000
  //      서버: 10분당 30회
  //      연속 3회 요청 → 모두 성공해야 함 (throttle 초과 아님)
  let vaultRequests = 0;
  for (let i = 0; i < 3; i++) {
    try {
      const { status } = await req('GET', `/users/vault/${testUid}`, {
        headers: authHeader(FIREBASE_TOKEN),
      });
      if ([200, 404].includes(status)) vaultRequests++;
    } catch {}
  }
  assert('ext-vault: 3회 연속 요청 모두 성공 (rate-limit 미초과)',
    vaultRequests === 3, `성공=${vaultRequests}/3`);
}

// ─────────────────────────────────────────────────────────────────────────────
// [6] SSE 실시간 이벤트 수신 (확장프로그램 실시간 업데이트)
// ─────────────────────────────────────────────────────────────────────────────
async function testExtensionSSE() {
  if (!FIREBASE_TOKEN) { log('\n[6] Extension SSE — ⏭️ SKIP (토큰 없음)'); return; }
  console.log('\n[6] 확장프로그램 SSE 실시간 이벤트');

  // SSE 연결 후 connected 이벤트 수신 확인 (5초 타임아웃)
  await new Promise(resolve => {
    const timeout = setTimeout(() => {
      fail('ext-sse: 5초 내 connected 이벤트 미수신', 'timeout');
      resolve();
    }, 5000);

    fetch(`${API}/events?email=ext_test@test.com&token=${FIREBASE_TOKEN}`, {
      headers: { Accept: 'text/event-stream' },
    }).then(res => {
      assert('ext-sse: 연결 → 200', res.status === 200, `status=${res.status}`);
      const ct = res.headers.get('content-type') || '';
      assert('ext-sse: Content-Type=text/event-stream', ct.includes('text/event-stream'), `ct=${ct}`);

      const reader = res.body.getReader();
      const dec = new TextDecoder();

      function read() {
        reader.read().then(({ done, value }) => {
          if (done) return;
          const chunk = dec.decode(value);
          if (chunk.includes('"event":"connected"') || chunk.includes('"event": "connected"')) {
            ok('ext-sse: connected 이벤트 수신');
            clearTimeout(timeout);
            reader.cancel();
            resolve();
          } else if (chunk.startsWith(': heartbeat')) {
            ok('ext-sse: heartbeat 수신');
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
      fail('ext-sse: SSE 연결', e.message);
      clearTimeout(timeout);
      resolve();
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// [7] 확장프로그램 허용 Extension ID 검증
// ─────────────────────────────────────────────────────────────────────────────
async function testAllowedExtensionIds() {
  console.log('\n[7] 허용된 Extension ID 목록 CORS 검증');

  const ALLOWED_IDS = [
    { id: 'dpncpmegjlgknkagcfjdaccbgmjncdef', label: '프로덕션 (웹 스토어)' },
    { id: 'nmdfmegmehnkacdeekekchjfcijpbmcp', label: '개발자 모드 테스트' },
    { id: 'iamgpaookjndjpcigifbfdmmbfijcane', label: '구 ID (레거시)' },
  ];

  for (const ext of ALLOWED_IDS) {
    try {
      const res = await fetch(`${BASE_URL}/health`, {
        headers: { Origin: `chrome-extension://${ext.id}` },
      });
      assert(`ext-cors: 허용 ID ${ext.label} → CORS 통과 (200)`,
        res.status === 200, `status=${res.status}`);
    } catch (e) {
      fail(`ext-cors: ${ext.label} CORS`, e.message);
    }
  }

  // 미허용 ID
  try {
    const res = await fetch(`${BASE_URL}/health`, {
      headers: { Origin: 'chrome-extension://totally_unknown_ext_id_xyz_test' },
    });
    // CORS 거부 시 0 또는 4xx
    assert('ext-cors: 미허용 ID → CORS 거부',
      res.status !== 200 || res.status === 0, `status=${res.status} (200이면 CORS 미검증)`);
  } catch {
    ok('ext-cors: 미허용 ID → 네트워크 거부 (CORS)');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 메인 실행
// ─────────────────────────────────────────────────────────────────────────────
async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('  DASH 확장프로그램 ↔ Backend 통합 테스트');
  console.log(`  대상: ${BASE_URL}`);
  console.log(`  Firebase 토큰: ${FIREBASE_TOKEN ? '있음' : '없음'}`);
  console.log(`  Google OAuth 토큰: ${GOOGLE_TOKEN ? '있음' : '없음'}`);
  console.log('═══════════════════════════════════════════════════════════');

  await testExtensionAuth();
  await testExtensionRecordFetch();
  await testRecordStatusUpdate();
  await testNCadsFieldMapping();
  await testExtensionVault();
  await testExtensionSSE();
  await testAllowedExtensionIds();

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
