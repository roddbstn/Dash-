// ==============================================
// pin.js — PIN 인증 & 암호화 / 복호화 로직
// Vault(PIN 암호화 키 저장소), AES-256, PBKDF2
// ==============================================

// ===== PIN 관련 DOM =====
const pinDots = document.getElementById('pin-dots');
const pinKeypad = document.getElementById('pin-keypad');
const pinError = document.getElementById('pin-error');
const btnForgotPin = document.getElementById('btn-forgot-pin');
const pinHelpModal = document.getElementById('pin-help-modal');
const btnClosePinHelp = document.getElementById('btn-close-pin-help');

// ===== PIN 상태 =====
let pinInput = '';           // 현재 입력 중인 PIN
let pinLocked = false;       // PIN 검증 중 잠금
let vaultKeys = {};          // { share_token: encryptionKey } — 메모리에만 보관, 영구 저장 안 함
let pinAuthenticated = false; // PIN 인증 성공 여부 (vault가 빈 {}이어도 인증된 상태 추적)
let lastVaultRefreshTime = 0; // refreshVaultKeys 마지막 호출 시각 (rate limit 보호)
let pinFailCount = 0;        // PIN 연속 실패 횟수
let pinLockUntil = 0;        // 잠금 해제 시각 (Date.now() 기준)
let _vaultRefreshInProgress = false; // refreshVaultKeys 동시 실행 방지

// ==============================================
// 2.5. PIN 인증 로직
// ==============================================

// PIN 입력 후 서버 Vault와 검증하는 핵심 함수
async function checkPinAndProceed() {
    // 1. 세션 스토리지에 캐시된 vaultKeys 확인 (브라우저 닫기 전까지 재입력 불필요)
    //    PIN 자체는 저장하지 않음 — 복호화된 키만 세션에 보관
    const session = await new Promise(resolve => {
        chrome.storage.session.get(['cachedVaultKeys', 'cachedDerivedKey'], result => resolve(result));
    });
    // cachedDerivedKey도 있어야 vault 갱신 가능 → 없으면 PIN 재입력으로 캐시
    if (session.cachedVaultKeys && session.cachedDerivedKey && Object.keys(session.cachedVaultKeys).length > 0) {
        vaultKeys = session.cachedVaultKeys;
        pinAuthenticated = true;
        showMainView();
        fetchRecords();
        fetchHistory();
        setupRealtimeSync();
        return;
    }

    // 2. 서버에 Vault가 존재하는지 확인
    const hasVault = await checkVaultExists();
    if (!hasVault) {
        // Vault 없음 = 모바일에서 아직 PIN 미설정
        // → 복호화할 키가 없으므로 인증 완료 처리 (배너 미표시)
        pinAuthenticated = true;
        showMainView();
        fetchRecords();
        fetchHistory();
        setupRealtimeSync();
        return;
    }

    // 3. PIN 입력 화면 표시
    showPinView();
}

// 서버에 Vault가 존재하고 실제 암호화 데이터가 있는지 확인
async function checkVaultExists() {
    if (!currentUser?.uid) return false;
    try {
        const res = await fetch(`${API_BASE}/users/vault/${currentUser.uid}`, { headers: authHeaders() });
        if (res.status === 401 || res.status === 403) {
            showAccountDeletedError();
            return false;
        }
        if (!res.ok) return false;
        const data = await res.json();
        return !!(data.encrypted_vault); // 빈 문자열이나 null이면 false → PIN 화면 생략
    } catch (e) {
        console.error('Vault check failed:', e);
        return false;
    }
}

// PIN으로 Vault 복호화 시도 — 성공 시 { share_token: encryptionKey } 맵 반환, 실패 시 null
async function verifyPinWithVault(pin) {
    if (!currentUser?.uid) return null;
    try {
        const res = await fetch(`${API_BASE}/users/vault/${currentUser.uid}`, { headers: authHeaders() });
        if (!res.ok) return null;

        const { encrypted_vault, salt } = await res.json();
        console.log('[DEBUG] vault fetch OK, encrypted_vault len:', encrypted_vault?.length, 'salt len:', salt?.length);
        if (!encrypted_vault) return null;

        // PIN 성공 시 derived key를 세션에 캐시 → vault 재복호화에 재사용
        if (salt && salt.length > 10) {
            try {
                const keyBytes = await deriveVaultKey(pin, salt);
                const keyB64 = btoa(String.fromCharCode(...keyBytes));
                chrome.storage.session.set({ cachedDerivedKey: keyB64 });
            } catch (_) {}
        }

        const result = await attemptDecryptVault(pin, encrypted_vault, salt);
        return result;
    } catch (e) {
        console.error('PIN verification failed:', e);
        return null;
    }
}

