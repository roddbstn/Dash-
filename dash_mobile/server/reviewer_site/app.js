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

// ── Google 로그인 (popup 방식 — Firebase Hosting 불필요)
async function signInWithGoogle() {
    const btn = document.getElementById('btn-google-login');
    const errorEl = document.getElementById('auth-error');
    btn.disabled = true;
    btn.textContent = '로그인 중...';
    errorEl.textContent = '';

    try {
        const provider = new firebase.auth.GoogleAuthProvider();
        const result = await firebase.auth().signInWithPopup(provider);
        await handleReviewerLogin(result.user);
    } catch (e) {
        errorEl.textContent = '오류: ' + (e.message || e.code);
        btn.disabled = false;
        btn.textContent = 'Google 계정으로 로그인';
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

    const idToken = await user.getIdToken();
    const res = await fetch(`/api/records/reviewer-login/${token}`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${idToken}` },
    });
    const data = await res.json();

    if (res.ok && data.ok) {
        sessionStorage.setItem('dash_auth_' + token, '1');
        document.getElementById('auth-modal').style.display = 'none';
        // 프로필 아바타 표시
        showUserProfile(user);
        // 본인 DB 접근 시 편집 UI 숨김 + encryption_key 세션 저장
        if (data.isOwner) {
            setOwnerReadOnlyMode();
            if (data.encryptionKey) {
                sessionStorage.setItem('dash_key_' + token, data.encryptionKey);
            }
        }
        loadRecord(token);
    } else if (data.error === 'not_registered') {
        // 모바일 앱 미가입 → Firebase 세션 즉시 소거 후 안내 화면 표시
        await firebase.auth().signOut();
        document.getElementById('auth-modal').style.display = 'none';
        document.getElementById('not-registered-modal').style.display = 'flex';
    } else {
        document.getElementById('auth-modal').style.display = 'flex';
        document.getElementById('auth-error').textContent = data.error || '접근 권한이 없습니다.';
        const btn = document.getElementById('btn-google-login');
        btn.disabled = false;
        btn.textContent = 'Google 계정으로 로그인';
    }
}

let isInfoExpanded = false;
let saveTimeout = null;
let isEditMode = true; // 항상 편집 모드
let editHistory = []; // [{main, opinion}, ...]
let historyIndex = -1;

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
    const hasChanges = historyIndex > 0;
    document.querySelectorAll('.notify-btn').forEach(btn => {
        btn.disabled = !hasChanges;
        btn.style.opacity = hasChanges ? '1' : '0.45';
        btn.style.cursor = hasChanges ? 'pointer' : 'not-allowed';
        if (btn.id === 'btn-notify-mobile') {
            btn.style.background = hasChanges ? '' : '#ADB5BD';
        }
    });
}

// ── 자동 저장 ────────────────────────────────────────────────
function handleTyping() {
    const status = document.getElementById('save-status');
    status.textContent = '저장 중...';
    status.style.opacity = '1';

    if (saveTimeout) clearTimeout(saveTimeout);

    saveTimeout = setTimeout(async () => {
        const now = new Date();
        const timeStr = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`;

        const main = document.getElementById('main-editor').value;
        const opinion = document.getElementById('opinion-editor').value || '';

        // 메모리 내 currentRecord 갱신 (re-encryption 시 최신 값 사용)
        if (window.currentRecord) {
            window.currentRecord.serviceDescription = main;
            window.currentRecord.agentOpinion = opinion;
        }

        // 히스토리에 현재 상태 push (내용이 변경된 경우만)
        const last = editHistory[historyIndex] || {};
        if (last.main !== main || last.opinion !== opinion) {
            pushHistory(main, opinion);
        }

        // 세션 임시 저장 (새로고침 복원용)
        persistDraft(main, opinion);

        // ── 서버 자동 저장 ──────────────────────────────────────
        const token = new URLSearchParams(window.location.search).get('token');
        if (token) {
            try {
                const body = { service_description: main, agent_opinion: opinion };

                // 암호화 키가 있으면 re-encrypt하여 encrypted_blob도 함께 저장
                const _qp = new URLSearchParams(window.location.search);
                let encKey = _qp.get('key') || window.location.hash.substring(1) || sessionStorage.getItem('dash_key_' + token) || '';
                if (encKey && window.currentRecord) {
                    try {
                        const updatedData = { ...window.currentRecord, serviceDescription: main, agentOpinion: opinion };
                        const key = CryptoJS.enc.Utf8.parse(encKey.padEnd(32).substring(0, 32));
                        const iv = CryptoJS.lib.WordArray.random(16);
                        const encrypted = CryptoJS.AES.encrypt(JSON.stringify(updatedData), key, { iv });
                        body.encrypted_blob = iv.toString(CryptoJS.enc.Base64) + ':' + encrypted.toString();
                    } catch (e) {
                        console.warn('[AutoSave] 암호화 실패, 평문만 저장:', e);
                    }
                }

                const res = await fetch(`/api/records/share/${token}`, {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(body),
                });
                if (!res.ok) throw new Error(`HTTP ${res.status}`);
                status.textContent = `✓ ${timeStr} 저장됨`;
            } catch (e) {
                console.error('[AutoSave] 서버 저장 실패:', e);
                status.textContent = `⚠ 저장 실패 (${timeStr})`;
            }
        } else {
            status.textContent = `✓ ${timeStr} 저장됨`;
        }

        setTimeout(() => {
            status.style.opacity = '0.6';
        }, 2000);
    }, 1500);
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

function confirmNotify() {
    const urlParams = new URLSearchParams(window.location.search);
    const token = urlParams.get('token');
    // 쿼리 파라미터 ?key= 우선, fragment #key 폴백
    const _qp = new URLSearchParams(window.location.search);
    const encKey = _qp.get('key') || window.location.hash.substring(1);

    if (!token) {
        alert('토큰 정보가 없어 완료할 수 없습니다.');
        return closeModal();
    }
    
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
            // Still send raw fields for legacy/transition support or specific meta needs, 
            // but the server should ideally ignore them.
            body.service_description = ''; 
            body.agent_opinion = '';
        } catch (e) {
            console.error("Encryption failed:", e);
        }
    }

    fetch(`/api/records/reviewed/${token}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
    })
    .then(res => res.json())
    .then(data => {
        if (data.error) throw new Error(data.error);
        alert('사례 담당자에게 검토 완료 알림을 보냈습니다.');
        closeModal();
    })
    .catch(err => {
        alert('처리 중 오류가 발생했습니다.');
        console.error(err);
    });
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
    // 1) 쿼리 파라미터 ?key= 우선 (메시지 앱이 fragment를 제거하는 경우 대응)
    const urlParams = new URLSearchParams(window.location.search);
    const qKey = urlParams.get('key');
    if (qKey) {
        encKey = qKey;
    } else {
        // 2) 이전 방식 호환: URL fragment #key 또는 #KEY
        const hash = window.location.hash.substring(1);
        if (hash) {
            const parts = hash.split('key=');
            encKey = parts.length > 1 ? parts[1] : parts[0];
        }
    }
    // 3) 오너 로그인 시 서버에서 받아 세션에 저장된 키 (URL에 키가 없는 경우)
    if (!encKey) {
        encKey = sessionStorage.getItem('dash_key_' + token) || "";
    }

    fetch(`${window.location.origin}/api/records/share/${token}`)
        .then(res => {
            if (!res.ok) throw new Error(`HTTP error! status: ${res.status}`);
            return res.json();
        })
        .then(data => {
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
                updateUI(data);
            })
            .catch(err => {
                console.log("Error fetching data (likely deleted):", err);
                document.getElementById('page-title').textContent = "삭제된 DB입니다.";
                const mainArea = document.querySelector('.main-editor-area');
                if (mainArea) mainArea.innerHTML = '<div style="text-align:center; padding: 40px; color: #ADB5BD; font-size: 16px;">해당 DB는 삭제되었으므로 열람할 수 없습니다.</div>';
            });
}

// ── 본인 DB: 수정 완료 알림 버튼만 숨김 (편집 및 자동저장은 허용)
function setOwnerReadOnlyMode() {
    // 수정 완료 알림 버튼만 숨김 (오너는 FCM 알림 불필요)
    document.querySelectorAll('.notify-btn').forEach(btn => btn.style.display = 'none');
    // 오너임을 표시 (status 영역)
    const status = document.getElementById('save-status');
    if (status) { status.textContent = '내 DB · 수정 내용은 자동 저장됩니다'; status.style.opacity = '0.7'; }
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

    // 인앱 브라우저 감지 — 구글 로그인 불가 안내
    if (isInAppBrowser()) {
        document.getElementById('auth-modal').style.display = 'none';
        document.getElementById('inapp-modal').style.display = 'flex';
        return;
    }

    // popup 방식: onAuthStateChanged만으로 세션 복원 처리
    // (팝업 로그인은 signInWithGoogle()에서 직접 처리, 여기서는 재방문 세션만)
    let _loginHandled = false;
    firebase.auth().onAuthStateChanged(async (user) => {
        if (_loginHandled) return;
        if (user) {
            _loginHandled = true;
            await handleReviewerLogin(user);
        } else {
            document.getElementById('auth-modal').style.display = 'flex';
        }
    });
};

function updateUI(data) {
    document.getElementById('page-title').textContent = `${data.case_name || '미지정'} 아동 사례`;
    
    // Update Author Name
    const authorEl = document.getElementById('author-name');
    if (authorEl) {
        authorEl.textContent = `${data.user_name || '관리자'} 상담원 작성`;
    }
    
    const mobileTag = document.getElementById('mobile-child-tag');
    if (mobileTag) {
        mobileTag.innerHTML = `
            <span style="font-size: 13px; font-weight: 600; color: #4e5968;">${data.user_name || '담당자'} 작성</span>
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
        { label: '제공서비스', value: (data.service_category && data.service_name) ? `${data.service_category}: ${data.service_name}` : (data.service_name || '-') },
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
}
