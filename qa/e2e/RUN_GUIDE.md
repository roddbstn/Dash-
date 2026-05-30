# DASH E2E 테스트 실행 가이드

## 디렉토리 구조

```
qa/e2e/
├── playwright.config.ts          # Playwright 설정
├── package.json                  # 의존성
├── RUN_GUIDE.md                  # 이 파일
├── fixtures/
│   └── test-data.ts              # 공통 픽스처 & 유틸리티
└── tests/
    ├── reviewer-web.spec.ts      # Reviewer Web E2E (23개 TC)
    ├── extension.spec.ts         # Chrome Extension E2E (17개 TC)
    ├── api.spec.ts               # Backend API (31개 TC)
    └── bottleneck-report.md      # 병목 구간 분석

dash_mobile/integration_test/
└── app_flow_test.dart            # Flutter Integration Tests (30개 TC)
```

---

## 사전 준비

### 1. Node.js 의존성 설치
```bash
cd qa/e2e
npm install
npx playwright install chromium
```

### 2. Flutter 의존성 (모바일 통합 테스트)
```bash
cd dash_mobile
flutter pub get
flutter pub add --dev integration_test
```

---

## 테스트 실행

### Reviewer Web E2E
```bash
cd qa/e2e

# Mock 서버 사용 (프로덕션 영향 없음)
npx playwright test tests/reviewer-web.spec.ts

# 실제 서버 대상
BASE_URL=https://dash.qpon npx playwright test tests/reviewer-web.spec.ts

# 특정 TC만 실행
npx playwright test tests/reviewer-web.spec.ts -g "TC-RW-006"

# headed 모드 (브라우저 화면 보면서)
npx playwright test tests/reviewer-web.spec.ts --headed
```

### Chrome Extension E2E
```bash
cd qa/e2e

# 확장프로그램 로드하여 실행
npx playwright test tests/extension.spec.ts --project=extension

# headed 모드 필수 (extension은 headless 미지원)
npx playwright test tests/extension.spec.ts --project=extension --headed
```

### Backend API 테스트
```bash
cd qa/e2e

# 공개 API만 (토큰 불필요)
npx playwright test tests/api.spec.ts --project=api

# 인증 필요 API까지 (Firebase 토큰 주입)
DASH_TEST_ID_TOKEN=<firebase_id_token> \
DASH_TEST_UID=<test_user_uid> \
npx playwright test tests/api.spec.ts --project=api

# 로컬 서버 대상
BASE_URL=http://localhost:3000 npx playwright test tests/api.spec.ts
```

### Flutter 통합 테스트 (모바일)
```bash
cd dash_mobile

# 연결된 기기에서 실행
flutter test integration_test/app_flow_test.dart

# 특정 기기
flutter test integration_test/app_flow_test.dart --device-id=<device_id>

# 에뮬레이터
flutter emulators --launch Pixel_7_API_34
flutter test integration_test/app_flow_test.dart

# iOS 시뮬레이터
open -a Simulator
flutter test integration_test/app_flow_test.dart --device-id=<ios_simulator_id>
```

### 전체 실행 (E2E만)
```bash
cd qa/e2e
npx playwright test
# 결과 리포트
npx playwright show-report
```

---

## 환경변수 설정

| 변수명 | 설명 | 기본값 |
|--------|------|--------|
| `BASE_URL` | 백엔드 서버 URL | `https://dash.qpon` |
| `DASH_TEST_ID_TOKEN` | Firebase ID Token (인증 필요 TC) | 없음 |
| `DASH_TEST_UID` | 테스트 계정 UID | `test-uid-qa-001` |
| `DASH_TEST_PIN` | 테스트 PIN | `1234` |

### Firebase 테스트 토큰 발급 방법
```bash
# Firebase CLI로 커스텀 토큰 발급 후 ID Token 교환
firebase auth:export --format=json  # 유저 목록 확인

# REST API로 테스트 토큰 발급 (Firebase Emulator 사용 권장)
curl -X POST 'http://localhost:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-key' \
  -H 'Content-Type: application/json' \
  -d '{"token":"<custom_token>","returnSecureToken":true}'
```

---

## TC 목록 요약

