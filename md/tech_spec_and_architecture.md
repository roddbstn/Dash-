# Dash (DBAuto) Tech Spec & Architecture
**작성일**: 2026-03-03  
**대상**: 개발/유지보수 담당자 및 제품 이해관계자

---

## 1. 아키텍처 개요 (Architecture Overview)

Dash 확장 프로그램은 무거운 빌드 도구나 프레임워크(React/Vue 등)를 배제하고, 가장 가볍고 빠른 **바닐라 자바스크립트(Vanilla JS)**를 기반으로 구축되었습니다. 확장 기능이 1,000줄 이상으로 커지는 상황에 대비하여 유지보수성을 극대화하기 위해 **경량화된 헥사고날(Hexagonal, Ports & Adapters) 아키텍처**를 채택했습니다.

### 계층 분리 원칙
* **`core/` (비즈니스 로직)**: 브라우저나 UI가 바뀌어도 절대 변하지 않는 핵심 매핑 테이블 구조와 컴포넌트 간 통신 규약(Interface)을 정의합니다.
* **`ui/` (프리젠테이션)**: 사이드 패널에서 사용자가 탭을 전환하고 폼을 제출, 엑셀을 업로드하는 행위만을 담당합니다.
* **`adapters/` (외부 인프라 연동)**: Chrome Extension API, Storage API 등 외부 요소와 소통하는 포트 역할을 수행합니다.
* **`content.js` (DOM 제어)**: 오직 렌더링된 타겟 시스템 웹페이지의 DOM 요소 검색 및 조작(의사결정이 아닌 행동)만 전담합니다.

---

## 2. 세부 기술 스택 (Technology Stack)

| 구분 | 사용 기술 | 선정 이유 및 특징 |
|------|-----------|--------------------|
| **코어 생태계** | **Chrome Extension (Manifest V3)** | 최신 보안 규격 준수. 백그라운드 페이지 대신 `Service Worker`를 사용하여 리소스 점유 최소화 |
| **언어 및 구조** | **ES6 모듈 (`import/export`)** | 무거운 Webpack/Vite 빌드 없이 네이티브 모듈 로딩을 통해 코드를 깔끔하게 분리 (`<script type="module">`) |
| **마크업/스타일** | **HTML5, Vanilla CSS3** | 인라인 스타일 제거(sidepanel.css 분리). DOM을 직접 조작하는 빠르고 직관적인 구현체 유지 |
| **데이터 파싱** | **SheetJS (`xlsx.mini.min.js`)** | 서버 없이 클라이언트 렌더 웹 환경 안에서 엑셀 파일 파싱 및 JSON 변환. `mini` 버전을 사용하여 번들 크기 축소 |
| **데이터 저장소** | **`chrome.storage.local`** | 로컬 기기에 사용자의 입력 폼 진행 이력(History) 및 설정 영구 보존용 어댑터로 사용 |
| **메시징 통신** | **Chrome IPC (Message Passing)** | `chrome.tabs.sendMessage`와 `chrome.runtime.onMessage`를 통해 컨텐츠 스크립트와 사이드 패널 간 데이터 무손실 교환 |

---

## 3. 핵심 영역: URL Window에 데이터를 어떻게 기입하는가? (Injection Logic)

우리 서비스의 가장 핵심은 **추출된 데이터를 어떻게 실서버 시스템(타겟 URL)의 DOM에 꽂아 넣고 시스템이 정상적인 입력으로 인식하게 만드느냐**입니다. 

> **💡 DOM(Document Object Model)이란?**  
> 웹 브라우저가 HTML 코드를 인식하여 화면을 그릴 때 생성하는 '객체 트리(Tree)' 구조입니다. "DOM에 꽂아 넣는다"는 의미는, 우리의 `content.js`(자바스크립트 코드)가 타겟 웹페이지의 메모리 구조에 접근하여 `<input>`이나 `<select>` 같은 특정 HTML 태그를 찾아낸 뒤, 그 안에 원하는 값을 동적으로 삽입한다는 뜻입니다.

이를 위해 프로그램은 `ui/window-manager.js`(또는 `ui/manual-form.js`) -> `adapters/chrome-messenger.js` -> `content.js` 파이프라인으로 동작하며, 다음과 같은 치밀한 기법을 적용했습니다.

