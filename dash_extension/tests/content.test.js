// =============================================================================
// content.js 단위 테스트 — DOM 조작 및 비즈니스 로직 검증
// jsdom 환경에서 실제 DOM을 생성하여 함수 동작을 검증합니다.
// =============================================================================

// content.js의 핵심 순수 함수들을 테스트용으로 추출합니다.
// (content.js는 chrome.runtime.onMessage로 시작하므로 eval 로드 방식 사용)

// ── 테스트용 함수 정의 (content.js에서 추출) ────────────────────────────────

function smartFill(id, value, forceFail = false, allowEmpty = false) {
    const el = document.getElementById(id);
    if (!el) return;
    const hasValue = value !== undefined && value !== null && value !== '';
    if (!forceFail && (hasValue || allowEmpty)) {
        el.value = value || '';
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        el.classList.add('dbauto-success');
        setTimeout(() => el.classList.remove('dbauto-success'), 1500);
    } else {
        el.value = '';
        el.classList.add('dbauto-fail');
    }
}

function smartFillRadio(name, value) {
    const radio = document.querySelector(`input[name="${name}"][value="${value}"]`);
    if (radio) {
        radio.checked = true;
    } else {
        const firstRadio = document.querySelector(`input[name="${name}"]`);
        if (firstRadio) firstRadio.parentElement.classList.add('dbauto-fail');
    }
}

function markFail(id) {
    const el = document.getElementById(id);
    if (el) el.classList.add('dbauto-fail');
}

// 날짜/시간 파싱 로직 (handleAutoFill에서 추출)
function parseDateTimeVal(dateTime_val) {
    if (!dateTime_val) return null;
    const parts = dateTime_val.toString().trim().split(' ');
    if (parts.length < 2) return null;

    const datePart = parts[0];
    const timePart = parts[1];
    const isDateValid = /^\d{4}-\d{2}-\d{2}$/.test(datePart);

    const result = { date: datePart, isDateValid };
    if (timePart && timePart.includes('~')) {
        const [start, end] = timePart.split('~');
        const [sh, sm] = start.split(':');
        const [eh, em] = end.split(':');
        result.startHH = sh;
        result.startMI = sm;
        result.endHH = eh;
        result.endMI = em;
    }
    return result;
}

// ── 헬퍼: DOM 요소 생성 ───────────────────────────────────────────────────────

function createInput(id, type = 'text') {
    const el = document.createElement('input');
    el.id = id;
    el.type = type;
    document.body.appendChild(el);
    return el;
}

function createSelect(id) {
    const el = document.createElement('select');
    el.id = id;
    document.body.appendChild(el);
    return el;
}

function createTextarea(id) {
    const el = document.createElement('textarea');
    el.id = id;
    document.body.appendChild(el);
    return el;
}

// ── Setup / Teardown ─────────────────────────────────────────────────────────

beforeEach(() => {
    document.body.innerHTML = '';
});

// ─────────────────────────────────────────────────────────────────────────────
// smartFill 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('smartFill — 정상 기입', () => {
    test('존재하는 input에 값을 채움', () => {
        createInput('testField');
        smartFill('testField', 'A');
        expect(document.getElementById('testField').value).toBe('A');
    });

    test('성공 시 dbauto-success 클래스 추가됨', () => {
        createInput('testField');
        smartFill('testField', 'A');
        expect(document.getElementById('testField').classList.contains('dbauto-success')).toBe(true);
    });

    test('값 기입 시 input 이벤트 발생', () => {
        const el = createInput('testField');
        const inputHandler = jest.fn();
        el.addEventListener('input', inputHandler);
        smartFill('testField', 'A');
        expect(inputHandler).toHaveBeenCalledTimes(1);
    });

    test('값 기입 시 change 이벤트 발생', () => {
        const el = createInput('testField');
        const changeHandler = jest.fn();
        el.addEventListener('change', changeHandler);
        smartFill('testField', 'A');
        expect(changeHandler).toHaveBeenCalledTimes(1);
    });

    test('select 요소에도 동작', () => {
        const sel = createSelect('testSelect');
        const opt = document.createElement('option');
        opt.value = 'B'; sel.appendChild(opt);
        smartFill('testSelect', 'B');
        expect(sel.value).toBe('B');
        expect(sel.classList.contains('dbauto-success')).toBe(true);
    });

    test('textarea에도 동작', () => {
        createTextarea('testArea');
        smartFill('testArea', '상담 내용입니다.');
        expect(document.getElementById('testArea').value).toBe('상담 내용입니다.');
    });
});

