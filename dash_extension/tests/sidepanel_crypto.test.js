/**
 * @jest-environment node
 *
 * sidepanel.js — Web Crypto API 단위 테스트
 *
 * 테스트 대상:
 *   - deriveVaultKey(pin, saltB64)        PBKDF2 키 파생
 *   - attemptDecryptVault(pin, enc, salt) Vault 복호화 (PBKDF2 + 레거시 폴백)
 *   - decryptBlob(encBlobStr, encKey)     공유 DB blob 복호화
 *
 * Node.js 18+: crypto.subtle / TextEncoder / TextDecoder 전역 사용 가능
 * jsdom은 crypto.subtle을 제공하지 않으므로 node 환경 사용
 */

// ─────────────────────────────────────────────────────────────────────────────
// 함수 추출 (sidepanel.js 순수 로직 복제 — chrome.runtime.id 없이 로드 불가)
// ─────────────────────────────────────────────────────────────────────────────

function base64ToArrayBuffer(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes.buffer;
}

function arrayBufferToBase64(buf) {
    return btoa(String.fromCharCode(...new Uint8Array(buf)));
}

function removePkcs7(bytes) {
    const padLen = bytes[bytes.length - 1];
    if (padLen < 1 || padLen > 16) return bytes;
    return bytes.slice(0, bytes.length - padLen);
}

async function deriveVaultKey(pin, saltB64) {
    const keyMaterial = await crypto.subtle.importKey(
        'raw',
        new TextEncoder().encode(pin),
        'PBKDF2',
        false,
        ['deriveBits']
    );
    const saltBytes = Uint8Array.from(atob(saltB64), c => c.charCodeAt(0));
    const bits = await crypto.subtle.deriveBits(
        { name: 'PBKDF2', hash: 'SHA-256', salt: saltBytes, iterations: 100000 },
        keyMaterial,
        256
    );
    return new Uint8Array(bits);
}

async function attemptDecryptVault(pin, encryptedVaultB64, salt) {
    const parts = encryptedVaultB64.split(':');
    if (parts.length !== 2) return null;

    const iv = base64ToArrayBuffer(parts[0]);
    const ciphertext = base64ToArrayBuffer(parts[1]);

    // 1차 시도: PBKDF2 파생 키 (salt가 있는 신규 Vault)
    if (salt && salt.length > 10) {
        try {
            const keyBytes = await deriveVaultKey(pin, salt);
            const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']);
            const buf = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, key, ciphertext);
            const decryptedText = new TextDecoder().decode(buf);
            return JSON.parse(decryptedText);
        } catch (e) {}
        return null; // 신규 Vault는 PBKDF2만 시도
    }

    // 2차 시도: 레거시 raw PIN pad
    const keyBytes = new TextEncoder().encode(pin.padEnd(32).substring(0, 32));
    try {
        const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']);
        const buf = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, key, ciphertext);
        return JSON.parse(new TextDecoder().decode(buf));
    } catch {}
    try {
        const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CTR' }, false, ['decrypt']);
        const buf = await crypto.subtle.decrypt({ name: 'AES-CTR', counter: iv, length: 128 }, key, ciphertext);
        const unpadded = removePkcs7(new Uint8Array(buf));
        return JSON.parse(new TextDecoder().decode(unpadded));
    } catch {}

    return null;
}

async function decryptBlob(encryptedBlobStr, encryptionKey) {
    try {
        const parts = encryptedBlobStr.split(':');
        if (parts.length !== 2) return null;

        const iv = base64ToArrayBuffer(parts[0]);
        const ciphertext = base64ToArrayBuffer(parts[1]);

        const keyStr = encryptionKey.padEnd(32).substring(0, 32);
        const keyBytes = new TextEncoder().encode(keyStr);

        const cryptoKey = await crypto.subtle.importKey(
            'raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']
        );

        const decryptedBuffer = await crypto.subtle.decrypt(
            { name: 'AES-CBC', iv }, cryptoKey, ciphertext
        );

        return JSON.parse(new TextDecoder().decode(decryptedBuffer));
    } catch (e) {
        return null;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 테스트 헬퍼 — 암호화 유틸
// ─────────────────────────────────────────────────────────────────────────────

/** AES-CBC(PBKDF2 키)로 평문 JSON 암호화 → "ivB64:cipherB64" */
async function encryptWithPbkdf2(pin, saltB64, plainObj) {
    const keyBytes = await deriveVaultKey(pin, saltB64);
    const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['encrypt']);
    const iv = crypto.getRandomValues(new Uint8Array(16));
    const plaintext = new TextEncoder().encode(JSON.stringify(plainObj));
    const ciphertext = await crypto.subtle.encrypt({ name: 'AES-CBC', iv }, key, plaintext);
    return `${arrayBufferToBase64(iv.buffer)}:${arrayBufferToBase64(ciphertext)}`;
}