### 3.1 타겟 필드 정의와 분리 (`core/config.js`)
타겟 시스템(사복 정보망 등)은 언제 HTML ID가 변경될지 모릅니다. 따라서 `content.js`에 DOM ID를 하드코딩하지 않고 매핑 테이블을 만들어 관리합니다.
```javascript
export const FIELD_IDS = {
    SERVICE_DETAIL: 'svcClassDetailCd',  // 제공서비스
    RECIPIENT_TYPE: 'svcExecRecipientTyCd', // 대상자 구분
    LOCATION:       'svcProvLocCd',      // 제공장소
    MEANS:          'provMeansCd',       // 서비스 제공방법
};
```

### 3.2 타겟 시스템 웹 브라우저 창 인식 및 탐색 로직 (Target Window Discovery)
Dash는 사용자가 띄워놓은 아동학대정보시스템(타겟 시스템) 창이 몇 개인지, 어떤 탭인지 정확하게 찾아내기 위해 Chrome의 탭 검색 백그라운드 API를 사용합니다.

```javascript
// adapters/chrome-messenger.js
async queryTargetTabs() {
    const cfg = window.DBAuto.Config;
    
    // 1. URL 패턴 기반 백그라운드 검색
    // 서브도메인(*.ncads.go.kr)을 포함하여 팝업창이나 모듈별 창도 모두 스캔합니다.
    // cfg.TARGET_URLS = ["*://localhost/*",ㅇ
    const tabs = await chrome.tabs.query({ url: cfg.TARGET_URLS });
    
    // 2. 제외 키워드 필터링 및 창 고정 정렬
    return tabs
        // 보안 프로그램 다운로드 페이지 등 실제 업무 폼이 아닌 화면을 제외 (예: 'AnySignPlus')
        .filter(t => !cfg.EXCLUDED_KEYWORDS.some(kw => t.url.includes(kw)))
        // 탭 ID 오름차순 정렬: 서버 구동 순서나 로딩 차이와 무관하게 사용자가 브라우저에 띄운 순서대로 "창 1, 창 2, 창 3" 순서를 확실히 고정(Determinism)시킵니다.
        .sort((a, b) => a.id - b.id);
}
```
창을 탐색해 낸 뒤에는 각 탭으로 메시지를 보내(GET_FORM_OPTIONS 액션) 해당 창 안에 현재 어떤 아동의 폼이 열려 있는지 "비동기 이름 스캔"까지 진행하여 사이드 패널에 보여줍니다. 이를 통해 사용자는 현재 자신이 조작할 창의 상태를 사이드 패널 안에서 한눈에 지휘할 수 있습니다.

### 3.3 수동 입력(Manual Form) 데이터 조립 로직
Dash는 엑셀 데이터뿐만 아니라 사이드 패널의 수동 기입 폼(`ui/manual-form.js`)에서 직접 입력한 데이터도 처리할 수 있습니다. 수동 입력과 엑셀 입력은 **UI단에서 데이터를 수집하는 방법만 다를 뿐, 결국 완벽히 동일한 JSON 객체를 만들어 `content.js`로 전달**합니다.

수동 폼 처리 기법은 다음과 같습니다.
1. **HTML 폼 런타임 수집**: 사용자가 사이드 패널의 `<select id="ui-svcClassDetailCd">`, `<input type="date" id="ui-svcProvStartDate">` 등을 채우고 버튼을 누르면, JS가 모든 값을 즉시 읽어 들입니다.
2. **어댑팅(Adapting)**: 읽어온 값들을 엑셀에서 파싱 한 값과 완벽히 동일한 스키마 구조의 JSON 객체(`{ svcClassDetailCd_val: '...', provMeansCd_val: '...' }`)로 가공합니다.
3. 동일한 파이프라인 탑승: 만들어진 객체는 엑셀 프로세스와 동일하게 `['START_AUTO_FILL']` 액션을 통해 `content.js`로 발송됩니다. 이렇게 하면 유지보수 시 입력 로직을 두 번 짤 필요 없이 **단일 통로**로 통합됩니다.

### 3.4 IPC 통신: 액션 전달
`window-manager.js` 또는 `manual-form.js`에서 엑셀 혹은 수동 단일 데이터를 조립한 뒤, 특정 대상 URL 창(Tab ID)으로 메시지를 전송합니다.
```javascript
chrome.tabs.sendMessage(tabId, { action: 'START_AUTO_FILL', ...data }, ...)
```

### 3.5 우회 기입의 핵심: 프레임워크 트리거 전략 (`smartFill` 함수)
단순히 `element.value = '데이터';` 라고 코드를 입력하면 겉으로는 값이 들어간 것처럼 보입니다. 그러나 상대 웹사이트가 최신 JS 프레임워크(React, Vue 등)나 jQuery를 사용하고 있을 경우 **값 변경을 인식하지 못하고 결국 저장 시 빈 값으로 처리**됩니다. 이를 극복하는 것이 `smartFill()` 로직입니다.

