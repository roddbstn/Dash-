// ==============================================
// sidepanel.js — Dash Extension Main Logic
// Magazine Fill 전략: Draft → Magazine → Inject
// ==============================================

// ===== 설정 =====
const API_BASE = 'https://dash.qpon/api';
const FIREBASE_API_KEY = 'AIzaSyDd8anDd8ASoz9zr6oZ_DUwPQMiELVSxjE'; // From mobile google-services.json

// Google OAuth — launchWebAuthFlow (Chrome / Edge 공통 동작)
// Firebase 프로젝트(dash-7cdea)의 Web client ID (client_type: 3, google-services.json 기준)
const GOOGLE_CLIENT_ID = '803548605147-8p75oeqvre7frce70lkl59akqung8kd7.apps.googleusercontent.com';
const OAUTH_REDIRECT_URI = `https://${chrome.runtime.id}.chromiumapp.org`;

async function getGoogleAccessToken(interactive) {
    const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    authUrl.searchParams.set('client_id', GOOGLE_CLIENT_ID);
    authUrl.searchParams.set('redirect_uri', OAUTH_REDIRECT_URI);
    authUrl.searchParams.set('response_type', 'token');
    authUrl.searchParams.set('scope', 'https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile');
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

// chrome.identity.getAuthToken — 팝업 없이 로그인 (Chrome 전용, Edge도 지원)
async function getGoogleTokenViaAuthToken() {
    return new Promise((resolve, reject) => {
        chrome.identity.getAuthToken({ interactive: true }, (token) => {
            if (chrome.runtime.lastError || !token) {
                reject(new Error(chrome.runtime.lastError?.message || 'getAuthToken 실패'));
            } else {
                resolve(token);
            }
        });
    });
}

// 구글 액세스 토큰을 Firebase ID Token으로 교환 (백엔드 verifyIdToken 대응)
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

// 팝업 없이 조용히 토큰 갱신 (SSE 재연결, 세션 복원 시 사용)
// launchWebAuthFlow(prompt=none)으로 Firebase Web client 기준 토큰 갱신
async function getFreshTokenSilent() {
    const googleToken = await getGoogleAccessToken(false); // interactive: false
    return await getFirebaseIdToken(googleToken);
}
async function handleGoogleLogin(googleToken) {
    // 1. 구글 유저 정보 가져오기 (이메일, 사진 등)
    const response = await fetch('https://www.googleapis.com/oauth2/v1/userinfo?alt=json', {
        headers: { Authorization: `Bearer ${googleToken}` }
    });
    const userInfo = await response.json();

    // 2. 구글 액세스 토큰을 Firebase ID Token으로 교환
    const idToken = await getFirebaseIdToken(googleToken);
    currentOAuthToken = idToken; // 이제부터 모든 API 요청에 Firebase ID Token 사용

    const firebaseUid = userInfo.id;

    currentUser = {
        uid: firebaseUid,
        email: userInfo.email,
        name: userInfo.name || userInfo.email,
        photo: userInfo.picture
    };

    chrome.storage.local.set({ dashUser: currentUser });
    chrome.storage.session.set({ cachedOAuthToken: idToken });

    await checkPinAndProceed();
}

// ===== 상태 관리 =====
let currentUser = null;   // { uid, email }
let currentOAuthToken = null; // Google OAuth 토큰 (API 인증용)
let records = [];          // 서버에서 가져온 기록 목록
let historyRecords = [];   // 기입 완료(Injected) 기록
let selectedRecordId = null; // 현재 선택된 기록 ID
let currentMainTab = 'pending'; // 'pending' | 'history'

function authHeaders() {
    if (currentOAuthToken) return { 'Authorization': `Bearer ${currentOAuthToken}` };
    return {};
}

// ===== DOM 참조 =====
const loginView = document.getElementById('login-view');
const pinView = document.getElementById('pin-view');
const mainView = document.getElementById('main-view');
const resultView = document.getElementById('result-view');
const btnGoogleLogin = document.getElementById('btn-google-login');
const btnLogout = document.getElementById('btn-logout');
const btnRefresh = document.getElementById('btn-refresh');

// 탭 클릭 이벤트 (MV3 CSP: inline onclick 대신 addEventListener 사용)
document.getElementById('tab-pending').addEventListener('click', () => switchMainTab('pending'));
document.getElementById('tab-history').addEventListener('click', () => switchMainTab('history'));
const btnInject = document.getElementById('btn-inject');
const btnBackToList = document.getElementById('btn-back-to-list');
const userEmailEl = document.getElementById('user-email');
const profilePicEl = document.getElementById('profile-pic');
const statusBar = document.getElementById('status-bar');
const recordsContainer = document.getElementById('records-container');
const emptyState = document.getElementById('empty-state');
const actionBar = document.getElementById('action-bar');

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

// ==============================================
// 1. 인증 (간소화된 구글 로그인)
// ==============================================

// 확장 프로그램에서의 로그인은 chrome.identity API를 사용합니다.
// Firebase SDK 대신, 서버에 토큰을 보내 검증하는 방식을 사용합니다.
// MVP 단계에서는 이메일 기반 간소화 로그인을 구현합니다.

btnGoogleLogin.addEventListener('click', async () => {
    btnGoogleLogin.disabled = true;
    const contentsSpan = btnGoogleLogin.querySelector('.gsi-material-button-contents');
    if (contentsSpan) contentsSpan.textContent = '로그인 중...';

    try {
        // launchWebAuthFlow로 Firebase Web client ID 기준 액세스 토큰 획득
        const token = await getGoogleAccessToken(true);
        await handleGoogleLogin(token);
    } catch (error) {
        console.error('Google 로그인 실패:', error);
        btnGoogleLogin.disabled = false;
        if (contentsSpan) contentsSpan.textContent = 'Google 계정으로 로그인';
        showLoginError(error.message);
    }
});

// "다른 계정으로 로그인" — launchWebAuthFlow로 계정 선택 창 열기
const btnOtherAccount = document.getElementById('btn-other-account');
btnOtherAccount.addEventListener('click', async () => {
    btnOtherAccount.disabled = true;
    btnOtherAccount.textContent = '로그인 중...';
    hideLoginError();

    try {
        const token = await getGoogleAccessToken(true);
        await handleGoogleLogin(token);
    } catch (error) {
        console.error('다른 계정 로그인 실패:', error);
        btnOtherAccount.disabled = false;
        btnOtherAccount.textContent = '다른 계정으로 로그인';
        showLoginError(error.message);
    }
});

function performLogout() {
    currentUser = null;
    selectedRecordId = null;
    records = [];
    vaultKeys = {};
    pinAuthenticated = false;
    chrome.storage.local.remove(['dashUser']);
    chrome.storage.session.remove(['cachedVaultKeys', 'cachedOAuthToken']);
    pinInput = '';

    // 버튼 상태 초기화
    btnGoogleLogin.disabled = false;
    const contentsSpan = btnGoogleLogin.querySelector('.gsi-material-button-contents');
    if (contentsSpan) contentsSpan.textContent = 'Google 계정으로 로그인';
    btnOtherAccount.disabled = false;
    btnOtherAccount.textContent = '다른 계정으로 로그인';

    showLoginView();
}

profilePicEl.addEventListener('click', () => {
    if (!confirm('로그아웃하시겠어요?')) return;
    performLogout();
});

// 푸터 로그아웃 버튼
const btnFooterLogout = document.getElementById('btn-footer-logout');
btnFooterLogout.addEventListener('click', () => {
    if (!confirm('로그아웃하시겠어요?')) return;
    performLogout();
});

// ==============================================
// 2. 뷰 전환
// ==============================================

function showLoginView() {
    loginView.classList.remove('hidden');
    pinView.classList.add('hidden');
    mainView.classList.add('hidden');
    resultView.classList.add('hidden');
    btnGoogleLogin.disabled = false;
    const contentsSpan = btnGoogleLogin.querySelector('.gsi-material-button-contents');
    if (contentsSpan) contentsSpan.textContent = 'Google 계정으로 로그인';
    btnOtherAccount.disabled = false;
    btnOtherAccount.textContent = '다른 계정으로 로그인';
    hideLoginError();
}

function showLoginError(msg) {
    let el = document.getElementById('login-error-msg');
    if (!el) {
        el = document.createElement('p');
        el.id = 'login-error-msg';
        el.style.cssText = 'margin-top:12px;font-size:12px;color:#DC2626;text-align:center;line-height:1.5;padding:0 8px;';
        btnGoogleLogin.insertAdjacentElement('afterend', el);
    }
    const isCancelled = msg && (msg.includes('cancel') || msg.includes('취소') || msg.includes('closed'));
    el.textContent = isCancelled
        ? '로그인 창이 닫혔습니다. 다시 시도해주세요.'
        : 'Google 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.';
    el.style.display = 'block';
}

function hideLoginError() {
    const el = document.getElementById('login-error-msg');
    if (el) el.style.display = 'none';
}

function showPinView() {
    loginView.classList.add('hidden');
    pinView.classList.remove('hidden');
    mainView.classList.add('hidden');
    resultView.classList.add('hidden');
    // PIN 입력 초기화
    pinInput = '';
    pinLocked = false;
    updatePinDots();
    pinError.classList.add('hidden');
}

function showMainView() {
    loginView.classList.add('hidden');
    pinView.classList.add('hidden');
    mainView.classList.remove('hidden');
    resultView.classList.add('hidden');
    if (currentUser?.photo) {
        profilePicEl.src = currentUser.photo;
        profilePicEl.title = currentUser.email || '';
        profilePicEl.classList.remove('hidden');
    }
}

function showResultView() {
    loginView.classList.add('hidden');
    pinView.classList.add('hidden');
    mainView.classList.add('hidden');
    resultView.classList.remove('hidden');
}

function switchMainTab(tab) {
    currentMainTab = tab;
    document.getElementById('tab-pending').classList.toggle('active', tab === 'pending');
    document.getElementById('tab-history').classList.toggle('active', tab === 'history');
    document.getElementById('tab-content-pending').classList.toggle('hidden', tab !== 'pending');
    document.getElementById('tab-content-history').classList.toggle('hidden', tab !== 'history');

    if (tab === 'history') {
        fetchHistory();
    }
}

// ==============================================
// 2.5. PIN 인증 로직
// ==============================================

// PIN 입력 후 서버 Vault와 검증하는 핵심 함수
async function checkPinAndProceed() {
    // 1. 세션 스토리지에 캐시된 vaultKeys 확인 (브라우저 닫기 전까지 재입력 불필요)
    //    PIN 자체는 저장하지 않음 — 복호화된 키만 세션에 보관
    const session = await new Promise(resolve => {
        chrome.storage.session.get(['cachedVaultKeys'], result => resolve(result));
    });
    if (session.cachedVaultKeys && Object.keys(session.cachedVaultKeys).length > 0) {
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

// 서버에 Vault가 존재하는지 확인
async function checkVaultExists() {
    if (!currentUser?.uid) return false;
    try {
        const res = await fetch(`${API_BASE}/users/vault/${currentUser.uid}`, { headers: authHeaders() });
        return res.ok;
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
        if (!encrypted_vault) return null;

        return await attemptDecryptVault(pin, encrypted_vault, salt);
    } catch (e) {
        console.error('PIN verification failed:', e);
        return null;
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
            return JSON.parse(new TextDecoder().decode(buf));
        } catch {}
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
        const keyStr = encryptionKey.padEnd(32).substring(0, 32);
        const keyBytes = new TextEncoder().encode(keyStr);

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
            const dots = pinDots.querySelectorAll('.pin-dot');
            dots.forEach(d => {
                d.classList.remove('filled');
                d.classList.add('error');
            });
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

// ==============================================
// 3. 서버에서 기록 가져오기 (Magazine)
// ==============================================

async function fetchRecords() {
    setStatus('loading', '기록을 불러오는 중...');
    showSkeleton();

    try {
        const userEmail = currentUser?.email;
        if (!userEmail) throw new Error('로그인이 필요합니다.');

        const res = await fetch(`${API_BASE}/records/ready?email=${encodeURIComponent(userEmail)}`, { headers: authHeaders() });
        if (!res.ok) throw new Error(`서버 오류: ${res.status}`);

        const rawRecords = await res.json();

        // encrypted_blob을 vaultKeys로 복호화 (없으면 레거시 encryption_key 폴백)
        records = await Promise.all(rawRecords.map(async (record) => {
            const decryptKey = (record.share_token && vaultKeys[record.share_token])
                || record.encryption_key || null;
            if (record.encrypted_blob && decryptKey) {
                const decrypted = await decryptBlob(record.encrypted_blob, decryptKey);
                if (decrypted) {
                    return {
                        ...record,
                        service_description: decrypted.serviceDescription || decrypted.service_description || '',
                        agent_opinion: decrypted.agentOpinion || decrypted.agent_opinion || '',
                    };
                }
            }
            return record;
        }));

        const selectBar = document.getElementById('selection-bar');
        const pendingCount = records.filter(r => r.status !== 'Injected').length;
        if (pendingCount === 0) {
            recordsContainer.innerHTML = '';
            emptyState.classList.remove('hidden');
            actionBar.classList.add('hidden');
            if (selectBar) selectBar.classList.add('hidden');
            hidePinSetupBanner();
            setStatus('success', '모든 기록이 처리되었습니다');
        } else {
            emptyState.classList.add('hidden');
            actionBar.classList.remove('hidden');
            renderRecords();
            // PIN 미인증 상태 → 민감 내용이 복호화 안 된 상태
            // → 모바일에서 PIN 설정 안내 배너 표시, 선택 버튼 숨김
            if (!pinAuthenticated) {
                if (selectBar) selectBar.classList.add('hidden');
                showPinSetupBanner();
                setStatus('info', '모바일에서 PIN을 설정하면 내용을 볼 수 있어요');
            } else {
                if (selectBar) selectBar.classList.remove('hidden');
                hidePinSetupBanner();
                setStatus('success', '삽입할 DB를 선택해주세요');
            }
        }

    } catch (error) {
        console.error('기록 패치 오류:', error);
        recordsContainer.innerHTML = '';
        emptyState.classList.remove('hidden');
        setStatus('error', '서버 연결에 실패했어요. 새로고침해 보세요.');
    }
}

// ==============================================
// 3-1. 이전 기록 (Injected) 조회 및 렌더링
// ==============================================

async function fetchHistory() {
    const historyContainer = document.getElementById('history-container');
    const historyEmpty = document.getElementById('history-empty-state');
    historyContainer.innerHTML = '<div style="padding:20px 16px;color:#ADB5BD;font-size:13px;text-align:center;">불러오는 중...</div>';
    historyEmpty.classList.add('hidden');

    try {
        const email = currentUser?.email;
        if (!email) return;

        // 토큰 만료 방지: API 호출 전 조용히 갱신 시도
        try {
            const freshToken = await getFreshTokenSilent();
            currentOAuthToken = freshToken;
        } catch (e) {
            console.warn('[History] 토큰 갱신 실패, 기존 토큰 사용:', e.message);
        }

        const res = await fetch(`${API_BASE}/records/history?email=${encodeURIComponent(email)}`, { headers: authHeaders() });
        if (!res.ok) throw new Error(`서버 오류: ${res.status}`);
        historyRecords = await res.json();

        // 복호화 (vaultKeys 또는 레거시 encryption_key 폴백)
        historyRecords = await Promise.all(historyRecords.map(async (record) => {
            const decryptKey = (record.share_token && vaultKeys[record.share_token])
                || record.encryption_key || null;
            if (record.encrypted_blob && decryptKey) {
                const decrypted = await decryptBlob(record.encrypted_blob, decryptKey);
                if (decrypted) {
                    return {
                        ...record,
                        service_description: decrypted.serviceDescription || decrypted.service_description || '',
                        agent_opinion: decrypted.agentOpinion || decrypted.agent_opinion || '',
                    };
                }
            }
            return record;
        }));

        renderHistory();
    } catch (e) {
        historyContainer.innerHTML = '<div style="padding:20px 16px;color:#ADB5BD;font-size:13px;text-align:center;">불러오기 실패. 새로고침해 보세요.</div>';
    }
}

function renderHistory() {
    const container = document.getElementById('history-container');
    const emptyEl = document.getElementById('history-empty-state');
    container.innerHTML = '';

    if (historyRecords.length === 0) {
        emptyEl.classList.remove('hidden');
        return;
    }
    emptyEl.classList.add('hidden');

    const dayNames = ['일', '월', '화', '수', '목', '금', '토'];

    // 날짜별 그룹핑 (updated_at 기준)
    const groups = {};
    historyRecords.forEach(record => {
        const rawDate = record.updated_at || record.created_at || '';
        const dt = rawDate ? new Date(rawDate.endsWith('Z') ? rawDate : rawDate + 'Z') : new Date();
        const dayName = dayNames[dt.getDay()];
        const dateKey = `${dt.getFullYear()}.${dt.getMonth() + 1}.${dt.getDate()} (${dayName})`;
        if (!groups[dateKey]) groups[dateKey] = [];
        groups[dateKey].push(record);
    });

    Object.entries(groups).forEach(([dateLabel, groupRecords]) => {
        // 날짜 헤더
        const header = document.createElement('div');
        header.style.cssText = 'padding:12px 16px 6px;font-size:11px;font-weight:700;color:#8B95A1;letter-spacing:0.3px;';
        header.textContent = dateLabel;
        container.appendChild(header);

        groupRecords.forEach(record => {
            // 제공일시 포맷
            let dateTimeStr = '';
            if (record.start_time && record.end_time) {
                const start = new Date(record.start_time.replace(' ', 'T'));
                const end = new Date(record.end_time.replace(' ', 'T'));
                const startDay = dayNames[start.getDay()];
                const startPart = `${start.getMonth() + 1}.${start.getDate()} (${startDay})`;
                const startT = `${String(start.getHours()).padStart(2,'0')}:${String(start.getMinutes()).padStart(2,'0')}`;
                const endT = `${String(end.getHours()).padStart(2,'0')}:${String(end.getMinutes()).padStart(2,'0')}`;
                dateTimeStr = `${startPart} ${startT} ~ ${endT}`;
            }

            const card = document.createElement('div');
            card.className = 'record-card';
            card.style.cssText = 'opacity:0.85;';
            const dropdownId = `hist-dropdown-${record.id}`;
            card.innerHTML = `
                <div class="record-card-header">
                    <div class="record-card-header-left">
                        <span class="record-case-name">${record.case_name || '미지정'} 아동 사례</span>
                        <span class="record-dong">${record.dong || ''}</span>
                    </div>
                    <span class="record-status-badge badge-injected">${(() => { const d = record.updated_at ? new Date(record.updated_at.replace(' ', 'T') + 'Z') : null; const t = d && !isNaN(d) ? `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')} ` : ''; return t + '기입 완료'; })()}</span>
                </div>
                <div class="record-info-list">
                    <div class="record-info-row"><span class="info-label">제공일시</span><span class="info-value">${dateTimeStr || '-'}</span></div>
                    <div class="record-info-row"><span class="info-label">제공서비스</span><span class="info-value">${(record.service_category && record.service_name) ? record.service_category + ' :: ' + record.service_name : (record.service_name || '-')}</span></div>
                    <div class="record-info-row"><span class="info-label">제공방법</span><span class="info-value">${record.method || '-'}</span></div>
                </div>
                <div class="record-dropdown-toggle" data-target="${dropdownId}">
                    <div style="flex:1;"></div>
                    <span class="dropdown-label">상세 보기</span>
                    <svg class="dropdown-arrow" width="12" height="12" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M2 4L6 8L10 4" stroke="#ADB5BD" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
                </div>
                <div class="record-dropdown-content hidden" id="${dropdownId}">
                    <div class="record-info-list" style="margin-bottom:12px;">
                        <div class="record-info-row"><span class="info-label">대상자</span><span class="info-value">${record.target || '-'}</span></div>
                        <div class="record-info-row"><span class="info-label">제공구분</span><span class="info-value">${record.provision_type || '-'}</span></div>
                        <div class="record-info-row"><span class="info-label">제공방법</span><span class="info-value">${record.method || '-'}</span></div>
                        <div class="record-info-row"><span class="info-label">서비스제공유형</span><span class="info-value">${record.service_type === '아보전' ? '아보전서비스' : (record.service_type || '-')}</span></div>
                        <div class="record-info-row"><span class="info-label">제공장소</span><span class="info-value">${record.location || '-'}</span></div>
                        <div class="record-info-row"><span class="info-label">서비스제공횟수</span><span class="info-value">${record.service_count != null ? record.service_count + '회' : '-'}</span></div>
                        <div class="record-info-row"><span class="info-label">이동소요시간</span><span class="info-value">${record.travel_time != null ? record.travel_time + '분' : '-'}</span></div>
                    </div>
                    <div style="font-weight:700;color:#4e5968;font-size:13px;margin-bottom:6px;">서비스 내용</div>
                    <div class="dropdown-text" style="background:transparent;padding:0;margin-bottom:12px;">${record.service_description || '(내용 없음)'}</div>
                    <div style="font-weight:700;color:#4e5968;font-size:13px;margin-bottom:6px;">상담원 소견</div>
                    <div class="dropdown-text" style="background:transparent;padding:0;">${record.agent_opinion || '(소견 없음)'}</div>
                </div>
                <div class="record-card-footer" style="display:flex;gap:8px;margin-top:12px;padding-top:12px;">
                    <button class="btn-reinject" data-id="${record.id}">⚡ 재기입</button>
                </div>
            `;

            // 드롭다운 토글
            card.querySelector('.record-dropdown-toggle').addEventListener('click', (e) => {
                e.stopPropagation();
                const content = card.querySelector(`#${dropdownId}`);
                const arrow = card.querySelector('.dropdown-arrow');
                const label = card.querySelector('.dropdown-label');
                content.classList.toggle('hidden');
                const isHidden = content.classList.contains('hidden');
                arrow.classList.toggle('open', !isHidden);
                label.textContent = isHidden ? '상세 보기' : '접기';
            });

            // 재기입 버튼
            card.querySelector('.btn-reinject').addEventListener('click', (e) => {
                e.stopPropagation();
                reinjectRecord(record);
            });

            container.appendChild(card);
        });
    });
}

async function reinjectRecord(record) {
    const tabs = await chrome.tabs.query({ url: ["*://localhost:*/*", "*://ncads.go.kr/*", "*://*.ncads.go.kr/*"] });
    const potentialTabs = tabs.filter(t => !t.url.includes('AnySignPlus'));
    let targetTab = null;
    const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (activeTab && potentialTabs.some(t => t.id === activeTab.id)) {
        targetTab = activeTab;
    } else {
        for (const tab of potentialTabs) {
            try {
                const pong = await new Promise((resolve, reject) => {
                    chrome.tabs.sendMessage(tab.id, { action: 'PING' }, (res) => {
                        if (chrome.runtime.lastError || !res) reject(); else resolve(res);
                    });
                });
                if (pong) { targetTab = tab; break; }
            } catch (e) { continue; }
        }
    }

    if (!targetTab) { alert('아동학대정보시스템 창을 찾지 못했어요.'); return; }

    const CFG = window.DBAuto?.Config || {};
    const meansMap = { '전화': 'A', '내방': 'B', '방문': 'C' };
    const locMap = { '기관내': 'A', '아동가정': 'B', '유관기관': 'C', '기타': 'X' };
    const svcMap = CFG.SERVICE_MAP || {};

    let dateTime_val = '';
    if (record.start_time && record.end_time) {
        const start = new Date(record.start_time.replace(' ', 'T'));
        const end = new Date(record.end_time.replace(' ', 'T'));
        const datePart = `${start.getFullYear()}-${String(start.getMonth()+1).padStart(2,'0')}-${String(start.getDate()).padStart(2,'0')}`;
        dateTime_val = `${datePart} ${String(start.getHours()).padStart(2,'0')}:${String(start.getMinutes()).padStart(2,'0')}~${String(end.getHours()).padStart(2,'0')}:${String(end.getMinutes()).padStart(2,'0')}`;
    }

    const fillData = {
        id: `dash-${record.id}`,
        provCd_val: record.provision_type || '',
        provTyCd_val: record.service_type || '',
        svcClassDetailCd_val: svcMap[record.service_name] || record.service_name || '',
        provMeansCd_val: meansMap[record.method] || record.method || '',
        loc_val: locMap[record.location] || record.location || '',
        dateTime_val,
        mvmnReqreHr_val: record.travel_time || '0',
        desc_val: record.service_description || '',
        opn_val: record.agent_opinion || '',
        cnt_val: record.service_count || 1,
        recipient_fullVal: [],
        pic_fullVal: [],
    };

    chrome.tabs.sendMessage(targetTab.id, { action: 'START_AUTO_FILL', data: fillData }, (res) => {
        if (chrome.runtime.lastError) {
            alert('재기입에 실패했습니다. 시스템 창을 새로고침한 후 다시 시도해 주세요.');
        } else {
            showToastNotification('재기입 완료!');
        }
    });
}

// PIN 설정 안내 배너 (Vault 없는데 기록이 있을 때)
function showPinSetupBanner() {
    let banner = document.getElementById('pin-setup-banner');
    if (!banner) {
        banner = document.createElement('div');
        banner.id = 'pin-setup-banner';
        banner.style.cssText = [
            'margin:12px 16px 4px;',
            'background:#FEF9C3;border:1px solid #FDE68A;',
            'border-radius:12px;padding:12px 14px;',
        ].join('');
        banner.innerHTML = `
            <div style="display:flex;align-items:flex-start;gap:8px;">
                <span style="font-size:16px;flex-shrink:0;">🔐</span>
                <div>
                    <p style="margin:0;font-size:13px;font-weight:700;color:#92400E;line-height:1.4;">
                        기록 내용을 보려면 PIN 설정이 필요해요
                    </p>
                    <p style="margin:4px 0 0;font-size:12px;color:#78350F;line-height:1.55;">
                        아직 PIN이 설정되지 않아 민감 내용이 잠겨 있습니다.<br>
                        아래 순서대로 모바일 앱에서 설정하면 바로 연동됩니다.
                    </p>
                    <ol style="margin:8px 0 0;padding-left:18px;font-size:12px;color:#78350F;line-height:1.8;">
                        <li>Dash 앱 실행 → 하단 <strong>프로필</strong> 탭</li>
                        <li><strong>보안 PIN 확인</strong> → PIN 생성</li>
                        <li>설정 완료 후 이 확장 프로그램 재로그인</li>
                    </ol>
                </div>
            </div>`;
        recordsContainer.insertAdjacentElement('beforebegin', banner);
    }
    banner.style.display = 'block';
}

function hidePinSetupBanner() {
    const banner = document.getElementById('pin-setup-banner');
    if (banner) banner.style.display = 'none';
}

function exitSelectionMode() {
    isSelectionMode = false;
    selectedForDelete.clear();
    const toggleBtn = document.getElementById('toggle-select-mode-btn');
    const cancelBtn = document.getElementById('cancel-select-btn');
    const selectText = document.getElementById('select-mode-text');
    
    if (toggleBtn) toggleBtn.classList.remove('delete-mode');
    if (selectText) selectText.textContent = '선택';
    if (cancelBtn) cancelBtn.classList.add('hidden');
    
    document.querySelectorAll('.record-card').forEach(c => {
         c.classList.remove('selection-mode', 'selected-for-delete');
    });
}

function setupSelectionLogic() {
    const toggleBtn = document.getElementById('toggle-select-mode-btn');
    const cancelBtn = document.getElementById('cancel-select-btn');
    const selectText = document.getElementById('select-mode-text');
    
    if (!toggleBtn) return;
    
    toggleBtn.addEventListener('click', async () => {
        if (!isSelectionMode) {
            // Enter selection mode
            isSelectionMode = true;
            selectedForDelete.clear();
            toggleBtn.classList.add('delete-mode');
            selectText.textContent = '삭제';
            cancelBtn.classList.remove('hidden');
            
            document.querySelectorAll('.record-card').forEach(c => {
                c.classList.add('selection-mode');
                c.classList.remove('selected-for-delete');
            });
        } else {
            // We are IN selection mode and user clicked "삭제"
            if (selectedForDelete.size === 0) {
                alert('삭제할 DB를 선택해주세요.');
                return;
            }
            if (confirm(`${selectedForDelete.size}개의 DB를 삭제하시겠어요? (삭제한 DB는 복구되지 않아요)`)) {
                try {
                    setStatus('loading', '삭제 중입니다...');
                    for (const id of selectedForDelete.keys()) {
                        await fetch(`${API_BASE}/records/id/${id}`, { method: 'DELETE', headers: authHeaders() });
                    }
                    exitSelectionMode();
                    fetchRecords(); 
                } catch (e) {
                    console.error('Delete multiple failed:', e);
                    setStatus('error', '삭제 실패. 다시 시도해 주세요.');
                }
            }
        }
    });
    
    cancelBtn.addEventListener('click', () => {
        exitSelectionMode();
    });
}

function showSkeleton() {
    recordsContainer.innerHTML = '';
    for (let i = 0; i < 3; i++) {
        const sk = document.createElement('div');
        sk.className = 'skeleton skeleton-card';
        recordsContainer.appendChild(sk);
    }
}

// ==============================================
// 4. 기록 카드 렌더링
// ==============================================

function renderRecords() {
    recordsContainer.innerHTML = '';
    const dayNames = ['일', '월', '화', '수', '목', '금', '토'];

    const pendingRecords = records.filter(record => record.status !== 'Injected');
    pendingRecords.forEach(record => {
        const card = document.createElement('div');
        card.className = `record-card ${record.id === selectedRecordId ? 'selected' : ''}`;
        card.dataset.id = record.id;

        // 날짜/시간 포맷 (요일 포함, 다른 날짜 대응)
        let dateTimeStr = '';
        if (record.start_time && record.end_time) {
            const cleanStart = record.start_time.replace(' ', 'T');
            const cleanEnd = record.end_time.replace(' ', 'T');
            const start = new Date(cleanStart);
            const end = new Date(cleanEnd);
            const startDayName = dayNames[start.getDay()];
            const startDatePart = `${start.getMonth() + 1}.${start.getDate()} (${startDayName})`;
            const startTime = `${String(start.getHours()).padStart(2, '0')}:${String(start.getMinutes()).padStart(2, '0')}`;
            const endTime = `${String(end.getHours()).padStart(2, '0')}:${String(end.getMinutes()).padStart(2, '0')}`;

            const isSameDay = start.getFullYear() === end.getFullYear() &&
                              start.getMonth() === end.getMonth() &&
                              start.getDate() === end.getDate();

            if (isSameDay) {
                dateTimeStr = `${startDatePart} ${startTime} ~ ${endTime}`;
            } else {
                const endDayName = dayNames[end.getDay()];
                const endDatePart = `${end.getMonth() + 1}.${end.getDate()} (${endDayName})`;
                dateTimeStr = `${startDatePart} ${startTime} ~ ${endDatePart} ${endTime}`;
            }
        }

        // 서비스 내용 / 상담원 소견 드롭다운 ID
        const dropdownId = `dropdown-${record.id}`;

        card.innerHTML = `
            <div class="record-card-header">
                <div class="record-card-header-left">
                    <span class="record-case-name">${record.case_name || '미지정'} 아동 사례</span>
                    <span class="record-dong">${record.dong || ''}</span>
                </div>
            </div>
            <div class="record-info-list">
                <div class="record-info-row"><span class="info-label">대상자</span><span class="info-value">${record.target || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">제공구분</span><span class="info-value">${record.provision_type || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">제공방법</span><span class="info-value">${record.method || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">서비스제공유형</span><span class="info-value">${record.service_type === '아보전' ? '아보전서비스' : (record.service_type || '-')}</span></div>
                <div class="record-info-row"><span class="info-label">제공서비스</span><span class="info-value">${(record.service_category && record.service_name) ? record.service_category + ' :: ' + record.service_name : (record.service_name || '-')}</span></div>
                <div class="record-info-row"><span class="info-label">제공장소</span><span class="info-value">${record.location || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">서비스제공횟수</span><span class="info-value">${record.service_count != null ? record.service_count + '회' : '-'}</span></div>
                <div class="record-info-row"><span class="info-label">이동소요시간</span><span class="info-value">${record.travel_time != null ? record.travel_time + '분' : '-'}</span></div>
                <div class="record-info-row"><span class="info-label">제공일시</span><span class="info-value">${dateTimeStr || '-'}</span></div>
            </div>
            <div class="record-dropdown-toggle" data-target="${dropdownId}">
                <div style="flex: 1;"></div>
                <span class="dropdown-label">상세 보기</span>
                <svg class="dropdown-arrow" width="12" height="12" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M2 4L6 8L10 4" stroke="#ADB5BD" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
            </div>
            <div class="record-dropdown-content hidden" id="${dropdownId}">
                <div class="dropdown-section" style="margin-bottom: 24px;">
                    <div style="font-weight: 700; color: #4e5968; font-size: 13px; margin-bottom: 6px;">서비스 내용</div>
                    <div class="dropdown-text" style="background: transparent; padding: 0;">${record.service_description || '(내용 없음)'}</div>
                </div>
                <div class="dropdown-section">
                    <div style="font-weight: 700; color: #4e5968; font-size: 13px; margin-bottom: 6px;">상담원 소견</div>
                    <div class="dropdown-text" style="background: transparent; padding: 0;">${record.agent_opinion || '(소견 없음)'}</div>
                </div>
            </div>
            ${record.share_token ? `
            <div class="record-card-footer" style="display:flex;gap:8px;margin-top:12px;padding-top:4px;">
                <button class="btn-share-pending" data-token="${record.share_token}" style="
                    display:inline-flex;align-items:center;gap:4px;padding:7px 14px;
                    background:#F2F4F6;color:#4E5968;border:none;border-radius:8px;
                    font-size:12px;font-weight:700;cursor:pointer;font-family:inherit;
                ">🔗 공유</button>
            </div>` : ''}
            <div class="card-select-number"></div>
        `;

        // 드롭다운 토글
        const toggleBtn = card.querySelector('.record-dropdown-toggle');
        toggleBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            const content = card.querySelector(`#${dropdownId}`);
            const arrow = toggleBtn.querySelector('.dropdown-arrow');
            const label = toggleBtn.querySelector('.dropdown-label');
            content.classList.toggle('hidden');
            const isHidden = content.classList.contains('hidden');
            arrow.classList.toggle('open', !isHidden);
            label.textContent = isHidden ? '상세 보기' : '접기';
        });

        // 공유 버튼 (share_token 있을 때만 렌더됨)
        const shareBtn = card.querySelector('.btn-share-pending');
        if (shareBtn) {
            shareBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                const token = e.currentTarget.dataset.token;
                // [Security] Phase 2-B: 클릭 시점에 vaultKeys에서 키 조회 (렌더 타이밍 문제 방지)
                const key = vaultKeys[token] || '';
                const url = `https://dash.qpon/?token=${token}${key ? '#key=' + key : ''}`;
                navigator.clipboard.writeText(url).then(() => {
                    showToastNotification('공유 링크가 복사됐어요');
                }).catch(() => alert(url));
            });
        }

        // 카드 클릭 → 선택/해제 (단일 선택)
        card.addEventListener('click', () => {
            if (isSelectionMode) {
                if (selectedForDelete.has(record.id)) {
                    selectedForDelete.delete(record.id);
                } else {
                    const nextNum = selectedForDelete.size + 1;
                    selectedForDelete.set(record.id, nextNum);
                }
                renderRecords(); // Re-render to update numbers
                return;
            }

            if (record.status === 'Injected') return;

            if (selectedRecordId === record.id) {
                selectedRecordId = null;
            } else {
                selectedRecordId = record.id;
            }
            renderRecords();
            updateInjectButton();
        });

        // 렌더링 시 현재 모드유지
        if (isSelectionMode) {
            card.classList.add('selection-mode');
            if (selectedForDelete.has(record.id)) {
                card.classList.add('selected-for-delete');
                const numEl = card.querySelector('.card-select-number');
                if (numEl) {
                    // Re-calculate order from Map keys to handle deletions in middle
                    const keys = Array.from(selectedForDelete.keys());
                    const order = keys.indexOf(record.id) + 1;
                    numEl.textContent = order;
                }
            }
        }

        recordsContainer.appendChild(card);
    });
}

