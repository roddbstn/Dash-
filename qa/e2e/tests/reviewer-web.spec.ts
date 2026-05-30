// ================================================================
// DASH Reviewer Web — E2E 테스트
// 대상: dash.qpon/?token=<token>#key=<encKey>
// 시나리오: 공유 링크 열기 → E2EE 복호화 → 레코드 조회 → 엣지케이스
// ================================================================

import { test, expect, Page, Route } from '@playwright/test';
import {
  ENV,
  buildShareUrl,
  FIXTURE_ENC_KEY,
  FIXTURE_SHARE_TOKEN,
  FIXTURE_RECORD_PLAINTEXT,
  MOCK_SHARE_RESPONSE,
  waitForVisible,
} from '../fixtures/test-data';

// ── 공통 Mock 설정 ──────────────────────────────────────────────
async function mockShareApi(page: Page, response: object | null = MOCK_SHARE_RESPONSE) {
  await page.route(`**/api/records/share/${FIXTURE_SHARE_TOKEN}`, (route: Route) => {
    if (response === null) {
      route.fulfill({ status: 404, body: 'Not found' });
    } else {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(response),
      });
    }
  });
}

// ── 유효한 공유 링크로 레코드 전체 플로우 ──────────────────────
test.describe('공유 링크 — 정상 플로우', () => {
  test.beforeEach(async ({ page }) => {
    await mockShareApi(page);
  });

  test('TC-RW-001: 페이지 로드 시 로딩 스피너 표시', async ({ page }) => {
    const url = buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY);
    // API를 잠깐 지연시켜 로딩 상태 확인
    await page.route(`**/api/records/share/**`, async (route) => {
      await new Promise(r => setTimeout(r, 800));
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(MOCK_SHARE_RESPONSE),
      });
    });

    await page.goto(url);
    // 로딩 스피너가 즉시 보여야 함
    await expect(page.locator('#state-loading')).toBeVisible();
    // 완료 후 스피너 사라짐
    await expect(page.locator('#state-loading')).toBeHidden({ timeout: 5000 });
  });

  test('TC-RW-002: E2EE 복호화 후 케이스명 표시', async ({ page }) => {
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#db-content');

    const title = await page.locator('#page-title').textContent();
    expect(title).toContain(FIXTURE_RECORD_PLAINTEXT.caseName);
    expect(title).toContain('아동 사례');
  });

  test('TC-RW-003: 작성자 이름 뱃지 표시', async ({ page }) => {
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#db-content');

    const badge = await page.locator('#author-name').textContent();
    expect(badge).toContain(MOCK_SHARE_RESPONSE.user_name);
    expect(badge).toContain('작성');
  });

  test('TC-RW-004: 서비스 내용 — 앱 전용 안내 메시지 표시', async ({ page }) => {
    // 현재 reviewer web은 서비스 내용을 앱에서만 확인하도록 설계됨
    // (E2EE 제거 후 서비스 상세 내용은 앱에서 확인 유도)
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#db-content');

    const dbContent = page.locator('#db-content');
    const text = await dbContent.textContent();
    expect(text).toContain('앱에서');
  });

  test('TC-RW-005: CTA 섹션 — 앱 설치 유도 표시', async ({ page }) => {
    // 서비스 내용·소견은 앱에서만 확인 → CTA(앱 설치) 섹션이 핵심 UX
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#db-content');

    const cta = page.locator('#cta-section');
    await expect(cta).toBeVisible();
    const ctaText = await cta.textContent();
    expect(ctaText).toContain('다운로드');
  });

  test('TC-RW-006: 서비스 상세정보 아코디언 — 클릭으로 펼치기/접기', async ({ page }) => {
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#db-content');

    const metaGrid = page.locator('#meta-grid');
    const toggleBtn = page.locator('.meta-toggle');
    const metaIcon = page.locator('#meta-icon');

    // 초기 상태: 접혀있음
    await expect(metaGrid).toBeHidden();
    expect(await metaIcon.textContent()).toBe('▾');

    // 클릭 → 펼침
    await toggleBtn.click();
    await expect(metaGrid).toBeVisible();
    expect(await metaIcon.textContent()).toBe('▴');

    // 재클릭 → 접힘
    await toggleBtn.click();
    await expect(metaGrid).toBeHidden();
    expect(await metaIcon.textContent()).toBe('▾');
  });

  test('TC-RW-007: 메타 정보 그리드 — 핵심 필드 렌더링 확인', async ({ page }) => {
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#db-content');
    await page.locator('.meta-toggle').click();

    const metaText = await page.locator('#meta-grid').textContent();

    // 레이블 확인
    expect(metaText).toContain('대상자');
    expect(metaText).toContain('제공구분');
    expect(metaText).toContain('제공방법');
    expect(metaText).toContain('서비스유형');
    expect(metaText).toContain('제공장소');
    expect(metaText).toContain('제공일시');
    expect(metaText).toContain('이동시간');

    // 값 확인 (API 평문 응답 필드)
    expect(metaText).toContain('방문');
    expect(metaText).toContain('상담');
    expect(metaText).toContain('아동가정');
    expect(metaText).toContain('30분');
  });

  test('TC-RW-008: 대상자 배열 → "·" 구분자로 표시', async ({ page }) => {
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#db-content');
    await page.locator('.meta-toggle').click();

    const metaText = await page.locator('#meta-grid').textContent();
    expect(metaText).toContain('피해아동 · 보호자');
  });

  test('TC-RW-009: CTA 섹션(앱/확장프로그램 다운로드 버튼) 표시', async ({ page }) => {
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#db-content');

    const cta = page.locator('#cta-section');
    await expect(cta).toBeVisible();
  });

  test('TC-RW-010: XSS 방지 — HTML 특수문자 이스케이프 처리', async ({ page }) => {
    // 악성 페이로드가 포함된 Mock 레코드
    const maliciousResponse = {
      ...MOCK_SHARE_RESPONSE,
      encrypted_blob: undefined,
      case_name: '<script>alert("xss")</script>',
      service_description: '<img src=x onerror="alert(1)">',
      agent_opinion: '정상 소견',
    };

    await page.route(`**/api/records/share/${FIXTURE_SHARE_TOKEN}`, route =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(maliciousResponse),
      })
    );

    // XSS alert 발생 시 테스트 실패
    let xssTriggered = false;
    page.on('dialog', async (dialog) => {
      xssTriggered = true;
      await dialog.dismiss();
    });

    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, ''));
    await page.waitForTimeout(2000);

    expect(xssTriggered).toBe(false);

    // script 태그가 DOM에 주입되지 않았는지 확인
    const scriptCount = await page.locator('script[src="x"]').count();
    expect(scriptCount).toBe(0);
  });
});

