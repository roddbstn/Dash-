# Dash 시스템 아키텍처 및 데이터 흐름 설계 (v1.5)

**버전**: v1.5 (Production Hybrid Pipeline)  
**최근 업데이트**: 2026-05-30 (기술 스택 현행화)  
**상태**: 운영 중

---

## 1. 시스템 개요 (System Architecture)

Dash v1.5는 상담원이 현장에서 기록한 데이터가 사무실의 PC 시스템에 안전하고 직관적으로 도달할 수 있도록 설계된 **'하이브리드 동기화 파이프라인'** 모델입니다.

### 1.1 핵심 구성 요소
1.  **Dash Mobile (Flutter/Dart)**: 상담 현장에서 데이터를 입력하고, *(Phase 2: AI 요약 예정)* 로컬에서 데이터를 암호화합니다.
2.  **Dash Extension (Chrome MV3)**: 암호화된 데이터를 수신하여 복호화하고, 타겟 시스템(국가아동학대정보시스템)의 DOM에 데이터를 직접 주입합니다.
3.  **Dash Cloud Service (Express.js + MySQL)**: 사용자 인증(Firebase Admin), 암호화된 데이터의 릴레이, SSE 실시간 알림을 담당합니다. (E2EE를 통해 원문 데이터는 서버에서 조회 불가)

---

## 2. 데이터 흐름 설계 (Data Flow)

데이터는 생성부터 주입까지 **보안(Security)**과 **정확성(Accuracy)**을 유지하며 흐릅니다.

### 2.1 주요 파이프라인
1.  **[현장/입력]**: 상담원이 Mobile App에서 아동별 서비스 정보를 입력합니다.
2.  **[암호화/전송]**: 입력된 데이터는 기기 내부 키를 사용하여 **AES-256**으로 암호화된 후 Cloud DB로 전송됩니다.
3.  **[동기화/수신]**: PC 확장 프로그램이 클라우드에서 암호화된 레코드를 실시간으로 감지(Real-time Subscription)합니다.
4.  **[복호화/검토]**: 확장 프로그램 내부에서 데이터를 복호화하여 사이드 패널에 리스트업합니다.
5.  **[매핑/주입]**: 사용자가 '주입' 버튼을 누르면, 현재 열려 있는 탭의 DOM 구조를 분석하여 매핑된 ID값에 데이터를 자동으로 입력(`dispatchEvent`)합니다.

---

## 3. 시스템별 폴더 구조 및 역할 (Folder Structure)

| 폴더명 | 시스템 지칭 | 주요 역할 |
|---|---|---|
| `dash_mobile/lib/` | **Dash Mobile App** | Flutter/Dart 기반 앱. 현장 입력 UI, AES-256 E2EE 암호화, Firebase Auth, SSE 실시간 동기화 담당. |
| `dash_extension/extension/` | **Dash PC Extension** | Chrome MV3 확장 프로그램. 사이드 패널 UI(`sidepanel.js`), DOM 주입(`content.js`), PC 로컬 복호화 담당. |
| `dash_mobile/server/` | **Dash Cloud Service** | Express.js + MySQL 백엔드. API 엔드포인트, SSE 브로드캐스트, Firebase Admin 인증, FCM 푸시 알림. |
| `dash_mobile/server/reviewer_site/` | **Reviewer Web** | 공유 링크 열람 및 편집 웹 페이지. E2EE 복호화(CryptoJS), 이름 인증, 내용 수정 저장. |
| `dash_extension/md/` | **Documentation** | 기획서(PRD), 아키텍처 설계, 기술 사양서(Tech Spec) 보관. |

---

## 4. 데이터베이스 설계 (Database Schema)

서버는 **MySQL** 단독 운영합니다 (Railway 호스팅). 필드 매핑은 DB 테이블이 아닌 `extension/core/config.js`에 하드코딩되어 있습니다.

### 4.1 `dash_users` (사용자 테이블)
- **id (VARCHAR)**: Firebase UID (기본키)
- **email**: 사용자 이메일
- **name**: 앱에서 설정한 닉네임
- **fcm_token**: FCM 푸시 알림 토큰
- **pin_hash**: PIN 해시 (vault 잠금용)
> ⚠️ RSA 공개키 컬럼 미사용. E2EE 키 관리는 모바일 기기의 PIN Vault 방식으로 구현됨

### 4.2 `cases` (사례 관리 테이블)
- **id (INT, AUTO_INCREMENT)**: 사례 고유 번호
- **user_id**: 담당 상담원 Firebase UID
- **case_name**: 마스킹된 아동 이름 (예: 강O정)
- **dong**: 소속 동/지역
- **target_system_code**: 'NCADS_v2' (하드코딩)

### 4.3 `service_drafts` (상담 데이터 테이블)
- **id (INT, AUTO_INCREMENT)**: 레코드 고유 ID
- **case_id**: 연결된 사례 ID
- **share_token (VARCHAR, UNIQUE)**: 공유 링크 토큰
- **encrypted_blob (LONGTEXT)**: AES-256 암호화 JSON (Base64, `IV:CipherText` 형식)
- **service_description / agent_opinion**: 복호화 실패 대비 평문 fallback (선택적)
- **status**: 상태값 (Draft → Synced → Reviewed → Injected)
- **reviewer_user_id**: 수정한 상급자 UID
- **created_at / updated_at**: 생성/수정 일시

### 4.4 `record_edit_history` (수정 이력 테이블)
- **share_token**: 대상 레코드 토큰
- **editor_user_id / editor_name**: 수정자
- **action**: 행위 (saved, reviewed, injected)
- **service_description_before / agent_opinion_before**: 수정 전 스냅샷
- **service_description_snapshot / agent_opinion_snapshot**: 수정 후 스냅샷

### 4.5 필드 매핑
국가아동학대정보시스템 HTML 필드 ID ↔ Dash 데이터 매핑은 **`extension/core/config.js`**에 관리됩니다. (DB 테이블 아님 — 시스템 업데이트 시 config.js 수정으로 빠른 패치 가능)

---

## 5. 버전 체계 정의 (Version Scheme)

| 구분 | 현재 버전 | 비고 |
|---|---|---|
| **Chrome 확장 프로그램** | 3.5.x | `manifest.json`의 `version` 필드 기준. Chrome Web Store 배포 단위 |
| **Flutter 모바일 앱** | `pubspec.yaml`의 `version` 기준 | |
| **서버 (Express)** | 별도 버전 없음 | git commit 해시로 추적 |
| **기획/설계 문서** | v1.5 (이 문서) | 아키텍처 변경 시 문서 버전 증가 |

> **이전 버전 명칭 정리**: plan.md에서 언급된 "v2.0"은 Extension-only 초기 모델(2026-02-27)의 문서 버전이며, 현재 아키텍처(모바일+Extension+클라우드 통합)와 무관합니다. 현행 아키텍처 기준 문서는 이 파일(v1.5)과 `plan.md` (2026-05-30 현행화)를 기준으로 합니다.

## 6. 향후 확장성 (Future Scalability)

- **AI 분석 레이어**: 클로바노트 등 외부 텍스트를 AI가 분석하여 `dash_records`의 필드를 자동으로 채우는 로직 추가 예정.
- **멀티 브라우저 지원**: Edge, Whale 등 Chromium 기반 브라우저로의 확장.
- **기관 통계 모듈**: 입력 완료된 데이터를 기반으로 상담원별 업무 부하 통계 시각화.
