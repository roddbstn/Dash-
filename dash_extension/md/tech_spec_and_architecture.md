# Dash (DBAuto) Tech Spec & Architecture
**버전**: v1.2.0 (하이브리드 파이프라인 아키텍처 반영)
**작성일**: 2026-03-13  
**대상**: 개발/유지보수 담당자 및 제품 이해관계자

---

## 1. 하이브리드 아키텍처 개요 (System Architecture)

Dash는 단순히 브라우저에서 동작하는 확장 프로그램을 넘어, 현장 기록부터 시스템 주입까지를 잇는 **'허브 앤 스포크(Hub-and-Spoke)'** 모델로 진화했습니다.

### 1.1 하이브리드 파이프라인 구조
1. **[모바일/Mobile] Data Source (PWA)**: 상담 현장에서 DB 양식에 맞춰 정보를 1차 입력하고 암호화하여 전송합니다.
2. **[서버/Server] E2EE Sync Layer (Firebase/Cloud)**: 개인정보를 식별할 수 없는 암호화된 상태(Zero-Knowledge)로 데이터를 중계/보관합니다.
3. **[PC/Extension] Data Injector**: 사무실 PC에서 암호화된 데이터를 복호화하여 타겟 시스템(아동학대망 등)의 DOM에 주입합니다.

### 1.2 계층 분리 원칙
* **`core/` (비즈니스 로직)**: 암호화/복호화 알고리즘, 필드 매핑 테이블, 상태 관리 로직.
* **`mobile/` (PWA UI)**: 현장 입력에 최적화된 모바일 폼 및 AI 요약 연동 레이어.
* **`adapters/` (인프라 연동)**: Chrome API, Firebase Sync, E2EE 키 관리 스토리지.
* **`content.js` (DOM 제어)**: 타겟 시스템의 DOM 요소 검색 및 자동 기입 로직.

---

## 2. 세부 기술 스택 (Technology Stack)

| 구분 | 사용 기술 | 선정 이유 및 특징 |
|------|-----------|--------------------|
| **코어 엔진** | **Chrome Extension (MV3)** | PC 브라우저 내 시스템 자동 기입 및 DOM 제어 전담 |
| **모바일 계층** | **Progressive Web App (PWA)** | 별도 설치 없이 URL 접속만으로 앱 환경 제공, 기기 내 로컬 저장 활용 |
| **보안 레이어** | **E2EE (AES-256 + RSA)** | 종단간 암호화를 통해 서버 관리자도 데이터를 볼 수 없는 보안 환경 구축 |
| **데이터 파싱** | **SheetJS / AI Parser** | 엑셀 데이터 및 구어체 상담 메모를 정형화된 JSON 데이터로 변환 |
| **동기화 채널** | **Websocket / Cloud Firestore** | 모바일과 PC 간의 데이터 실시간 동기화 (암호화된 상태 유지) |

---

## 3. 핵심 기술: 보안 연동 및 데이터 주입 (Core Mechanisms)

### 3.1 종단간 암호화(E2EE) 동기화 로직
현장 데이터의 민감성을 고려하여, Dash는 중앙 서버를 단순한 '암호화된 우체통'으로만 사용합니다.
- **키 생성**: 유저가 최초 가입/로그인 시 기기 고유의 개인키를 생성하여 기기 보안 저장소에 보관합니다.
- **암호화**: 모바일에서 저장 버튼 클릭 시, AES-256 알고리즘으로 데이터를 암호화하여 서버로 송신합니다.
- **복호화**: PC 확장 프로그램이 서버에서 데이터를 수신한 후, 기기 내 보관된 키로만 내용을 복원합니다.

### 3.2 URL Window 데이터 기입 로직 (Injection)
PC 확장 프로그램의 `content.js`는 수동 입력, 엑셀, 혹은 모바일 연동 데이터를 통합된 JSON Schema로 받아 DOM에 주입합니다.

#### 프레임워크 트리거 전략 (`smartFill`)
단순히 `value`를 변경하는 것이 아니라, 타겟 시스템이 사용 중인 JS 프레임워크(React, Vue 등)가 변경을 인식하도록 이벤트를 강제 발생시킵니다.
```javascript
function smartFill(id, value) {
    const el = document.getElementById(id);
    if (!el) return;
    el.value = value;
    // 프레임워크 상태 갱신 강제 (Input/Change 이벤트 트리거)
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    // 시각적 피드백
    el.classList.add('dash-success');
}
```

---

## 4. 데이터 흐름도 (Data Flow)

1. **[현장]**: 상담원이 모바일 Dash에서 특정 아동의 상담 정보 입력.
2. **[암호화]**: 기기 내 로컬 키로 데이터 암호화 (`x8fb2...`).
3. **[동기화]**: 클라우드 서버를 통해 PC로 암호화된 데이터 전송.
4. **[복호화]**: 사무실 PC의 Dash 확장 프로그램이 데이터를 수신하여 복문으로 변환.
5. **[주입]**: 타겟 시스템 창을 인식(`chrome.tabs.query`)하여 `content.js`로 데이터 전송 및 자동 기입 실행.

---

## 5. 개인정보 통제 원칙 (Safety by Design)

- **식별 데이터 배제**: 성명, 주민번호 등 극민감 정보는 자동 입력에서 제외하거나 마스킹 처리하여 유저의 수동 확인을 유도합니다.
- **휘발성 보관**: 주입이 완료된 데이터는 로컬 및 서버 스토리지에서 즉시 삭제하거나 아카이빙 처리하여 불필요한 보관을 최소화합니다.
