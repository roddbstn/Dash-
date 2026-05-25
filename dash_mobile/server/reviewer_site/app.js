// Reviewer Application Logic

// ── Firebase 초기화 ──────────────────────────────────────────
const _fbConfig = {
    apiKey: 'AIzaSyASW_FfIITQdQjuppQzazGreivrmUMhfYY',
    authDomain: 'dash-7cdea.firebaseapp.com',
    projectId: 'dash-7cdea',
    storageBucket: 'dash-7cdea.firebasestorage.app',
    messagingSenderId: '803548605147',
    appId: '1:803548605147:web:e9b76ac7245af36afc3afe',
};
firebase.initializeApp(_fbConfig);
const _analytics = firebase.analytics();
function _logEvent(name, params) { try { _analytics.logEvent(name, params); } catch(_) {} }

// ── 인앱 브라우저 감지 (카카오톡, 라인, 인스타그램 등)
function isInAppBrowser() {
    const ua = navigator.userAgent || '';
    // 명시적 인앱 브라우저 식별자
    if (/KAKAOTALK|NAVER|Line\/|FB_IAB|FBAN|Instagram|DaumApps/i.test(ua)) return true;
    // iOS/Android 기기인데 Safari나 Chrome이 아닌 경우 (WebView)
    const isMobile = /iPhone|iPad|Android/i.test(ua);
    const isSafari = /Safari\//i.test(ua) && !/Chrome\//i.test(ua);
    const isChrome = /Chrome\//i.test(ua) && !/Chromium/i.test(ua);
    if (isMobile && !isSafari && !isChrome) return true;
    return false;
}

function copyAndClose() {
    navigator.clipboard.writeText(window.location.href).then(() => {
        const btn = document.querySelector('#inapp-modal button');
        if (btn) { btn.textContent = '복사됨 ✓'; setTimeout(() => { btn.textContent = '주소 복사하기'; }, 2000); }
    }).catch(() => {
        prompt('아래 주소를 복사해서 Chrome/Safari에 붙여넣기 해주세요:', window.location.href);
    });
}

// ── 프로필 아바타 표시/숨김
function showUserProfile(user) {
    const wrapper = document.getElementById('user-avatar-wrapper');
    const avatar = document.getElementById('user-avatar');
    const tooltip = document.getElementById('user-email-tooltip');
    if (!wrapper || !avatar) return;
    avatar.src = user.photoURL || `https://ui-avatars.com/api/?name=${encodeURIComponent(user.displayName || user.email)}&background=4e73df&color=fff&size=64`;
    if (tooltip) tooltip.textContent = user.email || '';
    wrapper.style.display = 'block';
}

function hideUserProfile() {
    const wrapper = document.getElementById('user-avatar-wrapper');
    if (wrapper) wrapper.style.display = 'none';
}

// ── Google 로그인 (GIS + signInWithCredential)
function signInWithGoogle() {
    const btn = document.getElementById('btn-google-login');
    const errorEl = document.getElementById('auth-error');
    btn.disabled = true;
    btn.textContent = '로그인 중...';
    errorEl.textContent = '';

    // 직접 Google OAuth 팝업 — GIS/FedCM/storagerelay 완전 무관
    const REDIRECT_URI = window.location.origin + '/oauth_callback.html';
    const authUrl = 'https://accounts.google.com/o/oauth2/v2/auth?' + new URLSearchParams({
        client_id: '803548605147-8p75oeqvre7frce70lkl59akqung8kd7.apps.googleusercontent.com',
        redirect_uri: REDIRECT_URI,
        response_type: 'token',
        scope: 'openid email profile',
        prompt: 'select_account',
    }).toString();

    // 새 탭으로 열릴 경우를 대비해 복귀 URL 저장
    sessionStorage.setItem('oauth_return_url', window.location.href);

    const popup = window.open(authUrl, 'google_login', 'width=500,height=600,scrollbars=yes,resizable=yes');
    if (!popup) {
        errorEl.textContent = '팝업이 차단됐습니다. 주소창에서 팝업 허용 후 다시 시도해주세요.';
        btn.disabled = false;
        btn.textContent = 'Google 계정으로 로그인';
        return;
    }

    let handled = false;

    function handleOAuthResult(data) {
        if (handled) return;
        handled = true;
        clearInterval(pollTimer);
        window.removeEventListener('message', onOAuthMessage);
        if (bc) { try { bc.close(); } catch (_) {} bc = null; }

        if (data.error) {
            errorEl.textContent = '오류: ' + data.error;
            btn.disabled = false;
            btn.textContent = 'Google 계정으로 로그인';
            return;
        }
        const credential = firebase.auth.GoogleAuthProvider.credential(null, data.access_token);
        firebase.auth().signInWithCredential(credential).then(async (result) => {
            if (!_loginHandled) {
                _loginHandled = true;
                await handleReviewerLogin(result.user);
            }
        }).catch((e) => {
            _loginHandled = false;
            errorEl.textContent = '오류: ' + (e.message || e.code);
            btn.disabled = false;
            btn.textContent = 'Google 계정으로 로그인';
        });
    }

    // postMessage (팝업 경로)
    function onOAuthMessage(event) {
        if (event.origin !== window.location.origin) return;
        if (!event.data || event.data.type !== 'google_oauth_result') return;
        handleOAuthResult(event.data);
    }
    window.addEventListener('message', onOAuthMessage);

    // BroadcastChannel (새 탭 경로) — 탭이 닫히지 않고 리다이렉트된 경우 중복 방지
    let bc = null;
    try {
        bc = new BroadcastChannel('dash_oauth');
        bc.onmessage = (event) => {
            if (event.data?.type === 'google_oauth_result') handleOAuthResult(event.data);
        };
    } catch (_) {}

    // 유저가 팝업/탭을 직접 닫은 경우 버튼 복원
    const pollTimer = setInterval(() => {
        if (popup.closed && !handled) {
            clearInterval(pollTimer);
            window.removeEventListener('message', onOAuthMessage);
            if (bc) { try { bc.close(); } catch (_) {} bc = null; }
            btn.disabled = false;
            btn.textContent = 'Google 계정으로 로그인';
        }
    }, 500);
}

async function submitOwnerName() {
    const token = new URLSearchParams(window.location.search).get('token');
    const nameInput = document.getElementById('owner-name-input');
    const errorEl = document.getElementById('name-verify-error');
    const btn = document.getElementById('btn-verify-name');
    const name = nameInput.value.trim();

    if (!name) { errorEl.textContent = '이름을 입력해주세요.'; return; }

    btn.disabled = true;
    btn.textContent = '확인 중...';
    errorEl.textContent = '';

    try {
        const user = firebase.auth().currentUser;
        const idToken = await user.getIdToken(true);
        const res = await fetch(`/api/records/verify-name/${token}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${idToken}` },
            body: JSON.stringify({ owner_name: name }),
        });
        const data = await res.json();

        if (res.ok && data.ok) {
            sessionStorage.setItem('dash_auth_' + token, '1');
            document.getElementById('name-verify-modal').style.display = 'none';
            loadRecord(token);
        } else if (data.error === 'name_mismatch') {
            errorEl.textContent = '이름이 일치하지 않습니다. 다시 확인해주세요.';
            nameInput.value = '';
            nameInput.focus();
        } else if (data.error === 'viewer_limit_reached') {
            document.getElementById('name-verify-modal').style.display = 'none';
            document.getElementById('viewer-limit-modal').style.display = 'flex';
        } else {
            errorEl.textContent = data.error || '오류가 발생했습니다.';
        }
    } catch (_) {
        errorEl.textContent = '네트워크 오류가 발생했습니다.';
    } finally {
        btn.disabled = false;
        btn.textContent = '확인';
    }
}

