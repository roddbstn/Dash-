// ================================================================
// DASH 성능 / 부하 테스트
// 항목: 페이지 로드, E2EE 복호화, API 응답시간, 동시 접속, SSE 재연결
//
// 실행: npx playwright test --project=perf
// 로컬 서버(reviewer-web)는 playwright.config.ts webServer가 자동 기동
// API 성능은 BASE_URL=https://dash.qpon 환경변수로 실서버 지정 가능
// ================================================================

import { test, expect, request } from '@playwright/test';
import {
  ENV,
  FIXTURE_ENC_KEY,
  FIXTURE_SHARE_TOKEN,
  MOCK_SHARE_RESPONSE,
  encryptBlob,
  buildShareUrl,
} from '../fixtures/test-data';

// ── 공통 mock 등록 헬퍼 ──────────────────────────────────────
async function mockShareApi(page: import('@playwright/test').Page) {
  await page.route(`**/api/records/share/${FIXTURE_SHARE_TOKEN}`, route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(MOCK_SHARE_RESPONSE),
    })
  );
}

// ── 허용 임계값 ──────────────────────────────────────────────
const THRESHOLDS = {
  PAGE_LOAD_MS: 3000,       // 초기 페이지 로드
  DECRYPT_MS: 200,          // 클라이언트 E2EE 복호화
  RENDER_MS: 2000,          // #db-content 렌더링 완료
  API_LOCAL_MS: 300,        // 로컬 /api 응답
  CONCURRENT_USERS: 5,      // 동시 탭 수
  LARGE_DATASET_COUNT: 30,  // 대용량 레코드 렌더링 테스트 수
  LARGE_RENDER_MS: 2500,    // 대용량 렌더링 허용 시간
};

// ──────────────────────────────────────────────────────────────
// 1. 페이지 로드 성능
// ──────────────────────────────────────────────────────────────
test.describe('페이지 로드 성능', () => {
  test('PERF-001: 공유 링크 초기 로드 — DOMContentLoaded < 3s', async ({ page }) => {
    await mockShareApi(page);

    const t0 = Date.now();
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await page.waitForLoadState('domcontentloaded');
    const elapsed = Date.now() - t0;

    expect(elapsed).toBeLessThan(THRESHOLDS.PAGE_LOAD_MS);
    console.log(`[PERF-001] DOMContentLoaded: ${elapsed}ms`);
  });

  test('PERF-002: #db-content 렌더링 완료 시간 < 2s', async ({ page }) => {
    await mockShareApi(page);
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));

    const t0 = Date.now();
    await page.waitForSelector('#db-content', { state: 'visible', timeout: 5000 });
    const elapsed = Date.now() - t0;

    expect(elapsed).toBeLessThan(THRESHOLDS.RENDER_MS);
    console.log(`[PERF-002] #db-content 렌더 완료: ${elapsed}ms`);
  });

  test('PERF-003: Navigation Timing — TTFB + 로드 시간 측정', async ({ page }) => {
    await mockShareApi(page);
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await page.waitForLoadState('load');

    const metrics = await page.evaluate(() => {
      const nav = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming;
      return {
        ttfb: Math.round(nav.responseStart - nav.requestStart),
        domInteractive: Math.round(nav.domInteractive),
        loadComplete: Math.round(nav.loadEventEnd),
      };
    });

    console.log(`[PERF-003] TTFB: ${metrics.ttfb}ms | domInteractive: ${metrics.domInteractive}ms | loadComplete: ${metrics.loadComplete}ms`);
    expect(metrics.loadComplete).toBeLessThan(THRESHOLDS.PAGE_LOAD_MS);
  });
});

