let currentParsedData = [];
let selectedRecords = [];
let targetTabs = [];
let selectedTabs = [];

const MATCH_COLORS = ['#42a5f5', '#66bb6a', '#ffa726', '#ec407a', '#26a69a', '#ab47bc', '#8d6e63'];

// 탭 전환 로직
document.getElementById('tab-upload').onclick = () => switchTab('upload');
document.getElementById('tab-manual').onclick = () => switchTab('manual');
document.getElementById('tab-history').onclick = () => {
    switchTab('history');
    loadHistory();
};

function switchTab(tab) {
    document.getElementById('upload-view').classList.add('hidden');
    document.getElementById('manual-view').classList.add('hidden');
    document.getElementById('history-view').classList.add('hidden');
    document.getElementById('window-section').classList.add('hidden');
    document.getElementById('status').classList.add('hidden'); // 기본으로 숨김

    document.getElementById('tab-upload').classList.remove('active');
    document.getElementById('tab-manual').classList.remove('active');
    document.getElementById('tab-history').classList.remove('active');

    if (tab === 'upload') {
        document.getElementById('upload-view').classList.remove('hidden');
        document.getElementById('window-section').classList.remove('hidden');
        document.getElementById('status').classList.remove('hidden'); // 파일 탭에서만 보임
        document.getElementById('tab-upload').classList.add('active');
    } else if (tab === 'manual') {
        document.getElementById('manual-view').classList.remove('hidden');
        document.getElementById('tab-manual').classList.add('active');
        renderManualForms();
    } else {
        document.getElementById('history-view').classList.remove('hidden');
        document.getElementById('tab-history').classList.add('active');
    }
}

// ==========================================
// 🌟 수동 기입 (Manual Input) 로직 🌟
// ==========================================
// 대상 창 전체 새로고침 및 내부 폼 데이터 캐시 초기화 기믹 구현
document.getElementById('refresh-manual-windows').onclick = () => {
    // 1. 기존의 작성 내용(storage) 모두 초기화
    chrome.storage.local.set({ manualFormState: {} }, () => {
        // 2. 각 창에 쿼리를 날려서 최신 정보를 읽은 상태로 폼 재렌더링
        renderManualForms();
    });
};

// 폼 입력 컨테이너 전체에 이벤트 리스너를 걸어 자동 저장 구현
document.getElementById('manual-form-container').addEventListener('input', saveManualFormState);
document.getElementById('manual-form-container').addEventListener('change', saveManualFormState);

async function renderManualForms() {
    const container = document.getElementById('manual-form-container');
    container.innerHTML = '<div style="text-align:center; padding:15px; color:#666; font-size:11px;">대상 창을 검색 중입니다...</div>';

    // 대상 창 다시 탐색 (AnySign 등 기입과 무관한 유틸리티 창 배제)
    let tabs = await new Promise(resolve => chrome.tabs.query({ url: ["*://localhost/*", "*://ncads.go.kr/*"] }, resolve));
    tabs = tabs.filter(t => !t.url.includes('AnySignPlus'));

    if (tabs.length === 0) {
        container.innerHTML = '<div style="text-align:center; padding:15px; color:#999; font-size:11px;">감지된 시스템 창이 없습니다.<br>아동학대정보시스템 창을 열어주세요.</div>';
        return;
    }

    container.innerHTML = '';

    tabs.forEach((tab, index) => {
        // Content Script에 드롭다운 옵션 요청
        chrome.tabs.sendMessage(tab.id, { action: 'GET_FORM_OPTIONS' }, (options) => {
            if (chrome.runtime.lastError || !options) {
                // 아직 스크립트가 로드되지 않거나 에러 발생 시 임시 폼 렌더링
                container.insertAdjacentHTML('beforeend', createManualFormHtml(tab, {}, index));
            } else {
                container.insertAdjacentHTML('beforeend', createManualFormHtml(tab, options, index));
            }
            // 폼 생성 직후 저장된 상태 복원
            restoreManualFormState(tab.id, document.getElementById(`manual-form-${tab.id}`));
        });
    });
}

