// =============================================================================
// sidepanel.js — DOM 조작 함수 단위 테스트
//
// 테스트 대상:
//   - showLoginView()       로그인 뷰 표시
//   - showPinView()         PIN 뷰 표시
//   - showMainView()        메인 뷰 표시 (프로필 업데이트 포함)
//   - showResultView()      결과 뷰 표시
//   - switchMainTab(tab)    탭 전환 (pending/shared/history)
//   - updatePinDots()       PIN 입력 시각화
//   - showLoginError(msg)   에러 메시지 표시 (동적 생성 포함)
//   - hideLoginError()      에러 메시지 숨기기
//
// jsdom 환경에서 최소 HTML 구조를 직접 구성하여 테스트
// =============================================================================

const fs = require('fs');
const path = require('path');

// ─────────────────────────────────────────────────────────────────────────────
// 최소 HTML 구조 빌더 — 각 describe 블록에서 beforeEach로 초기화
// ─────────────────────────────────────────────────────────────────────────────

function buildDom() {
    document.body.innerHTML = `
        <div id="login-view" class="view">
            <button id="btn-google-login" class="gsi-material-button">
                <span class="gsi-material-button-contents">Google 계정으로 로그인</span>
            </button>
        </div>
        <div id="pin-view" class="view hidden">
            <div id="pin-dots">
                <span class="pin-dot"></span>
                <span class="pin-dot"></span>
                <span class="pin-dot"></span>
                <span class="pin-dot"></span>
            </div>
            <p id="pin-error" class="hidden">PIN이 일치하지 않습니다</p>
            <div id="pin-keypad"></div>
            <button id="btn-forgot-pin">PIN이 기억나지 않으세요?</button>
            <div id="pin-help-modal" class="hidden"></div>
            <button id="btn-close-pin-help">확인</button>
        </div>
        <div id="main-view" class="view hidden">
            <img id="profile-pic" class="hidden" alt="Profile" />
            <span id="profile-name" class="hidden"></span>
            <button id="tab-pending" class="active">나의 DB</button>
            <button id="tab-shared">공유할 DB</button>
            <button id="tab-history">이전 기록</button>
            <div id="selection-bar" class="hidden"></div>
            <div id="tab-content-pending"></div>
            <div id="tab-content-shared" class="hidden"></div>
            <div id="tab-content-history" class="hidden"></div>
            <div id="records-container"></div>
            <button id="btn-refresh"></button>
            <div id="tab-pending-badge" class="hidden"></div>
            <div id="tab-shared-badge" class="hidden"></div>
        </div>
        <div id="result-view" class="view hidden"></div>
        <button id="btn-footer-logout"></button>
    `;
}

// ─────────────────────────────────────────────────────────────────────────────
// 테스트 대상 함수 (sidepanel.js에서 추출 — DOM 의존 버전)
// 전역 상태를 테스트 함수 컨텍스트에서 관리
// ─────────────────────────────────────────────────────────────────────────────

