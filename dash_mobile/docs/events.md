# DASH Mobile — Analytics Events 정의서

> **수집 도구**: Firebase Analytics  
> **구현 파일**: `lib/analytics_service.dart`  
> **최종 업데이트**: 2026-04-11

---

## 우선순위 랭킹

서비스의 핵심 가치(현장에서 DB 작성 → 서버 전송 → 리뷰어 공유)를 기준으로 중요도를 판단했습니다.

| 순위 | 이벤트 | 이유 |
|:----:|--------|------|
| 🥇 1 | `dbrecord_saved` | 서비스의 핵심 행동. 이 이벤트가 곧 실제 업무 사용량 |
| 🥈 2 | `login_success` / `login_failure` | DAU 근사치 + 로그인 장벽 파악 |
| 🥉 3 | `dbrecord_sync_failure` | 동기화 실패 = 데이터 유실 위험. 즉각 대응 필요 |
| 4 | `consent_complete` | 온보딩 퍼널 시작점. 여기서 이탈하면 아무것도 안 됨 |
| 5 | `case_created` | 사례 등록 = 실질적 서비스 진입 |
| 6 | `link_copied` | 리뷰어 공유 전환율. 공유 안 하면 검토 단계 막힘 |
| 7 | `onboarding_skip` + `from_page` | 어떤 페이지에서 이탈하는지 → 온보딩 개선 근거 |
| 8 | `onboarding_complete` | 온보딩 완주율 측정 |
| 9 | `pin_set` | PIN 설정 실패 빈도 → E2EE 도입 장벽 파악 |
| 10 | `offline_banner_shown` | 서버 불안정 빈도 → 인프라 안정성 지표 |
| 11 | `app_foregrounded` | 재방문 빈도 (세션 수 근사치) |
| 12 | `notification_received` | 알림 도달률 |
| 13 | `screen_view` (각 화면) | 화면별 방문 빈도 및 이탈 분석 |

---

## 이벤트 상세 정의

---

### 1. 인증 (Auth)

#### `login_success`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 실제 로그인 성공 유저 수 측정 (DAU 근사치) |
| **핵심 지표** | 일별/주별 로그인 성공 횟수, 활성 사용자 추이 |
| **수집 순간** | 구글 로그인 후 Firebase 인증 완료 직후 |
| **트리거 UI** | 로그인 화면 → '구글로 로그인' 버튼 |
| **파일** | `login_screen.dart:46` |
| **파라미터** | 없음 |

---

#### `login_failure`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 로그인 실패 원인 파악 및 빈도 모니터링 |
| **핵심 지표** | 실패율 (= failure / (success + failure)), 에러 유형별 분포 |
| **수집 순간** | 로그인 과정에서 예외(Exception) 발생 시 |
| **트리거 UI** | 로그인 화면 → '구글로 로그인' 버튼 (실패 케이스) |
| **파일** | `login_screen.dart:67` |
| **파라미터** | `reason` (String) — 에러 메시지 원문 |

---

### 2. 온보딩 (Onboarding)

#### `onboarding_complete`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 온보딩 완주율 측정 |
| **핵심 지표** | 완주율 (= complete / (complete + skip)) |
| **수집 순간** | 온보딩 마지막 페이지(4번째)에서 '시작하기' 버튼 탭 |
| **트리거 UI** | 온보딩 4번째 화면 → '시작하기' 버튼 |
| **파일** | `onboarding_screen.dart:24` |
| **파라미터** | 없음 |

---

#### `onboarding_skip`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 온보딩 중도 이탈 지점 파악 → 콘텐츠 개선 근거 |
| **핵심 지표** | 페이지별 이탈 분포 (`from_page` 값 기준) |
| **수집 순간** | 온보딩 1~3번째 화면에서 '건너뛰기' 탭 |
| **트리거 UI** | 온보딩 화면 우상단 → '건너뛰기' 텍스트 버튼 |
| **파일** | `onboarding_screen.dart:22` |
| **파라미터** | `from_page` (int) — 0: 1번째, 1: 2번째, 2: 3번째 화면에서 이탈 |

