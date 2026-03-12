// =============================================
// standalone.js — 독립 실행형 프로토타입
// Chrome 확장 없이 작동, 단일 창(강화정) 전제
// =============================================

const CFG = {
    PROV_CD_MAP: { '제공': 'A', '부가업무': 'B', '거부': 'C' },
    MEANS_MAP: { '전화': 'A', '내방': 'B', '방문': 'C' },
    PROV_TY_MAP: { '아보전서비스': 'A', '연계서비스': 'B', '통합서비스': 'C' },
    LOCATION_MAP: { '기관내': 'A', '아동가정': 'B', '유관기관': 'C', '기타': 'X' },
    SERVICE_MAP: {
        '사례회의': '060524', '식사(식품)지원_식품지원': '010201',
        '생활용품지원_기타생활용품지원': '010501', '생활용품지원_의류지원': '010509',
        '복합지원_복지서비스물제공': '010703', '안전 및 인권교육_성폭력(예방)교육': '060103',
        '안전 및 인권교육_아동권리교육': '060101', '안전 및 인권교육_안전교육': '060104',
        '안전 및 인권교육_학대예방교육': '060102',
        '아동학대대상자 및 가족 지원_아동 안전점검 및 상담': '060501',
    },
    MATCH_COLORS: ['#42a5f5', '#66bb6a', '#ffa726', '#ec407a', '#26a69a', '#ab47bc', '#8d6e63'],
    FIELD_FINGERPRINTS: [
        { field: 'provCd_val', type: 'exact', values: ['제공', '부가업무', '거부'] },
        { field: 'provMeansCd_val', type: 'exact', values: ['전화', '내방', '방문'] },
        { field: 'loc_val', type: 'exact', values: ['기관내', '아동가정', '유관기관', '기타'] },
        { field: 'svcClassDetailCd_val', type: 'service' },
        { field: 'dateTime_val', type: 'regex', pattern: '\\d{4}[-/.]\\d{1,2}[-/.]\\d{1,2}' },
        { field: 'desc_val', type: 'freetext', priority: 1 },
        { field: 'opn_val', type: 'freetext', priority: 2 },
    ],
    HEADER_HINTS: {
        '제공구분': 'provCd_val', '제공유형': 'provTyCd_val', '유형': 'provTyCd_val',
        '제공방법': 'provMeansCd_val', '제공서비스': 'svcClassDetailCd_val', '서비스명': 'svcClassDetailCd_val',
        '대상자': 'recipient_val', '일시': 'dateTime_val', '날짜': 'dateTime_val',
        '장소': 'loc_val', '기타': 'locEtc_val_raw', '담당자': 'pic_val',
        '제공자': 'pic_val', '서비스제공자': 'pic_val', '횟수': 'cnt_val',
        '내용': 'desc_val', '소견': 'opn_val', '이동': 'mvmnReqreHr_val',
    },
};

const SERVICE_OPTIONS = [
    { value: '010509', text: '생활용품 지원 :: 의류지원' },
    { value: '060103', text: '안전 및 인권교육 :: 성폭력(예방)교육' },
    { value: '060524', text: '아동학대대상자 및 가족 지원 :: 사례회의' },
    { value: '060510', text: '아동학대대상자 및 가족 지원 :: 아동 양육기술 상담 및 교육' },
    { value: '010201', text: '식사(식품) 지원 :: 식품지원' },
    { value: '060101', text: '안전 및 인권교육 :: 아동권리교육' },
    { value: '060534', text: '아동학대대상자 및 가족 지원 :: 외부기관연계지원' },
    { value: '010703', text: '복합지원 :: 복지서비스정보물제공' },
    { value: '060104', text: '안전 및 인권교육 :: 안전교육' },
    { value: '060501', text: '아동학대대상자 및 가족 지원 :: 아동 안전점검 및 상담' },
    { value: '060522', text: '아동학대대상자 및 가족 지원 :: 사건처리 및 절차지원' },
    { value: '060102', text: '안전 및 인권교육 :: 학대예방교육' },
];

let selectedRecords = [];
let currentParsedData = [];
let activeWindowIdx = 0;

const WINDOWS = [
    { name: '강화정', masked: '강*정' },
    { name: '이민수', masked: '이*수' },
    { name: '박민규', masked: '박*규' },
];

// ═══════════════════════════════════════════
// Init
// ═══════════════════════════════════════════
document.addEventListener('DOMContentLoaded', () => {
    renderManualForm();
    initTabs();
    initExcelUpload();
    loadHistory();
    initBrowserTabs();
    renderWindowTabs();
});