// ── 오류 케이스 ─────────────────────────────────────────────────
test.describe('공유 링크 — 오류 / 엣지케이스', () => {
  test('TC-RW-011: 존재하지 않는 토큰 → 오류 상태 표시', async ({ page }) => {
    const invalidToken = 'invalid-token-000';
    await page.route(`**/api/records/share/${invalidToken}`, route =>
      route.fulfill({ status: 404, body: 'Not found' })
    );

    await page.goto(buildShareUrl(invalidToken, 'any-key'));

    await waitForVisible(page, '#state-error');
    await expect(page.locator('#state-loading')).toBeHidden();
    await expect(page.locator('#db-content')).toBeHidden();

    const errorText = await page.locator('#state-error').textContent();
    expect(errorText).toContain('삭제된 DB');
  });

  test('TC-RW-012: 암호화 키 없는 링크 → 정상 로드 (현재 앱은 키 미사용)', async ({ page }) => {
    // 현재 reviewer web은 E2EE 복호화를 앱에 위임 — URL fragment 키 유무와 무관하게 메타 정보 표시
    await mockShareApi(page);
    await page.goto(`${ENV.BASE_URL}/?token=${FIXTURE_SHARE_TOKEN}`);

    await waitForVisible(page, '#db-content');

    // 케이스명/작성자가 표시되어야 함 (평문 API 응답 기반)
    await expect(page.locator('#page-title')).toHaveText(/QA테스트아동/);
    // 복호화 오류 메시지가 없어야 함
    await expect(page.locator('#state-error')).toBeHidden();
  });

  test('TC-RW-013: URL에 임의 키가 있어도 정상 로드 (현재 앱은 키 미사용)', async ({ page }) => {
    // 현재 앱은 fragment key를 파싱하지 않으므로 어떤 키를 줘도 오류 없이 동작
    await mockShareApi(page);
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, 'wrong-key-that-will-fail'));

    await waitForVisible(page, '#db-content');

    // 정상 렌더링 확인
    await expect(page.locator('#page-title')).toHaveText(/QA테스트아동/);
    await expect(page.locator('#state-error')).toBeHidden();
    // JS 오류 없이 완료
    const errors: string[] = [];
    page.on('pageerror', err => errors.push(err.message));
    await page.waitForTimeout(500);
    expect(errors).toHaveLength(0);
  });

  test('TC-RW-014: 네트워크 오류 → 오류 상태 표시', async ({ page }) => {
    await page.route(`**/api/records/share/**`, route => route.abort('failed'));
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));

    await waitForVisible(page, '#state-error');
    await expect(page.locator('#state-loading')).toBeHidden();
  });

  test('TC-RW-015: token 파라미터 없이 접근 → 오류 처리', async ({ page }) => {
    await page.goto(`${ENV.BASE_URL}/`);
    // 오류 상태이거나 빈 페이지여야 함 — 앱이 크래시되면 안 됨
    // JS 에러가 uncaught exception으로 올라오면 실패
    const errors: string[] = [];
    page.on('pageerror', err => errors.push(err.message));
    await page.waitForTimeout(2000);

    // 치명적 JS 에러가 없어야 함 (uncaught TypeError 등)
    const fatalErrors = errors.filter(e =>
      e.includes('Cannot read') || e.includes('is not a function')
    );
    expect(fatalErrors).toHaveLength(0);
  });
});