---

### 3. 동의 (Consent)

#### `consent_complete`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 서비스 동의 완료 전환율 측정, 마케팅 동의율 파악 |
| **핵심 지표** | 동의 완료율, 마케팅 동의 비율 |
| **수집 순간** | 필수 항목 3개 모두 동의 후 '동의하고 시작하기' 버튼 탭 |
| **트리거 UI** | 동의 화면 최하단 → '동의하고 시작하기' 버튼 |
| **파일** | `consent_screen.dart:56` |
| **파라미터** | `marketing_agreed` (int) — 1: 마케팅 동의, 0: 미동의 |

---

### 4. 사례 관리 (Case)

#### `case_created`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 사례 등록 수 측정 (서비스 실질 진입 지표) |
| **핵심 지표** | 유저당 평균 사례 수, 사례 등록 추이 |
| **수집 순간** | 사례 이름·동 입력 후 '등록' 버튼 탭, 서버 동기화 완료 직후 |
| **트리거 UI** | 사례 등록 화면 → '등록' 버튼 |
| **파일** | `create_case_screen.dart:103` |
| **파라미터** | 없음 |

---

### 5. DB 기록 (Record)

#### `dbrecord_saved`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 핵심 업무 행동(DB 작성 및 저장) 측정 |
| **핵심 지표** | 일별 저장 건수, 내용 입력 완성도 (서비스 내용·소견 기입율), 제공구분 분포 |
| **수집 순간** | 폼 작성 완료 후 서버 동기화 성공 직후 |
| **트리거 UI** | DB 수정 화면 → '저장' 버튼 |
| **파일** | `form_screen.dart:243` |
| **파라미터** | `provision_type` (String) — 제공구분 (제공/부가업무/거부) · `target` (String) — 대상자 전체 · `has_service_description` (int) — 서비스 내용 기입 여부 · `has_agent_opinion` (int) — 상담원 소견 기입 여부 |

---

#### `dbrecord_sync_success`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 서버 동기화 성공률 모니터링 |
| **핵심 지표** | 성공률 (= success / (success + failure)) |
| **수집 순간** | `ApiService.syncRecord()` 응답으로 `share_token` 정상 수신 시 |
| **트리거 UI** | DB 수정 화면 → '저장' 버튼 (내부 처리) |
| **파일** | `form_screen.dart:249` |
| **파라미터** | 없음 |

---

#### `dbrecord_sync_failure`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 동기화 실패 빈도 파악 → 데이터 유실 위험 감지 |
| **핵심 지표** | 동기화 실패 건수, 실패율 |
| **수집 순간** | `ApiService.syncRecord()` 결과 `share_token`이 null일 때 |
| **트리거 UI** | DB 수정 화면 → '저장' 버튼 (내부 처리, 실패 케이스) |
| **파일** | `form_screen.dart:262` |
| **파라미터** | `reason` (String) — 실패 원인 (`no_share_token`) |

---

#### `link_copied`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 리뷰어 공유 전환율 측정 |
| **핵심 지표** | `dbrecord_saved` 대비 `link_copied` 비율 (공유 전환율) |
| **수집 순간** | 공유 링크가 클립보드에 복사된 직후 |
| **트리거 UI** | DB 수정 화면 → 공유 아이콘(↗) 버튼 |
| **파일** | `form_screen.dart:455` |
| **파라미터** | 없음 |

---

### 6. 보안 · PIN

#### `pin_set`

| 항목 | 내용 |
|------|------|
| **수집 목적** | E2EE PIN 설정 완료율 측정 |
| **핵심 지표** | 최초 저장 시도 유저 중 PIN 설정 완료 비율 |
| **수집 순간** | PIN 설정 다이얼로그에서 번호 입력 후 확인 완료 시 |
| **트리거 UI** | '저장' 버튼 탭 → 자동 노출되는 PIN 설정 다이얼로그 → 확인 버튼 |
| **파일** | `form_screen.dart:212` |
| **파라미터** | 없음 |

---

### 7. 앱 상태 (App Lifecycle)

