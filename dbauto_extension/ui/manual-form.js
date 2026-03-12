// =============================================
// ui/manual-form.js — 수동 기입 폼 렌더링 & 상태 관리
// 책임: 폼 HTML 생성, 상태 저장/복원, 일괄 복사, 리스트 빌더
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.ManualForm = {
    _isRendering: false,

    init() {
        const container = document.getElementById('manual-form-container');

        // 새로고침 버튼 — 저장 상태 초기화 후 재렌더링
        document.getElementById('refresh-manual-windows').onclick = () => {
            this._isRendering = true;
            chrome.storage.local.set({ manualFormState: {} }, () => {
                this.renderForms();
                setTimeout(() => { this._isRendering = false; }, 500);
            });
        };

        // 폼 입력 시 자동 저장
        container.addEventListener('input', () => this.saveState());
        container.addEventListener('change', () => this.saveState());

        // 이벤트 위임: 개별 전송 / 개별 새로고침 / 아코디언 토글
        container.addEventListener('click', (e) => {
            // 창 탭 전환
            const windowTab = e.target.closest('.window-tab');
            if (windowTab) {
                this._switchToTab(parseInt(windowTab.dataset.tabidx));
                return;
            }
            // 칩 버튼 선택
            const chip = e.target.closest('.chip');
            if (chip) {
                const chipGroup = chip.closest('.chip-group');
                if (!chipGroup) return;
                const field = chipGroup.dataset.field;
                const tabId = chipGroup.dataset.tabid;
                const panel = document.getElementById(`manual-form-${tabId}`);
                const hiddenInput = panel?.querySelector(`.manual-input-${field}`);
                const wasActive = chip.classList.contains('chip-active');
                chipGroup.querySelectorAll('.chip').forEach(c => c.classList.remove('chip-active'));
                if (!wasActive) {
                    chip.classList.add('chip-active');
                    if (hiddenInput) hiddenInput.value = chip.dataset.value;
                    // 대상자 구분 → 이름 옵션 동적 로딩
                    if (field === 'svcExecRecipientTyCd') {
                        const targetSelect = panel?.querySelector('.builder-select-svcExecRecipientId');
                        if (targetSelect) {
                            targetSelect.innerHTML = '<option value="">로딩 중...</option>';
                            chrome.tabs.sendMessage(parseInt(tabId), { action: window.DBAuto.Actions.UPDATE_TY_CD, value: chip.dataset.value, silent: true }, (res) => {
                                targetSelect.innerHTML = (!chrome.runtime.lastError && res?.svcExecRecipientId)
                                    ? '<option value="" disabled selected hidden></option>' + res.svcExecRecipientId.map(o => `<option value="${o.value}">${o.text}</option>`).join('')
                                    : '<option value="" disabled selected hidden></option>';
                                this.saveState();
                            });
                        }
                    }
                } else {
                    if (hiddenInput) hiddenInput.value = '';
                    if (field === 'svcExecRecipientTyCd') {
                        const targetSelect = panel?.querySelector('.builder-select-svcExecRecipientId');
                        if (targetSelect) targetSelect.innerHTML = '<option value="" disabled selected hidden></option>';
                    }
                }
                this.saveState();
                return;
            }
            // styled-select 변경 시 has-value 클래스 토글
            const styledSel = e.target.closest('select.styled-select');
            if (styledSel) {
                styledSel.classList.toggle('has-value', !!styledSel.value);
            }
            const sendBtn = e.target.closest('[data-action="send-single"]');
            const refreshBtn = e.target.closest('[data-action="refresh-single"]');
            if (sendBtn) {
                this._handleSingleFill(parseInt(sendBtn.dataset.tabid));
            } else if (refreshBtn) {
                e.stopPropagation();
                this._handleSingleRefresh(parseInt(refreshBtn.dataset.tabid));
            }
        });
        // styled-select change → has-value 동기화
        container.addEventListener('change', (e) => {
            if (e.target.matches('select.styled-select')) {
                e.target.classList.toggle('has-value', !!e.target.value);
            }
        });

        // 수동 일괄 기입 전송 버튼
        document.getElementById('manual-fill-btn').onclick = () => this._handleManualFill();

        // textarea 자동 높이 조절
        container.addEventListener('input', (e) => {
            if (e.target.tagName === 'TEXTAREA') {
                e.target.style.height = 'auto';
                e.target.style.height = e.target.scrollHeight + 'px';
            }
        });

        // 🔍 확대 편집 모달
        container.addEventListener('click', (e) => {
            const expandBtn = e.target.closest('.expand-btn');
            if (!expandBtn) return;
            const field = expandBtn.dataset.field;
            const tabId = expandBtn.dataset.tabid;
            const textarea = container.querySelector(`.manual-input-${field}[data-tabid="${tabId}"]`);
            if (!textarea) return;
            this._openExpandModal(textarea);
        });

        // ─── 스텝퍼 버튼 ───
        container.addEventListener('click', (e) => {
            const btn = e.target.closest('.stepper-btn');
            if (!btn) return;
            const stepper = btn.closest('.stepper');
            if (!stepper) return;
            const field = stepper.dataset.field;
            const tabId = stepper.dataset.tabid;
            const min = parseInt(stepper.dataset.min) || 0;
            const max = parseInt(stepper.dataset.max) || 999;
            const panel = stepper.closest('.manual-form-group');
            const hiddenInput = panel?.querySelector(`.manual-input-${field}`);
            if (!hiddenInput) return;

            let val = parseInt(hiddenInput.value) || 0;
            const delta = btn.dataset.delta ? parseInt(btn.dataset.delta)
                : (btn.classList.contains('stepper-minus') ? -1 : 1);
            val = Math.max(min, Math.min(max, val + delta));
            hiddenInput.value = val;
            stepper.querySelector('.stepper-val').textContent = val;

            // 비활성화 처리: 각 버튼의 delta 기준으로 개별 판단
            stepper.querySelectorAll('.stepper-minus').forEach(b => {
                const d = parseInt(b.dataset.delta) || -1;
                b.disabled = (val + d < min);
            });
            stepper.querySelectorAll('.stepper-plus').forEach(b => {
                const d = parseInt(b.dataset.delta) || 1;
                b.disabled = (val + d > max);
            });

            this.saveState();
        });
    },

    // ── 탭 패널 전환 (캐러셀 스크롤 및 실제 브라우저 탭 포커스) ──
    _switchToTab(tabIdx) {
        const container = document.getElementById('manual-form-container');
        const tabs = container.querySelectorAll('.window-tab');
        tabs.forEach((t, i) => t.classList.toggle('active', i === tabIdx));
        
        const panels = container.querySelectorAll('.manual-form-group');
        if (panels[tabIdx]) {
            panels[tabIdx].scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
            
            // 실제 브라우저 탭 및 창 포커스
            const activeTab = tabs[tabIdx];
            const tabId = parseInt(activeTab.dataset.tabid);
            if (tabId) {
                chrome.tabs.update(tabId, { active: true });
                chrome.tabs.get(tabId, (tab) => {
                    if (tab && !chrome.runtime.lastError) {
                        chrome.windows.update(tab.windowId, { focused: true });
                    }
                });
            }
        }
    },

    // ── 칩 동기화: 저장된 값으로 chip-active 복원 ──
    _syncChips(groupEl) {
        groupEl.querySelectorAll('.chip-group').forEach(chipGroup => {
            const field = chipGroup.dataset.field;
            const panel = chipGroup.closest('.manual-form-group');
            const hiddenInput = panel?.querySelector(`.manual-input-${field}`);
            if (!hiddenInput) return;
            const val = hiddenInput.value;
            chipGroup.querySelectorAll('.chip').forEach(chip => {
                chip.classList.toggle('chip-active', chip.dataset.value === val && !!val);
            });
        });
        // styled-select has-value 동기화
        groupEl.querySelectorAll('select.styled-select').forEach(sel => {
            sel.classList.toggle('has-value', !!sel.value);
        });
        // 스텝퍼 동기화
        groupEl.querySelectorAll('.stepper').forEach(stepper => {
            const field = stepper.dataset.field;
            const hiddenInput = groupEl.querySelector(`.manual-input-${field}`);
            if (!hiddenInput) return;
            const val = parseInt(hiddenInput.value) || 0;
            const min = parseInt(stepper.dataset.min) || 0;
            const max = parseInt(stepper.dataset.max) || 999;
            stepper.querySelector('.stepper-val').textContent = val;
            stepper.querySelectorAll('.stepper-minus').forEach(b => {
                const d = parseInt(b.dataset.delta) || -1;
                b.disabled = (val + d < min);
            });
            stepper.querySelectorAll('.stepper-plus').forEach(b => {
                const d = parseInt(b.dataset.delta) || 1;
                b.disabled = (val + d > max);
            });
        });
    },

    // ─── 폼 렌더링 ───
    async renderForms() {
        const container = document.getElementById('manual-form-container');
        container.innerHTML = '<div style="text-align:center; padding:15px; color:#666; font-size:11px;">대상 창을 검색 중입니다...</div>';

        const tabs = await window.DBAuto.Messenger.queryTargetTabs();
        if (tabs.length === 0) {
            container.innerHTML = '<div style="text-align:center; padding:15px; color:#999; font-size:11px;">감지된 시스템 창이 없습니다.<br>아동학대정보시스템 창을 열어주세요.</div>';
            return;
        }

        const Actions = window.DBAuto.Actions;
        const optionsList = await Promise.all(tabs.map(tab =>
            new Promise(resolve => {
                chrome.tabs.sendMessage(tab.id, { action: Actions.GET_FORM_OPTIONS }, (options) => {
                    resolve(chrome.runtime.lastError ? {} : (options || {}));
                });
            })
        ));

        // 이름 마스킹 유틸
        const maskName = name => {
            if (!name || name.length <= 1) return name;
            if (name.length === 2) return name[0] + 'O';
            return name[0] + 'O'.repeat(name.length - 2) + name[name.length - 1];
        };

        // 탭 바 (피해아동 이름 포함 - 첫 번째 이름만)
        const tabBarHtml = `<div class="window-tab-bar">${tabs.map((tab, i) => {
            const opts = optionsList[i];
            const masked = (opts.victimNames || []).map(maskName).filter(Boolean);
            const label = masked.length > 0 ? `창 ${i + 1}(${masked[0]})` : `창 ${i + 1}`;
            return `<button class="window-tab${i === 0 ? ' active' : ''}" data-tabidx="${i}" data-tabid="${tab.id}">${label}</button>`;
        }).join('')}</div>`;

        const panelsHtml = tabs.map((tab, index) =>
            this._createFormHtml(tab, optionsList[index], index)
        ).join('');

        container.innerHTML = tabBarHtml + `<div class="manual-carousel">${panelsHtml}</div>`;

        // 상태 복원
        tabs.forEach((tab, index) => {
            const panel = document.getElementById(`manual-form-${tab.id}`);
            if (!panel) return;
            this._restoreState(tab.id, panel);
        });

        // 캐러셀 스크롤 → 탭 활성 동기화
        const carousel = container.querySelector('.manual-carousel');
        if (carousel) {
            let scrollTimer;
            carousel.addEventListener('scroll', () => {
                clearTimeout(scrollTimer);
                scrollTimer = setTimeout(() => {
                    const panels = carousel.querySelectorAll('.manual-form-group');
                    const scrollLeft = carousel.scrollLeft;
                    const containerWidth = carousel.clientWidth;
                    let closestIdx = 0;
                    let minDist = Infinity;
                    panels.forEach((p, i) => {
                        const dist = Math.abs(p.offsetLeft - scrollLeft - (containerWidth - p.offsetWidth) / 2);
                        if (dist < minDist) { minDist = dist; closestIdx = i; }
                    });
                    container.querySelectorAll('.window-tab').forEach((t, i) => t.classList.toggle('active', i === closestIdx));
                }, 50);
            });
        }
    },

    // ─── 상태 저장 ───
    saveState() {
        if (this._isRendering) return;
        chrome.storage.local.get(['manualFormState'], (res) => {
            const state = res.manualFormState || {};
            document.querySelectorAll('.manual-form-group').forEach(group => {
                const tabId = group.id.replace('manual-form-', '');
                if (!state[tabId]) state[tabId] = {};

                group.querySelectorAll('.form-input').forEach(el => {
                    const inputClass = Array.from(el.classList).find(c => c.startsWith('manual-input-'));
                    if (inputClass) {
                        const key = inputClass.replace('manual-input-', '');
                        state[tabId][key] = el.value;
                    }
                });

                group.querySelectorAll('.list-builder-container').forEach(container => {
                    const field = container.dataset.field;
                    const items = Array.from(container.querySelectorAll('.builder-item')).map(it => ({
                        value: it.dataset.value,
                        text: it.dataset.text,
                        tyCd: it.dataset.tycd || ''
                    }));
                    state[tabId][field] = items;
                });
            });
            try {
                chrome.storage.local.set({ manualFormState: state });
            } catch (e) {
                console.error("Export failed:", e);
            }
        });
    },

    // ─── 상태 복원 ───
    _restoreState(tabId, groupEl) {
        if (!groupEl) return;

        const syncUI = () => {
            this._syncChips(groupEl);
            // 스테퍼 disabled 상태 초기화
            groupEl.querySelectorAll('.stepper').forEach(stepper => {
                const field = stepper.dataset.field;
                const hiddenInput = groupEl.querySelector(`.manual-input-${field}`);
                if (!hiddenInput) return;
                const val = parseInt(hiddenInput.value) || 0;
                const min = parseInt(stepper.dataset.min) || 0;
                const max = parseInt(stepper.dataset.max) || 999;
                stepper.querySelector('.stepper-val').textContent = val;
                stepper.querySelectorAll('.stepper-minus').forEach(b => {
                    const d = parseInt(b.dataset.delta) || -1;
                    b.disabled = (val + d < min);
                });
                stepper.querySelectorAll('.stepper-plus').forEach(b => {
                    const d = parseInt(b.dataset.delta) || 1;
                    b.disabled = (val + d > max);
                });
            });
            // 날짜 트리거 버튼 텍스트 동기화
            groupEl.querySelectorAll('.date-trigger').forEach(btn => {
                const inputId = btn.dataset.for;
                const input = document.getElementById(inputId);
                if (input && input.value) btn.textContent = input.value;
            });
        };

        chrome.storage.local.get(['manualFormState'], (res) => {
            const state = res.manualFormState;
            if (state && state[tabId]) {
                const tabState = state[tabId];
                groupEl.querySelectorAll('.form-input').forEach(el => {
                    const inputClass = Array.from(el.classList).find(c => c.startsWith('manual-input-'));
                    if (inputClass) {
                        const key = inputClass.replace('manual-input-', '');
                        if (tabState[key] !== undefined && tabState[key] !== '') el.value = tabState[key];
                    }
                });

                groupEl.querySelectorAll('.list-builder-container').forEach(container => {
                    const field = container.dataset.field;
                    const items = tabState[field];
                    if (Array.isArray(items)) {
                        const list = container.querySelector(`.builder-list-${field}`);
                        list.innerHTML = '';
                        items.forEach(it => this.renderBuilderItem(list, it.value, it.text, it.tyCd));
                    }
                });
            }
            syncUI();
        });
    },

    // ─── 폼 HTML 생성 ───
    _createFormHtml(tab, options, index) {
        // 칩 버튼 그룹 (옵션 수 적고 텍스트 짧은 필드 전용)
        const buildButtonGroup = (id, opts = [], defaultText = '') => {
            const safeOpts = (opts || []).filter(o => o.value && !o.text.includes('선택'));

            let matchedVal = '';
            if (defaultText) {
                const target = safeOpts.find(o => o.text.includes(defaultText) || o.value === defaultText);
                if (target) matchedVal = target.value;
                else matchedVal = defaultText; // 폴백용 fallback
            }

            const chips = safeOpts.map(o => {
                const display = o.text.includes(' :: ') ? o.text.split(' :: ').pop() : o.text;
                const isDefault = matchedVal && o.value === matchedVal;
                return `<button type="button" class="chip${isDefault ? ' chip-active' : ''}" data-value="${o.value}" title="${o.text}">${display}</button>`;
            }).join('');
            return `<div class="chip-group-wrapper"><input type="hidden" class="form-input manual-input-${id}" data-tabid="${tab.id}" value="${matchedVal}"><div class="chip-group" data-field="${id}" data-tabid="${tab.id}">${chips}</div></div>`;
        };

        // 서비스 전용 styled-select (칩과 같은 시각 언어)
        const buildStyledSelect = (id, opts = []) => {
            const safeOpts = (opts || []).filter(o => o.value && !o.text.includes('선택'));
            return `<select class="form-input styled-select hover-select manual-input-${id}" data-tabid="${tab.id}" autocomplete="off">
                <option value="">선택</option>
                ${safeOpts.map(o => `<option value="${o.value}" title="${o.text}">${o.text}</option>`).join('')}
            </select>`;
        };

        const buildListBuilder = (id, opts = []) => {
            const safeOpts = (opts || []).filter(o => o.value && !o.text.includes('선택'));
            return `<div class="list-builder-container" data-field="${id}" data-tabid="${tab.id}">
                <div style="display:flex; gap:3px;">
                    <div class="hover-select-wrapper" style="position: relative; flex:1;">
                        <select autocomplete="off" class="form-input builder-select-${id} hover-select" style="width:100%;position:absolute;top:0;left:0;box-sizing:border-box;z-index:10;min-height:22px;appearance:auto;cursor:pointer;background:#fff;">
                            <option value="" disabled selected hidden></option>
                            ${safeOpts.map(o => `<option value="${o.value}">${o.text}</option>`).join('')}
                        </select>
                        <div style="visibility:hidden;min-height:22px;width:100%;pointer-events:none;padding:3px 5px;font-size:10px;">&nbsp;</div>
                    </div>
                </div>
                <div class="builder-list-${id}" style="margin-top:3px;display:flex;flex-wrap:wrap;gap:3px;"></div>
            </div>`;
        };

        const buildInput = (id, placeholder, extraStyle = '', attr = '', type = 'text') =>
            `<input type="${type}" class="form-input manual-input-${id}" data-tabid="${tab.id}" placeholder="${placeholder}" style="${extraStyle}" ${attr}>`;

        return `
        <div class="manual-form-group window-panel" id="manual-form-${tab.id}">
        <div class="panel-header">
            ${(() => {
                const maskName = n => !n ? n : n.length <= 1 ? n : n.length === 2 ? n[0] + 'O' : n[0] + 'O'.repeat(n.length - 2) + n[n.length - 1];
                const masked = (options.victimNames || []).map(maskName).filter(Boolean);
                return masked.length > 0
                    ? `<span style="font-size:13px;font-weight:700;color:#333d4b;">피해아동: ${masked.join(', ')}</span>`
                    : `<span style="font-size:11px;color:#8b95a1;">피해아동 정보 없음</span>`;
            })()}
            <button class="refresh-single-btn" data-action="refresh-single" data-tabid="${tab.id}" title="새로고침" style="margin-left:auto;">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.59-9.21l5.67-5.67"/></svg>
            </button>
        </div>

        <div class="manual-form-body">
        <div class="form-row"><div class="form-label">제공구분</div>
            ${buildButtonGroup('provCd', [{ value: '제공', text: '제공' }, { value: '부가업무', text: '부가업무' }, { value: '거부', text: '거부' }], '제공')}
        </div>
        <div class="form-row"><div class="form-label">제공방법</div>${buildButtonGroup('provMeansCd',
                options.provMeansCd?.length ? options.provMeansCd :
                    [{ value: '전화', text: '전화' }, { value: '방문', text: '방문' }, { value: '내방', text: '내방' }],
                '전화'
            )}</div>
        <div class="form-row"><div class="form-label">서비스유형</div>${buildButtonGroup('provTyCd',
                options.provTyCd?.length ? options.provTyCd :
                    [{ value: '아보전서비스', text: '아보전서비스' }, { value: '연계서비스', text: '연계서비스' }, { value: '통합서비스', text: '통합서비스' }],
                '아보전서비스'
            )}</div>
        <div class="form-row"><div class="form-label">제공서비스</div>${buildStyledSelect('svcClassDetailCd', options.svcClassDetailCd)}</div>
        
        <div class="form-row"><div class="form-label">제공장소</div>
            <div style="display:flex; gap:5px; flex:1; flex-wrap:wrap; align-items:center;">
                ${buildButtonGroup('svcProvLocCd',
                options.svcProvLocCd?.length ? options.svcProvLocCd :
                    [{ value: '기관내', text: '기관내' }, { value: '아동가정', text: '아동가정' }, { value: '유관기관', text: '유관기관' }, { value: '기타', text: '기타' }],
                '기관내'
            )}
                ${buildInput('svcProvLocEtc', '기타 장소', 'width:120px; flex:none;')}
            </div>
        </div>
        <div class="form-row"><div class="form-label">제공일시</div>
            <div style="display:flex; flex-direction:column; gap:4px; flex:1; font-size:11px; white-space:nowrap;">
                <div style="display:flex; align-items:center; gap:2px;">
                    <input type="hidden" class="form-input manual-input-startDate" data-tabid="${tab.id}" id="dp-start-${tab.id}" value="${new Date().toISOString().slice(0, 10)}">
                    <button type="button" class="date-trigger" data-for="dp-start-${tab.id}">${new Date().toISOString().slice(0, 10)}</button>
                    ${buildInput('startHH', 'HH', 'width:24px; text-align:center; padding:0;', 'maxlength="2"')}시
                    ${buildInput('startMI', 'MM', 'width:24px; text-align:center; padding:0;', 'maxlength="2"')}분~
                </div>
                <div style="display:flex; align-items:center; gap:2px;">
                    <input type="hidden" class="form-input manual-input-endDate" data-tabid="${tab.id}" id="dp-end-${tab.id}" value="${new Date().toISOString().slice(0, 10)}">
                    <button type="button" class="date-trigger" data-for="dp-end-${tab.id}">${new Date().toISOString().slice(0, 10)}</button>
                    ${buildInput('endHH', 'HH', 'width:24px; text-align:center; padding:0;', 'maxlength="2"')}시
                    ${buildInput('endMI', 'MM', 'width:24px; text-align:center; padding:0;', 'maxlength="2"')}분
                </div>
            </div>
        </div>
        
        <div class="form-row"><div class="form-label"></div>
            <div style="display:flex; gap:12px; flex:1; align-items:center; font-size:10px; flex-wrap:wrap;">
                <span style="display:flex;align-items:center;gap:4px;">제공횟수
                    <input type="hidden" class="form-input manual-input-cnt_val" data-tabid="${tab.id}" value="1">
                    <span class="stepper" data-field="cnt_val" data-tabid="${tab.id}" data-min="1" data-max="100" data-step-minus="1" data-step-plus="1">
                        <button type="button" class="stepper-btn stepper-minus" disabled>−</button>
                        <span class="stepper-val">1</span>
                        <button type="button" class="stepper-btn stepper-plus">+</button>
                    </span>회
                </span>
                <span style="display:flex;align-items:center;gap:4px;">이동소요
                    <input type="hidden" class="form-input manual-input-mvmnReqreHr_val" data-tabid="${tab.id}" value="0">
                    <span class="stepper" data-field="mvmnReqreHr_val" data-tabid="${tab.id}" data-min="0" data-max="999" data-step-minus="5,1" data-step-plus="1,5">
                        <button type="button" class="stepper-btn stepper-minus" data-delta="-5" disabled>−5</button>
                        <button type="button" class="stepper-btn stepper-minus" data-delta="-1" disabled>−1</button>
                        <span class="stepper-val">0</span>
                        <button type="button" class="stepper-btn stepper-plus" data-delta="1">+1</button>
                        <button type="button" class="stepper-btn stepper-plus" data-delta="5">+5</button>
                    </span>분
                </span>
            </div>
        </div>

        <div class="form-row" style="align-items:flex-start;"><div class="form-label" style="padding-top:5px;">서비스내용</div>
            <div style="flex:1; position:relative;">
                <textarea class="form-input manual-input-desc_val" data-tabid="${tab.id}" placeholder="서비스 내용 입력" rows="2" style="width:100%; resize:none; overflow:hidden; min-height:36px; padding-bottom: 22px;"></textarea>
                <div class="expand-btn" data-field="desc_val" data-tabid="${tab.id}">+ 확대</div>
            </div>
        </div>
        <div class="form-row" style="align-items:flex-start;"><div class="form-label" style="padding-top:5px;">상담원 소견</div>
            <div style="flex:1; position:relative;">
                <textarea class="form-input manual-input-opn_val" data-tabid="${tab.id}" placeholder="상담원 소견 입력" rows="2" style="width:100%; resize:none; overflow:hidden; min-height:36px; padding-bottom: 22px;"></textarea>
                <div class="expand-btn" data-field="opn_val" data-tabid="${tab.id}">+ 확대</div>
            </div>
        </div>
        <div style="display:flex; justify-content:flex-end; margin-top:8px;">
            <button class="btn-send-single" data-action="send-single" data-tabid="${tab.id}">이 창에 DB 입력</button>
        </div>
        </div><!-- /.manual-form-body -->
    </div>
    `;
    },

    // ─── 확대 편집 모달 ───
    _openExpandModal(sourceTextarea) {
        const overlay = document.createElement('div');
        overlay.className = 'expand-modal-overlay';
        overlay.innerHTML = `
            <div class="expand-modal">
                <div class="expand-modal-header">
                    <span style="font-weight:600; font-size:14px;">📝 텍스트 편집</span>
                    <button class="expand-modal-close">✕</button>
                </div>
                <textarea class="expand-modal-textarea">${sourceTextarea.value}</textarea>
                <div class="expand-modal-footer">
                    <span class="expand-modal-count">${sourceTextarea.value.length}자</span>
                    <button class="expand-modal-save btn btn-primary">저장</button>
                </div>
            </div>
        `;
        document.body.appendChild(overlay);

        const modalTextarea = overlay.querySelector('.expand-modal-textarea');
        const countEl = overlay.querySelector('.expand-modal-count');
        modalTextarea.focus();
        modalTextarea.addEventListener('input', () => {
            countEl.textContent = modalTextarea.value.length + '자';
        });

        const close = () => { overlay.remove(); };
        overlay.querySelector('.expand-modal-close').onclick = close;
        overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });
        overlay.querySelector('.expand-modal-save').onclick = () => {
            sourceTextarea.value = modalTextarea.value;
            sourceTextarea.style.height = 'auto';
            sourceTextarea.style.height = sourceTextarea.scrollHeight + 'px';
            sourceTextarea.dispatchEvent(new Event('input', { bubbles: true }));
            this.saveState();
            close();
        };
    },

    // ─── 리스트 빌더 항목 렌더링 ───
    renderBuilderItem(parent, value, text, tyCd = '') {
        const item = document.createElement('span');
        item.className = 'builder-item';
        item.dataset.value = value;
        item.dataset.text = text;
        if (tyCd) item.dataset.tycd = tyCd;
        item.style.cssText = 'background:#f2f4f6; border:1px solid #d1d6db; border-radius:12px; padding:2px 8px; font-size:10px; display:inline-flex; align-items:center; gap:4px; color:#333d4b;';
        item.innerHTML = `${text} <span class="builder-remove-btn" style="cursor:pointer; font-weight:bold; color:#8b95a1;">×</span>`;
        parent.appendChild(item);
    },

    // ─── 폼 그룹에서 레코드 데이터 추출 (공통) ───
    _buildRecordFromGroup(group, label) {
        const getVal = (id) => {
            const el = group.querySelector(`.manual-input-${id}`);
            return el ? el.value : '';
        };

        const getListBuilderVal = (id) => {
            const items = group.querySelectorAll(`.list-builder-container[data-field="${id}"] .builder-item`);
            return Array.from(items).map(it => it.dataset.text).join(',');
        };

        const getListBuilderFullVal = (id) => {
            const items = group.querySelectorAll(`.list-builder-container[data-field="${id}"] .builder-item`);
            return Array.from(items).map(it => ({
                value: it.dataset.value,
                text: it.dataset.text.trim(),
                tyCd: (it.dataset.tycd || '').trim()
            }));
        };

        const sd = getVal('startDate'), sh = getVal('startHH'), sm = getVal('startMI');
        const ed = getVal('endDate'), eh = getVal('endHH'), em = getVal('endMI');
        let dateTime_val = '';
        if (sd && sh && sm && ed && eh && em) {
            dateTime_val = `${sd} ${sh}:${sm}~${eh}:${em}`;
        }

        return {
            id: label,
            provCd_val: getVal('provCd'),
            provTyCd_val: getVal('provTyCd'),
            svcClassDetailCd_val: getVal('svcClassDetailCd'),
            recipient_val: getListBuilderVal('svcExecRecipientId'),
            recipient_fullVal: getListBuilderFullVal('svcExecRecipientId'),
            recipientTy_val_raw: getVal('svcExecRecipientTyCd'),
            provMeansCd_val: getVal('provMeansCd'),
            loc_val: getVal('svcProvLocCd'),
            locEtc_val_raw: getVal('svcProvLocEtc'),
            pic_val: getListBuilderVal('picId'),
            pic_fullVal: getListBuilderFullVal('picId'),
            dateTime_val: dateTime_val,
            mvmnReqreHr_val: getVal('mvmnReqreHr_val'),
            desc_val: getVal('desc_val'),
            opn_val: getVal('opn_val'),
            cnt_val: getVal('cnt_val') || 1
        };
    },

    // ─── 개별 창 새로고침 ───
    async _handleSingleRefresh(tabId) {
        const Actions = window.DBAuto.Actions;
        const group = document.getElementById(`manual-form-${tabId}`);
        if (!group) return;

        group.style.opacity = '0.5';

        // 1. 해당 탭의 저장 상태 초기화
        chrome.storage.local.get(['manualFormState'], async (res) => {
            const state = res.manualFormState || {};
            if (state[tabId]) delete state[tabId];
            chrome.storage.local.set({ manualFormState: state }, async () => {

                // 2. 탭 정보 다시 가져오기
                const tabs = await window.DBAuto.Messenger.queryTargetTabs();
                const tabIndex = tabs.findIndex(t => t.id === tabId);
                const tab = tabs[tabIndex];

                if (!tab) {
                    alert('해당 창을 찾을 수 없습니다.');
                    group.style.opacity = '1';
                    return;
                }

                // 3. 새 데이터로 DOM 부분 교체
                chrome.tabs.sendMessage(tabId, { action: Actions.GET_FORM_OPTIONS }, (options) => {
                    const newHtml = this._createFormHtml(tab, options || {}, tabIndex);
                    group.outerHTML = newHtml;
                    const newGroup = document.getElementById(`manual-form-${tab.id}`);
                    if (newGroup) newGroup.style.opacity = '1';
                });
            });
        });
    },

    // ─── 개별 창 전송 ───
    _handleSingleFill(tabId) {
        const Actions = window.DBAuto.Actions;
        const group = document.getElementById(`manual-form-${tabId}`);
        if (!group) return alert('해당 창의 폼을 찾을 수 없습니다.');

        const record = this._buildRecordFromGroup(group, `수동-개별`);

        console.log(`[dbauto] Sending data to tab ${tabId}:`, record);
        chrome.tabs.sendMessage(tabId, { action: Actions.START_AUTO_FILL, data: record }, (res) => {
            if (chrome.runtime.lastError) console.error(`기입 실패 (탭 ${tabId}):`, chrome.runtime.lastError);
        });

        alert('입력 요청이 해당 창에 발송되었습니다. 빨간색 필드가 없는지 확인하세요.');
    },

    // ─── 수동 일괄 기입 전송 ───
    _handleManualFill() {
        const Actions = window.DBAuto.Actions;
        const formGroups = document.querySelectorAll('.manual-form-group');
        if (formGroups.length === 0) return alert('기입할 창이 없습니다.');

        const confirmMsg = `현재 작성된 내용으로 ${formGroups.length}개의 창에 기입을 시작하시겠습니까?`;
        if (!confirm(confirmMsg)) return;

        formGroups.forEach((group, i) => {
            const tabId = parseInt(group.id.replace('manual-form-', ''));
            const record = this._buildRecordFromGroup(group, `수동-${i + 1}`);

            console.log(`[dbauto] Sending data to tab ${tabId}:`, record);
            chrome.tabs.sendMessage(tabId, { action: Actions.START_AUTO_FILL, data: record }, (res) => {
                if (chrome.runtime.lastError) console.error(`기입 실패 (탭 ${tabId}):`, chrome.runtime.lastError);
            });
        });

        alert('수동 일괄 입력 요청이 각 창에 발송되었습니다. 창마다 빨간색 필드가 없는지 확인하세요.');
    },
};

window.addListItem = function (field, tabId) {
    const container = document.querySelector(`.list-builder-container[data-field="${field}"][data-tabid="${tabId}"]`);
    if (!container) return;
    const select = container.querySelector(`.builder-select-${field}`);
    const list = container.querySelector(`.builder-list-${field}`);

    let tyCd = '';
    if (field === 'svcExecRecipientId') {
        const group = document.getElementById(`manual-form-${tabId}`);
        if (group) {
            const tySelect = group.querySelector('.manual-input-svcExecRecipientTyCd');
            if (tySelect) tyCd = tySelect.value;
        }
    }

    if (!select.value) return;

    if (Array.from(list.querySelectorAll('.builder-item')).some(el => el.dataset.value === select.value)) {
        alert('이미 추가된 항목입니다.');
        return;
    }

    window.DBAuto.ManualForm.renderBuilderItem(list, select.value, select.options[select.selectedIndex].text, tyCd);
    window.DBAuto.ManualForm.saveState();
};
