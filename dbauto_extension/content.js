// =============================================
// content.js — 타겟 페이지 DOM 제어
// Config와 Actions(message-types)를 참조합니다.
// =============================================

// content_scripts에서는 ES Module 불가 → config.js를 먼저 로드하여 전역 사용
const CFG = (window.DBAuto && window.DBAuto.Config) || {};
const ACT = (window.DBAuto && window.DBAuto.Actions) || {};

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    const action = message.action;

    if (action === (ACT.START_AUTO_FILL || 'START_AUTO_FILL')) {
        handleAutoFill(message.data);
        sendResponse({ success: true });

    } else if (action === (ACT.HIGHLIGHT_TAB || 'HIGHLIGHT_TAB')) {
        const overlayId = 'dbauto-highlight-overlay';
        let overlay = document.getElementById(overlayId);

        if (message.active) {
            if (!overlay) {
                overlay = document.createElement('div');
                overlay.id = overlayId;
                overlay.style.cssText = `
                    position: fixed; top: 0; left: 0; width: 100%; height: 100%;
                    border: 8px solid #C2FFA7; box-sizing: border-box;
                    pointer-events: none; z-index: 999999;
                    background: rgba(194, 255, 167, 0.1);
                    box-shadow: inset 0 0 50px rgba(194, 255, 167, 0.3);
                `;
                document.body.appendChild(overlay);
            }
        } else if (overlay) {
            overlay.remove();
        }

    } else if (action === (ACT.GET_FORM_OPTIONS || 'GET_FORM_OPTIONS')) {
        const getOptions = (id) => {
            const select = document.getElementById(id);
            if (!select) return [];
            return Array.from(select.options).map(opt => ({ value: opt.value, text: opt.text }));
        };

        const F = CFG.FIELD_IDS || {};

        // 타겟 페이지의 드롭다운 옵션을 단순 조회 (DOM 조작 없음)
        // 피해아동 이름: 이미 로딩된 대상자 옵션 또는 추가된 목록에서 비파괴적으로 읽기
        const getVictimNames = () => {
            const names = [];
            // 방법1: recipientTyId_view (이미 추가된 대상자 목록)
            const view = document.getElementById('recipientTyId_view');
            if (view) {
                view.querySelectorAll('span, li, div').forEach(el => {
                    const t = el.textContent.trim();
                    if (t.includes('[피해아동]') || t.includes('피해아동')) {
                        names.push(t.replace(/\[피해아동\]\s*/g, '').split(/\s+/)[0].trim());
                    }
                });
            }
            // 방법2: svcExecRecipientId에 현재 로딩된 옵션 중 피해아동 포함
            if (names.length === 0) {
                const sel = document.getElementById(F.RECIPIENT_ID || 'svcExecRecipientId');
                if (sel) {
                    Array.from(sel.options).forEach(opt => {
                        if (opt.text.includes('[피해아동]')) {
                            names.push(opt.text.replace(/\[피해아동\]\s*/g, '').trim());
                        }
                    });
                }
            }
            return [...new Set(names)];
        };

        sendResponse({
            svcClassDetailCd: getOptions(F.SERVICE_DETAIL || 'svcClassDetailCd'),
            svcProvLocCd: getOptions(F.LOCATION || 'svcProvLocCd'),
            provMeansCd: getOptions(F.MEANS || 'provMeansCd'),
            provTyCd: getOptions(F.TYPE || 'provTyCd'),
            victimNames: getVictimNames(),
        });

    } else if (action === (ACT.UPDATE_TY_CD || 'UPDATE_TY_CD_AND_GET_OPTIONS')) {
        // MutationObserver로 옵션 로딩 완료를 감지하는 방식
        const F = CFG.FIELD_IDS || {};
        const tySelect = document.getElementById(F.RECIPIENT_TYPE || 'svcExecRecipientTyCd');
        const idSelect = document.getElementById(F.RECIPIENT_ID || 'svcExecRecipientId');

        if (tySelect) {
            tySelect.value = message.value;
            tySelect.dispatchEvent(new Event('change', { bubbles: true }));
        }

        if (!idSelect) {
            sendResponse({ svcExecRecipientId: [] });
            return true;
        }

        // MutationObserver: 옵션이 실제로 로딩될 때까지 대기
        const observer = new MutationObserver(() => {
            if (idSelect.options.length > 1) {
                observer.disconnect();
                clearTimeout(fallbackTimer);
                const options = Array.from(idSelect.options).map(opt => ({ value: opt.value, text: opt.text }));
                sendResponse({ svcExecRecipientId: options });
            }
        });
        observer.observe(idSelect, { childList: true });

        // 3초 타임아웃 보험
        const fallbackTimer = setTimeout(() => {
            observer.disconnect();
            const options = Array.from(idSelect.options).map(opt => ({ value: opt.value, text: opt.text }));
            sendResponse({ svcExecRecipientId: options });
        }, 3000);

        return true; // 비동기 응답
    }
    return true;
});
// 크롬 익스텐션 Isolated World 정책을 우회하여 메인 권한에서 코드를 실행시키는 기법
function executeInMainWorld(element, jsCode = '') {
    const script = document.createElement('script');

    if (jsCode) {
        script.textContent = `(function() { 
            try { 
                ${jsCode} 
            } catch(e) { console.error('[dbauto-main-world] Error executing code:', e); }
        })();`;
    } else if (element) {
        const href = element.getAttribute('href');
        if (href && href.startsWith('javascript:')) {
            const code = href.replace('javascript:', '');
            script.textContent = `(function() { 
                try { ${code} } catch(e) { console.error('[dbauto-main-world]', e); }
            })();`;
        } else {
            const originalId = element.id;
            const tempId = originalId || `dbauto-temp-btn-${Date.now()}`;
            if (!originalId) element.id = tempId;
            script.textContent = `(function() { 
                var btn = document.getElementById('${tempId}'); 
                if (btn) btn.click();
            })();`;
            setTimeout(() => {
                const el = document.getElementById(tempId);
                if (el && !originalId) el.removeAttribute('id');
            }, 300);
        }
    }

    (document.head || document.documentElement).appendChild(script);
    script.remove();
}

