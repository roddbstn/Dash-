// =============================================
// ui/window-manager.js — 창 스캔, 선택, 일괄 기입 실행
// 책임: 타겟 시스템 창 탐색, 목록 렌더링, 일괄 전송
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.WindowManager = {

    // 이름 마스킹: 강윤수→강O수, 유나→유O, 제갈도민→제OO민
    _maskName(name) {
        if (!name || name.length <= 1) return name;
        if (name.length === 2) return name[0] + 'O';
        return name[0] + 'O'.repeat(name.length - 2) + name[name.length - 1];
    },

    init() {
        document.getElementById('refresh-windows').onclick = () => this.scanTabs();
        document.getElementById('batch-fill-btn').onclick = () => this._handleBatchFill();
        window.DBAuto.State.collapsedTabs = window.DBAuto.State.collapsedTabs || new Set();
    },

    async scanTabs() {
        const State = window.DBAuto.State;
        const Actions = window.DBAuto.Actions;
        const rawTabs = await window.DBAuto.Messenger.queryTargetTabs();

        // 탭 ID 오름차순 정렬 — 먼저 연 창(낮은 ID)이 항상 위에 위치
        State.targetTabs = rawTabs.sort((a, b) => a.id - b.id);

        // 이전에 선택했던 탭이 여전히 존재하는지 필터링
        State.selectedTabs = State.selectedTabs.filter(
            st => State.targetTabs.some(t => t.id === st.id)
        );
        // 사라진 탭의 접힘 상태 정리
        State.collapsedTabs = State.collapsedTabs || new Set();
        for (const id of State.collapsedTabs) {
            if (!State.targetTabs.some(t => t.id === id)) State.collapsedTabs.delete(id);
        }

        // 목록 렌더링
        this._renderList();
    },

    updateStatus() {
        const State = window.DBAuto.State;
        const status = document.getElementById('status');
        if (State.selectedRecords.length > 0 || State.selectedTabs.length > 0) {
            status.innerText = `케이스 ${State.selectedRecords.length}개, 창 ${State.selectedTabs.length}개 선택됨`;
        } else {
            status.innerText = '파일을 대기 중입니다.';
        }
    },

    _renderList() {
        const State = window.DBAuto.State;
        const Actions = window.DBAuto.Actions;
        const cfg = window.DBAuto.Config;
        const list = document.getElementById('window-list');
        list.innerHTML = '';

        if (State.targetTabs.length === 0) {
            list.innerHTML = '<div style="text-align:center; padding:12px; color:#8b95a1; font-size:12px;">감지된 시스템 창이 없습니다.</div>';
            return;
        }

        State.collapsedTabs = State.collapsedTabs || new Set();

        State.targetTabs.forEach((tab, tabIndex) => {
            const orderIndex = State.selectedTabs.findIndex(st => st.id === tab.id);
            const isSelected = orderIndex > -1;
            const isCollapsed = State.collapsedTabs.has(tab.id);
            const color = isSelected ? cfg.MATCH_COLORS[orderIndex % cfg.MATCH_COLORS.length] : '#ccc';

            const childText = '';
            // 창 번호: ID 정렬 기준 내 순서 (tabIndex + 1)
            const winNum = tabIndex + 1;

            const wrapper = document.createElement('div');

            // ── 헤더 행: 항상 표시 ──
            const header = document.createElement('div');
            header.className = `item-row ${isSelected ? 'selected' : ''} ${isCollapsed ? 'collapsed-row' : ''}`;
            header.style.cssText = 'position:relative;';
            header.innerHTML = `
                <input type="checkbox" class="checkbox" ${isSelected ? 'checked' : ''}>
                ${isSelected
                    ? `<span class="match-badge" style="background:${color}; color:#fff;">${orderIndex + 1}</span>`
                    : `<span class="window-badge">창 ${winNum}</span>`}
                <div class="item-info" style="${isCollapsed ? 'opacity:0.5;' : ''}">
                    <div class="item-title" data-tabid="${tab.id}">${tab.title || '제목 없음'}${childText}</div>
                    ${!isCollapsed ? `<div style="font-size:10px;color:#999;">${tab.url.substring(0, 40)}...</div>` : ''}
                </div>
                <button class="collapse-btn" title="${isCollapsed ? '펼치기' : '접기 (기입 완료)'}"
                    style="margin-left:auto; background:none; border:none; cursor:pointer;
                           font-size:13px; color:#b0b8c1; padding:4px 6px; border-radius:4px;
                           transition:all 0.15s; flex-shrink:0;">
                    ${isCollapsed ? '›' : '‹'}
                </button>
            `;

            // 접기 버튼 클릭: 이벤트 전파 중단 (체크박스 토글 방지)
            const collapseBtn = header.querySelector('.collapse-btn');
            collapseBtn.onclick = (e) => {
                e.stopPropagation();
                if (State.collapsedTabs.has(tab.id)) {
                    State.collapsedTabs.delete(tab.id);
                } else {
                    State.collapsedTabs.add(tab.id);
                }
                this._renderList();
            };

            // 행 클릭: 체크박스(창 선택) 토글
            header.onclick = (e) => {
                if (e.target === collapseBtn) return;
                const index = State.selectedTabs.findIndex(st => st.id === tab.id);
                if (index > -1) {
                    State.selectedTabs.splice(index, 1);
                } else {
                    State.selectedTabs.push(tab);
                }
                this._renderList();
                this.updateStatus();
            };

            header.onmouseenter = () => chrome.tabs.sendMessage(tab.id, { action: Actions.HIGHLIGHT_TAB, active: true });
            header.onmouseleave = () => chrome.tabs.sendMessage(tab.id, { action: Actions.HIGHLIGHT_TAB, active: false });

            wrapper.appendChild(header);
            list.appendChild(wrapper);
        });
    },

    _handleBatchFill() {
        const State = window.DBAuto.State;
        const Actions = window.DBAuto.Actions;

        if (State.selectedRecords.length === 0) return alert('기입할 케이스를 먼저 선택해주세요.');
        if (State.selectedTabs.length === 0) return alert('데이터를 넣을 대상 창을 아래 목록에서 클릭해 주세요.');

        const confirmMsg = `${State.selectedRecords.length}개의 데이터를 선택한 ${State.selectedTabs.length}개의 창에 입력하시겠습니까?`;
        if (!confirm(confirmMsg)) return;

        State.selectedRecords.forEach((record, i) => {
            const targetTab = State.selectedTabs[i % State.selectedTabs.length];
            chrome.tabs.sendMessage(targetTab.id, { action: Actions.START_AUTO_FILL, data: record }, (res) => {
                if (chrome.runtime.lastError) console.error(`기입 실패:`, chrome.runtime.lastError);
            });
        });

        alert('자동 입력이 시작되었습니다. 각 창의 미흡한 항목(빨간색)을 확인해 주세요.');
    },
};
