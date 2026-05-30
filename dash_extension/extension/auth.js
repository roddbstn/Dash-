// ==============================================
// auth.js — Google OAuth & Firebase Auth
// Google 액세스 토큰 → Firebase ID Token 교환 로직
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

    // 3. Firebase ID Token(JWT)에서 실제 Firebase UID 추출
    // userInfo.id는 Google 계정 숫자 ID이며, Firebase UID와 다름
    // Firebase UID는 JWT payload의 sub(=user_id) 클레임에 포함됨
    const firebaseUid = parseJwtPayload(idToken).sub;

    currentUser = {
        uid: firebaseUid,
        email: userInfo.email,
        name: userInfo.name || userInfo.email, // 임시: Google 이름 (아래에서 Dash 닉네임으로 교체됨)
        photo: userInfo.picture
    };

    // 4. 서버 dash_users에서 Dash 닉네임 가져오기 (Google 계정 이름 대신)
    try {
        const idTokenForProfile = currentOAuthToken;
        const profileRes = await fetch(`${API_BASE}/users/${firebaseUid}`, {
            headers: { 'Authorization': `Bearer ${idTokenForProfile}` }
        });
        if (profileRes.ok) {
            const profile = await profileRes.json();
            if (profile.name) currentUser.name = profile.name;
        }
    } catch (e) {
        // 닉네임 조회 실패 시 Google 이름 유지
    }

    chrome.storage.local.set({ dashUser: currentUser });
    chrome.storage.session.set({ cachedOAuthToken: idToken });

    // 확장프로그램 최초 로그인 기록 (모바일 프로필 배너 해제용)
    try {
        await fetch(`${API_BASE}/users/extension-login`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${idToken}` },
        });
    } catch (e) {
        // 실패해도 로그인 흐름에 영향 없음
    }

    await checkPinAndProceed();
}

// Firebase ID Token(JWT) payload 디코딩 유틸
// JWT는 header.payload.signature 형식이며, payload는 base64url 인코딩
function parseJwtPayload(token) {
    try {
        if (!token || typeof token !== 'string') throw new Error('토큰이 없습니다.');
        const parts = token.split('.');
        if (parts.length !== 3) throw new Error('유효하지 않은 JWT 형식입니다.');
        const base64Url = parts[1];
        const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
        const jsonPayload = decodeURIComponent(
            atob(base64).split('').map(c =>
                '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2)
            ).join('')
        );
        return JSON.parse(jsonPayload);
    } catch (e) {
        console.error('[parseJwtPayload] JWT 파싱 실패:', e.message);
        throw new Error('인증 토큰 처리 중 오류가 발생했습니다. 다시 로그인해주세요.');
    }
}
