# DASH 앱 Firebase Analytics — 화면 및 이벤트 정의

> Firebase Console 경로:
> - **화면 보고서**: Analytics → 참여도 → 페이지 및 화면
> - **이벤트 보고서**: Analytics → 참여도 → 이벤트
> - **실시간 모니터링**: Analytics → DebugView (기기에서 디버그 모드 활성화 필요)

---

## 1. 화면 (Screen Views)

Firebase "페이지 및 화면" 보고서의 `화면 이름` 열에서 아래 값으로 필터링합니다.

| screen_name | screen_class | 실제 화면 | 진입 시점 |
|---|---|---|---|
| `login` | `LoginScreen` | 구글 로그인 화면 | 앱 최초 실행 또는 로그아웃 후 |
| `consent` | `ConsentScreen` | 서비스 이용 동의 화면 | 로그인 후 최초 1회 |
| `onboarding_0` | `OnboardingScreen` | 온보딩 1페이지 — 서비스 소개 | 동의 완료 후 또는 첫 실행 |
| `onboarding_1` | `OnboardingScreen` | 온보딩 2페이지 — 확장프로그램 연동 | 온보딩 스와이프 |
| `onboarding_2` | `OnboardingScreen` | 온보딩 3페이지 — PC 자동 기입 흐름 | 온보딩 스와이프 |
| `onboarding_3` | `OnboardingScreen` | 온보딩 4페이지 — 완료 | 온보딩 스와이프 |
| `home` | `HomeScreen` | 홈 화면 — 사례 목록 및 DB 목록 | 온보딩 완료 또는 앱 재진입 |
| `create_case` | `CreateCaseScreen` | 사례 생성 화면 | 홈에서 "사례 생성" 탭 |
| `form` | `FormScreen` | DB 작성/수정 화면 | 홈에서 사례 선택 후 |
| `user_guide` | `UserGuideScreen` | 사용법 안내 화면 | 홈 설정 메뉴에서 진입 |
| `security_detail` | `SecurityDetailScreen` | 암호화 구조 안내 화면 | 동의 화면 또는 설정에서 진입 |
| `privacy_policy` | `PrivacyPolicyScreen` | 개인정보처리방침 화면 | 홈 설정 메뉴에서 진입 |

### 보고서 해석 팁

- `onboarding_0` 진입 수 대비 `onboarding_complete` 이벤트 수를 비교하면 **온보딩 이탈률** 파악 가능
- `consent` 진입 수 대비 `consent_complete` 이벤트 수로 **동의 완료율** 파악 가능
- `form` 진입 수 대비 `dbrecord_saved` 이벤트 수로 **DB 저장 완료율** 파악 가능

---

## 2. 이벤트 (Custom Events)

Firebase "이벤트" 보고서의 `이벤트 이름` 열에서 아래 값으로 확인합니다.

### 인증

| 이벤트 이름 | 의미 | 파라미터 |
|---|---|---|
| `login_success` | 구글 로그인 성공 | — |
| `login_failure` | 구글 로그인 실패 | `reason`: 에러 메시지 |

### 온보딩 / 동의

| 이벤트 이름 | 의미 | 파라미터 |
|---|---|---|
| `onboarding_complete` | 온보딩 끝까지 완료 | — |
| `onboarding_skip` | 온보딩 중간 건너뜀 | `from_page`: 건너뛴 페이지 번호 |
| `consent_complete` | 서비스 이용 동의 완료 | `marketing_agreed`: 1(동의) / 0(거부) |

### 사례 / DB

| 이벤트 이름 | 의미 | 파라미터 |
|---|---|---|
| `case_created` | 새 사례 생성 완료 | — |
| `dbrecord_saved` | DB 저장 및 서버 전송 성공 | `provision_type`, `target`, `has_service_description`, `has_agent_opinion` |
| `dbrecord_sync_success` | 서버 동기화 성공 | — |
| `dbrecord_sync_failure` | 서버 동기화 실패 | `reason`: 실패 원인 |

### PIN / 보안

| 이벤트 이름 | 의미 | 파라미터 |
|---|---|---|
| `pin_set` | PIN 최초 설정 | — |
| `pin_entered` | PIN 입력 시도 | — |
| `link_copied` | 공유 링크 클립보드 복사 | — |
| `link_shared` | 공유 링크 공유 (미사용 예약) | — |

### 앱 상태

| 이벤트 이름 | 의미 | 파라미터 |
|---|---|---|
| `app_foregrounded` | 앱이 백그라운드에서 포그라운드로 전환 | — |
| `offline_banner_shown` | 서버 연결 끊김 → 오프라인 배너 노출 | — |
| `notification_received` | 푸시 알림 수신 | `type`: 알림 제목 |

---

## 3. Firebase Console 에서 빠르게 확인하는 법

### 특정 화면 진입자 수 보기
1. Analytics → 참여도 → 페이지 및 화면
2. `화면 이름` 열에서 원하는 값 클릭 (예: `form`)

### 온보딩 이탈 구간 파악
1. Analytics → 참여도 → 이벤트
2. `onboarding_skip` 클릭 → `from_page` 파라미터 분포 확인

### 실시간 테스터 행동 보기 (DebugView)
1. 테스터 기기에서 터미널 실행 후:
   ```
   adb shell setprop debug.firebase.analytics.app com.dash.mobile.yunsoo
   ```
2. Firebase Console → Analytics → DebugView

> DebugView는 기기 재부팅 시 초기화됩니다. 테스트할 때마다 재실행 필요.

---

## 4. 추후 추가 권장 이벤트

현재 미수집이지만 서비스 분석에 유용할 항목들:

| 이벤트 | 설명 |
|---|---|
| `db_draft_deleted` | DB 임시저장 삭제 |
| `extension_guide_viewed` | 확장프로그램 연동 안내 조회 |
| `pin_auth_success` / `pin_auth_failure` | PIN 인증 성공/실패 구분 |
| `case_deleted` | 사례 삭제 |
