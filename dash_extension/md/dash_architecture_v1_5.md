# Dash 시스템 아키텍처 및 데이터 흐름 설계 (v1.5)

**버전**: v1.5 (Production Hybrid Pipeline)  
**최근 업데이트**: 2026-03-17  
**상태**: 구현 및 고도화 단계

---

## 1. 시스템 개요 (System Architecture)

Dash v1.5는 상담원이 현장에서 기록한 데이터가 사무실의 PC 시스템에 안전하고 직관적으로 도달할 수 있도록 설계된 **'하이브리드 동기화 파이프라인'** 모델입니다.

### 1.1 핵심 구성 요소
1.  **Dash Mobile (Expo/React Native)**: 상담 현장에서 데이터를 입력하고, AI 요약을 생성하며, 로컬에서 데이터를 암호화합니다.
2.  **Dash Extension (Chrome MV3)**: 암호화된 데이터를 수신하여 복호화하고, 타겟 시스템(국가아동학대정보시스템)의 DOM에 데이터를 직접 주입합니다.
3.  **Dash Cloud Service (Supabase/MySQL)**: 사용자 인증, 암호화된 데이터의 릴레이, 필드 매핑 템플릿 정보를 보관합니다. (E2EE를 통해 원문 데이터는 서버에서 조회 불가)

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
| `expo-mobile/` | **Dash Mobile App** | React Native 기반 앱. 현장 입력 UI, AI 요약 엔진 연동, 모바일 로컬 암호화 로직 담당. |
| `extension/` | **Dash PC Extension** | Chrome 확장 프로그램. 사이드 패널 UI, DOM 주입 핵심 로직(`content.js`), PC 로컬 복호화 담당. |
| `shared/` | **Core Utilities** | 암호화 알고리즘(E2EE), 공통 인터페이스(TypeScript), 데이터 검증 로직 등 플랫폼 공통 모듈. |
| `prototypes/` | **UI/UX Research** | 새로운 기능(예: Sticky Memo, AI 분석 UI)을 실제 구현 전 테스트하는 독립적 HTML/JS 실험장. |
| `scripts/` | **DevOps & Tools** | 빌드 자동화 스크립트, 데이터 마이그레이션 도구, 환경 설정 관리자. |
| `md/` | **Documentation** | 기획서(PRD), 아키텍처 설계, 기술 사양서(Tech Spec) 보관. |

---

## 4. 데이터베이스 설계 (Database Schema)

v1.5에서는 **Supabase(PostgreSQL/MySQL)**를 기반으로 실시간 동기화와 데이터 무결성을 보장합니다.

### 4.1 `dash_users` (사용자 테이블)
- **ID (UUID)**: 고유 식별자
- **Email**: 사용자 이메일
- **Organization_ID**: 소속 기관 ID (기관별 템플릿 연동용)
- **Public_Key**: E2EE용 RSA 공개키 (복호화 키는 절대 저장하지 않음)

### 4.2 `dash_cases` (사례 관리 테이블)
- **ID (Serial)**: 사례 고유 번호
- **User_ID**: 담당 상담원 식별자
- **Masked_Name**: 마스킹 처리된 아동 이름 (예: 강*정)
- **Target_System_Code**: 입력할 대상 시스템 식별 코드

### 4.3 `dash_records` (상담 데이터 테이블)
- **ID (Serial)**: 레코드 고유 ID
- **Case_ID**: 연결된 사례 ID
- **Encrypted_Blob (Text)**: AES-256으로 암호화된 JSON 데이터 (Base64)
- **Status**: 상태값 (Draft, Synced, Injected, Archived)
- **Created_At**: 생성 일시

### 4.4 `dash_field_mappings` (매핑 엔진 테이블)
- **System_ID**: 시스템 식별자 (예: NCADS_v2)
- **Mapping_JSON**: 필드 ID와 엑셀/앱 항목 간의 매핑 정보
- **Version**: 매핑 버전 (시스템 업데이트 대응용)

---

## 5. 향후 확장성 (Future Scalability)

- **AI 분석 레이어**: 클로바노트 등 외부 텍스트를 AI가 분석하여 `dash_records`의 필드를 자동으로 채우는 로직 추가 예정.
- **멀티 브라우저 지원**: Edge, Whale 등 Chromium 기반 브라우저로의 확장.
- **기관 통계 모듈**: 입력 완료된 데이터를 기반으로 상담원별 업무 부하 통계 시각화.