// 폼 상태를 스토리지에 자동 저장하는 함수
function saveManualFormState() {
    chrome.storage.local.get(['manualFormState'], (res) => {
        const state = res.manualFormState || {};
        document.querySelectorAll('.manual-form-group').forEach(group => {
            const tabId = group.id.replace('manual-form-', '');
            if (!state[tabId]) state[tabId] = {};

            // Select, Input 값 저장
            group.querySelectorAll('.form-input').forEach(el => {
                const inputClass = Array.from(el.classList).find(c => c.startsWith('manual-input-'));
                if (inputClass) {
                    const key = inputClass.replace('manual-input-', '');
                    state[tabId][key] = el.value;
                }
            });

            // List Builder 아이템 저장
            group.querySelectorAll('.list-builder-container').forEach(container => {
                const field = container.dataset.field;
                const items = Array.from(container.querySelectorAll('.builder-item')).map(it => ({
                    value: it.dataset.value,
                    text: it.dataset.text,
                    tyCd: it.dataset.tycd || ''
                }));
                state[tabId][field] = items;
            });
        });
        try {
            chrome.storage.local.set({ manualFormState: state });
        } catch (e) {
            console.error("Export failed:", e);
            alert("내보내기에 실패했습니다.");
        }
    });
}

// === 드롭다운 마우스 오버 전개 (Hover Select) 로직 ===
document.addEventListener('mouseover', function (e) {
    if (e.target.matches('select.hover-select')) {
        // 다른 열려있는 호버 셀렉트는 모두 닫기
        document.querySelectorAll('select.hover-select[data-is-hovered="true"]').forEach(select => {
            if (select !== e.target) closeHoverSelect(select);
        });

        const select = e.target;
        if (select.options.length <= 1) return; // 항목이 하나면 안 펼침
        if (select.dataset.isHovered === 'true') return;

        select.dataset.isHovered = 'true';
        select.size = Math.min(select.options.length, 8); // 최대 8개 항목 표시
        select.style.zIndex = '9999';
        select.style.boxShadow = '0 4px 12px rgba(0,0,0,0.2)';
        select.style.height = 'auto'; // 리스트 길이에 맞게 확장되도록 강제 제한 해제
    }
});

const closeHoverSelect = (select) => {
    if (select.dataset.isHovered !== 'true') return;
    select.size = 1;
    select.style.zIndex = '10';
    select.style.boxShadow = 'none';
    select.style.height = ''; // 확장되었던 높이 속성 삭제 (다시 원래 CSS의 22px 높이로 원복됨)
    select.dataset.isHovered = 'false';
    select.blur();
};

document.addEventListener('mouseout', function (e) {
    if (e.target.matches('select.hover-select')) {
        // 마우스가 select 요소 바깥으로 나갔을 때 닫기
        if (!e.relatedTarget || !e.target.contains(e.relatedTarget)) {
            closeHoverSelect(e.target);
        }
    }
});

document.addEventListener('change', function (e) {
    if (e.target.matches('select.hover-select')) {
        closeHoverSelect(e.target);
        // 리스트 빌더 자동 추가 로직 (선택 시 바로 리스트에 추가)
        if (e.target.classList.contains('builder-select-picId') || e.target.classList.contains('builder-select-svcExecRecipientId')) {
            const container = e.target.closest('.list-builder-container');
            const field = container.dataset.field;
            const tabId = container.dataset.tabid;
            window.addListItem(field, tabId);
            // 추가 직후 선택 초기화하여 다음 입력을 편하게 만듦
            setTimeout(() => { e.target.value = ""; }, 50);
        }
    }

    // 대상자 구분 드롭다운 값이 변경된 경우, 해당되는 이름을 동적 렌더링
    if (e.target.classList.contains('manual-input-svcExecRecipientTyCd')) {
        const tabId = parseInt(e.target.dataset.tabid, 10);
        const tyCdVal = e.target.value;
        const container = e.target.closest('.manual-form-group');
        const targetSelect = container.querySelector('.builder-select-svcExecRecipientId');

        if (targetSelect && tyCdVal) {
            targetSelect.innerHTML = '<option value="">로딩 중...</option>';
            // 실시간 반영은 옵션을 가져오기 위한 용도로만 최소화
            chrome.tabs.sendMessage(tabId, { action: 'UPDATE_TY_CD_AND_GET_OPTIONS', value: tyCdVal, silent: true }, (res) => {
                if (!chrome.runtime.lastError && res && res.svcExecRecipientId) {
                    targetSelect.innerHTML = '<option value="">선택하세요</option>' +
                        res.svcExecRecipientId.map(o => `<option value="${o.value}">${o.text}</option>`).join('');
                } else {
                    targetSelect.innerHTML = '<option value="">선택하세요</option>';
                }
            });
        }
        saveManualFormState();
    }
});

// 드롭다운 내 옵션을 클릭(또는 같은 옵션 재클릭)하면 무조건 닫기
// change 이벤트는 "값이 바뀔 때만" 발생하므로, 같은 옵션 재클릭 시 닫히지 않는 문제를 해결
document.addEventListener('mousedown', function (e) {
    // option을 직접 클릭한 경우 → 부모 select를 닫음
    if (e.target.tagName === 'OPTION' && e.target.parentElement.matches('select.hover-select')) {
        setTimeout(() => closeHoverSelect(e.target.parentElement), 0);
    }
    // select 자체를 클릭한 경우 (펼쳐진 상태에서)
    if (e.target.matches('select.hover-select') && e.target.size > 1) {
        setTimeout(() => closeHoverSelect(e.target), 0);
    }
});

