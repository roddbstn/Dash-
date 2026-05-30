/**
 * @jest-environment node
 *
 * sidepanel.js — 상태 관리 / SSE / Vault 캐시 단위 테스트
 *
 * 테스트 대상:
 *   - getShareKeyForToken(token)  vaultKeys 캐시 히트/미스, vault 재fetch
 *   - refreshVaultKeys()          30초 throttle, vault 복호화, PIN 재요청
 *   - setupRealtimeSync()         SSE 연결, new_record/onerror 핸들러
 */

// ─────────────────────────────────────────────────────────────────────────────
// Node.js globals (crypto.subtle, TextEncoder, TextDecoder available in Node 22)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Chrome API 목 (setup.js는 jsdom 전용이므로 node 환경에서 직접 정의)
// ─────────────────────────────────────────────────────────────────────────────

global.chrome = {
    runtime: { lastError: null },
    storage: {
        session: {
            get: jest.fn(),
            set: jest.fn(),
            remove: jest.fn(),
        },
        local: {
            get: jest.fn(),
            set: jest.fn(),
        },
    },
    identity: {
        launchWebAuthFlow: jest.fn(),
        getAuthToken: jest.fn(),
    },
    tabs: { query: jest.fn(), sendMessage: jest.fn() },
};

// ─────────────────────────────────────────────────────────────────────────────
// 모듈 상태 (테스트마다 reset)
// ─────────────────────────────────────────────────────────────────────────────

let vaultKeys = {};
let currentUser = null;
let currentOAuthToken = null;
let pinAuthenticated = false;
let lastVaultRefreshTime = 0;
let eventSource = null;
let records = [];

const viewCalls = [];
const toastCalls = [];
function showPinView()           { viewCalls.push('showPinView'); }
function showMainView()          { viewCalls.push('showMainView'); }
function fetchRecords()          { viewCalls.push('fetchRecords'); }
function fetchHistory()          { viewCalls.push('fetchHistory'); }
function setupRealtimeSync()     { viewCalls.push('setupRealtimeSync'); }
function showToastNotification(msg) { toastCalls.push(msg); }
function performLogout()         { viewCalls.push('performLogout'); }
function showAccountDeletedError() { viewCalls.push('showAccountDeletedError'); }

const API_BASE = 'https://dash.qpon/api';

function base64ToArrayBuffer(base64) {
    const binary = Buffer.from(base64, 'base64');
    return binary.buffer.slice(binary.byteOffset, binary.byteOffset + binary.byteLength);
}

function arrayBufferToBase64(buf) {
    return Buffer.from(buf).toString('base64');
}

function authHeaders() {
    return currentOAuthToken ? { 'Authorization': `Bearer ${currentOAuthToken}` } : {};
}

// ─────────────────────────────────────────────────────────────────────────────
// 테스트 대상 함수
// ─────────────────────────────────────────────────────────────────────────────

async function getShareKeyForToken(token) {
    if (vaultKeys[token]) return vaultKeys[token];

    const session = await new Promise(resolve =>
        chrome.storage.session.get(['cachedDerivedKey'], result => resolve(result))
    );
    if (!session.cachedDerivedKey || !currentUser?.uid) return 'PIN_REQUIRED';

    try {
        const res = await fetch(`${API_BASE}/users/vault/${currentUser.uid}`, { headers: authHeaders() });
        if (!res.ok) return '';
        const { encrypted_vault } = await res.json();
        if (!encrypted_vault) return '';

        const parts = encrypted_vault.split(':');
        if (parts.length !== 2) return '';
        const iv = base64ToArrayBuffer(parts[0]);
        const ciphertext = base64ToArrayBuffer(parts[1]);
        const keyBytes = Buffer.from(session.cachedDerivedKey, 'base64');
        const aesKey = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']);
        const buf = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, aesKey, ciphertext);
        const freshVault = JSON.parse(new TextDecoder().decode(buf));

        vaultKeys = { ...vaultKeys, ...freshVault };
        lastVaultRefreshTime = Date.now();
        chrome.storage.session.set({ cachedVaultKeys: vaultKeys });
        if (freshVault[token]) return freshVault[token];

        const fallbackRec = records.find(r => r.share_token === token);
        if (fallbackRec?.encryption_key) return fallbackRec.encryption_key;
        return '';
    } catch (e) {
        chrome.storage.session.remove(['cachedVaultKeys', 'cachedDerivedKey']);
        return 'PIN_REQUIRED';
    }
}

