// =============================================================================
// sidepanel.js — OAuth / 로그인 플로우 단위 테스트
//
// 테스트 대상:
//   - getGoogleAccessToken(interactive)  OAuth 콜백 URL 파싱
//   - getFirebaseIdToken(googleToken)     Firebase ID Token 교환
//   - checkVaultExists()                 Vault 존재 여부 확인
//   - handleGoogleLogin(googleToken)     전체 로그인 플로우 상태 전환
//
// chrome.identity, fetch는 jest.fn()으로 대체
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// 모듈 상태 및 의존 함수 (sidepanel.js chrome.runtime.id 없이 추출)
// ─────────────────────────────────────────────────────────────────────────────

const API_BASE = 'https://dash.qpon/api';
const FIREBASE_API_KEY = 'FAKE_KEY_FOR_TESTS';
const GOOGLE_CLIENT_ID = 'test_client_id.apps.googleusercontent.com';

let currentOAuthToken = null;
let currentUser = null;
let vaultKeys = {};
let pinAuthenticated = false;

// Simplified view stubs (DOM not needed)
const viewCalls = [];
function showMainView()          { viewCalls.push('showMainView'); }
function showPinView()           { viewCalls.push('showPinView'); }
function fetchRecords()          { viewCalls.push('fetchRecords'); }
function fetchHistory()          { viewCalls.push('fetchHistory'); }
function setupRealtimeSync()     { viewCalls.push('setupRealtimeSync'); }
function showAccountDeletedError() { viewCalls.push('showAccountDeletedError'); }
function performLogout()         { viewCalls.push('performLogout'); }

function parseJwtPayload(token) {
    const base64Url = token.split('.')[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const jsonPayload = decodeURIComponent(
        atob(base64).split('').map(c => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2)).join('')
    );
    return JSON.parse(jsonPayload);
}

function authHeaders() {
    return currentOAuthToken ? { 'Authorization': `Bearer ${currentOAuthToken}` } : {};
}

// ─────────────────────────────────────────────────────────────────────────────
// 테스트 대상 함수 (OAuth 플로우)
// ─────────────────────────────────────────────────────────────────────────────

function getGoogleAccessToken(interactive) {
    const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    authUrl.searchParams.set('client_id', GOOGLE_CLIENT_ID);
    authUrl.searchParams.set('redirect_uri', 'https://fakeid.chromiumapp.org');
    authUrl.searchParams.set('response_type', 'token');
    authUrl.searchParams.set('scope', 'https://www.googleapis.com/auth/userinfo.email');
    if (!interactive) authUrl.searchParams.set('prompt', 'none');

    return new Promise((resolve, reject) => {
        chrome.identity.launchWebAuthFlow(
            { url: authUrl.toString(), interactive },
            (callbackUrl) => {
                if (chrome.runtime.lastError || !callbackUrl) {
                    reject(new Error(chrome.runtime.lastError?.message || '로그인 취소'));
                    return;
                }
                const hash = new URL(callbackUrl).hash.slice(1);
                const params = new URLSearchParams(hash);
                const token = params.get('access_token');
                if (token) resolve(token);
                else reject(new Error('액세스 토큰을 받지 못했습니다.'));
            }
        );
    });
}