// 공유 링크 클릭 시 key 반환
// vaultKeys 캐시에 있으면 바로 반환, 없을 때만 서버 vault 재fetch (rate limit 보호)
async function getShareKeyForToken(token) {
    // 1. 캐시에 이미 있으면 바로 반환
    if (vaultKeys[token]) {
        console.log('[getShareKey] 캐시 히트:', token.slice(0, 8));
        return vaultKeys[token];
    }

    // 2. 캐시 미스 → 서버 vault 실시간 fetch
    const session = await new Promise(resolve => {
        chrome.storage.session.get(['cachedDerivedKey'], result => resolve(result));
    });
    if (!session.cachedDerivedKey || !currentUser?.uid) {
        console.warn('[getShareKey] cachedDerivedKey 없음 → PIN 재인증 필요');
        return 'PIN_REQUIRED';
    }

    try {
        const res = await fetch(`${API_BASE}/users/vault/${currentUser.uid}`, { headers: authHeaders() });
        if (!res.ok) {
            console.warn('[getShareKey] vault fetch 실패:', res.status);
            return '';
        }
        const { encrypted_vault } = await res.json();
        if (!encrypted_vault) {
            console.warn('[getShareKey] vault가 비어있음');
            return '';
        }

        const parts = encrypted_vault.split(':');
        if (parts.length !== 2) return '';
        const iv = base64ToArrayBuffer(parts[0]);
        const ciphertext = base64ToArrayBuffer(parts[1]);
        const keyBytes = Uint8Array.from(atob(session.cachedDerivedKey), c => c.charCodeAt(0));
        const aesKey = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']);
        const buf = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, aesKey, ciphertext);
        const freshVault = JSON.parse(new TextDecoder().decode(buf));

        vaultKeys = { ...vaultKeys, ...freshVault };
        lastVaultRefreshTime = Date.now();
        chrome.storage.session.set({ cachedVaultKeys: vaultKeys });
        const found = !!freshVault[token];
        console.log('[getShareKey] vault 재fetch 완료, key 있음:', found,
            '| vault 키 수:', Object.keys(freshVault).length,
            '| 찾는 token:', token.slice(0, 8));
        if (freshVault[token]) return freshVault[token];

        // vault에 없을 때: records 배열의 레거시 encryption_key 폴백
        const fallbackRec = records.find(r => r.share_token === token);
        if (fallbackRec?.encryption_key) {
            console.log('[getShareKey] vault 미등록 → encryption_key 폴백 사용');
            return fallbackRec.encryption_key;
        }
        return '';
    } catch (e) {
        console.warn('[getShareKey] vault 복호화 실패 (cachedDerivedKey 무효 가능성):', e.message);
        // cachedDerivedKey가 무효(PIN 변경/새 salt) → 세션 초기화하여 PIN 재입력 강제
        chrome.storage.session.remove(['cachedVaultKeys', 'cachedDerivedKey']);
        return 'PIN_REQUIRED';
    }
}