async function refreshVaultKeys() {
    if (!pinAuthenticated || !currentUser?.uid) return;
    const THROTTLE_MS = 30 * 1000;
    if (Date.now() - lastVaultRefreshTime < THROTTLE_MS) return;

    try {
        const session = await new Promise(resolve =>
            chrome.storage.session.get(['cachedDerivedKey'], result => resolve(result))
        );
        if (!session.cachedDerivedKey) return;

        const res = await fetch(`${API_BASE}/users/vault/${currentUser.uid}`, { headers: authHeaders() });
        if (!res.ok) return;
        const { encrypted_vault } = await res.json();
        if (!encrypted_vault) return;

        const parts = encrypted_vault.split(':');
        if (parts.length !== 2) return;
        const iv = base64ToArrayBuffer(parts[0]);
        const ciphertext = base64ToArrayBuffer(parts[1]);

        let freshVault;
        try {
            const keyBytes = Buffer.from(session.cachedDerivedKey, 'base64');
            const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']);
            const buf = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, key, ciphertext);
            freshVault = JSON.parse(new TextDecoder().decode(buf));
        } catch (_) {
            vaultKeys = {};
            pinAuthenticated = false;
            chrome.storage.session.remove(['cachedVaultKeys', 'cachedDerivedKey']);
            showPinView();
            return;
        }

        vaultKeys = { ...vaultKeys, ...freshVault };
        lastVaultRefreshTime = Date.now();
        chrome.storage.session.set({ cachedVaultKeys: vaultKeys });
    } catch (e) {
        // 조용히 무시
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 테스트 헬퍼 — vault 암호화
// ─────────────────────────────────────────────────────────────────────────────

async function encryptVaultWithKey(keyBytes, vaultObj) {
    const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['encrypt']);
    const iv = crypto.getRandomValues(new Uint8Array(16));
    const plaintext = new TextEncoder().encode(JSON.stringify(vaultObj));
    const ciphertext = await crypto.subtle.encrypt({ name: 'AES-CBC', iv }, key, plaintext);
    return `${arrayBufferToBase64(iv.buffer)}:${arrayBufferToBase64(ciphertext)}`;
}

function resetState() {
    vaultKeys = {};
    currentUser = null;
    currentOAuthToken = null;
    pinAuthenticated = false;
    lastVaultRefreshTime = 0;
    records = [];
    viewCalls.length = 0;
    toastCalls.length = 0;
    global.fetch = undefined;
    jest.clearAllMocks();
    chrome.runtime.lastError = null;
}

