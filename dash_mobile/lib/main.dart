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


@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // notification 키가 있으면 OS가 자동으로 표시하므로 별도 처리 불필요
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dash',
      theme: AppTheme.light,
      routes: {
        '/onboarding': (_) => const OnboardingScreen(),
        '/home': (_) => const HomeScreen(),
        '/pin_setup': (_) => const PinSetupScreen(),
      },
      builder: (context, child) {
        // 태블릿(shortestSide >= 600)은 모든 방향, 폰은 세로 고정
        final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
        SystemChrome.setPreferredOrientations(
          isTablet
              ? DeviceOrientation.values
              : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
        );
        return child!;
      },
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
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: const Center(
        child: Text(
          'DASH',
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.8,
          ),
        ),
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
    final lastUid = prefs.getString('last_logged_in_uid');
    final consentUid = prefs.getString('consent_user_uid');
    final isDifferentUser =
        (lastUid != null && lastUid != currentUid) ||
        (lastUid == null && consentUid != null && consentUid != currentUid);
    if (isDifferentUser) {
      await StorageService.clearSessionData();
      // consent 플래그는 유저별(consent_done_<uid>)로 관리하므로 삭제하지 않음
    }
    await prefs.setString('last_logged_in_uid', currentUid);

    // ① 이 기기에서 온보딩(PIN 설정)까지 완료한 계정 → 서버 호출 없이 바로 홈
    final isReg = await StorageService.isRegistered(currentUid);
    debugPrint('🔍 [ROUTE] isRegistered=$isReg');
    if (isReg) {
      final pinSetupRequired = prefs.getBool('pin_setup_required') ?? false;
      if (pinSetupRequired) return 'pin_setup';
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
          // 서버에 등록된 사용자 → 로컬 플래그 복원 (이전 버전 사용자 포함)
          await prefs.setBool('consent_done_$currentUid', true);
          await StorageService.setRegistered(currentUid); // 이후 재설치 시에도 서버 호출 불필요
          // 새 기기/재설치: PIN은 기기 Keystore에 저장되므로 재설정 필요
          await prefs.setBool('pin_setup_required', true);
          debugPrint('🔍 [ROUTE] server user found → fall through to PIN check');
          // fall through to PIN check below
        } else {
          // 404: 서버 DB에 사용자 없음
          // Firebase Auth 계정 생성 시각이 24시간 이내면 진짜 신규 사용자
          // 그 이상이면 기존 계정 재설치/신규기기 → 홈으로 (DB 누락 방어)
          final createdAt = FirebaseAuth.instance.currentUser?.metadata.creationTime;
          debugPrint('🔍 [ROUTE] uid=$currentUid createdAt=$createdAt now=${DateTime.now()}');
          // creationTime이 null이면 판별 불가 → 기존 유저로 간주 (fail-open to home)
          final isNewSignup = createdAt != null &&
              DateTime.now().difference(createdAt) < const Duration(hours: 24);
          debugPrint('🔍 [ROUTE] isNewSignup=$isNewSignup → ${isNewSignup ? "consent" : "home"}');
          if (isNewSignup) {
            return 'consent';
          } else {
            await prefs.setBool('consent_done_$currentUid', true);
            await StorageService.setRegistered(currentUid);
            return 'home';
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