function updateInjectButton() {
    if (selectedRecordId) {
        btnInject.disabled = false;
        const record = records.find(r => r.id === selectedRecordId);
        btnInject.textContent = `${record?.case_name || '기록'} 아동 사례 삽입`;
    } else {
        btnInject.disabled = true;
        btnInject.textContent = '삽입할 DB를 선택해주세요';
    }
}

// ==============================================
// 5. 데이터 주입 (Inject)
// ==============================================

btnInject.addEventListener('click', async () => {
    if (!selectedRecordId) return;

    const record = records.find(r => r.id === selectedRecordId);
    if (!record) return;

    // 1. 타겟 탭 찾기 (복수 가능하므로 핑을 쏴서 확인)
    const tabs = await chrome.tabs.query({ url: ["*://localhost:*/*", "*://localhost/*", "*://ncads.go.kr/*", "*://*.ncads.go.kr/*"] });
    const potentialTabs = tabs.filter(t => !t.url.includes('AnySignPlus'));
    
    let targetTab = null;

    // 현재 활성화된 페이지가 타겟이면 우선적으로 사용
    const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (activeTab && potentialTabs.some(t => t.id === activeTab.id)) {
        targetTab = activeTab;
    } else {
        // 활성 탭이 아니면 핑을 쏴서 응답하는 첫 번째 탭 사용
        for (const tab of potentialTabs) {
            try {
                const pong = await new Promise((resolve, reject) => {
                    chrome.tabs.sendMessage(tab.id, { action: 'PING' }, (res) => {
                        if (chrome.runtime.lastError || !res) reject(); else resolve(res);
                    });
                });
                if (pong) { targetTab = tab; break; }
            } catch (e) { continue; }
        }
    }

    if (!targetTab) {
        alert('아동학대정보시스템 창을 찾지 못했어요.');
        updateInjectButton();
        return;
    }

    // 서버 데이터 → content.js 호환 형식으로 변환
    const CFG = window.DBAuto?.Config || {};
    const provCdMap = { '제공': 'A', '부가업무': 'B', '거부': 'C' };
    const meansMap = { '전화': 'A', '내방': 'B', '방문': 'C' };
    const locMap = { '기관내': 'A', '아동가정': 'B', '유관기관': 'C', '기타': 'X' };
    const svcMap = CFG.SERVICE_MAP || {};

    // 시간 포맷 변환 (ISO → content.js 형식)
    let dateTime_val = '';
    if (record.start_time && record.end_time) {
        const cleanStart = record.start_time.replace(' ', 'T');
        const cleanEnd = record.end_time.replace(' ', 'T');
        const start = new Date(cleanStart);
        const end = new Date(cleanEnd);
        const datePart = `${start.getFullYear()}-${String(start.getMonth() + 1).padStart(2, '0')}-${String(start.getDate()).padStart(2, '0')}`;
        const startTime = `${String(start.getHours()).padStart(2, '0')}:${String(start.getMinutes()).padStart(2, '0')}`;
        const endTime = `${String(end.getHours()).padStart(2, '0')}:${String(end.getMinutes()).padStart(2, '0')}`;
        dateTime_val = `${datePart} ${startTime}~${endTime}`;
    }

    const fillData = {
        id: `dash-${record.id}`,
        provCd_val: record.provision_type || '',
        provTyCd_val: record.service_type || '',
        svcClassDetailCd_val: svcMap[record.service_name] || record.service_name || '',
        provMeansCd_val: meansMap[record.method] || record.method || '',
        loc_val: locMap[record.location] || record.location || '',
        dateTime_val: dateTime_val,
        mvmnReqreHr_val: record.travel_time || '0',
        desc_val: record.service_description || '',
        opn_val: record.agent_opinion || '',
        cnt_val: record.service_count || 1,
        // 대상자, 담당자는 시스템에서 직접 선택해야 함 (보안상 서버에서 전달 불가)
        recipient_fullVal: [],
        pic_fullVal: [],
    };

    // 첫 번째 NCADS 탭에 데이터 전송 (위에서 핑으로 확인된 targetTab 사용)

    btnInject.disabled = true;
    btnInject.innerHTML = '<span class="btn-icon-left">⏳</span> 주입 중...';

    chrome.tabs.sendMessage(targetTab.id, { action: 'START_AUTO_FILL', data: fillData }, async (res) => {
        if (chrome.runtime.lastError) {
            console.error('주입 실패:', chrome.runtime.lastError);
            alert('주입에 실패했습니다. 시스템 창을 새로고침한 후 다시 시도해 주세요.');
            updateInjectButton();
            return;
        }

        // 서버에 상태 업데이트 (Injected)
        try {
            await fetch(`${API_BASE}/records/${record.id}/review`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json', ...authHeaders() },
                body: JSON.stringify({ status: 'Injected' })
            });
        } catch (e) {
            console.error('상태 업데이트 실패:', e);
        }

        // 결과 화면 표시
        showResultView();
    });
});