// ─────────────────────────────────────────────────────────────────────────────
// getShareKeyForToken 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('getShareKeyForToken — Vault 키 캐시/재fetch', () => {
    beforeEach(resetState);

    test('캐시 히트: vaultKeys에 이미 있으면 바로 반환', async () => {
        vaultKeys = { 'tok1': 'encKey_abc' };
        const result = await getShareKeyForToken('tok1');
        expect(result).toBe('encKey_abc');
        expect(chrome.storage.session.get).not.toHaveBeenCalled();
    });

    test('cachedDerivedKey 없음 → PIN_REQUIRED', async () => {
        currentUser = { uid: 'uid1' };
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({}));

        const result = await getShareKeyForToken('missing_token');
        expect(result).toBe('PIN_REQUIRED');
    });

    test('currentUser 없음 → PIN_REQUIRED', async () => {
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({
            cachedDerivedKey: 'someKey'
        }));
        // currentUser = null

        const result = await getShareKeyForToken('tok');
        expect(result).toBe('PIN_REQUIRED');
    });

    test('vault fetch 실패(non-ok) → 빈 문자열', async () => {
        currentUser = { uid: 'uid1' };
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({ cachedDerivedKey: 'someKey' }));
        global.fetch = jest.fn().mockResolvedValue({ ok: false, status: 500 });

        expect(await getShareKeyForToken('tok')).toBe('');
    });

    test('vault에 토큰 없고 records fallback 있음 → encryption_key 반환', async () => {
        const derivedKeyBytes = crypto.getRandomValues(new Uint8Array(32));
        const derivedKeyB64 = arrayBufferToBase64(derivedKeyBytes.buffer);
        const encrypted = await encryptVaultWithKey(derivedKeyBytes, { other_tok: 'other_key' });

        currentUser = { uid: 'uid1' };
        currentOAuthToken = 'token';
        records = [{ share_token: 'target_tok', encryption_key: 'legacy_enc_key' }];
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({ cachedDerivedKey: derivedKeyB64 }));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted })
        });

        const result = await getShareKeyForToken('target_tok');
        expect(result).toBe('legacy_enc_key');
    });

    test('vault에 토큰 있음 → 해당 키 반환 + vaultKeys 업데이트', async () => {
        const derivedKeyBytes = crypto.getRandomValues(new Uint8Array(32));
        const derivedKeyB64 = arrayBufferToBase64(derivedKeyBytes.buffer);
        const encrypted = await encryptVaultWithKey(derivedKeyBytes, { 'real_tok': 'real_key_xyz' });

        currentUser = { uid: 'uid1' };
        currentOAuthToken = 'token';
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({ cachedDerivedKey: derivedKeyB64 }));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted })
        });

        const result = await getShareKeyForToken('real_tok');
        expect(result).toBe('real_key_xyz');
        expect(vaultKeys['real_tok']).toBe('real_key_xyz');
    });

    test('복호화 실패(잘못된 키) → PIN_REQUIRED + 세션 삭제', async () => {
        currentUser = { uid: 'uid1' };
        const correctKeyBytes = crypto.getRandomValues(new Uint8Array(32));
        const wrongKeyBytes = crypto.getRandomValues(new Uint8Array(32));
        const wrongKeyB64 = arrayBufferToBase64(wrongKeyBytes.buffer);
        const encrypted = await encryptVaultWithKey(correctKeyBytes, { tok: 'key' });

        chrome.storage.session.get.mockImplementation((keys, cb) => cb({ cachedDerivedKey: wrongKeyB64 }));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted })
        });

        const result = await getShareKeyForToken('tok');
        expect(result).toBe('PIN_REQUIRED');
        expect(chrome.storage.session.remove).toHaveBeenCalled();
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// refreshVaultKeys 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('refreshVaultKeys — 30초 throttle & vault 갱신', () => {
    beforeEach(resetState);

    test('pinAuthenticated=false → 즉시 반환 (fetch 없음)', async () => {
        pinAuthenticated = false;
        currentUser = { uid: 'uid1' };
        global.fetch = jest.fn();

        await refreshVaultKeys();
        expect(global.fetch).not.toHaveBeenCalled();
    });

    test('currentUser 없음 → 즉시 반환', async () => {
        pinAuthenticated = true;
        currentUser = null;
        global.fetch = jest.fn();

        await refreshVaultKeys();
        expect(global.fetch).not.toHaveBeenCalled();
    });

    test('30초 내 재호출 → throttle (fetch 없음)', async () => {
        pinAuthenticated = true;
        currentUser = { uid: 'uid1' };
        lastVaultRefreshTime = Date.now() - 10_000; // 10초 전
        global.fetch = jest.fn();
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({ cachedDerivedKey: 'key' }));

        await refreshVaultKeys();
        expect(global.fetch).not.toHaveBeenCalled();
    });

    test('30초 초과 후 → fetch 실행', async () => {
        const derivedKeyBytes = crypto.getRandomValues(new Uint8Array(32));
        const derivedKeyB64 = arrayBufferToBase64(derivedKeyBytes.buffer);
        const encrypted = await encryptVaultWithKey(derivedKeyBytes, { tok: 'new_key' });

        pinAuthenticated = true;
        currentUser = { uid: 'uid1' };
        lastVaultRefreshTime = Date.now() - 60_000; // 60초 전
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({ cachedDerivedKey: derivedKeyB64 }));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted })
        });

        await refreshVaultKeys();
        expect(global.fetch).toHaveBeenCalled();
        expect(vaultKeys['tok']).toBe('new_key');
    });

    test('cachedDerivedKey 없음 → fetch 없음', async () => {
        pinAuthenticated = true;
        currentUser = { uid: 'uid1' };
        lastVaultRefreshTime = 0;
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({}));
        global.fetch = jest.fn();

        await refreshVaultKeys();
        expect(global.fetch).not.toHaveBeenCalled();
    });

    test('fetch 실패(non-ok) → 조용히 반환', async () => {
        pinAuthenticated = true;
        currentUser = { uid: 'uid1' };
        lastVaultRefreshTime = 0;
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({ cachedDerivedKey: 'key' }));
        global.fetch = jest.fn().mockResolvedValue({ ok: false, status: 500 });

        await expect(refreshVaultKeys()).resolves.toBeUndefined();
    });

    test('복호화 실패(잘못된 키) → pinAuthenticated=false, showPinView 호출', async () => {
        const correctKey = crypto.getRandomValues(new Uint8Array(32));
        const wrongKey = crypto.getRandomValues(new Uint8Array(32));
        const wrongKeyB64 = arrayBufferToBase64(wrongKey.buffer);
        const encrypted = await encryptVaultWithKey(correctKey, { tok: 'key' });

        pinAuthenticated = true;
        currentUser = { uid: 'uid1' };
        lastVaultRefreshTime = 0;
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({ cachedDerivedKey: wrongKeyB64 }));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted })
        });

        await refreshVaultKeys();

        expect(pinAuthenticated).toBe(false);
        expect(vaultKeys).toEqual({});
        expect(viewCalls).toContain('showPinView');
        expect(chrome.storage.session.remove).toHaveBeenCalled();
    });

    test('성공적 갱신 후 lastVaultRefreshTime 업데이트', async () => {
        const derivedKeyBytes = crypto.getRandomValues(new Uint8Array(32));
        const derivedKeyB64 = arrayBufferToBase64(derivedKeyBytes.buffer);
        const encrypted = await encryptVaultWithKey(derivedKeyBytes, {});

        pinAuthenticated = true;
        currentUser = { uid: 'uid1' };
        lastVaultRefreshTime = 0;
        chrome.storage.session.get.mockImplementation((keys, cb) => cb({ cachedDerivedKey: derivedKeyB64 }));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted })
        });

        const before = Date.now();
        await refreshVaultKeys();
        expect(lastVaultRefreshTime).toBeGreaterThanOrEqual(before);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// setupRealtimeSync — EventSource SSE 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('setupRealtimeSync — SSE 연결 관리', () => {
    // EventSource mock 클래스
    class MockEventSource {
        constructor(url) {
            this.url = url;
            this.listeners = {};
            this.onmessage = null;
            this.onerror = null;
            MockEventSource.instance = this;
        }
        addEventListener(type, handler) {
            this.listeners[type] = handler;
        }
        close() { this.closed = true; }
        // 테스트에서 이벤트를 수동으로 발생시킴
        emit(type, data) {
            if (this.listeners[type]) this.listeners[type]({ data: JSON.stringify(data) });
        }
        emitError(err) {
            if (this.onerror) this.onerror(err);
        }
    }
    MockEventSource.instance = null;

    async function setupRealtimeSyncLocal() {
        if (eventSource) eventSource.close();

        try {
            const freshToken = await Promise.resolve('fresh_token');
            currentOAuthToken = freshToken;
            chrome.storage.session.set({ cachedOAuthToken: freshToken });
        } catch (e) {}

        const sseToken = currentOAuthToken ? `?token=${encodeURIComponent(currentOAuthToken)}` : '';
        eventSource = new MockEventSource(`${API_BASE}/events${sseToken}`);

        eventSource.addEventListener('new_record', async (e) => {
            const data = JSON.parse(e.data);
            if (!currentUser || (data.user_email !== currentUser.email && data.user_id !== currentUser.uid)) return;

            if (Object.keys(vaultKeys).length === 0) {
                showToastNotification('모바일에서 PIN이 설정되었습니다. PIN을 입력해주세요.');
                showPinView();
                return;
            }
            showToastNotification('새 데이터가 도착했습니다✨');
            fetchRecords();
        });

        eventSource.addEventListener('record_deleted', (e) => {
            const data = JSON.parse(e.data);
            if (!currentUser || (data.user_email && data.user_email !== currentUser.email)) return;
            fetchRecords();
        });

        eventSource.onerror = async (err) => {
            eventSource.close();
            if (!currentOAuthToken) return;
            try {
                currentOAuthToken = 'refreshed_token';
                chrome.storage.session.set({ cachedOAuthToken: currentOAuthToken });
                // setTimeout 대신 즉시 setupRealtimeSyncLocal() (테스트에서 순환 방지)
            } catch (e) {
                performLogout();
            }
        };
    }

    beforeEach(() => {
        resetState();
        currentUser = { uid: 'uid1', email: 'test@test.com' };
        currentOAuthToken = 'initial_token';
    });

    test('EventSource URL에 토큰 포함 (토큰 갱신 후 반영)', async () => {
        // setupRealtimeSyncLocal은 항상 getFreshTokenSilent()로 갱신 → 'fresh_token' 사용
        await setupRealtimeSyncLocal();
        expect(MockEventSource.instance.url).toContain('?token=');
        expect(MockEventSource.instance.url).toContain('fresh_token');
    });

    test('기존 eventSource 닫고 새로 생성', async () => {
        const oldEs = { close: jest.fn() };
        eventSource = oldEs;

        await setupRealtimeSyncLocal();
        expect(oldEs.close).toHaveBeenCalled();
        expect(MockEventSource.instance).not.toBe(oldEs);
    });

    test('new_record: 현재 사용자 이벤트 → fetchRecords 호출', async () => {
        vaultKeys = { tok: 'key' }; // vault 있음 → 새 데이터 토스트
        await setupRealtimeSyncLocal();

        MockEventSource.instance.emit('new_record', {
            user_email: 'test@test.com',
            user_id: 'uid1'
        });

        await new Promise(r => setTimeout(r, 10));
        expect(viewCalls).toContain('fetchRecords');
    });

    test('new_record: 다른 사용자 이벤트 → 무시', async () => {
        vaultKeys = { tok: 'key' };
        await setupRealtimeSyncLocal();

        MockEventSource.instance.emit('new_record', {
            user_email: 'other@test.com',
            user_id: 'other_uid'
        });

        await new Promise(r => setTimeout(r, 10));
        expect(viewCalls).not.toContain('fetchRecords');
    });

    test('new_record: vaultKeys 빈 상태 → showPinView 호출', async () => {
        vaultKeys = {}; // vault 없음 → PIN 요청
        await setupRealtimeSyncLocal();

        MockEventSource.instance.emit('new_record', {
            user_email: 'test@test.com',
            user_id: 'uid1'
        });

        await new Promise(r => setTimeout(r, 10));
        expect(viewCalls).toContain('showPinView');
        expect(toastCalls.some(t => t.includes('PIN'))).toBe(true);
    });

    test('record_deleted: 같은 사용자 → fetchRecords', async () => {
        await setupRealtimeSyncLocal();

        MockEventSource.instance.emit('record_deleted', {
            user_email: 'test@test.com'
        });

        expect(viewCalls).toContain('fetchRecords');
    });

    test('record_deleted: 다른 사용자 → 무시', async () => {
        await setupRealtimeSyncLocal();

        MockEventSource.instance.emit('record_deleted', {
            user_email: 'other@test.com'
        });

        expect(viewCalls).not.toContain('fetchRecords');
    });

    test('토큰 갱신 성공 시 EventSource URL에 갱신된 토큰 포함', async () => {
        // 토큰 갱신은 항상 성공(fresh_token)하므로 URL에 갱신 토큰 포함됨
        currentOAuthToken = null;
        await setupRealtimeSyncLocal();
        // setupRealtimeSyncLocal 내부에서 currentOAuthToken = 'fresh_token'으로 갱신됨
        expect(MockEventSource.instance.url).toContain('fresh_token');
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// verifyPinWithVault — PIN 검증 핵심 함수 (pin.js:81)
// ─────────────────────────────────────────────────────────────────────────────

// pin.js verifyPinWithVault 구현 복제 (crypto.subtle 필요 → @jest-environment node)
async function deriveVaultKey(pin, saltB64) {
    const keyMaterial = await crypto.subtle.importKey(
        'raw', new TextEncoder().encode(pin), 'PBKDF2', false, ['deriveBits']
    );
    const saltBytes = Uint8Array.from(atob(saltB64), c => c.charCodeAt(0));
    const bits = await crypto.subtle.deriveBits(
        { name: 'PBKDF2', hash: 'SHA-256', salt: saltBytes, iterations: 100000 },
        keyMaterial, 256
    );
    return new Uint8Array(bits);
}

async function attemptDecryptVault(pin, encryptedVaultB64, salt) {
    const parts = encryptedVaultB64.split(':');
    if (parts.length !== 2) return null;
    const iv = base64ToArrayBuffer(parts[0]);
    const ciphertext = base64ToArrayBuffer(parts[1]);

    if (salt && salt.length > 10) {
        try {
            const keyBytes = await deriveVaultKey(pin, salt);
            const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']);
            const buf = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, key, ciphertext);
            return JSON.parse(new TextDecoder().decode(buf));
        } catch (_) {}
        return null;
    }
    // 레거시: raw PIN pad
    const keyBytes = new TextEncoder().encode(pin.padEnd(32).substring(0, 32));
    try {
        const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']);
        const buf = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, key, ciphertext);
        return JSON.parse(new TextDecoder().decode(buf));
    } catch (_) {}
    return null;
}

