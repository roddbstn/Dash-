# dbauto — 기술 사양서 v2.0 (Chrome/Edge 확장 프로그램)

## 1. 프로젝트 개요

### 배경
아동보호전문기관 상담원들이 엑셀로 관리하는 문서 데이터를 `labelmaker.kr/app`에 수동으로 입력하는 반복 작업을 자동화한다.

### 목표
- 엑셀 파일을 드래그 앤 드롭하면 labelmaker.kr 폼에 자동 입력
- **Chrome/Edge 확장 프로그램** 방식으로 구현 → 디버깅 모드 불필요
- 상담원이 평소 쓰던 브라우저 그대로 사용 가능

### v1 → v2 전환 이유
| 항목 | v1 (Python CDP) | v2 (확장 프로그램) |
|---|---|---|
| 브라우저 요구사항 | 디버깅 모드 필수 | 일반 Chrome/Edge |
| 설치 방법 | Python + 터미널 | 확장 프로그램 설치 한 번 |
| Edge 지원 | 별도 작업 필요 | 동일 확장 사용 가능 |
| 상담원 부담 | 높음 | 낮음 |

---

## 2. 서비스 아키텍처

```
[상담원 PC]
│
├── Chrome / Edge (일반 모드)
│   ├── labelmaker.kr/app 탭 (열려 있음)
│   └── dbauto 확장 프로그램
│       ├── popup.html       ← 드래그 앤 드롭 UI
│       ├── popup.js         ← 엑셀 파싱 + UI 로직
│       ├── content.js       ← labelmaker.kr 폼 자동 입력
│       ├── background.js    ← 탭 관리 / 메시지 라우팅
│       └── manifest.json    ← 확장 프로그램 설정
│
└── 엑셀 파일 (라벨1.xlsx)
    └── 드래그 앤 드롭 → 확장 팝업으로
```

### 데이터 흐름
```
엑셀 파일 드롭
    → popup.js: SheetJS로 파싱
    → popup.js: 데이터 미리보기 표시
    → 사용자: "자동 입력" 클릭
    → background.js: labelmaker.kr 탭 찾기
    → content.js: DOM 조작으로 폼 자동 입력
    → content.js: 결과 반환
    → popup.js: 성공/실패 표시
```

---

## 3. 기술 스택

| 레이어 | 기술 | 이유 |
|---|---|---|
| 엑셀 파싱 | **SheetJS (xlsx.js)** | 브라우저 내장 JS 라이브러리, 서버 불필요 |
| UI | HTML/CSS/JS | 확장 팝업 |
| 폼 자동 입력 | Content Script (JS) | 페이지 DOM에 직접 접근 |
| 탭 관리 | Chrome Extension API | `chrome.tabs`, `chrome.scripting` |
| 브라우저 지원 | Chrome + Edge | Chromium 기반, 동일 확장 사용 |

---

## 4. 파일 구조

```
dbauto_test/
├── extension/               ← 확장 프로그램 폴더
│   ├── manifest.json        ← 확장 설정 (Manifest V3)
│   ├── popup.html           ← 팝업 UI (드래그 앤 드롭)
│   ├── popup.js             ← 팝업 로직 (엑셀 파싱, UI)
│   ├── content.js           ← labelmaker.kr 폼 자동 입력
│   ├── background.js        ← Service Worker (탭 관리)
│   ├── xlsx.min.js          ← SheetJS 라이브러리
│   └── icons/
│       ├── icon16.png
│       ├── icon48.png
│       └── icon128.png
├── tech_spec.md             ← 이 문서
├── 라벨1.xlsx               ← 테스트용 엑셀
└── plan 복사본.md
```

---

## 5. 엑셀 ↔ 폼 필드 매핑

| 엑셀 B열 | 내부 키 | 웹 폼 요소 | 타입 |
|---|---|---|---|
| 제목 | `title` | `#title` | contenteditable div |
| 생산연도 | `productionYear` | `#productionYear` | contenteditable div |
| 부서명 | `departmentName` | `#departmentName` | contenteditable div (줄바꿈 → `<br>`) |
| 분류번호 | `classificationCode` | `input[placeholder*="사업"]` | text input |
| 보존기간 | `retentionPeriod` | `select` | select dropdown |
| 관리번호 | `managementNumber` | `input[placeholder*="A-001"]` | text input |

---

## 6. 주요 구현 포인트

### 6-1. 엑셀 파싱 (SheetJS)
- B열 = 필드명, C열 = 값 형식
- `XLSX.read(arrayBuffer)` → 시트 순회 → 필드 매핑

### 6-2. Content Script 폼 입력
- `contenteditable` div: `innerText` 설정 + `input` 이벤트 디스패치
- `<input>`: `nativeInputValueSetter` + `input`/`change` 이벤트
- `<select>`: `nativeSelectValueSetter` + `change` 이벤트
- React 상태 동기화를 위해 반드시 네이티브 setter 사용

### 6-3. 탭 찾기 (background.js)
```js
chrome.tabs.query({ url: '*://labelmaker.kr/*' }, tabs => { ... })
```

### 6-4. Manifest V3 권한
```json
"permissions": ["tabs", "scripting", "activeTab"],
"host_permissions": ["*://labelmaker.kr/*", "*://www.labelmaker.kr/*"]
```

---

## 7. 설치 방법 (개발 버전)

1. Chrome/Edge 주소창에 `chrome://extensions` 입력
2. 우측 상단 **"개발자 모드"** 활성화
3. **"압축 해제된 확장 프로그램 로드"** 클릭
4. `dbauto_test/extension/` 폴더 선택
5. 툴바에 dbauto 아이콘 고정

---

## 8. 사용 방법

1. Chrome/Edge에서 `labelmaker.kr/app` 접속 및 로그인
2. 툴바의 **dbauto 아이콘** 클릭 → 팝업 열림
3. 팝업에 엑셀 파일 **드래그 앤 드롭** (또는 클릭하여 선택)
4. 파싱된 데이터 미리보기 확인
5. **"자동 입력 시작"** 클릭
6. labelmaker.kr 폼에 자동 입력 완료

---

## 9. 향후 확장

- **스토어 배포**: Chrome Web Store / Edge Add-ons 스토어 등록 (심사 필요)
- **다중 라벨**: 여러 행 → 여러 라벨 순차 입력
- **인쇄 자동화**: 입력 완료 후 인쇄 버튼 자동 클릭
- **다른 시스템 지원**: labelmaker.kr 외 다른 폼 시스템으로 확장