// 리스트 빌더 아이템 제거 버튼 (X) 이벤트 및 달력 열기 위임
document.addEventListener('click', function (e) {
    if (e.target.matches('.builder-remove-btn')) {
        e.target.parentElement.remove();
        saveManualFormState();
    } else if (e.target.matches('input[type="date"]')) {
        try { e.target.showPicker(); } catch (err) { }
    }
});
document.addEventListener('mouseover', function (e) {
    if (e.target.matches('input[type="date"]')) {
        try { e.target.showPicker(); } catch (err) { }
    }
});

// 저장된 폼 상태를 불러와 복원하는 함수
function restoreManualFormState(tabId, groupEl) {
    if (!groupEl) return;
    chrome.storage.local.get(['manualFormState'], (res) => {
        const state = res.manualFormState;
        if (!state || !state[tabId]) return;

        const tabState = state[tabId];
        // Select, Input 복원
        groupEl.querySelectorAll('.form-input').forEach(el => {
            const inputClass = Array.from(el.classList).find(c => c.startsWith('manual-input-'));
            if (inputClass) {
                const key = inputClass.replace('manual-input-', '');
                if (tabState[key] !== undefined) el.value = tabState[key];
            }
        });

        // Checkbox 복원 대신 List Builder 복원
        groupEl.querySelectorAll('.list-builder-container').forEach(container => {
            const field = container.dataset.field;
            const items = tabState[field];
            if (Array.isArray(items)) {
                const list = container.querySelector(`.builder-list-${field}`);
                list.innerHTML = '';
                items.forEach(it => renderBuilderItem(list, it.value, it.text, it.tyCd));
            }
        });
    });
}

