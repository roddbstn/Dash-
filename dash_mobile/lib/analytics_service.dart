import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// 유저 행동 분석 로그 서비스
/// Firebase Analytics를 통해 주요 이벤트를 수집합니다.
class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  static Future<void> _log(String name,
      [Map<String, Object>? params]) async {
    try {
      await _analytics.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('📊 Analytics log failed ($name): $e');
    }
  }

  // ── 화면 뷰 (Firebase "페이지 및 화면" 보고서에 반영됨) ──────────────
  static Future<void> _screen(String name, String className) async {
    try {
      await _analytics.logScreenView(
        screenName: name,
        screenClass: className,
      );
    } catch (e) {
      debugPrint('📊 Analytics screenView failed ($name): $e');
    }
  }

  // ── 사용자 식별 ────────────────────────────────────────────────────
  /// 로그인 성공 시 호출 — GA4 및 Crashlytics에 userId를 연결합니다.
  static Future<void> setUser(String userId) async {
    try {
      await _analytics.setUserId(id: userId);
      if (!kDebugMode) {
        await FirebaseCrashlytics.instance.setUserIdentifier(userId);
      }
    } catch (e) {
      debugPrint('📊 setUser failed: $e');
    }
  }

  static Future<void> screenLogin() => _screen('login', 'LoginScreen');

  static Future<void> screenOnboarding(int page) =>
      _screen('onboarding_$page', 'OnboardingScreen');

  static Future<void> screenHome() => _screen('home', 'HomeScreen');

  static Future<void> screenConsent() => _screen('consent', 'ConsentScreen');

  static Future<void> screenCreateCase() =>
      _screen('create_case', 'CreateCaseScreen');

  static Future<void> screenForm() => _screen('form', 'FormScreen');

  static Future<void> screenUserGuide() =>
      _screen('user_guide', 'UserGuideScreen');

  static Future<void> screenSecurityDetail() =>
      _screen('security_detail', 'SecurityDetailScreen');

  static Future<void> screenPrivacyPolicy() =>
      _screen('privacy_policy', 'PrivacyPolicyScreen');

  // ── 인증 ──────────────────────────────────────────────────────────
  static Future<void> loginSuccess() => _log('login_success');

  static Future<void> loginFailure(String reason) =>
      _log('login_failure', {'reason': reason});

  // ── 온보딩 ────────────────────────────────────────────────────────
  static Future<void> onboardingComplete() => _log('onboarding_complete');

  static Future<void> onboardingSkip(int fromPage) =>
      _log('onboarding_skip', {'from_page': fromPage});

  /// 로그인 버튼 탭 — 어느 온보딩 페이지에서 눌렀는지 기록
  static Future<void> onboardingLoginTapped(int fromPage) =>
      _log('onboarding_login_tapped', {'from_page': fromPage});

  // ── 동의 ──────────────────────────────────────────────────────────
  static Future<void> consentComplete({required bool marketingAgreed}) =>
      _log('consent_complete', {'marketing_agreed': marketingAgreed ? 1 : 0});

  /// 전체 동의 버튼 토글
  static Future<void> consentAllToggled(bool checked) =>
      _log('consent_all_toggled', {'checked': checked ? 1 : 0});

  /// 개별 체크박스 토글 — item: 'privacy' | 'terms' | 'marketing' | 'sensitive'
  static Future<void> consentCheckboxToggled(String item, bool checked) =>
      _log('consent_checkbox_toggled', {'item': item, 'checked': checked ? 1 : 0});

  /// 드롭다운 펼침/접기 — item: 'privacy' | 'terms' | 'marketing' | 'sensitive'
  static Future<void> consentDropdownToggled(String item, bool expanded) =>
      _log('consent_dropdown_toggled', {'item': item, 'expanded': expanded ? 1 : 0});

  /// 전문 보기 클릭 — docType: 'privacy_policy' | 'terms' | 'security_detail'
  static Future<void> consentFullDocViewed(String docType) =>
      _log('consent_full_doc_viewed', {'doc_type': docType});

  // ── 사례 ──────────────────────────────────────────────────────────
  static Future<void> caseCreated() => _log('case_created');

  // ── DB 기록 ───────────────────────────────────────────────────────
  static Future<void> recordSaved({
    required String provisionType,
    required String target,
    required bool hasServiceDescription,
    required bool hasAgentOpinion,
  }) =>
      _log('dbrecord_saved', {
        'provision_type': provisionType,
        'target': target,
        'has_service_description': hasServiceDescription ? 1 : 0,
        'has_agent_opinion': hasAgentOpinion ? 1 : 0,
      });

  static Future<void> recordSyncSuccess() => _log('dbrecord_sync_success');

  static Future<void> recordSyncFailure(String reason) =>
      _log('dbrecord_sync_failure', {'reason': reason});

  static Future<void> linkShared() => _log('link_shared');

  static Future<void> linkCopied() => _log('link_copied');

  // ── PIN ──────────────────────────────────────────────────────────
  static Future<void> pinSet() => _log('pin_set');

  static Future<void> pinEntered() => _log('pin_entered');

  // ── 기타 ─────────────────────────────────────────────────────────
  static Future<void> offlineBannerShown() => _log('offline_banner_shown');

  static Future<void> appForegrounded() => _log('app_foregrounded');

  static Future<void> notificationReceived(String type) =>
      _log('notification_received', {'type': type});

  // ── 동행 파트너(상담원) ──────────────────────────────────────────────
  static Future<void> counselorAdded() => _log('counselor_added');

  static Future<void> counselorDeleted() => _log('counselor_deleted');

  // ── 탭 네비게이션 ────────────────────────────────────────────────────
  static Future<void> tabSwitched(String tabName) =>
      _log('tab_switched', {'tab': tabName});

  static Future<void> dbTabSwitched(String tabName) =>
      _log('db_tab_switched', {'tab': tabName}); // 나의DB / 공유받은DB

  // ── PIN 재설정 ────────────────────────────────────────────────────
  static Future<void> pinReset() => _log('pin_reset');

  // ── 사례 선택 모달 ────────────────────────────────────────────────
  static Future<void> caseSelectionModalOpened() =>
      _log('case_selection_modal_opened');

  // ── 공유 링크 ────────────────────────────────────────────────────
  static Future<void> shareUrlOpened() => _log('share_url_opened');

  // ── 웹 리뷰어 ─────────────────────────────────────────────────────
  /// 공유 링크 페이지 방문 (웹에서 토큰 로드 성공 시 서버가 기록)
  static Future<void> reviewerPageVisited() => _log('reviewer_page_visited');

  static Future<void> reviewerLoginSuccess() => _log('reviewer_login_success');

  static Future<void> reviewSubmitted() => _log('review_submitted');

  // ── Vault 재시도 (Priority 3 관측성) ────────────────────────────────
  static Future<void> vaultKeyRetried({
    required int successCount,
    required int failureCount,
  }) =>
      _log('vault_key_retried', {
        'success_count': successCount,
        'failure_count': failureCount,
      });

  // ── 오프라인 큐 재시도 (Priority 4 펀넬) ────────────────────────────
  static Future<void> pendingSyncRetried({
    required int successCount,
    required int failureCount,
  }) =>
      _log('pending_sync_retried', {
        'success_count': successCount,
        'failure_count': failureCount,
      });
}
