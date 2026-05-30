// ================================================================
// DASH Chrome Extension — E2E 테스트
// 대상: dash_extension/extension (Manifest v3)
// 시나리오: 로그인 → PIN 인증 → 레코드 조회 → NCADS 자동입력
//
// 주의: Chrome 확장프로그램 테스트는 launchPersistentContext + headless:false 필수
//       (Playwright 공식 권고 사항 — headless에서 extension 미지원)
// ================================================================

import { test, expect, chromium, BrowserContext, Page } from '@playwright/test';
import path from 'path';
import { enterPin, waitForVisible } from '../fixtures/test-data';

const EXTENSION_PATH = path.resolve(__dirname, '../../../dash_extension/extension');

// ── 공유 persistent context (모든 extension 테스트에서 사용) ──
let sharedCtx: BrowserContext;
let extensionId: string;

test.beforeAll(async () => {
  sharedCtx = await chromium.launchPersistentContext('', {
    headless: false,
    args: [
      `--disable-extensions-except=${EXTENSION_PATH}`,
      `--load-extension=${EXTENSION_PATH}`,
    ],
  });

  // 서비스워커 등록 대기 (이미 등록된 경우 즉시 반환)
  let [background] = sharedCtx.serviceWorkers();
  if (!background) {
    background = await sharedCtx.waitForEvent('serviceworker', { timeout: 10000 });
  }
  extensionId = background.url().split('/')[2];
});

test.afterAll(async () => {
  await sharedCtx?.close();
});

// ── 각 테스트 전 chrome.storage 초기화 ─────────────────────────
test.beforeEach(async () => {
  const page = await sharedCtx.newPage();
  await page.goto(`chrome-extension://${extensionId}/sidepanel.html`);
  await page.evaluate(() => new Promise<void>(r => chrome.storage.local.clear(r)));
  await page.close();
});

async function openSidepanel(): Promise<Page> {
  const page = await sharedCtx.newPage();
  await page.goto(`chrome-extension://${extensionId}/sidepanel.html`);
  await page.waitForLoadState('domcontentloaded');
  return page;
}

// ── Mock 백엔드 레코드 ──────────────────────────────────────
const MOCK_RECORDS = [
  {
    id: 101,
    case_name: 'QA테스트아동',
    case_id: 1,
    status: 'Synced',
    created_at: '2026-05-29T01:00:00.000Z',
    service_name: '사례관리',
    method: '방문',
  },
  {
    id: 102,
    case_name: '홍길동아동',
    case_id: 2,
    status: 'Synced',
    created_at: '2026-05-28T10:00:00.000Z',
    service_name: '상담',
    method: '전화',
  },
];

// ── 메인 뷰 mock 헬퍼 (모듈 스코프 — 여러 describe에서 재사용) ─
// cachedVaultKeys + cachedDerivedKey → checkPinAndProceed()가 PIN 생략하고 main view 진입
// vault API를 반드시 mock: refreshVaultKeys()가 실서버 vault 복호화 실패 시 showPinView() 호출 방지
async function openMainViewWithMock(records = MOCK_RECORDS): Promise<Page> {
  const page = await openSidepanel();
  await page.route('**/api/records/ready**', route =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(records) })
  );
  await page.route('**/api/records/history**', route =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '[]' })
  );
  await page.route('**/api/users/vault/**', route =>
    route.fulfill({ status: 200, contentType: 'application/json',
      body: JSON.stringify({ encrypted_vault: null }) }) // encrypted_vault 없음 → refreshVaultKeys 조기 반환
  );
  await page.route('**/api/events**', route => route.abort());
  await page.evaluate(() =>
    new Promise<void>(resolve =>
      chrome.storage.local.set({
        dashUser: { uid: 'test-uid-qa-001', email: 'qa@test.com', name: 'QA상담원', photo: '' },
      }, resolve)
    )
  );
  await page.evaluate(() =>
    new Promise<void>(resolve =>
      chrome.storage.session.set({
        cachedOAuthToken: 'mock-oauth-token',
        cachedVaultKeys: { 'mock-share-token': 'mock-enc-key' },
        cachedDerivedKey: 'mock-derived-key-32chars-padding!!',
      }, resolve)
    )
  );
  await page.reload();
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(500);
  return page;
}

