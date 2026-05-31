// ==============================================
// sidepanel.js — Main UI, State, and App Logic
// Auth: auth.js | PIN/Crypto: pin.js | Config: core/config.js
// ==============================================

// ===== 상태 관리 =====
let currentUser = null;   // { uid, email }
let currentOAuthToken = null; // Google OAuth 토큰 (API 인증용)
let records = [];          // 서버에서 가져온 기록 목록
let historyRecords = [];   // 기입 완료(Injected) 기록
let selectedRecordId = null; // 현재 선택된 기록 ID
let currentMainTab = 'pending'; // 'pending' | 'shared' | 'history'

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
document.getElementById('tab-pending')?.addEventListener('click', () => switchMainTab('pending'));
document.getElementById('tab-shared')?.addEventListener('click', () => switchMainTab('shared'));
document.getElementById('tab-history')?.addEventListener('click', () => switchMainTab('history'));
const btnInject = document.getElementById('btn-inject');
const btnBackToList = document.getElementById('btn-back-to-list');
const userEmailEl = document.getElementById('user-email');
const profilePicEl = document.getElementById('profile-pic');
const profileNameEl = document.getElementById('profile-name');
const statusBar = document.getElementById('status-bar');
const recordsContainer = document.getElementById('records-container');
const emptyState = document.getElementById('empty-state');
const actionBar = document.getElementById('action-bar');

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
        // launchWebAuthFlow: Web client ID로 동작 — getAuthToken은 Chrome App 타입 client 필요
        const token = await getGoogleAccessToken(true);
        await handleGoogleLogin(token);
    } catch (error) {
        console.error('Google 로그인 실패:', error);
        btnGoogleLogin.disabled = false;
        if (contentsSpan) contentsSpan.textContent = 'Google 계정으로 로그인';
        showLoginError(error.message);
    }
});


