import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/analytics_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  static const int _pageCount = 4;

  static const String _serverClientId =
      '803548605147-8p75oeqvre7frce70lkl59akqung8kd7.apps.googleusercontent.com';

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenOnboarding(0);
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    AnalyticsService.onboardingLoginTapped(_currentPage);
    try {
      final googleSignIn = GoogleSignIn(serverClientId: _serverClientId);
      // Firebase에서 계정 삭제 후 재가입 등에서 캐시 토큰이 남아있는 경우를 대비해
      // signOut + disconnect로 완전 초기화하여 계정 선택 모달을 강제 표시
      await googleSignIn.signOut().catchError((_) {});
      await googleSignIn.disconnect().catchError((_) {});

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return;

      // 계정 선택 완료 후 로딩 표시 (picker가 즉시 열리도록)
      setState(() => _isLoading = true);

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // idToken이 null이면 Firebase 인증 불가 → 명시적 에러 처리
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw Exception(
          'Google 인증 토큰(idToken)을 가져오지 못했습니다.\n'
          '잠시 후 다시 시도하거나, 기기의 Google 계정 연결을 확인해 주세요.',
        );
      }

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: idToken,
      );

      // onboarding 완료 플래그를 먼저 저장 → authStateChanges 스트림 발동 후
      // _PreLoginRouter가 LoginScreen 대신 올바른 화면으로 라우팅되도록 보장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_v1_completed', true);

      await FirebaseAuth.instance.signInWithCredential(credential);
      AnalyticsService.loginSuccess();
      AnalyticsService.onboardingComplete();
    } catch (e) {
      AnalyticsService.loginFailure(e.toString());
      if (mounted) {
        final errStr = e.toString();
        final bool isSha1Error = errStr.contains('ApiException: 10') ||
            errStr.contains('DEVELOPER_ERROR') ||
            errStr.contains('sign_in_failed');
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('로그인 실패'),
            content: Text(
              isSha1Error
                  ? '개발자 오류(code 10): SHA-1 인증서 지문이 Firebase 콘솔에 등록되지 않았거나 앱 설정이 잘못됐습니다.\n\n$errStr'
                  : errStr,
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 52),

            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) {
                  setState(() => _currentPage = i);
                  AnalyticsService.screenOnboarding(i);
                },
                children: const [
                  _OnboardingPage2(),
                  _OnboardingPage1(),
                  _OnboardingPage3(),
                  _OnboardingPage0(),
                ],
              ),
            ),

            // 점 인디케이터
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pageCount, (i) {
                  final isActive = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: isActive ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF222222)
                          : const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),

            // 하단 버튼 영역
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                MediaQuery.of(context).padding.bottom +
                    (MediaQuery.of(context).orientation == Orientation.landscape
                        ? 12
                        : 24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : (_currentPage < _pageCount - 1
                              ? () => _pageController.nextPage(
                                    duration:
                                        const Duration(milliseconds: 350),
                                    curve: Curves.easeInOut,
                                  )
                              : _signInWithGoogle),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentPage == _pageCount - 1
                            ? const Color(0xFFF8FAFC)
                            : AppColors.primary,
                        disabledBackgroundColor: _currentPage == _pageCount - 1
                            ? const Color(0xFFF8FAFC).withValues(alpha: 0.6)
                            : AppColors.primary.withValues(alpha: 0.6),
                        side: _currentPage == _pageCount - 1
                            ? const BorderSide(color: Color(0xFFDDE1E7), width: 1)
                            : BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading && _currentPage == _pageCount - 1
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                                strokeWidth: 2.5,
                              ),
                            )
                          : _currentPage < _pageCount - 1
                              ? const Text(
                                  '다음',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/icons/google_logo.png',
                                      width: 20,
                                      height: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      '구글 계정으로 시작하기',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF222222),
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ],
                                ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 52),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 페이지 0: 보안 신뢰 페이지 (4번째 화면) ─────────────────────────
