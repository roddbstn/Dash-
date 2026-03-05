/**
 * content.js — labelmaker.kr 페이지에 주입되는 스크립트
 * background.js로부터 메시지를 받아 폼 필드에 데이터를 자동 입력합니다.
 */

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === 'FILL_FORM') {
        fillForm(message.data).then(sendResponse);
        return true;
    }
});

async function fillForm(labelData) {
    const results = {};

    const handlers = {
        title: () => setRichText('title', labelData.title),
        productionYear: () => setRichText('productionYear', labelData.productionYear),
        departmentName: () => setRichTextHTML('departmentName', labelData.departmentName),
        classificationCode: () => setInputValue('input[placeholder*="사업"], input[placeholder*="분류"]', labelData.classificationCode),
        retentionPeriod: () => setSelectValue(labelData.retentionPeriod),
        managementNumber: () => setInputValue('input[placeholder*="A-001"], input[placeholder*="관리"]', labelData.managementNumber),
    };

    for (const [field, handler] of Object.entries(handlers)) {
        if (labelData[field] === undefined) continue;
        try {
            await handler();
            results[field] = true;
            await sleep(200);
        } catch (e) {
            results[field] = false;
            console.warn(`[dbauto] ${field} 입력 실패:`, e.message);
        }
    }

    const allOk = Object.values(results).every(v => v);
    return { ok: allOk, results };
}

/** contenteditable div에 텍스트 입력 */
function setRichText(id, value) {
    const el = document.getElementById(id);
    if (!el) throw new Error(`#${id} 요소를 찾을 수 없습니다`);
    el.focus();
    el.innerText = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));
}

/** contenteditable div에 HTML 입력 (줄바꿈 포함) */
function setRichTextHTML(id, value) {
    const el = document.getElementById(id);
    if (!el) throw new Error(`#${id} 요소를 찾을 수 없습니다`);
    el.focus();
    // \n → <br> 변환
    el.innerHTML = value.replace(/\n/g, '<br>');
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));
}

/** <input> 필드에 값 입력 (React 호환) */
function setInputValue(selector, value) {
    // 여러 셀렉터 시도
    const selectors = selector.split(', ');
    let el = null;
    for (const s of selectors) {
        el = document.querySelector(s.trim());
        if (el) break;
    }
    if (!el) throw new Error(`입력 필드를 찾을 수 없습니다: ${selector}`);

    // React의 synthetic event 시스템 우회
    const nativeSetter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype, 'value'
    ).set;
    nativeSetter.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
}

/** <select> 드롭다운 값 변경 (React 호환) */
function setSelectValue(value) {
    // 보존기간 옵션이 있는 select 찾기
    const selects = document.querySelectorAll('select');
    let el = null;
    for (const sel of selects) {
        for (const opt of sel.options) {
            if (['영구', '준영구', '30년', '10년', '5년', '3년', '1년'].includes(opt.value)) {
                el = sel;
                break;
            }
        }
        if (el) break;
    }
    if (!el) throw new Error('보존기간 select 요소를 찾을 수 없습니다');

    const nativeSetter = Object.getOwnPropertyDescriptor(
        window.HTMLSelectElement.prototype, 'value'
    ).set;
    nativeSetter.call(el, value);
    el.dispatchEvent(new Event('change', { bubbles: true }));
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}
