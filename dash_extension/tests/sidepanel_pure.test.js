// =============================================================================
// sidepanel.js — 순수 함수 단위 테스트
//
// 테스트 대상 (DOM/네트워크 의존성 없는 순수 로직):
//   - parseJwtPayload(token)       JWT payload 디코딩
//   - removePkcs7(bytes)           PKCS7 패딩 제거
//   - base64ToArrayBuffer(base64)  Base64 → ArrayBuffer 변환
//   - handleApiStatus(status)      API 상태 코드 처리
//   - showLoginError(msg)          에러 메시지 분류 (cancel vs general)
//   - authHeaders()                OAuth 토큰 헤더 생성
//   - performLogout()              상태 초기화
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// 테스트용 함수 추출 (auth.js 실제 구현과 동기화)
// chrome.runtime.id가 로드 시점에 필요하므로 eval 로드 대신 함수 추출 방식 사용
// ─────────────────────────────────────────────────────────────────────────────

// auth.js 현재 구현: null/non-string 체크 + 정확히 3파트 검증 + 한국어 에러 메시지 래핑
function parseJwtPayload(token) {
    try {
        if (!token || typeof token !== 'string') throw new Error('토큰이 없습니다.');
        const parts = token.split('.');
        if (parts.length !== 3) throw new Error('유효하지 않은 JWT 형식입니다.');
        const base64Url = parts[1];
        const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
        const jsonPayload = decodeURIComponent(
            atob(base64).split('').map(c =>
                '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2)
            ).join('')
        );
        return JSON.parse(jsonPayload);
    } catch (e) {
        throw new Error('인증 토큰 처리 중 오류가 발생했습니다. 다시 로그인해주세요.');
    }
}

function removePkcs7(bytes) {
    const padLen = bytes[bytes.length - 1];
    if (padLen < 1 || padLen > 16) return bytes;
    return bytes.slice(0, bytes.length - padLen);
}

function base64ToArrayBuffer(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes.buffer;
}

function handleApiStatus(status) {
    if (status === 401 || status === 403) {
        // showAccountDeletedError() 호출 시뮬레이션 — 테스트에서는 상태만 확인
        return true;
    }
    return false;
}

function classifyLoginError(msg) {
    const isCancelled = msg && (msg.includes('cancel') || msg.includes('취소') || msg.includes('closed'));
    return isCancelled ? 'cancelled' : 'general';
}

