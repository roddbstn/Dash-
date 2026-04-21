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
import 'package:dash_mobile/login_screen.dart';
import 'package:dash_mobile/consent_screen.dart';
import 'package:dash_mobile/onboarding_screen.dart';
import 'package:dash_mobile/firebase_options.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/nickname_screen.dart';
import 'package:dash_mobile/pin_setup_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드 수신 시 Firebase 초기화 필수
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) debugPrint("📩 Background message received: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // 백그라운드 메시지 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // SharedPreferences에 남아있던 PIN을 Secure Storage로 1회 마이그레이션
  await StorageService.migratePinIfNeeded();

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
            return const _PostLoginRouter();
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

// ── 비로그인 라우터: 최초 방문 → 온보딩, 재방문 → 로그인 ──────────────
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
        return onboardingDone ? const LoginScreen() : const OnboardingScreen();
      },
    );
  }
}

// ── 로그인 후 동의 완료 여부에 따른 라우터 ──────────────────────────────
class _PostLoginRouter extends StatelessWidget {
  const _PostLoginRouter();

  Future<String> _resolveRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final consentDone = prefs.getBool('consent_v1_completed') ?? false;
    if (!consentDone) return 'consent';
    final nickname = await StorageService.getUserNickname();
    if (nickname == null || nickname.isEmpty) return 'nickname';
    return 'home';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolveRoute(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        switch (snapshot.data) {
          case 'consent':
            return const ConsentScreen();
          case 'nickname':
            return const NicknameScreen();
          case 'pin_setup':
            return const PinSetupScreen();
          default:
            return const HomeScreen();
        }
      },
    );
  }
}