function initTabs() {
    document.querySelectorAll('.main-tab').forEach(tab => {
        tab.addEventListener('click', () => {
            document.querySelectorAll('.main-tab').forEach(t => t.classList.remove('active'));
            tab.classList.add('active');
            const target = tab.dataset.tab;
            document.querySelectorAll('.tab-view').forEach(v => v.classList.add('hidden'));
            document.getElementById(
                target === 'manual' ? 'manual-view' : target === 'upload' ? 'upload-view' : 'history-view'
            ).classList.remove('hidden');
            if (target === 'history') loadHistory();
            document.querySelector('.sp-sticky-bar').style.display = target === 'manual' ? 'flex' : 'none';
        });
    });
}

function togglePanel() {
    const panel = document.getElementById('right-panel');
    const btn = document.getElementById('reopen-panel-btn');
    const collapsed = panel.classList.toggle('collapsed');
    btn.style.display = collapsed ? 'flex' : 'none';
}

// ═══════════════════════════════════════════
// Browser Tab Bar (왼쪽 패널 상단)
// ═══════════════════════════════════════════
function initBrowserTabs() {
    document.getElementById('browser-tab-bar').addEventListener('click', (e) => {
        const tab = e.target.closest('.browser-tab');
        if (!tab) return;
        const idx = parseInt(tab.dataset.win);
        switchWindow(idx);
    });
}

function switchWindow(idx) {
    activeWindowIdx = idx;
    // 브라우저 탭 활성화
    document.querySelectorAll('.browser-tab').forEach((t, i) => {
        t.classList.toggle('active', i === idx);
    });
    // 확장프로그램 패널 window-tab 활성화
    document.querySelectorAll('.window-tab').forEach((t, i) => {
        t.classList.toggle('window-tab-active', i === idx);
    });
    
    // iframe 내용 갱신 (index_8000.html, index_8001.html, index_8002.html)
    const iframe = document.getElementById('proto-frame');
    iframe.src = `index_800${idx}.html`;

    // 패널 헤더 및 폼 내용 갱신
    renderManualForm();
}

// ═══════════════════════════════════════════
// Window Tabs in Extension Panel (Masked)
// ═══════════════════════════════════════════
function renderWindowTabs() {
    const container = document.getElementById('window-tab-container');
    container.innerHTML = WINDOWS.map((w, i) => `
        <div class="window-tab ${i === activeWindowIdx ? 'window-tab-active' : ''}" data-win="${i}">
            창${i+1} · ${w.masked}
        </div>
    `).join('');
    container.addEventListener('click', (e) => {
        const tab = e.target.closest('.window-tab');
        if (!tab) return;
        switchWindow(parseInt(tab.dataset.win));
    });
}

// ═══════════════════════════════════════════
// Manual Form
// ═══════════════════════════════════════════
function renderManualForm() {
    const container = document.getElementById('manual-form-container');
    container.innerHTML = createFormHtml();
    container.addEventListener('click', handleClick);
    container.addEventListener('input', handleInput);
    container.addEventListener('change', handleChange);
}

