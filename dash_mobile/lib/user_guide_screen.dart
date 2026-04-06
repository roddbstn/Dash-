import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';
import 'package:url_launcher/url_launcher.dart';

class UserGuideScreen extends StatelessWidget {
  const UserGuideScreen({super.key});

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
                color: AppColors.primary,
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
                    '현장 기록부터 시스템 입력까지\n5단계로 완성됩니다.',
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
              icon: Icons.person_add_outlined,
              title: '새 사례 등록',
              description: '홈 화면 하단의 + 버튼을 눌러 새 사례를 만드세요.\n'
                  '아동 이름과 동(읍·면·동) 정보를 입력하면 사례가 생성됩니다.',
              tip: '아동 이름은 마스킹되어 외부에 노출되지 않습니다.',
            ),
            _StepConnector(),

            _StepCard(
              step: 2,
              icon: Icons.edit_note_outlined,
              title: '상담 기록 작성',
              description: '등록된 사례를 탭하면 상담 기록 폼이 열립니다.\n'
                  '제공 구분, 방법, 서비스 유형, 일시, 내용 등을 입력하세요.\n'
                  '태블릿과 휴대폰 모두 지원합니다.',
              tip: '저장한 기록은 서버 연결 없이도 기기에 보관되며, 연결 복구 시 자동 동기화됩니다.',
            ),
            _StepConnector(),

            _StepCard(
              step: 3,
              icon: Icons.share_outlined,
              title: '상사에게 공유 및 검토 요청',
              description: '작성 완료 후 공유 버튼을 누르면 고유 링크가 생성됩니다.\n'
                  '링크를 상사에게 전달하면 PC 웹에서 내용을 확인하고\n'
                  '수정·검토를 진행할 수 있습니다.',
              tip: '링크는 본인 계정의 기록에만 접근 가능합니다.',
            ),
            _StepConnector(),

            _StepCard(
              step: 4,
              icon: Icons.notifications_active_outlined,
              title: '검토 완료 알림 수신',
              description: '상사가 검토를 완료하면 즉시 푸시 알림이 도착합니다.\n'
                  '홈 화면 알림 탭에서 검토 내용을 확인할 수 있습니다.',
              tip: '알림 설정은 프로필 탭에서 변경할 수 있습니다.',
            ),
            _StepConnector(),

            _StepCard(
              step: 5,
              icon: Icons.computer_outlined,
              title: 'NCADS 자동 입력',
              description: 'PC에서 Chrome 확장프로그램을 설치하세요.\n'
                  'NCADS 업무 시스템에 접속한 상태에서 확장프로그램을 열면\n'
                  '작성한 기록이 클릭 한 번으로 자동 입력됩니다.',
              tip: 'Chrome 웹 스토어에서 무료로 설치할 수 있습니다.',
              actionLabel: 'Chrome 웹 스토어에서 설치하기',
              actionUrl: 'https://chromewebstore.google.com/detail/dpncpmegjlgknkagcfjdaccbgmjncdef?utm_source=item-share-cb',
            ),

            const SizedBox(height: 28),

            // E2EE 안내 박스
            Container(
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
                  const Row(
                    children: [
                      Icon(Icons.lock_outline,
                          size: 15, color: Color(0xFF2563EB)),
                      SizedBox(width: 6),
                      Text(
                        '보안에 대해',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1D4ED8),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _securityRow('모든 상담 내용은 기기에서 AES-256으로 암호화됩니다.'),
                  _securityRow('DASH 서버는 내용을 열람하거나 저장하지 않습니다.'),
                  _securityRow('시스템 전송 완료 후 서버 데이터는 즉시 삭제됩니다.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _securityRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('∙  ',
              style: TextStyle(fontSize: 12, color: Color(0xFF3B82F6))),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1E3A5F),
                height: 1.5,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
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

  const _StepCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.description,
    required this.tip,
    this.actionLabel,
    this.actionUrl,
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
