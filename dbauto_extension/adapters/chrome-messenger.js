// =============================================
// adapters/chrome-messenger.js — Chrome/Edge 탭 통신 추상화
// UI 계층은 chrome.tabs API를 직접 알 필요가 없습니다.
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.Messenger = {

    /**
     * 특정 탭에 메시지를 전송합니다.
     * @param {number} tabId - 대상 탭 ID
     * @param {string} action - DBAuto.Actions 중 하나
     * @param {object} payload - 전달할 데이터
     * @param {function} callback - 응답 콜백 (선택)
     */
    sendToTab(tabId, action, payload = {}, callback) {
        const message = { action, ...payload };
        chrome.tabs.sendMessage(tabId, message, (response) => {
            if (chrome.runtime.lastError) {
                console.error(`[DBAuto Messenger] 전송 실패 (탭 ${tabId}):`, chrome.runtime.lastError);
            }
            if (callback) callback(response);
        });
    },

    /**
     * 대상 시스템 탭 목록을 조회합니다.
     * @returns {Promise<chrome.tabs.Tab[]>}
     */
    async queryTargetTabs() {
        const cfg = window.DBAuto.Config;
        const tabs = await chrome.tabs.query({ url: cfg.TARGET_URLS });
        // 탭 ID 기준 오름차순 정렬 — 서버 구동 순서와 무관하게 항상 "창 1, 창 2" 고정 순서 보장
        return tabs
            .filter(t => !cfg.EXCLUDED_KEYWORDS.some(kw => t.url.includes(kw)))
            .sort((a, b) => a.id - b.id);
    },
};
