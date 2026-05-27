// ── 인앱 브라우저 감지 ────────────────────────────────────────
function isInAppBrowser() {
    const ua = navigator.userAgent || '';
    if (/KAKAOTALK|NAVER|Line\/|FB_IAB|FBAN|Instagram|DaumApps/i.test(ua)) return true;
    const isMobile = /iPhone|iPad|Android/i.test(ua);
    const isSafari = /Safari\//i.test(ua) && !/Chrome\//i.test(ua);
    const isChrome = /Chrome\//i.test(ua) && !/Chromium/i.test(ua);
    if (isMobile && !isSafari && !isChrome) return true;
    return false;
}

function copyAndClose() {
    navigator.clipboard.writeText(window.location.href).then(() => {
        const btn = document.querySelector('#inapp-modal .btn-modal');
        if (btn) { btn.textContent = '복사됨 ✓'; setTimeout(() => { btn.textContent = '주소 복사하기'; }, 2000); }
    }).catch(() => {
        prompt('아래 주소를 복사해서 Chrome/Safari에 붙여넣기 해주세요:', window.location.href);
    });
}

// ── 암호화 키 추출 (URL fragment에서만 읽음 — 서버 로그에 기록 안 됨) ──
function _getEncKey(token) {
    const hashParams = new URLSearchParams(window.location.hash.substring(1));
    let key = hashParams.get('key') || '';
    if (!key) key = sessionStorage.getItem('dash_key_' + token) || '';
    return key;
}

// ── 메타 아코디언 ─────────────────────────────────────────────
let _metaOpen = false;
function toggleMeta() {
    _metaOpen = !_metaOpen;
    const grid = document.getElementById('meta-grid');
    const icon = document.getElementById('meta-icon');
    if (grid) grid.style.display = _metaOpen ? 'grid' : 'none';
    if (icon) icon.textContent = _metaOpen ? '▴' : '▾';
}

// ── 날짜 포매팅 ───────────────────────────────────────────────
function formatDayOfWeek(dateString) {
    if (!dateString) return '';
    const date = new Date(dateString.replace(' ', 'T'));
    if (isNaN(date)) return dateString;
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    return `${date.getMonth() + 1}.${date.getDate()} (${days[date.getDay()]})`;
}

function formatDateTimeRange(startStr, endStr) {
    if (!startStr || !endStr) return '';
    const s = new Date(startStr.replace(' ', 'T'));
    const e = new Date(endStr.replace(' ', 'T'));
    if (isNaN(s) || isNaN(e)) return `${startStr} ~ ${endStr}`;
    const pad = n => String(n).padStart(2, '0');
    const sDay = formatDayOfWeek(startStr);
    const sTime = `${pad(s.getHours())}:${pad(s.getMinutes())}`;
    const eTime = `${pad(e.getHours())}:${pad(e.getMinutes())}`;
    const sameDay = s.toDateString() === e.toDateString();
    return sameDay
        ? `${sDay} ${sTime} ~ ${eTime}`
        : `${sDay} ${sTime} ~ ${formatDayOfWeek(endStr)} ${eTime}`;
}