// ==============================================
// 6. 새로고침
// ==============================================


// ==============================================
// 7. 결과 → 목록 복귀
// ==============================================

btnBackToList.addEventListener('click', () => {
    selectedRecordId = null;
    updateInjectButton();
    showMainView();
    switchMainTab('history');
    fetchRecords();
    fetchHistory();
});

btnRefresh.addEventListener('click', () => {
    fetchRecords();
    fetchHistory();
});

// ==============================================
// 8. 상태 메시지 표시
// ==============================================

function setStatus(type, text) {
    // 상태 텍스트 표시 제거 — status bar는 프로필/새로고침 용도로만 사용
}

let isSelectionMode = false;
let selectedForDelete = new Map(); // Use Map to maintain order for numbering

// ==============================================
// 9. 초기화 및 실시간 동기화 (SSE)
// ==============================================

let eventSource = null;
async function setupRealtimeSync() {
    if (eventSource) eventSource.close();

    // SSE 연결 전 항상 신선한 토큰으로 갱신 (만료된 캐시 토큰으로 인한 401 방지)
    try {
        const freshToken = await getFreshTokenSilent();
        currentOAuthToken = freshToken;
        chrome.storage.session.set({ cachedOAuthToken: freshToken });
    } catch (e) {
        // 갱신 실패 시 기존 토큰 사용 (로그아웃 상태 등)
        console.warn('SSE 토큰 갱신 실패, 캐시 토큰 사용:', e.message);
    }

    const sseToken = currentOAuthToken ? `?token=${encodeURIComponent(currentOAuthToken)}` : '';
    eventSource = new EventSource(`${API_BASE}/events${sseToken}`);
    eventSource.addEventListener('new_record', async (e) => {
        const data = JSON.parse(e.data);
        if (!currentUser || (data.user_email !== currentUser.email && data.user_id !== currentUser.uid)) return;

        // Vault가 없던 상태에서 새 기록 수신 → PIN이 방금 설정됐을 수 있음
        // PIN 화면으로 전환 (fetchRecords는 PIN 인증 후 호출됨)
        if (Object.keys(vaultKeys).length === 0) {
            const hasVault = await checkVaultExists();
            if (hasVault) {
                showToastNotification('모바일에서 PIN이 설정되었습니다. PIN을 입력해주세요.');
                showPinView();
                return;
            }
        }

        showToastNotification('새 데이터가 도착했습니다✨');
        fetchRecords();
    });

    eventSource.addEventListener('record_deleted', (e) => {
        const data = JSON.parse(e.data);
        // Refresh only if the deletion belongs to this user or is a general cleanup for this user
        if (!currentUser || (data.user_email && data.user_email !== currentUser.email)) return;
        
        console.log('🔄 Record deleted at server, refreshing list...');
        fetchRecords(); 
    });

    eventSource.onmessage = (e) => {
        const data = JSON.parse(e.data);
        if (data.status === 'connected') return;
    };
    eventSource.onerror = (err) => {
        console.error('SSE Error:', err);
        eventSource.close();
        // 로그인된 상태에서만 재연결 (토큰 없으면 무한 루프 방지)
        if (currentOAuthToken) {
            setTimeout(setupRealtimeSync, 5000);
        }
    };
}