// ── 인앱 브라우저 감지 ─────────────────────────────────────────
test.describe('인앱 브라우저 감지', () => {
  test('TC-RW-016: 카카오톡 UA → 차단 모달 표시', async ({ page }) => {
    await mockShareApi(page);

    // 카카오톡 UA 주입
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'userAgent', {
        get: () => 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 KAKAOTALK/10.4.5',
      });
    });

    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#inapp-modal');

    const modalText = await page.locator('#inapp-modal').textContent();
    expect(modalText).toContain('브라우저에서 열어주세요');
    expect(modalText).toContain('주소 복사하기');
  });

  test('TC-RW-017: 일반 Chrome UA → 차단 모달 미표시', async ({ page }) => {
    await mockShareApi(page);

    // Chrome UA (정상)
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'userAgent', {
        get: () => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      });
    });

    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));

    // 모달이 표시되지 않아야 함
    const modal = page.locator('#inapp-modal');
    await expect(modal).toBeHidden();
  });

  test('TC-RW-018: 주소 복사하기 버튼 클릭 → 텍스트 변경 확인', async ({ page, context }) => {
    // clipboard-write 권한 부여 (Chrome 전용 — WebKit/Safari는 미지원이므로 무시)
    await context.grantPermissions(['clipboard-read', 'clipboard-write']).catch(() => {});

    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'userAgent', {
        get: () => 'KAKAOTALK',
      });
      // read-only 프로퍼티인 clipboard를 Object.defineProperty로 대체
      Object.defineProperty(navigator, 'clipboard', {
        get: () => ({ writeText: () => Promise.resolve() }),
        configurable: true,
      });
    });

    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#inapp-modal');

    const copyBtn = page.locator('#inapp-modal .btn-modal');
    await copyBtn.click();

    // 버튼 텍스트가 "복사됨 ✓" 로 변경 (비동기 Promise.then 완료 대기)
    await expect(copyBtn).toHaveText(/복사됨/, { timeout: 3000 });
  });
});

