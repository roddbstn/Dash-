// ==============================================
// sidepanel.js — Dash Extension Main Logic
// Magazine Fill 전략: Draft → Magazine → Inject
// ==============================================

// ===== 설정 =====
const API_BASE = 'https://dash.qpon/api';

// ===== 상태 관리 =====
let currentUser = null;   // { uid, email }
let currentOAuthToken = null; // Google OAuth 토큰 (API 인증용)
let records = [];          // 서버에서 가져온 기록 목록
let selectedRecordId = null; // 현재 선택된 기록 ID

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
const btnInject = document.getElementById('btn-inject');
const btnBackToList = document.getElementById('btn-back-to-list');
const userEmailEl = document.getElementById('user-email');
const profilePicEl = document.getElementById('profile-pic');
const statusBar = document.getElementById('status-bar');
const statusIcon = document.getElementById('status-icon');
const statusText = document.getElementById('status-text');
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

// ==============================================
// 1. 인증 (간소화된 구글 로그인)
// ==============================================

// 확장 프로그램에서의 로그인은 chrome.identity API를 사용합니다.
// Firebase SDK 대신, 서버에 토큰을 보내 검증하는 방식을 사용합니다.
// MVP 단계에서는 이메일 기반 간소화 로그인을 구현합니다.

btnGoogleLogin.addEventListener('click', async () => {
    btnGoogleLogin.disabled = true;
    const contentsSpan = btnGoogleLogin.querySelector('.gsi-material-button-contents');
    const hiddenSpan = btnGoogleLogin.querySelector('span[style="display: none;"]');
    
    if (contentsSpan) contentsSpan.textContent = '로그인 중...';

    try {
        // chrome.identity를 사용한 구글 인증
        const token = await new Promise((resolve, reject) => {
            chrome.identity.getAuthToken({ interactive: true }, (token) => {
                if (chrome.runtime.lastError) {
                    reject(new Error(chrome.runtime.lastError.message));
                } else {
                    resolve(token);
                }
            });
        });

        // 토큰으로 사용자 정보 가져오기
        const response = await fetch('https://www.googleapis.com/oauth2/v1/userinfo?alt=json', {
            headers: { Authorization: `Bearer ${token}` }
        });
        const userInfo = await response.json();

        currentOAuthToken = token;
        currentUser = {
            uid: userInfo.id,
            email: userInfo.email,
            name: userInfo.name || userInfo.email,
            photo: userInfo.picture
        };

        // 로컬 스토리지에 저장
        chrome.storage.local.set({ dashUser: currentUser });

        // PIN 인증 확인 후 메인 뷰로 전환
        await checkPinAndProceed();
        // fetchRecords는 checkPinAndProceed에서 호출됨

    } catch (error) {
        console.error('로그인 실패:', error);
        // Fallback: 수동 로그인 (개발/테스트용)
        const email = prompt('Google 로그인에 실패했습니다.\n테스트용 이메일을 입력하세요:');
        if (email) {
            let actualUid = email.split('@')[0];
            try {
                const res = await fetch(`${API_BASE}/test/uid-by-email?email=${encodeURIComponent(email)}`);
                if (res.ok) {
                    const data = await res.json();
                    if (data.uid) actualUid = data.uid;
                }
            } catch (err) {
                console.error('UID 조회 실패:', err);
            }
            
            currentUser = { uid: actualUid, email: email, name: email };
            chrome.storage.local.set({ dashUser: currentUser });
            await checkPinAndProceed();
            // fetchRecords는 checkPinAndProceed에서 호출됨
        } else {
            btnGoogleLogin.disabled = false;
            if (contentsSpan) contentsSpan.textContent = 'Google 계정으로 로그인';
        }
    }
});