function showToastNotification(msg) {
    const toast = document.createElement('div');
    toast.className = 'toast-notification';
    toast.textContent = msg;
    document.body.appendChild(toast);
    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => toast.remove(), 300);
    }, 4000);
}

(async function init() {
    // 저장된 로그인 정보 확인
    chrome.storage.local.get(['dashUser'], async (result) => {
        if (result.dashUser) {
            currentUser = result.dashUser;
            // 세션 토큰 복원 시도 (브라우저 세션 유지 중이면 재로그인 불필요)
            const sess = await new Promise(r => chrome.storage.session.get(['cachedOAuthToken'], r));
            if (sess.cachedOAuthToken) {
                currentOAuthToken = sess.cachedOAuthToken;
                // 세션 복원 시 토큰 조용히 갱신 (만료 방지)
                try {
                    const freshToken = await getFreshTokenSilent();
                    currentOAuthToken = freshToken;
                    chrome.storage.session.set({ cachedOAuthToken: freshToken });
                } catch (e) {
                    // 갱신 실패 시 캐시 토큰 그대로 사용
                }
            } else {
                // 세션 토큰 없음 = 브라우저 재시작 → 재로그인
                chrome.storage.local.remove(['dashUser']);
                chrome.storage.session.remove(['cachedVaultKeys', 'cachedOAuthToken']);
                vaultKeys = {};
                currentUser = null;
                showLoginView();
                return;
            }
            // PIN 인증 확인 후 메인 뷰로 전환
            await checkPinAndProceed();
        } else {
            showLoginView();
        }
    });

    updateInjectButton();
    setupSelectionLogic();
})();
