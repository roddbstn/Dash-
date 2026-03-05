// =============================================
// ui/app.js — 애플리케이션 진입점 (초기화 전용)
// 모든 모듈을 초기화하고 주기적 갱신을 설정합니다.
// =============================================
window.DBAuto = window.DBAuto || {};

// 공유 상태 (모듈 간 반응형 데이터)
window.DBAuto.State = {
    currentParsedData: [],
    selectedRecords: [],
    targetTabs: [],
    selectedTabs: [],
};

// 유틸리티
window.DBAuto.Utils = {
    getRelativeTime(timestamp) {
        const diff = Date.now() - timestamp;
        const seconds = Math.floor(diff / 1000);
        const minutes = Math.floor(seconds / 60);
        const hours = Math.floor(minutes / 60);
        if (hours > 0) return `${hours}시간 전`;
        if (minutes > 0) return `${minutes}분 전`;
        return `방금 전`;
    },
};

// ─── 모듈 초기화 (순서 중요) ───
window.DBAuto.TabManager.init();
window.DBAuto.HoverSelect.init();
window.DBAuto.DatePicker.init();
window.DBAuto.ManualForm.init();
window.DBAuto.ExcelHandler.init();
window.DBAuto.WindowManager.init();
window.DBAuto.HistoryManager.init();

// 초기 창 스캔 + 3초 주기 갱신
window.DBAuto.WindowManager.scanTabs();
setInterval(() => window.DBAuto.WindowManager.scanTabs(), 3000);
