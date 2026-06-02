import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/analytics_service.dart';
import 'package:url_launcher/url_launcher.dart';

class UserGuideScreen extends StatefulWidget {
  const UserGuideScreen({super.key});

  @override
  State<UserGuideScreen> createState() => _UserGuideScreenState();
}

class _UserGuideScreenState extends State<UserGuideScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.screenUserGuide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FA),
        surfaceTintColor: const Color(0xFFF7F8FA),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '이용 안내',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF222222),
            letterSpacing: -0.4,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더 카드
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFF1B2340), Color(0xFF2A3F80)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DASH 한눈에 보기',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 스텝 카드들
            _StepCard(
              stepLabel: '1',
              icon: Icons.edit_note_outlined,
              title: '사례 선택',
              description: '내 사례 또는 동료 상담원의 사례를 선택해요.',
              mockup: const _MockupCtaAndModal(),
            ),
            _StepConnector(),

            _StepCard(
              stepLabel: '2',
              icon: Icons.tune_outlined,
              title: 'DB 유형 선택',
              description: '목적에 따라 두 가지 유형 중 하나를 선택해요.',
              mockup: const _MockupDbTypeSelection(),
            ),
            _StepConnector(),

            _StepCard(
              stepLabel: '3',
              icon: Icons.person_add_outlined,
              title: 'DB 작성',
              description: '시스템에 기입하듯이 DB를 작성해요.',
              tip: '아동 이름은 마스킹되어 외부에 노출되지 않아요.',
              mockup: const _MockupDbCreation(),
            ),
            _StepConnector(),

            _StepCard(
              stepLabel: '4-1',
              icon: Icons.share_outlined,
              title: '동행하셨다면?',
              description: '상담 내용을 모바일 DB로 작성하여 링크를 공유하세요.',
              mockup: const _MockupShareAndNotif(),
            ),
            _StepConnector(),

            // 확장프로그램 배너 (Step 4-2 바로 위)
            _GuideExtensionBanner(),
            const SizedBox(height: 16),

            _StepCard(
              stepLabel: '4-2',
              icon: Icons.computer_outlined,
              title: '내 DB 만들었다면?',
              description: '확장프로그램에서 바로 자동기입하세요.',
              mockup: const _MockupAutoFillAnimation(),
            ),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

}

// ── 스텝 카드 ────────────────────────────────────────────────────────────────
class _StepCard extends StatelessWidget {
  final String stepLabel;
  final IconData icon;
  final String title;
  final String description;
  final String? tip;
  final String? actionLabel;
  final String? actionUrl;
  final Widget? mockup;
  final Widget? extraNote;