// ──────────────────────────────────────────────────────────────
// 2. E2EE 복호화 성능
// ──────────────────────────────────────────────────────────────
test.describe('E2EE 복호화 성능', () => {
  test('PERF-004: 단일 레코드 복호화 < 200ms', async ({ page }) => {
    await mockShareApi(page);
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));

    const decryptTime = await page.evaluate(() => {
      // app.js의 decryptBlob 함수가 window에 노출되지 않으므로 타이밍은 렌더 완료 기준
      const start = performance.now();
      return new Promise<number>(resolve => {
        const observer = new MutationObserver(() => {
          const el = document.getElementById('db-content');
          if (el && el.textContent && el.textContent.trim().length > 0) {
            observer.disconnect();
            resolve(Math.round(performance.now() - start));
          }
        });
        observer.observe(document.body, { childList: true, subtree: true });
        setTimeout(() => { observer.disconnect(); resolve(5000); }, 5000);
      });
    });

    console.log(`[PERF-004] E2EE 복호화+렌더: ${decryptTime}ms`);
    expect(decryptTime).toBeLessThan(THRESHOLDS.DECRYPT_MS);
  });

  test('PERF-005: 잘못된 키 — 복호화 실패 감지 < 500ms', async ({ page }) => {
    await mockShareApi(page);
    const t0 = Date.now();
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, 'wrong-key-!!'));
    await page.waitForSelector('#db-content, .enc-notice, #state-error', {
      state: 'visible', timeout: 5000,
    });
    const elapsed = Date.now() - t0;

    console.log(`[PERF-005] 복호화 실패 감지: ${elapsed}ms`);
    expect(elapsed).toBeLessThan(500);
  });
});

// ──────────────────────────────────────────────────────────────
// 3. 대용량 데이터 렌더링
// ──────────────────────────────────────────────────────────────
test.describe('대용량 데이터 렌더링', () => {
  test(`PERF-006: 긴 서비스 내용(2000자) 렌더링 < 2.5s`, async ({ page }) => {
    const longText = 'A'.repeat(2000);
    const bigRecord = {
      ...MOCK_SHARE_RESPONSE,
      encrypted_blob: encryptBlob(
        {
          caseName: 'QA대용량테스트',
          serviceDescription: longText,
          agentOpinion: longText,
          target: ['피해아동'],
          provision_type: '기관',
          method: '방문',
          service_type: '상담',
          service_category: '직접서비스',
          service_name: '사례관리',
          location: '아동가정',
          startTime: '2026-05-29 10:00:00',
          endTime: '2026-05-29 11:00:00',
          serviceCount: 1,
          travelTime: 30,
        },
        FIXTURE_ENC_KEY
      ),
    };

    await page.route(`**/api/records/share/${FIXTURE_SHARE_TOKEN}`, route =>
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(bigRecord) })
    );

    const t0 = Date.now();
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await page.waitForSelector('#db-content', { state: 'visible', timeout: 6000 });
    const elapsed = Date.now() - t0;

    console.log(`[PERF-006] 2000자 렌더링: ${elapsed}ms`);
    expect(elapsed).toBeLessThan(THRESHOLDS.LARGE_RENDER_MS);
  });
});

// ──────────────────────────────────────────────────────────────
// 4. 동시 접속 (탭 병렬 오픈)
// ──────────────────────────────────────────────────────────────
test.describe('동시 접속 성능', () => {
  test(`PERF-007: ${THRESHOLDS.CONCURRENT_USERS}개 탭 동시 로드 — 모두 3s 내 완료`, async ({ browser }) => {
    const context = await browser.newContext({ locale: 'ko-KR' });

    const pages = await Promise.all(
      Array.from({ length: THRESHOLDS.CONCURRENT_USERS }, () => context.newPage())
    );

    // 각 탭에 API mock 등록
    for (const p of pages) {
      await p.route(`**/api/records/share/${FIXTURE_SHARE_TOKEN}`, route =>
        route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(MOCK_SHARE_RESPONSE) })
      );
    }

    const t0 = Date.now();
    await Promise.all(
      pages.map(p => p.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY)))
    );
    await Promise.all(
      pages.map(p => p.waitForSelector('#db-content', { state: 'visible', timeout: 6000 }))
    );
    const totalElapsed = Date.now() - t0;

    console.log(`[PERF-007] ${THRESHOLDS.CONCURRENT_USERS}탭 동시 로드: ${totalElapsed}ms`);
    expect(totalElapsed).toBeLessThan(THRESHOLDS.PAGE_LOAD_MS + 1000); // 동시 부하 여유 +1s

    await Promise.all(pages.map(p => p.close()));
    await context.close();
  });

  test('PERF-008: 동일 링크 5회 연속 재로드 — 평균 로드 < 2s', async ({ page }) => {
    await page.route(`**/api/records/share/${FIXTURE_SHARE_TOKEN}`, route =>
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(MOCK_SHARE_RESPONSE) })
    );

    const times: number[] = [];
    for (let i = 0; i < 5; i++) {
      const t0 = Date.now();
      await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
      await page.waitForSelector('#db-content', { state: 'visible', timeout: 5000 });
      times.push(Date.now() - t0);
    }

    const avg = Math.round(times.reduce((a, b) => a + b, 0) / times.length);
    console.log(`[PERF-008] 5회 재로드 시간: ${times.map(t => `${t}ms`).join(', ')} | 평균: ${avg}ms`);
    expect(avg).toBeLessThan(2000);
  });
});

