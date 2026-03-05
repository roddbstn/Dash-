/**
 * popup.js — 팝업 UI 로직
 * SheetJS로 엑셀 파싱 → 미리보기 → background.js로 자동 입력 요청
 */

// 엑셀 필드명 → 내부 키 매핑
const FIELD_MAP = {
    '제목': 'title',
    '생산연도': 'productionYear',
    '부서명': 'departmentName',
    '분류번호': 'classificationCode',
    '보존기간': 'retentionPeriod',
    '관리번호': 'managementNumber',
};

const FIELD_LABELS = {
    title: '제목',
    productionYear: '생산연도',
    departmentName: '부서명',
    classificationCode: '분류번호',
    retentionPeriod: '보존기간',
    managementNumber: '관리번호',
};

const VALID_RETENTION = new Set(['영구', '준영구', '30년', '10년', '5년', '3년', '1년']);

let parsedLabels = [];

// ── 드래그 앤 드롭 ──────────────────────────────
const dropZone = document.getElementById('drop-zone');
const fileInput = document.getElementById('file-input');

// 드롭존 클릭 → 파일 선택 창 열기
dropZone.addEventListener('click', () => fileInput.click());

// 실행 버튼 클릭
document.getElementById('run-btn').addEventListener('click', startFill);

dropZone.addEventListener('dragover', e => { e.preventDefault(); dropZone.classList.add('drag-over'); });
dropZone.addEventListener('dragleave', () => dropZone.classList.remove('drag-over'));
dropZone.addEventListener('drop', e => {
    e.preventDefault();
    dropZone.classList.remove('drag-over');
    const file = e.dataTransfer.files[0];
    if (file) handleFile(file);
});
fileInput.addEventListener('change', e => {
    if (e.target.files[0]) handleFile(e.target.files[0]);
});

// ── 파일 처리 ────────────────────────────────────
function handleFile(file) {
    if (!file.name.endsWith('.xlsx')) {
        alert('.xlsx 파일만 지원합니다.');
        return;
    }

    const reader = new FileReader();
    reader.onload = e => {
        try {
            const data = new Uint8Array(e.target.result);
            const wb = XLSX.read(data, { type: 'array' });

            parsedLabels = [];
            for (const sheetName of wb.SheetNames) {
                const ws = wb.Sheets[sheetName];
                const label = parseSheet(ws);
                if (label && Object.keys(label).length > 0) {
                    parsedLabels.push(label);
                }
            }

            if (parsedLabels.length === 0) {
                alert('라벨 데이터를 찾을 수 없습니다.\n엑셀 파일 형식을 확인해주세요.');
                return;
            }

            // 드롭존 성공 표시
            dropZone.classList.add('success');
            dropZone.querySelector('.icon').textContent = '✅';
            dropZone.querySelector('.main').textContent = `${file.name} (${parsedLabels.length}개 라벨)`;
            dropZone.querySelector('.sub').textContent = '다른 파일을 드래그하면 교체됩니다';

            renderPreview(parsedLabels[0]);
            document.getElementById('run-btn').style.display = 'block';
            document.getElementById('log').style.display = 'none';
            document.getElementById('log-list').innerHTML = '';

        } catch (err) {
            alert(`파싱 오류: ${err.message}`);
        }
    };
    reader.readAsArrayBuffer(file);
}

function parseSheet(ws) {
    const label = {};
    const range = XLSX.utils.decode_range(ws['!ref'] || 'A1:Z100');

    for (let row = range.s.r; row <= range.e.r; row++) {
        const bCell = ws[XLSX.utils.encode_cell({ r: row, c: 1 })]; // B열
        const cCell = ws[XLSX.utils.encode_cell({ r: row, c: 2 })]; // C열

        if (!bCell || !bCell.v) continue;
        const fieldName = String(bCell.v).trim();
        const key = FIELD_MAP[fieldName];
        if (!key) continue;

        const rawValue = cCell ? String(cCell.v ?? '').trim() : '';
        label[key] = normalizeValue(key, rawValue);
    }
    return label;
}

