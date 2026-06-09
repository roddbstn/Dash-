import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/home_screen.dart';
import 'package:dash_mobile/consent_screen.dart';
import 'package:dash_mobile/onboarding_screen.dart';
import 'package:dash_mobile/firebase_options.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/pin_setup_screen.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/deep_link_service.dart';


@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // notification 키가 있으면 OS가 자동으로 표시하므로 별도 처리 불필요
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android 15 Edge-to-Edge: 시스템 UI를 투명하게 처리하여
  // deprecated setStatusBarColor / setNavigationBarColor 경고 해소
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseAuth.instance.setLanguageCode('ko');

  // 백그라운드 메시지 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // SharedPreferences에 남아있던 PIN/Salt를 Secure Storage로 1회 마이그레이션
  await StorageService.migratePinIfNeeded();
  await StorageService.migrateSaltIfNeeded();

  // Crashlytics: Flutter 프레임워크 내 오류 수집
  if (!kDebugMode) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    // Dart 비동기 오류 (Zone 밖)
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // 딥링크 서비스 초기화 (앱 시작 시 1회)
    DeepLinkService.init(navigatorKey);

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Dash',
      theme: AppTheme.light,
      routes: {
        '/onboarding': (_) => const OnboardingScreen(),
        '/home': (_) => const HomeScreen(),
        '/pin_setup': (_) => const PinSetupScreen(),
      },
      builder: (context, child) => _OrientationHandler(child: child!),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SplashScreen();
          }
          if (snapshot.hasData) {
            return _PostLoginRouter(uid: snapshot.data!.uid);
          }
          return const _PreLoginRouter();
        },
      ),
    );
  }
}