### Reviewer Web (`reviewer-web.spec.ts`) — 23개
| TC ID | 분류 | 설명 |
|-------|------|------|
| TC-RW-001 | 정상 | 로딩 스피너 → 콘텐츠 전환 |
| TC-RW-002 | 정상 | E2EE 복호화 → 케이스명 표시 |
| TC-RW-003 | 정상 | 작성자 뱃지 표시 |
| TC-RW-004 | 정상 | 서비스 내용 렌더링 |
| TC-RW-005 | 정상 | 상담원 소견 블록 표시 |
| TC-RW-006 | 정상 | 아코디언 펼치기/접기 |
| TC-RW-007 | 정상 | 메타 그리드 핵심 필드 |
| TC-RW-008 | 정상 | 대상자 배열 구분자 표시 |
| TC-RW-009 | 정상 | CTA 섹션 표시 |
| TC-RW-010 | 보안 | XSS 방지 이스케이프 |
| TC-RW-011 | 오류 | 없는 토큰 → 오류 상태 |
| TC-RW-012 | 오류 | 키 없는 링크 → 경고 |
| TC-RW-013 | 오류 | 잘못된 키 → 복호화 실패 경고 |
| TC-RW-014 | 오류 | 네트워크 오류 처리 |
| TC-RW-015 | 오류 | token 없이 접근 |
| TC-RW-016 | 인앱 | 카카오톡 UA 차단 모달 |
| TC-RW-017 | 인앱 | Chrome UA 차단 미표시 |
| TC-RW-018 | 인앱 | 주소 복사 버튼 동작 |
| TC-RW-019 | 반응형 | 모바일 뷰포트 |
| TC-RW-020 | 반응형 | 가로 모드 |
| TC-RW-021 | 접근성 | lang="ko" 설정 |
| TC-RW-022 | 접근성 | img alt 속성 |
| TC-RW-023 | SEO | OG 메타 태그 |

### Chrome Extension (`extension.spec.ts`) — 17개
| TC ID | 분류 | 설명 |
|-------|------|------|
| TC-EX-001~003 | 로그인 | 로그인 뷰, 버튼, 로고 |
| TC-EX-004~008 | PIN | 도트, 키패드, 입력, 삭제, 오류 |
| TC-EX-009~012 | 메인뷰 | 탭, 레코드 목록, 빈 상태 |
| TC-EX-013~014 | 주입 | NCADS 하이라이트, 메시지 발송 |
| TC-EX-015 | SSE | 재연결 처리 |
| TC-EX-016~017 | 접근성 | 버튼 label, 콘솔 에러 없음 |

### Backend API (`api.spec.ts`) — 31개
| TC ID | 분류 | 설명 |
|-------|------|------|
| TC-API-001~003 | 헬스 | 200, 보안 헤더, X-Powered-By 제거 |
| TC-API-004~006 | 인증 | 무인증 401, 잘못된 토큰, 정상 |
| TC-API-007~008 | RateLimit | 공개 엔드, 보호 엔드 |
| TC-API-009~012 | 공유 | 토큰 CRUD, 인증없이 접근 |
| TC-API-013~019 | CRUD | 케이스&레코드 생성/조회/삭제 |
| TC-API-020~023 | 사용자 | 프로필, 통계, 닉네임, FCM |
| TC-API-024~025 | 볼트 | 저장, 조회 |
| TC-API-026~027 | 알림 | 목록, 읽음 처리 |
| TC-API-028~030 | 검증 | 필수필드, SQL Injection |
| TC-API-031 | SSE | Content-Type 헤더 |

### Flutter Integration (`app_flow_test.dart`) — 30개
| TC ID | 분류 | 설명 |
|-------|------|------|
| TC-MOB-001~002 | 초기화 | 크래시 없음, 온보딩 표시 |
| TC-MOB-003~004 | 온보딩 | 스와이프, 구글 로그인 버튼 |
| TC-MOB-008~009 | PIN | dot 표시, 4자리 입력 |
| TC-MOB-013~016 | 홈 | 탭 바, FAB, 탭 전환 |
| TC-MOB-021~023 | 케이스 | FAB → 화면전환, 입력필드, 유효성 |
| TC-MOB-029~032 | 폼 | 필드표시, 날짜피커, draft, 유효성 |
| TC-MOB-037~038 | 공유 | 롱프레스, 링크 생성 |
| TC-MOB-043~044 | 프로필 | 정보표시, 로그아웃 확인 |
| TC-MOB-048 | 딥링크 | 공유 DB 미리보기 |
| TC-MOB-053~054 | 오류 | 네트워크, 토큰 만료 |
| TC-MOB-058~059 | 접근성 | Semantics, 큰 폰트 |

---

## CI/CD 연동 예시 (GitHub Actions)

```yaml
# .github/workflows/e2e.yml
name: E2E Tests

on: [push, pull_request]

jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: cd qa/e2e && npm ci
      - run: npx playwright install --with-deps chromium
      - name: Run E2E (Reviewer Web + API)
        run: |
          cd qa/e2e
          BASE_URL=${{ secrets.DASH_STAGING_URL }} \
          npx playwright test tests/reviewer-web.spec.ts tests/api.spec.ts
        env:
          DASH_TEST_ID_TOKEN: ${{ secrets.DASH_TEST_ID_TOKEN }}
          DASH_TEST_UID: ${{ secrets.DASH_TEST_UID }}
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: qa/e2e/playwright-report/
```