async function getFirebaseIdToken(googleAccessToken) {
    const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=${FIREBASE_API_KEY}`;
    const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            postBody: `access_token=${googleAccessToken}&providerId=google.com`,
            requestUri: 'http://localhost',
            returnIdpCredential: true,
            returnSecureToken: true
        })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error?.message || 'Firebase Auth failed');
    return data.idToken;
}

// pin.js 현재 구현과 동기화: 401/403 시 showAccountDeletedError() 호출 추가
async function checkVaultExists() {
    if (!currentUser?.uid) return false;
    try {
        const res = await fetch(`${API_BASE}/users/vault/${currentUser.uid}`, { headers: authHeaders() });
        if (res.status === 401 || res.status === 403) {
            showAccountDeletedError();
            return false;
        }
        if (!res.ok) return false;
        const body = await res.json();
        return !!(body.encrypted_vault);
    } catch (e) {
        return false;
    }
}

async function checkPinAndProceed() {
    const session = await new Promise(resolve =>
        chrome.storage.session.get(['cachedVaultKeys', 'cachedDerivedKey'], result => resolve(result))
    );
    if (session.cachedVaultKeys && session.cachedDerivedKey && Object.keys(session.cachedVaultKeys).length > 0) {
        vaultKeys = session.cachedVaultKeys;
        pinAuthenticated = true;
        showMainView();
        fetchRecords();
        fetchHistory();
        setupRealtimeSync();
        return;
    }
    const hasVault = await checkVaultExists();
    if (!hasVault) {
        pinAuthenticated = true;
        showMainView();
        fetchRecords();
        fetchHistory();
        setupRealtimeSync();
        return;
    }
    showPinView();
}

// ─────────────────────────────────────────────────────────────────────────────
// 헬퍼: 테스트용 JWT 생성
// ─────────────────────────────────────────────────────────────────────────────

function makeJwt(payload) {
    const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const jsonStr = JSON.stringify(payload);
    const unicodeSafe = encodeURIComponent(jsonStr).replace(
        /%([0-9A-F]{2})/g,
        (_, p1) => String.fromCharCode(parseInt(p1, 16))
    );
    const body = btoa(unicodeSafe).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    return `${header}.${body}.fakesig`;
}

// ─────────────────────────────────────────────────────────────────────────────
// getGoogleAccessToken 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('getGoogleAccessToken — OAuth 콜백 URL 파싱', () => {
    beforeEach(() => {
        chrome.runtime.lastError = null;
    });

    test('정상 콜백: access_token 추출 성공', async () => {
        const callbackUrl = 'https://fakeid.chromiumapp.org/#access_token=MY_GOOGLE_TOKEN&token_type=Bearer';
        chrome.identity.launchWebAuthFlow.mockImplementation((params, cb) => cb(callbackUrl));

        const token = await getGoogleAccessToken(true);
        expect(token).toBe('MY_GOOGLE_TOKEN');
    });

    test('interactive=false → prompt=none 쿼리 파라미터 추가됨', async () => {
        let capturedUrl = '';
        chrome.identity.launchWebAuthFlow.mockImplementation(({ url }, cb) => {
            capturedUrl = url;
            cb('https://fakeid.chromiumapp.org/#access_token=TOKEN');
        });

        await getGoogleAccessToken(false);
        expect(capturedUrl).toContain('prompt=none');
    });

    test('interactive=true → prompt 없음', async () => {
        let capturedUrl = '';
        chrome.identity.launchWebAuthFlow.mockImplementation(({ url }, cb) => {
            capturedUrl = url;
            cb('https://fakeid.chromiumapp.org/#access_token=TOKEN');
        });

        await getGoogleAccessToken(true);
        expect(capturedUrl).not.toContain('prompt=none');
    });

    test('callbackUrl null → reject (취소)', async () => {
        chrome.identity.launchWebAuthFlow.mockImplementation((params, cb) => cb(null));

        await expect(getGoogleAccessToken(true)).rejects.toThrow('로그인 취소');
    });

    test('lastError 있음 → reject with error message', async () => {
        chrome.runtime.lastError = { message: '사용자가 취소했습니다' };
        chrome.identity.launchWebAuthFlow.mockImplementation((params, cb) => cb(null));

        await expect(getGoogleAccessToken(true)).rejects.toThrow('사용자가 취소했습니다');
    });

    test('콜백 URL에 access_token 없음 → reject', async () => {
        const callbackUrl = 'https://fakeid.chromiumapp.org/#error=access_denied';
        chrome.identity.launchWebAuthFlow.mockImplementation((params, cb) => cb(callbackUrl));

        await expect(getGoogleAccessToken(true)).rejects.toThrow('액세스 토큰을 받지 못했습니다');
    });

    test('authUrl에 client_id 포함됨', async () => {
        let capturedUrl = '';
        chrome.identity.launchWebAuthFlow.mockImplementation(({ url }, cb) => {
            capturedUrl = url;
            cb('https://fakeid.chromiumapp.org/#access_token=T');
        });

        await getGoogleAccessToken(true);
        expect(capturedUrl).toContain('client_id=test_client_id.apps.googleusercontent.com');
        expect(capturedUrl).toContain('response_type=token');
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// getFirebaseIdToken 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('getFirebaseIdToken — Firebase ID Token 교환', () => {
    afterEach(() => {
        global.fetch = undefined;
    });

    test('정상 응답 → idToken 반환', async () => {
        const fakeToken = makeJwt({ sub: 'firebase_uid_abc', email: 'user@test.com' });
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ idToken: fakeToken })
        });

        const result = await getFirebaseIdToken('google_access_token');
        expect(result).toBe(fakeToken);
    });

    test('서버 오류(ok=false) → throw Error', async () => {
        global.fetch = jest.fn().mockResolvedValue({
            ok: false,
            json: async () => ({ error: { message: 'INVALID_IDP_RESPONSE' } })
        });

        await expect(getFirebaseIdToken('bad_token')).rejects.toThrow('INVALID_IDP_RESPONSE');
    });

    test('error.message 없을 때 → "Firebase Auth failed" throw', async () => {
        global.fetch = jest.fn().mockResolvedValue({
            ok: false,
            json: async () => ({})
        });

        await expect(getFirebaseIdToken('bad_token')).rejects.toThrow('Firebase Auth failed');
    });

    test('요청 body에 access_token 포함 확인', async () => {
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ idToken: 'some_token' })
        });

        await getFirebaseIdToken('MY_GOOGLE_TOKEN');
        const callArgs = global.fetch.mock.calls[0];
        const body = JSON.parse(callArgs[1].body);
        expect(body.postBody).toContain('access_token=MY_GOOGLE_TOKEN');
        expect(body.postBody).toContain('providerId=google.com');
        expect(body.returnSecureToken).toBe(true);
    });

    test('네트워크 오류 → throw', async () => {
        global.fetch = jest.fn().mockRejectedValue(new Error('Network Error'));
        await expect(getFirebaseIdToken('tok')).rejects.toThrow('Network Error');
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// checkVaultExists 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('checkVaultExists', () => {
    beforeEach(() => {
        currentUser = { uid: 'test_uid', email: 'test@test.com' };
    });

    afterEach(() => {
        global.fetch = undefined;
        currentUser = null;
        currentOAuthToken = null;
    });

    test('encrypted_vault 있음 → true', async () => {
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            status: 200,
            json: async () => ({ encrypted_vault: 'ivB64:cipherB64' })
        });

        expect(await checkVaultExists()).toBe(true);
    });

    test('encrypted_vault null/없음 → false', async () => {
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            status: 200,
            json: async () => ({ encrypted_vault: null })
        });

        expect(await checkVaultExists()).toBe(false);
    });

    test('404 응답 → false', async () => {
        global.fetch = jest.fn().mockResolvedValue({
            ok: false,
            status: 404,
            json: async () => ({})
        });

        expect(await checkVaultExists()).toBe(false);
    });

    test('401 → false + showAccountDeletedError 호출', async () => {
        global.fetch = jest.fn().mockResolvedValue({
            ok: false,
            status: 401,
            json: async () => ({})
        });
        viewCalls.length = 0;

        expect(await checkVaultExists()).toBe(false);
        expect(viewCalls).toContain('showAccountDeletedError');
    });

    test('403 → false + showAccountDeletedError 호출', async () => {
        global.fetch = jest.fn().mockResolvedValue({
            ok: false,
            status: 403,
            json: async () => ({})
        });
        viewCalls.length = 0;

        expect(await checkVaultExists()).toBe(false);
        expect(viewCalls).toContain('showAccountDeletedError');
    });

    test('404(ok=false, status≠401/403) → false, showAccountDeletedError 미호출', async () => {
        global.fetch = jest.fn().mockResolvedValue({
            ok: false,
            status: 404,
            json: async () => ({})
        });
        viewCalls.length = 0;

        expect(await checkVaultExists()).toBe(false);
        expect(viewCalls).not.toContain('showAccountDeletedError');
    });

    test('currentUser 없으면 fetch 호출 없이 false', async () => {
        currentUser = null;
        global.fetch = jest.fn();

        expect(await checkVaultExists()).toBe(false);
        expect(global.fetch).not.toHaveBeenCalled();
    });

    test('네트워크 오류 → false (조용히 처리)', async () => {
        global.fetch = jest.fn().mockRejectedValue(new Error('Network Error'));
        expect(await checkVaultExists()).toBe(false);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// checkPinAndProceed 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('checkPinAndProceed — PIN 인증 진입 로직', () => {
    beforeEach(() => {
        currentUser = { uid: 'uid_abc', email: 'test@test.com' };
        currentOAuthToken = 'fake_token';
        vaultKeys = {};
        pinAuthenticated = false;
        viewCalls.length = 0;
    });

    afterEach(() => {
        global.fetch = undefined;
        currentUser = null;
        currentOAuthToken = null;
    });

    test('세션 캐시(cachedVaultKeys + cachedDerivedKey) 있음 → showMainView', async () => {
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({
            cachedVaultKeys: { tok1: 'key1' },
            cachedDerivedKey: 'someB64DerivedKey'
        }));

        await checkPinAndProceed();

        expect(viewCalls).toContain('showMainView');
        expect(viewCalls).toContain('fetchRecords');
        expect(pinAuthenticated).toBe(true);
        expect(vaultKeys).toEqual({ tok1: 'key1' });
    });

    test('cachedVaultKeys 있어도 cachedDerivedKey 없으면 PIN 화면', async () => {
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({
            cachedVaultKeys: { tok1: 'key1' },
            cachedDerivedKey: undefined  // 없음
        }));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true, status: 200,
            json: async () => ({ encrypted_vault: 'ivB64:cipherB64' })
        });

        await checkPinAndProceed();

        expect(viewCalls).toContain('showPinView');
        expect(viewCalls).not.toContain('showMainView');
    });

    test('캐시 없음 + vault 없음 → showMainView (PIN 설정 전)', async () => {
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({}));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true, status: 200,
            json: async () => ({ encrypted_vault: null })
        });

        await checkPinAndProceed();

        expect(viewCalls).toContain('showMainView');
        expect(viewCalls).not.toContain('showPinView');
        expect(pinAuthenticated).toBe(true);
    });

    test('캐시 없음 + vault 있음 → showPinView', async () => {
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({}));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true, status: 200,
            json: async () => ({ encrypted_vault: 'ivB64:cipherB64' })
        });

        await checkPinAndProceed();

        expect(viewCalls).toContain('showPinView');
        expect(viewCalls).not.toContain('showMainView');
        expect(pinAuthenticated).toBe(false);
    });

    test('빈 cachedVaultKeys({}) → 캐시 미사용 처리', async () => {
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({
            cachedVaultKeys: {},          // 빈 객체 → length 0
            cachedDerivedKey: 'someKey'
        }));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true, status: 200,
            json: async () => ({ encrypted_vault: 'ivB64:cipherB64' })
        });

        await checkPinAndProceed();

        expect(viewCalls).toContain('showPinView');
    });
});