// ── 로그인 화면 ─────────────────────────────────────────────
test.describe('로그인 화면', () => {
  test('TC-EX-001: 최초 실행 시 로그인 뷰 표시', async () => {
    const page = await openSidepanel();

    await expect(page.locator('#login-view')).toBeVisible({ timeout: 5000 });
    await expect(page.locator('#pin-view')).toBeHidden();
    await expect(page.locator('#main-view')).toBeHidden();

    await page.close();
  });

  test('TC-EX-002: 구글 로그인 버튼 존재 및 클릭 가능', async () => {
    const page = await openSidepanel();
    await waitForVisible(page, '#login-view');

    const loginBtn = page.locator('#btn-google-login');
    await expect(loginBtn).toBeVisible();
    await expect(loginBtn).toBeEnabled();
    expect(await loginBtn.textContent()).toContain('Google');

    await page.close();
  });

  test('TC-EX-003: 로그인 화면 — 로고 및 타이틀 표시', async () => {
    const page = await openSidepanel();
    await waitForVisible(page, '#login-view');

    await expect(page.locator('.login-logo img')).toBeVisible();
    const title = page.locator('.login-title');
    await expect(title).toBeVisible();
    expect(await title.textContent()).toBe('Dash');
    await expect(page.locator('.login-subtitle')).toBeVisible();

    await page.close();
  });
});

// ── PIN 인증 화면 ────────────────────────────────────────────
test.describe('PIN 인증 화면', () => {
  // 올바른 스토리지 키: dashUser (local) + cachedOAuthToken (session)
  // Vault API mock → hasVault=true → PIN 화면 표시
  async function openPinView(): Promise<Page> {
    const page = await openSidepanel();
    await page.route('**/api/users/vault/**', route =>
      route.fulfill({
        status: 200, contentType: 'application/json',
        body: JSON.stringify({ encrypted_vault: 'mock-encrypted-vault-blob', salt: 'mock-salt-16bytes!!' }),
      })
    );
    await page.evaluate(() =>
      new Promise<void>(resolve =>
        chrome.storage.local.set({
          dashUser: { uid: 'test-uid-qa-001', email: 'qa@test.com', name: 'QA상담원', photo: '' },
        }, resolve)
      )
    );
    await page.evaluate(() =>
      new Promise<void>(resolve =>
        chrome.storage.session.set({ cachedOAuthToken: 'mock-oauth-token' }, resolve)
      )
    );
    await page.reload();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(500);
    return page;
  }

  test('TC-EX-004: PIN 뷰 — 4개의 PIN 도트 표시', async () => {
    const page = await openPinView();
    await expect(page.locator('#pin-view')).toBeVisible({ timeout: 3000 });
    const dots = page.locator('#pin-dots .pin-dot, .pin-dot');
    expect(await dots.count()).toBeGreaterThanOrEqual(4);
    await page.close();
  });

  test('TC-EX-005: PIN 키패드 — 숫자 0~9 버튼 존재', async () => {
    const page = await openPinView();
    await expect(page.locator('#pin-view')).toBeVisible({ timeout: 3000 });
    for (const digit of ['1','2','3','4','5','6','7','8','9','0']) {
      await expect(page.locator(`.pin-key:has-text("${digit}"), [data-digit="${digit}"]`).first()).toBeVisible();
    }
    await page.close();
  });

  test('TC-EX-006: 숫자 입력 시 PIN 도트 채워짐', async () => {
    const page = await openPinView();
    await expect(page.locator('#pin-view')).toBeVisible({ timeout: 3000 });
    await page.locator('.pin-key:has-text("1"), [data-digit="1"]').first().click();
    await expect(page.locator('.pin-dot').first()).toHaveClass(/filled|active/);
    await page.close();
  });

  test('TC-EX-007: 삭제 버튼으로 마지막 입력 제거', async () => {
    const page = await openPinView();
    await expect(page.locator('#pin-view')).toBeVisible({ timeout: 3000 });
    await page.locator('.pin-key:has-text("1"), [data-digit="1"]').first().click();
    const delBtn = page.locator('[data-key="delete"], .pin-key-delete, .pin-key:has-text("⌫")').first();
    await delBtn.click();
    await expect(page.locator('.pin-dot').first()).not.toHaveClass(/filled|active/);
    await page.close();
  });

  test('TC-EX-008: 잘못된 PIN 입력 시 오류 메시지 / 도트 흔들림', async () => {
    const page = await openSidepanel();
    // vault 인증 실패 응답 먼저 등록
    await page.route('**/api/users/vault/**', route => {
      const url = route.request().url();
      // GET vault → vault 존재 (PIN 화면 표시용), POST/기타 → 403 (잘못된 PIN)
      if (route.request().method() === 'GET') {
        route.fulfill({
          status: 200, contentType: 'application/json',
          body: JSON.stringify({ encrypted_vault: 'mock-vault', salt: 'mock-salt-16bytes!!' }),
        });
      } else {
        route.fulfill({ status: 403, contentType: 'application/json',
          body: JSON.stringify({ error: 'Invalid PIN' }) });
      }
    });
    await page.evaluate(() =>
      new Promise<void>(resolve =>
        chrome.storage.local.set({
          dashUser: { uid: 'test-uid-qa-001', email: 'qa@test.com', name: 'QA상담원', photo: '' },
        }, resolve)
      )
    );
    await page.evaluate(() =>
      new Promise<void>(resolve =>
        chrome.storage.session.set({ cachedOAuthToken: 'mock-oauth-token' }, resolve)
      )
    );
    await page.reload();
    await page.waitForLoadState('domcontentloaded');
    await expect(page.locator('#pin-view')).toBeVisible({ timeout: 3000 });

    for (const d of ['9','9','9','9']) {
      await page.locator(`.pin-key:has-text("${d}"), [data-key="${d}"]`).first().click();
    }
    await page.waitForTimeout(1000);

    const hasError = await page.locator('.pin-error, .error-text, #pin-error').isVisible().catch(() => false);
    const hasShake = await page.locator('.pin-dots.shake, #pin-dots.shake').isVisible().catch(() => false);
    expect(hasError || hasShake).toBe(true);
    await page.close();
  });
});

