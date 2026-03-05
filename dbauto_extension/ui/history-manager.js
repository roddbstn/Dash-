// =============================================
// ui/history-manager.js — 히스토리(최근 기록) 관리
// 책임: 업로드 기록 저장, 로드, 삭제
// 다중 시트 히스토리 지원
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.HistoryManager = {

    init() {
        document.getElementById('clear-history').onclick = () => {
            if (confirm('모든 기록을 삭제하시겠습니까?')) {
                chrome.storage.local.set({ history: [] }, () => this.load());
            }
        };
    },

    load() {
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
                const d = new Date(entry.timestamp);
                const dateStr = `${d.getFullYear()}.${String(d.getMonth() + 1).padStart(2, '0')}.${String(d.getDate()).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
                group.innerHTML = `<div style="display:flex; justify-content:space-between; align-items:center; font-size:11px; margin-bottom:5px; border-bottom:1px solid #eee; padding-bottom:4px;"><span style="color:#222; font-weight:bold;">📁 ${entry.fileName}</span><span style="color:#aaa; font-weight:300; font-size:10px;">${dateStr}</span></div>`;

                // 호환성: 기존 records 배열 또는 새 sheetResults 배열
                if (entry.sheetResults) {
                    // 다중 시트
                    const totalCount = entry.sheetResults.reduce((sum, sr) => sum + sr.records.length, 0);
                    if (entry.sheetResults.length > 1) {
                        const sheetInfo = document.createElement('div');
                        sheetInfo.style.cssText = 'font-size:10px; color:#8b95a1; margin-bottom:4px;';
                        sheetInfo.textContent = `${entry.sheetResults.length}개 시트, 총 ${totalCount}건`;
                        group.appendChild(sheetInfo);
                    }
                    entry.sheetResults.forEach(sr => {
                        if (entry.sheetResults.length > 1) {
                            const sheetLabel = document.createElement('div');
                            sheetLabel.style.cssText = 'font-size:10px; font-weight:600; color:#4e5968; margin:6px 0 2px; padding-left:2px;';
                            sheetLabel.textContent = `📄 ${sr.sheetName} (${sr.records.length}건)`;
                            group.appendChild(sheetLabel);
                        }
                        sr.records.forEach(r => group.appendChild(
                            window.DBAuto.ExcelHandler._createRecordElement(r, entry.timestamp)
                        ));
                    });
                } else if (entry.records) {
                    // 레거시 (단일 시트)
                    entry.records.forEach(r => group.appendChild(
                        window.DBAuto.ExcelHandler._createRecordElement(r, entry.timestamp)
                    ));
                }
                list.appendChild(group);
            });
        });
    },

    save(fileName, sheetResults) {
        chrome.storage.local.get({ history: [] }, (data) => {
            const history = data.history;
            history.unshift({ fileName, timestamp: Date.now(), sheetResults });
            if (history.length > 50) history.pop();
            chrome.storage.local.set({ history });
        });
    },
};