function normalizeValue(key, value) {
    if (key === 'departmentName') {
        // 리터럴 \n 또는 실제 줄바꿈 모두 처리
        return value.replace(/\\n/g, '\n');
    }
    if (key === 'retentionPeriod') {
        if (!VALID_RETENTION.has(value)) {
            // 부분 매칭 시도
            for (const v of VALID_RETENTION) {
                if (value.includes(v) || v.includes(value)) return v;
            }
        }
    }
    return value;
}

// ── 미리보기 렌더링 ──────────────────────────────
function renderPreview(label) {
    const table = document.getElementById('preview-table');
    const order = ['title', 'productionYear', 'departmentName', 'classificationCode', 'retentionPeriod', 'managementNumber'];

    table.innerHTML = order
        .filter(k => label[k] !== undefined)
        .map(k => {
            const displayVal = label[k].replace(/\n/g, ' / ');
            return `<tr><td>${FIELD_LABELS[k]}</td><td>${displayVal}</td></tr>`;
        })
        .join('');

    document.getElementById('preview').style.display = 'block';
}

// ── 자동 입력 실행 ───────────────────────────────
async function startFill() {
    if (parsedLabels.length === 0) return;

    const btn = document.getElementById('run-btn');
    btn.disabled = true;
    btn.textContent = '⏳ 입력 중...';

    const logDiv = document.getElementById('log');
    const logList = document.getElementById('log-list');
    logDiv.style.display = 'block';
    logList.innerHTML = '';
    setProgress(10);

    addLog('status', '🔗 labelmaker.kr 탭 찾는 중...');

    try {
        let response;
        try {
            response = await new Promise((resolve, reject) => {
                chrome.runtime.sendMessage({ type: 'FILL_LABEL', data: parsedLabels[0] }, res => {
                    if (chrome.runtime.lastError) {
                        reject(new Error(chrome.runtime.lastError.message));
                    } else {
                        resolve(res);
                    }
                });
            });
        } catch (msgErr) {
            addLog('error', `❌ 통신 오류: ${msgErr.message}`);
            addLog('status', '💡 labelmaker.kr 탭을 새로고침(Cmd+R) 후 다시 시도하세요');
            finish(btn, false);
            return;
        }

        if (!response) {
            addLog('error', '❌ 응답 없음. labelmaker.kr 탭이 열려 있는지 확인하세요.');
            finish(btn, false);
            return;
        }

        if (!response.ok) {
            addLog('error', `❌ ${response.error}`);
            finish(btn, false);
            return;
        }

        // 필드별 결과 표시
        const results = response.results || {};
        let successCount = 0;
        let failCount = 0;

        for (const [field, ok] of Object.entries(results)) {
            const label = FIELD_LABELS[field] || field;
            if (ok) {
                addLog('success', `✅ ${label}`);
                successCount++;
            } else {
                addLog('fail', `❌ ${label} 입력 실패`);
                failCount++;
            }
            setProgress(10 + (successCount + failCount) / Object.keys(results).length * 80);
        }

        setProgress(100);

        if (failCount === 0) {
            addLog('done', `🎉 완료! ${successCount}개 필드 모두 입력 성공!`);
            finish(btn, true);
        } else {
            addLog('error', `⚠️ ${successCount}개 성공, ${failCount}개 실패`);
            finish(btn, false);
        }

    } catch (err) {
        addLog('error', `❌ 오류: ${err.message}`);
        finish(btn, false);
    }
}

function finish(btn, success) {
    btn.disabled = false;
    btn.textContent = success ? '▶️ 다시 실행' : '▶️ 다시 시도';
}

function addLog(type, message) {
    const list = document.getElementById('log-list');
    const div = document.createElement('div');
    div.className = `log-item log-${type}`;
    div.textContent = message;
    list.appendChild(div);
    list.scrollTop = list.scrollHeight;
}

function setProgress(pct) {
    document.getElementById('progress-bar').style.width = pct + '%';
}