function createManualFormHtml(tab, options, index) {
    // 옵션 배열이 텍스트로 바로 들어갈 수 있도록 value를 올바르게 매핑
    const buildSelect = (id, opts = [], extraStyle = '') => {
        const safeOpts = opts || [];
        return `<div class="hover-select-wrapper" style="position: relative; ${extraStyle}">
            <select class="form-input manual-input-${id} hover-select" data-tabid="${tab.id}" style="width: 100%; position: absolute; top:0; left:0; box-sizing: border-box; z-index:10; min-height:22px; appearance:auto; cursor:pointer; background:#fff;">
                <option value="">선택하세요</option>
                ${safeOpts.map(o => `<option value="${o.value}">${o.text}</option>`).join('')}
            </select>
            <!-- 투명 플레이스홀더로 레이아웃 유지 -->
            <div style="visibility: hidden; min-height:22px; width: 100%; pointer-events:none; padding:3px 5px; font-size:10px;">선택하세요</div>
        </div>`;
    };

    // 담당자/대상자 다중 입력을 위한 리스트 빌더 (드롭다운 + [+] 버튼 + 결과 리스트)
    const buildListBuilder = (id, opts = []) => {
        const safeOpts = opts || [];
        return `
        <div class="list-builder-container" data-field="${id}" data-tabid="${tab.id}">
            <div style="display:flex; gap:3px;">
                <div class="hover-select-wrapper" style="position: relative; flex:1;">
                    <select class="form-input builder-select-${id} hover-select" style="width: 100%; position: absolute; top:0; left:0; box-sizing: border-box; z-index:10; min-height:22px; appearance:auto; cursor:pointer; background:#fff;">
                        <option value="">선택하세요</option>
                        ${safeOpts.map(o => `<option value="${o.value}">${o.text}</option>`).join('')}
                    </select>
                    <div style="visibility: hidden; min-height:22px; width: 100%; pointer-events:none; padding:3px 5px; font-size:10px;">선택하세요</div>
                </div>
            </div>
            <div class="builder-list-${id}" style="display:flex; flex-wrap:wrap; gap:4px; margin-top:5px; min-height:20px; padding:3px; border:1px dashed #ccc; border-radius:3px; background:#fafafa;">
                <!-- 추가된 항목들이 여기에 렌더링됨 -->
            </div>
        </div>`;
    };

    const buildInput = (id, placeholder, extraStyle = '', attr = '', type = 'text') =>
        `<input type="${type}" class="form-input manual-input-${id}" data-tabid="${tab.id}" placeholder="${placeholder}" style="${extraStyle}" ${attr}>`;

    // 대상자 옵션 중 피해아동 데이터를 1~3개 추출하여 제목에 표시 (마스킹 처리 포함)
    let childText = '';

    // content script가 스캔한 타겟 페이지 전체의 피해아동 목록(victimNames)을 최우선으로 사용, 없을 경우 기존 dropdown 옵션 폴백
    let nameSource = [];
    if (options && options.victimNames && options.victimNames.length > 0) {
        nameSource = options.victimNames;
    } else if (options && options.svcExecRecipientId) {
        nameSource = options.svcExecRecipientId.map(opt => opt.text);
    }

    if (nameSource.length > 0) {
        const abusedChildren = nameSource
            .filter(text => text.includes('피해아동')) // 다시 '피해아동'만 표시하도록 엄격한 필터링 복원
            .map(text => {
                const name = text.replace(/\[.*?\]|\(.*?\)|선택하세요|피해아동/g, '').trim();
                if (!name) return '';

                // 이름 길이에 따른 마스킹 처리 로직
                let maskedName = name;
                if (name.length === 2) {
                    maskedName = name.charAt(0) + 'O';
                } else if (name.length === 3) {
                    maskedName = name.charAt(0) + 'O' + name.slice(2);
                } else if (name.length >= 4) {
                    const midLength = name.length - 2;
                    maskedName = name.charAt(0) + 'O'.repeat(midLength) + name.slice(-1);
                }
                return maskedName;
            })
            .filter(t => t);

        // 중복 제거 후 최대 3명까지만 표시
        const uniqueChildren = [...new Set(abusedChildren)].slice(0, 3);
        if (uniqueChildren.length > 0) {
            childText = ` (피해아동: ${uniqueChildren.join(', ')})`;
        }
    }

    return `
    <div class="manual-form-group" id="manual-form-${tab.id}">
        <div class="manual-form-title">
            <span class="window-badge" style="background:${MATCH_COLORS[index % MATCH_COLORS.length]}">창 ${index + 1}</span> 
            <span style="flex:1; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${tab.title || '제목 없음'}<b style="color:#2196F3;">${childText}</b></span>
            <button class="copy-all-btn" onclick="copyManualFormToAll(${tab.id})">이 내용으로 복사 ⬇</button>
        </div>
        
        <div style="font-size: 11px; color: #555; background: #f9f9f9; padding: 8px; border-radius: 4px; border: 1px solid #e0e0e0; margin-bottom: 10px; word-break: keep-all; line-height: 1.4; text-align: left;">
            <span style="font-weight: 500;">🔒 대상자·담당자는 시스템에서 직접 선택해 주세요.</span>
            <div style="color: #999; font-size: 10px; margin-top: 3px;">※ 모든 데이터는 서버에 저장되지 않습니다.</div>
        </div>
        
        <div class="form-row"><div class="form-label">제공구분</div>
            ${buildSelect('provCd', [{ value: '제공', text: '제공' }, { value: '부가업무', text: '부가업무' }, { value: '거부', text: '거부' }], 'flex:1')}
        </div>
        
        <div class="form-row"><div class="form-label">제공방법</div>${buildSelect('provMeansCd', options.provMeansCd, 'flex:1')}</div>
        
        <div class="form-row"><div class="form-label">서비스유형</div>${buildSelect('provTyCd', options.provTyCd, 'flex:1')}</div>
        
        <div class="form-row"><div class="form-label">제공서비스</div>${buildSelect('svcClassDetailCd', options.svcClassDetailCd, 'flex:1')}</div>
        
        <div class="form-row"><div class="form-label">제공장소</div>
            <div style="display:flex; gap:5px; flex:1;">
                ${buildSelect('svcProvLocCd', options.svcProvLocCd, 'flex:1; max-width:120px;')}
                ${buildInput('svcProvLocEtc', '기타 장소 입력', 'flex:1')}
            </div>
        </div>
        <div class="form-row"><div class="form-label">제공일시</div>
            <div style="display:flex; flex-wrap:nowrap; gap:2px; flex:1; align-items:center; font-size:11px; white-space:nowrap; overflow:hidden;">
                ${buildInput('startDate', '', 'width:105px; padding:0 2px;', '', 'date')}
                ${buildInput('startHH', 'HH', 'width:24px; text-align:center; padding:0;', 'maxlength="2"')}시
                ${buildInput('startMI', 'MM', 'width:24px; text-align:center; padding:0;', 'maxlength="2"')}분~
                ${buildInput('endDate', '', 'width:105px; padding:0 2px;', '', 'date')}
                ${buildInput('endHH', 'HH', 'width:24px; text-align:center; padding:0;', 'maxlength="2"')}시
                ${buildInput('endMI', 'MM', 'width:24px; text-align:center; padding:0;', 'maxlength="2"')}분
            </div>
        </div>
        
        <div class="form-row"><div class="form-label"></div>
            <div style="display:flex; gap:5px; flex:1; align-items:center; font-size:10px;">
                제공횟수 ${buildInput('cnt_val', '1', 'width:30px; text-align:center')}회, 
                이동소요 ${buildInput('mvmnReqreHr_val', '0', 'width:40px; text-align:center')}분
            </div>
        </div>
        
        <div class="form-row"><div class="form-label">서비스내용</div>${buildInput('desc_val', '서비스 내용 입력')}</div>
        <div class="form-row"><div class="form-label">상담소견</div>${buildInput('opn_val', '상담 소견 입력')}</div>
    </div>
    `;
}

