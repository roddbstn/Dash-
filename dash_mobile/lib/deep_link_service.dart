import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:dash_mobile/screens/shared_db_preview_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 딥링크(App Links / Universal Links) 수신 및 라우팅 서비스
///
/// 메신저에서 https://dash.qpon/share/{token} 링크를 클릭하면:
///   - 앱 설치됨 → 이 서비스가 수신하여 SharedDbPreviewScreen으로 라우팅
///   - 앱 미설치 → 웹 프리뷰 페이지가 표시됨 (서버 /share/:token 라우트)
class DeepLinkService {
  DeepLinkService._();

  static final AppLinks _appLinks = AppLinks();
  static GlobalKey<NavigatorState>? _navigatorKey;
  static bool _initialized = false;

  /// 앱 시작 시 호출 — cold start + warm start 딥링크 모두 처리
  /// MyApp.build()에서 호출되더라도 실제 초기화(리스너 등록)는 1회만 실행됩니다.
  static void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    if (_initialized) return;
    _initialized = true;

    // Cold start: 앱이 종료된 상태에서 링크로 실행된 경우
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });

    // Warm start: 앱이 이미 실행 중인 상태에서 링크를 클릭한 경우
    _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  /// 딥링크 URI 파싱 및 화면 라우팅
  static void _handleDeepLink(Uri uri) {
    debugPrint('🔗 [DeepLink] Received: $uri');

    final token = _extractShareToken(uri);
    if (token == null) {
      debugPrint('🔗 [DeepLink] No share token found in URI');
      return;
    }

    // 구버전 URL 호환: fragment에 #key= 가 있으면 fallback으로 전달
    String? fragmentKey;
    final fragment = uri.fragment;
    if (fragment.startsWith('key=')) {
      fragmentKey = fragment.substring(4);
      debugPrint('🔗 [DeepLink] Fragment key found (legacy URL)');
    }

    debugPrint('🔗 [DeepLink] Token: $token');

    // 로그인 상태 확인 후 라우팅
    _navigateToPreview(token, fallbackKey: fragmentKey);
  }

  /// /share/{token} 패턴에서 토큰 추출
  ///
  /// 지원 형식:
  ///   - https://dash.qpon/share/{token}  (path 기반)
  ///   - https://dash.qpon/?token={token} (query 파라미터 폴백)
  @visibleForTesting
  static String? extractShareToken(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[0] == 'share') {
      return segments[1];
    }
    return uri.queryParameters['token'];
  }

  // 내부 호출용 — 테스트에서는 extractShareToken(public) 사용
  static String? _extractShareToken(Uri uri) => extractShareToken(uri);

  /// 프리뷰 화면으로 네비게이션
  static void _navigateToPreview(String token, {String? fallbackKey}) {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      debugPrint('🔗 [DeepLink] Navigator not available yet, retrying...');
      Future.delayed(const Duration(milliseconds: 500), () {
        _navigateToPreview(token, fallbackKey: fallbackKey);
      });
      return;
    }

    // 로그인 체크: 미로그인이면 로그인 후 자동 이동할 수 있도록 pending 처리
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('🔗 [DeepLink] User not logged in, saving pending deep link');
      _pendingToken = token;
      _pendingFallbackKey = fallbackKey;
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => SharedDbPreviewScreen(
          token: token,
          fallbackKey: fallbackKey,
          onSaved: onDbSaved,
        ),
      ),
    );
  }

  // 로그인 완료 후 대기 중인 딥링크 처리용
  static String? _pendingToken;
  static String? _pendingFallbackKey;

  // 저장 완료 후 홈화면 갱신용 콜백 (HomeScreen에서 등록)
  static VoidCallback? onDbSaved;

  static void registerOnSaved(VoidCallback cb) {
    onDbSaved = cb;
  }

  /// 로그인 완료 후 호출 — 대기 중인 딥링크가 있으면 처리
  static void processPendingDeepLink() {
    if (_pendingToken != null) {
      final token = _pendingToken!;
      final key = _pendingFallbackKey;
      _pendingToken = null;
      _pendingFallbackKey = null;
      _navigateToPreview(token, fallbackKey: key);
    }
  }
}