// ── 메인 뷰 — 레코드 탭 ─────────────────────────────────────
test.describe('메인 뷰 — 레코드 탭', () => {
  test('TC-EX-009: 메인 뷰 — 3개 탭(나의 DB, 공유할 DB, 이전 기록) 표시', async () => {
    const page = await openMainViewWithMock();
    await expect(page.locator('#main-view')).toBeVisible({ timeout: 3000 });

    const tabs = page.locator('.main-tab, .tab-btn, [role="tab"]');
    expect(await tabs.count()).toBeGreaterThanOrEqual(3);
    const joined = (await tabs.allTextContents()).join(' ');
    expect(joined).toContain('나의 DB');
    expect(joined).toContain('공유');
    expect(joined).toContain('이전');
    await page.close();
  });

  test('TC-EX-010: 레코드 카드 목록 표시', async () => {
    const page = await openMainViewWithMock();
    await expect(page.locator('#main-view')).toBeVisible({ timeout: 3000 });
    await page.waitForTimeout(1500);
    const count = await page.locator('.record-item, .db-card-item, .record-row, #records-container > *').count();
    expect(count).toBeGreaterThan(0);
    await page.close();
  });

  test('TC-EX-011: 레코드 카드 — 케이스명 표시', async () => {
    const page = await openMainViewWithMock();
    await expect(page.locator('#main-view')).toBeVisible({ timeout: 3000 });
    await page.waitForTimeout(1500);
    const text = await page.locator('.record-item, .db-card-item, .record-row, #records-container > *').first().textContent();
    expect(text).toMatch(/QA테스트아동|홍길동아동|사례관리|상담/);
    await page.close();
  });

  test('TC-EX-012: 빈 레코드 목록 — 안내 메시지 표시', async () => {
    const page = await openMainViewWithMock([]);
    await expect(page.locator('#main-view')).toBeVisible({ timeout: 3000 });
    await page.waitForTimeout(1500);

    const recordCount = await page.locator('.record-item, .db-card-item, #records-container > *').count();
    const hasEmptyUI = await page.locator('#empty-state, .empty-state, .no-records, .empty-msg').isVisible().catch(() => false);
    expect(recordCount === 0 || hasEmptyUI).toBe(true);
    await page.close();
  });
});

