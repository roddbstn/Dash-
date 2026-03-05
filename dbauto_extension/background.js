// background.js — 서비스 워커
// 확장 아이콘 클릭 시 사이드 패널을 엽니다 (Chrome & Edge 공통)

// 아이콘을 클릭하면 사이드 패널이 열리도록 설정
chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true })
    .catch((error) => console.error('sidePanel 설정 오류:', error));