// Vault 갱신: fetchRecords 호출 시 새로 추가된 공유 DB 키를 반영 (30초 throttle)
async function refreshVaultKeys() {
    if (!pinAuthenticated || !currentUser?.uid) return;
    const THROTTLE_MS = 30 * 1000; // 30초
    if (Date.now() - lastVaultRefreshTime < THROTTLE_MS) return;
    // 동시 호출 방지: 이미 실행 중이면 즉시 반환 (throttle과 별도로 async race 방어)
    if (_vaultRefreshInProgress) return;
    _vaultRefreshInProgress = true;
    try {
        const session = await new Promise(resolve => {
            chrome.storage.session.get(['cachedDerivedKey'], result => resolve(result));
        });
        if (!session.cachedDerivedKey) return;

        const res = await fetch(`${API_BASE}/users/vault/${currentUser.uid}`, { headers: authHeaders() });
        if (!res.ok) return; // 네트워크/인증 오류 — 조용히 skip
        const { encrypted_vault } = await res.json();
        if (!encrypted_vault) return;

        const parts = encrypted_vault.split(':');
        if (parts.length !== 2) return;
        const iv = base64ToArrayBuffer(parts[0]);
        const ciphertext = base64ToArrayBuffer(parts[1]);

        let freshVault;
        try {
            const keyBytes = Uint8Array.from(atob(session.cachedDerivedKey), c => c.charCodeAt(0));
            const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']);
            const buf = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, key, ciphertext);
            freshVault = JSON.parse(new TextDecoder().decode(buf));
        } catch (_) {
            // 복호화 실패 = 모바일에서 PIN 변경 또는 vault 재초기화로 salt가 바뀐 것
            // cachedDerivedKey가 무효하므로 세션 캐시를 지우고 PIN 재입력 유도
            console.warn('[refreshVaultKeys] 복호화 실패 — vault 키 변경 감지, PIN 재입력 필요');
            vaultKeys = {};
            pinAuthenticated = false;
            chrome.storage.session.remove(['cachedVaultKeys', 'cachedDerivedKey']);
            showPinView();
            return;
        }

        const merged = { ...vaultKeys, ...freshVault };
        vaultKeys = merged;
        lastVaultRefreshTime = Date.now();
        chrome.storage.session.set({ cachedVaultKeys: merged });
        console.log('[refreshVaultKeys] vault 갱신 완료, 토큰 수:', Object.keys(merged).length);
    } catch (e) {
        console.warn('[refreshVaultKeys] 갱신 실패 (무시):', e);
    } finally {
        _vaultRefreshInProgress = false;
    }
}

// PKCS7 패딩 제거 유틸
function removePkcs7(bytes) {
    const padLen = bytes[bytes.length - 1];
    if (padLen < 1 || padLen > 16) return bytes;
    return bytes.slice(0, bytes.length - padLen);
}

// [Security] Phase 1-B: PBKDF2로 PIN → Vault 키 파생 (100,000 iterations, SHA-256)
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

// Vault 복호화 — PBKDF2(신규) → raw PIN pad(레거시 폴백) 순으로 시도
// 성공 시 파싱된 Vault 객체 반환, 실패 시 null
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
        } catch (e) {
        }
        return null; // 신규 Vault는 PBKDF2만 시도 — 실패 = PIN 불일치
    }


    // 2차 시도: 레거시 raw PIN pad (salt 없는 구버전 Vault)
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

// encrypted_blob 복호화 — 성공 시 draftData 객체 반환, 실패 시 null
async function decryptBlob(encryptedBlobStr, encryptionKey) {
    try {
        const parts = encryptedBlobStr.split(':');
        if (parts.length !== 2) return null;

        const iv = base64ToArrayBuffer(parts[0]);        // 16 bytes
        const ciphertext = base64ToArrayBuffer(parts[1]);

        // Flutter: encrypt.Key.fromUtf8(encryptionKey.padRight(32).substring(0, 32))
        // 문자 기준 padEnd/substring 후 UTF-8 인코딩 → 멀티바이트 문자 포함 시 32바이트 초과 가능
        // → 32바이트 고정 버퍼에 복사하여 AES-256 키 길이 보장 (space 0x20으로 패딩)
        const keyStr = encryptionKey.padEnd(32).substring(0, 32);
        const rawKeyBytes = new TextEncoder().encode(keyStr);
        const keyBytes = new Uint8Array(32).fill(0x20); // space padding
        keyBytes.set(rawKeyBytes.subarray(0, 32));

        const cryptoKey = await crypto.subtle.importKey(
            'raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']
        );

        const decryptedBuffer = await crypto.subtle.decrypt(
            { name: 'AES-CBC', iv }, cryptoKey, ciphertext
        );

        const json = new TextDecoder().decode(decryptedBuffer);
        return JSON.parse(json);
    } catch (e) {
        console.error('Blob decryption failed:', e);
        return null;
    }
}

