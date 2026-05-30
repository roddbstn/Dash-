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

// ── 메타 아코디언 ─────────────────────────────────────────────
let _metaOpen = false;
function toggleMeta() {
    _metaOpen = !_metaOpen;
    const grid = document.getElementById('meta-grid');
    const icon = document.getElementById('meta-icon');
    if (grid) grid.style.display = _metaOpen ? 'grid' : 'none';
    if (icon) icon.textContent = _metaOpen ? '▴' : '▾';
}

// ── KST 날짜 파싱 (타임존 미지정 시 UTC+9 가정) ────────────────
function _parseKST(dateString) {
    if (!dateString) return new Date(NaN);
    const s = dateString.replace(' ', 'T');
    // 이미 타임존 정보가 있으면 그대로 파싱
    return new Date(/[Z+]/.test(s) ? s : s + '+09:00');
}

// ── 날짜 포매팅 ───────────────────────────────────────────────
function formatDayOfWeek(dateString) {
    if (!dateString) return '';
    const date = _parseKST(dateString);
    if (isNaN(date)) return dateString;
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    return `${date.getMonth() + 1}.${date.getDate()} (${days[date.getDay()]})`;
}

function formatDateTimeRange(startStr, endStr) {
    if (!startStr || !endStr) return '';
    const s = _parseKST(startStr);
    const e = _parseKST(endStr);
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
    fetch(`${window.location.origin}/api/records/share/${token}`)
        .then(res => {
            if (!res.ok) throw new Error('not_found');
            return res.json();
        })
        .then(data => renderUI(data))
        .catch(() => {
            document.getElementById('state-loading').style.display = 'none';
            document.getElementById('state-error').style.display = 'flex';
        });
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

    // 상태 전환
    const stateLoading = document.getElementById('state-loading');
    const dbContent = document.getElementById('db-content');
    if (stateLoading) stateLoading.style.display = 'none';
    if (dbContent) dbContent.style.display = '';

    // CTA 표시
    const cta = document.getElementById('cta-section');
    const spacer = document.getElementById('cta-spacer');
    if (cta) cta.style.display = '';
    if (spacer) spacer.style.display = '';
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
        el.alt = '';
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

// ── 라이트박스 ────────────────────────────────────────────────
function openLightbox() {
    const lb = document.getElementById('lightbox');
    if (lb) {
        lb.classList.add('open');
        document.body.style.overflow = 'hidden';
    }
}

function closeLightbox() {
    const lb = document.getElementById('lightbox');
    if (lb) {
        lb.classList.remove('open');
        document.body.style.overflow = '';
    }
}

// ESC 키로 닫기
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeLightbox(); });

// ── 앱 열기 (OS별 딥링크 → 스토어 폴백) ─────────────────────
function openApp() {
    const token = new URLSearchParams(window.location.search).get('token') || '';
    const ua = navigator.userAgent;

    // iPad 데스크탑 모드는 UA에 'iPad'가 없으므로 maxTouchPoints로 보완
    const isIOS = /iPhone|iPad|iPod/i.test(ua)
        || (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1);
    const isAndroid = /Android/i.test(ua);
    // intent:// 는 Chrome 계열 Android 브라우저에서만 안정적으로 작동
    const isAndroidChrome = isAndroid && /Chrome\//i.test(ua) && !/Chromium/i.test(ua);

    const playStore = 'https://play.google.com/store/apps/details?id=com.dash.mobile.yunsoo';
    const appStore = 'https://apps.apple.com/app/id0000000000'; // TODO: 실제 App Store ID로 교체

    // token 없으면 딥링크 의미 없음 → 스토어 직행
    if (!token) {
        window.location = isIOS ? appStore : playStore;
        return;
    }

    if (isAndroidChrome) {
        // intent:// — 앱 설치 시 앱으로, 미설치 시 browser_fallback_url(Play Store)로 자동 폴백
        window.location = 'intent://dash.qpon/share/' + token
            + '#Intent;scheme=https;package=com.dash.mobile.yunsoo;S.browser_fallback_url='
            + encodeURIComponent(playStore) + ';end';
    } else if (isAndroid) {
        // Chrome 외 Android 브라우저 (Firefox 등) — intent:// 미지원이므로 Play Store 직행
        window.location = playStore;
    } else if (isIOS) {
        // Universal Link 시도 → 앱이 열리면 페이지가 hidden 상태로 전환됨
        // visibilitychange로 감지해 App Store 리다이렉트 타이머 취소
        const timer = setTimeout(function() { window.location = appStore; }, 1500);
        document.addEventListener('visibilitychange', function onHidden() {
            if (document.hidden) {
                clearTimeout(timer);
                document.removeEventListener('visibilitychange', onHidden);
            }
        });
        window.location = 'https://dash.qpon/share/' + token;
    } else {
        // PC — 모바일에서 열어달라는 안내 toast
        showToast('모바일 기기에서 열어주세요.');
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