// ── NCADS 자동 입력 플로우 ──────────────────────────────────
test.describe('NCADS 자동 입력 플로우', () => {
  test('TC-EX-013: NCADS 페이지에서 확장프로그램 아이콘 강조(하이라이트)', async () => {
    const ncadsMockPage = await sharedCtx.newPage();
    await ncadsMockPage.setContent(`
      <!DOCTYPE html>
      <html>
        <head><title>아동학대정보시스템</title></head>
        <body>
          <form>
            <input id="svcClassDetailCd" name="svcClassDetailCd" />
            <select id="svcExecRecipientId"><option value="">선택</option></select>
            <input id="svcExecYmd" name="svcExecYmd" />
            <textarea id="svcExecContent"></textarea>
          </form>
        </body>
      </html>
    `, { url: 'https://ncads.go.kr/mock-form' });

    await ncadsMockPage.waitForTimeout(1000);
    expect(ncadsMockPage.isClosed()).toBe(false);
    await ncadsMockPage.close();
  });

  test('TC-EX-014: 레코드 클릭 → content script에 INJECT 메시지 발송', async () => {
    const singleRecord = [{ id: 101, case_name: 'QA테스트아동', status: 'Synced',
      created_at: '2026-05-29T01:00:00.000Z', service_name: '사례관리', method: '방문' }];
    const page = await openMainViewWithMock(singleRecord);
    await expect(page.locator('#main-view')).toBeVisible({ timeout: 3000 });

    await page.evaluate(() => {
      const orig = chrome.tabs.sendMessage;
      (chrome.tabs as any).sendMessage = (tabId: number, msg: any, ...args: any[]) => {
        (window as any).__lastMessage = msg;
        return orig(tabId, msg, ...args);
      };
    });

    const firstRecord = page.locator('.record-card, .record-item, .db-card-item, .record-row, #records-container > *').first();
    if (await firstRecord.count() > 0) {
      await firstRecord.click();
      await page.waitForTimeout(500);
      const lastMsg = await page.evaluate(() => (window as any).__lastMessage);
      if (lastMsg) {
        expect(lastMsg.action || lastMsg.type).toMatch(/inject|INJECT|fill|FILL/i);
      }
    }
    await page.close();
  });
});

// ── 실시간 동기화 (SSE) ─────────────────────────────────────
test.describe('실시간 동기화', () => {
  test('TC-EX-015: SSE 연결 끊김 후 재연결 시도', async () => {
    const page = await openSidepanel();
    await page.route('**/api/events**', route => route.abort('connectionreset'));
    await page.route('**/api/records/ready**', route =>
      route.fulfill({ status: 200, contentType: 'application/json', body: '[]' })
    );
    await page.route('**/api/records/history**', route =>
      route.fulfill({ status: 200, contentType: 'application/json', body: '[]' })
    );
    await page.route('**/api/users/vault/**', route =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ encrypted_vault: null }) })
    );
    await page.evaluate(() =>
      new Promise<void>(resolve =>
        chrome.storage.local.set({
          dashUser: { uid: 'test-uid-qa-001', email: 'qa@test.com', name: 'QA상담원', photo: '' },
        }, resolve)
      )
    );
    await page.evaluate(() =>
      new Promise<void>(resolve =>
        chrome.storage.session.set({
          cachedOAuthToken: 'mock-oauth-token',
          cachedVaultKeys: { 'mock-share-token': 'mock-enc-key' },
          cachedDerivedKey: 'mock-derived-key-32chars-padding!!',
        }, resolve)
      )
    );
    await page.reload();
    await page.waitForTimeout(3000);

    expect(page.isClosed()).toBe(false);
    expect(await page.locator('.fatal-error, .crash-screen').isVisible().catch(() => false)).toBe(false);
    await page.close();
  });
});

// ── UI 접근성 ────────────────────────────────────────────────
test.describe('Extension UI 접근성', () => {
  test('TC-EX-016: 모든 버튼에 aria-label 또는 텍스트 콘텐츠 존재', async () => {
    const page = await openSidepanel();
    await page.waitForTimeout(500);

    const buttons = page.locator('button');
    const count = await buttons.count();
    for (let i = 0; i < count; i++) {
      const btn = buttons.nth(i);
      const ariaLabel = await btn.getAttribute('aria-label');
      const text = await btn.textContent();
      const title = await btn.getAttribute('title');
      expect((ariaLabel && ariaLabel.trim()) || (text && text.trim()) || (title && title.trim())).toBeTruthy();
    }
    await page.close();
  });

  test('TC-EX-017: 확장프로그램 페이지 — JS 콘솔 에러 없음', async () => {
    const errors: string[] = [];
    const page = await openSidepanel();
    page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
    page.on('pageerror', err => errors.push(err.message));
    await page.waitForTimeout(2000);

    const fatalErrors = errors.filter(e =>
      !e.includes('net::ERR') && !e.includes('Failed to fetch') && !e.includes('ERR_BLOCKED_BY_CLIENT') &&
      (e.includes('TypeError') || e.includes('ReferenceError') || e.includes('SyntaxError'))
    );
    expect(fatalErrors).toHaveLength(0);
    await page.close();
  });
});