// 특정 폼의 내용을 다른 모든 폼에 복사하는 기능
window.copyManualFormToAll = function (sourceTabId) {
    const fields = ['provCd', 'provTyCd', 'svcClassDetailCd', 'svcExecRecipientTyCd', 'svcExecRecipientId', 'provMeansCd', 'svcProvLocCd', 'svcProvLocEtc',
        'startDate', 'startHH', 'startMI', 'endDate', 'endHH', 'endMI', 'cnt_val', 'mvmnReqreHr_val', 'desc_val', 'opn_val'];

    fields.forEach(field => {
        const sourceEl = document.querySelector(`.manual-input-${field}[data-tabid="${sourceTabId}"]`);
        if (!sourceEl) return;
        const val = sourceEl.value;

        document.querySelectorAll(`.manual-input-${field}`).forEach(targetEl => {
            if (targetEl.dataset.tabid != sourceTabId) {
                targetEl.value = val;
            }
        });
    });

    // 다중 선택 리스트 복사
    document.querySelectorAll(`.list-builder-container`).forEach(targetContainer => {
        if (targetContainer.dataset.tabid != sourceTabId) {
            const field = targetContainer.dataset.field;
            const sourceItems = Array.from(document.querySelectorAll(`.list-builder-container[data-tabid="${sourceTabId}"][data-field="${field}"] .builder-item`));
            const targetList = targetContainer.querySelector(`.builder-list-${field}`);
            targetList.innerHTML = '';
            sourceItems.forEach(item => {
                renderBuilderItem(targetList, item.dataset.value, item.dataset.text, item.dataset.tycd);
            });
        }
    });

    // 복사한 뒤에도 임시저장 트리거 수행
    saveManualFormState();
};

// 리스트 빌더에 항목 추가
window.addListItem = function (field, tabId) {
    const container = document.querySelector(`.list-builder-container[data-field="${field}"][data-tabid="${tabId}"]`);
    const select = container.querySelector(`.builder-select-${field}`);
    const list = container.querySelector(`.builder-list-${field}`);

    let tyCd = '';
    if (field === 'svcExecRecipientId') {
        const group = document.getElementById(`manual-form-${tabId}`);
        const tySelect = group.querySelector('.manual-input-svcExecRecipientTyCd');
        if (tySelect) tyCd = tySelect.value;
    }

    if (!select.value) return;

    // 중복 체크
    if (Array.from(list.querySelectorAll('.builder-item')).some(el => el.dataset.value === select.value)) {
        alert('이미 추가된 항목입니다.');
        return;
    }

    renderBuilderItem(list, select.value, select.options[select.selectedIndex].text, tyCd);
    saveManualFormState();
};

function renderBuilderItem(parent, value, text, tyCd = '') {
    const item = document.createElement('span');
    item.className = 'builder-item';
    item.dataset.value = value;
    item.dataset.text = text;
    if (tyCd) item.dataset.tycd = tyCd;
    item.style.cssText = 'background:#e0f2f1; border:1px solid #80cbc4; border-radius:12px; padding:1px 8px; font-size:10px; display:inline-flex; align-items:center; gap:4px; color:#00695c;';
    item.innerHTML = `${text} <span class="builder-remove-btn" style="cursor:pointer; font-weight:bold; color:#b71c1c;">×</span>`;
    parent.appendChild(item);
}

