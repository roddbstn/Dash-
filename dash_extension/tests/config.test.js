// =============================================================================
// config.js 단위 테스트 — 매핑 테이블 및 설정 정확성 검증
// =============================================================================

// config.js 로드 전에 window.DBAuto 초기화
beforeEach(() => {
    window.DBAuto = undefined;
    // config.js는 window.DBAuto를 사용하므로 직접 로드하지 않고
    // 테스트 파일에서 동일한 Config 구조를 검증합니다.
    // 실제 로드는 fs.readFileSync + eval 또는 import 방식 사용
    const fs = require('fs');
    const path = require('path');
    const code = fs.readFileSync(
        path.join(__dirname, '../extension/core/config.js'), 'utf8'
    );
    // eslint-disable-next-line no-eval
    eval(code);
});

describe('DBAuto.Config — 초기화', () => {
    test('window.DBAuto.Config이 정의되어 있음', () => {
        expect(window.DBAuto).toBeDefined();
        expect(window.DBAuto.Config).toBeDefined();
    });

    test('Config이 Object.freeze로 불변 처리됨', () => {
        const cfg = window.DBAuto.Config;
        expect(Object.isFrozen(cfg)).toBe(true);
    });

    test('FIELD_IDS가 존재함', () => {
        expect(window.DBAuto.Config.FIELD_IDS).toBeDefined();
    });
});

describe('DBAuto.Config — TARGET_URLS', () => {
    let cfg;
    beforeEach(() => { cfg = window.DBAuto.Config; });

    test('ncads.go.kr 패턴 포함', () => {
        expect(cfg.TARGET_URLS).toContain('*://ncads.go.kr/*');
    });

    test('wildcard 서브도메인 패턴 포함 (*.ncads.go.kr)', () => {
        expect(cfg.TARGET_URLS).toContain('*://*.ncads.go.kr/*');
    });

    test('TARGET_URLS 배열 형식 (glob 패턴)', () => {
        cfg.TARGET_URLS.forEach(url => {
            expect(url).toMatch(/^\*:\/\//);
        });
    });

    test('EXCLUDED_KEYWORDS에 AnySignPlus 포함', () => {
        expect(cfg.EXCLUDED_KEYWORDS).toContain('AnySignPlus');
    });
});

describe('DBAuto.Config — FIELD_IDS', () => {
    let FIELD_IDS;
    beforeEach(() => { FIELD_IDS = window.DBAuto.Config.FIELD_IDS; });

    const requiredFields = [
        'SERVICE_DETAIL',
        'RECIPIENT_TYPE',
        'RECIPIENT_ID',
        'LOCATION',
        'LOCATION_ETC',
        'PIC',
        'MEANS',
        'TYPE',
        'PROV_COUNT',
        'START_DATE',
        'END_DATE',
        'START_HH',
        'START_MI',
        'END_HH',
        'END_MI',
        'MOVE_TIME',
        'DESC',
        'OPINION',
    ];

    test.each(requiredFields)('FIELD_IDS.%s가 존재함', (field) => {
        expect(FIELD_IDS[field]).toBeDefined();
        expect(typeof FIELD_IDS[field]).toBe('string');
        expect(FIELD_IDS[field].length).toBeGreaterThan(0);
    });

    test('FIELD_IDS 값은 모두 문자열', () => {
        Object.values(FIELD_IDS).forEach(val => {
            expect(typeof val).toBe('string');
        });
    });

    test('FIELD_IDS 값에 중복 없음 (DOM ID 충돌 방지)', () => {
        const values = Object.values(FIELD_IDS);
        const unique = new Set(values);
        expect(unique.size).toBe(values.length);
    });
});

describe('DBAuto.Config — PROV_CD_MAP (제공구분)', () => {
    let map;
    beforeEach(() => { map = window.DBAuto.Config.PROV_CD_MAP; });

    test('제공 → A', () => { expect(map['제공']).toBe('A'); });
    test('부가업무 → B', () => { expect(map['부가업무']).toBe('B'); });
    test('거부 → C', () => { expect(map['거부']).toBe('C'); });

    test('모든 값이 대문자 알파벳 단일 문자', () => {
        Object.values(map).forEach(v => {
            expect(v).toMatch(/^[A-Z]$/);
        });
    });

    test('엣지: 존재하지 않는 키는 undefined', () => {
        expect(map['없는값']).toBeUndefined();
    });
});

describe('DBAuto.Config — MEANS_MAP (서비스제공방법)', () => {
    let map;
    beforeEach(() => { map = window.DBAuto.Config.MEANS_MAP; });

    test('전화 → A', () => { expect(map['전화']).toBe('A'); });
    test('내방 → B', () => { expect(map['내방']).toBe('B'); });
    test('방문 → C', () => { expect(map['방문']).toBe('C'); });
    test('총 3개 항목', () => { expect(Object.keys(map).length).toBe(3); });
});

describe('DBAuto.Config — TYPE_MAP (서비스제공유형)', () => {
    let map;
    beforeEach(() => { map = window.DBAuto.Config.TYPE_MAP; });

    test('아보전 → A', () => { expect(map['아보전']).toBe('A'); });
    test('연계 → B', () => { expect(map['연계']).toBe('B'); });
    test('통합 → C', () => { expect(map['통합']).toBe('C'); });
});

describe('DBAuto.Config — LOCATION_MAP (제공장소)', () => {
    let map;
    beforeEach(() => { map = window.DBAuto.Config.LOCATION_MAP; });

    test('기관내 → A', () => { expect(map['기관내']).toBe('A'); });
    test('아동가정 → B', () => { expect(map['아동가정']).toBe('B'); });
    test('유관기관 → C', () => { expect(map['유관기관']).toBe('C'); });
    test('기타 → X', () => { expect(map['기타']).toBe('X'); });
    test('총 4개 항목', () => { expect(Object.keys(map).length).toBe(4); });
});

describe('DBAuto.Config — SERVICE_MAP (서비스코드)', () => {
    let map;
    beforeEach(() => { map = window.DBAuto.Config.SERVICE_MAP; });

    test('사례회의 → 060524', () => {
        expect(map['사례회의']).toBe('060524');
    });

    test('식품지원 → 010201', () => {
        expect(map['식품지원']).toBe('010201');
    });

    test('아동 안전점검 및 상담 → 060501', () => {
        expect(map['아동 안전점검 및 상담']).toBe('060501');
    });

    test('아동 양육기술 상담/교육 → 060501 (별칭)', () => {
        expect(map['아동 양육기술 상담/교육']).toBe('060501');
    });

    test('의류지원 간소화명 → 010509', () => {
        expect(map['의류지원']).toBe('010509');
    });

    test('모든 코드값은 6자리 숫자 문자열', () => {
        Object.values(map).forEach(code => {
            expect(code).toMatch(/^\d{6}$/);
        });
    });

    test('존재하지 않는 서비스는 undefined', () => {
        expect(map['없는서비스']).toBeUndefined();
    });

    test('안전교육 코드 정확성', () => {
        expect(map['안전교육']).toBe('060104');
    });

    test('학대예방교육 코드 정확성', () => {
        expect(map['학대예방교육']).toBe('060102');
    });

    test('성폭력(예방)교육 코드 정확성', () => {
        expect(map['성폭력(예방)교육']).toBe('060103');
    });
});