// Base64 ↔ ArrayBuffer 유틸
function base64ToArrayBuffer(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes.buffer;
}

// PIN Dots UI 업데이트
function updatePinDots() {
    const dots = pinDots.querySelectorAll('.pin-dot');
    dots.forEach((dot, i) => {
        dot.classList.remove('filled', 'error', 'success');
        if (i < pinInput.length) {
            dot.classList.add('filled');
        }
    });
}

// PIN 키패드 이벤트 핸들링
pinKeypad.addEventListener('click', async (e) => {
    const btn = e.target.closest('.pin-key');
    // 잠금 시간 체크
    if (pinLockUntil > Date.now()) {
        const remaining = Math.ceil((pinLockUntil - Date.now()) / 1000);
        pinError.textContent = `PIN 5회 실패. ${remaining}초 후 다시 시도해주세요.`;
        pinError.classList.remove('hidden');
        return;
    }
    if (!btn || btn.disabled || pinLocked) return;

    const key = btn.dataset.key;

    if (key === 'delete') {
        if (pinInput.length > 0) {
            pinInput = pinInput.slice(0, -1);
            pinError.classList.add('hidden');
            updatePinDots();
        }
        return;
    }

    if (pinInput.length >= 4) return;

    pinInput += key;
    updatePinDots();

    // 4자리 완성 → 자동 검증
    if (pinInput.length === 4) {
        pinLocked = true;

        const vault = await verifyPinWithVault(pinInput);

        if (vault !== null) {
            // ✅ 성공: Vault 키 메모리 저장 → 초록색 표시 → 메인 진입
            vaultKeys = vault;
            pinAuthenticated = true;

            const dots = pinDots.querySelectorAll('.pin-dot');
            dots.forEach(d => {
                d.classList.remove('filled');
                d.classList.add('success');
            });

            // 세션 스토리지에 복호화된 vaultKeys 저장 (PIN 자체는 저장하지 않음)
            // chrome.storage.session은 브라우저 종료 시 자동 소멸 → DevTools에서 읽을 수 없음
            chrome.storage.session.set({ cachedVaultKeys: vault });

            setTimeout(() => {
                showMainView();
                fetchRecords();
                fetchHistory();
                setupRealtimeSync();
            }, 500);
        } else {
            // ❌ 실패: 빨간색 + 흔들기 → 초기화
            pinFailCount++;
            const dots = pinDots.querySelectorAll('.pin-dot');
            dots.forEach(d => {
                d.classList.remove('filled');
                d.classList.add('error');
            });

            if (pinFailCount >= 5) {
                pinLockUntil = Date.now() + 30 * 1000;
                pinFailCount = 0;
                pinError.textContent = 'PIN 5회 실패. 30초 후 다시 시도해주세요.';
                // 30초 후 에러 메시지 자동 업데이트
                const lockInterval = setInterval(() => {
                    const remaining = Math.ceil((pinLockUntil - Date.now()) / 1000);
                    if (remaining <= 0) {
                        clearInterval(lockInterval);
                        pinError.classList.add('hidden');
                    } else {
                        pinError.textContent = `PIN 5회 실패. ${remaining}초 후 다시 시도해주세요.`;
                    }
                }, 1000);
            } else {
                pinError.textContent = `PIN이 맞지 않아요. (${pinFailCount}/5회)`;
            }
            pinError.classList.remove('hidden');

            setTimeout(() => {
                pinInput = '';
                pinLocked = false;
                updatePinDots();
            }, 600);
        }
    }
});

// PIN 분실 도움말 모달
btnForgotPin.addEventListener('click', () => {
    pinHelpModal.classList.remove('hidden');
});

btnClosePinHelp.addEventListener('click', () => {
    pinHelpModal.classList.add('hidden');
});

// 모달 외부 클릭 시 닫기
pinHelpModal.addEventListener('click', (e) => {
    if (e.target === pinHelpModal) {
        pinHelpModal.classList.add('hidden');
    }
});