// 수동 일괄 기입 실행
document.getElementById('manual-fill-btn').onclick = () => {
    const formGroups = document.querySelectorAll('.manual-form-group');
    if (formGroups.length === 0) return alert('기입할 창이 없습니다.');

    const confirmMsg = `현재 작성된 내용으로 ${formGroups.length}개의 창에 기입을 시작하시겠습니까?`;
    if (!confirm(confirmMsg)) return;

    formGroups.forEach((group, i) => {
        const tabId = parseInt(group.id.replace('manual-form-', ''));
        const getVal = (id) => {
            const el = group.querySelector(`.manual-input-${id}`);
            return el ? el.value : '';
        };

        // 리스트 빌더 데이터 수집 (담당자, 대상자 등) - 단순 텍스트
        const getListBuilderVal = (id) => {
            const items = group.querySelectorAll(`.list-builder-container[data-field="${id}"] .builder-item`);
            return Array.from(items).map(it => it.dataset.text).join(',');
        };

        // 리스트 빌더 데이터 수집 (담당자, 대상자 등) - 전체 정보 (공백 제거 보완)
        const getListBuilderFullVal = (id) => {
            const items = group.querySelectorAll(`.list-builder-container[data-field="${id}"] .builder-item`);
            return Array.from(items).map(it => ({
                value: it.dataset.value,
                text: it.dataset.text.trim(),
                tyCd: (it.dataset.tycd || '').trim()
            }));
        };

        // 날짜/시간 포맷 조합 (YYYY-MM-DD HH:MM~HH:MM)
        const sd = getVal('startDate');
        const sh = getVal('startHH');
        const sm = getVal('startMI');
        const ed = getVal('endDate');
        const eh = getVal('endHH');
        const em = getVal('endMI');
        let dateTime_val = '';
        if (sd && sh && sm && ed && eh && em) {
            dateTime_val = `${sd} ${sh}:${sm}~${eh}:${em}`;
        }

        // 대상자 텍스트 조합
        let recipientName = '';
        const recIdEl = group.querySelector(`.manual-input-svcExecRecipientId`);
        if (recIdEl && recIdEl.selectedIndex > 0) {
            recipientName = recIdEl.options[recIdEl.selectedIndex].text;
        }

        // 엑셀에서 추출되는 동일한 형태의 데이터 객체 생성 (content.js 호환)
        const record = {
            id: `수동-${i + 1}`,
            provCd_val: getVal('provCd'),
            provTyCd_val: getVal('provTyCd'),
            svcClassDetailCd_val: getVal('svcClassDetailCd'),
            recipient_val: getListBuilderVal('svcExecRecipientId'),
            recipient_fullVal: getListBuilderFullVal('svcExecRecipientId'),
            recipientTy_val_raw: getVal('svcExecRecipientTyCd'),
            provMeansCd_val: getVal('provMeansCd'),
            loc_val: getVal('svcProvLocCd'),
            locEtc_val_raw: getVal('svcProvLocEtc'),
            pic_val: getListBuilderVal('picId'),
            pic_fullVal: getListBuilderFullVal('picId'),
            dateTime_val: dateTime_val,
            mvmnReqreHr_val: getVal('mvmnReqreHr_val'),
            desc_val: getVal('desc_val'),
            opn_val: getVal('opn_val'),
            cnt_val: getVal('cnt_val') || 1
        };

        console.log(`[dbauto-popup] Sending data to tab ${tabId}:`, record);
        chrome.tabs.sendMessage(tabId, { action: 'START_AUTO_FILL', data: record }, (res) => {
            if (chrome.runtime.lastError) console.error(`기입 실패 (탭 ${tabId}):`, chrome.runtime.lastError);
        });
    });

    alert('수동 일괄 입력 요청이 각 창에 발송되었습니다. 창마다 빨간색 필드가 없는지 확인하세요.');

    // 전송 후 입력 폼 초기화(임시저장 비우기)할지 의견 조율될 때까진 남겨둠.
};

// ==========================================
// 엑셀 데이터 파싱 등 기존 코드 시작
// ==========================================

// 파일 업로드 관련
document.getElementById('drop-zone').addEventListener('click', () => document.getElementById('file-input').click());
document.getElementById('file-input').addEventListener('change', handleFile);
document.getElementById('drop-zone').addEventListener('dragover', (e) => { e.preventDefault(); e.target.style.background = '#f3e5f5'; });
document.getElementById('drop-zone').addEventListener('dragleave', (e) => { e.preventDefault(); e.target.style.background = '#fff'; });
document.getElementById('drop-zone').addEventListener('drop', (e) => {
    e.preventDefault();
    e.target.style.background = '#fff';
    if (e.dataTransfer.files.length > 0) handleFile({ target: { files: e.dataTransfer.files } });
});

