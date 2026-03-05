// =============================================
// ui/excel-handler.js — 엑셀 파싱 & 레코드 표시
// 책임: 파일 업로드, SheetJS 파싱, 레코드 UI 생성
// 다중 시트 지원: 시트별 탭 + 캐러셀 UI
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.ExcelHandler = {

    init() {
        const dropZone = document.getElementById('drop-zone');
        const fileInput = document.getElementById('file-input');

        dropZone.addEventListener('click', () => fileInput.click());
        fileInput.addEventListener('change', (e) => this._handleFile(e));
        dropZone.addEventListener('dragover', (e) => { e.preventDefault(); e.target.style.background = '#e8ffd9'; });
        dropZone.addEventListener('dragleave', (e) => { e.preventDefault(); e.target.style.background = '#fff'; });
        dropZone.addEventListener('drop', (e) => {
            e.preventDefault();
            e.target.style.background = '#fff';
            if (e.dataTransfer.files.length > 0) this._handleFile({ target: { files: e.dataTransfer.files } });
        });
    },

    _handleFile(e) {
        const file = e.target.files[0];
        if (!file) return;

        document.getElementById('status').innerText = '';
        const reader = new FileReader();
        reader.onload = (e) => {
            try {
                const data = new Uint8Array(e.target.result);
                const workbook = XLSX.read(data, { type: 'array' });

                // 다중 시트 파싱
                const sheetResults = [];
                for (const sheetName of workbook.SheetNames) {
                    const sheet = workbook.Sheets[sheetName];
                    const rows = XLSX.utils.sheet_to_json(sheet, { header: 1 });
                    const results = this._parseVerticalData(rows);
                    if (results.length > 0) {
                        sheetResults.push({ sheetName, records: results });
                    }
                }

                if (sheetResults.length > 0) {
                    // 히스토리에 저장 (시트 구조 포함)
                    window.DBAuto.HistoryManager.save(file.name, sheetResults);
                    this.displaySheetRecords(sheetResults);
                    document.getElementById('current-section').classList.remove('hidden');
                } else {
                    document.getElementById('status').innerText = '파싱 가능한 서비스 데이터가 없습니다.';
                }
            } catch (err) {
                document.getElementById('status').innerText = '분석 오류: ' + err.message;
            }
        };
        reader.readAsArrayBuffer(file);
    },

    // ─── 다중 시트 결과 표시 (시트별 탭 + 캐러셀) ───
    displaySheetRecords(sheetResults) {
        const section = document.getElementById('current-section');
        const container = document.getElementById('current-records');

        // 전체 서비스 데이터를 State에 저장 (flat)
        const allRecords = [];
        sheetResults.forEach(sr => allRecords.push(...sr.records));
        window.DBAuto.State.currentParsedData = allRecords;

        if (sheetResults.length === 1) {
            // 시트 1개 → 기존처럼 단순 리스트
            section.querySelector('.section-title').textContent = `추출된 서비스 목록 (${sheetResults[0].records.length}건)`;
            container.innerHTML = '';
            sheetResults[0].records.forEach(r => container.appendChild(this._createRecordElement(r)));
            return;
        }

        // 시트 2개 이상 → 탭 + 캐러셀
        section.querySelector('.section-title').textContent = `추출된 서비스 목록 (${allRecords.length}건, ${sheetResults.length}시트)`;

        // 탭 바
        const tabBarHtml = `<div class="sheet-tab-bar">${sheetResults.map((sr, i) =>
            `<button class="sheet-tab${i === 0 ? ' active' : ''}" data-sheetidx="${i}">${sr.sheetName} (${sr.records.length}개의 열)</button>`
        ).join('')}</div>`;

        // 캐러셀 패널
        const panelsHtml = sheetResults.map((sr, i) => {
            const recordsHtml = sr.records.map(r => {
                const el = this._createRecordElement(r);
                return el.outerHTML;
            }).join('');
            return `<div class="sheet-panel" id="sheet-panel-${i}">${recordsHtml}</div>`;
        }).join('');

        container.innerHTML = tabBarHtml + `<div class="sheet-carousel">${panelsHtml}</div>`;

        // 탭 클릭 이벤트
        container.querySelectorAll('.sheet-tab').forEach(tab => {
            tab.addEventListener('click', () => {
                const idx = parseInt(tab.dataset.sheetidx);
                this._switchToSheet(container, idx);
            });
        });

        // 캐러셀 스크롤 동기화
        const carousel = container.querySelector('.sheet-carousel');
        if (carousel) {
            let scrollTimer;
            carousel.addEventListener('scroll', () => {
                clearTimeout(scrollTimer);
                scrollTimer = setTimeout(() => {
                    const panels = carousel.querySelectorAll('.sheet-panel');
                    const scrollLeft = carousel.scrollLeft;
                    const containerWidth = carousel.clientWidth;
                    let closestIdx = 0;
                    let closestDist = Infinity;
                    panels.forEach((p, i) => {
                        const dist = Math.abs(p.offsetLeft - scrollLeft - (containerWidth - p.offsetWidth) / 2);
                        if (dist < closestDist) { closestDist = dist; closestIdx = i; }
                    });
                    container.querySelectorAll('.sheet-tab').forEach((t, i) =>
                        t.classList.toggle('active', i === closestIdx)
                    );
                }, 100);
            });
        }

        // 체크박스 이벤트 다시 바인딩
        this._bindRecordClicks(container);
    },

    _switchToSheet(container, idx) {
        container.querySelectorAll('.sheet-tab').forEach((t, i) =>
            t.classList.toggle('active', i === idx)
        );
        const panel = container.querySelector(`#sheet-panel-${idx}`);
        if (panel) panel.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
    },

    _bindRecordClicks(container) {
        container.querySelectorAll('.item-row').forEach(row => {
            row.onclick = () => {
                const State = window.DBAuto.State;
                const recordId = row.dataset.recordId;
                if (!recordId) return;
                const r = State.currentParsedData.find(rec => String(rec.id) === recordId);
                if (!r) return;

                const index = State.selectedRecords.findIndex(sr => sr.id === r.id);
                if (index > -1) {
                    State.selectedRecords.splice(index, 1);
                } else {
                    State.selectedRecords.push(r);
                }
                // 다시 전체 렌더
                this._refreshRecordUI(container);
                window.DBAuto.WindowManager.updateStatus();
            };
        });
    },

    _refreshRecordUI(container) {
        const State = window.DBAuto.State;
        container.querySelectorAll('.item-row').forEach(row => {
            const recordId = row.dataset.recordId;
            if (!recordId) return;
            const r = State.currentParsedData.find(rec => String(rec.id) === recordId);
            if (!r) return;

            const cfg = window.DBAuto.Config;
            const orderIndex = State.selectedRecords.findIndex(sr => sr.id === r.id);
            const isSelected = orderIndex > -1;
            const color = isSelected ? cfg.MATCH_COLORS[orderIndex % cfg.MATCH_COLORS.length] : '#ccc';

            row.className = `item-row ${isSelected ? 'selected' : ''}`;
            const checkbox = row.querySelector('.checkbox');
            if (checkbox) checkbox.checked = isSelected;

            const badge = row.querySelector('.match-badge, .window-badge');
            if (badge) {
                if (isSelected) {
                    badge.className = 'match-badge';
                    badge.style.background = color;
                    badge.style.color = '#fff';
                    badge.textContent = orderIndex + 1;
                } else {
                    badge.className = 'window-badge';
                    badge.style.background = '#ccc';
                    badge.style.color = '';
                    badge.textContent = '서비스';
                }
            }
        });
    },

    // ─── 기존 단일 레코드 표시 (히스토리 등 호환용) ───
    displayRecords(records) {
        window.DBAuto.State.currentParsedData = records;
        const list = document.getElementById('current-records');
        list.innerHTML = '';
        records.forEach(r => list.appendChild(this._createRecordElement(r)));
    },

    _parseVerticalData(rows) {
        const cfg = window.DBAuto.Config;
        const fingerprints = cfg.FIELD_FINGERPRINTS;
        const serviceMapKeys = Object.keys(cfg.SERVICE_MAP);
        const headerHints = cfg.HEADER_HINTS || {};

        // --- Step 1: 데이터가 있는 열(서비스) 범위 감지 ---
        let maxCol = 0;
        for (let r = 0; r < rows.length; r++) {
            if (rows[r]) maxCol = Math.max(maxCol, rows[r].length - 1);
        }
        // 데이터 열 범위: 1열(B)부터 maxCol까지
        const dataCols = [];
        for (let c = 1; c <= Math.min(maxCol, 20); c++) dataCols.push(c);

        // --- Step 2: 각 행의 데이터 값을 Fingerprint와 대조 ---
        const rowFieldMap = {};   // { 행번호: 필드명 }
        const usedFields = new Set();
        const unmatchedRows = []; // Fingerprint 매칭 실패한 행들

        for (let rowIdx = 0; rowIdx < rows.length; rowIdx++) {
            const row = rows[rowIdx];
            if (!row) continue;

            // 이 행의 데이터 셀 값들 수집 (A열 제외)
            const cellValues = dataCols
                .map(c => (row[c] !== undefined && row[c] !== null) ? row[c].toString().trim() : '')
                .filter(v => v.length > 0);

            if (cellValues.length === 0) continue; // 빈 행 스킵

            let bestField = null;
            let bestScore = 0;

            for (const fp of fingerprints) {
                if (fp.type === 'freetext') continue; // 자유 텍스트는 나중에 처리
                if (usedFields.has(fp.field)) continue; // 이미 매칭된 필드 스킵

                let score = 0;
                if (fp.type === 'exact') {
                    score = cellValues.filter(v => fp.values.includes(v)).length;
                } else if (fp.type === 'regex') {
                    const regex = new RegExp(fp.pattern);
                    score = cellValues.filter(v => regex.test(v)).length;
                } else if (fp.type === 'service') {
                    // SERVICE_MAP 키와 부분 매칭 (엑셀 값이 키의 일부만 포함해도 OK)
                    score = cellValues.filter(v =>
                        serviceMapKeys.some(k => k.includes(v) || v.includes(k))
                    ).length;
                }

                if (score > bestScore) {
                    bestScore = score;
                    bestField = fp.field;
                }
            }

            // 매칭 신뢰도: 데이터 셀 중 30% 이상이 해당 Fingerprint에 맞아야 확정
            if (bestField && bestScore >= Math.max(1, cellValues.length * 0.3)) {
                rowFieldMap[rowIdx] = bestField;
                usedFields.add(bestField);
            } else {
                unmatchedRows.push(rowIdx);
            }
        }

        // --- Step 3: 매칭 안 된 행 → A열 헤더 텍스트로 fallback ---
        const stillUnmatched = [];
        for (const rowIdx of unmatchedRows) {
            const row = rows[rowIdx];
            const headerText = (row[0] || '').toString().trim().replace(/\s+/g, '');

            let matched = false;
            for (const [keyword, fieldName] of Object.entries(headerHints)) {
                if (usedFields.has(fieldName)) continue;
                if (headerText.includes(keyword.replace(/\s+/g, ''))) {
                    rowFieldMap[rowIdx] = fieldName;
                    usedFields.add(fieldName);
                    matched = true;
                    break;
                }
            }
            if (!matched) stillUnmatched.push(rowIdx);
        }

        // --- Step 4: 여전히 매칭 안 된 행 → 자유 텍스트 (서비스내용 → 소견 순서) ---
        const freetextFields = fingerprints
            .filter(fp => fp.type === 'freetext' && !usedFields.has(fp.field))
            .sort((a, b) => a.priority - b.priority);

        // 자유 텍스트 후보 행: 데이터가 있으면서 아직 미분류인 행
        const freetextCandidates = stillUnmatched.filter(rowIdx => {
            const row = rows[rowIdx];
            return dataCols.some(c => row[c] && row[c].toString().trim().length > 0);
        });

        freetextFields.forEach((fp, i) => {
            if (i < freetextCandidates.length) {
                rowFieldMap[freetextCandidates[i]] = fp.field;
                usedFields.add(fp.field);
            }
        });

        // --- Step 5: 매핑 기반으로 각 열(서비스)의 데이터 추출 ---
        const results = [];
        for (const col of dataCols) {
            // 이 열에 의미 있는 데이터가 있는지 확인
            const hasData = Object.keys(rowFieldMap).some(ridx => {
                const val = rows[ridx] && rows[ridx][col];
                return val !== undefined && val !== null && val.toString().trim().length > 0;
            });
            if (!hasData) continue;

            const record = { id: col };
            for (const [rowIdx, fieldName] of Object.entries(rowFieldMap)) {
                const val = rows[rowIdx] ? rows[rowIdx][col] : '';
                record[fieldName] = (val !== undefined && val !== null) ? val.toString().trim() : '';
            }
            results.push(record);
        }

        console.log('[DBAuto SmartParse] 행↔필드 매핑 결과:', rowFieldMap);
        return results;
    },

    _createRecordElement(r, timestamp) {
        const State = window.DBAuto.State;
        const cfg = window.DBAuto.Config;
        const orderIndex = State.selectedRecords.findIndex(sr => sr.id === r.id);
        const isSelected = orderIndex > -1;
        const color = isSelected ? cfg.MATCH_COLORS[orderIndex % cfg.MATCH_COLORS.length] : '#ccc';

        const row = document.createElement('div');
        row.className = `item-row ${isSelected ? 'selected' : ''}`;
        row.dataset.recordId = String(r.id);

        row.innerHTML = `
            <input type="checkbox" class="checkbox" ${isSelected ? 'checked' : ''}>
            ${isSelected ? `<span class="match-badge" style="background:${color}; color:#fff;">${orderIndex + 1}</span>` : `<span class="window-badge" style="background:#ccc;">서비스</span>`}
            <div class="item-info">
                <div class="item-title">서비스 ${r.id}: ${r.svcClassDetailCd_val || '-'}</div>
                <div class="item-tags">
                    <span class="tag">🕒 ${r.dateTime_val || '일시 미입력'}</span>
                    ${r.recipient_val ? `<span class="tag">👤 ${r.recipient_val}</span>` : ''}
                    ${r.provMeansCd_val ? `<span class="tag">📞 ${r.provMeansCd_val}</span>` : ''}
                    ${r.loc_val ? `<span class="tag">📍 ${r.loc_val}</span>` : ''}
                    ${r.pic_val ? `<span class="tag">👣 ${r.pic_val}</span>` : ''}
                </div>
                ${timestamp ? `<div class="upload-time">업로드: ${window.DBAuto.Utils.getRelativeTime(timestamp)}</div>` : ''}
            </div>
        `;

        row.onclick = () => {
            const index = State.selectedRecords.findIndex(sr => sr.id === r.id);
            if (index > -1) {
                State.selectedRecords.splice(index, 1);
            } else {
                State.selectedRecords.push(r);
            }
            this.displayRecords(State.currentParsedData);
            window.DBAuto.WindowManager.updateStatus();
        };

        return row;
    },
};