function createFormHtml() {
    const today = new Date().toISOString().slice(0, 10);
    const chipGroup = (id, items, defaultVal) => {
        const chips = items.map(it => {
            const active = it.value === defaultVal ? ' chip-active' : '';
            return `<button type="button" class="chip${active}" data-field="${id}" data-value="${it.value}">${it.text}</button>`;
        }).join('');
        return `<input type="hidden" class="form-input fi-${id}" value="${defaultVal || ''}"><div class="chip-group">${chips}</div>`;
    };
    // 제공장소 2×2 그리드 (기관내/아동가정 위, 유관기관/기타 아래)
    const locChipGroup = (id, defaultVal) => {
        const items = [
            {value:'A', text:'기관내'}, {value:'B', text:'아동가정'},
            {value:'C', text:'유관기관'}, {value:'X', text:'기타'}
        ];
        const chips = items.map(it => {
            const active = it.value === defaultVal ? ' chip-active' : '';
            return `<button type="button" class="chip${active}" data-field="${id}" data-value="${it.value}">${it.text}</button>`;
        }).join('');
        return `<input type="hidden" class="form-input fi-${id}" value="${defaultVal || ''}">
                <div class="chip-group chip-group-2col">${chips}</div>`;
    };
    const svcSelect = SERVICE_OPTIONS.map(o => `<option value="${o.value}">${o.text}</option>`).join('');

    return `
    <div class="manual-form-group" id="form-main">
        <div class="panel-header">
            <span class="panel-victim">피해아동: ${WINDOWS[activeWindowIdx].name}</span>
            <button class="refresh-single-btn" onclick="resetAllForms()">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.59-9.21l5.67-5.67"/></svg>
            </button>
        </div>

        <div class="form-row"><div class="form-label">제공구분</div>
            ${chipGroup('provCd', [{value:'A',text:'제공'},{value:'B',text:'부가업무'},{value:'C',text:'거부'}], 'A')}
        </div>
        <div class="form-row"><div class="form-label">제공방법</div>
            ${chipGroup('provMeansCd', [{value:'A',text:'전화'},{value:'C',text:'방문'},{value:'B',text:'내방'}], 'A')}
        </div>
        <div class="form-row"><div class="form-label">서비스유형</div>
            ${chipGroup('provTyCd', [{value:'A',text:'아보전서비스'},{value:'B',text:'연계서비스'},{value:'C',text:'통합서비스'}], 'A')}
        </div>
        <div class="form-row"><div class="form-label">제공서비스</div>
            <select class="styled-select form-input fi-svcClassDetailCd"><option value="">선택</option>${svcSelect}</select>
        </div>

        <div class="form-row" style="align-items:flex-start;"><div class="form-label" style="padding-top:6px;">제공장소</div>
            <div style="flex:1;">
                ${locChipGroup('svcProvLocCd', 'A')}
                <input type="text" class="form-input fi-svcProvLocEtc" placeholder="기타 장소" style="margin-top:6px;width:100%;box-sizing:border-box;">
            </div>
        </div>

        <div class="form-row"><div class="form-label">제공일시</div>
            <div style="display:flex;flex-direction:column;gap:6px;flex:1;font-size:14px;">
                <div style="display:flex;align-items:center;gap:4px;">
                    <input type="hidden" class="form-input fi-startDate manual-input-startDate" id="dp-start" value="${today}">
                    <button type="button" class="date-trigger" data-for="dp-start" data-isstart="true">${today}</button>
                    <input type="text" class="form-input fi-startHH manual-input-startHH" placeholder="HH" style="width:36px;text-align:center;" maxlength="2">시
                    <input type="text" class="form-input fi-startMI manual-input-startMI" placeholder="MM" style="width:36px;text-align:center;" maxlength="2">분~
                </div>
                <div style="display:flex;align-items:center;gap:4px;">
                    <input type="hidden" class="form-input fi-endDate manual-input-endDate" id="dp-end" value="${today}">
                    <button type="button" class="date-trigger" data-for="dp-end">${today}</button>
                    <input type="text" class="form-input fi-endHH manual-input-endHH" placeholder="HH" style="width:36px;text-align:center;" maxlength="2">시
                    <input type="text" class="form-input fi-endMI manual-input-endMI" placeholder="MM" style="width:36px;text-align:center;" maxlength="2">분
                </div>
            </div>
        </div>

        <div class="form-row"><div class="form-label"></div>
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;flex:1;font-size:14px;">
                <div style="display:flex;align-items:center;gap:6px;">
                    <span style="white-space:nowrap;">제공횟수</span>
                    <input type="hidden" class="form-input fi-cnt_val" value="1">
                    <span class="stepper" data-field="cnt_val" data-min="1" data-max="100">
                        <button type="button" class="stepper-btn stepper-minus" disabled>−</button>
                        <span class="stepper-val">1</span>
                        <button type="button" class="stepper-btn stepper-plus">+</button>
                    </span>회
                </div>
                <div style="display:flex;align-items:center;gap:6px;">
                    <span style="white-space:nowrap;">이동소요</span>
                    <input type="hidden" class="form-input fi-mvmnReqreHr_val" value="0">
                    <span class="stepper" data-field="mvmnReqreHr_val" data-min="0" data-max="999">
                        <button type="button" class="stepper-btn stepper-minus" data-delta="-5" disabled>−5</button>
                        <button type="button" class="stepper-btn stepper-minus" data-delta="-1" disabled>−1</button>
                        <span class="stepper-val">0</span>
                        <button type="button" class="stepper-btn stepper-plus" data-delta="1">+1</button>
                        <button type="button" class="stepper-btn stepper-plus" data-delta="5">+5</button>
                    </span>분
                </div>
            </div>
        </div>

        <div class="form-row" style="align-items:flex-start;"><div class="form-label" style="padding-top:12px;">서비스내용</div>
            <div style="flex:1;position:relative;">
                <textarea class="form-input fi-desc_val" placeholder="서비스  내용  입력" rows="2"></textarea>
                <div class="expand-btn" data-field="desc_val">+ 확대</div>
            </div>
        </div>
        <div class="form-row" style="align-items:flex-start;"><div class="form-label" style="padding-top:12px;">상담원 소견</div>
            <div style="flex:1;position:relative;">
                <textarea class="form-input fi-opn_val" placeholder="상담원  소견  입력" rows="2"></textarea>
                <div class="expand-btn" data-field="opn_val">+ 확대</div>
            </div>
        </div>
    </div>`;
}