function showAuthModal() {
    document.getElementById('not-registered-modal').style.display = 'none';
    document.getElementById('auth-modal').style.display = 'flex';
    // Google 로그인 버튼 초기화
    const btn = document.getElementById('btn-google-login');
    if (btn) { btn.disabled = false; btn.textContent = 'Google 계정으로 로그인'; }
    document.getElementById('auth-error').textContent = '';
}

function confirmLogout() {
    const token = new URLSearchParams(window.location.search).get('token');
    firebase.auth().signOut().then(() => {
        if (token) sessionStorage.removeItem('dash_auth_' + token);
        document.getElementById('logout-confirm-modal').style.display = 'none';
        hideUserProfile();
        showAuthModal();
    });
}

async function handleReviewerLogin(user) {
    const token = new URLSearchParams(window.location.search).get('token');
    if (!token) return;

    const idToken = await user.getIdToken(true); // 강제 갱신
    const res = await fetch(`/api/records/reviewer-login/${token}`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${idToken}` },
    });
    const data = await res.json();

    if (res.ok && data.ok) {
        document.getElementById('auth-modal').style.display = 'none';
        _logEvent('reviewer_login_success', { is_owner: data.isOwner ? 1 : 0 });
        showUserProfile(user);
        if (data.isOwner) {
            sessionStorage.setItem('dash_auth_' + token, '1');
            setOwnerReadOnlyMode();
            loadRecord(token);
        } else if (data.needsNameVerification) {
            // 이름 인증 모달 표시 (share_viewers 등록은 인증 후)
            const modal = document.getElementById('name-verify-modal');
            modal.style.display = 'flex';
            document.getElementById('owner-name-input').focus();
        } else {
            sessionStorage.setItem('dash_auth_' + token, '1');
            loadRecord(token);
        }
    } else if (data.error === 'not_registered') {
        // 모바일 앱 미가입 → Firebase 세션 즉시 소거 후 안내 화면 표시
        await firebase.auth().signOut();
        document.getElementById('auth-modal').style.display = 'none';
        document.getElementById('not-registered-modal').style.display = 'flex';
    } else if (data.error === 'viewer_limit_reached') {
        // 공유 인원 초과 (3명 이상)
        await firebase.auth().signOut();
        document.getElementById('auth-modal').style.display = 'none';
        document.getElementById('viewer-limit-modal').style.display = 'flex';
    } else {
        document.getElementById('auth-modal').style.display = 'flex';
        document.getElementById('auth-error').textContent = data.error || '접근 권한이 없습니다.';
        const btn = document.getElementById('btn-google-login');
        btn.disabled = false;
        btn.textContent = 'Google 계정으로 로그인';
    }
}

let _loginHandled = false; // 전역 플래그: handleReviewerLogin 중복 호출 방지


let isInfoExpanded = false;
let isEditMode = true; // 항상 편집 모드
let editHistory = []; // [{main, opinion}, ...]
let historyIndex = -1;
let hasEverSentNotify = false; // 최초 "저장 알림 보내기" 클릭 여부
let _recordOwnerName = ''; // DB 생성자(공유자) 이름
let _savedToMyDbDesc = null;    // 마지막 '내 DB로 저장' 시점의 service_description
let _savedToMyDbOpinion = null; // 마지막 '내 DB로 저장' 시점의 agent_opinion

// ── 편집 모드 (항상 활성) ──────────────────────────────────────
// toggleEditMode 제거: 편집 버튼 없이 바로 편집 가능

// ── Undo / Redo ─────────────────────────────────────────────
function pushHistory(main, opinion) {
    editHistory = editHistory.slice(0, historyIndex + 1);
    editHistory.push({ main, opinion });
    historyIndex = editHistory.length - 1;
    updateUndoRedoButtons();
    updateCTAState();
}

function persistDraft(main, opinion) {
    const token = new URLSearchParams(window.location.search).get('token');
    if (token) {
        sessionStorage.setItem('dash_draft_' + token, JSON.stringify({ main, opinion }));
    }
}

function undo() {
    if (historyIndex <= 0) return;
    historyIndex--;
    const state = editHistory[historyIndex];
    document.getElementById('main-editor').value = state.main;
    document.getElementById('opinion-editor').value = state.opinion;
    if (window.currentRecord) {
        window.currentRecord.serviceDescription = state.main;
        window.currentRecord.agentOpinion = state.opinion;
    }
    persistDraft(state.main, state.opinion);
    updateUndoRedoButtons();
    updateCTAState();
}

function redo() {
    if (historyIndex >= editHistory.length - 1) return;
    historyIndex++;
    const state = editHistory[historyIndex];
    document.getElementById('main-editor').value = state.main;
    document.getElementById('opinion-editor').value = state.opinion;
    if (window.currentRecord) {
        window.currentRecord.serviceDescription = state.main;
        window.currentRecord.agentOpinion = state.opinion;
    }
    persistDraft(state.main, state.opinion);
    updateUndoRedoButtons();
    updateCTAState();
}

function updateUndoRedoButtons() {
    const undoBtn = document.getElementById('btn-undo');
    const redoBtn = document.getElementById('btn-redo');
    const canUndo = historyIndex > 0;
    const canRedo = historyIndex < editHistory.length - 1;

    undoBtn.disabled = !canUndo;
    undoBtn.style.background = canUndo ? '#4e73df' : '#E9ECEF';
    undoBtn.style.color = canUndo ? '#fff' : '#ADB5BD';
    undoBtn.style.cursor = canUndo ? 'pointer' : 'not-allowed';
    undoBtn.style.border = 'none';

    redoBtn.disabled = !canRedo;
    redoBtn.style.background = canRedo ? '#4e73df' : '#E9ECEF';
    redoBtn.style.color = canRedo ? '#fff' : '#ADB5BD';
    redoBtn.style.cursor = canRedo ? 'pointer' : 'not-allowed';
    redoBtn.style.border = 'none';
}

function updateCTAState() {
    // historyIndex >= 0: 레코드가 로드된 시점부터 버튼 활성화
    const hasChanges = historyIndex >= 0;
    document.querySelectorAll('.notify-btn').forEach(btn => {
        btn.disabled = !hasChanges;
        btn.style.opacity = hasChanges ? '1' : '0.45';
        btn.style.cursor = hasChanges ? 'pointer' : 'not-allowed';
        if (btn.id === 'btn-notify-mobile') {
            btn.style.background = hasChanges ? '' : '#ADB5BD';
        }
    });
    // 저장 버튼 활성화 (owner용)
    const headerSave = document.getElementById('btn-owner-save');
    const mobileSave = document.getElementById('btn-owner-save-mobile');
    [headerSave, mobileSave].forEach(btn => {
        if (!btn || btn.style.display === 'none') return;
        btn.disabled = !hasChanges;
        btn.style.opacity = hasChanges ? '1' : '0.45';
        btn.style.cursor = hasChanges ? 'pointer' : 'not-allowed';
        if (btn.id === 'btn-owner-save-mobile') {
            btn.style.background = hasChanges ? '' : '#ADB5BD';
        }
    });
    // 내 DB로 저장 버튼: 마지막 저장 이후 내용이 변경됐으면 재활성화
    if (_savedToMyDbDesc !== null) {
        const curDesc = (document.getElementById('main-editor')?.value) ?? '';
        const curOpinion = (document.getElementById('opinion-editor')?.value) ?? '';
        const isDirty = curDesc !== _savedToMyDbDesc || curOpinion !== _savedToMyDbOpinion;
        const saveHeader = document.getElementById('btn-save-to-my-db-header');
        const saveMobile = document.getElementById('btn-save-to-my-db-mobile');
        [saveHeader, saveMobile].forEach(btn => {
            if (!btn) return;
            btn.disabled = !isDirty;
            btn.style.opacity = isDirty ? '1' : '0.6';
            btn.style.cursor = isDirty ? 'pointer' : 'not-allowed';
            if (isDirty) btn.textContent = '내 DB로 저장';
        });
    }
}

// 버튼 텍스트를 "저장 후 전송"으로 업데이트 (최초 알림 전송 후)
function markNotifySent() {
    hasEverSentNotify = true;
    const token = new URLSearchParams(window.location.search).get('token');
    if (token) sessionStorage.setItem('dash_notify_sent_' + token, '1');
    const headerBtn = document.getElementById('btn-notify-header');
    const mobileBtn = document.getElementById('btn-notify-mobile');
    if (headerBtn) headerBtn.textContent = '저장 후 전송';
    if (mobileBtn) mobileBtn.textContent = '저장 후 전송';
}

// ── 로컬 임시 저장 (세션 복원용) — 서버 자동 저장 제거, 버튼 클릭 시만 저장
let _typingTimer = null;

function _getEncKey(token) {
    // [Security] 키는 fragment(#key=)에서만 읽음 — 서버 로그/히스토리에 기록 안 됨
    const hashParams = new URLSearchParams(window.location.hash.substring(1));
    let key = hashParams.get('key') || '';
    if (!key) key = sessionStorage.getItem('dash_key_' + token) || '';
    return key;
}

function handleTyping() {
    const main = document.getElementById('main-editor').value;
    const opinion = document.getElementById('opinion-editor').value || '';

    // 메모리 내 currentRecord 갱신 (버튼 클릭 시 re-encryption에 사용)
    if (window.currentRecord) {
        window.currentRecord.serviceDescription = main;
        window.currentRecord.agentOpinion = opinion;
    }

    if (_typingTimer) clearTimeout(_typingTimer);
    _typingTimer = setTimeout(() => {
        // 히스토리에 현재 상태 push (내용이 변경된 경우만)
        const last = editHistory[historyIndex] || {};
        if (last.main !== main || last.opinion !== opinion) {
            pushHistory(main, opinion);
        }
        // 세션 임시 저장 (새로고침 복원용)
        persistDraft(main, opinion);
    }, 500);
}

// ── 저장 버튼 클릭 시 서버에 명시적 저장 (소유자 전용)
async function saveRecord() {
    const token = new URLSearchParams(window.location.search).get('token');
    if (!token) return;
    const serviceDescription = document.getElementById('main-editor').value;
    const agentOpinion = document.getElementById('opinion-editor').value || '';
    const body = { service_description: serviceDescription, agent_opinion: agentOpinion };
    const encKey = _getEncKey(token);
    if (encKey && window.currentRecord) {
        try {
            const updatedData = { ...window.currentRecord, serviceDescription, agentOpinion };
            const aesKey = CryptoJS.enc.Utf8.parse(encKey.padEnd(32).substring(0, 32));
            const iv = CryptoJS.lib.WordArray.random(16);
            const encrypted = CryptoJS.AES.encrypt(JSON.stringify(updatedData), aesKey, { iv });
            body.encrypted_blob = iv.toString(CryptoJS.enc.Base64) + ':' + encrypted.toString();
        } catch (e) { console.error('Encryption failed:', e); }
    }
    const headerBtn = document.getElementById('btn-owner-save');
    const mobileBtn = document.getElementById('btn-owner-save-mobile');
    [headerBtn, mobileBtn].forEach(btn => { if (btn) { btn.disabled = true; btn.textContent = '저장 중...'; } });
    try {
        const res = await fetch(`/api/records/share/${token}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        if (res.ok) {
            showToast('저장되었습니다.');
        } else {
            showToast('저장 실패. 다시 시도해주세요.');
        }
    } catch (_) {
        showToast('저장 실패. 다시 시도해주세요.');
    } finally {
        [headerBtn, mobileBtn].forEach(btn => { if (btn) { btn.disabled = false; btn.textContent = '저장'; btn.style.opacity = '1'; btn.style.cursor = 'pointer'; } });
    }
}



