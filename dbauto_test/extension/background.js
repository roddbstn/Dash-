/**
 * background.js — Service Worker
 * 팝업과 content script 사이의 메시지를 라우팅하고
 * labelmaker.kr 탭을 찾아 자동 입력을 실행합니다.
 */

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === 'FILL_LABEL') {
        handleFillLabel(message.data).then(sendResponse).catch(err => {
            sendResponse({ ok: false, error: err.message });
        });
        return true; // 비동기 응답을 위해 true 반환
    }
});

async function handleFillLabel(labelData) {
    // 1. labelmaker.kr 탭 찾기
    const tabs = await chrome.tabs.query({
        url: ['*://labelmaker.kr/*', '*://www.labelmaker.kr/*']
    });

    if (tabs.length === 0) {
        return {
            ok: false,
            error: 'labelmaker.kr 탭을 찾을 수 없습니다.\nChrome/Edge에서 labelmaker.kr/app을 열고 로그인해주세요.'
        };
    }

    const targetTab = tabs[tabs.length - 1];

    // 2. content.js를 탭에 직접 주입 (새로고침 없이도 동작)
    try {
        await chrome.scripting.executeScript({
            target: { tabId: targetTab.id },
            files: ['content.js']
        });
    } catch (e) {
        // 이미 주입된 경우 무시
        console.log('[dbauto] content.js 주입 시도:', e.message);
    }

    // 잠깐 대기 후 메시지 전송
    await sleep(300);

    // 3. content script에 데이터 전송
    try {
        const result = await chrome.tabs.sendMessage(targetTab.id, {
            type: 'FILL_FORM',
            data: labelData
        });
        return result;
    } catch (err) {
        return {
            ok: false,
            error: `폼 입력 실패: ${err.message}\n\nlabelmaker.kr 탭을 새로고침(Cmd+R) 후 다시 시도해주세요.`
        };
    }
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}