  const _StepCard({
    required this.stepLabel,
    required this.icon,
    required this.title,
    required this.description,
    this.tip,
    this.actionLabel,
    this.actionUrl,
    this.mockup,
    this.extraNote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 스텝 번호 + 아이콘
          Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'STEP $stepLabel',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // 텍스트
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4B5563),
                    height: 1.6,
                    letterSpacing: -0.1,
                  ),
                ),
                if (extraNote != null) ...[
                  const SizedBox(height: 10),
                  extraNote!,
                ],
                if (mockup != null) ...[
                  const SizedBox(height: 12),
                  mockup!,
                ],
                if (tip != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '💡 ',
                          style: TextStyle(fontSize: 12),
                        ),
                        Expanded(
                          child: Text(
                            tip!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                              height: 1.5,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (actionLabel != null && actionUrl != null) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse(actionUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.open_in_new,
                              size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            actionLabel!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 스텝 간 연결선 ────────────────────────────────────────────────────────────
class _StepConnector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 38),
      child: Column(
        children: List.generate(
          4,
          (_) => Container(
            width: 2,
            height: 5,
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

// (unused – replaced by _MockupCtaAndModal)

// ── Step 2 목업: 사무실 밖에서 DB 쓰기 버튼 ──────────────────────────────────
class _MockupDbButton extends StatelessWidget {
  const _MockupDbButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Text(
          'DB 작성하러 가기',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

// ── Step 3 목업: 스와이프 공유 애니메이션 ────────────────────────────────────
class _MockupDbCard extends StatefulWidget {
  const _MockupDbCard();

  @override
  State<_MockupDbCard> createState() => _MockupDbCardState();
}

class _MockupDbCardState extends State<_MockupDbCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _slide = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 25), // 대기
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 72.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 25), // 스와이프
      TweenSequenceItem(tween: Tween(begin: 72.0, end: 72.0), weight: 25), // 유지
      TweenSequenceItem(
          tween: Tween(begin: 72.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 25), // 복귀
    ]).animate(_ctrl);
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AnimatedBuilder(
        animation: _slide,
        builder: (_, __) {
          return Stack(
            children: [
              // 배경: 파란 공유 패널
              Positioned.fill(
                child: Container(
                  color: AppColors.primary,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 16),
                  child: const Icon(Icons.ios_share_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
              // 카드: 오른쪽으로 슬라이드
              Transform.translate(
                offset: Offset(_slide.value, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E8EB)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '강O수 아동',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '대상: 피해아동  |  방문',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8B95A1),
                            fontWeight: FontWeight.w500,
                            height: 1.5),
                      ),
                      const Text(
                        '4.14 (화) 11:47 ~ 12:47',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8B95A1),
                            fontWeight: FontWeight.w500,
                            height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Step 4 목업: 푸시 알림 위젯 ──────────────────────────────────────────────
class _MockupNotification extends StatelessWidget {
  const _MockupNotification();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 앱 아이콘
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/icons/logo.png',
              width: 36,
              height: 36,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          // 알림 텍스트
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'DASH',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const Text(
                      '  ·  오후 4:13',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8B95A1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'OOO 상담원님이 DB를 저장했어요.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                    height: 1.4,
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

// ── Step 5 Edge 브라우저 설치 안내 ────────────────────────────────────────────
class _EdgeInstallNote extends StatelessWidget {
  const _EdgeInstallNote();

  @override
  Widget build(BuildContext context) {
    const steps = [
      '브라우저 프로필 아이콘 오른쪽 ··· 버튼 클릭',
      '확장 → 확장 관리',
      'Chrome 웹 스토어 클릭',
      '\'Dash\' 검색 후 설치',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD1D9F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/edge_logo.png', width: 13, height: 13),
              const SizedBox(width: 5),
              const Text(
                'Edge 브라우저 설치 방법',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3B5BDB),
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...steps.asMap().entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.key + 1}.  ',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF3B5BDB),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF374151),
                        height: 1.5,
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

// ── Step 5 목업: NCADS 브라우저 + 확장 패널 ──────────────────────────────────
class _MockupExtensionPopup extends StatelessWidget {
  const _MockupExtensionPopup();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 브라우저 타이틀바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFFE8EAED),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                // macOS 점
                const _BrowserDot(color: Color(0xFFFF5F57)),
                const SizedBox(width: 4),
                const _BrowserDot(color: Color(0xFFFFBD2E)),
                const SizedBox(width: 4),
                const _BrowserDot(color: Color(0xFF28CA41)),
                const SizedBox(width: 8),
                // URL 바
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '아동학대정보시스템',
                      style: TextStyle(fontSize: 8, color: Color(0xFF6B7280)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 콘텐츠: NCADS 폼(좌) + 확장 패널(우)
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // NCADS 폼 (좌측) — 실제 아동학대정보시스템 UI
                  Expanded(
                    flex: 54,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(width: 2.5, height: 10, color: const Color(0xFF3B5BDB)),
                              const SizedBox(width: 3),
                              const Text(
                                '서비스 제공 내용',
                                style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          _NcadsSection(label: '제공구분', value: '제공'),
                          _NcadsSection(label: '서비스제공방법', value: '방문'),
                          _NcadsSection(label: '서비스제공유형', value: '아보전서비스'),
                          _NcadsSection(label: '제공서비스', value: '아동 안전점검'),
                          _NcadsSection(label: '서비스제공기관', value: '대전광역시아동보호'),
                          _NcadsSection(label: '제공장소', value: '아동가정'),
                          const SizedBox(height: 3),
                          Container(height: 0.5, color: const Color(0xFFE5E7EB)),
                          const SizedBox(height: 3),
                          _NcadsSection(label: '대상자', value: '피해아동'),
                          _NcadsSection(label: '서비스제공횟수', value: '1회'),
                          _NcadsSection(label: '이동소요시간', value: '15분'),
                          _NcadsSection(label: '서비스제공일시', value: '5.4 15:00~15:30'),
                          const SizedBox(height: 3),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFD1D5DB), width: 0.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: const Text('서비스내용 입력...', style: TextStyle(fontSize: 6, color: Color(0xFF9CA3AF))),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFD1D5DB), width: 0.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: const Text('상담원소견 입력...', style: TextStyle(fontSize: 6, color: Color(0xFF9CA3AF))),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFF6B7280), borderRadius: BorderRadius.circular(2)),
                                child: const Text('저장', style: TextStyle(fontSize: 6, color: Colors.white, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFFD1D5DB), width: 0.5),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: const Text('닫기', style: TextStyle(fontSize: 6, color: Color(0xFF374151), fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 구분선
                  Container(width: 1, color: const Color(0xFFE5E8EB)),
                  // 확장 패널 (우측) — 실제 Dash 확장프로그램 UI
                  Expanded(
                    flex: 46,
                    child: Container(
                      color: const Color(0xFFF3F4F6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 헤더
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            color: Colors.white,
                            child: Row(
                              children: [
                                Image.asset('assets/icons/logo.png', width: 11, height: 11),
                                const SizedBox(width: 3),
                                const Text('Dash', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                                const Spacer(),
                                const Icon(Icons.close, size: 8, color: Color(0xFF9CA3AF)),
                              ],
                            ),
                          ),
                          // 상태바
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            color: const Color(0xFFEEF2FF),
                            child: const Row(
                              children: [
                                Text('✅', style: TextStyle(fontSize: 6)),
                                SizedBox(width: 3),
                                Expanded(child: Text('삽입할 DB를 선택해주세요', style: TextStyle(fontSize: 6, color: Color(0xFF3B6BFF), fontWeight: FontWeight.w600))),
                              ],
                            ),
                          ),
                          // 탭
                          Container(
                            color: Colors.white,
                            child: Row(
                              children: [
                                _GuideExtTab(label: '대기 중', active: true),
                                _GuideExtTab(label: '이전 기록', active: false),
                              ],
                            ),
                          ),
                          // 선택 버튼
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: const Text('○  선택', style: TextStyle(fontSize: 6, color: Color(0xFF6B7280))),
                            ),
                          ),
                          // DB 카드
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('류O진 아동 사례', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w800, color: Color(0xFF111827), letterSpacing: -0.2)),
                                    const SizedBox(width: 3),
                                    const Text('부사동', style: TextStyle(fontSize: 6, color: Color(0xFF8B95A1))),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                _ExtMiniRow(label: '대상자', value: '피해아동'),
                                _ExtMiniRow(label: '제공구분', value: '제공'),
                                _ExtMiniRow(label: '제공방법', value: '방문'),
                                _ExtMiniRow(label: '서비스유형', value: '아보전'),
                                _ExtMiniRow(label: '제공서비스', value: '심리치료'),
                                _ExtMiniRow(label: '제공장소', value: '기관내'),
                                _ExtMiniRow(label: '제공일시', value: '4.20 11:53~12:53'),
                                const SizedBox(height: 3),
                                const Align(
                                  alignment: Alignment.centerRight,
                                  child: Text('상세 보기 ▼', style: TextStyle(fontSize: 6, color: Color(0xFF6B7280))),
                                ),
                                const Divider(height: 8, color: Color(0xFFE5E7EB)),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Center(
                                    child: Text('⚡ DB 삽입', style: TextStyle(fontSize: 6.5, color: Colors.white, fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                        ],
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

class _BrowserDot extends StatelessWidget {
  final Color color;
  const _BrowserDot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 7, height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ── Step 1 새 목업: DB 작성하기 CTA → 사례 선택 모달 버튼 ──────────────────────
class _MockupCtaAndModal extends StatelessWidget {
  const _MockupCtaAndModal();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // DB 작성하기 버튼 (홈화면 CTA)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Text(
              'DB 작성하러 가기',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF8B95A1), size: 22),
        const SizedBox(height: 10),
        // 사례 선택 모달 mockup
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E8EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '사례 선택',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'DB를 작성할 사례를 선택해주세요.',
                      style: TextStyle(fontSize: 10, color: Color(0xFF8B95A1)),
                    ),
                    const SizedBox(height: 8),
                    // 상담원 필터 chips
                    Row(
                      children: [
                        // 내 사례 chip (선택됨)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: const Text(
                            '내 사례',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 동료 상담원 chip (미선택)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: const Color(0xFFDDE1E7)),
                          ),
                          child: const Text(
                            '오은영 대리님',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF4E5968),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 사례 카드 그리드 (홍O동 1개)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Row(
                  children: [
                    const Expanded(child: _MockupCaseCard(name: '홍O동', dong: '서초구')),
                    const SizedBox(width: 12),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
              // 구분선 + 하단 버튼
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                  border: Border(top: BorderSide(color: Color(0xFFE5E8EB))),
                ),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: const Color(0xFFE5E8EB)),
                        ),
                        child: const Center(
                          child: Text(
                            '상담원 추가',
                            style: TextStyle(
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: const Center(
                          child: Text(
                            '사례 추가',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MockupCaseCard extends StatelessWidget {
  final String name;
  final String dong;
  const _MockupCaseCard({required this.name, required this.dong});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.6,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF222222),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dong,
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textSub.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step 2 새 목업: DB 생성 화면 ───────────────────────────────────────────────
class _MockupDbCreation extends StatelessWidget {
  const _MockupDbCreation();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E8EB)),
      ),
      child: Column(
        children: [
          // AppBar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Color(0xFFF1F3F5))),
            ),
            child: const Row(
              children: [
                Icon(Icons.arrow_back_ios_new, size: 12, color: Color(0xFF8B95A1)),
                Expanded(
                  child: Center(
                    child: Text(
                      'DB 추가',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    ),
                  ),
                ),
                SizedBox(width: 12),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                // 사례 카드
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E8EB)),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '강O수 아동',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '유천동',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 서비스 내용 섹션
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E8EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '서비스 내용',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF3B5BDB)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '아동은 전반적으로 안정된 상태이며, 가정 내 보호자와의 관계 개선이 이루어지고 있음.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF111827), height: 1.5),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('완료', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 상담원 소견 섹션
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E8EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '상담원 소견',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF3B5BDB)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '입력해주세요',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      ),
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

// ── NCADS Section row (개선된 버전) ────────────────────────────────────────────
class _NcadsSection extends StatelessWidget {
  final String label;
  final String value;
  const _NcadsSection({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.5),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(label, style: const TextStyle(fontSize: 6, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                border: Border.all(color: const Color(0xFFBDD0FF), width: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(value, style: const TextStyle(fontSize: 6, color: Color(0xFF3B5BDB), fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NcadsFormRow extends StatelessWidget {
  final String label;
  final String filled;
  const _NcadsFormRow({required this.label, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(label, style: const TextStyle(fontSize: 7, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                border: Border.all(color: const Color(0xFFBDD0FF), width: 0.8),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(filled, style: const TextStyle(fontSize: 7, color: Color(0xFF3B5BDB), fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtMiniRow extends StatelessWidget {
  final String label;
  final String value;
  const _ExtMiniRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(label, style: const TextStyle(fontSize: 7, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          ),
        ],
      ),
    );
  }
}

// ── Step 2 목업: DB 유형 선택 (실제 시트 디자인 동일) ─────────────────────────
class _MockupDbTypeSelection extends StatelessWidget {
  const _MockupDbTypeSelection();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DB 유형 선택',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
          ),
          const SizedBox(height: 3),
          const Text(
            '어떤 목적으로 작성하세요?',
            style: TextStyle(fontSize: 11, color: Color(0xFF8B95A1)),
          ),
          const SizedBox(height: 12),
          _MockupTypeCard(
            icon: Icons.person_outline_rounded,
            title: '내 DB',
            description: '나만 보는 개인 기록이에요',
            accent: false,
          ),
          const SizedBox(height: 8),
          _MockupTypeCard(
            icon: Icons.people_outline_rounded,
            title: '공유할 DB',
            description: '동행자로서 담당자의 DB를 대신 작성하고 공유할 수 있어요',
            accent: true,
          ),
        ],
      ),
    );
  }
}

class _MockupTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool accent;

  const _MockupTypeCard({
    required this.icon,
    required this.title,
    required this.description,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.primary : const Color(0xFF4E5968);
    final bgColor = accent ? AppColors.primary.withValues(alpha: 0.06) : const Color(0xFFF8F9FA);
    final borderColor = accent ? AppColors.primary.withValues(alpha: 0.3) : const Color(0xFFE9ECEF);
    final iconBg = accent ? AppColors.primary.withValues(alpha: 0.12) : const Color(0xFFE9ECEF);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(fontSize: 10.5, color: Color(0xFF8B95A1), height: 1.4)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.5), size: 16),
        ],
      ),
    );
  }
}

class _GuideExtTab extends StatelessWidget {
  final String label;
  final bool active;
  const _GuideExtTab({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          color: Colors.white,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 6.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AppColors.primary : const Color(0xFF9CA3AF),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Step 4-1 목업: 공유 슬라이드 + 그라데이션 화살표 + 푸시 알림 ────────────
class _MockupShareAndNotif extends StatelessWidget {
  const _MockupShareAndNotif();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _MockupDbCard(),
        const _GradientArrow(),
        const _MockupNotification(),
      ],
    );
  }
}

class _GradientArrow extends StatelessWidget {
  const _GradientArrow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A56DB), Color(0xFF7BA7F7)],
          ).createShader(bounds),
          child: const Icon(
            Icons.keyboard_double_arrow_down_rounded,
            size: 32,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── Step 4-2 목업: 확장프로그램 자동기입 애니메이션 ─────────────────────────────
class _MockupAutoFillAnimation extends StatefulWidget {
  const _MockupAutoFillAnimation();

  @override
  State<_MockupAutoFillAnimation> createState() => _MockupAutoFillAnimationState();
}

class _MockupAutoFillAnimationState extends State<_MockupAutoFillAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static const _fields = [
    ('서비스제공방법', '방문'),
    ('서비스유형', '아보전서비스'),
    ('제공서비스', '아동 안전점검'),
    ('대상자', '피해아동'),
    ('제공일시', '5.12 16:09~17:09'),
    ('이동시간', '20분'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        // 0.0~0.2: 대기, 0.2~0.3: 버튼 클릭, 0.3~0.75: 필드 순차 등장, 0.75~1.0: 완료 유지
        final buttonPressed = t >= 0.2 && t < 0.35;
        final fillRatio = t < 0.3 ? 0.0 : t > 0.75 ? 1.0 : (t - 0.3) / (0.75 - 0.3);
        final filledCount = (fillRatio * _fields.length).floor();
        final allDone = t >= 0.75;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 브라우저 타이틀바
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFFE8EAED),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                  ),
                ),
                child: Row(
                  children: [
                    const _BrowserDot(color: Color(0xFFFF5F57)),
                    const SizedBox(width: 4),
                    const _BrowserDot(color: Color(0xFFFFBD2E)),
                    const SizedBox(width: 4),
                    const _BrowserDot(color: Color(0xFF28CA41)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '아동학대정보시스템',
                          style: TextStyle(fontSize: 8, color: Color(0xFF6B7280)),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 콘텐츠: NCADS 폼(좌) + 확장 패널(우)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // NCADS 폼 (좌측) — 필드 순차 기입 애니메이션
                      Expanded(
                        flex: 54,
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(width: 2.5, height: 10, color: const Color(0xFF3B5BDB)),
                                  const SizedBox(width: 3),
                                  const Text(
                                    '서비스 제공 내용',
                                    style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ..._fields.asMap().entries.map((e) {
                                final filled = e.key < filledCount;
                                final isActive = e.key == filledCount && t >= 0.3 && !allDone;
                                return _NcadsFieldAnimated(
                                  label: e.value.$1,
                                  value: e.value.$2,
                                  filled: filled,
                                  active: isActive,
                                );
                              }),
                              const SizedBox(height: 3),
                              // 서비스내용 텍스트 박스
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                                decoration: BoxDecoration(
                                  color: allDone ? const Color(0xFFF0F4FF) : Colors.white,
                                  border: Border.all(
                                    color: allDone ? const Color(0xFFBDD0FF) : const Color(0xFFD1D5DB),
                                    width: 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  allDone ? '아동의 전반적인 상태를 확인하고...' : '서비스내용 입력...',
                                  style: TextStyle(
                                    fontSize: 6,
                                    color: allDone ? const Color(0xFF3B5BDB) : const Color(0xFF9CA3AF),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 구분선
                      Container(width: 1, color: const Color(0xFFE5E8EB)),
                      // 확장 패널 (우측)
                      Expanded(
                        flex: 46,
                        child: Container(
                          color: const Color(0xFFF3F4F6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 헤더
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                color: Colors.white,
                                child: Row(
                                  children: [
                                    Image.asset('assets/icons/logo.png', width: 11, height: 11),
                                    const SizedBox(width: 3),
                                    const Text('Dash', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                                    const Spacer(),
                                    const Icon(Icons.close, size: 8, color: Color(0xFF9CA3AF)),
                                  ],
                                ),
                              ),
                              // 상태바
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                color: allDone ? const Color(0xFFECFDF5) : const Color(0xFFEEF2FF),
                                child: Row(
                                  children: [
                                    Text(allDone ? '✅' : '📋', style: const TextStyle(fontSize: 6)),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text(
                                        allDone ? '자동기입 완료!' : '삽입할 DB를 선택해주세요',
                                        style: TextStyle(
                                          fontSize: 6,
                                          color: allDone ? const Color(0xFF059669) : const Color(0xFF3B6BFF),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // 탭
                              Container(
                                color: Colors.white,
                                child: Row(
                                  children: [
                                    _GuideExtTab(label: '대기 중', active: true),
                                    _GuideExtTab(label: '이전 기록', active: false),
                                  ],
                                ),
                              ),
                              // DB 카드
                              Container(
                                margin: const EdgeInsets.all(5),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text('홍O동 아동 사례', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w800, color: Color(0xFF111827), letterSpacing: -0.2)),
                                        const SizedBox(width: 3),
                                        const Text('서초구', style: TextStyle(fontSize: 6, color: Color(0xFF8B95A1))),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const _ExtMiniRow(label: '대상자', value: '피해아동'),
                                    const _ExtMiniRow(label: '제공방법', value: '방문'),
                                    const _ExtMiniRow(label: '서비스유형', value: '아보전'),
                                    const _ExtMiniRow(label: '제공일시', value: '5.12 16:09~17:09'),
                                    const SizedBox(height: 3),
                                    const Align(
                                      alignment: Alignment.centerRight,
                                      child: Text('상세 보기 ▼', style: TextStyle(fontSize: 6, color: Color(0xFF6B7280))),
                                    ),
                                    const Divider(height: 8, color: Color(0xFFE5E7EB)),
                                    // DB 삽입 버튼 (클릭 애니메이션)
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 120),
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 5),
                                      decoration: BoxDecoration(
                                        color: buttonPressed
                                            ? const Color(0xFF1D4ED8)
                                            : allDone
                                                ? const Color(0xFF059669)
                                                : const Color(0xFF2563EB),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Center(
                                        child: Text(
                                          allDone ? '✅ 기입 완료' : '⚡ DB 삽입',
                                          style: const TextStyle(fontSize: 6.5, color: Colors.white, fontWeight: FontWeight.w700),
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NcadsFieldAnimated extends StatelessWidget {
  final String label;
  final String value;
  final bool filled;
  final bool active;
  const _NcadsFieldAnimated({
    required this.label,
    required this.value,
    required this.filled,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.5),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(label, style: const TextStyle(fontSize: 6, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
              decoration: BoxDecoration(
                color: filled
                    ? const Color(0xFFF0F4FF)
                    : active
                        ? const Color(0xFFFFF8E1)
                        : const Color(0xFFF9FAFB),
                border: Border.all(
                  color: filled
                      ? const Color(0xFFBDD0FF)
                      : active
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFFE5E7EB),
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                filled ? value : active ? '...' : '',
                style: TextStyle(
                  fontSize: 6,
                  color: filled ? const Color(0xFF3B5BDB) : const Color(0xFFD97706),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 하단 확장프로그램 배너 (프로필 화면 배너 동일 디자인) ─────────────────────────
class _GuideExtensionBanner extends StatelessWidget {
  _GuideExtensionBanner();

  static const _storeUrl =
      'https://chromewebstore.google.com/detail/dpncpmegjlgknkagcfjdaccbgmjncdef?utm_source=item-share-cb';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(_storeUrl), mode: LaunchMode.externalApplication),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFEEF3FC),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111111),
                    letterSpacing: -0.3,
                    height: 1.35,
                  ),
                  children: [
                    TextSpan(text: 'DASH '),
                    TextSpan(
                      text: '확장프로그램\n',
                      style: TextStyle(color: Color(0xFF1A56DB)),
                    ),
                    TextSpan(text: '아직 설치하지 않으셨나요?'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 8,
                    top: -6,
                    child: Opacity(
                      opacity: 0.32,
                      child: Transform.rotate(
                        angle: 30 * pi / 180,
                        child: const Icon(
                          Icons.extension,
                          size: 68,
                          color: Color(0xFF1A56DB),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 30),
          ],
        ),
      ),
    );
  }
}