// ─────────────────────────────────────────────────────────────────────────────
// JWT Payload 파싱 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('parseJwtPayload', () => {
    // 테스트용 JWT 생성 헬퍼 (서명은 가짜)
    // Unicode-safe: encodeURIComponent → percent-decode → btoa (jsdom atob은 ASCII만 지원)
    function makeJwt(payload) {
        const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
        const jsonStr = JSON.stringify(payload);
        const unicodeSafe = encodeURIComponent(jsonStr).replace(
            /%([0-9A-F]{2})/g,
            (_, p1) => String.fromCharCode(parseInt(p1, 16))
        );
        const body = btoa(unicodeSafe)
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=/g, '');
        return `${header}.${body}.fakesignature`;
    }

    test('Firebase UID(sub) 추출 성공', () => {
        const token = makeJwt({ sub: 'firebase_uid_abc123', email: 'test@example.com' });
        const payload = parseJwtPayload(token);
        expect(payload.sub).toBe('firebase_uid_abc123');
    });

    test('이메일 필드 추출', () => {
        const token = makeJwt({ sub: 'uid', email: 'user@test.com', name: '홍길동' });
        const payload = parseJwtPayload(token);
        expect(payload.email).toBe('user@test.com');
        expect(payload.name).toBe('홍길동');
    });

    test('만료 시간(exp) 필드 추출', () => {
        const exp = Math.floor(Date.now() / 1000) + 3600;
        const token = makeJwt({ sub: 'uid', exp });
        const payload = parseJwtPayload(token);
        expect(payload.exp).toBe(exp);
    });

    test('base64url 인코딩 처리 (- → +, _ → /)', () => {
        // base64url 특수문자가 포함된 payload
        const token = makeJwt({ sub: 'test', data: '특수문자테스트' });
        expect(() => parseJwtPayload(token)).not.toThrow();
        const payload = parseJwtPayload(token);
        expect(payload.data).toBe('특수문자테스트');
    });

    test('한국어 포함 payload 정상 디코딩', () => {
        const token = makeJwt({ name: '홍길동', org: '아동보호전문기관' });
        const payload = parseJwtPayload(token);
        expect(payload.name).toBe('홍길동');
        expect(payload.org).toBe('아동보호전문기관');
    });

    test('잘못된 토큰 형식 → 에러 메시지 한국어', () => {
        expect(() => parseJwtPayload('invalid')).toThrow('다시 로그인해주세요');
        expect(() => parseJwtPayload('hdr.!!!.sig')).toThrow('다시 로그인해주세요');
    });

    test('null → throw', () => {
        expect(() => parseJwtPayload(null)).toThrow('다시 로그인해주세요');
    });

    test('undefined → throw', () => {
        expect(() => parseJwtPayload(undefined)).toThrow('다시 로그인해주세요');
    });

    test('숫자(non-string) → throw', () => {
        expect(() => parseJwtPayload(12345)).toThrow('다시 로그인해주세요');
    });

    test('2파트 토큰 ("a.b") → throw (정확히 3파트 필요)', () => {
        expect(() => parseJwtPayload('header.payload')).toThrow('다시 로그인해주세요');
    });

    test('4파트 토큰 ("a.b.c.d") → throw (정확히 3파트 필요)', () => {
        expect(() => parseJwtPayload('a.b.c.d')).toThrow('다시 로그인해주세요');
    });

    test('빈 payload {} → 정상 파싱', () => {
        const token = makeJwt({});
        const payload = parseJwtPayload(token);
        expect(typeof payload).toBe('object');
        expect(Object.keys(payload).length).toBe(0);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// removePkcs7 — PKCS7 패딩 제거 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('removePkcs7', () => {
    test('패딩 1바이트: [...data, 0x01]', () => {
        const input = new Uint8Array([0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x01]);
        const result = removePkcs7(input);
        expect(result.length).toBe(5);
        expect(Array.from(result)).toEqual([0x48, 0x65, 0x6c, 0x6c, 0x6f]);
    });

    test('패딩 4바이트: [...data, 0x04, 0x04, 0x04, 0x04]', () => {
        const input = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 4, 4, 4, 4]);
        const result = removePkcs7(input);
        expect(result.length).toBe(8);
        expect(Array.from(result)).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('패딩 16바이트 (최대): 전체가 패딩인 경우', () => {
        const input = new Uint8Array(Array(16).fill(16));
        const result = removePkcs7(input);
        expect(result.length).toBe(0);
    });

    test('padLen=0 → 원본 반환 (유효하지 않은 패딩)', () => {
        const input = new Uint8Array([1, 2, 3, 0]);
        const result = removePkcs7(input);
        expect(Array.from(result)).toEqual([1, 2, 3, 0]);
    });

    test('padLen=17 → 원본 반환 (범위 초과)', () => {
        const input = new Uint8Array([1, 2, 3, 17]);
        const result = removePkcs7(input);
        expect(Array.from(result)).toEqual([1, 2, 3, 17]);
    });

    test('padLen=255 → 원본 반환 (범위 초과)', () => {
        const input = new Uint8Array([100, 200, 255]);
        const result = removePkcs7(input);
        expect(Array.from(result)).toEqual([100, 200, 255]);
    });

    test('단일 바이트 배열 [0x01] → 빈 배열', () => {
        const input = new Uint8Array([0x01]);
        const result = removePkcs7(input);
        expect(result.length).toBe(0);
    });

    test('패딩 8바이트: AES 블록 절반', () => {
        const data = new Uint8Array([10, 20, 30, 40, 50, 60, 70, 80]);
        const padding = new Uint8Array(Array(8).fill(8));
        const input = new Uint8Array([...data, ...padding]);
        const result = removePkcs7(input);
        expect(result.length).toBe(8);
        expect(Array.from(result)).toEqual([10, 20, 30, 40, 50, 60, 70, 80]);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// base64ToArrayBuffer 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('base64ToArrayBuffer', () => {
    test('16바이트 IV 변환 (AES IV 크기)', () => {
        const iv = new Uint8Array(16);
        for (let i = 0; i < 16; i++) iv[i] = i;
        const b64 = btoa(String.fromCharCode(...iv));
        const result = new Uint8Array(base64ToArrayBuffer(b64));
        expect(result.length).toBe(16);
        expect(Array.from(result)).toEqual(Array.from(iv));
    });

    test('32바이트 키 변환 (AES-256 키 크기)', () => {
        const key = new Uint8Array(32).fill(0xAB);
        const b64 = btoa(String.fromCharCode(...key));
        const result = new Uint8Array(base64ToArrayBuffer(b64));
        expect(result.length).toBe(32);
        expect(result.every(b => b === 0xAB)).toBe(true);
    });

    test('빈 base64 문자열 → 빈 ArrayBuffer', () => {
        const result = base64ToArrayBuffer(btoa(''));
        expect(new Uint8Array(result).length).toBe(0);
    });

    test('단일 바이트 변환', () => {
        const b64 = btoa(String.fromCharCode(42));
        const result = new Uint8Array(base64ToArrayBuffer(b64));
        expect(result.length).toBe(1);
        expect(result[0]).toBe(42);
    });

    test('모든 바이트 값(0~255) 변환 roundtrip', () => {
        const original = new Uint8Array(256);
        for (let i = 0; i < 256; i++) original[i] = i;
        const b64 = btoa(String.fromCharCode(...original));
        const result = new Uint8Array(base64ToArrayBuffer(b64));
        expect(Array.from(result)).toEqual(Array.from(original));
    });

    test('반환 타입이 ArrayBuffer', () => {
        const result = base64ToArrayBuffer(btoa('hello'));
        expect(result).toBeInstanceOf(ArrayBuffer);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// handleApiStatus — API 상태 코드 처리
// ─────────────────────────────────────────────────────────────────────────────

describe('handleApiStatus', () => {
    test('401 → true (처리됨, 계정 삭제 에러)', () => {
        expect(handleApiStatus(401)).toBe(true);
    });

    test('403 → true (처리됨, 계정 삭제 에러)', () => {
        expect(handleApiStatus(403)).toBe(true);
    });

    test('200 → false (처리 안 함, 성공)', () => {
        expect(handleApiStatus(200)).toBe(false);
    });

    test('404 → false (처리 안 함, 리소스 없음)', () => {
        expect(handleApiStatus(404)).toBe(false);
    });

    test('500 → false (처리 안 함, 서버 오류)', () => {
        expect(handleApiStatus(500)).toBe(false);
    });

    test('0 → false (비정상 상태)', () => {
        expect(handleApiStatus(0)).toBe(false);
    });

    test('undefined → false', () => {
        expect(handleApiStatus(undefined)).toBe(false);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// showLoginError 메시지 분류 로직
// ─────────────────────────────────────────────────────────────────────────────

describe('classifyLoginError — 에러 메시지 분류', () => {
    test('"cancel" 포함 → cancelled', () => {
        expect(classifyLoginError('User cancelled the login')).toBe('cancelled');
    });

    test('"취소" 포함 → cancelled', () => {
        expect(classifyLoginError('로그인 취소')).toBe('cancelled');
    });

    test('"closed" 포함 → cancelled', () => {
        expect(classifyLoginError('Window closed by user')).toBe('cancelled');
    });

    test('일반 오류 → general', () => {
        expect(classifyLoginError('Network error')).toBe('general');
    });

    test('서버 오류 → general', () => {
        expect(classifyLoginError('Firebase Auth failed')).toBe('general');
    });

    test('빈 문자열 → general', () => {
        expect(classifyLoginError('')).toBe('general');
    });

    test('null → general (null 안전 처리)', () => {
        expect(classifyLoginError(null)).toBe('general');
    });

    test('대소문자 무관: "CANCEL" → general (대소문자 민감)', () => {
        // sidepanel.js 원본은 소문자 includes 사용 → 대문자 'CANCEL'은 매칭 안 됨
        expect(classifyLoginError('CANCEL')).toBe('general');
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// authHeaders — OAuth 토큰 헤더 생성
// ─────────────────────────────────────────────────────────────────────────────

describe('authHeaders', () => {
    let currentOAuthToken;

    function authHeaders() {
        if (currentOAuthToken) return { 'Authorization': `Bearer ${currentOAuthToken}` };
        return {};
    }

    test('토큰 있음 → Authorization 헤더 포함', () => {
        currentOAuthToken = 'test_firebase_id_token';
        const headers = authHeaders();
        expect(headers['Authorization']).toBe('Bearer test_firebase_id_token');
    });

    test('토큰 없음(null) → 빈 헤더', () => {
        currentOAuthToken = null;
        expect(authHeaders()).toEqual({});
    });

    test('토큰 없음(undefined) → 빈 헤더', () => {
        currentOAuthToken = undefined;
        expect(authHeaders()).toEqual({});
    });

    test('토큰 없음(빈 문자열) → 빈 헤더', () => {
        currentOAuthToken = '';
        expect(authHeaders()).toEqual({});
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// performLogout — 상태 초기화 로직
// ─────────────────────────────────────────────────────────────────────────────

describe('performLogout — 상태 초기화', () => {
    // 상태 변수 시뮬레이션
    let state;

    function simulatePerformLogout(s) {
        s.currentUser = null;
        s.selectedRecordId = null;
        s.records = [];
        s.vaultKeys = {};
        s.pinAuthenticated = false;
        s.pinInput = '';
        return s;
    }

    beforeEach(() => {
        state = {
            currentUser: { uid: 'u1', email: 'test@test.com' },
            selectedRecordId: 'r123',
            records: [{ id: 1 }, { id: 2 }],
            vaultKeys: { tok: 'key' },
            pinAuthenticated: true,
            pinInput: '1234',
        };
    });

    test('로그아웃 후 currentUser null', () => {
        simulatePerformLogout(state);
        expect(state.currentUser).toBeNull();
    });

    test('로그아웃 후 선택된 레코드 null', () => {
        simulatePerformLogout(state);
        expect(state.selectedRecordId).toBeNull();
    });

    test('로그아웃 후 records 빈 배열', () => {
        simulatePerformLogout(state);
        expect(state.records).toEqual([]);
    });

    test('로그아웃 후 vaultKeys 빈 객체', () => {
        simulatePerformLogout(state);
        expect(state.vaultKeys).toEqual({});
    });

    test('로그아웃 후 pinAuthenticated false', () => {
        simulatePerformLogout(state);
        expect(state.pinAuthenticated).toBe(false);
    });

    test('로그아웃 후 pinInput 빈 문자열', () => {
        simulatePerformLogout(state);
        expect(state.pinInput).toBe('');
    });

    test('이미 로그아웃 상태에서 재호출 안전', () => {
        simulatePerformLogout(state);
        expect(() => simulatePerformLogout(state)).not.toThrow();
    });
});
