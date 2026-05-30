# DASH E2E 테스트 — 병목/취약 구간 분석 보고서

## 분석 대상
- dash_mobile (Flutter)
- Reviewer Web (dash.qpon reviewer_site)
- Chrome Extension (Manifest v3)
- Backend API (Node.js/Express)

---

## 병목 구간 1: 온보딩 → 홈까지의 라우팅 분기

**위치**: `dash_mobile/lib/main.dart`

**문제**:
- Firebase Auth 상태 + `consent_done_<uid>` flag + 서버 사용자 존재 여부까지 비동기로 연쇄 확인
- 네트워크 느린 환경에서 로딩 스피너 없이 빈 화면 노출 가능성

**테스트 커버리지**: TC-MOB-001, TC-MOB-002

**권고**:
- `FutureBuilder` 또는 Riverpod의 `AsyncValue` 로딩 상태를 반드시 처리
- 각 라우팅 분기에 로딩 인디케이터 추가

---

## 병목 구간 2: E2EE 복호화 실패 시 UX

**위치**: `dash_mobile/server/reviewer_site/app.js` L93–132

**문제**:
- `encrypted_blob`이 있으나 URL fragment의 `key`가 누락된 경우 → `showEncNotice('no_key')` 호출
- 복호화 실패 시 `showEncNotice('decrypt_failed')` 호출
- **두 경우 모두 `renderUI(data)` 는 호출되어 빈 레코드 UI가 표시됨**
- 사용자는 "왜 내용이 비어있지?" 혼란 → UX 병목

**테스트 커버리지**: TC-RW-012, TC-RW-013

**권고**:
- 복호화 실패 시 `renderUI` 대신 전용 오류 화면(`state-error`) 표시
- `enc-notice` 영역을 더 눈에 띄게 처리

---

## 병목 구간 3: 인앱 브라우저(카카오톡) 차단 — iOS 탐지 미흡

**위치**: `dash_mobile/server/reviewer_site/app.js` L1–18

**문제**:
```js
const isMobile = /iPhone|iPad|Android/i.test(ua);
const isSafari = /Safari\//i.test(ua) && !/Chrome\//i.test(ua);
const isChrome = /Chrome\//i.test(ua) && !/Chromium/i.test(ua);
if (isMobile && !isSafari && !isChrome) return true;
```
- iOS 카카오톡 인앱 브라우저의 UA가 `KAKAOTALK` 문자열을 항상 포함하지 않을 수 있음
- 일부 버전에서 정규 Safari UA처럼 보이는 경우 → 차단 모달 미표시

**테스트 커버리지**: TC-RW-016, TC-RW-017

**권고**:
- `document.referrer` 또는 `window.navigator.standalone` 병행 체크
- 사용자 에이전트 기반이 아닌 딥링크/Universal Link로 전환 고려

---

## 병목 구간 4: Extension — PIN 볼트 검증 실패 시 무한 재시도

**위치**: `dash_extension/extension/sidepanel.js`

**문제**:
- 서버의 `/api/vault/:userId` 응답이 타임아웃되면 PIN 인증이 무기한 대기
- 재시도 로직 없이 로딩 스피너만 표시 가능성

**테스트 커버리지**: TC-EX-008, TC-EX-015

**권고**:
- 볼트 API 호출에 `AbortController` + 타임아웃(5초) 추가
- 실패 시 "잠시 후 다시 시도하세요" 안내 메시지 표시

---

## 병목 구간 5: SSE 연결 끊김 시 Extension 재연결 지연

**위치**: `dash_extension/extension/sidepanel.js`

**문제**:
- SSE(`/api/events`) 연결이 끊기면 기록 목록이 실시간 업데이트 안 됨
- 재연결 시도 간격이 길 경우 사용자가 수동 새로고침 필요

**테스트 커버리지**: TC-EX-015

**권고**:
- exponential backoff (1s → 2s → 4s → 최대 30s) 재연결 로직 추가
- 재연결 중 UI에 "연결 중..." 인디케이터 표시

---

## 병목 구간 6: 케이스 생성 → 폼 작성 전환 시 Draft 동기화

**위치**: `dash_mobile/lib/form_screen.dart`

**문제**:
- 폼 작성 중 앱이 백그라운드로 이동하면 임시 저장(draft) 타이밍 이슈
- `AppLifecycleState.paused` 핸들러에서 비동기 저장 시 완료 전 앱 종료 가능

**테스트 커버리지**: TC-MOB-031

**권고**:
- `WillPopScope` 또는 `NavigationObserver`에서 동기식 임시 저장 보장
- `isolate` 분리 없이 UI 쓰레드에서 먼저 로컬 저장 후 비동기 서버 업로드

---

## 병목 구간 7: 공유 링크 OG 메타태그 — SSR 미지원

**위치**: `dash_mobile/server/index.js` (GET /)

**문제**:
- 카카오톡에서 링크 공유 시 OG 이미지/제목 크롤링 → 서버가 `/?token=` 요청에 
  동적 OG 메타를 반환해야 하지만 현재 정적 HTML
- 토큰마다 다른 케이스명이 OG 제목에 반영 안 됨

**테스트 커버리지**: TC-RW-023

**권고**:
- Express에서 `/?token=:token` 요청 시 DB에서 케이스명 조회 → 동적 OG 메타 삽입
- 카카오톡 캐싱 갱신 주기 고려 (초기 공유 전 서버 배포 필요)

---

## 우선순위 요약

| 우선순위 | 병목 구간 | 영향도 | 수정 난이도 |
|---------|---------|-------|-----------|
| P0 | E2EE 복호화 실패 UX (구간 2) | 높음 | 낮음 |
| P0 | Extension PIN 타임아웃 미처리 (구간 4) | 높음 | 낮음 |
| P1 | 온보딩 라우팅 분기 로딩 (구간 1) | 중간 | 낮음 |
| P1 | SSE 재연결 로직 (구간 5) | 중간 | 중간 |
| P2 | 인앱 브라우저 탐지 iOS (구간 3) | 중간 | 중간 |
| P2 | Draft 동기화 타이밍 (구간 6) | 중간 | 중간 |
| P3 | OG 메타태그 동적화 (구간 7) | 낮음 | 높음 |