```javascript
// content.js
function smartFill(id, value, forceFail = false) {
    const el = document.getElementById(id);
    if (!el) return;

    if (!forceFail && value !== undefined && value !== null && value !== '') {
        el.value = value;
        
        // 🚨 프레임워크 상태 갱신을 강제하기 위한 인위적인 Event 발생
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        
        // 시각적 성공 피드백 (초록색 깜빡임)
        el.classList.add('dbauto-success');
        setTimeout(() => el.classList.remove('dbauto-success'), 1500);
    } else {
        // 실패 또는 무시 시 (빨간색 점선 테두리)
        if (value) el.value = value;
        el.classList.add('dbauto-fail');
    }
}
```

### 3.6 라디오(Radio) 버튼 및 커스텀 제어 
드롭다운(`Select`) 등과 달리 라디오 버튼은 직접 `checked = true` 처리해야 합니다.
```javascript
function smartFillRadio(name, value) {
    const radio = document.querySelector(`input[name="${name}"][value="${value}"]`);
    if (radio) {
        radio.checked = true;
    } else {
        const firstRadio = document.querySelector(`input[name="${name}"]`);
        if (firstRadio) firstRadio.parentElement.classList.add('dbauto-fail');
    }
}
```

### 3.7 Isolated World의 극복 (`executeInMainWorld` 기법)
Chrome Extension의 컨텐츠 스크립트는 **'Isolated World(격리된 세계)'**라는 독자적인 메모리 공간에서 동작합니다. 만약 타겟 시스템의 버튼에 `<a href="javascript:doSubmit()">` 처럼 실세계의 전역 합수가 등록되어 있다면, Extension에서 `element.click()`을 해도 실행되지 않는 경우가 있습니다.

해당 정책을 우회하기 위해 **동적으로 `<script>` 태그를 생성하여 본래 Document의 `<head>`에 코드를 삽입 및 즉시 실행(IIFE)한 뒤 허물을 버리듯 삭제하는 기법**을 적용했습니다.
```javascript
function executeInMainWorld(element, jsCode = '') {
    const script = document.createElement('script');
    
    // 대상 브라우저의 전역 메모리 공간(Main World)에 코드를 직접 주사 
    script.textContent = `(function() { 
        try { ${jsCode} } catch(e) { console.error('[main-world-error]', e); }
    })();`;
    
    (document.head || document.documentElement).appendChild(script);
    script.remove(); // 사용 직후 폐기
}
```

### 3.8 개인정보 통제 아키텍처 (Privacy by Design)
시스템 설계상 **대상자** 및 **담당자**와 같이 개인정보보호법에 민감한 실명 데이터는 엑셀에서 받아오지 않으며, `content.js` 내부에서도 아래와 같이 `markFail()`을 명시적으로 호출합니다.
이를 통해 시스템은 해당 필드를 고의로 빨간색 경고 표시한 뒤, 사용자가 타겟 시스템 드롭다운에서 직접 실명을 손으로 선택하게 넛지(Nudge)합니다.
```javascript
// 5. 대상자 — 자동 입력 배제 (사용자 직접 선택 유도)
markFail(F.RECIPIENT_TYPE || 'svcExecRecipientTyCd');
markFail(F.RECIPIENT_ID || 'svcExecRecipientId');

// 10. 서비스 제공자 — 자동 입력 배제
markFail(F.PIC || 'picId');
```

---

## 4. 로직 수행 프로세스 플로우

1. **데이터 수집 단계**: 엑셀 업로드(SheetJS 파싱 처리 후 객체 반환) 또는 사이드 패널의 수동 폼 드롭다운/입력값 수집.
2. **사이드 패널 조립/렌더링**: 수집된 데이터를 통합된 Schema(JSON 객체)로 변환 (오류 점검, 매핑).
3. **'기입' 버튼 클릭**: Target Window를 `chrome.tabs.query`로 검색.
4. `['START_AUTO_FILL']` IPC 송신
5. **DOM 스캐닝**: `content.js`가 타겟 페이지 내 필드 여부 점검 (`CFG.FIELD_IDS`)
6. **Smart Fill 처리**: 값 주입 → 이벤트 생성(`change`, `input`) 트리거 → 타겟 SPA/Legacy 서버 값 인식
7. **Animation Play**: 연두색 네온 보더 효과(`dbauto-success`)로 주입 성공 시인성 제공.
8. 시스템 저장(사용자 수동 클릭 대기 혹은 추가 팝업 처리 등).
