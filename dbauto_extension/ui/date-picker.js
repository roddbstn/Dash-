// =============================================
// ui/date-picker.js — 커스텀 날짜 선택 UI
// 참고 디자인: 둥근 모서리, 좌/우 화살표, 오늘 표시, 선택 강조, 우측 시간/소요시간 선택
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.DatePicker = {
    _overlay: null,
    _picker: null,
    _target: null,    // 값이 저장될 hidden input
    _display: null,   // 보여줄 버튼 요소
    _currentYear: 0,
    _currentMonth: 0, // 0-indexed
    _selectedDateStr: '',
    _selectedTime: '',
    _selectedDuration: 0,

    init() {
        document.addEventListener('click', (e) => {
            const trigger = e.target.closest('.date-trigger');
            if (trigger) {
                e.stopPropagation();
                const inputId = trigger.dataset.for;
                const input = document.getElementById(inputId) || trigger.parentElement.querySelector(`input.${inputId}`);
                this.open(trigger, input);
                return;
            }
        });
    },

    open(displayEl, inputEl) {
        this.close();

        this._display = displayEl;
        this._target = inputEl;

        const val = inputEl?.value || new Date().toISOString().slice(0, 10);
        const parts = val.split('-');
        this._currentYear = parseInt(parts[0]) || new Date().getFullYear();
        this._currentMonth = (parseInt(parts[1]) || (new Date().getMonth() + 1)) - 1;

        this._selectedDateStr = val;
        this._selectedTime = '';
        this._selectedDuration = 0;

        // Try to read hour/min from adjacent inputs if it's the start date
        if (inputEl) {
            const panel = inputEl.closest('.manual-form-group');
            if (panel && inputEl.classList.contains('manual-input-startDate')) {
                const hh = panel.querySelector('.manual-input-startHH')?.value;
                const mi = panel.querySelector('.manual-input-startMI')?.value;
                if (hh && mi) {
                    let hInt = parseInt(hh, 10);
                    let displayH = hInt > 12 ? hInt - 12 : hInt;
                    if (hInt === 12) displayH = 12;
                    if (hInt === 0) displayH = 12;
                    let mStr = mi === '0' || mi === '00' ? '00' : '30';
                    this._selectedTime = `${displayH}:${mStr}`;
                }
            }
        }

        this._createOverlay();
        this._render();
    },

    close() {
        if (this._overlay) {
            this._overlay.remove();
            this._overlay = null;
            this._picker = null;
        }
    },

    _createOverlay() {
        this._overlay = document.createElement('div');
        this._overlay.className = 'dp-overlay';
        this._overlay.addEventListener('click', (e) => {
            if (e.target === this._overlay) this.close();
        });

        this._picker = document.createElement('div');
        this._picker.className = 'dp-picker';
        this._overlay.appendChild(this._picker);
        document.body.appendChild(this._overlay);
    },

    _render() {
        const year = this._currentYear;
        const month = this._currentMonth;
        const today = new Date();
        const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

        const monthNames = ['1월', '2월', '3월', '4월', '5월', '6월', '7월', '8월', '9월', '10월', '11월', '12월'];

        const firstDay = new Date(year, month, 1).getDay();
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const daysInPrev = new Date(year, month, 0).getDate();
        const startOffset = (firstDay + 6) % 7; // 월요일=0, 일요일=6

        let html = `<div class="dp-container">`;

        // --- LEFT: Calendar ---
        html += `<div class="dp-left">`;
        html += `
            <div class="dp-header">
                <button class="dp-nav dp-prev" title="이전 달">‹</button>
                <span class="dp-title">${year}년 ${monthNames[month]}</span>
                <button class="dp-nav dp-next" title="다음 달">›</button>
            </div>
            <div class="dp-weekdays">
                <span>월</span><span>화</span><span>수</span><span>목</span><span>금</span><span class="dp-sat">토</span><span class="dp-sun">일</span>
            </div>
            <div class="dp-days">
        `;

        for (let i = startOffset - 1; i >= 0; i--) {
            html += `<span class="dp-day dp-other">${daysInPrev - i}</span>`;
        }
        for (let d = 1; d <= daysInMonth; d++) {
            const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
            const classes = ['dp-day'];
            if (dateStr === todayStr) classes.push('dp-today');
            if (dateStr === this._selectedDateStr) classes.push('dp-selected');
            html += `<span class="${classes.join(' ')}" data-date="${dateStr}">${d}</span>`;
        }
        const totalCells = startOffset + daysInMonth;
        const remaining = (7 - (totalCells % 7)) % 7;
        for (let i = 1; i <= remaining; i++) {
            html += `<span class="dp-day dp-other">${i}</span>`;
        }
        html += `</div>`;
        html += `<div class="dp-footer"><button class="btn btn-primary dp-apply-btn" style="width:100%; padding:10px 0; margin-top:10px;">적용하기</button></div>`;
        html += `</div>`; // .dp-left

        const isStartDate = this._target && this._target.classList.contains('manual-input-startDate');

        // --- RIGHT: Time & Duration ---
        if (isStartDate) {
            html += `<div class="dp-right">`;
            let dateHeader = "날짜를 먼저 선택하세요";
            if (this._selectedDateStr) {
                const dObj = new Date(this._selectedDateStr);
                const days = ['일', '월', '화', '수', '목', '금', '토'];
                dateHeader = `${dObj.getMonth() + 1}월 ${dObj.getDate()}일 (${days[dObj.getDay()]})<br>협의된 시간을 알려주세요.`;
            }

            html += `<div class="dp-right-title" style="flex-shrink:0;">${dateHeader}</div>`;

            // === 시간 선택 영역 (Scrollable) ===
            html += `<div class="dp-scroll-section" style="margin-bottom: 8px;">`;
            html += `<div class="dp-section-title">오전</div><div class="dp-time-grid">`;
            for (let h = 8; h < 12; h++) {
                for (let m = 0; m <= 30; m += 30) {
                    const t = `${h}:${m === 0 ? '00' : '30'}`;
                    html += `<div class="dp-time-btn ${this._selectedTime === t ? 'active' : ''}" data-time="${t}" data-hour="${h}">${t}</div>`;
                }
            }
            html += `</div>`;

            html += `<div class="dp-section-title">오후</div><div class="dp-time-grid">`;
            for (let h = 12; h <= 21; h++) {
                for (let m = 0; m <= 30; m += 30) {
                    if (h === 21 && m === 30) continue;
                    const displayH = h > 12 ? h - 12 : h;
                    const t = `${displayH}:${m === 0 ? '00' : '30'}`;
                    html += `<div class="dp-time-btn ${this._selectedTime === t ? 'active' : ''}" data-time="${t}" data-hour="${h}">${t}</div>`;
                }
            }
            html += `</div>`;
            html += `</div>`;

            // === 상담 소요시간 영역 (Scrollable) ===
            html += `<div class="dp-scroll-section" style="border-top:1px dashed #e5e8eb; padding-top:12px;">`;
            html += `<div class="dp-section-title" style="margin-top:0;">상담 소요시간</div><div class="dp-time-grid">`;
            for (let t = 10; t <= 120; t += 10) {
                let text = t < 60 ? `${t}분` : (t === 60 ? `1시간` : (t === 120 ? `2시간` : `1시간 ${t - 60}분`));
                html += `<div class="dp-duration-btn ${this._selectedDuration === t ? 'active' : ''}" data-dur="${t}">${text}</div>`;
            }
            html += `</div>`;
            html += `</div>`;
            html += `</div>`; // .dp-right
        }

        html += `</div>`; // .dp-container

        this._picker.innerHTML = html;

        // Events
        this._picker.querySelector('.dp-prev').addEventListener('click', () => {
            this._currentMonth--;
            if (this._currentMonth < 0) { this._currentMonth = 11; this._currentYear--; }
            this._render();
        });
        this._picker.querySelector('.dp-next').addEventListener('click', () => {
            this._currentMonth++;
            if (this._currentMonth > 11) { this._currentMonth = 0; this._currentYear++; }
            this._render();
        });
        this._picker.querySelectorAll('.dp-day:not(.dp-other)').forEach(el => {
            el.addEventListener('click', () => {
                this._selectedDateStr = el.dataset.date;
                this._render();
            });
        });
        this._picker.querySelectorAll('.dp-time-btn').forEach(el => {
            el.addEventListener('click', () => {
                this._selectedTime = el.dataset.time;
                this._render();
            });
        });
        this._picker.querySelectorAll('.dp-duration-btn').forEach(el => {
            el.addEventListener('click', () => {
                this._selectedDuration = parseInt(el.dataset.dur);
                this._render();
            });
        });
        this._picker.querySelector('.dp-apply-btn').addEventListener('click', () => {
            this._applySelection();
        });
    },

    _applySelection() {
        if (!this._selectedDateStr) {
            alert('날짜를 선택해주세요.');
            return;
        }

        const isStartDateTrigger = this._target && this._target.classList.contains('manual-input-startDate');

        if (isStartDateTrigger && (!this._selectedTime || !this._selectedDuration)) {
            alert('시간과 상담 소요시간을 모두 선택해주세요.');
            return;
        }

        // Fill date
        if (this._target) {
            this._target.value = this._selectedDateStr;
            this._target.dispatchEvent(new Event('change', { bubbles: true }));
        }
        if (this._display) {
            this._display.textContent = this._selectedDateStr;
        }

        // Fill time and duration if it's the start date
        if (isStartDateTrigger) {
            const panel = this._target.closest('.manual-form-group');
            if (panel) {
                const activeTimeBtn = this._picker.querySelector('.dp-time-btn.active');
                let hInt = 0;
                let mInt = 0;
                if (activeTimeBtn) {
                    const t = activeTimeBtn.dataset.time;
                    const [hh, mm] = t.split(':');
                    hInt = parseInt(hh, 10);
                    mInt = parseInt(mm, 10);

                    if (activeTimeBtn.dataset.hour) {
                        hInt = parseInt(activeTimeBtn.dataset.hour, 10);
                    }
                }

                const startHHInput = panel.querySelector('.manual-input-startHH');
                const startMIInput = panel.querySelector('.manual-input-startMI');
                const endDateInput = panel.querySelector('.manual-input-endDate');
                const endHHInput = panel.querySelector('.manual-input-endHH');
                const endMIInput = panel.querySelector('.manual-input-endMI');

                if (startHHInput) {
                    startHHInput.value = String(hInt).padStart(2, '0');
                    startHHInput.dispatchEvent(new Event('change', { bubbles: true }));
                }
                if (startMIInput) {
                    startMIInput.value = String(mInt).padStart(2, '0');
                    startMIInput.dispatchEvent(new Event('change', { bubbles: true }));
                }

                if (endDateInput && endHHInput && endMIInput) {
                    const totalMin = hInt * 60 + mInt + this._selectedDuration;
                    const endH = Math.floor(totalMin / 60);
                    const endM = totalMin % 60;

                    endDateInput.value = this._selectedDateStr;
                    endDateInput.dispatchEvent(new Event('change', { bubbles: true }));

                    const endTrigger = panel.querySelector(`.date-trigger[data-for="${endDateInput.id}"]`);
                    if (endTrigger) endTrigger.textContent = this._selectedDateStr;

                    endHHInput.value = String(endH).padStart(2, '0');
                    endHHInput.dispatchEvent(new Event('change', { bubbles: true }));

                    endMIInput.value = String(endM).padStart(2, '0');
                    endMIInput.dispatchEvent(new Event('change', { bubbles: true }));
                }
            }
        }

        if (window.DBAuto.ManualForm) {
            window.DBAuto.ManualForm.saveState();
        }
        this.close();
    },
};
