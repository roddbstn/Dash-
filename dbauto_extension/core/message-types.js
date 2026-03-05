// =============================================
// core/message-types.js — 메시지 프로토콜 인터페이스
// popup ↔ content 간 통신 "계약서" 역할
// 새로운 통신이 필요하면 여기에 action을 추가합니다.
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.Actions = Object.freeze({
    // content.js → 타겟 페이지 자동 기입 실행
    START_AUTO_FILL: 'START_AUTO_FILL',

    // content.js → 타겟 페이지 하이라이트 표시/해제
    HIGHLIGHT_TAB: 'HIGHLIGHT_TAB',

    // content.js → 타겟 페이지의 폼 드롭다운 옵션 조회
    GET_FORM_OPTIONS: 'GET_FORM_OPTIONS',

    // content.js → 대상자 구분 변경 후 이름 옵션 재조회
    UPDATE_TY_CD: 'UPDATE_TY_CD_AND_GET_OPTIONS',
});