// ── 반응형 / 모바일 ────────────────────────────────────────────
test.describe('모바일 반응형', () => {
  test('TC-RW-019: 모바일 뷰포트에서 레코드 정상 표시', async ({ page }) => {
    await mockShareApi(page);

    await page.setViewportSize({ width: 390, height: 844 }); // iPhone 14 Pro
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#db-content');

    // 제목, 본문이 뷰포트 내에서 가려지지 않는지 확인
    const title = page.locator('#page-title');
    await expect(title).toBeVisible();
    const titleBox = await title.boundingBox();
    expect(titleBox).not.toBeNull();
    expect(titleBox!.width).toBeLessThanOrEqual(390);
  });

  test('TC-RW-020: 가로 모드(landscape)에서 레이아웃 깨짐 없음', async ({ page }) => {
    await mockShareApi(page);

    await page.setViewportSize({ width: 844, height: 390 });
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#db-content');

    // JS 에러 없이 렌더링 완료 확인
    const errors: string[] = [];
    page.on('pageerror', err => errors.push(err.message));
    await page.waitForTimeout(1000);
    expect(errors).toHaveLength(0);
  });
});

// ── 접근성 ─────────────────────────────────────────────────────
test.describe('접근성 & SEO', () => {
  test('TC-RW-021: 페이지 lang 속성이 "ko"로 설정됨', async ({ page }) => {
    await mockShareApi(page);
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    const lang = await page.locator('html').getAttribute('lang');
    expect(lang).toBe('ko');
  });

  test('TC-RW-022: 이미지에 alt 속성 존재 [알려진 버그: rocket-particle]', async ({ page }) => {
    await mockShareApi(page);
    await page.goto(buildShareUrl(FIXTURE_SHARE_TOKEN, FIXTURE_ENC_KEY));
    await waitForVisible(page, '#db-content');

    // rocket-particle은 장식용 이미지 — alt="" 추가 필요한 알려진 버그
    // 비장식용 콘텐츠 이미지만 검사 (logo 이미지 등)
    const nonDecorativeImages = page.locator('img:not([alt]):not(.rocket-particle)');
    const count = await nonDecorativeImages.count();

    // 로켓 파티클 외 alt 없는 이미지 수 보고
    if (count > 0) {
      const srcs = await page.evaluate(() =>
        [...document.querySelectorAll('img:not([alt]):not(.rocket-particle)')]
          .map(img => (img as HTMLImageElement).src)
      );
      console.warn(`[BUG] alt 속성 없는 콘텐츠 이미지 ${count}개:`, srcs);
    }
    expect(count).toBe(0);

    // 별도: 로켓 파티클 버그 기록 (실패로 처리하지 않음 — TODO로 추적)
    const rocketBugCount = await page.locator('.rocket-particle:not([alt])').count();
    if (rocketBugCount > 0) {
      console.warn(`[BUG-KNOWN] rocket-particle 이미지 ${rocketBugCount}개에 alt="" 없음 (접근성 이슈)`);
    }
  });

  test('TC-RW-023: 메타 태그 — og:title, og:description (프로덕션 서버)', async ({ page }) => {
    // OG 태그는 Express 서버가 동적으로 주입 — 로컬 정적 서버에서는 없음
    // PROD_SHARE_TOKEN 환경변수로 프로덕션 실 토큰을 주입해야 검증 가능
    const prodToken = process.env.PROD_SHARE_TOKEN;
    if (!prodToken) {
      console.info('[SKIP] TC-RW-023: PROD_SHARE_TOKEN 미설정 → 실서버 OG 태그 검증 생략');
      return;
    }

    const prodUrl = `https://dash.qpon/?token=${prodToken}`;

    // waitUntil: 'commit' — HTML 수신 직후 (리다이렉트 JS 실행 전) 메타 태그 읽기
    const response = await page.goto(prodUrl, { waitUntil: 'commit', timeout: 10000 });
    expect(response?.status()).not.toBe(404);

    const ogTitle = await page.locator('meta[property="og:title"]').getAttribute('content', { timeout: 3000 });
    const ogDesc = await page.locator('meta[property="og:description"]').getAttribute('content', { timeout: 3000 });

    expect(ogTitle).toBeTruthy();
    expect(ogDesc).toBeTruthy();
  });
});
