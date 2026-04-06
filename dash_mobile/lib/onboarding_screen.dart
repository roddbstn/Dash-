import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const int _pageCount = 4;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_v1_completed', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
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
            // 상단: 건너뛰기
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
                child: _currentPage < _pageCount - 1
                    ? TextButton(
                        onPressed: _finish,
                        child: Text(
                          '건너뛰기',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSub,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                        ),
                      )
                    : const SizedBox(height: 40),
              ),
            ),

            // 페이지 본문
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: const [
                  _OnboardingPage0(),
                  _OnboardingPage1(),
                  _OnboardingPage2(),
                  _OnboardingPage3(),
                ],
              ),
            ),

            // 점 인디케이터
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pageCount, (i) {
                  final isActive = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
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
            const SizedBox(height: 16),

            // 하단 버튼
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                MediaQuery.of(context).padding.bottom + 24,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: _currentPage < _pageCount - 1
                    ? ElevatedButton(
                        onPressed: () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOut,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          '다음',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: _finish,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          '시작하기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 페이지 0: 보안 신뢰 페이지 (첫 화면) ────────────────────────────
class _OnboardingPage0 extends StatelessWidget {
  const _OnboardingPage0();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          // 타이틀
          const Text(
            '아동 정보,\nDASH에 남지 않습니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              letterSpacing: -0.6,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'DASH는 공식 시스템으로 안전하게 전달하는\n보안 전송 도구입니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSub,
              height: 1.5,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 28),
          // 흐름도
          _SecurityFlowDiagram(),
          const SizedBox(height: 24),
          // 보장 항목 카드
          _SecurityGuaranteeCard(),
        ],
      ),
    );
  }
}

class _SecurityFlowDiagram extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 상담원 기기
          _FlowNode(
            icon: Icons.phone_iphone,
            label: '상담원 기기',
            sublabel: '입력 즉시 암호화',
            color: AppColors.primary,
          ),
          _DashedArrow(label: 'E2EE\n암호화 전송'),
          // DASH 서버
          _FlowNode(
            icon: Icons.sync_alt,
            label: 'DASH 서버',
            sublabel: '복호화 불가\n전송 후 즉시 삭제',
            color: const Color(0xFF6B7280),
            isDimmed: true,
          ),
          _DashedArrow(label: '자동\n입력'),
          // 공식 시스템
          _FlowNode(
            icon: Icons.account_balance,
            label: '공식 시스템',
            sublabel: '기관 서버\n(NCADS)',
            color: const Color(0xFF059669),
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

  const _FlowNode({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    this.isDimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDimmed ? 0.55 : 1.0,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDimmed ? const Color(0xFF9CA3AF) : const Color(0xFF111827),
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sublabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
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
      padding: const EdgeInsets.only(bottom: 24),
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
              fontSize: 8,
              color: Color(0xFF94A3B8),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityGuaranteeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GuaranteeRow(
            icon: Icons.lock_outline,
            color: Color(0xFF2563EB),
            text: '입력 즉시 AES-256 암호화 — 평문이 서버에 전달되지 않습니다',
          ),
          const SizedBox(height: 10),
          const _GuaranteeRow(
            icon: Icons.delete_sweep_outlined,
            color: Color(0xFF7C3AED),
            text: '시스템 전송 완료 후 서버 데이터 즉시 삭제',
          ),
          const SizedBox(height: 10),
          const _GuaranteeRow(
            icon: Icons.visibility_off_outlined,
            color: Color(0xFF059669),
            text: 'DASH 서버에서는 누구도 내용을 열람할 수 없습니다 (E2EE)',
          ),
          const SizedBox(height: 10),
          const _GuaranteeRow(
            icon: Icons.account_balance_outlined,
            color: Color(0xFFD97706),
            text: '기관 공식 시스템으로만 전달 — 제3자 제공 없음',
          ),
        ],
      ),
    );
  }
}

class _GuaranteeRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _GuaranteeRow(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1E3A5F),
                height: 1.45,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 공통 페이지 레이아웃 ───────────────────────────────────────────
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
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
          const SizedBox(height: 24),
          // 일러스트 영역
          Expanded(child: illustration),
        ],
      ),
    );
  }
}

// ── 페이지 1: 태블릿·휴대폰으로 DB 작성 ────────────────────────────
class _OnboardingPage1 extends StatelessWidget {
  const _OnboardingPage1();

  @override
  Widget build(BuildContext context) {
    return _PageLayout(
      title: '태블릿·휴대폰으로\nDB 작성',
      subtitle: '현장에서 바로 기록하세요.\n태블릿과 휴대폰 모두 지원합니다.',
      illustration: _Page1Illustration(),
    );
  }
}

