# DASH 데이터베이스 스키마 및 데이터 흐름

> 최종 업데이트: 2026-05-21  
> 서버: Railway (MySQL)  
> 암호화 정책: 상담 내용은 E2EE(AES-256-CBC). 서버는 암호문만 보관하며 복호화 불가.

---

## 목차

1. [전체 테이블 관계도](#1-전체-테이블-관계도)
2. [테이블 상세](#2-테이블-상세)
   - [dash_users](#dash_users)
   - [cases](#cases)
   - [counselors](#counselors)
   - [service_drafts](#service_drafts)
   - [notifications](#notifications)
   - [user_key_vault](#user_key_vault)
   - [retention_policy_log](#retention_policy_log)
3. [데이터 흐름](#3-데이터-흐름)
4. [보안 및 암호화 구조](#4-보안-및-암호화-구조)
5. [데이터 보존 정책](#5-데이터-보존-정책)
6. [관리자 조회 쿼리 모음](#6-관리자-조회-쿼리-모음)

---

## 1. 전체 테이블 관계도

```
dash_users (계정)
  │
  ├─── counselors (담당 상담원 목록)
  │
  ├─── cases (사례)
  │      └─── service_drafts (상담 기록 / DB)
  │               └── reviewer_user_id → dash_users (리뷰어)
  │
  ├─── notifications (알림)
  │
  └─── user_key_vault (PIN 암호화 볼트)
```

**Foreign Key 관계 요약**

| 자식 테이블 | 컬럼 | 참조 |
|---|---|---|
| `cases` | `user_id` | `dash_users.id` |
| `cases` | `counselor_id` | `counselors.id` |
| `counselors` | `user_id` | `dash_users.id` |
| `service_drafts` | `case_id` | `cases.id` |
| `service_drafts` | `reviewer_user_id` | `dash_users.id` |
| `notifications` | `user_id` | `dash_users.id` |
| `user_key_vault` | `user_id` | `dash_users.id` |

---

## 2. 테이블 상세

---

### dash_users

**역할**: 앱 사용자 계정. Firebase Auth UID를 PK로 사용.

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | VARCHAR(128) | PRIMARY KEY | Firebase Auth UID |
| `email` | VARCHAR(255) | NOT NULL | Google 계정 이메일 |
| `name` | VARCHAR(100) | NULL | 앱 내 닉네임 (Firebase displayName과 별도 관리) |
| `organization_id` | VARCHAR(64) | DEFAULT `'DEFAULT_ORG'` | 기관 ID (현재 단일 기관) |
| `fcm_token` | TEXT | NULL | FCM 푸시 토큰. 같은 기기에서 계정 전환 시 이전 계정 토큰 자동 NULL 처리 |
| `public_key` | TEXT | NULL | RSA 공개키 (E2EE 키 공유용, 미래 확장) |
| `last_login_at` | DATETIME | NULL | 마지막 로그인 시각 |
| `login_count` | INT | DEFAULT 0 | 누적 로그인 횟수 |

**주요 동작**
- 로그인 시 `ON DUPLICATE KEY UPDATE`로 upsert
- FCM 토큰 등록 시 동일 토큰을 가진 다른 계정의 `fcm_token`을 NULL로 초기화 → 다기기 다계정 알림 오수신 방지

---

### cases

**역할**: 아동 사례 단위. 상담원 1명이 여러 사례를 가짐.

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | VARCHAR(64) | PRIMARY KEY | 클라이언트에서 생성한 UUID |
| `user_id` | VARCHAR(128) | NOT NULL | 사례 소유 상담원 (→ `dash_users.id`) |
| `case_name` | VARCHAR(255) | NOT NULL | 아동 이름 |
| `dong` | VARCHAR(100) | NOT NULL | 담당 동 |
| `counselor_id` | VARCHAR(64) | NULL | 담당 상담원 (→ `counselors.id`). NULL이면 첫 번째 상담원에 귀속 |
| `target_system_code` | VARCHAR(50) | DEFAULT `'NCADS_V2'` | 연계 시스템 코드 |
| `created_at` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP | 생성 시각 |

---

### counselors

**역할**: 사용자가 관리하는 담당 상담원 목록. 기본값으로 자기 자신(`is_self=1`)이 생성됨.

```sql
CREATE TABLE IF NOT EXISTS counselors (
  id         VARCHAR(64)  PRIMARY KEY,
  user_id    VARCHAR(128) NOT NULL,
  name       VARCHAR(100) NOT NULL,
  is_self    TINYINT(1)   DEFAULT 0,   -- 1 = 본인('내 사례')
  sort_order INT          DEFAULT 0,
  created_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_counselor_user (user_id)
)
```

| 컬럼 | 설명 |
|---|---|
| `id` | 클라이언트에서 생성한 UUID |
| `user_id` | 소유 상담원 |
| `name` | 표시 이름 |
| `is_self` | `1` = 본인 사례("내 사례"). 앱에서 기본 생성 |
| `sort_order` | 목록 정렬 순서 |

---

### service_drafts

**역할**: 상담 기록(DB) 본체. DASH의 핵심 데이터. 내용은 AES-256 암호화.

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | INT | AUTO_INCREMENT PK | 서버 생성 ID |
| `case_id` | VARCHAR(64) | NOT NULL | 속한 사례 (→ `cases.id`) |
| `share_token` | VARCHAR(64) | NULL | 공유 링크 토큰. 앱에서 UUID로 생성 |
| `status` | VARCHAR(20) | NOT NULL | `Draft` / `Synced` / `Reviewed` / `Injected` |
| `target` | VARCHAR(255) | DEFAULT `''` | 서비스 대상 (예: 피해아동) |
| `provision_type` | VARCHAR(100) | NOT NULL | 제공 유형 |
| `method` | VARCHAR(100) | NOT NULL | 제공 방법 (방문/전화 등) |
| `service_type` | VARCHAR(100) | NOT NULL | 서비스 유형 |
| `service_category` | VARCHAR(100) | DEFAULT `''` | 서비스 세부목표(대분류) |
| `service_name` | VARCHAR(255) | NOT NULL | 서비스명 |
| `location` | VARCHAR(255) | NOT NULL | 장소 |
| `start_time` | DATETIME | NULL | 서비스 시작 시각 |
| `end_time` | DATETIME | NULL | 서비스 종료 시각 |
| `service_count` | VARCHAR(20) | NOT NULL | 제공 횟수 |
| `travel_time` | INT | NOT NULL | 이동 시간(분) |
| `service_description` | TEXT | DEFAULT `''` | 서비스 내용 **(평문 폴백, 신규 레코드는 항상 빈 값)** |
| `agent_opinion` | TEXT | DEFAULT `''` | 상담원 소견 **(평문 폴백)** |
| `encrypted_blob` | LONGTEXT | NULL | AES-256-CBC 암호문. 형식: `base64(IV):base64(ciphertext)` |
| `encryption_key` | VARCHAR(255) | NULL | **항상 NULL** (레거시 컬럼 보존용. E2EE 이전 구조 흔적) |
| `reviewer_user_id` | VARCHAR(36) | NULL | 리뷰한 상담원 (→ `dash_users.id`) |
| `share_expires_at` | DATETIME | NULL | 공유 링크 만료일 (현재 미사용, 확장 예정) |
| `created_at` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP | 생성 시각 |
| `updated_at` | DATETIME | NULL | 마지막 수정 시각 |
| `reviewed_at` | DATETIME | NULL | 리뷰 완료 시각 |

**status 값 흐름**

```
Draft  →  Synced  →  Reviewed  →  Injected
  (앱저장)   (서버동기화)  (리뷰완료)    (NCADS 자동입력 완료)
```

**encrypted_blob 구조**
```
"<IV(base64)>:<ciphertext(base64)>"
예: "xGC7hQ/MG0pd3bQn1cPY9w==:yJAAMQ..."
```
- 키는 서버에 없음. 유저의 PIN Vault에서만 복호화 가능.
- `service_description` / `agent_opinion`은 암호화 전 평문 필드로도 저장되나, 신규 레코드는 `encrypted_blob`에만 실제 내용이 있음.

---

### notifications

**역할**: 상담원에게 전달되는 앱 내 알림.

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | INT | AUTO_INCREMENT PK | |
| `user_id` | VARCHAR(128) | NOT NULL | 알림 수신 상담원 (→ `dash_users.id`) |
| `case_name` | VARCHAR(255) | NOT NULL | 관련 아동 이름 |
| `record_token` | VARCHAR(64) | NOT NULL | 관련 `service_drafts.share_token` |
| `message` | TEXT | NOT NULL | 알림 메시지 본문 |
| `is_read` | TINYINT(1) | DEFAULT 0 | `0` = 미읽음, `1` = 읽음 |
| `created_at` | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP | |

**동작 규칙**
- 리뷰 완료 시 동일 `record_token`의 기존 미읽음 알림을 `is_read=1`로 일괄 처리 → 최신 알림 1건만 뱃지 카운트에 반영
- FCM 푸시 페이로드의 `target_user_id`와 현재 로그인 계정이 다를 경우 앱에서 무시 (다기기 다계정 보호)

---

### user_key_vault

**역할**: PIN으로 암호화된 유저의 E2EE 키 묶음 (Zero-Knowledge 구조).

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `user_id` | VARCHAR(128) | PRIMARY KEY | → `dash_users.id` |
| `encrypted_vault` | LONGTEXT | NULL | PIN으로 암호화된 `{ share_token: encryption_key }` JSON |
| `salt` | VARCHAR(255) | NULL | 키 유도 함수(PBKDF2)용 Salt |

**구조 설명**
```
PIN  →  PBKDF2(PIN, salt)  →  AES-256 키
→  encrypt({ share_token_1: enc_key_1, share_token_2: enc_key_2, ... })
→  encrypted_vault (서버 저장)
```
- 서버는 `encrypted_vault`를 저장/전달만 함. 내용 열람 불가.
- 앱 재설치 시 이 테이블에서 볼트를 받아 기존 PIN으로 복호화 → 키 복구.

---

### retention_policy_log

**역할**: 개인정보 자동 파기 이력 감사 로그 (개인정보보호법 제21조 근거).

```sql
CREATE TABLE IF NOT EXISTS retention_policy_log (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  target_table  VARCHAR(64)  NOT NULL COMMENT '파기 대상 테이블',
  deleted_count INT          NOT NULL DEFAULT 0 COMMENT '파기된 레코드 수',
  cutoff_date   DATE         NOT NULL COMMENT '파기 기준일',
  law_basis     VARCHAR(255) NOT NULL COMMENT '법적 근거',
  executed_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) COMMENT='개인정보 자동 파기 이력';
```

---

## 3. 데이터 흐름

### 3-1. 신규 상담 기록 작성

```
[Flutter 앱]
  1. 폼 입력 완료
  2. SecureStorage에서 share_token에 대응하는 encryption_key 조회
     (없으면 random 16바이트 생성 → base64url 인코딩)
  3. AES-256-CBC 암호화
     key = encryptionKey.padRight(32)
     iv  = random 16바이트
     encrypted_blob = base64(iv) + ":" + base64(ciphertext)
  4. POST /api/records
     { case_id, share_token, encrypted_blob,
       service_description: "", agent_opinion: "",  ← 평문은 빈값
       target, method, ... }

[서버]
  5. service_drafts INSERT (status='Synced')
  6. cases에 해당 case_id 없으면 INSERT
  7. 응답: { id, share_token }

[Flutter 앱]
  8. SecureStorage keyMap에 { share_token: encryption_key } 저장
  9. user_key_vault에 전체 keyMap을 PIN 암호화하여 백업 (vault sync)
```

### 3-2. 공유 링크 생성 및 리뷰어 열람

```
[Flutter 앱]
  1. SecureStorage에서 encryption_key 조회
  2. 공유 URL 생성:
     https://dash.qpon/?token={share_token}#key={encryption_key}
     (# 이후 fragment는 서버 로그에 남지 않음)
  3. 클립보드 복사

[리뷰어 브라우저]
  4. URL 접속 → 구글 로그인 (GIS + signInWithCredential)
  5. POST /api/records/reviewer-login/{token}
     → 서버: authAttempts Map에 { verified: true, uid } 저장
     → 응답: { ok: true, isOwner: bool }
  6. GET /api/records/share/{token}
     → 서버: authAttempts 검증 후 service_drafts 데이터 반환
  7. 브라우저: URL fragment에서 key 추출 → AES 복호화 → 화면 표시

[리뷰 완료 시]
  8. POST /api/records/reviewed/{token}
     { encrypted_blob: 수정된_암호문 }
  9. 서버: status='Reviewed', reviewer_user_id 업데이트
 10. notifications INSERT (소유 상담원에게)
 11. FCM 푸시 전송 (소유 상담원의 fcm_token으로)
```

### 3-3. 앱 재설치 / 새 기기 로그인

```
[Flutter 앱]
  1. Google 로그인 성공
  2. GET /api/users/{uid} → 200이면 기존 사용자
     → 로컬 consent_done_{uid} 복원 → 온보딩 스킵
  3. GET /api/users/vault/{uid}
     → encrypted_vault, salt 수신
  4. VaultRecoveryScreen: 기존 PIN 입력
     → PBKDF2(PIN, salt) → AES 복호화 → keyMap 복원
     → SecureStorage에 키 저장
```

### 3-4. Chrome 확장프로그램 자동 입력 (NCADS)

```
[확장프로그램]
  1. getAuthToken (Chrome 프로필 계정)
  2. GET /api/records (Firebase 인증 포함)
  3. 서버: status='Synced' OR 'Reviewed' 레코드 반환
  4. NCADS 입력 폼에 데이터 자동 입력
  5. PUT /api/records/{id} { status: 'Injected' }
```

---

## 4. 보안 및 암호화 구조

### E2EE 키 흐름

```
기기 내부 (SecureStorage)
  encryptionKey (랜덤 16바이트 → base64url, 패딩 제거)
       │
       ├──→ 레코드 암호화 시 사용
       │      AES-256-CBC key = encryptionKey.padRight(32)
       │
       └──→ 공유 URL fragment (#key=...) 로 리뷰어에게 전달
              서버 로그에 절대 남지 않음

서버 (MySQL)
  user_key_vault.encrypted_vault
    = AES-256-CBC( JSON.stringify(keyMap), PBKDF2(PIN, salt) )
    ← 서버는 복호화 불가
```

### authAttempts (서버 인메모리)

- 리뷰어 웹 접속 세션 관리용 `Map<token, { verified, verifiedAt, uid }>`
- **서버 재시작 시 초기화됨** → 재로그인 필요
- 유효 시간: 4시간

---

## 5. 데이터 보존 정책

| 테이블 | 보존 기간 | 파기 방식 | 법적 근거 |
|---|---|---|---|
| `service_drafts` | 5년 | 매일 02:00 KST 자동 DELETE | 아동복지법 제28조 |
| `notifications` | 1년 | 매일 02:00 KST 자동 DELETE | 내부 정책 |
| `dash_users` | 탈퇴 시 즉시 | 회원 탈퇴 API 호출 | 개인정보보호법 제21조 |
| `user_key_vault` | 탈퇴 시 즉시 | 회원 탈퇴 API 호출 | 개인정보보호법 제21조 |
| `retention_policy_log` | 영구 보존 | 파기 안 함 | 증빙 목적 |

> ⚠️ 파기된 데이터는 복구 불가. 서버 백업도 없음.  
> 파기 이력은 `retention_policy_log` 에서 건수/날짜만 확인 가능 (내용 없음).

---

## 6. 관리자 조회 쿼리 모음

> Railway 콘솔 또는 MySQL 클라이언트에서 직접 실행.

### 특정 유저의 전체 기록 조회

```sql
SELECT
  sd.id,
  c.case_name,
  sd.status,
  sd.share_token,
  sd.created_at,
  sd.updated_at,
  CASE WHEN sd.encrypted_blob IS NOT NULL THEN 'E2EE' ELSE 'plain' END AS enc_type
FROM service_drafts sd
JOIN cases c ON sd.case_id = c.id
JOIN dash_users u ON c.user_id = u.id
WHERE u.email = '조회할이메일@gmail.com'
ORDER BY sd.created_at DESC;
```

### 전체 유저 현황

```sql
SELECT
  u.email,
  u.name,
  u.last_login_at,
  COUNT(DISTINCT c.id) AS case_count,
  COUNT(DISTINCT sd.id) AS draft_count
FROM dash_users u
LEFT JOIN cases c ON c.user_id = u.id
LEFT JOIN service_drafts sd ON sd.case_id = c.id
GROUP BY u.id
ORDER BY u.last_login_at DESC;
```

### 파기 이력 확인

```sql
SELECT * FROM retention_policy_log ORDER BY executed_at DESC;
```

### 볼트 백업 현황 (복구 가능 여부)

```sql
SELECT
  u.email,
  CASE WHEN v.encrypted_vault IS NOT NULL THEN '백업있음' ELSE '백업없음' END AS vault_status
FROM dash_users u
LEFT JOIN user_key_vault v ON v.user_id = u.id;
```

### 특정 share_token으로 레코드 확인

```sql
SELECT
  sd.id, sd.status, sd.created_at,
  c.case_name,
  u.email AS owner_email,
  ru.email AS reviewer_email
FROM service_drafts sd
JOIN cases c ON sd.case_id = c.id
JOIN dash_users u ON c.user_id = u.id
LEFT JOIN dash_users ru ON sd.reviewer_user_id = ru.id
WHERE sd.share_token = '토큰값';
```