async function handleAutoFill(data) {
    try {
        console.log('dbauto data received:', data);
        const F = CFG.FIELD_IDS || {};

        // 스타일 주입
        if (!document.getElementById('dbauto-styles')) {
            const style = document.createElement('style');
            style.id = 'dbauto-styles';
            style.innerHTML = `
                .dbauto-success { border: 2px solid #C2FFA7 !important; transition: all 0.5s; box-shadow: 0 0 10px rgba(194, 255, 167, 0.5); }
                .dbauto-fail { border: 2px dashed #ff5252 !important; background-color: #fff1f1 !important; transition: all 0.3s; }
            `;
            document.head.appendChild(style);
        }

        // 초기화
        document.querySelectorAll('.dbauto-success, .dbauto-fail').forEach(el => {
            el.classList.remove('dbauto-success', 'dbauto-fail');
        });

        const delay = (ms) => new Promise(r => setTimeout(r, ms));

        // 매핑 테이블 (config에서 가져오거나 폴백)
        const provCdMap = CFG.PROV_CD_MAP || { '제공': 'A', '부가업무': 'B', '거부': 'C' };
        const meansMap = CFG.MEANS_MAP || { '전화': 'A', '내방': 'B', '방문': 'C' };
        const locMap = CFG.LOCATION_MAP || { '기관내': 'A', '아동가정': 'B', '유관기관': 'C', '기타': 'X' };
        const svcMap = CFG.SERVICE_MAP || {};

        // 1. 제공구분 (Radio)
        smartFillRadio('provCd', provCdMap[data.provCd_val] || data.provCd_val || '');

        // 2. 서비스제공방법 (Select)
        smartFill(F.MEANS || 'provMeansCd', meansMap[data.provMeansCd_val] || data.provMeansCd_val || '');

        // 3. 서비스제공유형
        if (data.provTyCd_val) {
            smartFill(F.TYPE || 'provTyCd', data.provTyCd_val);
        } else {
            markFail(F.TYPE || 'provTyCd');
        }

        // 4. 제공서비스 (Select)
        smartFill(F.SERVICE_DETAIL || 'svcClassDetailCd', svcMap[data.svcClassDetailCd_val] || data.svcClassDetailCd_val || '');

        // 5. 대상자 — (추후 구현 예정)


        // 6. 제공장소
        smartFill(F.LOCATION || 'svcProvLocCd', locMap[data.loc_val] || data.loc_val || '');
        if (data.locEtc_val_raw) {
            smartFill(F.LOCATION_ETC || 'svcProvLocEtc', data.locEtc_val_raw);
        }

        // 6-2. 서비스 제공 횟수
        if (data.cnt_val !== undefined && data.cnt_val !== '') {
            smartFill(F.PROV_COUNT || 'svcProvCnt', data.cnt_val);
        }

        // 7. 서비스제공일시
        if (data.dateTime_val) {
            const parts = data.dateTime_val.toString().trim().split(' ');
            if (parts.length >= 2) {
                const datePart = parts[0];
                const isDateValid = /^\d{4}-\d{2}-\d{2}$/.test(datePart);

                if (isDateValid) {
                    smartFill(F.START_DATE || 'svcProvStartDate', datePart);
                    smartFill(F.END_DATE || 'svcProvEndDate', datePart);
                } else {
                    smartFill(F.START_DATE || 'svcProvStartDate', datePart, true);
                    smartFill(F.END_DATE || 'svcProvEndDate', datePart, true);
                }

                const timePart = parts[1];
                if (timePart.includes('~')) {
                    const [start, end] = timePart.split('~');
                    const [sh, sm] = start.split(':');
                    const [eh, em] = end.split(':');
                    smartFill(F.START_HH || 'svcProvStartHH', sh);
                    smartFill(F.START_MI || 'svcProvStartMI', sm);
                    smartFill(F.END_HH || 'svcProvEndHH', eh);
                    smartFill(F.END_MI || 'svcProvEndMI', em);
                }
            } else {
                markFail(F.START_DATE || 'svcProvStartDate');
                markFail(F.END_DATE || 'svcProvEndDate');
            }
        } else {
            markFail(F.START_DATE || 'svcProvStartDate');
            markFail(F.END_DATE || 'svcProvEndDate');
        }

        // 8. 이동소요시간
        if (data.mvmnReqreHr_val !== undefined && data.mvmnReqreHr_val !== '') {
            smartFill(F.MOVE_TIME || 'mvmnReqreHr', data.mvmnReqreHr_val);
        } else {
            markFail(F.MOVE_TIME || 'mvmnReqreHr');
        }

        // 9. 서비스내용 & 소견
        smartFill(F.DESC || 'svcProvDesc', data.desc_val);
        smartFill(F.OPINION || 'consOpn', data.opn_val);

        // 10. 대상자 — MutationObserver 기반 이중 드롭다운 기입
        if (data.recipient_fullVal && data.recipient_fullVal.length > 0) {
            fillRecipientsSequentially(data.recipient_fullVal);
        }

        // 11. 서비스 제공자 (단일 Select + "+" 버튼)
        if (data.pic_fullVal && data.pic_fullVal.length > 0) {
            fillPicSequentially(data.pic_fullVal);
        }

    } catch (e) {
        console.error('dbauto error:', e);
    }
}