// ─── Event Handlers ───
function handleClick(e) {
    const chip = e.target.closest('.chip');
    if (chip) {
        const field = chip.dataset.field;
        chip.parentElement.querySelectorAll('.chip').forEach(c => c.classList.remove('chip-active'));
        chip.classList.add('chip-active');
        const h = document.querySelector(`.fi-${field}`);
        if (h) h.value = chip.dataset.value;
        return;
    }
    const stepperBtn = e.target.closest('.stepper-btn');
    if (stepperBtn) {
        const stepper = stepperBtn.closest('.stepper');
        const field = stepper.dataset.field;
        const min = parseInt(stepper.dataset.min) || 0;
        const max = parseInt(stepper.dataset.max) || 999;
        const h = document.querySelector(`.fi-${field}`);
        if (!h) return;
        let val = parseInt(h.value) || 0;
        const delta = stepperBtn.dataset.delta ? parseInt(stepperBtn.dataset.delta) : (stepperBtn.classList.contains('stepper-minus') ? -1 : 1);
        val = Math.max(min, Math.min(max, val + delta));
        h.value = val;
        stepper.querySelector('.stepper-val').textContent = val;
        stepper.querySelectorAll('.stepper-minus').forEach(b => { b.disabled = val + (parseInt(b.dataset.delta) || -1) < min; });
        stepper.querySelectorAll('.stepper-plus').forEach(b => { b.disabled = val + (parseInt(b.dataset.delta) || 1) > max; });
        return;
    }
    const expandBtn = e.target.closest('.expand-btn');
    if (expandBtn) {
        const ta = document.querySelector(`.fi-${expandBtn.dataset.field}`);
        if (ta) openExpandModal(ta);
        return;
    }
    const dateTrigger = e.target.closest('.date-trigger');
    if (dateTrigger) {
        const inputId = dateTrigger.dataset.for;
        const input = document.getElementById(inputId);
        const isStart = dateTrigger.dataset.isstart === 'true';
        openDatePicker(dateTrigger, input, isStart);
        return;
    }
}

function handleInput(e) {
    if (e.target.tagName === 'TEXTAREA') {
        e.target.style.height = 'auto';
        e.target.style.height = e.target.scrollHeight + 'px';
    }
}
function handleChange(e) {
    if (e.target.matches('select.styled-select')) e.target.classList.toggle('has-value', !!e.target.value);
}

// ─── Build Record & Fill ───
function buildRecord() {
    const g = (f) => { const el = document.querySelector(`.fi-${f}`); return el ? el.value : ''; };
    const sd = g('startDate'), sh = g('startHH'), sm = g('startMI');
    const ed = g('endDate'),   eh = g('endHH'),   em = g('endMI');
    let dateTime_val = '';
    if (sd && sh && sm && ed && eh && em) dateTime_val = `${sd} ${sh}:${sm}~${eh}:${em}`;
    return {
        provCd_val: g('provCd'), provTyCd_val: g('provTyCd'),
        svcClassDetailCd_val: g('svcClassDetailCd'),
        provMeansCd_val: g('provMeansCd'),
        loc_val: g('svcProvLocCd'), locEtc_val_raw: g('svcProvLocEtc'),
        dateTime_val, mvmnReqreHr_val: g('mvmnReqreHr_val'),
        desc_val: g('desc_val'), opn_val: g('opn_val'), cnt_val: g('cnt_val') || '1',
    };
}

function handleSingleFill() {
    const rec = buildRecord();
    const iframe = document.getElementById('proto-frame');
    if (!iframe?.contentDocument) { alert('iframe 접근 오류'); return; }
    autoFillIframe(iframe.contentDocument, rec);
    alert('입력이 완료되었습니다.');
}
function handleExcelAutoFill() {
    if (!selectedRecords.length) { alert('데이터를 선택해주세요.'); return; }
    const iframe = document.getElementById('proto-frame');
    if (!iframe?.contentDocument) return;
    autoFillIframe(iframe.contentDocument, selectedRecords[0]);
    alert('입력이 완료되었습니다.');
}

function autoFillIframe(doc, data) {
    if (!doc.getElementById('dbauto-styles')) {
        const s = doc.createElement('style'); s.id = 'dbauto-styles';
        s.innerHTML = `.dbauto-ok{border:2px solid #C2FFA7!important;box-shadow:0 0 8px #C2FFA7!important;transition:all .5s}.dbauto-fail{border:2px dashed #ff5252!important;background:#fff1f1!important}`;
        doc.head.appendChild(s);
    }
    doc.querySelectorAll('.dbauto-ok,.dbauto-fail').forEach(el => el.classList.remove('dbauto-ok','dbauto-fail'));

    const fill = (id, val) => {
        const el = doc.getElementById(id); if (!el || !val) return;
        el.value = val;
        ['input','change','blur'].forEach(ev => el.dispatchEvent(new Event(ev, {bubbles:true})));
        el.classList.add('dbauto-ok'); setTimeout(() => el.classList.remove('dbauto-ok'), 1500);
    };

    // Radio for 제공구분
    const r = doc.querySelector(`input[name="provCd"][value="${data.provCd_val || 'A'}"]`);
    if (r) r.checked = true;

    fill('provMeansCd',      data.provMeansCd_val);
    fill('provTyCd',         data.provTyCd_val);
    fill('svcClassDetailCd', data.svcClassDetailCd_val);
    fill('svcProvLocCd',     data.loc_val);
    if (data.locEtc_val_raw) fill('svcProvLocEtc', data.locEtc_val_raw);
    fill('svcProvCnt', data.cnt_val);
    fill('mvmnReqreHr', data.mvmnReqreHr_val);
    fill('svcProvDesc', data.desc_val);
    fill('consOpn',     data.opn_val);

    if (data.dateTime_val) {
        const [datePart, timePart] = data.dateTime_val.split(' ');
        if (datePart) { fill('svcProvStartDate', datePart); fill('svcProvEndDate', datePart); }
        if (timePart && timePart.includes('~')) {
            const [s, e] = timePart.split('~');
            fill('svcProvStartHH', s.split(':')[0]); fill('svcProvStartMI', s.split(':')[1]);
            fill('svcProvEndHH',   e.split(':')[0]); fill('svcProvEndMI',   e.split(':')[1]);
        }
    }
}

