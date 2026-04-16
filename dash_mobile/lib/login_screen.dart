import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/analytics_service.dart';
import 'package:dash_mobile/user_guide_screen.dart';
import 'package:dash_mobile/privacy_policy_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenLogin();
  }

  // ── 접근 허용 이메일 도메인 목록 ────────────────────────────────
  static const List<String> _allowedDomains = [
    // 'example.or.kr',
  ];
  // ─────────────────────────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: '803548605147-8p75oeqvre7frce70lkl59akqung8kd7.apps.googleusercontent.com',
      );
      // 이전 선택 계정 초기화 → 계정 선택 모달 강제 표시 (태블릿 자동 로그인 방지)
      await googleSignIn.signOut().catchError((_) {});

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);

      AnalyticsService.loginSuccess();
      if (userCredential.user?.uid != null) {
        AnalyticsService.setUser(userCredential.user!.uid);
      }

      if (_allowedDomains.isNotEmpty) {
        final email = userCredential.user?.email ?? '';
        final domain = email.contains('@') ? email.split('@').last : '';
        if (!_allowedDomains.contains(domain)) {
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('승인되지 않은 이메일 계정입니다. 기관 이메일로 로그인해 주세요.'),
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }
    } catch (e) {
      AnalyticsService.loginFailure(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTabletLandscape = size.width > 600 && size.width > size.height;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: isTabletLandscape
            ? _TabletLandscapeLayout(isLoading: _isLoading, onSignIn: _signInWithGoogle)
            : _PortraitLayout(isLoading: _isLoading, onSignIn: _signInWithGoogle),
      ),
    );
  }
}

// ── 세로(기본) 레이아웃 ────────────────────────────────────────────
class _PortraitLayout extends StatelessWidget {
  const _PortraitLayout({required this.isLoading, required this.onSignIn});
  final bool isLoading;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          const Text(
            'DASH',
            style: TextStyle(
              fontSize: 54,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '모바일로 DB 기록하세요',
            style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          _GoogleSignInButton(isLoading: isLoading, onSignIn: onSignIn),
          const SizedBox(height: 20),
          _FooterLinks(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── 태블릿 가로 레이아웃 ───────────────────────────────────────────
class _TabletLandscapeLayout extends StatelessWidget {
  const _TabletLandscapeLayout({required this.isLoading, required this.onSignIn});
  final bool isLoading;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 왼쪽: 브랜딩
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'DASH',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '사무실 밖에서도\nDB를 작성하세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 오른쪽: 로그인 영역 — 세로 가운데 정렬
        SizedBox(
          width: 340,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 상단: 이용안내 | 개인정보처리방침
                  _FooterLinks(color: Colors.white.withValues(alpha: 0.75)),
                  const SizedBox(height: 28),
                  // 하단: 로그인 CTA
                  _GoogleSignInButton(isLoading: isLoading, onSignIn: onSignIn),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 구글 로그인 버튼 ──────────────────────────────────────────────
class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.isLoading, required this.onSignIn});
  final bool isLoading;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: onSignIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icons/google_logo.png', width: 20, height: 20),
            const SizedBox(width: 10),
            const Text(
              '구글 아이디로 계속하기',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F1F1F),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 이용안내 | 개인정보처리방침 링크 ──────────────────────────────
class _FooterLinks extends StatelessWidget {
  const _FooterLinks({this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? Colors.white.withValues(alpha: 0.7);
    final dividerColor = color ?? Colors.white.withValues(alpha: 0.4);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserGuideScreen())),
          child: Text('이용 안내', style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('|', style: TextStyle(fontSize: 12, color: dividerColor)),
        ),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
          child: Text('개인정보처리방침', style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
