// =============================================
// ui/hover-select.js — 호버 드롭다운 UX 전용 모듈
// 책임: 마우스 오버 시 드롭다운 확장/축소, 닫기 처리
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.HoverSelect = {
    init() {
        // 마우스 오버 시 드롭다운 자동 전개
        document.addEventListener('mouseover', (e) => {
            if (e.target.matches('select.hover-select') || (e.target.tagName === 'OPTION' && e.target.parentElement.matches('select.hover-select'))) {
                const select = e.target.matches('select.hover-select') ? e.target : e.target.parentElement;

                // 닫기 타이머가 걸려 있으면 취소 (마우스가 다시 들어온 경우)
                if (select._closeTimer) {
                    clearTimeout(select._closeTimer);
                    select._closeTimer = null;
                }

                // 다른 열려있는 호버 셀렉트는 모두 닫기
                document.querySelectorAll('select.hover-select[data-is-hovered="true"]').forEach(s => {
                    if (s !== select) this.close(s);
                });

                if (select.options.length <= 1) return;
                if (select.dataset.isHovered === 'true') return;

                select.dataset.isHovered = 'true';

                // 숨겨진 옵션(빈 기본값 등)을 제외한 실제 항목 수만 계산하여 공백 방지
                const visibleCount = Array.from(select.options).filter(o => !o.hidden && o.style.display !== 'none').length;
                select.size = Math.max(2, Math.min(visibleCount, 8));

                select.style.zIndex = '9999';
                select.style.boxShadow = '0 4px 12px rgba(0,0,0,0.2)';
                select.style.height = 'auto';
            }
        });

        // 마우스 아웃 시 지연 닫기 (옵션 사이 이동 시 깜빡임 방지)
        document.addEventListener('mouseout', (e) => {
            const select = e.target.matches('select.hover-select') ? e.target :
                (e.target.tagName === 'OPTION' && e.target.parentElement.matches('select.hover-select')) ? e.target.parentElement : null;
            if (!select) return;
            if (select.dataset.isHovered !== 'true') return;

            // 마우스가 select 또는 그 자식으로 이동한 경우에는 닫지 않음
            if (e.relatedTarget && (select.contains(e.relatedTarget) || select === e.relatedTarget)) return;

            // 약간의 딜레이 후 닫기 (마우스가 잠시 벗어났다 돌아올 수 있음)
            select._closeTimer = setTimeout(() => {
                this.close(select);
                select._closeTimer = null;
            }, 120);
        });

        // 값 변경 시 닫기 + 리스트 빌더 자동 추가
        document.addEventListener('change', (e) => {
            if (e.target.matches('select.hover-select')) {
                // change 이벤트가 확실히 완료된 후 닫기
                setTimeout(() => this.close(e.target), 50);

                // 리스트 빌더 자동 추가 로직
                if (e.target.classList.contains('builder-select-picId') || e.target.classList.contains('builder-select-svcExecRecipientId')) {
                    const container = e.target.closest('.list-builder-container');
                    const field = container.dataset.field;
                    const tabId = container.dataset.tabid;
                    window.addListItem(field, tabId);
                    setTimeout(() => { e.target.value = ""; }, 100);
                }
            }

            // 대상자 구분 변경 시 이름 동적 렌더링
            if (e.target.classList.contains('manual-input-svcExecRecipientTyCd')) {
                const Actions = window.DBAuto.Actions;
                const tabId = parseInt(e.target.dataset.tabid, 10);
                const tyCdVal = e.target.value;
                const container = e.target.closest('.manual-form-group');
                const targetSelect = container.querySelector('.builder-select-svcExecRecipientId');

                if (targetSelect && tyCdVal) {
                    targetSelect.innerHTML = '<option value="">로딩 중...</option>';
                    chrome.tabs.sendMessage(tabId, { action: Actions.UPDATE_TY_CD, value: tyCdVal, silent: true }, (res) => {
                        window.DBAuto.ManualForm.saveState();
                        if (!chrome.runtime.lastError && res && res.svcExecRecipientId) {
                            targetSelect.innerHTML = '<option value="">선택하세요</option>' +
                                res.svcExecRecipientId.map(o => `<option value="${o.value}">${o.text}</option>`).join('');
                        } else {
                            targetSelect.innerHTML = '<option value="">선택하세요</option>';
                        }
                    });
                } else if (targetSelect && !tyCdVal) {
                    targetSelect.innerHTML = '<option value="" disabled selected hidden></option>';
                }
                setTimeout(() => { window.DBAuto.ManualForm.saveState(); }, 50);
            }
        });

        // 옵션 클릭 시: click 이벤트로 처리 (mousedown 대신 — 선택 누락 방지)
        // 브라우저 이벤트 순서: mousedown → mouseup → click → change
        // mousedown에서 닫으면 change가 발생하기 전에 옵션이 사라져 선택이 무시됨
        document.addEventListener('click', (e) => {
            // 옵션 클릭 → change에서 이미 닫히지만, 같은 옵션 재클릭 시 change가 안 뜸
            if (e.target.tagName === 'OPTION' && e.target.parentElement.matches('select.hover-select')) {
                const select = e.target.parentElement;
                setTimeout(() => this.close(select), 80);
            }

            // 빌더 아이템 제거
            if (e.target.matches('.builder-remove-btn')) {
                e.target.parentElement.remove();
                window.DBAuto.ManualForm.saveState();
            }

            // 날짜 입력 클릭 시 피커 열기
            if (e.target.matches('input[type="date"]')) {
                try { e.target.showPicker(); } catch (err) { }
            }
        });
    },

    close(select) {
        if (select.dataset.isHovered !== 'true') return;
        select.size = 1;
        select.style.zIndex = '10';
        select.style.boxShadow = 'none';
        select.style.height = '';
        select.dataset.isHovered = 'false';
        select.blur();
    },
};
