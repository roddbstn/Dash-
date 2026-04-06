import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dash_mobile/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  // ── 접근 허용 이메일 도메인 목록 ────────────────────────────────
  // 비어있으면 모든 구글 계정 허용 (테스트/개발 시),
  // 운영 시에는 기관 도메인을 추가하세요. 예: 'ncrc.or.kr'
  static const List<String> _allowedDomains = [
    // 'example.or.kr',
  ];
  // ─────────────────────────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      // Chrome Custom Tab 방식(signInWithProvider)은 브라우저 세션 저장소 접근 권한 문제
      // (partitioned storage environment 등)로 인해 신규 로그인 시 오류가 발생할 수 있습니다.
      // 따라서 가장 안정적인 플러터 네이티브 GoogleSignIn 패키지를 사용하여 인증합니다.
      final GoogleSignInAccount? googleUser = await GoogleSignIn(
        serverClientId: '803548605147-8p75oeqvre7frce70lkl59akqung8kd7.apps.googleusercontent.com',
      ).signIn();

      // 사용자가 로그인 팝업을 그냥 닫은 경우 중단
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);

      // 이메일 도메인 화이트리스트 검사
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

      // main.dart의 StreamBuilder가 자동으로 상태를 감지하고 라우팅합니다.
    } catch (e) {
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
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // 로고 영역
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
              if (_isLoading)
                const CircularProgressIndicator(color: Colors.white)
              else
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _signInWithGoogle,
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
                          Image.asset(
                            'assets/icons/google_logo.png',
                            width: 20,
                            height: 20,
                          ),
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
                  ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
