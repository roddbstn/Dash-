import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      // 다시 안정적인 버전의 기본 생성자 사용
      final googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Firebase 인증용 Credential 생성
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      await FirebaseAuth.instance.signInWithCredential(credential);
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // 로고 영역 (나중에 대시 로고 넣기)
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.flash_on_rounded, color: AppColors.primary, size: 40),
              ),
              const SizedBox(height: 24),
              const Text(
                'Dash',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.textMain),
              ),
              const SizedBox(height: 8),
              const Text(
                '현장 활동 기록의 혁신, 대시',
                style: TextStyle(fontSize: 16, color: AppColors.textSub, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (_isLoading)
                const CircularProgressIndicator(color: AppColors.primary)
              else
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1F1F1F),
                        side: const BorderSide(color: Color(0xFF747775)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), // Google Guideline radius
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ).copyWith(
                        elevation: WidgetStateProperty.resolveWith<double>((Set<WidgetState> states) {
                          if (states.contains(WidgetState.hovered)) return 1.0;
                          if (states.contains(WidgetState.pressed)) return 0.0;
                          return 0.0;
                        }),
                        backgroundColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
                          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) {
                            return const Color(0xFF303030).withValues(alpha: 0.08);
                          }
                          return Colors.white;
                        }),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            margin: const EdgeInsets.only(right: 10),
                            child: Center(
                              child: Text(
                                'G',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Roboto', 
                                  foreground: Paint()..shader = const LinearGradient(
                                    colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335)],
                                  ).createShader(const Rect.fromLTWH(0, 0, 20, 20)),
                                ),
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Text(
                              'Continue with Google', 
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14, 
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w500, 
                                color: Color(0xFF1F1F1F),
                                letterSpacing: 0.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 30), // visually balance the icon width + margin
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