function resetAllForms() { renderManualForm(); }

// ═══════════════════════════════════════════
// Excel
// ═══════════════════════════════════════════
function initExcelUpload() {
    const dz = document.getElementById('drop-zone'), fi = document.getElementById('file-input');
    dz.onclick = () => fi.click();
    fi.onchange = (e) => handleExcelFile(e.target.files[0]);
    dz.ondragover = (e) => { e.preventDefault(); dz.style.background = '#e8ffd9'; };
    dz.ondragleave  = () => dz.style.background = '#fff';
    dz.ondrop = (e) => { e.preventDefault(); dz.style.background = '#fff'; handleExcelFile(e.dataTransfer.files[0]); };
}
function handleExcelFile(file) {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (e) => {
        const wb = XLSX.read(new Uint8Array(e.target.result), {type:'array'});
        const res = [];
        wb.SheetNames.forEach(n => {
            const rows = XLSX.utils.sheet_to_json(wb.Sheets[n], {header:1});
            const parsed = parseVerticalData(rows);
            if (parsed.length) res.push({sheetName:n, records:parsed});
        });
        if (res.length) {
            saveHistory(file.name, res); displayExcelRecords(res);
            document.getElementById('current-section').classList.remove('hidden');
            document.getElementById('excel-window-section').classList.remove('hidden');
        } else {
            document.getElementById('status').textContent = '파싱 가능한 데이터가 없습니다.';
        }
    };
    reader.readAsArrayBuffer(file);
}
function displayExcelRecords(res) {
    const container = document.getElementById('current-records');
    currentParsedData = []; res.forEach(s => currentParsedData.push(...s.records));
    selectedRecords = []; container.innerHTML = '';
    document.querySelector('.excel-section-title').textContent = `추출된 서비스 목록 (${currentParsedData.length}건)`;
    currentParsedData.forEach(r => container.appendChild(createRecordElement(r)));
}
function createRecordElement(r) {
    const idx = selectedRecords.findIndex(s => s.id === r.id);
    const isSel = idx > -1;
    const row = document.createElement('div');
    row.className = `item-row ${isSel ? 'selected' : ''}`;
    row.innerHTML = `
        <input type="checkbox" class="checkbox" ${isSel ? 'checked' : ''}>
        <span class="${isSel ? 'match-badge' : 'window-badge'}" style="${isSel ? 'background:'+CFG.MATCH_COLORS[idx%7]+';color:#fff' : ''}">${isSel ? idx+1 : '서비스'}</span>
        <div class="item-info">
            <div class="item-title">${r.svcClassDetailCd_val || '서비스'}</div>
            <div class="item-tags"><span class="tag">🕒 ${r.dateTime_val||'-'}</span><span class="tag">📍 ${r.loc_val||'-'}</span></div>
        </div>`;
    row.onclick = () => {
        const i = selectedRecords.findIndex(s => s.id === r.id);
        if (i > -1) selectedRecords.splice(i, 1); else selectedRecords.push(r);
        const c = document.getElementById('current-records'); c.innerHTML = '';
        currentParsedData.forEach(rc => c.appendChild(createRecordElement(rc)));
    };
    return row;
}
function parseVerticalData(rows) {
    const serviceMapKeys = Object.keys(CFG.SERVICE_MAP);
    const fps = CFG.FIELD_FINGERPRINTS;
    const hints = CFG.HEADER_HINTS;
    let maxCol = 0;
    rows.forEach(r => { if (r) maxCol = Math.max(maxCol, r.length - 1); });
    const dataCols = []; for (let c = 1; c <= Math.min(maxCol, 20); c++) dataCols.push(c);
    const rowFieldMap = {}, usedFields = new Set(), unmatched = [];
    rows.forEach((row, ri) => {
        if (!row) return;
        const cellVals = dataCols.map(c => (row[c]!=null)?row[c].toString().trim():'').filter(v=>v);
        if (!cellVals.length) return;
        let best = null, bestScore = 0;
        for (const fp of fps) {
            if (fp.type === 'freetext' || usedFields.has(fp.field)) continue;
            let score = 0;
            if (fp.type === 'exact') score = cellVals.filter(v => fp.values.includes(v)).length;
            else if (fp.type === 'regex') { const rx = new RegExp(fp.pattern); score = cellVals.filter(v => rx.test(v)).length; }
            else if (fp.type === 'service') score = cellVals.filter(v => serviceMapKeys.some(k => k.includes(v)||v.includes(k))).length;
            if (score > bestScore) { bestScore = score; best = fp.field; }
        }
        if (best && bestScore >= Math.max(1, cellVals.length * 0.3)) { rowFieldMap[ri] = best; usedFields.add(best); }
        else unmatched.push(ri);
    });
    const stillUnmatched = [];
    for (const ri of unmatched) {
        const hText = String(rows[ri][0]||'').replace(/\s/g,'');
        let matched = false;
        for (const [kw, fn] of Object.entries(hints)) {
            if (usedFields.has(fn)) continue;
            if (hText.includes(kw.replace(/\s/g,''))) { rowFieldMap[ri] = fn; usedFields.add(fn); matched = true; break; }
        }
        if (!matched) stillUnmatched.push(ri);
    }
    const ftFields = fps.filter(fp => fp.type==='freetext' && !usedFields.has(fp.field)).sort((a,b)=>a.priority-b.priority);
    const ftCands = stillUnmatched.filter(ri => dataCols.some(c => rows[ri][c]?.toString().trim()));
    ftFields.forEach((fp,i) => { if (i < ftCands.length) { rowFieldMap[ftCands[i]] = fp.field; usedFields.add(fp.field); } });
    const results = [];
    for (const col of dataCols) {
        const hasData = Object.keys(rowFieldMap).some(ri => { const v = rows[ri]?.[col]; return v!=null && v.toString().trim(); });
        if (!hasData) continue;
        const rec = { id: col };
        for (const [ri, fn] of Object.entries(rowFieldMap)) {
            const v = rows[ri]?.[col]; rec[fn] = (v!=null) ? v.toString().trim() : '';
        }
        results.push(rec);
    }
    return results;
}
function saveHistory(n, r) {
    const h = JSON.parse(localStorage.getItem('dash_history')||'[]');
    h.unshift({fileName:n, timestamp:Date.now(), sheetResults:r});
    localStorage.setItem('dash_history', JSON.stringify(h.slice(0,50)));
}
function loadHistory() {
    const list = document.getElementById('history-list');
    const h = JSON.parse(localStorage.getItem('dash_history')||'[]');
    if (!h.length) { list.innerHTML = '<div style="text-align:center;padding:20px;color:#999;font-size:14px;">기록이 없습니다.</div>'; return; }
    list.innerHTML = '';
    h.forEach(entry => {
        const d = new Date(entry.timestamp);
        const ds = `${d.getFullYear()}.${String(d.getMonth()+1).padStart(2,'0')}.${String(d.getDate()).padStart(2,'0')} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;
        const div = document.createElement('div'); div.style.marginBottom = '16px';
        div.innerHTML = `<div style="display:flex;justify-content:space-between;align-items:center;font-size:13px;margin-bottom:6px;border-bottom:1px solid #eee;padding-bottom:6px;"><span style="font-weight:bold;">📁 ${entry.fileName}</span><span style="color:#aaa;font-size:12px;">${ds}</span></div>`;
        if (entry.sheetResults) entry.sheetResults.forEach(s => s.records.forEach(r => div.appendChild(createRecordElement(r))));
        list.appendChild(div);
    });
}
function clearHistory() { if (confirm('모든 기록을 삭제하시겠습니까?')) { localStorage.removeItem('dash_history'); loadHistory(); } }

// ═══════════════════════════════════════════
// Expand Modal
// ═══════════════════════════════════════════
function openExpandModal(ta) {
    const ov = document.createElement('div'); ov.className = 'expand-modal-overlay';
    ov.innerHTML = `<div class="expand-modal">
        <div class="expand-modal-header"><span style="font-weight:600;font-size:16px;">📝 텍스트 편집</span><button class="expand-modal-close">✕</button></div>
        <textarea class="expand-modal-textarea">${ta.value}</textarea>
        <div class="expand-modal-footer"><span class="expand-modal-count">${ta.value.length}자</span><button class="expand-modal-save">저장</button></div>
    </div>`;
    document.body.appendChild(ov);
    const inner = ov.querySelector('.expand-modal-textarea'), cnt = ov.querySelector('.expand-modal-count');
    inner.focus(); inner.addEventListener('input', () => cnt.textContent = inner.value.length + '자');
    const close = () => ov.remove();
    ov.querySelector('.expand-modal-close').onclick = close;
    ov.addEventListener('click', e => { if (e.target === ov) close(); });
    ov.querySelector('.expand-modal-save').onclick = () => { ta.value = inner.value; ta.style.height = 'auto'; ta.style.height = ta.scrollHeight + 'px'; close(); };
}

// ═══════════════════════════════════════════
// Date Picker  (원래 디자인 그대로 복원)
// ═══════════════════════════════════════════
const DP = {
    overlay: null, picker: null,
    displayEl: null, targetEl: null,
    year: 0, month: 0,
    selectedDate: '', selectedTime: '', selectedDuration: 0,
    isStart: false,

    open(displayEl, inputEl, isStart) {
        this.close();
        this.displayEl = displayEl;
        this.targetEl  = inputEl;
        this.isStart   = isStart;
        const val = inputEl?.value || new Date().toISOString().slice(0,10);
        const p = val.split('-');
        this.year  = parseInt(p[0]) || new Date().getFullYear();
        this.month = (parseInt(p[1]) || new Date().getMonth()+1) - 1;
        this.selectedDate = val;
        this.selectedTime = '';
        this.selectedDuration = 0;
        this.overlay = document.createElement('div');
        this.overlay.className = 'dp-overlay dp-overlay-panel';
        this.overlay.addEventListener('click', e => { if (e.target === this.overlay) this.close(); });
        this.picker = document.createElement('div');
        this.picker.className = 'dp-picker';
        this.overlay.appendChild(this.picker);
        // 오버레이를 right-panel 기준으로 배치
        const panel = document.getElementById('right-panel');
        (panel || document.body).appendChild(this.overlay);
        this.render();
    },

    close() {
        if (this.overlay) { this.overlay.remove(); this.overlay = null; this.picker = null; }
    },

    render() {
        const { year, month, selectedDate, selectedTime, selectedDuration, isStart } = this;
        const today = new Date();
        const todayStr = `${today.getFullYear()}-${String(today.getMonth()+1).padStart(2,'0')}-${String(today.getDate()).padStart(2,'0')}`;
        const monthNames = ['1월','2월','3월','4월','5월','6월','7월','8월','9월','10월','11월','12월'];
        const firstDay   = new Date(year, month, 1).getDay();
        const daysInMon  = new Date(year, month+1, 0).getDate();
        const daysInPrev = new Date(year, month, 0).getDate();
        const offset     = (firstDay + 6) % 7; // 월=0

        let html = `<div class="dp-container"><div class="dp-left">`;
        html += `<div class="dp-header">
            <button class="dp-nav dp-prev">‹</button>
            <span class="dp-title">${year}년 ${monthNames[month]}</span>
            <button class="dp-nav dp-next">›</button>
        </div>
        <div class="dp-weekdays"><span>월</span><span>화</span><span>수</span><span>목</span><span>금</span><span class="dp-sat">토</span><span class="dp-sun">일</span></div>
        <div class="dp-days">`;

        for (let i = offset-1; i >= 0; i--) html += `<span class="dp-day dp-other">${daysInPrev-i}</span>`;
        for (let d = 1; d <= daysInMon; d++) {
            const ds = `${year}-${String(month+1).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
            const cls = ['dp-day'];
            if (ds === todayStr) cls.push('dp-today');
            if (ds === selectedDate) cls.push('dp-selected');
            html += `<span class="${cls.join(' ')}" data-date="${ds}">${d}</span>`;
        }
        const total = offset + daysInMon, rem = (7 - total%7)%7;
        for (let i = 1; i <= rem; i++) html += `<span class="dp-day dp-other">${i}</span>`;
        html += `</div><div class="dp-footer"><button class="dp-apply-btn">✦ 적용하기</button></div></div>`;

        if (isStart) {
            let hdr = '날짜를 먼저 선택하세요';
            if (selectedDate) {
                const dObj = new Date(selectedDate);
                const days = ['일','월','화','수','목','금','토'];
                hdr = `${dObj.getMonth()+1}월 ${dObj.getDate()}일 (${days[dObj.getDay()]})<br>시작 시간과 소요 시간을 알려주세요.`;
            }
            html += `<div class="dp-right">`;
            html += `<div class="dp-right-title">${hdr}</div>`;

            // 오전
            html += `<div class="dp-scroll-section" style="margin-bottom:8px;">`;
            html += `<div class="dp-section-title">오전</div><div class="dp-time-grid">`;
            for (let h = 9; h < 12; h++) for (let m = 0; m <= 30; m += 30) {
                const t = `${h}:${m===0?'00':'30'}`;
                html += `<div class="dp-time-btn ${selectedTime===t?'active':''}" data-time="${t}" data-hour="${h}">${t}</div>`;
            }
            html += `</div>`;

            // 오후
            html += `<div class="dp-section-title">오후</div><div class="dp-time-grid">`;
            for (let h = 12; h <= 21; h++) for (let m = 0; m <= 30; m += 30) {
                if (h===21 && m===30) continue;
                const dh = h > 12 ? h-12 : h;
                const t = `${dh}:${m===0?'00':'30'}`;
                html += `<div class="dp-time-btn ${selectedTime===t?'active':''}" data-time="${t}" data-hour="${h}">${t}</div>`;
            }
            html += `</div></div>`;

            // 소요시간
            html += `<div class="dp-scroll-section" style="border-top:1px dashed #e5e8eb;padding-top:12px;">`;
            html += `<div class="dp-section-title" style="margin-top:0;">상담 소요시간</div><div class="dp-time-grid">`;
            for (let t = 10; t <= 240; t += 10) {
                let txt;
                if (t < 60) txt = `${t}분`;
                else if (t === 60) txt = '1시간';
                else if (t % 60 === 0) txt = `${t/60}시간`;
                else txt = `${Math.floor(t/60)}시간 ${t%60}분`;
                html += `<div class="dp-duration-btn ${selectedDuration===t?'active':''}" data-dur="${t}">${txt}</div>`;
            }
            html += `</div></div></div>`;
        }
        html += `</div>`;
        this.picker.innerHTML = html;

        this.picker.querySelector('.dp-prev').onclick = () => { this.month--; if (this.month<0){this.month=11;this.year--;} this.render(); };
        this.picker.querySelector('.dp-next').onclick = () => { this.month++; if (this.month>11){this.month=0;this.year++;} this.render(); };
        this.picker.querySelectorAll('.dp-day:not(.dp-other)').forEach(el => el.onclick = () => {
            this.selectedDate = el.dataset.date;
            // 날짜 선택 시 스크롤 위치 보존
            const scrollEls = Array.from(this.picker.querySelectorAll('.dp-scroll-section'));
            const scrollTops = scrollEls.map(s => s.scrollTop);
            this.render();
            this.picker.querySelectorAll('.dp-scroll-section').forEach((s, i) => { s.scrollTop = scrollTops[i] || 0; });
        });
        // 시간/소요시간 버튼: active 클래스만 교체 (re-render 없이) → 스크롤 위치 유지
        this.picker.querySelectorAll('.dp-time-btn').forEach(el => el.onclick = () => {
            this.selectedTime = el.dataset.time;
            this.picker.querySelectorAll('.dp-time-btn').forEach(b => b.classList.remove('active'));
            el.classList.add('active');
        });
        this.picker.querySelectorAll('.dp-duration-btn').forEach(el => el.onclick = () => {
            this.selectedDuration = parseInt(el.dataset.dur);
            this.picker.querySelectorAll('.dp-duration-btn').forEach(b => b.classList.remove('active'));
            el.classList.add('active');
        });
        this.picker.querySelector('.dp-apply-btn').onclick = () => this.apply();
    },

    apply() {
        if (!this.selectedDate) { alert('날짜를 선택해주세요.'); return; }
        if (this.isStart && (!this.selectedTime || !this.selectedDuration)) {
            alert('시간과 상담 소요시간을 모두 선택해주세요.'); return;
        }
        // 날짜 기입
        if (this.targetEl) this.targetEl.value = this.selectedDate;
        if (this.displayEl) this.displayEl.textContent = this.selectedDate;

        if (this.isStart) {
            const activeBtn = this.picker.querySelector('.dp-time-btn.active');
            let hInt = 0, mInt = 0;
            if (activeBtn) {
                hInt = parseInt(activeBtn.dataset.hour);
                mInt = parseInt(activeBtn.dataset.time.split(':')[1]);
            }
            // 시작 HH/MI 채우기
            const hhEl = document.querySelector('.manual-input-startHH');
            const miEl = document.querySelector('.manual-input-startMI');
            if (hhEl) hhEl.value = String(hInt).padStart(2,'0');
            if (miEl) miEl.value = String(mInt).padStart(2,'0');

            // 종료 계산
            const total = hInt*60 + mInt + this.selectedDuration;
            const endH = Math.floor(total/60), endM = total%60;
            const edEl = document.querySelector('.manual-input-endDate');
            const edTrigger = document.querySelector('.date-trigger:not([data-isstart])');
            if (edEl) edEl.value = this.selectedDate;
            if (edTrigger) edTrigger.textContent = this.selectedDate;
            const ehEl = document.querySelector('.manual-input-endHH');
            const emEl = document.querySelector('.manual-input-endMI');
            if (ehEl) ehEl.value = String(endH).padStart(2,'0');
            if (emEl) emEl.value = String(endM).padStart(2,'0');
        }
        this.close();
    },
};

function openDatePicker(displayEl, inputEl, isStart) {
    DP.open(displayEl, inputEl, isStart);
}
