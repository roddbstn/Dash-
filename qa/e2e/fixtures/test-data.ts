// ──────────────────────────────────────────────────────────────
// DASH E2E 테스트 공통 픽스처 & 유틸리티
// ──────────────────────────────────────────────────────────────

import * as crypto from 'crypto';

// ── 테스트 환경 변수 ─────────────────────────────────────────
export const ENV = {
  // reviewer-web 테스트: 로컬 정적 서버 (playwright.config의 webServer)
  BASE_URL: process.env.REVIEWER_BASE_URL || 'http://localhost:4321',
  // API 테스트: 실제 백엔드 서버
  API_BASE_URL: process.env.BASE_URL || 'https://dash.qpon',
  /** 실제 테스트용 Firebase ID Token (CI 환경에서 주입) */
  TEST_ID_TOKEN: process.env.DASH_TEST_ID_TOKEN || '',
  /** 테스트 계정 UID */
  TEST_UID: process.env.DASH_TEST_UID || 'test-uid-qa-001',
  /** 테스트 PIN */
  TEST_PIN: process.env.DASH_TEST_PIN || '1234',
};

// ── AES-256-CBC 암호화 헬퍼 (앱과 동일 알고리즘) ────────────
export function encryptBlob(plainJson: object, keyStr: string): string {
  const key = Buffer.from(keyStr.padEnd(32).substring(0, 32), 'utf8');
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
  let encrypted = cipher.update(JSON.stringify(plainJson), 'utf8', 'base64');
  encrypted += cipher.final('base64');
  return `${iv.toString('base64')}:${encrypted}`;
}

// ── 공유 링크 생성 헬퍼 ─────────────────────────────────────
export function buildShareUrl(token: string, encKey: string, base = ENV.BASE_URL): string {
  return `${base}/?token=${token}#key=${encKey}`;
}

// ── 픽스처: 공유 DB 레코드 (복호화 전 상태) ────────────────
export const FIXTURE_ENC_KEY = 'qa-test-key-32chars-padded!!!!!';

export const FIXTURE_RECORD_PLAINTEXT = {
  caseName: 'QA테스트아동',
  serviceDescription: '가정방문 후 아동 안전 확인. 보호자 면담 실시.',
  agentOpinion: '아동 상태 안정적. 주 1회 모니터링 필요.',
  target: ['피해아동', '보호자'],
  provision_type: '아동보호전문기관',
  method: '방문',
  service_type: '상담',
  service_category: '직접서비스',
  service_name: '사례관리',
  location: '아동가정',
  startTime: '2026-05-29 10:00:00',
  endTime: '2026-05-29 11:30:00',
  serviceCount: 1,
  travelTime: 30,
};

export const FIXTURE_SHARE_TOKEN = 'qa-share-token-00001';

// ── 픽스처: Mock API 응답 ────────────────────────────────────
// /api/records/share/:token 이 실제로 반환하는 평문 필드와 일치
export const MOCK_SHARE_RESPONSE = {
  id: 1,
  share_token: FIXTURE_SHARE_TOKEN,
  case_name: 'QA테스트아동',
  user_name: 'QA상담원',
  provision_type: '아동보호전문기관',
  method: '방문',
  service_type: '상담',
  service_category: '직접서비스',
  service_name: '사례관리',
  location: '아동가정',
  start_time: '2026-05-29 10:00:00',
  end_time: '2026-05-29 11:30:00',
  travel_time: 30,
  service_count: 1,
  target: '피해아동,보호자',
  created_at: '2026-05-29T01:00:00.000Z',
};

// ── PIN 키패드 유틸 ─────────────────────────────────────────
export async function enterPin(page: import('@playwright/test').Page, pin: string) {
  for (const digit of pin.split('')) {
    // 키패드 버튼 (data-digit 속성 또는 텍스트로 찾기)
    const btn = page.locator(`[data-digit="${digit}"], .pin-key:has-text("${digit}")`).first();
    await btn.click();
    await page.waitForTimeout(80); // 타이핑 느낌
  }
}

// ── 요소 대기 래퍼 ──────────────────────────────────────────
export async function waitForVisible(
  page: import('@playwright/test').Page,
  selector: string,
  timeout = 8000,
) {
  await page.waitForSelector(selector, { state: 'visible', timeout });
}
