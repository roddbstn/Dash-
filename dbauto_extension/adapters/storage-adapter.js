// =============================================
// adapters/storage-adapter.js — Chrome/Edge Storage 추상화
// UI 계층은 chrome.storage API를 직접 알 필요가 없습니다.
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.Storage = {

    /**
     * 스토리지에서 값을 가져옵니다.
     * @param {string|object} keys - 가져올 키 또는 기본값 포함 객체
     * @returns {Promise<object>}
     */
    get(keys) {
        return new Promise((resolve) => {
            chrome.storage.local.get(keys, resolve);
        });
    },

    /**
     * 스토리지에 값을 저장합니다.
     * @param {object} data - 저장할 키-값 쌍
     * @returns {Promise<void>}
     */
    set(data) {
        return new Promise((resolve) => {
            chrome.storage.local.set(data, resolve);
        });
    },
};