// ── 스플래시 ─────────────────────────────────────────────────────
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();
  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;

          // ① 등장: 0.0 → 0.15 (fade + scale in with easeOutBack)
          final appearProgress = (t / 0.15).clamp(0.0, 1.0);
          final appearScale = 0.65 + 0.35 * Curves.easeOutBack.transform(appearProgress);
          final appearOpacity = Curves.easeOut.transform(appearProgress);

          // ② 이륙: 0.0 → 1.0 (처음부터 바로 출발, ease-in 가속)
          final launchCurved = Curves.easeIn.transform(t);

          // 우측 상단 대각선 이동
          final dx = launchCurved * 260.0;
          final dy = launchCurved * -340.0;

          // 이륙 방향으로 기울기 (~22도 시계방향)
          final rotation = launchCurved * 0.38;

          // 로고 페이드아웃: 0.45 → 0.72
          final logoFadeProgress = ((t - 0.45) / 0.27).clamp(0.0, 1.0);
          final logoFadeOut = t < 0.45 ? 1.0 : (1.0 - Curves.easeIn.transform(logoFadeProgress));

          final logoOpacity = (appearOpacity * logoFadeOut).clamp(0.0, 1.0);
          final logoScale = appearScale * (1.0 - 0.3 * launchCurved);

          // 텍스트는 등장만 (이륙 후에도 유지)
          final textOpacity = appearOpacity.clamp(0.0, 1.0);

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 파란 대상체 — 로켓 이륙
                Opacity(
                  opacity: logoOpacity,
                  child: Transform.translate(
                    offset: Offset(dx, dy),
                    child: Transform.rotate(
                      angle: rotation,
                      child: Transform.scale(
                        scale: logoScale,
                        child: Image.asset(
                          'assets/icons/logo_transparent.png',
                          width: 86,
                          height: 86,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // DASH 텍스트 — 제자리 유지
                Opacity(
                  opacity: textOpacity,
                  child: const Text(
                    'DASH',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── 비로그인 라우터: 최초 방문 → 온보딩 1페이지, 재방문(로그아웃) → 온보딩 4페이지
class _PreLoginRouter extends StatelessWidget {
  const _PreLoginRouter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: SharedPreferences.getInstance()
          .then((p) => p.getBool('onboarding_v1_completed') ?? false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        final onboardingDone = snapshot.data ?? false;
        return OnboardingScreen(initialPage: onboardingDone ? 3 : 0);
      },
    );
  }
}

// ── 로그인 후 동의 완료 여부에 따른 라우터 ──────────────────────────────
// 닉네임·PIN 설정은 신규 회원가입(ConsentScreen 통과) 직후에만 실행됩니다.
// 로그아웃 후 재로그인한 사용자는 동의가 이미 완료되어 있으므로 바로 홈으로 이동합니다.
class _PostLoginRouter extends StatefulWidget {
  final String uid;
  const _PostLoginRouter({required this.uid});

  @override
  State<_PostLoginRouter> createState() => _PostLoginRouterState();
}

class _PostLoginRouterState extends State<_PostLoginRouter> {
  // authStateChanges가 여러 번 emit되어도 _resolveRoute()는 한 번만 실행
  late final Future<String> _routeFuture = _resolveRoute();

  Future<String> _resolveRoute() async {
    debugPrint('🔍 [ROUTE] _resolveRoute START');
    final prefs = await SharedPreferences.getInstance();
    // StreamBuilder의 snapshot.data에서 직접 받아서 사용 → null 타이밍 이슈 방지
    final currentUid = widget.uid;
    debugPrint('🔍 [ROUTE] uid=$currentUid');

    // 다른 계정으로 전환된 경우 이전 유저의 로컬 데이터 초기화 (consent 제외 — 유저별 저장)
    // last_logged_in_uid는 로그아웃 시 유지되므로, null이면 최초 설치/탈퇴 후 재가입
    final lastUid = prefs.getString('last_logged_in_uid');
    final consentUid = prefs.getString('consent_user_uid');
    final isDifferentUser = lastUid == null ||
        lastUid != currentUid ||
        (consentUid != null && consentUid != currentUid);
    if (isDifferentUser) {
      await StorageService.clearSessionData();
      // 다른 계정으로 전환 시 이전 유저의 PIN도 삭제 (같은 유저 재로그인은 PIN 유지)
      if (lastUid != null && lastUid != currentUid) {
        await StorageService.clearPinAndSalt();
      }
      // consent 플래그는 유저별(consent_done_<uid>)로 관리하므로 삭제하지 않음
    }
    await prefs.setString('last_logged_in_uid', currentUid);

    // ① 이 기기에서 온보딩(PIN 설정)까지 완료한 계정 → 서버 호출 없이 바로 홈
    final isReg = await StorageService.isRegistered(currentUid);
    debugPrint('🔍 [ROUTE] isRegistered=$isReg');
    if (isReg) {
      final pinSetupRequired = prefs.getBool('pin_setup_required') ?? false;
      if (pinSetupRequired) return 'pin_setup';
      // 재설치/기기변경으로 SecureStorage가 초기화된 경우 PIN 재설정 필요
      final existingPin = await StorageService.getPin();
      if (existingPin == null || existingPin.isEmpty) {
        debugPrint('🔍 [ROUTE] → pin_setup (PIN missing after reinstall)');
        return 'pin_setup';
      }
      debugPrint('🔍 [ROUTE] → home (isRegistered)');
      return 'home';
    }

    // ② 유저별 consent 확인 (consent_done_<uid> 우선, 레거시 consent_user_uid 폴백)
    final perUserConsent = prefs.getBool('consent_done_$currentUid') ?? false;
    final legacyConsent = (prefs.getBool('consent_v1_completed') ?? false) &&
        currentUid == prefs.getString('consent_user_uid');
    debugPrint('🔍 [ROUTE] perUserConsent=$perUserConsent legacyConsent=$legacyConsent');
    if (!perUserConsent && !legacyConsent) {
      // ③ 로컬 플래그 없음 → 서버에서 기존/신규 사용자 구분
      try {
        final serverUser = await ApiService.fetchUser(currentUid);
        debugPrint('🔍 [ROUTE] fetchUser result: ${serverUser != null ? "found" : "404 not found"}');
        if (serverUser != null) {
          // 서버에 등록된 사용자일지라도, 신규 자동생성 유저인지 구별하기 위해 Vault 존재 여부 체크
          final vault = await ApiService.fetchVault(currentUid);
          if (vault == null) {
            // 네트워크 오류 등으로 판별 불가 시 기존 사용자로 간주 (Fail Open)
            debugPrint('🔍 [ROUTE] vault fetch failed (network error) → home');
            await prefs.setBool('consent_done_$currentUid', true);
            await StorageService.setRegistered(currentUid);
            return 'home';
          } else if (vault.isNotEmpty) {
            // 진짜 기존 가입 완료된 사용자 (Vault 존재)
            await prefs.setBool('consent_done_$currentUid', true);
            await StorageService.setRegistered(currentUid); // 이후 재설치 시에도 서버 호출 불필요
            // 새 기기/재설치: PIN은 기기 Keystore에 저장되므로 재설정 필요
            await prefs.setBool('pin_setup_required', true);
            debugPrint('🔍 [ROUTE] server user and vault found → fall through to PIN check');
          } else {
            // 자동생성만 된 신규/탈퇴 유저 (Vault 없음 - empty map {})
            debugPrint('🔍 [ROUTE] server user found but NO vault → new/deleted user (consent로)');
            return 'consent';
          }
        } else {
          // 404: 서버 DB에 사용자 없음 (신규 사용자 혹은 탈퇴한 계정)
          // 기존 작성한 케이스 데이터가 남아있는 기기교체/재설치 사용자 대응
          try {
            final existingCases = await ApiService.fetchCases(currentUid);
            if (existingCases != null && existingCases.isNotEmpty) {
              debugPrint('🔍 [ROUTE] dash_users 없지만 케이스 있음 → 기존 사용자 복원');
              await prefs.setBool('consent_done_$currentUid', true);
              await StorageService.setRegistered(currentUid);
              await prefs.setBool('pin_setup_required', true);
              // fall through to PIN check
            } else {
              debugPrint('🔍 [ROUTE] 서버 DB 유저 없음 & 케이스 없음 → 신규/탈퇴 유저 (consent로)');
              return 'consent';
            }
          } catch (_) {
            return 'consent';
          }
        }
      } catch (e) {
        // 네트워크/서버 오류 → 기존 사용자로 간주하고 홈으로 (fail open)
        debugPrint('🔍 [ROUTE] fetchUser exception: $e → home');
        return 'home';
      }
    }

    // PIN 초기화 후 재설정이 필요한 경우
    final pinSetupRequired = prefs.getBool('pin_setup_required') ?? false;
    if (pinSetupRequired) {
      debugPrint('🔍 [ROUTE] → pin_setup');
      return 'pin_setup';
    }
    debugPrint('🔍 [ROUTE] → home (final)');
    DeepLinkService.processPendingDeepLink();
    return 'home';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _routeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        switch (snapshot.data) {
          case 'consent':
            return const ConsentScreen();
          case 'pin_setup':
            return const PinSetupScreen();
          default:
            return const HomeScreen();
        }
      },
    );
  }
}

// ── 방향 설정 핸들러 ─────────────────────────────────────────
// builder 콜백에서 매 build마다 setPreferredOrientations를 호출하던 것을
// didChangeDependencies로 분리해, 태블릿 여부가 실제로 바뀔 때만 호출.
class _OrientationHandler extends StatefulWidget {
  final Widget child;
  const _OrientationHandler({required this.child});

  @override
  State<_OrientationHandler> createState() => _OrientationHandlerState();
}

class _OrientationHandlerState extends State<_OrientationHandler> {
  bool? _wasTablet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    if (_wasTablet != isTablet) {
      _wasTablet = isTablet;
      SystemChrome.setPreferredOrientations(
        isTablet
            ? DeviceOrientation.values
            : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