describe('smartFill — 실패 처리', () => {
    test('존재하지 않는 ID: 에러 없이 무시', () => {
        expect(() => smartFill('nonExistent', 'A')).not.toThrow();
    });

    test('값이 없으면 dbauto-fail 클래스 추가', () => {
        createInput('testField');
        smartFill('testField', '');
        expect(document.getElementById('testField').classList.contains('dbauto-fail')).toBe(true);
    });

    test('값이 null이면 dbauto-fail', () => {
        createInput('testField');
        smartFill('testField', null);
        expect(document.getElementById('testField').classList.contains('dbauto-fail')).toBe(true);
    });

    test('값이 undefined이면 dbauto-fail', () => {
        createInput('testField');
        smartFill('testField', undefined);
        expect(document.getElementById('testField').classList.contains('dbauto-fail')).toBe(true);
    });

    test('forceFail=true이면 값이 있어도 실패', () => {
        createInput('testField');
        smartFill('testField', 'A', true);
        expect(document.getElementById('testField').classList.contains('dbauto-fail')).toBe(true);
        expect(document.getElementById('testField').value).toBe('');
    });

    test('실패 시 기존 값 초기화', () => {
        const el = createInput('testField');
        el.value = '기존값';
        smartFill('testField', '', false, false);
        expect(el.value).toBe('');
    });
});