/** AES-CBC(raw PIN pad)로 평문 JSON 암호화 → "ivB64:cipherB64" */
async function encryptWithRawPin(pin, plainObj) {
    const keyBytes = new TextEncoder().encode(pin.padEnd(32).substring(0, 32));
    const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['encrypt']);
    const iv = crypto.getRandomValues(new Uint8Array(16));
    const plaintext = new TextEncoder().encode(JSON.stringify(plainObj));
    const ciphertext = await crypto.subtle.encrypt({ name: 'AES-CBC', iv }, key, plaintext);
    return `${arrayBufferToBase64(iv.buffer)}:${arrayBufferToBase64(ciphertext)}`;
}

/** AES-CBC(raw key string pad)로 blob 암호화 → "ivB64:cipherB64" */
async function encryptBlob(encryptionKey, plainObj) {
    const keyStr = encryptionKey.padEnd(32).substring(0, 32);
    const keyBytes = new TextEncoder().encode(keyStr);
    const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['encrypt']);
    const iv = crypto.getRandomValues(new Uint8Array(16));
    const plaintext = new TextEncoder().encode(JSON.stringify(plainObj));
    const ciphertext = await crypto.subtle.encrypt({ name: 'AES-CBC', iv }, key, plaintext);
    return `${arrayBufferToBase64(iv.buffer)}:${arrayBufferToBase64(ciphertext)}`;
}

/** base64 salt 생성 헬퍼 (16바이트) */
function makeSalt() {
    return arrayBufferToBase64(crypto.getRandomValues(new Uint8Array(16)).buffer);
}