#### `app_foregrounded`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 재방문 빈도 측정 (세션 수 근사치) |
| **핵심 지표** | 일별 포그라운드 복귀 횟수, 유저당 평균 세션 |
| **수집 순간** | 앱이 백그라운드에서 포그라운드로 복귀할 때 |
| **트리거 UI** | 사용자가 앱 전환 후 다시 DASH 앱으로 돌아올 때 (UI 없음) |
| **파일** | `home_screen.dart:67` |
| **파라미터** | 없음 |

---

#### `offline_banner_shown`

| 항목 | 내용 |
|------|------|
| **수집 목적** | 서버 불안정 빈도 파악 → 인프라 품질 지표 |
| **핵심 지표** | 발생 빈도, 발생 시간대 |
| **수집 순간** | `_serverReachable`이 `true → false`로 전환되는 순간 |
| **트리거 UI** | 홈 화면 상단에 오프라인 배너 노출 (자동, UI 없음) |
| **파일** | `home_screen.dart:193` |
| **파라미터** | 없음 |

---

#### `notification_received`

| 항목 | 내용 |
|------|------|
| **수집 목적** | FCM 알림 도달률 및 알림 유형 파악 |
| **핵심 지표** | 알림 수신 건수, 알림 제목별 분포 |
| **수집 순간** | FCM 포그라운드 메시지 수신 시 |
| **트리거 UI** | 없음 (서버 푸시 알림 수신) |
| **파일** | `home_screen.dart:440` |
| **파라미터** | `type` (String) — 알림 제목 (예: '검토 완료', '공유 알림') |

---

### 8. 화면 진입 (Screen View)

| 이벤트 파라미터 | 화면 | 파일 | 수집 시점 |
|----------------|------|------|-----------|
| `screen_name: consent` | 동의 화면 | `consent_screen.dart:49` | `initState` |
| `screen_name: home` | 홈 화면 | `home_screen.dart:57` | `initState` |
| `screen_name: create_case` | 사례 등록 화면 | `create_case_screen.dart:28` | `initState` |
| `screen_name: form` | DB 수정 화면 | `form_screen.dart:64` | `initState` |
| `screen_name: user_guide` | 이용 안내 | `user_guide_screen.dart:18` | `initState` |
| `screen_name: security_detail` | 암호화 구조 안내 | `security_detail_screen.dart:19` | `build` (최초 1회) |

> **활용**: Firebase Console → Analytics → **Events** 탭에서 `screen_view` 이벤트 필터링 후 `screen_name` 파라미터로 분류.

---

## 핵심 퍼널 구성 가이드

Firebase Console → **Analytics → Funnels** 에서 아래 순서로 설정.

### 퍼널 1: 온보딩 전환 퍼널
```
login_success
  → screen_view {consent}
    → consent_complete
      → onboarding_complete
```
> 각 단계 이탈율로 온보딩 어느 구간이 약한지 파악.

### 퍼널 2: 핵심 업무 퍼널
```
case_created
  → screen_view {form}
    → dbrecord_saved
      → link_copied
```
> `dbrecord_saved` 후 `link_copied`까지 가는 비율 = 리뷰어 공유 전환율.

### 퍼널 3: 동기화 품질 퍼널
```
dbrecord_saved
  → dbrecord_sync_success  (성공)
  → dbrecord_sync_failure  (실패)
```
> 실패율이 5% 초과 시 서버 또는 네트워크 이슈 점검.

---

## Firebase 설정 체크리스트

- [ ] Firebase Console → Analytics → **DebugView** 에서 실시간 이벤트 수신 확인
- [ ] `adb shell setprop debug.firebase.analytics.app com.dash.mobile.yunsoo` 로 디버그 모드 활성화
- [ ] `dbrecord_saved` 이벤트를 **전환 이벤트(Conversion Event)** 로 등록
- [ ] `login_success` 이벤트를 기준으로 **사용자 속성(User Property)** 설정
- [ ] Funnel 1, 2, 3 구성
- [ ] BigQuery 연동 (향후 고급 분석 시)