describe('smartFill — allowEmpty 옵션', () => {
    test('allowEmpty=true이면 빈 값도 성공으로 처리', () => {
        createInput('testField');
        smartFill('testField', '', false, true);
        expect(document.getElementById('testField').classList.contains('dbauto-success')).toBe(true);
        expect(document.getElementById('testField').classList.contains('dbauto-fail')).toBe(false);
    });

    test('allowEmpty=true + 빈 값 → value는 빈 문자열', () => {
        createInput('testField');
        smartFill('testField', '', false, true);
        expect(document.getElementById('testField').value).toBe('');
    });

    test('allowEmpty=true + 실제 값 있으면 그 값 기입', () => {
        createInput('testField');
        smartFill('testField', '내용있음', false, true);
        expect(document.getElementById('testField').value).toBe('내용있음');
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// smartFillRadio 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('smartFillRadio', () => {
    function createRadioGroup(name, values) {
        values.forEach(val => {
            const wrap = document.createElement('div');
            const radio = document.createElement('input');
            radio.type = 'radio';
            radio.name = name;
            radio.value = val;
            wrap.appendChild(radio);
            document.body.appendChild(wrap);
        });
    }

    test('일치하는 radio 체크됨', () => {
        createRadioGroup('provCd', ['A', 'B', 'C']);
        smartFillRadio('provCd', 'B');
        const radio = document.querySelector('input[name="provCd"][value="B"]');
        expect(radio.checked).toBe(true);
    });

    test('다른 radio는 체크되지 않음', () => {
        createRadioGroup('provCd', ['A', 'B', 'C']);
        smartFillRadio('provCd', 'A');
        const radioB = document.querySelector('input[name="provCd"][value="B"]');
        expect(radioB.checked).toBe(false);
    });

    test('존재하지 않는 값: 첫 번째 radio 부모에 dbauto-fail 추가', () => {
        createRadioGroup('provCd', ['A', 'B', 'C']);
        smartFillRadio('provCd', 'Z');
        const firstRadio = document.querySelector('input[name="provCd"]');
        expect(firstRadio.parentElement.classList.contains('dbauto-fail')).toBe(true);
    });

    test('radio 그룹이 없으면 에러 없이 무시', () => {
        expect(() => smartFillRadio('nonExistentGroup', 'A')).not.toThrow();
    });

    test('제공구분 매핑 A → radio 체크 (end-to-end 시뮬레이션)', () => {
        createRadioGroup('provCd', ['A', 'B', 'C']);
        const provCdMap = { '제공': 'A', '부가업무': 'B', '거부': 'C' };
        smartFillRadio('provCd', provCdMap['제공']);
        expect(document.querySelector('input[name="provCd"][value="A"]').checked).toBe(true);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// markFail 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('markFail', () => {
    test('존재하는 요소에 dbauto-fail 추가', () => {
        createInput('failField');
        markFail('failField');
        expect(document.getElementById('failField').classList.contains('dbauto-fail')).toBe(true);
    });

    test('존재하지 않는 ID: 에러 없이 무시', () => {
        expect(() => markFail('nonExistent')).not.toThrow();
    });

    test('이미 dbauto-fail이 있어도 중복 추가 없음', () => {
        const el = createInput('failField');
        el.classList.add('dbauto-fail');
        markFail('failField');
        // classList는 중복 클래스를 허용하지 않으므로 contains만 확인
        expect(el.classList.contains('dbauto-fail')).toBe(true);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// 날짜/시간 파싱 로직 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('parseDateTimeVal — 날짜/시간 파싱', () => {
    test('정상 형식: 2024-01-15 09:00~10:00', () => {
        const result = parseDateTimeVal('2024-01-15 09:00~10:00');
        expect(result).not.toBeNull();
        expect(result.date).toBe('2024-01-15');
        expect(result.isDateValid).toBe(true);
        expect(result.startHH).toBe('09');
        expect(result.startMI).toBe('00');
        expect(result.endHH).toBe('10');
        expect(result.endMI).toBe('00');
    });

    test('자정 경계: 00:00~00:30', () => {
        const result = parseDateTimeVal('2024-01-01 00:00~00:30');
        expect(result.startHH).toBe('00');
        expect(result.startMI).toBe('00');
        expect(result.endHH).toBe('00');
        expect(result.endMI).toBe('30');
    });

    test('23:59 경계값', () => {
        const result = parseDateTimeVal('2024-12-31 23:30~23:59');
        expect(result.startHH).toBe('23');
        expect(result.endMI).toBe('59');
    });

    test('날짜 형식이 잘못된 경우 isDateValid=false', () => {
        const result = parseDateTimeVal('20240115 09:00~10:00');
        expect(result.isDateValid).toBe(false);
    });

    test('시간 구분자 ~ 없으면 시간 필드 미파싱', () => {
        const result = parseDateTimeVal('2024-01-15 09:00');
        expect(result).not.toBeNull();
        expect(result.startHH).toBeUndefined();
    });

    test('null 입력 → null 반환', () => {
        expect(parseDateTimeVal(null)).toBeNull();
    });

    test('빈 문자열 → null 반환', () => {
        expect(parseDateTimeVal('')).toBeNull();
    });

    test('날짜만 있고 시간 없음 (공백 없음) → null 반환', () => {
        expect(parseDateTimeVal('2024-01-15')).toBeNull();
    });

    test('앞뒤 공백 trim 처리', () => {
        const result = parseDateTimeVal('  2024-01-15 09:00~10:00  ');
        expect(result.date).toBe('2024-01-15');
    });

    test('숫자로 입력된 날짜 처리 (toString 호출)', () => {
        // dateTime_val이 비문자열로 올 수도 있음
        expect(() => parseDateTimeVal(20240115)).not.toThrow();
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// 매핑 테이블 통합 — content.js handleAutoFill 시뮬레이션
// ─────────────────────────────────────────────────────────────────────────────

describe('매핑 테이블 적용 — handleAutoFill 핵심 로직', () => {
    const provCdMap = { '제공': 'A', '부가업무': 'B', '거부': 'C' };
    const meansMap = { '전화': 'A', '내방': 'B', '방문': 'C' };
    const typeMap = { '아보전': 'A', '연계': 'B', '통합': 'C' };
    const locMap = { '기관내': 'A', '아동가정': 'B', '유관기관': 'C', '기타': 'X' };
    const svcMap = { '사례회의': '060524', '식품지원': '010201' };

    test('제공 → A로 매핑 후 radio 선택', () => {
        const wrap = document.createElement('div');
        const radio = document.createElement('input');
        radio.type = 'radio'; radio.name = 'provCd'; radio.value = 'A';
        wrap.appendChild(radio); document.body.appendChild(wrap);

        const mapped = provCdMap['제공'] || '제공';
        smartFillRadio('provCd', mapped);
        expect(radio.checked).toBe(true);
    });

    test('전화 → A로 매핑 후 select 기입', () => {
        const sel = createSelect('provMeansCd');
        ['A', 'B', 'C'].forEach(v => {
            const opt = document.createElement('option');
            opt.value = v; sel.appendChild(opt);
        });
        const mapped = meansMap['전화'] || '전화';
        smartFill('provMeansCd', mapped);
        expect(sel.value).toBe('A');
    });

    test('알 수 없는 메서드는 원본값 폴백', () => {
        const sel = createSelect('provMeansCd');
        const opt = document.createElement('option');
        opt.value = 'Z'; sel.appendChild(opt);

        const val = '알수없음';
        const mapped = meansMap[val] || val; // undefined → 폴백
        expect(mapped).toBe('알수없음');
    });

    test('사례회의 → 060524 서비스코드 매핑', () => {
        const mapped = svcMap['사례회의'] || '사례회의';
        expect(mapped).toBe('060524');
    });

    test('서비스 코드 미매핑 → 원본값 폴백', () => {
        const mapped = svcMap['존재하지않는서비스'] || '존재하지않는서비스';
        expect(mapped).toBe('존재하지않는서비스');
    });

    test('기타 장소 → X 매핑', () => {
        expect(locMap['기타']).toBe('X');
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// 엣지 케이스 — 극한값 및 비정상 입력
// ─────────────────────────────────────────────────────────────────────────────

describe('엣지 케이스 — 극한 입력값', () => {
    test('매우 긴 텍스트를 textarea에 기입', () => {
        createTextarea('svcProvDesc');
        const longText = 'A'.repeat(10000);
        smartFill('svcProvDesc', longText, false, true);
        expect(document.getElementById('svcProvDesc').value).toBe(longText);
        expect(document.getElementById('svcProvDesc').classList.contains('dbauto-success')).toBe(true);
    });

    test('숫자 0은 빈 값이 아니므로 성공 처리', () => {
        createInput('svcProvCnt');
        smartFill('svcProvCnt', 0); // 0은 falsy지만 undefined/null/'' 아님
        // content.js에서 hasValue = value !== undefined && value !== null && value !== ''
        // 0은 !== '' → hasValue = true
        const el = document.getElementById('svcProvCnt');
        expect(el.classList.contains('dbauto-success')).toBe(true);
    });

    test('특수문자 포함 텍스트 기입', () => {
        createInput('testField');
        smartFill('testField', '<script>alert(1)</script>');
        // value는 그대로, DOM XSS 없음 (input.value는 텍스트)
        expect(document.getElementById('testField').value).toBe('<script>alert(1)</script>');
    });

    test('parseDateTimeVal: 미래 날짜 2099-12-31', () => {
        const result = parseDateTimeVal('2099-12-31 23:59~23:59');
        expect(result.isDateValid).toBe(true);
        expect(result.date).toBe('2099-12-31');
    });

    test('parseDateTimeVal: 윤년 2024-02-29', () => {
        const result = parseDateTimeVal('2024-02-29 09:00~10:00');
        expect(result.isDateValid).toBe(true);
    });
});