function handleFile(e) {
    const file = e.target.files[0];
    if (!file) return;

    document.getElementById('status').innerText = '';
    const reader = new FileReader();
    reader.onload = function (e) {
        try {
            const data = new Uint8Array(e.target.result);
            const workbook = XLSX.read(data, { type: 'array' });
            const sheet = workbook.Sheets[workbook.SheetNames[0]];
            const rows = XLSX.utils.sheet_to_json(sheet, { header: 1 });

            const results = parseVerticalData(rows);
            if (results.length > 0) {
                saveToHistory(file.name, results);
                displayCurrentRecords(results);
                document.getElementById('current-section').classList.remove('hidden');
            }
        } catch (err) {
            document.getElementById('status').innerText = '분석 오류: ' + err.message;
        }
    };
    reader.readAsArrayBuffer(file);
}

function parseVerticalData(rows) {
    const results = [];
    for (let col = 1; col <= 7; col++) {
        if (!rows[4] || !rows[4][col]) continue;
        results.push({
            id: col,
            provCd_val: rows[2] ? rows[2][col] : '',
            provMeansCd_val: rows[3] ? rows[3][col] : '',
            svcClassDetailCd_val: rows[4] ? rows[4][col] : '',
            recipient_val: rows[5] ? rows[5][col] : '',
            dateTime_val: rows[6] ? rows[6][col] : '',
            loc_val: rows[7] ? rows[7][col] : '',
            pic_val: rows[8] ? rows[8][col] : '',
            cnt_val: rows[9] ? rows[9][col] : '',
            desc_val: rows[10] ? rows[10][col] : '',
            opn_val: rows[11] ? rows[11][col] : ''
        });
    }
    return results;
}

// 레코드 체크박스 선택 관리
function toggleRecordSelection(record, row) {
    const index = selectedRecords.findIndex(r => r.id === record.id);
    if (index > -1) {
        selectedRecords.splice(index, 1);
    } else {
        selectedRecords.push(record);
    }
    displayCurrentRecords(currentParsedData); // 순번 업데이트를 위해 전체 다시 그리기
    updateStatus();
}

// 탭 스캔
async function scanTargetTabs() {
    // 필터링 기준: localhost(프로토타입) 및 ncads(실제 시스템), 단 AnySign 설치창 등은 제외
    let tabs = await chrome.tabs.query({ url: ["*://localhost/*", "*://ncads.go.kr/*"] });
    targetTabs = tabs.filter(t => !t.url.includes('AnySignPlus'));

    // 이전에 선택했던 탭이 여전히 존재하는지 필터링
    selectedTabs = selectedTabs.filter(st => tabs.some(t => t.id === st.id));

    renderWindowList();
}

function renderWindowList() {
    const list = document.getElementById('window-list');
    list.innerHTML = '';

    if (targetTabs.length === 0) {
        list.innerHTML = '<div style="text-align:center; padding:10px; color:#999; font-size:11px;">감지된 시스템 창이 없습니다.</div>';
        return;
    }

    targetTabs.forEach((tab, i) => {
        const orderIndex = selectedTabs.findIndex(st => st.id === tab.id);
        const isSelected = orderIndex > -1;
        const color = isSelected ? MATCH_COLORS[orderIndex % MATCH_COLORS.length] : '#ccc';

        const row = document.createElement('div');
        row.className = `item-row ${isSelected ? 'selected' : ''}`;
        row.innerHTML = `
            <input type="checkbox" class="checkbox" ${isSelected ? 'checked' : ''}>
            ${isSelected ? `<span class="match-badge" style="background:${color}; color:#fff;">${orderIndex + 1}</span>` : `<span class="window-badge">창</span>`}
            <div class="item-info">
                <div class="item-title">${tab.title || '제목 없음'}</div>
                <div style="font-size: 10px; color: #999;">${tab.url.substring(0, 40)}...</div>
            </div>
        `;

        row.onmouseenter = () => chrome.tabs.sendMessage(tab.id, { action: 'HIGHLIGHT_TAB', active: true });
        row.onmouseleave = () => chrome.tabs.sendMessage(tab.id, { action: 'HIGHLIGHT_TAB', active: false });

        row.onclick = (e) => {
            const index = selectedTabs.findIndex(st => st.id === tab.id);
            if (index > -1) {
                selectedTabs.splice(index, 1);
            } else {
                selectedTabs.push(tab);
            }
            renderWindowList();
            updateStatus();
        };

        list.appendChild(row);
    });
}

function updateStatus() {
    const status = document.getElementById('status');
    if (selectedRecords.length > 0 || selectedTabs.length > 0) {
        status.innerText = `케이스 ${selectedRecords.length}개, 창 ${selectedTabs.length}개 선택됨`;
    } else {
        status.innerText = '파일을 대기 중입니다.';
    }
}

