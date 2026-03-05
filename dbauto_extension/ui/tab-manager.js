// =============================================
// ui/tab-manager.js — 탭(메뉴) 전환 UI 로직
// 책임: "새 파일 업로드 / 수동 입력 / 최근 기록" 탭 전환만 담당
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.TabManager = {
    init() {
        document.getElementById('tab-upload').onclick = () => this.switchTab('upload');
        document.getElementById('tab-manual').onclick = () => this.switchTab('manual');
        document.getElementById('tab-history').onclick = () => {
            this.switchTab('history');
            window.DBAuto.HistoryManager.load();
        };
    },

    switchTab(tab) {
        document.getElementById('upload-view').classList.add('hidden');
        document.getElementById('manual-view').classList.add('hidden');
        document.getElementById('history-view').classList.add('hidden');
        document.getElementById('window-section').classList.add('hidden');
        document.getElementById('status').classList.add('hidden');

        document.getElementById('tab-upload').classList.remove('active');
        document.getElementById('tab-manual').classList.remove('active');
        document.getElementById('tab-history').classList.remove('active');

        if (tab === 'upload') {
            document.getElementById('upload-view').classList.remove('hidden');
            document.getElementById('window-section').classList.remove('hidden');
            document.getElementById('status').classList.remove('hidden');
            document.getElementById('tab-upload').classList.add('active');
        } else if (tab === 'manual') {
            document.getElementById('manual-view').classList.remove('hidden');
            document.getElementById('tab-manual').classList.add('active');
            window.DBAuto.ManualForm.renderForms();
        } else {
            document.getElementById('history-view').classList.remove('hidden');
            document.getElementById('tab-history').classList.add('active');
        }
    },
};