function performLogout() {
    currentUser = null;
    selectedRecordId = null;
    records = [];
    // 로그아웃 시 PIN 정보도 함께 삭제
    chrome.storage.local.remove(['dashUser', 'dashPin']);
    pinInput = '';
    
    // 버튼 상태 초기화 (비활성화 해제)
    btnGoogleLogin.disabled = false;
    const contentsSpan = btnGoogleLogin.querySelector('.gsi-material-button-contents');
    if (contentsSpan) contentsSpan.textContent = 'Google 계정으로 로그인';
    
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
    btnGoogleLogin.innerHTML = '<span class="google-g">G</span> Google 계정으로 시작하기';
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

// ==============================================
// 2.5. PIN 인증 로직
// ==============================================

// PIN 입력 후 서버 Vault와 검증하는 핵심 함수
async function checkPinAndProceed() {
    // 1. chrome.storage.local에 저장된 PIN이 있는지 확인
    const stored = await new Promise(resolve => {
        chrome.storage.local.get(['dashPin'], result => resolve(result));
    });

    if (stored.dashPin) {
        // 저장된 PIN이 있으면 → 자동으로 Vault 복호화 검증
        const vault = await verifyPinWithVault(stored.dashPin);
        if (vault !== null) {
            vaultKeys = vault; // 메모리에 저장 (복호화에 사용)
            showMainView();
            fetchRecords();
            setupRealtimeSync();
            return;
        } else {
            // 저장된 PIN이 서버와 불일치 (PIN 변경 등) → 다시 입력 요청
            chrome.storage.local.remove('dashPin');
        }
    }

    // 2. 서버에 Vault가 존재하는지 확인
    const hasVault = await checkVaultExists();
    if (!hasVault) {
        // Vault가 없으면 = 모바일에서 PIN을 아직 설정하지 않은 케이스
        // → PIN 없이 바로 진입 (모바일에서 PIN 설정 후 다음 로그인부터 적용)
        showMainView();
        fetchRecords();
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

        const { encrypted_vault } = await res.json();
        if (!encrypted_vault) return null;

        return await attemptDecryptVault(pin, encrypted_vault);
    } catch (e) {
        console.error('PIN verification failed:', e);
        return null;
    }
}

// AES-CBC로 Vault 복호화 (Flutter encrypt 패키지와 동일한 방식)
// 성공 시 파싱된 Vault 객체 반환, 실패 시 null
async function attemptDecryptVault(pin, encryptedVaultB64) {
    try {
        const parts = encryptedVaultB64.split(':');
        if (parts.length !== 2) return null;

        const iv = base64ToArrayBuffer(parts[0]);        // 16 bytes
        const ciphertext = base64ToArrayBuffer(parts[1]);

        // Flutter: encrypt.Key.fromUtf8(pin.padRight(32).substring(0, 32))
        const keyStr = pin.padEnd(32).substring(0, 32);
        const keyBytes = new TextEncoder().encode(keyStr);

        const cryptoKey = await crypto.subtle.importKey(
            'raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']
        );

        const decryptedBuffer = await crypto.subtle.decrypt(
            { name: 'AES-CBC', iv }, cryptoKey, ciphertext
        );

        const vaultJson = new TextDecoder().decode(decryptedBuffer);
        return JSON.parse(vaultJson); // { share_token: encryptionKey, ... }
    } catch (e) {
        return null; // 복호화 실패 = PIN 불일치
    }
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

            const dots = pinDots.querySelectorAll('.pin-dot');
            dots.forEach(d => {
                d.classList.remove('filled');
                d.classList.add('success');
            });

            // chrome.storage.local에 PIN 저장 (다음 실행 시 자동 복호화용)
            chrome.storage.local.set({ dashPin: pinInput });

            setTimeout(() => {
                showMainView();
                fetchRecords();
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

        // encrypted_blob을 vaultKeys로 복호화하여 service_description, agent_opinion 복원
        records = await Promise.all(rawRecords.map(async (record) => {
            if (record.encrypted_blob && record.share_token && vaultKeys[record.share_token]) {
                const decrypted = await decryptBlob(record.encrypted_blob, vaultKeys[record.share_token]);
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
        if (records.length === 0) {
            recordsContainer.innerHTML = '';
            emptyState.classList.remove('hidden');
            actionBar.classList.add('hidden');
            if (selectBar) selectBar.classList.add('hidden');
            setStatus('success', '모든 기록이 처리되었습니다');
        } else {
            emptyState.classList.add('hidden');
            actionBar.classList.remove('hidden');
            if (selectBar) selectBar.classList.remove('hidden');
            renderRecords();
            setStatus('success', '삽입할 DB를 선택해주세요');
        }

    } catch (error) {
        console.error('기록 패치 오류:', error);
        recordsContainer.innerHTML = '';
        emptyState.classList.remove('hidden');
        setStatus('error', '서버 연결에 실패했어요. 새로고침해 보세요.');
    }
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

    records.forEach(record => {
        const card = document.createElement('div');
        card.className = `record-card ${record.id === selectedRecordId ? 'selected' : ''} ${record.status === 'Injected' ? 'injected' : ''}`;
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

        // 상태 뱃지
        const statusLabel = record.status === 'Reviewed' ? '검토 완료' : '검토 대기';
        const statusClass = record.status === 'Reviewed' ? 'badge-reviewed' : 'badge-synced';

        card.innerHTML = `
            <div class="record-card-header">
                <div class="record-card-header-left">
                    <span class="record-case-name">${record.case_name || '미지정'} 아동 사례</span>
                    <span class="record-dong">${record.dong || ''}</span>
                </div>
                <div style="display:flex; align-items:center;">
                    <span class="record-status-badge ${statusClass}">${statusLabel}</span>
                </div>
            </div>
            <div class="record-info-list">
                <div class="record-info-row"><span class="info-label">대상자</span><span class="info-value">${record.target || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">제공구분</span><span class="info-value">${record.provision_type || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">제공방법</span><span class="info-value">${record.method || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">서비스유형</span><span class="info-value">${record.service_type || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">제공서비스</span><span class="info-value">${record.service_name || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">제공장소</span><span class="info-value">${record.location || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">제공일시</span><span class="info-value">${dateTimeStr || '-'}</span></div>
            </div>
            <div class="record-dropdown-toggle" data-target="${dropdownId}">
                <div style="flex: 1;"></div>
                <span class="dropdown-label">상세 보기</span>
                <span class="dropdown-arrow">▼</span>
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
            <div class="card-select-number"></div>
        `;

        // 드롭다운 토글
        const toggleBtn = card.querySelector('.record-dropdown-toggle');
        toggleBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            const content = card.querySelector(`#${dropdownId}`);
            const arrow = toggleBtn.querySelector('.dropdown-arrow');
            content.classList.toggle('hidden');
            arrow.textContent = content.classList.contains('hidden') ? '▼' : '▲';
        });

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
        alert('아동학대정보시스템 창을 찾을 수 없거나, 페이지가 새로고침되지 않았습니다.\n\n시스템 창(localhost:8080)을 새로고침한 후 다시 시도해 주세요.');
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
    showMainView();
    fetchRecords();
});

// ==============================================
// 8. 상태 메시지 표시
// ==============================================

function setStatus(type, text) {
    statusBar.className = 'status-bar';
    switch (type) {
        case 'loading':
            statusIcon.textContent = '🔄';
            break;
        case 'success':
            statusIcon.textContent = '✅';
            statusBar.classList.add('success');
            break;
        case 'error':
            statusIcon.textContent = '❌';
            statusBar.classList.add('error');
            break;
    }
    statusText.textContent = text;
}

let isSelectionMode = false;
let selectedForDelete = new Map(); // Use Map to maintain order for numbering

// ==============================================
// 9. 초기화 및 실시간 동기화 (SSE)
// ==============================================

let eventSource = null;
function setupRealtimeSync() {
    if (eventSource) eventSource.close();
    const sseToken = currentOAuthToken ? `?token=${encodeURIComponent(currentOAuthToken)}` : '';
    eventSource = new EventSource(`${API_BASE}/events${sseToken}`);
    eventSource.addEventListener('new_record', (e) => {
        const data = JSON.parse(e.data);
        if (currentUser && (data.user_email === currentUser.email || data.user_id === currentUser.uid)) {
            showToastNotification('새 데이터가 도착했습니다✨');
            fetchRecords(); // 목록 새로고침
        }
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
        setTimeout(setupRealtimeSync, 5000); // 5초 후 재연결 시도
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
            // OAuth 토큰 silent 복원 (API 인증용)
            try {
                currentOAuthToken = await new Promise((resolve) => {
                    chrome.identity.getAuthToken({ interactive: false }, (token) => {
                        resolve(chrome.runtime.lastError ? null : token);
                    });
                });
            } catch (_) { /* 토큰 없으면 null 유지 */ }
            // PIN 인증 확인 후 메인 뷰로 전환
            await checkPinAndProceed();
        } else {
            showLoginView();
        }
    });

    updateInjectButton();
    setupSelectionLogic();
})();