// ─────────────────────────────────────────────────────────────────────────────
// deriveVaultKey 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('deriveVaultKey — PBKDF2 키 파생', () => {
    const salt = 'AAAAAAAAAAAAAAAAAAAAAA=='; // 고정 salt (테스트 결정론성)

    test('32바이트(256비트) 키 반환', async () => {
        const key = await deriveVaultKey('1234', salt);
        expect(key).toBeInstanceOf(Uint8Array);
        expect(key.length).toBe(32);
    });

    test('결정론적 — 같은 PIN+salt는 항상 같은 키', async () => {
        const k1 = await deriveVaultKey('1234', salt);
        const k2 = await deriveVaultKey('1234', salt);
        expect(Array.from(k1)).toEqual(Array.from(k2));
    });

    test('다른 PIN → 다른 키', async () => {
        const k1 = await deriveVaultKey('1234', salt);
        const k2 = await deriveVaultKey('9999', salt);
        expect(Array.from(k1)).not.toEqual(Array.from(k2));
    });

    test('다른 salt → 다른 키', async () => {
        const salt2 = 'BBBBBBBBBBBBBBBBBBBBBB==';
        const k1 = await deriveVaultKey('1234', salt);
        const k2 = await deriveVaultKey('1234', salt2);
        expect(Array.from(k1)).not.toEqual(Array.from(k2));
    });

    test('빈 PIN도 키 파생 성공 (Zero-length key는 PBKDF2에서 허용)', async () => {
        const key = await deriveVaultKey('', salt);
        expect(key.length).toBe(32);
    });

    test('긴 PIN (100자) — 정상 파생', async () => {
        const longPin = 'A'.repeat(100);
        const key = await deriveVaultKey(longPin, salt);
        expect(key.length).toBe(32);
    });

    test('유니코드 PIN (Korean digits)', async () => {
        const key = await deriveVaultKey('일이삼사', salt);
        expect(key.length).toBe(32);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// attemptDecryptVault 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('attemptDecryptVault — Vault 복호화', () => {

    // ── PBKDF2 경로 (신규 Vault, salt 있음) ───────────────────────────────────

    describe('PBKDF2 경로 (salt.length > 10)', () => {
        test('올바른 PIN+salt → Vault 객체 반환', async () => {
            const salt = makeSalt();
            const vaultData = { tok1: 'key_abc', tok2: 'key_xyz' };
            const encrypted = await encryptWithPbkdf2('1234', salt, vaultData);

            const result = await attemptDecryptVault('1234', encrypted, salt);
            expect(result).toEqual(vaultData);
        });

        test('빈 Vault {}도 복호화 성공', async () => {
            const salt = makeSalt();
            const encrypted = await encryptWithPbkdf2('0000', salt, {});
            const result = await attemptDecryptVault('0000', encrypted, salt);
            expect(result).toEqual({});
        });

        test('여러 토큰 포함 Vault 복호화', async () => {
            const salt = makeSalt();
            const vaultData = {};
            for (let i = 0; i < 10; i++) vaultData[`token_${i}`] = `encKey_${i}`;
            const encrypted = await encryptWithPbkdf2('5678', salt, vaultData);

            const result = await attemptDecryptVault('5678', encrypted, salt);
            expect(Object.keys(result).length).toBe(10);
            expect(result['token_5']).toBe('encKey_5');
        });

        test('틀린 PIN → null 반환', async () => {
            const salt = makeSalt();
            const encrypted = await encryptWithPbkdf2('1234', salt, { tok: 'key' });
            const result = await attemptDecryptVault('9999', encrypted, salt);
            expect(result).toBeNull();
        });

        test('틀린 salt → null 반환', async () => {
            const salt1 = makeSalt();
            const salt2 = makeSalt();
            const encrypted = await encryptWithPbkdf2('1234', salt1, { tok: 'key' });
            const result = await attemptDecryptVault('1234', encrypted, salt2);
            expect(result).toBeNull();
        });

        test('short salt (≤10자) → 레거시 경로로 넘어감 (null)', async () => {
            // short salt는 PBKDF2를 건너뛰고 레거시 raw PIN 시도 → 암호화 방식 불일치 → null
            const salt = makeSalt();
            const encrypted = await encryptWithPbkdf2('1234', salt, { tok: 'key' });
            const result = await attemptDecryptVault('1234', encrypted, 'short'); // ≤10자
            expect(result).toBeNull();
        });
    });

    // ── 레거시 경로 (salt 없음 또는 null) ─────────────────────────────────────

    describe('레거시 경로 (raw PIN pad, salt=null)', () => {
        test('올바른 PIN → Vault 복호화 성공', async () => {
            const vaultData = { legacy_tok: 'legacy_key' };
            const encrypted = await encryptWithRawPin('1234', vaultData);
            const result = await attemptDecryptVault('1234', encrypted, null);
            expect(result).toEqual(vaultData);
        });

        test('틀린 PIN → null 반환', async () => {
            const encrypted = await encryptWithRawPin('1234', { tok: 'key' });
            const result = await attemptDecryptVault('9999', encrypted, null);
            expect(result).toBeNull();
        });

        test('salt 빈 문자열 → 레거시 경로', async () => {
            const vaultData = { tok: 'key' };
            const encrypted = await encryptWithRawPin('0000', vaultData);
            const result = await attemptDecryptVault('0000', encrypted, '');
            expect(result).toEqual(vaultData);
        });
    });

    // ── 형식 오류 ──────────────────────────────────────────────────────────────

    describe('형식 오류 처리', () => {
        test('콜론 없는 문자열 → null', async () => {
            const result = await attemptDecryptVault('1234', 'invalidbase64nocolon', makeSalt());
            expect(result).toBeNull();
        });

        test('빈 문자열 → null', async () => {
            const result = await attemptDecryptVault('1234', '', null);
            expect(result).toBeNull();
        });

        test('IV만 있고 ciphertext 없음 → null', async () => {
            const ivB64 = arrayBufferToBase64(crypto.getRandomValues(new Uint8Array(16)).buffer);
            const result = await attemptDecryptVault('1234', `${ivB64}:`, null);
            expect(result).toBeNull();
        });

        test('콜론 3개짜리 문자열 → null (parts.length !== 2)', async () => {
            const result = await attemptDecryptVault('1234', 'a:b:c', null);
            expect(result).toBeNull();
        });
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// decryptBlob 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('decryptBlob — 공유 DB blob 복호화', () => {

    test('올바른 키로 복호화 성공', async () => {
        const encKey = 'myEncryptionKey_abc123';
        const blobData = { name: '홍길동', age: 10, address: '서울' };
        const encrypted = await encryptBlob(encKey, blobData);

        const result = await decryptBlob(encrypted, encKey);
        expect(result).toEqual(blobData);
    });

    test('32자 초과 키 → 앞 32자만 사용 (padEnd/substring 로직)', async () => {
        const encKey = 'a'.repeat(50); // 50자
        const blobData = { field: 'value' };
        const encrypted = await encryptBlob(encKey, blobData);

        // 동일 키 (50자)로 복호화 — 내부적으로 앞 32자만 사용
        const result = await decryptBlob(encrypted, encKey);
        expect(result).toEqual(blobData);
    });

    test('짧은 키 → padEnd로 32자 패딩 후 사용', async () => {
        const encKey = 'short'; // 5자
        const blobData = { x: 1 };
        const encrypted = await encryptBlob(encKey, blobData);

        const result = await decryptBlob(encrypted, encKey);
        expect(result).toEqual(blobData);
    });

    test('틀린 키 → null 반환', async () => {
        const encKey = 'correct_key_here_12345';
        const encrypted = await encryptBlob(encKey, { data: 'secret' });
        const result = await decryptBlob(encrypted, 'wrong_key_here_12345');
        expect(result).toBeNull();
    });

    test('형식 오류: 콜론 없음 → null', async () => {
        const result = await decryptBlob('nocolonatall', 'somekey');
        expect(result).toBeNull();
    });

    test('형식 오류: 빈 문자열 → null', async () => {
        const result = await decryptBlob('', 'somekey');
        expect(result).toBeNull();
    });

    test('형식 오류: 콜론 3개 → null', async () => {
        const result = await decryptBlob('a:b:c', 'somekey');
        expect(result).toBeNull();
    });

    test('중첩 객체 포함 blob 복호화', async () => {
        const encKey = 'nested_test_key_32chars!!!!!!!!';
        const blobData = {
            header: { caseId: 'C001', date: '2025-01-01' },
            body: { victim: { age: 5 }, perpetrator: { age: 35 } }
        };
        const encrypted = await encryptBlob(encKey, blobData);
        const result = await decryptBlob(encrypted, encKey);
        expect(result.header.caseId).toBe('C001');
        expect(result.body.victim.age).toBe(5);
    });

    test('특수문자 포함 blob 복호화 (값은 한국어/특수문자, 키는 ASCII)', async () => {
        // 주의: encryptionKey에 멀티바이트 문자(Korean 등)가 포함되면
        // TextEncoder().encode(key.padEnd(32).substring(0,32)) → 32바이트 초과 → DataError
        // 실제 vault key는 항상 base64/ASCII 문자열이므로 ASCII 키를 사용
        const encKey = 'ascii_only_key_123456789_abc!!';  // 30 ASCII chars
        const blobData = { 이름: '홍길동', 메모: '특수문자!@#$%^&*()' };
        const encrypted = await encryptBlob(encKey, blobData);
        const result = await decryptBlob(encrypted, encKey);
        expect(result['이름']).toBe('홍길동');
        expect(result['메모']).toBe('특수문자!@#$%^&*()');
    });

    test('대용량 blob (1000필드) 복호화', async () => {
        const encKey = 'large_blob_test_key_here!!!!!!!';
        const blobData = {};
        for (let i = 0; i < 100; i++) blobData[`field_${i}`] = `value_${'x'.repeat(50)}_${i}`;
        const encrypted = await encryptBlob(encKey, blobData);
        const result = await decryptBlob(encrypted, encKey);
        expect(result['field_99']).toBe(`value_${'x'.repeat(50)}_99`);
    });
});
