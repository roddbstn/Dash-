// =============================================
// ui/date-picker.js — 커스텀 날짜 선택 UI
// 참고 디자인: 둥근 모서리, 좌/우 화살표, 오늘 표시, 선택 강조
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.DatePicker = {
    _overlay: null,
    _picker: null,
    _target: null,    // 값이 저장될 hidden input
    _display: null,   // 보여줄 버튼 요소
    _currentYear: 0,
    _currentMonth: 0, // 0-indexed

    init() {
        // 전역 클릭 위임: .date-trigger 클릭 시 피커 열기
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
        this.close(); // 기존 것 닫기

        this._display = displayEl;
        this._target = inputEl;

        // 현재 값 파싱
        const val = inputEl?.value || new Date().toISOString().slice(0, 10);
        const parts = val.split('-');
        this._currentYear = parseInt(parts[0]) || new Date().getFullYear();
        this._currentMonth = (parseInt(parts[1]) || (new Date().getMonth() + 1)) - 1;

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
        // 반투명 오버레이
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
        const selectedStr = this._target?.value || '';

        const monthNames = ['1월', '2월', '3월', '4월', '5월', '6월', '7월', '8월', '9월', '10월', '11월', '12월'];

        // 이 달의 1일: 어떤 요일인지
        const firstDay = new Date(year, month, 1).getDay(); // 0=일
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const daysInPrev = new Date(year, month, 0).getDate();

        // 월 시작을 월요일 기준으로 (0=월 ... 6=일)
        const startOffset = (firstDay + 6) % 7;

        let html = `
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

        // 이전 달 날짜
        for (let i = startOffset - 1; i >= 0; i--) {
            html += `<span class="dp-day dp-other">${daysInPrev - i}</span>`;
        }

        // 이번 달 날짜
        for (let d = 1; d <= daysInMonth; d++) {
            const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
            const classes = ['dp-day'];
            if (dateStr === todayStr) classes.push('dp-today');
            if (dateStr === selectedStr) classes.push('dp-selected');
            html += `<span class="${classes.join(' ')}" data-date="${dateStr}">${d}</span>`;
        }

        // 다음 달 날짜 (6줄 채우기)
        const totalCells = startOffset + daysInMonth;
        const remaining = (7 - (totalCells % 7)) % 7;
        for (let i = 1; i <= remaining; i++) {
            html += `<span class="dp-day dp-other">${i}</span>`;
        }

        html += '</div>';

        // 오늘 바로가기 버튼
        html += `<div class="dp-footer"><button class="dp-today-btn">오늘</button></div>`;

        this._picker.innerHTML = html;

        // 이벤트 바인딩
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
        this._picker.querySelector('.dp-today-btn').addEventListener('click', () => {
            this._selectDate(todayStr);
        });
        this._picker.querySelectorAll('.dp-day:not(.dp-other)').forEach(el => {
            el.addEventListener('click', () => {
                this._selectDate(el.dataset.date);
            });
        });
    },

    _selectDate(dateStr) {
        if (this._target) {
            this._target.value = dateStr;
            this._target.dispatchEvent(new Event('change', { bubbles: true }));
        }
        if (this._display) {
            this._display.textContent = dateStr;
        }
        // 저장 트리거
        if (window.DBAuto.ManualForm) {
            window.DBAuto.ManualForm.saveState();
        }
        this.close();
    },
};