class _Page1Illustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFEBF4FF),
              const Color(0xFFDCEEFF),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 배경 원
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // 메인 일러스트
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 두 사람 아이콘
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _PersonCard(
                      icon: Icons.person,
                      color: AppColors.primary,
                      label: '상담사',
                    ),
                    const SizedBox(width: 24),
                    _PersonCard(
                      icon: Icons.person_outline,
                      color: const Color(0xFF6366F1),
                      label: '아동',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // 디바이스 행
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _DeviceChip(
                      icon: Icons.tablet_mac,
                      label: '태블릿',
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '+',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w300,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _DeviceChip(
                      icon: Icons.smartphone,
                      label: '휴대폰',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // DB 작성 표시
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note,
                          color: AppColors.primary, size: 18),
                      const SizedBox(width: 6),
                      const Text(
                        'DB 기록 중...',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _PersonCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _PersonCard(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 30),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w500, color: color),
        ),
      ],
    );
  }
}

class _DeviceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DeviceChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSub),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 페이지 2: 작성한 DB를 곧바로 시스템에 ────────────────────────────
class _OnboardingPage2 extends StatelessWidget {
  const _OnboardingPage2();

  @override
  Widget build(BuildContext context) {
    return _PageLayout(
      title: '작성한 DB를\n곧바로 시스템에',
      subtitle: '클릭 한 번으로 NCADS 등\n업무 시스템에 자동 입력됩니다.',
      illustration: _Page2Illustration(),
    );
  }
}

class _Page2Illustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 모바일 → 확장프로그램 → PC 흐름
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 모바일 앱
              _FlowBox(
                icon: Icons.phone_iphone,
                label: 'DASH 앱',
                color: AppColors.primary,
              ),
              _ArrowChain(),
              // 확장 프로그램
              _FlowBox(
                icon: Icons.extension,
                label: '확장 프로그램',
                color: const Color(0xFF059669),
              ),
              _ArrowChain(),
              // 시스템 PC
              _FlowBox(
                icon: Icons.computer,
                label: '업무 시스템',
                color: const Color(0xFF7C3AED),
              ),
            ],
          ),
          const SizedBox(height: 28),
          // 설명 뱃지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF059669).withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt,
                    color: Color(0xFFF59E0B), size: 18),
                const SizedBox(width: 6),
                const Text(
                  '클릭 한 번으로 자동 입력',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                    letterSpacing: -0.2,
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

class _FlowBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _FlowBox(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ArrowChain extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: List.generate(
          3,
          (i) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 4,
            height: 2,
            decoration: BoxDecoration(
              color: const Color(0xFF9CA3AF),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        )..add(const Icon(Icons.arrow_forward_ios,
            size: 10, color: Color(0xFF9CA3AF))),
      ),
    );
  }
}

// ── 페이지 3: 상사분께 공유드리고 검토받기 ──────────────────────────
class _OnboardingPage3 extends StatelessWidget {
  const _OnboardingPage3();

  @override
  Widget build(BuildContext context) {
    return _PageLayout(
      title: '상사분께 공유드리고\n검토받기',
      subtitle: '작성 즉시 링크를 공유하고\n검토 완료 알림을 받아보세요.',
      illustration: _Page3Illustration(),
    );
  }
}

class _Page3Illustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5F3FF), Color(0xFFEDE9FE)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 모바일 화면 목업
              _MobileMockup(),
              const SizedBox(width: 20),
              // 화살표
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(
                  children: [
                    Icon(Icons.arrow_forward,
                        color: const Color(0xFF7C3AED), size: 22),
                    const SizedBox(height: 4),
                    Text(
                      '공유',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF7C3AED),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // PC 리뷰어 화면 목업
              _PCMockup(),
            ],
          ),
          const SizedBox(height: 20),
          // 검토 완료 알림 칩
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  '검토 완료 알림 수신',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                    letterSpacing: -0.2,
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

class _MobileMockup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: const Center(
              child: Text(
                'DASH',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MockLine(width: 50, color: const Color(0xFFD1D5DB)),
                  const SizedBox(height: 4),
                  _MockLine(width: 38, color: const Color(0xFFE5E7EB)),
                  const SizedBox(height: 4),
                  _MockLine(width: 44, color: const Color(0xFFE5E7EB)),
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Text(
                        '공유',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PCMockup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 100,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(7)),
                ),
                child: const Center(
                  child: Text(
                    'Reviewer',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MockLine(width: 80, color: const Color(0xFFD1D5DB)),
                    const SizedBox(height: 3),
                    _MockLine(width: 60, color: const Color(0xFFE5E7EB)),
                    const SizedBox(height: 3),
                    _MockLine(width: 70, color: const Color(0xFFE5E7EB)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Center(
                            child: Text(
                              '검토 완료',
                              style: TextStyle(
                                fontSize: 5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 모니터 받침
        Container(
          width: 30,
          height: 6,
          color: const Color(0xFFD1D5DB),
        ),
        Container(
          width: 50,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _MockLine extends StatelessWidget {
  final double width;
  final Color color;
  const _MockLine({required this.width, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