class _OnboardingPage0 extends StatelessWidget {
  const _OnboardingPage0();

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide > 600;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: isTablet ? 48 : 24),
          const Text(
            '안전하게 보호받는\nDB 작성내용',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              letterSpacing: -0.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '서버에서는 데이터 열람이 불가능해요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              height: 1.5,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isTablet ? 480 : double.infinity,
              ),
              child: _SecurityFlowDiagram(),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _SecurityFlowDiagram extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FlowNode(
                  icon: Icons.phone_iphone,
                  label: '상담원 기기',
                  sublabel: 'DB 암호화',
                  color: AppColors.primary,
                  canSee: true,
                ),
              ),
              _DashedArrow(label: 'E2EE\n암호화 전송'),
              Expanded(
                child: _FlowNode(
                  icon: Icons.sync_alt,
                  label: 'DASH 서버',
                  sublabel: '복호화 불가\n전송 후 즉시 삭제',
                  color: const Color(0xFF6B7280),
                  isDimmed: true,
                  canSee: false,
                ),
              ),
              _DashedArrow(label: '자동\n입력'),
              Expanded(
                child: _FlowNode(
                  icon: Icons.account_balance,
                  label: '공식 시스템',
                  sublabel: '기관 서버\n(NCADS)',
                  color: const Color(0xFF059669),
                  canSee: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE2E8F0), height: 1),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.visibility,
                              size: 12, color: Color(0xFF059669)),
                          SizedBox(width: 4),
                          Text(
                            '열람 가능',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF059669),
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const _LegendRow(label: '상담원 (입력한 사람)'),
                      const SizedBox(height: 4),
                      const _LegendRow(label: '공유받은 상사'),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  color: const Color(0xFFE2E8F0),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.visibility_off,
                              size: 12, color: Color(0xFFDC2626)),
                          SizedBox(width: 4),
                          Text(
                            '열람 불가 (E2EE)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const _LegendRow(label: 'DASH 운영자', isNegative: true),
                      const SizedBox(height: 4),
                      const _LegendRow(label: '외부인 / 해커', isNegative: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowNode extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final bool isDimmed;
  final bool canSee;

  const _FlowNode({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    this.isDimmed = false,
    this.canSee = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDimmed ? 0.55 : 1.0,
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 52,
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: canSee
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFFF8FAFC), width: 1.5),
                    ),
                    child: Icon(
                      canSee ? Icons.visibility : Icons.visibility_off,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDimmed
                  ? const Color(0xFF9CA3AF)
                  : const Color(0xFF111827),
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sublabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF9CA3AF),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedArrow extends StatelessWidget {
  final String label;
  const _DashedArrow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 21),
      child: Column(
        children: [
          Row(
            children: [
              ...List.generate(
                4,
                (i) => Container(
                  width: 4,
                  height: 1.5,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  color: const Color(0xFFCBD5E1),
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 8, color: Color(0xFFCBD5E1)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF94A3B8),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String label;
  final bool isNegative;
  const _LegendRow({required this.label, this.isNegative = false});

  @override
  Widget build(BuildContext context) {
    final dotColor =
        isNegative ? const Color(0xFFDC2626) : const Color(0xFF059669);
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF6B7280),
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

// ── 공통 페이지 레이아웃 ─────────────────────────────────────────────
class _PageLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget illustration;

  const _PageLayout({
    required this.title,
    required this.subtitle,
    required this.illustration,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide > 600;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          SizedBox(height: isTablet ? 48 : 24),
          SizedBox(
            height: 60,
            child: Align(
              alignment: Alignment.center,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                  letterSpacing: -0.5,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              height: 1.5,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: illustration),
        ],
      ),
    );
  }
}

// ── 페이지 1: 태블릿·휴대폰으로 DB 작성 (2번째 화면) ──────────────────
class _OnboardingPage1 extends StatelessWidget {
  const _OnboardingPage1();

  @override
  Widget build(BuildContext context) {
    return _PageLayout(
      title: '모바일·태블릿으로\nDB 작성하기',
      subtitle: '현장에서 바로 기록하세요',
      illustration: _Page1Illustration(),
    );
  }
}

class _Page1Illustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide > 600;
    return LayoutBuilder(
      builder: (context, constraints) {
        const baseW = 185.0;
        const baseH = 370.0;
        double targetW = isTablet ? baseW * 1.5 : baseW;
        double targetH = isTablet ? baseH * 1.5 : baseH;
        final maxH = constraints.maxHeight - 16;
        if (targetH > maxH && maxH > 0) {
          final factor = maxH / targetH;
          targetW *= factor;
          targetH = maxH;
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: targetW,
              height: targetH,
              child: FittedBox(
                fit: BoxFit.contain,
                child: _DBEntryPhoneMockup(),
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

// ── 페이지 2: 작성한 DB를 곧바로 시스템에 (1번째 화면) ─────────────────
class _OnboardingPage2 extends StatelessWidget {
  const _OnboardingPage2();

  @override
  Widget build(BuildContext context) {
    return _PageLayout(
      title: '작성한 DB를\n곧바로 시스템에',
      subtitle: '크롬 확장프로그램에 저장해놓고,\n시스템에 원클릭 기입하세요',
      illustration: _Page2Illustration(),
    );
  }
}

class _Page2Illustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackH =
            (constraints.maxHeight * 0.88).clamp(220.0, 340.0);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt, color: Color(0xFFF59E0B), size: 14),
                  SizedBox(width: 5),
                  Text(
                    '클릭 한 번으로 자동 입력',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      constraints.maxWidth > 600 ? 520 : double.infinity,
                ),
                child: SizedBox(
                  height: stackH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: _NCADSBrowserMock()),
                      Positioned(
                        top: 0,
                        right: 0,
                        width: 126,
                        child: _DashExtensionPopup(),
                      ),
                      Positioned(
                        top: 102,
                        right: 126,
                        child: _AutoFillArrow(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── DB 작성 모바일 목업 ─────────────────────────────────────────────
class _DBEntryPhoneMockup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 185,
        height: 370,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(5),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              color: const Color(0xFFF7F8FA),
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        const Text(
                          '12:39',
                          style: TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.signal_cellular_alt,
                            size: 8, color: Color(0xFF111827)),
                        const SizedBox(width: 2),
                        const Icon(Icons.wifi,
                            size: 8, color: Color(0xFF111827)),
                        const SizedBox(width: 2),
                        const Icon(Icons.battery_full,
                            size: 8, color: Color(0xFF111827)),
                      ],
                    ),
                  ),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_back_ios,
                            size: 9, color: Color(0xFF374151)),
                        const Expanded(
                          child: Text(
                            'DB 생성',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const Icon(Icons.link_outlined,
                            size: 10, color: Color(0xFF374151)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 7),
                            padding:
                                const EdgeInsets.fromLTRB(9, 5, 9, 5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                  color: const Color(0xFFE5E7EB)),
                            ),
                            child: const Row(
                              children: [
                                Text(
                                  '이O춘 아동',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '태평2동',
                                  style: TextStyle(
                                    fontSize: 7.5,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 7),
                            padding:
                                const EdgeInsets.fromLTRB(9, 5, 9, 5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                  color: AppColors.primary, width: 1.2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '서비스 내용',
                                  style: TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      fontSize: 7,
                                      color: Color(0xFF374151),
                                      height: 1.45,
                                      letterSpacing: -0.1,
                                    ),
                                    children: [
                                      const TextSpan(
                                        text:
                                            '아동은 낯선 환경에서 심한 불안 증상을 보이며, 보호자와 분리 시 과도한 울음과 신체 증상을 나타냄. 이번 방문에서 ',
                                      ),
                                      TextSpan(
                                        text: '|',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 7),
                            padding:
                                const EdgeInsets.fromLTRB(9, 5, 9, 5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                  color: const Color(0xFFE5E7EB)),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '상담원 소견',
                                  style: TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '상담원님의 소견을 입력해주세요',
                                  style: TextStyle(
                                    fontSize: 7,
                                    color: Color(0xFFD1D5DB),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 7),
                            padding:
                                const EdgeInsets.fromLTRB(9, 4, 9, 5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                  color: const Color(0xFFE5E7EB)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '대상자',
                                  style: TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Wrap(
                                  spacing: 3,
                                  runSpacing: 3,
                                  children: [
                                    _MiniChip(
                                        label: '피해아동', selected: true),
                                    _MiniChip(label: '사례관리대상자'),
                                    _MiniChip(label: '가족전체'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 7),
                            padding:
                                const EdgeInsets.fromLTRB(9, 4, 9, 5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                  color: const Color(0xFFE5E7EB)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '제공구분',
                                  style: TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Wrap(
                                  spacing: 3,
                                  runSpacing: 3,
                                  children: [
                                    _MiniChip(
                                        label: '제공', selected: true),
                                    _MiniChip(label: '부가업무'),
                                    _MiniChip(label: '거부'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 7),
                            width: double.infinity,
                            padding:
                                const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                '저장',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final bool selected;
  const _MiniChip({required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: selected ? AppColors.primary : const Color(0xFFD1D5DB),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 6.5,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : const Color(0xFF374151),
        ),
      ),
    );
  }
}

// NCADS 아동정보시스템 브라우저 목업
class _NCADSBrowserMock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF3F4F6),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: [
                ...List.generate(
                  3,
                  (i) => Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: [
                        const Color(0xFFEF4444),
                        const Color(0xFFF59E0B),
                        const Color(0xFF10B981),
                      ][i],
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFD1D5DB)),
                    ),
                    child: const Center(
                      child: Text(
                        '아동학대정보시스템',
                        style:
                            TextStyle(fontSize: 6, color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 28),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 13,
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          '서비스 제공 내용',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _NCADSFormRow(label: '제공구분', value: '제공', filled: true),
                    _NCADSFormRow(
                        label: '서비스유형', value: '아보전', filled: true),
                    _NCADSFormRow(
                        label: '대상자', value: '피해아동', filled: true),
                    _NCADSFormRow(
                      label: '제공기관',
                      value: '대전광역시아동보호전문기관',
                      filled: true,
                    ),
                    _NCADSFormRow(
                        label: '제공장소', value: '기관내', filled: true),
                    _NCADSFormRow(
                      label: '제공일시',
                      value: '3/17 16:00~17:00',
                      filled: true,
                    ),
                    _NCADSFormRow(
                        label: '서비스\n제공자', value: '김상담원', filled: true),
                    _NCADSTextareaRow(
                      label: '서비스내용',
                      text: '아동은 낯선 환경에서 심한 불안 증상을 보이며, 보호자와 분리 시 과도한 울음과 신체 증상을 나타냄.',
                    ),
                    _NCADSTextareaRow(
                      label: '상담원소견',
                      text: '',
                      hint: '상담원 소견을 입력해주세요.',
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _NCADSButton(
                            label: '저장', color: const Color(0xFF2563EB)),
                        const SizedBox(width: 4),
                        _NCADSButton(
                            label: '취소', color: const Color(0xFF6B7280)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NCADSFormRow extends StatelessWidget {
  final String label;
  final String value;
  final bool filled;
  const _NCADSFormRow(
      {required this.label, required this.value, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? const Color(0xFFFEFCE8) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: filled ? const Color(0xFFFDE047) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 38,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 7, color: Color(0xFF6B7280), height: 1.3),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.w600,
                color: filled
                    ? const Color(0xFF78350F)
                    : const Color(0xFF374151),
                height: 1.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (filled)
            const Icon(Icons.check_circle_outline,
                size: 9, color: Color(0xFF059669)),
        ],
      ),
    );
  }
}

class _NCADSButton extends StatelessWidget {
  final String label;
  final Color color;
  const _NCADSButton({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 7, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

class _NCADSTextareaRow extends StatelessWidget {
  final String label;
  final String text;
  final String hint;
  const _NCADSTextareaRow(
      {required this.label, required this.text, this.hint = ''});

  @override
  Widget build(BuildContext context) {
    final isEmpty = text.isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: BoxDecoration(
        color: isEmpty ? const Color(0xFFF9FAFB) : const Color(0xFFFEFCE8),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isEmpty ? const Color(0xFFE5E7EB) : const Color(0xFFFDE047),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 7, color: Color(0xFF6B7280), height: 1.3),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              isEmpty ? hint : text,
              style: TextStyle(
                fontSize: 7,
                color: isEmpty
                    ? const Color(0xFFD1D5DB)
                    : const Color(0xFF78350F),
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// DASH 확장 프로그램 팝업
class _DashExtensionPopup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(-2, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                color: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.extension, size: 9, color: Colors.white),
                        SizedBox(width: 3),
                        Text(
                          'DASH',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Text('×',
                        style:
                            TextStyle(fontSize: 10, color: Colors.white70)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            '강O수 아동 사례',
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '완료',
                            style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text('유천동',
                        style:
                            TextStyle(fontSize: 7, color: Color(0xFF9CA3AF))),
                    const SizedBox(height: 6),
                    Container(height: 1, color: const Color(0xFFF3F4F6)),
                    const SizedBox(height: 6),
                    _ExtCardRow(label: '제공구분', value: '제공'),
                    _ExtCardRow(label: '제공서비스', value: '아보전'),
                    _ExtCardRow(label: '대상자', value: '피해아동'),
                    _ExtCardRow(label: '제공장소', value: '기관내'),
                    _ExtCardRow(label: '제공일시', value: '3/17 16:00~17:00'),
                    const SizedBox(height: 7),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt, size: 9, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              '자동 기입',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtCardRow extends StatelessWidget {
  final String label;
  final String value;
  const _ExtCardRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: const TextStyle(fontSize: 7, color: Color(0xFF9CA3AF)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoFillArrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back, size: 10, color: Color(0xFF6366F1)),
            ...List.generate(
              4,
              (i) => Container(
                width: 3,
                height: 1.5,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                color: const Color(0xFF6366F1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          '자동 입력',
          style: TextStyle(
            fontSize: 7,
            color: Color(0xFF6366F1),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── 페이지 3: 동행자와 함께 공유 (3번째 화면) ────────────────────────
class _OnboardingPage3 extends StatelessWidget {
  const _OnboardingPage3();

  @override
  Widget build(BuildContext context) {
    return _PageLayout(
      title: '동행자와 함께\n상담 내용 공유하기',
      subtitle: '공유 메모로 DB를 관리해요',
      illustration: _Page3Illustration(),
    );
  }
}

class _Page3Illustration extends StatelessWidget {
  static const double _basePhoneW = 185.0;
  static const double _basePhoneH = 370.0;
  static const double _shadowPad = 16.0;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide > 600;
    return LayoutBuilder(
      builder: (context, constraints) {
        double phoneW = isTablet ? _basePhoneW * 1.5 : _basePhoneW;
        double phoneH = isTablet ? _basePhoneH * 1.5 : _basePhoneH;
        final maxAllowedH = constraints.maxHeight - _shadowPad;
        if (phoneH > maxAllowedH && maxAllowedH > 0) {
          phoneH = maxAllowedH;
          phoneW = _basePhoneW * (phoneH / _basePhoneH);
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: SizedBox(
                width: phoneW,
                height: phoneH,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _basePhoneW,
                    height: _basePhoneH,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(5),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: const _ReviewerPhoneMockup(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: _shadowPad),
          ],
        );
      },
    );
  }
}

class _ReviewerPhoneMockup extends StatefulWidget {
  const _ReviewerPhoneMockup({super.key});
  @override
  State<_ReviewerPhoneMockup> createState() => _ReviewerPhoneMockupState();
}

class _ReviewerPhoneMockupState extends State<_ReviewerPhoneMockup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Text(
                  '12:39',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.signal_cellular_alt,
                    size: 8, color: Color(0xFF111827)),
                const SizedBox(width: 2),
                const Icon(Icons.wifi, size: 8, color: Color(0xFF111827)),
                const SizedBox(width: 2),
                const Icon(Icons.battery_full,
                    size: 8, color: Color(0xFF111827)),
              ],
            ),
          ),
          Container(
            color: const Color(0xFFF9FAFB),
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 5),
            child: Row(
              children: [
                const Icon(Icons.lock_outline,
                    size: 8, color: Color(0xFF9CA3AF)),
                const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'dash.qpon/review?token=...',
                      style: TextStyle(
                          fontSize: 5.5, color: Color(0xFF6B7280)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '강O수 아동 사례',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '홍길동 상담원 작성',
                      style: TextStyle(
                          fontSize: 6.5, color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '서비스 내용',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4E5968),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Text(
                        '아동은 낯선 환경에서 심한 불안 증상을 보이며, 보호자와 분리 시 과도한 울음과 신체 증상을 나타냄.',
                        style: const TextStyle(
                            fontSize: 6.5, color: Color(0xFF374151), height: 1.4),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '상담원 소견',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4E5968),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: AppColors.primary, width: 1.2),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: const Text(
                              '지속적인 심리 지원이 필요하며',
                              style: TextStyle(
                                  fontSize: 6.5,
                                  color: Color(0xFF374151),
                                  height: 1.4),
                            ),
                          ),
                          FadeTransition(
                            opacity: _cursorController,
                            child: Container(
                              width: 1.2,
                              height: 10,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 4, 7, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  '검토 완료 알림 보내기',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
