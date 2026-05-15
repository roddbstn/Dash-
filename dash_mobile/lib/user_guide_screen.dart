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
                  const SizedBox(height: 6),
                  Text(
                    '현장 기록부터 시스템 입력까지\n5단계로 완성돼요.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                      height: 1.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 스텝 카드들
            _StepCard(
              step: 1,
              icon: Icons.edit_note_outlined,
              title: 'DB 작성하기',
              description: 'DB 작성하기를 클릭하여 상담원님의 사례를\n등록해주세요.',
              tip: '저장한 기록은 인터넷이 없어도 폰에 보관되며, 인터넷이 다시 연결되면 자동으로 업로드돼요.',
              mockup: const _MockupCtaAndModal(),
            ),
            _StepConnector(),

            _StepCard(
              step: 2,
              icon: Icons.person_add_outlined,
              title: '상담 기록 작성',
              description: '사례를 선택한 뒤, 시스템에 기입하듯이 DB를 작성해보세요.',
              tip: '아동 이름은 마스킹되어 외부에 노출되지 않아요.',
              mockup: const _MockupDbCreation(),
            ),
            _StepConnector(),

            _StepCard(
              step: 3,
              icon: Icons.share_outlined,
              title: '동행자에게 공유 및 검토 요청',
              description: 'DB 생성 후 동행자에게 공유메모를 전달해보세요. 서비스 내용을 공동으로 수정할 수 있어요.',
              tip: '링크는 본인 계정의 기록에만 접근 가능해요.',
              mockup: const _MockupDbCard(),
            ),
            _StepConnector(),

            _StepCard(
              step: 4,
              icon: Icons.notifications_active_outlined,
              title: '수정 완료 알림 받기',
              description: '동행자가 수정을 완료하면 완료 알림이 도착해요.\n'
                  '완료 즉시 수정 내용이 나의 DB에 반영돼요.',
              tip: '알림 설정은 프로필 탭에서 변경할 수 있어요.',
              mockup: const _MockupNotification(),
            ),
            _StepConnector(),

            _StepCard(
              step: 5,
              icon: Icons.computer_outlined,
              title: '확장프로그램 설치 후 자동입력',
              description: '아동학대정보시스템 화면에서 DASH 확장 프로그램을 열어보세요.\n'
                  '작성한 DB가 그대로 있으며, 클릭 한 번으로 자동 입력돼요.',
              tip: 'Chrome 웹스토어에서 무료로 Dash를 설치하세요.',
              actionLabel: 'Chrome 웹 스토어에서 설치하기',
              actionUrl: 'https://chromewebstore.google.com/detail/dpncpmegjlgknkagcfjdaccbgmjncdef?utm_source=item-share-cb',
              mockup: const _MockupExtensionPopup(),
              extraNote: const _EdgeInstallNote(),
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
  final int step;
  final IconData icon;
  final String title;
  final String description;
  final String tip;
  final String? actionLabel;
  final String? actionUrl;
  final Widget? mockup;
  final Widget? extraNote;

  const _StepCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.description,
    required this.tip,
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
                  'STEP $step',
                  style: const TextStyle(
                    fontSize: 9,
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
                        style: TextStyle(fontSize: 11),
                      ),
                      Expanded(
                        child: Text(
                          tip,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                            height: 1.5,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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

// ── Step 1 목업: 사례 선택 모달 하단 버튼 영역 ────────────────────────────────
class _MockupCaseButton extends StatelessWidget {
  const _MockupCaseButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E8EB)),
      ),
      child: Column(
        children: [
          // 사례 그리드 미리보기 (2열)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Row(
              children: [
                _MockCaseChip('김O희'),
                const SizedBox(width: 8),
                _MockCaseChip('박O준'),
              ],
            ),
          ),
          // 구분선 + 하단 버튼
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
              border: Border(top: BorderSide(color: Color(0xFFE5E8EB))),
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Center(
                      child: Text(
                        '동행 파트너 추가',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: const Color(0xFFE5E8EB)),
                  ),
                  child: const Text(
                    '사례 추가',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Color(0xFF111827),
                    ),
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

class _MockCaseChip extends StatelessWidget {
  final String name;
  const _MockCaseChip(this.name);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E8EB)),
        ),
        child: Center(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
        ),
      ),
    );
  }
}

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
          'DB 작성하기',
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
                            fontSize: 11,
                            color: Color(0xFF8B95A1),
                            fontWeight: FontWeight.w500,
                            height: 1.5),
                      ),
                      const Text(
                        '4.14 (화) 11:47 ~ 12:47',
                        style: TextStyle(
                            fontSize: 11,
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
                const SizedBox(height: 2),
                const Text(
                  '수정 완료 🗒',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'OOO 상담원이 강O수 아동 사례 DB를 일부 수정했어요',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4B5563),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('🔗 공유', style: TextStyle(fontSize: 6, color: Color(0xFF374151))),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // 하단 버튼
                          Container(
                            margin: const EdgeInsets.fromLTRB(5, 0, 5, 4),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1D5DB),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Center(
                              child: Text('삽입할 DB를 선택해주세요', style: TextStyle(fontSize: 6, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
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
              'DB 작성하기',
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
        // 화살표
        const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF8B95A1), size: 22),
        const SizedBox(height: 10),
        // 사례 선택 모달 하단 버튼 영역
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E8EB)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Center(
                    child: Text(
                      '동행 파트너 추가',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: const Color(0xFFE5E8EB)),
                ),
                child: const Text(
                  '사례 추가',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
                      'DB 생성',
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