function performLogout() {
    currentUser = null;
    currentOAuthToken = null;
    selectedRecordId = null;
    records = [];
    vaultKeys = {};
    pinAuthenticated = false;
    chrome.storage.local.remove(['dashUser']);
    chrome.storage.session.remove(['cachedVaultKeys', 'cachedOAuthToken', 'cachedDerivedKey']);
    pinInput = '';
    pinFailCount = 0;
    pinLockUntil = 0;

    // 버튼 상태 초기화
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
btnFooterLogout?.addEventListener('click', () => {
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

// 계정이 존재하지 않을 때 (삭제된 계정으로 접근 시)
function showAccountDeletedError() {
    performLogout();
    let el = document.getElementById('login-error-msg');
    if (!el) {
        el = document.createElement('p');
        el.id = 'login-error-msg';
        el.style.cssText = 'margin-top:12px;font-size:12px;color:#DC2626;text-align:center;line-height:1.5;padding:0 8px;';
        btnGoogleLogin.insertAdjacentElement('afterend', el);
    }
    el.textContent = '등록되지 않은 계정이에요. DASH 모바일 앱에서 가입 후 이용해주세요.';
    el.style.display = 'block';
}

// API 응답 상태에 따른 공통 에러 처리
// 401: 토큰 만료(세션 문제) / 403: 서버가 해당 계정을 거부(계정 삭제·미가입)
function handleApiStatus(status) {
    if (status === 403) {
        showAccountDeletedError();
        return true; // 처리됨
    }
    if (status === 401) {
        // 토큰 만료 → 재로그인 유도 (계정 삭제 메시지 표시하지 않음)
        performLogout();
        showLoginError('로그인 세션이 만료되었습니다. 다시 로그인해주세요.');
        return true; // 처리됨
    }
    return false;
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
    if (currentUser?.name) {
        profileNameEl.textContent = `${currentUser.name}님`;
        profileNameEl.classList.remove('hidden');
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
    document.getElementById('tab-shared').classList.toggle('active', tab === 'shared');
    document.getElementById('tab-history').classList.toggle('active', tab === 'history');
    document.getElementById('tab-content-pending').classList.toggle('hidden', tab !== 'pending');
    document.getElementById('tab-content-shared').classList.toggle('hidden', tab !== 'shared');
    document.getElementById('tab-content-history').classList.toggle('hidden', tab !== 'history');

    // selection-bar: 이전 기록 탭에서는 숨김, 나머지는 PIN 인증 시 표시
    const selBar = document.getElementById('selection-bar');
    if (selBar) {
        if (tab === 'history' || !pinAuthenticated) {
            selBar.classList.add('hidden');
        } else {
            selBar.classList.remove('hidden');
        }
    }

    if (tab === 'history') fetchHistory();
    if (tab === 'shared') renderSharedByMe();
}

// ==============================================
// 3. 서버에서 기록 가져오기 (Magazine)
// ==============================================

async function fetchRecords() {
    await refreshVaultKeys(); // 새로 추가된 공유 DB 암호화 키를 vault에서 갱신
    setStatus('loading', '기록을 불러오는 중...');
    showSkeleton();

    try {
        const userEmail = currentUser?.email;
        if (!userEmail) throw new Error('로그인이 필요합니다.');

        const res = await fetch(`${API_BASE}/records/ready?email=${encodeURIComponent(userEmail)}`, { headers: authHeaders() });
        if (!res.ok) {
            if (handleApiStatus(res.status)) return;
            throw new Error(`서버 오류: ${res.status}`);
        }

        const rawRecords = await res.json();

        // encrypted_blob을 vaultKeys로 복호화 (없으면 레거시 encryption_key 폴백)
        records = await Promise.all(rawRecords.map(async (record) => {
            const vaultKey = record.share_token ? vaultKeys[record.share_token] : null;
            const decryptKey = vaultKey || record.encryption_key || null;
            // 레거시 encryption_key로 복호화 성공 시 vaultKeys에 채워 share 버튼이 사용할 수 있게 함
            if (!vaultKey && decryptKey && record.share_token) {
                vaultKeys[record.share_token] = decryptKey;
            }
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
        const allPendingCount = records.filter(r => r.status !== 'Injected');
        // 공유할 DB(owned + is_shared_db)를 제외한 나의 DB 개수
        const myDbCount = allPendingCount.filter(r => !(r.record_type === 'owned' && r.is_shared_db == 1)).length;
        const pendingCount = allPendingCount.length;

        // 나의 DB 탭 배지 업데이트
        const pendingBadge = document.getElementById('tab-pending-badge');
        if (pendingBadge) {
            if (myDbCount > 0) {
                pendingBadge.textContent = myDbCount;
                pendingBadge.classList.remove('hidden');
            } else {
                pendingBadge.classList.add('hidden');
            }
        }

        if (pendingCount === 0) {
            recordsContainer.innerHTML = '';
            emptyState.classList.remove('hidden');
            if (selectBar) selectBar.classList.add('hidden');
            hidePinSetupBanner();
            setStatus('success', '모든 기록이 처리되었습니다');
        } else {
            emptyState.classList.add('hidden');
            renderRecords();
            if (!pinAuthenticated) {
                if (selectBar) selectBar.classList.add('hidden');
                showPinSetupBanner();
                setStatus('info', '모바일에서 PIN을 설정하면 내용을 볼 수 있어요');
            } else {
                if (selectBar) selectBar.classList.remove('hidden');
                hidePinSetupBanner();
                setStatus('success', '기록을 확인하고 삽입하세요');
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

        // 이전 기록은 사용자 명시적 액션 — throttle 우회하고 vault 강제 갱신 (새 키 반영)
        lastVaultRefreshTime = 0;
        await refreshVaultKeys();

        const res = await fetch(`${API_BASE}/records/history?email=${encodeURIComponent(email)}`, { headers: authHeaders() });
        if (!res.ok) {
            if (handleApiStatus(res.status)) return;
            throw new Error(`서버 오류: ${res.status}`);
        }
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
                const isSameDay = start.getFullYear() === end.getFullYear() &&
                                  start.getMonth() === end.getMonth() &&
                                  start.getDate() === end.getDate();
                if (isSameDay) {
                    dateTimeStr = `${startPart} ${startT} ~ ${endT}`;
                } else {
                    const endDay = dayNames[end.getDay()];
                    const endPart = `${end.getMonth() + 1}.${end.getDate()} (${endDay})`;
                    dateTimeStr = `${startPart} ${startT} ~ ${endPart} ${endT}`;
                }
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
                    <div class="record-info-row"><span class="info-label">기입자</span><span class="info-value">${record.injected_by_name || record.author_name || '-'}</span></div>
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
    const tabs = await chrome.tabs.query({ url: ["*://ncads.go.kr/*", "*://*.ncads.go.kr/*"] });
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
                        const rec = records.find(r => r.id === id);
                        const endpoint = rec?.record_type === 'shared'
                            ? `${API_BASE}/records/shared/${id}`
                            : `${API_BASE}/records/id/${id}`;
                        await fetch(endpoint, { method: 'DELETE', headers: authHeaders() });
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

    const allPending = records.filter(r => r.status !== 'Injected');
    // "내 DB" + "공유받은 DB" → 대기 목록
    const pendingRecords = allPending.filter(r => !(r.record_type === 'owned' && r.is_shared_db == 1));
    // "공유할 DB" → 별도 섹션
    const sharedByMeRecords = allPending.filter(r => r.record_type === 'owned' && r.is_shared_db == 1);

    pendingRecords.forEach(record => {
        const card = document.createElement('div');
        card.className = 'record-card';
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

        const isShared = record.record_type === 'shared';
        const dbTypeBadge = isShared
            ? `<span style="display:inline-block;padding:2px 8px;background:#EBF3FF;color:#1A56DB;border-radius:6px;font-size:10px;font-weight:700;flex-shrink:0;">공유받은 DB</span>`
            : `<span style="display:inline-block;padding:2px 8px;background:#F2F4F6;color:#8B95A1;border-radius:6px;font-size:10px;font-weight:700;flex-shrink:0;">나의 DB</span>`;
        const fromName = isShared
            ? record.author_name
            : (record.injected_by_name && record.injected_by_name !== currentUser?.name)
                ? record.injected_by_name
                : null;
        const fromTag = fromName
            ? `<span style="font-size:11px;color:#8B95A1;font-weight:500;">from ${fromName}</span>`
            : '';
        card.innerHTML = `
            <div class="record-card-header">
                <div class="record-card-header-left">
                    <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;">
                        <span class="record-case-name">${record.case_name || '미지정'} 아동 사례</span>
                        <span class="record-dong">${record.dong || ''}</span>
                    </div>
                </div>
                <div style="display:flex;align-items:center;gap:6px;flex-shrink:0;">${dbTypeBadge}${fromTag}</div>
            </div>
            <div class="record-info-list">
                <div class="record-info-row"><span class="info-label">제공방법</span><span class="info-value">${record.method || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">제공서비스</span><span class="info-value">${(record.service_category && record.service_name) ? record.service_category + ' :: ' + record.service_name : (record.service_name || '-')}</span></div>
                <div class="record-info-row"><span class="info-label">제공일시</span><span class="info-value">${dateTimeStr || '-'}</span></div>
            </div>
            <div class="record-dropdown-toggle" data-target="${dropdownId}">
                <div style="flex: 1;"></div>
                <span class="dropdown-label">상세 보기</span>
                <svg class="dropdown-arrow" width="12" height="12" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M2 4L6 8L10 4" stroke="#ADB5BD" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
            </div>
            <div class="record-dropdown-content hidden" id="${dropdownId}">
                <div class="record-info-list" style="margin-bottom:16px;">
                    <div class="record-info-row"><span class="info-label">대상자</span><span class="info-value">${record.target || '-'}</span></div>
                    <div class="record-info-row"><span class="info-label">제공구분</span><span class="info-value">${record.provision_type || '-'}</span></div>
                    <div class="record-info-row"><span class="info-label">서비스제공유형</span><span class="info-value">${record.service_type === '아보전' ? '아보전서비스' : (record.service_type || '-')}</span></div>
                    <div class="record-info-row"><span class="info-label">제공장소</span><span class="info-value">${record.location || '-'}</span></div>
                    <div class="record-info-row"><span class="info-label">서비스제공횟수</span><span class="info-value">${record.service_count != null ? record.service_count + '회' : '-'}</span></div>
                    <div class="record-info-row"><span class="info-label">이동소요시간</span><span class="info-value">${record.travel_time != null ? record.travel_time + '분' : '-'}</span></div>
                </div>
                <div class="dropdown-section" style="margin-bottom: 16px;">
                    <div style="font-weight: 700; color: #4e5968; font-size: 13px; margin-bottom: 6px;">서비스 내용</div>
                    <div class="dropdown-text" style="background: transparent; padding: 0;">${record.service_description || '(내용 없음)'}</div>
                </div>
                <div class="dropdown-section">
                    <div style="font-weight: 700; color: #4e5968; font-size: 13px; margin-bottom: 6px;">상담원 소견</div>
                    <div class="dropdown-text" style="background: transparent; padding: 0;">${record.agent_opinion || '(소견 없음)'}</div>
                </div>
            </div>
            <div class="record-card-footer" style="display:flex;gap:8px;margin-top:12px;padding-top:4px;">
                <button class="btn-inject-card" data-id="${record.id}" style="
                    display:inline-flex;align-items:center;justify-content:center;gap:4px;
                    flex:1;padding:9px 0;background:#1A56DB;color:#fff;border:none;border-radius:10px;
                    font-size:13px;font-weight:700;cursor:pointer;font-family:inherit;
                ">⚡ DB 삽입</button>
            </div>
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

        // 카드 내 삽입 버튼 → 바로 inject 실행
        const injectCardBtn = card.querySelector('.btn-inject-card');
        if (injectCardBtn) {
            injectCardBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                if (isSelectionMode) return;
                if (record.status === 'Injected') return;
                selectedRecordId = record.id;
                updateInjectButton();
                btnInject.click();
            });
        }

        // 카드 클릭 → 선택 모드일 때만 처리 (삭제용 다중 선택)
        card.addEventListener('click', () => {
            if (!isSelectionMode) return;
            if (selectedForDelete.has(record.id)) {
                selectedForDelete.delete(record.id);
            } else {
                selectedForDelete.set(record.id, selectedForDelete.size + 1);
            }
            renderRecords();
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

    // 공유할 DB 탭 배지 업데이트
    const badge = document.getElementById('tab-shared-badge');
    if (badge) {
        if (sharedByMeRecords.length > 0) {
            badge.textContent = sharedByMeRecords.length;
            badge.classList.remove('hidden');
        } else {
            badge.classList.add('hidden');
        }
    }
    // 공유할 DB 탭이 열려 있으면 즉시 재렌더
    if (currentMainTab === 'shared') renderSharedByMe();
}

function renderSharedByMe() {
    const container = document.getElementById('shared-records-container');
    const emptyState = document.getElementById('shared-empty-state');
    if (!container) return;

    const sharedByMeRecords = records.filter(
        r => r.status !== 'Injected' && r.record_type === 'owned' && r.is_shared_db == 1
    );

    container.innerHTML = '';

    // 공유할 DB 탭 배지 업데이트
    const sharedBadge = document.getElementById('tab-shared-badge');
    if (sharedBadge) {
        if (sharedByMeRecords.length > 0) {
            sharedBadge.textContent = sharedByMeRecords.length;
            sharedBadge.classList.remove('hidden');
        } else {
            sharedBadge.classList.add('hidden');
        }
    }

    if (sharedByMeRecords.length === 0) {
        emptyState && emptyState.classList.remove('hidden');
        return;
    }
    emptyState && emptyState.classList.add('hidden');

    const dayNames = ['일', '월', '화', '수', '목', '금', '토'];

    sharedByMeRecords.forEach(record => {
        const card = document.createElement('div');
        card.className = 'record-card';
        card.dataset.id = record.id;

        let dateTimeStr = '';
        if (record.start_time && record.end_time) {
            const start = new Date(record.start_time.replace(' ', 'T'));
            const end = new Date(record.end_time.replace(' ', 'T'));
            const startDay = dayNames[start.getDay()];
            const startPart = `${start.getMonth()+1}.${start.getDate()} (${startDay})`;
            const startTime = `${String(start.getHours()).padStart(2,'0')}:${String(start.getMinutes()).padStart(2,'0')}`;
            const endTime = `${String(end.getHours()).padStart(2,'0')}:${String(end.getMinutes()).padStart(2,'0')}`;
            const isSameDay = start.getFullYear() === end.getFullYear() &&
                              start.getMonth() === end.getMonth() &&
                              start.getDate() === end.getDate();
            if (isSameDay) {
                dateTimeStr = `${startPart} ${startTime} ~ ${endTime}`;
            } else {
                const endDay = dayNames[end.getDay()];
                const endPart = `${end.getMonth()+1}.${end.getDate()} (${endDay})`;
                dateTimeStr = `${startPart} ${startTime} ~ ${endPart} ${endTime}`;
            }
        }

        const sharedDropdownId = `shared-dropdown-${record.id}`;
        card.innerHTML = `
            <div class="record-card-header">
                <div class="record-card-header-left">
                    <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;">
                        <span class="record-case-name">${record.case_name || '미지정'} 아동 사례</span>
                        <span class="record-dong">${record.dong || ''}</span>
                    </div>
                </div>
                <div style="display:flex;align-items:center;gap:6px;flex-shrink:0;">
                    <span style="display:inline-block;padding:2px 8px;background:#EBF3FF;color:#1A56DB;border-radius:6px;font-size:10px;font-weight:700;flex-shrink:0;">공유할 DB</span>
                </div>
            </div>
            <div class="record-info-list">
                <div class="record-info-row"><span class="info-label">제공방법</span><span class="info-value">${record.method || '-'}</span></div>
                <div class="record-info-row"><span class="info-label">제공서비스</span><span class="info-value">${(record.service_category && record.service_name) ? record.service_category + ' :: ' + record.service_name : (record.service_name || '-')}</span></div>
                <div class="record-info-row"><span class="info-label">제공일시</span><span class="info-value">${dateTimeStr || '-'}</span></div>
            </div>
            <div class="record-dropdown-toggle" data-target="${sharedDropdownId}">
                <div style="flex: 1;"></div>
                <span class="dropdown-label">상세 보기</span>
                <svg class="dropdown-arrow" width="12" height="12" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M2 4L6 8L10 4" stroke="#ADB5BD" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
            </div>
            <div class="record-dropdown-content hidden" id="${sharedDropdownId}">
                <div class="record-info-list" style="margin-bottom:16px;">
                    <div class="record-info-row"><span class="info-label">대상자</span><span class="info-value">${record.target || '-'}</span></div>
                    <div class="record-info-row"><span class="info-label">제공구분</span><span class="info-value">${record.provision_type || '-'}</span></div>
                    <div class="record-info-row"><span class="info-label">서비스제공유형</span><span class="info-value">${record.service_type === '아보전' ? '아보전서비스' : (record.service_type || '-')}</span></div>
                    <div class="record-info-row"><span class="info-label">제공장소</span><span class="info-value">${record.location || '-'}</span></div>
                    <div class="record-info-row"><span class="info-label">서비스제공횟수</span><span class="info-value">${record.service_count != null ? record.service_count + '회' : '-'}</span></div>
                    <div class="record-info-row"><span class="info-label">이동소요시간</span><span class="info-value">${record.travel_time != null ? record.travel_time + '분' : '-'}</span></div>
                </div>
                <div class="dropdown-section" style="margin-bottom: 16px;">
                    <div style="font-weight: 700; color: #4e5968; font-size: 13px; margin-bottom: 6px;">서비스 내용</div>
                    <div class="dropdown-text" style="background: transparent; padding: 0;">${record.service_description || '(내용 없음)'}</div>
                </div>
                <div class="dropdown-section">
                    <div style="font-weight: 700; color: #4e5968; font-size: 13px; margin-bottom: 6px;">상담원 소견</div>
                    <div class="dropdown-text" style="background: transparent; padding: 0;">${record.agent_opinion || '(소견 없음)'}</div>
                </div>
            </div>
            <div class="record-card-footer" style="display:flex;gap:8px;margin-top:12px;padding-top:4px;">
                ${record.share_token ? `
                <button class="btn-share-shared-by-me" data-token="${record.share_token}" style="
                    display:inline-flex;align-items:center;gap:6px;width:100%;justify-content:center;
                    padding:10px 14px;background:#1A56DB;color:#fff;border:none;border-radius:10px;
                    font-size:13px;font-weight:700;cursor:pointer;font-family:inherit;
                ">🔗 링크 복사</button>` : ''}
            </div>
            <div class="card-select-number"></div>
        `;

        // 카드 클릭 → 선택 모드일 때만 처리
        card.addEventListener('click', () => {
            if (!isSelectionMode) return;
            if (selectedForDelete.has(record.id)) {
                selectedForDelete.delete(record.id);
            } else {
                selectedForDelete.set(record.id, selectedForDelete.size + 1);
            }
            renderSharedByMe();
        });

        // 선택 모드 상태 반영
        if (isSelectionMode) {
            card.classList.add('selection-mode');
            if (selectedForDelete.has(record.id)) {
                card.classList.add('selected-for-delete');
                const numEl = card.querySelector('.card-select-number');
                if (numEl) {
                    const keys = Array.from(selectedForDelete.keys());
                    numEl.textContent = keys.indexOf(record.id) + 1;
                }
            }
        }

        // 상세 보기 드롭다운 토글
        const sharedToggleBtn = card.querySelector('.record-dropdown-toggle');
        sharedToggleBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            const content = card.querySelector(`#${sharedDropdownId}`);
            const arrow = sharedToggleBtn.querySelector('.dropdown-arrow');
            const label = sharedToggleBtn.querySelector('.dropdown-label');
            content.classList.toggle('hidden');
            const isHidden = content.classList.contains('hidden');
            arrow.classList.toggle('open', !isHidden);
            label.textContent = isHidden ? '상세 보기' : '접기';
        });

        const shareBtn = card.querySelector('.btn-share-shared-by-me');
        if (shareBtn) {
            shareBtn.addEventListener('click', async (e) => {
                e.stopPropagation();
                const btn = e.currentTarget;
                const token = btn.dataset.token;
                const origText = btn.textContent;
                btn.textContent = '링크 생성 중...';
                btn.disabled = true;
                try {
                    const key = await getShareKeyForToken(token);
                    if (key === 'PIN_REQUIRED') {
                        showToastNotification('보안 PIN을 다시 입력해주세요. 확장프로그램을 새로고침 후 PIN을 입력하세요.');
                        return;
                    }
                    if (!key) {
                        showToastNotification('암호화 키를 찾지 못했어요. 모바일 앱에서 해당 DB를 다시 공유해주세요.');
                        return;
                    }
                    // 키를 서버에 업로드한 뒤 URL에서 제거
                    const uploadRes = await fetch(`${API_BASE}/shared-records/${token}/key`, {
                        method: 'POST',
                        headers: { ...authHeaders(), 'Content-Type': 'application/json' },
                        body: JSON.stringify({ share_key: key }),
                    });
                    if (!uploadRes.ok) {
                        showToastNotification('링크 생성에 실패했어요. 다시 시도해주세요.');
                        return;
                    }
                    const url = `https://dash.qpon/?token=${token}`;
                    await navigator.clipboard.writeText(url);
                    showToastNotification('공유 링크가 복사됐어요');
                } catch (_) {
                    showToastNotification('복사에 실패했어요. 다시 시도해주세요.');
                } finally {
                    btn.textContent = origText;
                    btn.disabled = false;
                }
            });
        }

        container.appendChild(card);
    });
}

function updateInjectButton() {
    if (selectedRecordId) {
        btnInject.disabled = false;
        const record = records.find(r => r.id === selectedRecordId);
        btnInject.textContent = 'DB 삽입';
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
    const tabs = await chrome.tabs.query({ url: ["*://ncads.go.kr/*", "*://*.ncads.go.kr/*"] });
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
                body: JSON.stringify({ status: 'Injected', injected_by_name: currentUser?.name || '' })
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
    eventSource.onerror = async (err) => {
        console.error('SSE Error:', err);
        eventSource.close();
        if (!currentOAuthToken) return;

        // 재연결 전 토큰 갱신 시도 — 실패 시 만료 토큰으로 무한 재시도하지 않고 로그아웃
        try {
            const freshToken = await getFreshTokenSilent();
            currentOAuthToken = freshToken;
            chrome.storage.session.set({ cachedOAuthToken: freshToken });
            setTimeout(setupRealtimeSync, 5000);
        } catch (e) {
            console.warn('SSE 재연결 포기: 토큰 갱신 불가', e.message);
            performLogout();
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
                chrome.storage.session.remove(['cachedVaultKeys', 'cachedOAuthToken', 'cachedDerivedKey']);
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