// 일괄 기입 실행
document.getElementById('batch-fill-btn').onclick = () => {
    if (selectedRecords.length === 0) return alert('기입할 케이스를 먼저 선택해주세요.');
    if (selectedTabs.length === 0) return alert('데이터를 넣을 대상 창을 아래 목록에서 클릭해 주세요.');

    const confirmMsg = `${selectedRecords.length}개의 데이터를 선택한 ${selectedTabs.length}개의 창에 입력하시겠습니까?`;
    if (!confirm(confirmMsg)) return;

    selectedRecords.forEach((record, i) => {
        // 선택된 창들에게 순서대로 배분
        const targetTab = selectedTabs[i % selectedTabs.length];
        chrome.tabs.sendMessage(targetTab.id, { action: 'START_AUTO_FILL', data: record }, (res) => {
            if (chrome.runtime.lastError) console.error(`기입 실패:`, chrome.runtime.lastError);
        });
    });

    alert('자동 입력이 시작되었습니다. 각 창의 미흡한 항목(빨간색)을 확인해 주세요.');
};

// UI 헬퍼
function createRecordElement(r, timestamp) {
    const orderIndex = selectedRecords.findIndex(sr => sr.id === r.id);
    const isSelected = orderIndex > -1;
    const color = isSelected ? MATCH_COLORS[orderIndex % MATCH_COLORS.length] : '#ccc';

    const row = document.createElement('div');
    row.className = `item-row ${isSelected ? 'selected' : ''}`;
    const timeStr = timestamp ? ` (${getRelativeTime(timestamp)})` : '';

    row.innerHTML = `
        <input type="checkbox" class="checkbox" ${isSelected ? 'checked' : ''}>
        ${isSelected ? `<span class="match-badge" style="background:${color}; color:#fff;">${orderIndex + 1}</span>` : `<span class="window-badge" style="background:#ccc;">데이터</span>`}
        <div class="item-info">
            <div class="item-title">케이스 ${r.id}: ${r.svcClassDetailCd_val || '-'}</div>
            <div class="item-tags">
                <span class="tag">🕒 ${r.dateTime_val || '일시 미입력'}</span>
                ${r.recipient_val ? `<span class="tag">👤 ${r.recipient_val}</span>` : ''}
                ${r.provMeansCd_val ? `<span class="tag">📞 ${r.provMeansCd_val}</span>` : ''}
                ${r.loc_val ? `<span class="tag">📍 ${r.loc_val}</span>` : ''}
                ${r.pic_val ? `<span class="tag">👨‍💼 ${r.pic_val}</span>` : ''}
            </div>
            ${timestamp ? `<div class="upload-time">업로드: ${getRelativeTime(timestamp)}</div>` : ''}
        </div>
    `;

    row.onclick = (e) => {
        toggleRecordSelection(r, row);
    };
    return row;
}

function displayCurrentRecords(records) {
    currentParsedData = records; // 전역 데이터 업데이트
    const list = document.getElementById('current-records');
    list.innerHTML = '';
    records.forEach(r => list.appendChild(createRecordElement(r)));
}

function loadHistory() {
    const list = document.getElementById('history-list');
    list.innerHTML = '로딩 중...';
    chrome.storage.local.get({ history: [] }, (data) => {
        list.innerHTML = '';
        if (data.history.length === 0) {
            list.innerHTML = '<div style="text-align:center; padding:20px; color:#999; font-size:12px;">기록이 없습니다.</div>';
            return;
        }
        data.history.forEach(entry => {
            const group = document.createElement('div');
            group.style.marginBottom = '15px';
            group.innerHTML = `<div style="font-size:11px; color:#7b1fa2; font-weight:bold; margin-bottom:5px; border-bottom:1px solid #eee;">📁 ${entry.fileName}</div>`;
            entry.records.forEach(r => group.appendChild(createRecordElement(r, entry.timestamp)));
            list.appendChild(group);
        });
    });
}

function saveToHistory(fileName, records) {
    chrome.storage.local.get({ history: [] }, (data) => {
        const history = data.history;
        history.unshift({ fileName, timestamp: Date.now(), records });
        if (history.length > 50) history.pop();
        chrome.storage.local.set({ history });
    });
}

function getRelativeTime(timestamp) {
    const diff = Date.now() - timestamp;
    const seconds = Math.floor(diff / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    if (hours > 0) return `${hours}시간 전`;
    if (minutes > 0) return `${minutes}분 전`;
    return `방금 전`;
}

document.getElementById('refresh-windows').onclick = scanTargetTabs;
document.getElementById('clear-history').onclick = () => {
    if (confirm('모든 기록을 삭제하시겠습니까?')) chrome.storage.local.set({ history: [] }, loadHistory);
};

// 초기화
scanTargetTabs();
setInterval(scanTargetTabs, 3000); // 주기적 갱신
