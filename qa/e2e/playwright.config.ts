import { defineConfig, devices } from '@playwright/test';
import path from 'path';

// reviewer_site 디렉토리를 로컬 정적 서버로 제공
// - /?token=<token>#key=<key> 형태로 접근 시 index.html이 서빙됨
// - API 호출(/api/...)은 page.route()로 모킹
const REVIEWER_SITE_DIR = path.resolve(__dirname, '../../dash_mobile/server/reviewer_site');
const LOCAL_PORT = 4321;

export default defineConfig({
  testDir: './tests',
  timeout: 30_000,
  expect: { timeout: 8_000 },
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 1 : 2,

  reporter: [
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
    ['list'],
  ],

  // reviewer-web 테스트: 로컬 정적 서버 자동 시작
  webServer: {
    command: `npx serve "${REVIEWER_SITE_DIR}" -l ${LOCAL_PORT}`,
    url: `http://localhost:${LOCAL_PORT}`,
    reuseExistingServer: !process.env.CI,
    timeout: 15_000,
  },

  use: {
    // reviewer-web 테스트는 로컬 서버 사용
    // API 테스트는 BASE_URL 환경변수로 실서버 지정 가능
    baseURL: `http://localhost:${LOCAL_PORT}`,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    locale: 'ko-KR',
    timezoneId: 'Asia/Seoul',
  },

  projects: [
    // ── Reviewer Web (Chrome Desktop) ──────────────────────────
    {
      name: 'reviewer-web-chrome',
      testMatch: '**/reviewer-web.spec.ts',
      use: { ...devices['Desktop Chrome'] },
    },
    // ── Reviewer Web (Mobile Safari — iOS) ─────────────────────
    {
      name: 'reviewer-web-mobile',
      testMatch: '**/reviewer-web.spec.ts',
      use: { ...devices['iPhone 13'] },
    },
    // ── Chrome Extension ────────────────────────────────────────
    // 주의: Chrome 확장프로그램은 headless 모드에서 동작하지 않음
    // headless: false 필수 (Playwright 공식 문서 권고)
    {
      name: 'extension',
      testMatch: '**/extension.spec.ts',
      use: {
        ...devices['Desktop Chrome'],
        headless: false,
        launchOptions: {
          headless: false,
          args: [
            '--disable-extensions-except=' + path.resolve(__dirname, '../../dash_extension/extension'),
            '--load-extension=' + path.resolve(__dirname, '../../dash_extension/extension'),
          ],
        },
      },
    },
    // ── API Integration — 실제 서버 대상 ──────────────────────
    {
      name: 'api',
      testMatch: '**/api.spec.ts',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: process.env.BASE_URL || 'https://dash.qpon',
      },
    },
  ],
});