// Mobile Info Toggle
function toggleMobileInfo() {
    const content = document.getElementById('mobile-info-content');
    const label = document.querySelector('.info-label');
    
    isInfoExpanded = !isInfoExpanded;
    
    if (isInfoExpanded) {
        content.style.display = 'block';
        label.innerHTML = '간략히 <span style="font-size: 1.4em;">▴</span>';
    } else {
        content.style.display = 'none';
        label.innerHTML = '서비스 상세 정보 <span style="font-size: 1.4em;">▾</span>';
    }
}

// Modal Logic
function openNotifyModal() {
    document.getElementById('modal-container').style.display = 'flex';
}

function closeModal() {
    document.getElementById('modal-container').style.display = 'none';
}

async function confirmNotify() {
    const urlParams = new URLSearchParams(window.location.search);
    const token = urlParams.get('token');
    const encKey = _getEncKey(token);

    if (!token) {
        alert('토큰 정보가 없어 완료할 수 없습니다.');
        return closeModal();
    }

    // 버튼 로딩 상태
    const confirmBtn = document.querySelector('#modal-container .btn-primary');
    if (confirmBtn) { confirmBtn.disabled = true; confirmBtn.textContent = '전송 중...'; }

    const serviceDescription = document.getElementById('main-editor').value;
    const agentOpinion = document.getElementById('opinion-editor').value;
    
    let body = { service_description: serviceDescription, agent_opinion: agentOpinion };

    // E2EE: If we have the encryption key, re-encrypt the entire record
    if (encKey && window.currentRecord) {
        try {
            const updatedData = { ...window.currentRecord, serviceDescription, agentOpinion };
            const key = CryptoJS.enc.Utf8.parse(encKey.padEnd(32).substring(0, 32));
            const iv = CryptoJS.lib.WordArray.random(16);
            const encrypted = CryptoJS.AES.encrypt(JSON.stringify(updatedData), key, { iv: iv });
            
            body.encrypted_blob = iv.toString(CryptoJS.enc.Base64) + ":" + encrypted.toString();
            // plaintext도 함께 저장 (복호화 실패 시 폴백)
        } catch (e) {
            console.error("Encryption failed:", e);
        }
    }

    try {
        const currentUser = firebase.auth().currentUser;
        const idToken = currentUser ? await currentUser.getIdToken(true) : null;
        const res = await fetch(`/api/records/reviewed/${token}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                ...(idToken ? { 'Authorization': `Bearer ${idToken}` } : {})
            },
            body: JSON.stringify(body)
        });
        const data = await res.json();
        if (data.error) throw new Error(data.error);

        // 최초 전송 완료 마킹 → 버튼 텍스트 변경
        markNotifySent();
        // 히스토리 리셋 (현재 상태를 새 baseline으로)
        const curMain = document.getElementById('main-editor').value;
        const curOpinion = document.getElementById('opinion-editor').value || '';
        editHistory = [{ main: curMain, opinion: curOpinion }];
        historyIndex = 0;
        updateUndoRedoButtons();
        updateCTAState();

        _logEvent('review_submitted');
        closeModal();
        // 성공 토스트
        showToast('담당자에게 저장 알림을 보냈어요.');
        // 히스토리 패널이 열려 있으면 즉시 갱신
        const histPanel = document.getElementById('history-panel');
        if (histPanel && histPanel.classList.contains('open')) loadHistory(token);
    } catch (err) {
        alert('처리 중 오류가 발생했습니다.');
        console.error(err);
    } finally {
        if (confirmBtn) { confirmBtn.disabled = false; confirmBtn.textContent = '알림 보내기'; }
    }
}

function formatDayOfWeek(dateString) {
    if(!dateString) return '';
    const cleanStr = dateString.replace(' ', 'T');
    const date = new Date(cleanStr);
    if(isNaN(date)) return dateString;
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    const m = date.getMonth() + 1;
    const d = date.getDate();
    const day = days[date.getDay()];
    // format to "M.d (day)"
    return `${m}.${d} (${day})`;
}

// Format start and end time string "3월 12일 (목) 17:45 ~ 18:45"
function formatDateTimeRange(startStr, endStr) {
    if(!startStr || !endStr) return '';
    const cleanStart = startStr.replace(' ', 'T');
    const cleanEnd = endStr.replace(' ', 'T');
    const startDate = new Date(cleanStart);
    const endDate = new Date(cleanEnd);
    if(isNaN(startDate) || isNaN(endDate)) return `${startStr} ~ ${endStr}`;
    
    const startDayFormatted = formatDayOfWeek(startStr);
    const startHour = startDate.getHours().toString().padStart(2, '0');
    const startMin = startDate.getMinutes().toString().padStart(2, '0');
    
    const endHour = endDate.getHours().toString().padStart(2, '0');
    const endMin = endDate.getMinutes().toString().padStart(2, '0');

    // Check if dates are same
    const isSameDay = startDate.getFullYear() === endDate.getFullYear() &&
                      startDate.getMonth() === endDate.getMonth() &&
                      startDate.getDate() === endDate.getDate();

    if (isSameDay) {
        return `${startDayFormatted} ${startHour}:${startMin} ~ ${endHour}:${endMin}`;
    } else {
        const endDayFormatted = formatDayOfWeek(endStr);
        return `${startDayFormatted} ${startHour}:${startMin} ~ ${endDayFormatted} ${endHour}:${endMin}`;
    }
}


function showEncryptionNotice(reason) {
    const existing = document.getElementById('enc-notice');
    if (existing) return;
    const notice = document.createElement('div');
    notice.id = 'enc-notice';
    notice.style.cssText = [
        'background:#FFF8E1', 'border:1px solid #FFD54F', 'border-radius:10px',
        'padding:12px 16px', 'margin:12px 20px 0', 'font-size:13px',
        'color:#795548', 'line-height:1.6', 'display:flex', 'align-items:flex-start', 'gap:8px'
    ].join(';');
    const msg = reason === 'no_key'
        ? '🔒 이 링크에 암호화 키가 포함되어 있지 않아 서비스 내용과 상담원 소견을 표시할 수 없습니다.<br>원래 공유 링크(#으로 끝나는 키 포함)를 다시 받아 열어주세요.'
        : '🔒 복호화에 실패했습니다. 링크가 변형됐거나 다른 기기에서 생성된 레코드일 수 있습니다.<br>담당 상담원에게 공유 링크를 다시 요청해 주세요.';
    notice.innerHTML = `<span>${msg}</span>`;
    const editorArea = document.querySelector('.editor-area') || document.querySelector('.writing-workspace');
    if (editorArea) editorArea.insertAdjacentElement('afterbegin', notice);
}

function loadRecord(token) {
    let encKey = "";
    // [Security] 키는 fragment(#key=)에서만 읽음
    const hashStr = window.location.hash.substring(1);
    if (hashStr) {
        const hashParams = new URLSearchParams(hashStr);
        encKey = hashParams.get('key') || '';
    }
    // 세션에 저장된 키 (URL에 키가 없는 경우)
    if (!encKey) {
        encKey = sessionStorage.getItem('dash_key_' + token) || "";
    }

    fetch(`${window.location.origin}/api/records/share/${token}`)
        .then(res => {
            if (!res.ok) throw new Error(`HTTP error! status: ${res.status}`);
            return res.json();
        })
        .then(data => {
                // 서버 응답의 encryption_key를 폴백으로 사용 (레거시 레코드 호환)
                if (!encKey && data.encryption_key) {
                    encKey = data.encryption_key;
                    sessionStorage.setItem('dash_key_' + token, encKey);
                }

                // E2EE Decryption
                if (data.encrypted_blob && encKey) {
                    try {
                        console.log("🔒 End-to-End Encryption Detected. Decrypting...");
                        const parts = data.encrypted_blob.split(':');
                        const iv = CryptoJS.enc.Base64.parse(parts[0]);
                        const ciphertext = parts[1];
                        const key = CryptoJS.enc.Utf8.parse(encKey.padEnd(32).substring(0, 32));

                        const decrypted = CryptoJS.AES.decrypt(
                            { ciphertext: CryptoJS.enc.Base64.parse(ciphertext) },
                            key,
                            { iv: iv }
                        );
                        const decryptedText = decrypted.toString(CryptoJS.enc.Utf8);
                        if (!decryptedText) throw new Error("Empty decryption result");

                        const decryptedData = JSON.parse(decryptedText);
                        console.log("Decrypted successful:", decryptedData);

                        // Merge decrypted data into the row object
                        // Handle camelCase from Flutter vs snake_case from DB
                        data = {
                            ...data,
                            ...decryptedData,
                            case_name: decryptedData.caseName || data.case_name,
                            service_description: decryptedData.serviceDescription || decryptedData.service_description || data.service_description,
                            agent_opinion: decryptedData.agentOpinion || decryptedData.agent_opinion || data.agent_opinion,
                            target: decryptedData.target || data.target,
                            method: decryptedData.method || data.method,
                            provision_type: decryptedData.provision_type || data.provision_type,
                            service_type: decryptedData.service_type || data.service_type,
                            service_category: decryptedData.service_category || data.service_category,
                            service_name: decryptedData.service_name || data.service_name,
                            location: decryptedData.location || data.location,
                            start_time: decryptedData.startTime || decryptedData.start_time || data.start_time,
                            end_time: decryptedData.endTime || decryptedData.end_time || data.end_time,
                            service_count: decryptedData.serviceCount || decryptedData.service_count || data.service_count,
                            travel_time: decryptedData.travelTime || decryptedData.travel_time || data.travel_time
                        };
                        window.currentRecord = data; // Store for re-encryption
                    } catch (e) {
                        console.error("Decryption failed:", e);
                        showEncryptionNotice('decrypt_failed');
                    }
                } else if (data.encrypted_blob && !encKey) {
                    showEncryptionNotice('no_key');
                }
                renderParticipants(data.user_name, data.share_viewers || []);
                updateUI(data);
                // 참여자 목록을 별도 엔드포인트로 한 번 더 갱신 (타이밍 문제 방어)
                const _tok = new URLSearchParams(window.location.search).get('token');
                if (_tok) refreshParticipants(_tok);
            })
            .catch(err => {
                console.log("Error fetching data (likely deleted):", err);
                document.getElementById('page-title').textContent = "삭제된 DB입니다.";
                const mainArea = document.querySelector('.main-editor-area');
                if (mainArea) mainArea.innerHTML = '<div style="text-align:center; padding: 40px; color: #ADB5BD; font-size: 16px;">해당 DB는 삭제되었으므로 열람할 수 없습니다.</div>';
            });
}

// ── 수정 히스토리 패널
function toggleHistoryPanel() {
    const panel = document.getElementById('history-panel');
    if (panel.classList.contains('open')) {
        closeHistoryPanel();
    } else {
        openHistoryPanel();
    }
}
function openHistoryPanel() {
    const panel = document.getElementById('history-panel');
    const overlay = document.getElementById('history-panel-overlay');
    const btn = document.getElementById('btn-history-toggle');
    panel.classList.add('open');
    overlay.style.display = 'block';
    if (btn) btn.classList.add('active');
    const token = new URLSearchParams(window.location.search).get('token');
    if (token) {
        loadHistory(token);
        refreshParticipants(token);
    }
}
function closeHistoryPanel() {
    const panel = document.getElementById('history-panel');
    const overlay = document.getElementById('history-panel-overlay');
    const btn = document.getElementById('btn-history-toggle');
    panel.classList.remove('open');
    overlay.style.display = 'none';
    if (btn) btn.classList.remove('active');
}
async function loadHistory(token) {
    const list = document.getElementById('history-list');
    list.innerHTML = '<div class="history-empty">불러오는 중...</div>';
    const headers = {};
    try {
        const user = firebase.auth().currentUser;
        if (user) headers['Authorization'] = 'Bearer ' + await user.getIdToken();
    } catch (_) {}
    fetch(`${window.location.origin}/api/records/history/${token}`, { headers })
        .then(r => r.json())
        .then(entries => {
            if (!entries.length) {
                list.innerHTML = '<div class="history-empty">아직 수정 기록이 없습니다.</div>';
                return;
            }
            list.innerHTML = entries.map((e, i) => {
                const timeStr = _relativeTime(e.created_at);
                const previewHtml = _buildPreviewDiff(
                    e.service_description_before, e.service_description_snapshot,
                    e.agent_opinion_before, e.agent_opinion_snapshot,
                    e.encrypted_blob_snapshot
                );
                return `<div class="history-entry" onclick="openHistoryDetail(${i})">
                    <div class="history-entry-top">
                        <span class="history-entry-time">${timeStr}</span>
                    </div>
                    <div class="history-editor">수정인: <span class="participant-tag" style="background:${_editorColor(e.editor_name)};font-size:11px;padding:2px 8px;">${_esc(e.editor_name || '알 수 없음')}</span></div>
                    <div class="history-preview">${previewHtml}</div>
                </div>`;
            }).join('');
            window._historyEntries = entries;
        })
        .catch(() => {
            list.innerHTML = '<div class="history-empty">불러오기 실패</div>';
        });
}
function openHistoryDetail(idx) {
    const entries = window._historyEntries || [];
    const e = entries[idx];
    if (!e) return;
    // _before 컬럼 우선 사용 (저장 직전 상태), 없으면 이전 항목 스냅샷으로 폴백
    const hasBefore = e.service_description_before !== null && e.service_description_before !== undefined;
    const prev = hasBefore ? e : (entries[idx + 1] || null);

    const timeStr = _toUtcDate(e.created_at).toLocaleString('ko-KR', { month: 'long', day: 'numeric', weekday: 'short', hour: '2-digit', minute: '2-digit' });
    const isEncrypted = !e.service_description_snapshot && !!e.encrypted_blob_snapshot;

    function diffSection(label, before, after) {
        const ops = _textDiff(before, after);
        const beforeHtml = ops ? _renderBefore(ops) : _esc(before);
        const afterHtml  = ops ? _renderAfter(ops)  : _esc(after);
        const hasChange = ops ? ops.some(o => o.t !== '=') : before !== after;
        const delChars = ops ? ops.filter(o => o.t === '-').reduce((n, o) => n + o.v.length, 0) : 0;
        const addChars = ops ? ops.filter(o => o.t === '+').reduce((n, o) => n + o.v.length, 0) : 0;
        const countBadges = hasChange ? [
            delChars > 0 ? `<span class="diff-count del-count">-${delChars}자</span>` : '',
            addChars > 0 ? `<span class="diff-count add-count">+${addChars}자</span>` : '',
        ].filter(Boolean).join('') : '';
        return `
        <div class="history-diff-section">
            <div class="history-diff-label">${label}${countBadges ? ' ' + countBadges : ''}</div>
            <div class="history-diff-row${!hasChange ? ' no-change' : ''}">
                <div class="history-diff-col">
                    <div class="history-diff-col-label before-label">이전</div>
                    <div class="history-diff-text">${beforeHtml || '<span style="color:#CED4DA;">없음</span>'}</div>
                </div>
                <div class="history-diff-divider"></div>
                <div class="history-diff-col">
                    <div class="history-diff-col-label after-label">이후</div>
                    <div class="history-diff-text">${afterHtml || '<span style="color:#CED4DA;">없음</span>'}</div>
                </div>
            </div>
            ${!hasChange ? '<div class="history-diff-unchanged">변경 없음</div>' : ''}
        </div>`;
    }

    const bodyHtml = isEncrypted
        ? '<div class="history-empty" style="padding:20px 0;">🔒 암호화된 내용은 복호화 키가 있는 기기에서만 확인 가능합니다.</div>'
        : diffSection('서비스 내용',
              hasBefore ? (e.service_description_before || '') : (prev ? (prev.service_description_snapshot || '') : ''),
              e.service_description_snapshot || '')
        + diffSection('상담원 의견',
              hasBefore ? (e.agent_opinion_before || '') : (prev ? (prev.agent_opinion_snapshot || '') : ''),
              e.agent_opinion_snapshot || '');

    const modal = document.createElement('div');
    modal.className = 'history-detail-modal';
    modal.innerHTML = `
        <div class="history-detail-box">
            <div class="history-detail-header">
                <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
                    <span class="participant-tag" style="background:${_editorColor(e.editor_name)};font-size:12px;">${_esc(e.editor_name || '알 수 없음')}</span>
                    <span class="history-detail-meta">${timeStr}</span>
                </div>
                <button class="history-detail-close" onclick="this.closest('.history-detail-modal').remove()">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                </button>
            </div>
            <div class="history-detail-body">${bodyHtml}</div>
        </div>`;
    modal.addEventListener('click', (ev) => { if (ev.target === modal) modal.remove(); });
    document.body.appendChild(modal);
}

// word-level diff (LCS 기반)
function _textDiff(before, after) {
    const tok = s => (s || '').match(/[^\s]+|\s+/g) || [];
    const a = tok(before), b = tok(after);
    if (a.length + b.length > 3000) return null; // 너무 길면 스킵
    const m = a.length, n = b.length;
    const dp = Array.from({length: m + 1}, () => new Int32Array(n + 1));
    for (let i = 1; i <= m; i++)
        for (let j = 1; j <= n; j++)
            dp[i][j] = a[i-1] === b[j-1] ? dp[i-1][j-1] + 1 : Math.max(dp[i-1][j], dp[i][j-1]);
    const ops = [];
    let i = m, j = n;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && a[i-1] === b[j-1]) { ops.unshift({t:'=', v:a[i-1]}); i--; j--; }
        else if (j > 0 && (i === 0 || dp[i][j-1] >= dp[i-1][j])) { ops.unshift({t:'+', v:b[j-1]}); j--; }
        else { ops.unshift({t:'-', v:a[i-1]}); i--; }
    }
    return ops;
}
function _renderBefore(ops) {
    return ops.map(o => {
        if (o.t === '=') return _esc(o.v);
        if (o.t === '-') return `<del class="diff-del">${_esc(o.v)}</del>`;
        return '';
    }).join('');
}
function _renderAfter(ops) {
    return ops.map(o => {
        if (o.t === '=') return _esc(o.v);
        if (o.t === '+') return `<ins class="diff-ins">${_esc(o.v)}</ins>`;
        return '';
    }).join('');
}
function _toUtcDate(dateStr) {
    // MySQL datetime는 UTC로 저장됨 — 'Z' 추가로 브라우저가 UTC로 파싱하게 함
    if (!dateStr) return new Date(0);
    return new Date(dateStr.replace(' ', 'T') + (dateStr.includes('Z') || dateStr.includes('+') ? '' : 'Z'));
}
// 히스토리 목록 미리보기: diff 인라인 표시 + 삭제/추가 글자 수
// descBefore/descAfter: 서비스 내용, opBefore/opAfter: 상담원 의견
function _buildPreviewDiff(descBefore, descAfter, opBefore, opAfter, encryptedBlob) {
    if (encryptedBlob && !descBefore && !descAfter && !opBefore && !opAfter) return '🔒 암호화된 내용';
    // 변경된 필드를 찾아 표시 (서비스 내용 우선, 없으면 상담원 의견)
    function _buildFieldDiff(before, after) {
        const b = before || '';
        const a = after || '';
        if (!b && !a) return null; // 내용 없음
        if (b === a) return null;  // 변경 없음
        const ops = _textDiff(b, a);
        if (!ops) return null;
        const delChars = ops.filter(o => o.t === '-').reduce((n, o) => n + o.v.length, 0);
        const addChars = ops.filter(o => o.t === '+').reduce((n, o) => n + o.v.length, 0);
        if (delChars === 0 && addChars === 0) return null;
        let charCount = 0;
        const diffHtml = ops.map(o => {
            if (charCount > 100) return '';
            charCount += o.v.length;
            if (o.t === '=') return _esc(o.v);
            if (o.t === '-') return `<del class="diff-del">${_esc(o.v)}</del>`;
            return `<ins class="diff-ins">${_esc(o.v)}</ins>`;
        }).join('') + (charCount > 100 ? '…' : '');
        const badges = [];
        if (delChars > 0) badges.push(`<span class="diff-count del-count">-${delChars}자</span>`);
        if (addChars > 0) badges.push(`<span class="diff-count add-count">+${addChars}자</span>`);
        return `<span>${diffHtml}</span>${badges.length ? ' ' + badges.join('') : ''}`;
    }
    const descDiff = _buildFieldDiff(descBefore, descAfter);
    const opDiff = _buildFieldDiff(opBefore, opAfter);
    if (descDiff && opDiff) return descDiff + '<br>' + opDiff;
    if (descDiff) return descDiff;
    if (opDiff) return opDiff;
    // 변경 없음 — 최신 내용 미리보기
    const preview = (descAfter || opAfter || '').slice(0, 60);
    return _esc(preview) + (preview.length === 60 ? '…' : '') || '<span style="color:#ADB5BD;">내용 없음</span>';
}
function _relativeTime(dateStr) {
    const diff = Date.now() - _toUtcDate(dateStr).getTime();
    const m = Math.floor(diff / 60000);
    if (m < 1) return '방금 전';
    if (m < 60) return `${m}분 전`;
    const h = Math.floor(m / 60);
    if (h < 24) return `${h}시간 전`;
    const d = Math.floor(h / 24);
    if (d < 30) return `${d}일 전`;
    return _toUtcDate(dateStr).toLocaleDateString('ko-KR', { month: 'long', day: 'numeric', weekday: 'short' });
}
function _esc(str) {
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

// ── 참여자 목록 새로고침 (세션 기반 — Firebase 만료 시 토큰 폴백)
async function refreshParticipants(token) {
    try {
        const headers = {};
        const user = firebase.auth().currentUser;
        if (user) {
            try { headers['Authorization'] = 'Bearer ' + await user.getIdToken(true); } catch(_) {}
        }
        const r = await fetch(`${window.location.origin}/api/records/share/${token}/participants`, { headers });
        if (!r.ok) return;
        const data = await r.json();
        renderParticipants(data.owner_name, data.viewers || []);
    } catch (_) {}
}

// ── 공유 참여자 태그 렌더링
const _VIEWER_COLORS = ['#10B981','#3B82F6','#F59E0B','#EF4444','#8B5CF6','#EC4899'];
function _editorColor(name) {
    if (!name) return '#ADB5BD';
    let h = 0;
    for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) | 0;
    return _VIEWER_COLORS[Math.abs(h) % _VIEWER_COLORS.length];
}
function renderParticipants(ownerName, viewers) {
    // 공통 HTML 조각 생성
    const ownerColor = _editorColor(ownerName);
    let html = `<div class="participant-group">
        <span class="participant-label">DB 생성자</span>
        <span class="participant-tag" style="background:${ownerColor};">${ownerName || '알 수 없음'}</span>
    </div>`;
    if (viewers && viewers.length > 0) {
        html += `<div class="participant-group"><span class="participant-label">공유받은 사람</span>`;
        viewers.forEach((name) => {
            const c = _editorColor(name);
            html += `<span class="participant-tag viewer-tag" style="background:${c}22;color:${c};border:1.5px solid ${c}66;">${name || '알 수 없음'}</span>`;
        });
        html += `</div>`;
    }
    // PC 헤더 영역
    const el = document.getElementById('share-participants');
    if (el) { el.innerHTML = html; el.style.display = 'flex'; }
    // 모바일 하단 CTA 영역
    const mobileEl = document.getElementById('mobile-participants');
    if (mobileEl) { mobileEl.innerHTML = html; }
}

// ── 본인 DB: 알림 버튼 숨김 (저장 버튼 없음)
function setOwnerReadOnlyMode() {
    document.querySelectorAll('.notify-btn').forEach(btn => btn.style.display = 'none');
}

// ── 토스트 알림 (간단한 UI 피드백)
function showToast(msg, duration = 3000) {
    let toast = document.getElementById('dash-toast');
    if (!toast) {
        toast = document.createElement('div');
        toast.id = 'dash-toast';
        toast.style.cssText = [
            'position:fixed', 'bottom:90px', 'left:50%', 'transform:translateX(-50%)',
            'background:#1a1a2e', 'color:#fff', 'padding:12px 20px',
            'border-radius:12px', 'font-size:14px', 'font-weight:500',
            'box-shadow:0 4px 20px rgba(0,0,0,0.25)', 'z-index:99999',
            'transition:opacity 0.3s', 'white-space:nowrap',
            'font-family:Pretendard,sans-serif',
        ].join(';');
        document.body.appendChild(toast);
    }
    toast.textContent = '✓ ' + msg;
    toast.style.opacity = '1';
    clearTimeout(toast._hideTimer);
    toast._hideTimer = setTimeout(() => { toast.style.opacity = '0'; }, duration);
}

// Initialize — 데이터 fetch 없이 인증 모달만 표시
window.onload = () => {
    const mainTextarea = document.getElementById('main-editor');
    const opinionTextarea = document.getElementById('opinion-editor');

    // 바로 편집 가능한 상태로 시작
    mainTextarea.readOnly = false;
    opinionTextarea.readOnly = false;
    mainTextarea.style.background = '#fff';
    mainTextarea.style.cursor = 'text';
    opinionTextarea.style.background = '#fff';
    opinionTextarea.style.cursor = 'text';

    function autoResize() {
        this.style.height = 'auto';
        this.style.height = (this.scrollHeight) + 'px';
    }
    mainTextarea.addEventListener('input', autoResize);
    opinionTextarea.addEventListener('input', autoResize);

    // 초기 CTA 비활성화
    updateUndoRedoButtons();
    updateCTAState();

    const urlParams = new URLSearchParams(window.location.search);
    const token = urlParams.get('token');

    if (!token) {
        document.getElementById('auth-modal').style.display = 'none';
        return;
    }

    // 세션에서 최초 전송 완료 여부 복원
    if (sessionStorage.getItem('dash_notify_sent_' + token)) {
        hasEverSentNotify = true;
        const headerBtn = document.getElementById('btn-notify-header');
        const mobileBtn = document.getElementById('btn-notify-mobile');
        if (headerBtn) headerBtn.textContent = '저장 후 전송';
        if (mobileBtn) mobileBtn.textContent = '저장 후 전송';
    }

    // 새 탭 OAuth 복귀 처리 — oauth_callback.html이 sessionStorage에 저장한 토큰 처리
    const pendingToken = sessionStorage.getItem('pending_oauth_token');
    const pendingError = sessionStorage.getItem('pending_oauth_error');
    if (pendingToken) {
        sessionStorage.removeItem('pending_oauth_token');
        document.getElementById('auth-modal').style.display = 'flex';
        const credential = firebase.auth.GoogleAuthProvider.credential(null, pendingToken);
        firebase.auth().signInWithCredential(credential).then(async (result) => {
            if (!_loginHandled) {
                _loginHandled = true;
                await handleReviewerLogin(result.user);
            }
        }).catch((e) => {
            document.getElementById('auth-error').textContent = '오류: ' + (e.message || e.code);
        });
        return;
    }
    if (pendingError) {
        sessionStorage.removeItem('pending_oauth_error');
        document.getElementById('auth-modal').style.display = 'flex';
        document.getElementById('auth-error').textContent = '오류: ' + pendingError;
        return;
    }

    // 인앱 브라우저 감지 — 구글 로그인 불가 안내
    if (isInAppBrowser()) {
        document.getElementById('auth-modal').style.display = 'none';
        document.getElementById('inapp-modal').style.display = 'flex';
        return;
    }

    // 재방문 세션 복원 (signInWithCredential 후 Firebase가 세션 캐시에 저장한 경우)
    _loginHandled = false;
    firebase.auth().onAuthStateChanged(async (user) => {
        if (_loginHandled) return;
        if (user) {
            _loginHandled = true;
            try {
                await handleReviewerLogin(user);
            } catch (e) {
                _loginHandled = false;
                document.getElementById('auth-error').textContent = '오류: ' + (e.message || e.code);
                document.getElementById('auth-modal').style.display = 'flex';
                const btn = document.getElementById('btn-google-login');
                if (btn) { btn.disabled = false; btn.textContent = 'Google 계정으로 로그인'; }
            }
        } else {
            document.getElementById('auth-modal').style.display = 'flex';
        }
    });

    // 탭 포커스 복귀 시 참여자 목록 자동 갱신 (30초 디바운스)
    let _participantsRefreshTimer = null;
    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') {
            clearTimeout(_participantsRefreshTimer);
            _participantsRefreshTimer = setTimeout(() => {
                const t = new URLSearchParams(window.location.search).get('token');
                if (t) refreshParticipants(t);
            }, 30000); // 30초 후 1회만 실행
        } else {
            clearTimeout(_participantsRefreshTimer);
        }
    });
};

function updateUI(data) {
    _logEvent('share_link_visited');
    document.getElementById('page-title').textContent = `${data.case_name || '미지정'} 아동 사례`;
    
    // Update Author Name
    _recordOwnerName = data.user_name || '';
    const authorEl = document.getElementById('author-name');
    if (authorEl) {
        authorEl.textContent = `${data.user_name || '관리자'} 상담원 작성`;
    }
    
    const mobileTag = document.getElementById('mobile-child-tag');
    if (mobileTag) {
        mobileTag.innerHTML = `
            <span style="font-size: 13px; font-weight: 600; color: #4e5968;">${_esc(data.user_name || '담당자')} 작성</span>
        `;
    }
    
    // 새로고침 전 저장된 초안이 있으면 서버 원본보다 우선 복원
    const _token = new URLSearchParams(window.location.search).get('token');
    const _saved = _token ? sessionStorage.getItem('dash_draft_' + _token) : null;
    let mainVal = data.service_description || '';
    let opinionVal = data.agent_opinion || '';
    if (_saved) {
        try {
            const parsed = JSON.parse(_saved);
            mainVal = parsed.main ?? mainVal;
            opinionVal = parsed.opinion ?? opinionVal;
        } catch (_) {}
    }

    document.getElementById('main-editor').value = mainVal;
    document.getElementById('opinion-editor').value = opinionVal;

    // Auto resize after setting value
    document.getElementById('main-editor').dispatchEvent(new Event('input'));
    document.getElementById('opinion-editor').dispatchEvent(new Event('input'));
    
    const metaList = [
        { label: '대상자', value: data.target ? (Array.isArray(data.target) ? data.target.join(' · ') : data.target.replace(/,/g, ' · ')) : '-' },
        { label: '제공구분', value: data.provision_type || '-' },
        { label: '제공방법', value: data.method || '-' },
        { label: '서비스유형', value: data.service_type || '-' },
        { label: '제공서비스', value: (data.service_category && data.service_name) ? `${data.service_category} :: ${data.service_name}` : (data.service_name || '-') },
        { label: '제공장소', value: data.location || '-' },
        { label: '제공일시', value: formatDateTimeRange(data.start_time, data.end_time) },
        { label: '이동시간', value: data.travel_time ? `${data.travel_time}분` : '-' },
        { label: '제공횟수', value: data.service_count ? `${data.service_count}회` : '-' },
    ];
    
    const pcGrid = document.getElementById('pc-meta-grid');
    const mobileGrid = document.getElementById('mobile-meta-grid');
    
    const htmlObj = metaList.map(m => {
        const isDate = m.label === '제공일시';
        return `
        <div class="meta-item">
            <label>${m.label}</label>
            <span class="${isDate ? 'meta-date-val' : ''}">${m.value}</span>
        </div>
        `;
    }).join('');
    
    pcGrid.innerHTML = htmlObj;
    mobileGrid.innerHTML = htmlObj;

    // 히스토리 초기화 — 저장된 초안이 있으면 baseline과 초안을 함께 넣어 변경사항 유지
    const _baseline = { main: data.service_description || '', opinion: data.agent_opinion || '' };
    editHistory = [_baseline];
    historyIndex = 0;
    if (_saved && (mainVal !== _baseline.main || opinionVal !== _baseline.opinion)) {
        editHistory.push({ main: mainVal, opinion: opinionVal });
        historyIndex = 1;
    }
    updateUndoRedoButtons();
    updateCTAState();

    // ── CTA 분기: is_shared_db 여부에 따라 버튼 전환
    if (data.is_shared_db) {
        _switchToSaveMode();
    }
}

// ── "내 DB로 저장" 모드로 전환 (notify 버튼 숨기고 save 버튼 표시)
function _switchToSaveMode() {
    document.querySelectorAll('.notify-btn').forEach(btn => {
        btn.style.display = 'none';
    });
    const saveHeader = document.getElementById('btn-save-to-my-db-header');
    const saveMobile = document.getElementById('btn-save-to-my-db-mobile');
    if (saveHeader) { saveHeader.style.display = ''; saveHeader.disabled = false; saveHeader.style.opacity = '1'; }
    if (saveMobile) { saveMobile.style.display = ''; saveMobile.disabled = false; saveMobile.style.opacity = '1'; }
}

function openSaveToMyDbModal() {
    const modal = document.getElementById('save-to-my-db-modal');
    if (!modal) return;
    const msgEl = modal.querySelector('p');
    if (msgEl) {
        const name = _recordOwnerName ? `${_esc(_recordOwnerName)} 상담원` : '담당 상담원';
        msgEl.innerHTML = `이 DB를 내 계정에 저장할까요?<br>저장하면 ${name}에게 알림이 전송돼요.`;
    }
    modal.style.display = 'flex';
}

function closeSaveToMyDbModal() {
    const modal = document.getElementById('save-to-my-db-modal');
    if (modal) modal.style.display = 'none';
}

async function confirmSaveToMyDb() {
    const token = new URLSearchParams(window.location.search).get('token');
    if (!token) return;

    const confirmBtn = document.getElementById('btn-confirm-save-to-my-db');
    if (confirmBtn) { confirmBtn.disabled = true; confirmBtn.textContent = '저장 중...'; }

    const serviceDescription = document.getElementById('main-editor').value;
    const agentOpinion = document.getElementById('opinion-editor').value || '';

    try {
        const user = firebase.auth().currentUser;
        if (!user) throw new Error('로그인이 필요합니다.');
        const idToken = await user.getIdToken(true);

        const body = { service_description: serviceDescription, agent_opinion: agentOpinion };
        const encKey = _getEncKey(token);
        if (encKey && window.currentRecord) {
            try {
                const updatedData = { ...window.currentRecord, serviceDescription, agentOpinion };
                const aesKey = CryptoJS.enc.Utf8.parse(encKey.padEnd(32).substring(0, 32));
                const iv = CryptoJS.lib.WordArray.random(16);
                const encrypted = CryptoJS.AES.encrypt(JSON.stringify(updatedData), aesKey, { iv });
                body.encrypted_blob = iv.toString(CryptoJS.enc.Base64) + ':' + encrypted.toString();
            } catch (e) { console.error('Encryption failed:', e); }
        }

        const res = await fetch(`/api/records/save-to-my-db/${token}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${idToken}` },
            body: JSON.stringify(body),
        });
        const data = await res.json();

        if (!res.ok) {
            if (data.error === 'not_registered') {
                showToast('DASH 앱에 가입된 계정만 저장할 수 있어요.');
            } else if (data.error === 'own_record') {
                showToast('자신이 작성한 DB는 저장할 수 없어요.');
            } else {
                showToast('저장에 실패했습니다. 다시 시도해 주세요.');
            }
            return;
        }

        // 저장 시점 스냅샷 기록 (이후 변경 감지용)
        _savedToMyDbDesc = serviceDescription;
        _savedToMyDbOpinion = agentOpinion;

        closeSaveToMyDbModal();
        const saveHeader = document.getElementById('btn-save-to-my-db-header');
        const saveMobile = document.getElementById('btn-save-to-my-db-mobile');
        [saveHeader, saveMobile].forEach(btn => {
            if (!btn) return;
            btn.disabled = true;
            btn.textContent = '저장 완료 ✓';
            btn.style.opacity = '0.6';
            btn.style.cursor = 'not-allowed';
        });
        showToast('내 DB에 저장되었어요. 담당자에게도 알림을 보냈어요.', 4000);
        _logEvent('save_to_my_db');
    } catch (err) {
        showToast('오류가 발생했습니다: ' + err.message);
        console.error(err);
    } finally {
        if (confirmBtn) { confirmBtn.disabled = false; confirmBtn.textContent = '저장'; }
    }
}