// ── HTML 이스케이프 ───────────────────────────────────────────
function _esc(str) {
    return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ── 토스트 ────────────────────────────────────────────────────
function showToast(msg, duration = 3000) {
    let toast = document.getElementById('dash-toast');
    if (!toast) {
        toast = document.createElement('div');
        toast.id = 'dash-toast';
        document.body.appendChild(toast);
    }
    toast.textContent = '✓ ' + msg;
    toast.style.opacity = '1';
    clearTimeout(toast._t);
    toast._t = setTimeout(() => { toast.style.opacity = '0'; }, duration);
}

// ── DB 로드 ───────────────────────────────────────────────────
function loadRecord(token) {
    const encKey = _getEncKey(token);

    fetch(`${window.location.origin}/api/records/share/${token}`)
        .then(res => {
            if (!res.ok) throw new Error('not_found');
            return res.json();
        })
        .then(data => {
            // E2EE 복호화
            if (data.encrypted_blob && encKey) {
                try {
                    const parts = data.encrypted_blob.split(':');
                    const iv = CryptoJS.enc.Base64.parse(parts[0]);
                    const key = CryptoJS.enc.Utf8.parse(encKey.padEnd(32).substring(0, 32));
                    const decrypted = CryptoJS.AES.decrypt(
                        { ciphertext: CryptoJS.enc.Base64.parse(parts[1]) }, key, { iv }
                    );
                    const text = decrypted.toString(CryptoJS.enc.Utf8);
                    if (!text) throw new Error('empty');
                    const dec = JSON.parse(text);
                    data = {
                        ...data, ...dec,
                        case_name: dec.caseName || data.case_name,
                        service_description: dec.serviceDescription || dec.service_description || data.service_description,
                        agent_opinion: dec.agentOpinion || dec.agent_opinion || data.agent_opinion,
                        target: dec.target || data.target,
                        method: dec.method || data.method,
                        provision_type: dec.provision_type || data.provision_type,
                        service_type: dec.service_type || data.service_type,
                        service_category: dec.service_category || data.service_category,
                        service_name: dec.service_name || data.service_name,
                        location: dec.location || data.location,
                        start_time: dec.startTime || dec.start_time || data.start_time,
                        end_time: dec.endTime || dec.end_time || data.end_time,
                        service_count: dec.serviceCount || dec.service_count || data.service_count,
                        travel_time: dec.travelTime || dec.travel_time || data.travel_time,
                    };
                } catch (e) {
                    console.error('Decryption failed:', e);
                    showEncNotice('decrypt_failed');
                }
            } else if (data.encrypted_blob && !encKey) {
                showEncNotice('no_key');
            }
            renderUI(data);
        })
        .catch(() => {
            document.getElementById('state-loading').style.display = 'none';
            document.getElementById('state-error').style.display = 'flex';
        });
}

function showEncNotice(reason) {
    const area = document.getElementById('enc-notice-area');
    if (!area) return;
    const msg = reason === 'no_key'
        ? '🔒 이 링크에 암호화 키가 포함되어 있지 않아 내용을 표시할 수 없습니다. 원래 공유 링크를 다시 받아 열어주세요.'
        : '🔒 복호화에 실패했습니다. 담당 상담원에게 공유 링크를 다시 요청해 주세요.';
    area.innerHTML = `<div class="enc-notice">${msg}</div>`;
}

// ── UI 렌더링 ─────────────────────────────────────────────────
function renderUI(data) {
    // 제목 / 작성자
    document.getElementById('page-title').textContent = `${data.case_name || '미지정'} 아동 사례`;
    document.getElementById('author-name').textContent = `${data.user_name || '상담원'} 작성`;

    // 메타 정보
    const metaList = [
        { label: '대상자', value: data.target ? (Array.isArray(data.target) ? data.target.join(' · ') : data.target.replace(/,/g, ' · ')) : '-' },
        { label: '제공구분', value: data.provision_type || '-' },
        { label: '제공방법', value: data.method || '-' },
        { label: '서비스유형', value: data.service_type || '-' },
        { label: '제공서비스', value: (data.service_category && data.service_name) ? `${data.service_category} :: ${data.service_name}` : (data.service_name || '-') },
        { label: '제공장소', value: data.location || '-' },
        { label: '제공일시', value: formatDateTimeRange(data.start_time, data.end_time), date: true },
        { label: '이동시간', value: data.travel_time ? `${data.travel_time}분` : '-' },
        { label: '제공횟수', value: data.service_count ? `${data.service_count}회` : '-' },
    ];

    document.getElementById('meta-grid').innerHTML = metaList.map(m =>
        `<div class="meta-item${m.date ? ' full-width' : ''}">
            <label>${m.label}</label>
            <span class="${m.date ? 'meta-date-val' : ''}">${_esc(m.value)}</span>
        </div>`
    ).join('');

    // 서비스 내용
    const mainContent = document.getElementById('main-content');
    if (mainContent) mainContent.textContent = data.service_description || '';

    // 상담원 소견
    const opinionContent = document.getElementById('opinion-content');
    const opinionBlock = document.getElementById('opinion-block');
    if (data.agent_opinion && data.agent_opinion.trim()) {
        if (opinionContent) opinionContent.textContent = data.agent_opinion;
        if (opinionBlock) opinionBlock.style.display = '';
    }

    // 상태 전환
    document.getElementById('state-loading').style.display = 'none';
    document.getElementById('db-content').style.display = '';

    // CTA 표시
    const cta = document.getElementById('cta-section');
    const ctaExt = document.getElementById('cta-ext-section');
    if (cta) cta.style.display = '';
    if (ctaExt) ctaExt.style.display = '';
}

// ── 로켓 배경 애니메이션 ──────────────────────────────────────
function initRockets() {
    const bg = document.createElement('div');
    bg.id = 'rocket-bg';
    document.body.insertBefore(bg, document.body.firstChild);

    const COUNT = 34;
    for (let i = 0; i < COUNT; i++) {
        const el = document.createElement('img');
        el.src = '/public/logo_nobg.png';
        el.className = 'rocket-particle';

        const size     = 20 + Math.random() * 32;          // 20~52px
        const duration = 8 + Math.random() * 8;            // 8~16s (더 빠르게)
        const delay    = -(Math.random() * duration);       // 이미 진행 중인 것처럼
        const dist     = 400 + Math.random() * 250;        // 이동 거리
        const opacity  = 0.10 + Math.random() * 0.12;      // 0.10~0.22

        el.style.cssText = [
            `width:${size}px`,
            `height:${size}px`,
            `left:${Math.random() * 110 - 10}%`,
            `top:${Math.random() * 110}%`,
            `--dx:${dist}px`,
            `--dy:-${dist}px`,
            `--max-opacity:${opacity}`,
            `animation-duration:${duration}s`,
            `animation-delay:${delay}s`,
        ].join(';');

        bg.appendChild(el);
    }
}

// ── 초기화 ────────────────────────────────────────────────────
window.onload = () => {
    initRockets();

    // 인앱 브라우저 감지
    if (isInAppBrowser()) {
        document.getElementById('inapp-modal').style.display = 'flex';
        return;
    }

    const token = new URLSearchParams(window.location.search).get('token');
    if (!token) {
        document.getElementById('state-loading').style.display = 'none';
        document.getElementById('state-error').style.display = 'flex';
        return;
    }

    loadRecord(token);
};
