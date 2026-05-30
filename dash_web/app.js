// ==============================================
// Dash Share Page — 공유 DB 웹 프리뷰
// URL: https://dash.qpon/share/{token}
//      https://dash.qpon/?token={token}   (레거시 폴백)
// ==============================================

const API_BASE = 'https://dash.qpon/api';

// 스토어 URL — 출시 후 실제 URL로 교체
const IOS_STORE_URL    = 'https://apps.apple.com/kr/app/dash/id0000000000';
const ANDROID_STORE_URL = 'https://play.google.com/store/apps/details?id=com.dash.mobile.yunsoo';

// ─── URL에서 token 추출 ────────────────────────────────────────────────────
// 지원 형식:
//   /share/{token}         → path 기반 (신규)
//   /?token={token}        → query 파라미터 (레거시)
function extractToken() {
    const segments = location.pathname.split('/').filter(Boolean);
    if (segments[0] === 'share' && segments[1]) return segments[1];
    return new URLSearchParams(location.search).get('token');
}

// ─── 플랫폼 감지 ──────────────────────────────────────────────────────────
const isIos     = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream;
const isAndroid = /Android/.test(navigator.userAgent);
const isMobile  = isIos || isAndroid;

// ─── 상태 전환 헬퍼 ───────────────────────────────────────────────────────
function showState(id) {
    ['state-loading', 'state-error', 'state-preview'].forEach(s => {
        document.getElementById(s).classList.toggle('hidden', s !== id);
    });
}

// ─── 날짜 포맷 ────────────────────────────────────────────────────────────
function formatDate(dateStr) {
    if (!dateStr) return '';
    try {
        const d = new Date(dateStr);
        const days = ['일','월','화','수','목','금','토'];
        return `${d.getMonth()+1}.${d.getDate()} (${days[d.getDay()]}) `
             + `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;
    } catch { return dateStr; }
}

function formatProvisionDate(startStr, endStr) {
    if (!startStr) return '';
    try {
        const s = new Date(startStr);
        const e = endStr ? new Date(endStr) : null;
        const days = ['일','월','화','수','목','금','토'];
        const sFmt = `${s.getMonth()+1}.${s.getDate()} (${days[s.getDay()]}) `
                   + `${String(s.getHours()).padStart(2,'0')}:${String(s.getMinutes()).padStart(2,'0')}`;
        if (!e) return sFmt;
        const sameDay = s.getFullYear()===e.getFullYear() && s.getMonth()===e.getMonth() && s.getDate()===e.getDate();
        const eFmt = `${String(e.getHours()).padStart(2,'0')}:${String(e.getMinutes()).padStart(2,'0')}`;
        if (sameDay) return `${sFmt} ~ ${eFmt}`;
        return `${sFmt} ~ ${e.getMonth()+1}.${e.getDate()} (${days[e.getDay()]}) ${eFmt}`;
    } catch { return startStr; }
}

function formatCreatedAt(dateStr) {
    if (!dateStr) return '';
    try {
        const d = new Date(dateStr);
        return `${d.getFullYear()}. ${d.getMonth()+1}. ${d.getDate()} 작성`;
    } catch { return ''; }
}

// ─── 메타 행 렌더링 ───────────────────────────────────────────────────────
function renderMeta(data) {
    const rows = [
        ['제공구분',  data.provision_type],
        ['제공방법',  data.method],
        ['서비스유형', data.service_type],
        ['제공서비스', data.service_category && data.service_name
            ? `${data.service_category} :: ${data.service_name}`
            : data.service_name],
        ['대상자',    data.target],
        ['제공장소',  data.location],
        ['제공일시',  formatProvisionDate(data.start_time, data.end_time)],
        ['제공횟수',  data.service_count && data.service_count !== '0' ? `${data.service_count}회` : null],
        ['이동시간',  data.travel_time && data.travel_time !== '0' ? `${data.travel_time}분` : null],
    ];

    const grid = document.getElementById('meta-grid');
    grid.innerHTML = rows
        .filter(([, v]) => v)
        .map(([label, value]) => `
            <div class="meta-row">
                <span class="meta-label">${label}</span>
                <span class="meta-value">${value}</span>
            </div>`)
        .join('');
}

// ─── 메인: 데이터 fetch & 렌더링 ─────────────────────────────────────────
async function init() {
    const token = extractToken();

    if (!token) {
        showState('state-error');
        return;
    }

    try {
        const res = await fetch(`${API_BASE}/shared-records/${token}`);

        if (!res.ok) {
            showState('state-error');
            return;
        }

        const data = await res.json();

        // 사례명
        const caseNameEl = document.getElementById('case-name');
        caseNameEl.textContent = data.case_name || '—';

        // 동 태그
        if (data.dong) {
            const dongTag = document.getElementById('dong-tag');
            dongTag.textContent = data.dong;
            dongTag.classList.remove('hidden');
        }

        // 작성자, 날짜
        if (data.author_name) {
            document.getElementById('author-name').textContent = data.author_name;
        }
        document.getElementById('created-at').textContent = formatCreatedAt(data.created_at);

        // 메타 그리드
        renderMeta(data);

        showState('state-preview');

    } catch {
        // 네트워크 오류 또는 서버 미지원 — 미리보기 없이 기본 상태로 표시
        showState('state-preview');
    }

    // CTA 및 데스크탑 안내 표시
    if (isMobile) {
        document.getElementById('cta-bar').classList.remove('hidden');
    } else {
        document.getElementById('desktop-notice').classList.remove('hidden');
    }
}

// ─── 앱 열기 로직 ────────────────────────────────────────────────────────
function openApp() {
    const token = extractToken();
    if (!token) return;

    const btn = document.getElementById('btn-open-app');
    btn.disabled = true;
    document.getElementById('btn-text').textContent = '앱 연결 중...';

    const universalLink = `https://dash.qpon/share/${token}`;

    if (isIos) {
        // Universal Link → 앱 설치돼있으면 iOS가 앱으로 라우팅
        // visibilitychange 로 앱 전환 감지 → 미전환 시 스토어 이동
        const fallbackTimer = setTimeout(() => {
            if (!document.hidden) {
                window.location.href = IOS_STORE_URL;
            }
        }, 2500);

        document.addEventListener('visibilitychange', () => {
            if (document.hidden) clearTimeout(fallbackTimer);
        }, { once: true });

        window.location.href = universalLink;

    } else if (isAndroid) {
        // Android Intent URL → 앱 미설치 시 자동으로 Play Store fallback
        const intentUrl = `intent://dash.qpon/share/${token}`
            + `#Intent;scheme=https;`
            + `package=com.dash.mobile.yunsoo;`
            + `S.browser_fallback_url=${encodeURIComponent(ANDROID_STORE_URL)};end`;

        window.location.href = intentUrl;

        // Intent가 처리되지 않는 브라우저(삼성 인터넷 일부) 보험
        setTimeout(() => {
            if (!document.hidden) {
                window.location.href = ANDROID_STORE_URL;
            }
        }, 2500);
    }

    // 버튼 상태 복원 (앱 안 열린 경우 대비)
    setTimeout(() => {
        btn.disabled = false;
        document.getElementById('btn-text').textContent = '앱에서 열기';
    }, 3000);
}

// ─── 진입 ────────────────────────────────────────────────────────────────
init();