// ──────────────────────────────────────────────────────────────
// 5. 오류 상태 응답 속도
// ──────────────────────────────────────────────────────────────
test.describe('오류 상태 응답 속도', () => {
  test('PERF-009: 없는 토큰 → 오류 UI 표시 < 2s', async ({ page }) => {
    await page.route(`**/api/records/share/**`, route =>
      route.fulfill({ status: 404, contentType: 'application/json', body: JSON.stringify({ error: 'Not found' }) })
    );

    const t0 = Date.now();
    await page.goto(`${ENV.BASE_URL}/?token=nonexistent-token-000#key=any-key`);
    await page.waitForSelector('#state-error, .error-state, .error-view', {
      state: 'visible', timeout: 5000,
    });
    const elapsed = Date.now() - t0;

    console.log(`[PERF-009] 404 오류 UI 표시: ${elapsed}ms`);
    expect(elapsed).toBeLessThan(2000);
  });

  test('PERF-010: 네트워크 오류 → 오류 UI 표시 < 2s', async ({ page }) => {
    await page.route(`**/api/records/share/**`, route => route.abort('connectionreset'));

    const t0 = Date.now();
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await page.waitForSelector('#state-error, .error-state, .error-view', {
      state: 'visible', timeout: 5000,
    });
    const elapsed = Date.now() - t0;

    console.log(`[PERF-010] 네트워크 오류 UI 표시: ${elapsed}ms`);
    expect(elapsed).toBeLessThan(2000);
  });
});

// ──────────────────────────────────────────────────────────────
// 6. API 응답 시간 (로컬 서버 대상)
// ──────────────────────────────────────────────────────────────
test.describe('로컬 정적 서버 응답 시간', () => {
  test('PERF-011: 정적 서버 — index.html 응답 < 300ms', async ({ request: req }) => {
    const t0 = Date.now();
    const res = await req.get(`${ENV.BASE_URL}/`);
    const elapsed = Date.now() - t0;

    expect(res.status()).toBeLessThan(400);
    console.log(`[PERF-011] 정적 서버 index.html: ${elapsed}ms (HTTP ${res.status()})`);
    expect(elapsed).toBeLessThan(THRESHOLDS.API_LOCAL_MS);
  });

  test('PERF-012: 정적 서버 — 10회 연속 요청 평균 < 200ms', async ({ request: req }) => {
    const times: number[] = [];
    for (let i = 0; i < 10; i++) {
      const t0 = Date.now();
      await req.get(`${ENV.BASE_URL}/`);
      times.push(Date.now() - t0);
    }

    const avg = Math.round(times.reduce((a, b) => a + b, 0) / times.length);
    const max = Math.max(...times);
    console.log(`[PERF-012] 10회 평균: ${avg}ms | 최대: ${max}ms`);
    expect(avg).toBeLessThan(200);
  });
});