async function verifyPinWithVault(pin) {
    if (!currentUser?.uid) return null;
    try {
        const res = await fetch(`${API_BASE}/users/vault/${currentUser.uid}`, { headers: authHeaders() });
        if (!res.ok) return null;
        const { encrypted_vault, salt } = await res.json();
        if (!encrypted_vault) return null;

        // PIN 성공 시 derived key를 세션에 캐시
        if (salt && salt.length > 10) {
            try {
                const keyBytes = await deriveVaultKey(pin, salt);
                const keyB64 = Buffer.from(keyBytes).toString('base64');
                chrome.storage.session.set({ cachedDerivedKey: keyB64 });
            } catch (_) {}
        }

        return await attemptDecryptVault(pin, encrypted_vault, salt);
    } catch (e) {
        return null;
    }
}

// 테스트 헬퍼: PBKDF2로 암호화된 vault 생성
async function makeEncryptedVault(pin, saltB64, vaultObj) {
    const keyBytes = await deriveVaultKey(pin, saltB64);
    return encryptVaultWithKey(keyBytes, vaultObj);
}

describe('verifyPinWithVault — PIN 검증 핵심 함수', () => {
    beforeEach(resetState);

    test('currentUser 없음 → null 즉시 반환 (fetch 없음)', async () => {
        currentUser = null;
        global.fetch = jest.fn();

        expect(await verifyPinWithVault('1234')).toBeNull();
        expect(global.fetch).not.toHaveBeenCalled();
    });

    test('서버 오류(non-ok) → null', async () => {
        currentUser = { uid: 'uid1' };
        global.fetch = jest.fn().mockResolvedValue({ ok: false, status: 500 });

        expect(await verifyPinWithVault('1234')).toBeNull();
    });

    test('encrypted_vault 없음(null) → null', async () => {
        currentUser = { uid: 'uid1' };
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: null, salt: 'AAAAAAAAAAAAAAAAAA==' })
        });

        expect(await verifyPinWithVault('1234')).toBeNull();
    });

    test('올바른 PIN + PBKDF2 salt → vault 맵 반환', async () => {
        const pin = '1234';
        const salt = arrayBufferToBase64(crypto.getRandomValues(new Uint8Array(16)).buffer);
        const vaultData = { share_tok: 'enc_key_abc' };
        const encrypted = await makeEncryptedVault(pin, salt, vaultData);

        currentUser = { uid: 'uid1' };
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted, salt })
        });

        const result = await verifyPinWithVault(pin);
        expect(result).toEqual(vaultData);
    });

    test('올바른 PIN → cachedDerivedKey를 세션에 저장', async () => {
        const pin = '5678';
        const salt = arrayBufferToBase64(crypto.getRandomValues(new Uint8Array(16)).buffer);
        const encrypted = await makeEncryptedVault(pin, salt, {});

        currentUser = { uid: 'uid1' };
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted, salt })
        });

        await verifyPinWithVault(pin);
        expect(chrome.storage.session.set).toHaveBeenCalledWith(
            expect.objectContaining({ cachedDerivedKey: expect.any(String) })
        );
    });

    test('틀린 PIN → null', async () => {
        const correctPin = '1234';
        const wrongPin = '9999';
        const salt = arrayBufferToBase64(crypto.getRandomValues(new Uint8Array(16)).buffer);
        const encrypted = await makeEncryptedVault(correctPin, salt, { tok: 'key' });

        currentUser = { uid: 'uid1' };
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted, salt })
        });

        expect(await verifyPinWithVault(wrongPin)).toBeNull();
    });

    test('salt 없음(레거시) → raw PIN pad 복호화 시도', async () => {
        const pin = '0000';
        // 레거시: raw PIN pad (AES-CBC, 32자 패딩)
        const keyStr = pin.padEnd(32).substring(0, 32);
        const keyBytes = new TextEncoder().encode(keyStr);
        const encrypted = await encryptVaultWithKey(keyBytes, { legacy_tok: 'legacy_key' });

        currentUser = { uid: 'uid1' };
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted, salt: null })
        });

        const result = await verifyPinWithVault(pin);
        expect(result).toEqual({ legacy_tok: 'legacy_key' });
    });

    test('빈 vault {} → 빈 맵 반환', async () => {
        const pin = '1234';
        const salt = arrayBufferToBase64(crypto.getRandomValues(new Uint8Array(16)).buffer);
        const encrypted = await makeEncryptedVault(pin, salt, {});

        currentUser = { uid: 'uid1' };
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted, salt })
        });

        expect(await verifyPinWithVault(pin)).toEqual({});
    });

    test('여러 토큰 포함 vault → 전체 맵 반환', async () => {
        const pin = '1234';
        const salt = arrayBufferToBase64(crypto.getRandomValues(new Uint8Array(16)).buffer);
        const vaultData = { tok1: 'key1', tok2: 'key2', tok3: 'key3' };
        const encrypted = await makeEncryptedVault(pin, salt, vaultData);

        currentUser = { uid: 'uid1' };
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => ({ encrypted_vault: encrypted, salt })
        });

        const result = await verifyPinWithVault(pin);
        expect(result).toEqual(vaultData);
    });

    test('네트워크 예외 → null (조용히 처리)', async () => {
        currentUser = { uid: 'uid1' };
        global.fetch = jest.fn().mockRejectedValue(new Error('Network Error'));

        expect(await verifyPinWithVault('1234')).toBeNull();
    });
});