function makeContext() {
    let pinInput = '';
    let pinLocked = false;
    let currentUser = null;
    let currentMainTab = 'pending';
    let pinAuthenticated = false;

    const g = () => ({
        loginView: document.getElementById('login-view'),
        pinView: document.getElementById('pin-view'),
        mainView: document.getElementById('main-view'),
        resultView: document.getElementById('result-view'),
        btnGoogleLogin: document.getElementById('btn-google-login'),
        pinDots: document.getElementById('pin-dots'),
        pinError: document.getElementById('pin-error'),
        profilePicEl: document.getElementById('profile-pic'),
        profileNameEl: document.getElementById('profile-name'),
    });

    return {
        get pinInput() { return pinInput; },
        set pinInput(v) { pinInput = v; },
        get pinLocked() { return pinLocked; },
        set pinLocked(v) { pinLocked = v; },
        get currentUser() { return currentUser; },
        set currentUser(v) { currentUser = v; },
        get pinAuthenticated() { return pinAuthenticated; },
        set pinAuthenticated(v) { pinAuthenticated = v; },

        showLoginView() {
            const { loginView, pinView, mainView, resultView, btnGoogleLogin } = g();
            loginView.classList.remove('hidden');
            pinView.classList.add('hidden');
            mainView.classList.add('hidden');
            resultView.classList.add('hidden');
            btnGoogleLogin.disabled = false;
            const contentsSpan = btnGoogleLogin.querySelector('.gsi-material-button-contents');
            if (contentsSpan) contentsSpan.textContent = 'Google 계정으로 로그인';
            this.hideLoginError();
        },

        showPinView() {
            const { loginView, pinView, mainView, resultView, pinError } = g();
            loginView.classList.add('hidden');
            pinView.classList.remove('hidden');
            mainView.classList.add('hidden');
            resultView.classList.add('hidden');
            pinInput = '';
            pinLocked = false;
            this.updatePinDots();
            pinError.classList.add('hidden');
        },

        showMainView() {
            const { loginView, pinView, mainView, resultView, profilePicEl, profileNameEl } = g();
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
        },

        showResultView() {
            const { loginView, pinView, mainView, resultView } = g();
            loginView.classList.add('hidden');
            pinView.classList.add('hidden');
            mainView.classList.add('hidden');
            resultView.classList.remove('hidden');
        },

        switchMainTab(tab) {
            currentMainTab = tab;
            document.getElementById('tab-pending').classList.toggle('active', tab === 'pending');
            document.getElementById('tab-shared').classList.toggle('active', tab === 'shared');
            document.getElementById('tab-history').classList.toggle('active', tab === 'history');
            document.getElementById('tab-content-pending').classList.toggle('hidden', tab !== 'pending');
            document.getElementById('tab-content-shared').classList.toggle('hidden', tab !== 'shared');
            document.getElementById('tab-content-history').classList.toggle('hidden', tab !== 'history');
            const selBar = document.getElementById('selection-bar');
            if (selBar) {
                if (tab === 'history' || !pinAuthenticated) {
                    selBar.classList.add('hidden');
                } else {
                    selBar.classList.remove('hidden');
                }
            }
        },

        updatePinDots() {
            const { pinDots } = g();
            const dots = pinDots.querySelectorAll('.pin-dot');
            dots.forEach((dot, i) => {
                dot.classList.remove('filled', 'error', 'success');
                if (i < pinInput.length) {
                    dot.classList.add('filled');
                }
            });
        },

        showLoginError(msg) {
            let el = document.getElementById('login-error-msg');
            if (!el) {
                el = document.createElement('p');
                el.id = 'login-error-msg';
                const { btnGoogleLogin } = g();
                btnGoogleLogin.insertAdjacentElement('afterend', el);
            }
            const isCancelled = msg && (msg.includes('cancel') || msg.includes('취소') || msg.includes('closed'));
            el.textContent = isCancelled
                ? '로그인 창이 닫혔습니다. 다시 시도해주세요.'
                : 'Google 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.';
            el.style.display = 'block';
        },

        hideLoginError() {
            const el = document.getElementById('login-error-msg');
            if (el) el.style.display = 'none';
        },
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// showLoginView 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('showLoginView', () => {
    let ctx;

    beforeEach(() => {
        buildDom();
        ctx = makeContext();
    });

    test('login-view visible, 나머지 hidden', () => {
        ctx.showMainView(); // 먼저 다른 뷰로 전환
        ctx.showLoginView();
        expect(document.getElementById('login-view').classList.contains('hidden')).toBe(false);
        expect(document.getElementById('pin-view').classList.contains('hidden')).toBe(true);
        expect(document.getElementById('main-view').classList.contains('hidden')).toBe(true);
        expect(document.getElementById('result-view').classList.contains('hidden')).toBe(true);
    });

    test('Google 로그인 버튼 활성화', () => {
        document.getElementById('btn-google-login').disabled = true;
        ctx.showLoginView();
        expect(document.getElementById('btn-google-login').disabled).toBe(false);
    });

    test('버튼 텍스트 초기값으로 복원', () => {
        const btn = document.getElementById('btn-google-login');
        btn.querySelector('.gsi-material-button-contents').textContent = '로그인 중...';
        ctx.showLoginView();
        expect(btn.querySelector('.gsi-material-button-contents').textContent).toBe('Google 계정으로 로그인');
    });

    test('에러 메시지 숨기기', () => {
        // 에러 메시지 먼저 표시
        ctx.showLoginError('오류 발생');
        ctx.showLoginView();
        const el = document.getElementById('login-error-msg');
        expect(el?.style.display).toBe('none');
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// showPinView 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('showPinView', () => {
    let ctx;

    beforeEach(() => {
        buildDom();
        ctx = makeContext();
    });

    test('pin-view visible, 나머지 hidden', () => {
        ctx.showLoginView();
        ctx.showPinView();
        expect(document.getElementById('pin-view').classList.contains('hidden')).toBe(false);
        expect(document.getElementById('login-view').classList.contains('hidden')).toBe(true);
        expect(document.getElementById('main-view').classList.contains('hidden')).toBe(true);
        expect(document.getElementById('result-view').classList.contains('hidden')).toBe(true);
    });

    test('pinInput 초기화', () => {
        ctx.pinInput = '123';
        ctx.showPinView();
        expect(ctx.pinInput).toBe('');
    });

    test('pinLocked 해제', () => {
        ctx.pinLocked = true;
        ctx.showPinView();
        expect(ctx.pinLocked).toBe(false);
    });

    test('pin-error 숨기기', () => {
        document.getElementById('pin-error').classList.remove('hidden');
        ctx.showPinView();
        expect(document.getElementById('pin-error').classList.contains('hidden')).toBe(true);
    });

    test('핀 도트 초기화 (filled 제거)', () => {
        ctx.pinInput = '12';
        ctx.updatePinDots(); // 먼저 2개 dot에 filled 추가
        ctx.showPinView();   // 내부에서 pinInput='', updatePinDots() 호출
        const dots = document.querySelectorAll('.pin-dot');
        dots.forEach(d => expect(d.classList.contains('filled')).toBe(false));
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// showMainView 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('showMainView', () => {
    let ctx;

    beforeEach(() => {
        buildDom();
        ctx = makeContext();
    });

    test('main-view visible, 나머지 hidden', () => {
        ctx.showPinView();
        ctx.showMainView();
        expect(document.getElementById('main-view').classList.contains('hidden')).toBe(false);
        expect(document.getElementById('login-view').classList.contains('hidden')).toBe(true);
        expect(document.getElementById('pin-view').classList.contains('hidden')).toBe(true);
        expect(document.getElementById('result-view').classList.contains('hidden')).toBe(true);
    });

    test('currentUser 없으면 프로필 hidden 유지', () => {
        ctx.currentUser = null;
        ctx.showMainView();
        expect(document.getElementById('profile-pic').classList.contains('hidden')).toBe(true);
        expect(document.getElementById('profile-name').classList.contains('hidden')).toBe(true);
    });

    test('currentUser.photo → profile-pic src/title 설정 및 visible', () => {
        ctx.currentUser = { photo: 'https://example.com/pic.jpg', email: 'test@test.com', name: '홍길동' };
        ctx.showMainView();
        const pic = document.getElementById('profile-pic');
        expect(pic.src).toBe('https://example.com/pic.jpg');
        expect(pic.title).toBe('test@test.com');
        expect(pic.classList.contains('hidden')).toBe(false);
    });

    test('currentUser.name → profile-name 텍스트 및 visible', () => {
        ctx.currentUser = { name: '홍길동', photo: null, email: 'test@test.com' };
        ctx.showMainView();
        const nameEl = document.getElementById('profile-name');
        expect(nameEl.textContent).toBe('홍길동님');
        expect(nameEl.classList.contains('hidden')).toBe(false);
    });

    test('currentUser에 photo 없으면 profile-pic hidden 유지', () => {
        ctx.currentUser = { name: '이름만', email: 'test@test.com' }; // photo: undefined
        ctx.showMainView();
        expect(document.getElementById('profile-pic').classList.contains('hidden')).toBe(true);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// showResultView 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('showResultView', () => {
    let ctx;

    beforeEach(() => {
        buildDom();
        ctx = makeContext();
    });

    test('result-view visible, 나머지 hidden', () => {
        ctx.showMainView();
        ctx.showResultView();
        expect(document.getElementById('result-view').classList.contains('hidden')).toBe(false);
        expect(document.getElementById('login-view').classList.contains('hidden')).toBe(true);
        expect(document.getElementById('pin-view').classList.contains('hidden')).toBe(true);
        expect(document.getElementById('main-view').classList.contains('hidden')).toBe(true);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// switchMainTab 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('switchMainTab', () => {
    let ctx;

    beforeEach(() => {
        buildDom();
        ctx = makeContext();
    });

    test('pending 탭: tab-pending active, 나머지 inactive', () => {
        ctx.switchMainTab('pending');
        expect(document.getElementById('tab-pending').classList.contains('active')).toBe(true);
        expect(document.getElementById('tab-shared').classList.contains('active')).toBe(false);
        expect(document.getElementById('tab-history').classList.contains('active')).toBe(false);
    });

    test('shared 탭: tab-shared active, 나머지 inactive', () => {
        ctx.switchMainTab('shared');
        expect(document.getElementById('tab-shared').classList.contains('active')).toBe(true);
        expect(document.getElementById('tab-pending').classList.contains('active')).toBe(false);
        expect(document.getElementById('tab-history').classList.contains('active')).toBe(false);
    });

    test('history 탭: tab-history active, 나머지 inactive', () => {
        ctx.switchMainTab('history');
        expect(document.getElementById('tab-history').classList.contains('active')).toBe(true);
        expect(document.getElementById('tab-pending').classList.contains('active')).toBe(false);
        expect(document.getElementById('tab-shared').classList.contains('active')).toBe(false);
    });

    test('pending 탭: tab-content-pending 표시, 나머지 hidden', () => {
        ctx.switchMainTab('pending');
        expect(document.getElementById('tab-content-pending').classList.contains('hidden')).toBe(false);
        expect(document.getElementById('tab-content-shared').classList.contains('hidden')).toBe(true);
        expect(document.getElementById('tab-content-history').classList.contains('hidden')).toBe(true);
    });

    test('shared 탭: tab-content-shared 표시', () => {
        ctx.switchMainTab('shared');
        expect(document.getElementById('tab-content-shared').classList.contains('hidden')).toBe(false);
        expect(document.getElementById('tab-content-pending').classList.contains('hidden')).toBe(true);
    });

    test('history 탭: tab-content-history 표시', () => {
        ctx.switchMainTab('history');
        expect(document.getElementById('tab-content-history').classList.contains('hidden')).toBe(false);
    });

    test('history 탭: selection-bar 항상 hidden (pinAuthenticated=true라도)', () => {
        ctx.pinAuthenticated = true;
        ctx.switchMainTab('history');
        expect(document.getElementById('selection-bar').classList.contains('hidden')).toBe(true);
    });

    test('pending 탭, pinAuthenticated=false: selection-bar hidden', () => {
        ctx.pinAuthenticated = false;
        ctx.switchMainTab('pending');
        expect(document.getElementById('selection-bar').classList.contains('hidden')).toBe(true);
    });

    test('pending 탭, pinAuthenticated=true: selection-bar 표시', () => {
        ctx.pinAuthenticated = true;
        ctx.switchMainTab('pending');
        expect(document.getElementById('selection-bar').classList.contains('hidden')).toBe(false);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// updatePinDots 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('updatePinDots', () => {
    let ctx;

    beforeEach(() => {
        buildDom();
        ctx = makeContext();
    });

    test('pinInput="" → 모든 dot에 filled 없음', () => {
        ctx.pinInput = '';
        ctx.updatePinDots();
        const dots = document.querySelectorAll('.pin-dot');
        dots.forEach(d => expect(d.classList.contains('filled')).toBe(false));
    });

    test('pinInput="1" → 첫 번째 dot만 filled', () => {
        ctx.pinInput = '1';
        ctx.updatePinDots();
        const dots = document.querySelectorAll('.pin-dot');
        expect(dots[0].classList.contains('filled')).toBe(true);
        expect(dots[1].classList.contains('filled')).toBe(false);
        expect(dots[2].classList.contains('filled')).toBe(false);
        expect(dots[3].classList.contains('filled')).toBe(false);
    });

    test('pinInput="1234" → 4개 모두 filled', () => {
        ctx.pinInput = '1234';
        ctx.updatePinDots();
        const dots = document.querySelectorAll('.pin-dot');
        dots.forEach(d => expect(d.classList.contains('filled')).toBe(true));
    });

    test('이전 error/success 클래스 제거', () => {
        const dots = document.querySelectorAll('.pin-dot');
        dots.forEach(d => d.classList.add('error', 'success'));
        ctx.pinInput = '12';
        ctx.updatePinDots();
        dots.forEach(d => {
            expect(d.classList.contains('error')).toBe(false);
            expect(d.classList.contains('success')).toBe(false);
        });
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// showLoginError / hideLoginError 테스트
// ─────────────────────────────────────────────────────────────────────────────

describe('showLoginError / hideLoginError', () => {
    let ctx;

    beforeEach(() => {
        buildDom();
        ctx = makeContext();
    });

    test('최초 호출 시 에러 요소 동적 생성', () => {
        expect(document.getElementById('login-error-msg')).toBeNull();
        ctx.showLoginError('일반 오류');
        expect(document.getElementById('login-error-msg')).not.toBeNull();
    });

    test('cancel 포함 메시지 → 취소 안내 텍스트', () => {
        ctx.showLoginError('popup_closed_by_user cancel');
        const el = document.getElementById('login-error-msg');
        expect(el.textContent).toBe('로그인 창이 닫혔습니다. 다시 시도해주세요.');
    });

    test('취소 포함 메시지 → 취소 안내 텍스트', () => {
        ctx.showLoginError('사용자가 취소했습니다');
        const el = document.getElementById('login-error-msg');
        expect(el.textContent).toBe('로그인 창이 닫혔습니다. 다시 시도해주세요.');
    });

    test('closed 포함 메시지 → 취소 안내 텍스트', () => {
        ctx.showLoginError('window closed');
        const el = document.getElementById('login-error-msg');
        expect(el.textContent).toBe('로그인 창이 닫혔습니다. 다시 시도해주세요.');
    });

    test('일반 오류 → 재시도 안내 텍스트', () => {
        ctx.showLoginError('네트워크 오류');
        const el = document.getElementById('login-error-msg');
        expect(el.textContent).toBe('Google 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.');
    });

    test('두 번 호출 시 요소 중복 생성 없음', () => {
        ctx.showLoginError('오류1');
        ctx.showLoginError('오류2');
        expect(document.querySelectorAll('#login-error-msg').length).toBe(1);
    });

    test('hideLoginError: display none', () => {
        ctx.showLoginError('오류');
        ctx.hideLoginError();
        expect(document.getElementById('login-error-msg').style.display).toBe('none');
    });

    test('hideLoginError: 요소 없어도 안전', () => {
        expect(() => ctx.hideLoginError()).not.toThrow();
    });
});
