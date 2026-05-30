# DASH 통합 테스트 스위트

## 구성

```
tests/integration/
├── api_integration_test.js        # 백엔드 API 전체 통합 테스트 (메인)
├── reviewer_web_e2e_test.js       # Reviewer Web E2E 테스트
├── extension_integration_test.js  # Chrome 확장프로그램 ↔ API 통합 테스트
└── mobile_sync_test.dart          # Flutter 모바일 ↔ API 통합 테스트 (Dart)
```

---

## 실행 방법

### 사전 준비

```bash
# 로컬 서버 실행 (서버 디렉토리에서)
cd dash_mobile/server
node index.js
```

### 1. API 통합 테스트 (메인)

```bash
# 로컬 서버 대상 (토큰 없이 — 공개 API만 테스트)
node tests/integration/api_integration_test.js

# 로컬 서버 + Firebase 토큰 (전체 테스트)
DASH_TEST_TOKEN=eyJ... node tests/integration/api_integration_test.js

# 프로덕션 대상
DASH_TEST_TOKEN=eyJ... DASH_ADMIN_SECRET=secret node tests/integration/api_integration_test.js --prod
```

### 2. Reviewer Web E2E 테스트

```bash
node tests/integration/reviewer_web_e2e_test.js

# 기존 share_token 사용
DASH_TEST_TOKEN=eyJ... DASH_TEST_SHARE_TOKEN=abc123 node tests/integration/reviewer_web_e2e_test.js
```

### 3. 확장프로그램 통합 테스트

```bash
DASH_TEST_TOKEN=eyJ... node tests/integration/extension_integration_test.js

# Google OAuth 토큰 추가 (ya29...)
DASH_TEST_GOOGLE_TOKEN=ya29... DASH_TEST_TOKEN=eyJ... node tests/integration/extension_integration_test.js
```

### 4. Flutter 모바일 통합 테스트

```bash
cd dash_mobile
# 로컬 서버 (fcmInitialized=false → 인증 bypass)
flutter test test/mobile_sync_test.dart \
  --dart-define=TEST_BASE_URL=http://localhost:3000

# Android 에뮬레이터 (로컬 서버)
flutter test test/mobile_sync_test.dart \
  --dart-define=TEST_BASE_URL=http://10.0.2.2:3000
```

---

## 환경변수

| 변수 | 설명 | 필수 여부 |
|------|------|-----------|
| `DASH_TEST_TOKEN` | Firebase ID Token (`eyJ...`) | 인증 테스트에 필요 |
| `DASH_ADMIN_SECRET` | Admin KPI API 시크릿 | Admin 테스트에 필요 |
| `DASH_TEST_SHARE_TOKEN` | 기존 share_token (레코드 생성 없이 테스트 시) | 선택 |
| `DASH_TEST_GOOGLE_TOKEN` | Google OAuth Access Token (`ya29...`) | 확장프로그램 OAuth 테스트 |

---

## 테스트 범위

### api_integration_test.js
| # | 그룹 | 설명 |
|---|------|------|
| 1 | 인프라 상태 | /health DB 연결, CORS 기본 동작 |
| 2 | 인증 미들웨어 | 토큰 없음/잘못됨 → 401, Firebase 토큰 검증 |
| 3 | User API | 프로필 upsert, 조회, 통계 |
| 4 | Case API | BIGINT ID 보존, 목록, 중복 upsert |
| 5 | Record 동기화 | 신규/업데이트, 幂等성, 길이 제한, 데이터 유실 방지 |
| 6 | 공유 링크 | 스키마 검증, E2EE 포맷, OG 태그, 딥링크 |
| 7 | Counselor API | CRUD, 순서 변경 |
| 8 | Vault | Zero-knowledge 저장/조회, 키 미노출 |
| 9 | SSE | 연결, connected 이벤트, heartbeat |
| 10 | Admin KPI | 인증 보호, 응답 스키마, 숫자 일관성 |
| 11 | 데이터 무결성 | 고아 레코드, encryption_key 미노출, 하위 호환 |
| 12 | Cross-Component E2E | 모바일 동기화 → 웹 조회 → 확장프로그램 조회 흐름 |

### reviewer_web_e2e_test.js
- 공유 레코드 조회 및 E2EE 복호화 검증 (AES-256-CBC)
- 리뷰어 저장 (PUT) 및 데이터 반영 확인
- 편집 히스토리 (record_edit_history) 스키마 검증
- 공유 링크 만료 설정
- Admin 대시보드 HTML + KPI API
- save-to-my-db 흐름
- 정적 파일, OG 이미지, App Links 파일

### extension_integration_test.js
- Google OAuth / Firebase 이중 인증 경로
- CORS Extension ID 화이트리스트
- 레코드 조회 필드 매핑 (NCADS 자동주입용)
- 상태 업데이트 (Injected 전환)
- NCADS 폼 필드 → API 필드 매핑 정합성
- Vault 접근 및 Rate Limiting
- SSE 실시간 이벤트 수신

### mobile_sync_test.dart
- 인증 미들웨어 (Flutter HTTP 클라이언트)
- BIGINT case_id 직렬화 보존
- 레코드 동기화 幂等성
- 입력 검증 (길이 초과 → 400)
- 빈 active_tokens 데이터 유실 방지
- E2EE blob 포맷 및 복호화 검증
- DateTime / 숫자 타입 직렬화
- Unicode 한글 데이터 보존

---

## 발견된 주요 통합 리스크 (테스트 설계 기준)

1. **BIGINT ID 정밀도 손실**: `case_id`가 13자리 Unix ms timestamp로 생성될 경우 JS `Number` 최대값(2^53) 초과 가능 → `save-to-my-db`에서 `Math.floor(Date.now()/1000)` (10자리)로 수정됨 — 하지만 모바일은 ms 사용 가능성 → 타입 일관성 모니터링 필요

2. **빈 active_tokens 전체 삭제**: `sync_active` 호출 시 빈 배열이면 해당 유저 모든 레코드 삭제 → 가드 로직 존재하나 모바일 오프라인 복구 시 엣지케이스 잔존

3. **encryption_key 노출 위험**: 구버전 클라이언트 또는 직접 API 호출로 `encryption_key`를 전송해도 서버가 저장하지 않는지 확인 필요

4. **E2EE blob null 처리**: `Reviewed` 상태 저장 시 `encrypted_blob=null`로 덮어쓰는 로직 → 확장프로그램이 stale blob 대신 plaintext 사용 — 복호화 실패 엣지케이스

5. **SSE 연결 누적**: Railway 재시작 후 dead client 정리 로직이 write 실패 시에만 동작 → 장시간 운영 시 메모리 누수 가능

6. **service_category 마이그레이션 미완**: schema.sql 원본에 없고 ALTER로만 추가 → 신규 DB 초기화 시 컬럼 누락 가능성