function smartFill(id, value, forceFail = false) {
    const el = document.getElementById(id);
    if (!el) return;

    if (!forceFail && value !== undefined && value !== null && value !== '') {
        el.value = value;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        el.classList.add('dbauto-success');
        setTimeout(() => el.classList.remove('dbauto-success'), 1500);
    } else {
        if (value) el.value = value;
        el.classList.add('dbauto-fail');
    }
}

function smartFillRadio(name, value) {
    const radio = document.querySelector(`input[name="${name}"][value="${value}"]`);
    if (radio) {
        radio.checked = true;
    } else {
        const firstRadio = document.querySelector(`input[name="${name}"]`);
        if (firstRadio) firstRadio.parentElement.classList.add('dbauto-fail');
    }
}

function markFail(id) {
    const el = document.getElementById(id);
    if (el) el.classList.add('dbauto-fail');
}

// ─── MutationObserver 기반: Select 옵션이 로딩될 때까지 대기 ───
function waitForSelectOptions(selectEl, timeoutMs = 3000) {
    return new Promise((resolve) => {
        if (selectEl.options.length > 1) { resolve(); return; }
        const observer = new MutationObserver(() => {
            if (selectEl.options.length > 1) {
                observer.disconnect();
                clearTimeout(timer);
                resolve();
            }
        });
        observer.observe(selectEl, { childList: true });
        const timer = setTimeout(() => { observer.disconnect(); resolve(); }, timeoutMs);
    });
}

// ─── 대상자 이중 드롭다운 순차 기입 ───
async function fillRecipientsSequentially(items) {
    const CFG = window.DBAuto?.Config || {};
    const F = CFG.FIELD_IDS || {};
    const tySelect = document.getElementById(F.RECIPIENT_TYPE || 'svcExecRecipientTyCd');
    const idSelect = document.getElementById(F.RECIPIENT_ID || 'svcExecRecipientId');
    if (!tySelect || !idSelect) return;

    for (const item of items) {
        // 1단계: 대상자 구분 선택
        tySelect.value = item.tyCd;
        tySelect.dispatchEvent(new Event('change', { bubbles: true }));
        // 2단계: 이름 옵션 로딩 대기
        await waitForSelectOptions(idSelect, 3000);
        // 3단계: 이름 선택
        idSelect.value = item.value;
        idSelect.dispatchEvent(new Event('change', { bubbles: true }));
        // 4단계: "+" 버튼 클릭
        const addBtn = document.querySelector('a[href*="fnAddRecipient"]');
        if (addBtn) { addBtn.click(); }
        else { try { fnAddRecipient(); } catch (e) { } }
        await new Promise(r => setTimeout(r, 100));
    }
}

// ─── 상담원 단일 Select + "+" 버튼 기입 ───
async function fillPicSequentially(items) {
    const CFG = window.DBAuto?.Config || {};
    const F = CFG.FIELD_IDS || {};
    const picSelect = document.getElementById(F.PIC || 'picId');
    if (!picSelect) return;

    for (const item of items) {
        picSelect.value = item.value;
        picSelect.dispatchEvent(new Event('change', { bubbles: true }));
        const addBtn = document.querySelector('a[href*="fnAddPicId"]');
        if (addBtn) { addBtn.click(); }
        else { try { fnAddPicId(); } catch (e) { } }
        await new Promise(r => setTimeout(r, 100));
    }
}
