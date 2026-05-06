import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/analytics_service.dart';

class SecurityDetailScreen extends StatefulWidget {
  const SecurityDetailScreen({super.key});

  @override
  State<SecurityDetailScreen> createState() => _SecurityDetailScreenState();
}

class _SecurityDetailScreenState extends State<SecurityDetailScreen> {
  bool _logged = false;

  @override
  Widget build(BuildContext context) {
    if (!_logged) {
      _logged = true;
      AnalyticsService.screenSecurityDetail();
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FA),
        surfaceTintColor: const Color(0xFFF7F8FA),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '암호화 구조 안내',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF222222),
            letterSpacing: -0.4,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 인트로 ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '왜 DASH는 내용을 볼 수 없나요?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '열쇠가 없기 때문입니다. 상담원님의 데이터를 잠그는 열쇠는\n'
                    '상담원님의 기기에서만 만들어지며, DASH 서버에는\n'
                    '전달되지 않습니다.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.88),
                      height: 1.6,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── 섹션 1: 데이터 이동 경로 ─────────────────────────────
            _sectionTitle('데이터가 이동하는 경로'),
            const SizedBox(height: 14),

            // STEP 1
            _FlowStep(
              icon: Icons.smartphone_outlined,
              iconBgColor: const Color(0xFF3B6BFF),
              label: 'STEP 1',
              title: '상담원 기기 (스마트폰)',
              rows: const [
                _FlowRow(symbol: '✏️', text: 'DB 내용 입력'),
                _FlowRow(symbol: '🔑', text: 'DB 저장 즉시 데이터 암호화\n(열쇠는 기기 안에만 존재,\n본인만 열람 가능)'),
                _FlowRow(symbol: '📤', text: '서버에는 암호문만 전송됨'),
              ],
              tagText: '열쇠 생성 위치',
              tagColor: const Color(0xFF16A34A),
            ),

            _Arrow(),

            // STEP 2
            _FlowStep(
              icon: Icons.dns_outlined,
              iconBgColor: const Color(0xFF64748B),
              label: 'STEP 2',
              title: 'DASH 서버',
              rows: const [
                _FlowRow(symbol: '🔒', text: '암호문 형태로만 수신·보관'),
                _FlowRow(symbol: '🚫', text: '열쇠 없음 → 내용 파악 불가'),
                _FlowRow(symbol: '📋', text: '저장 포맷: a3f9b2c1e8d4… (무의미한 문자열)'),
              ],
              tagText: '열쇠 없음',
              tagColor: const Color(0xFFDC2626),
            ),

            _Arrow(),

            // STEP 3 — 두 갈래
            _sectionSubtitle('전달 경로 (두 가지)'),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 경로 A
                Expanded(
                  child: _FlowStepSmall(
                    icon: Icons.link_outlined,
                    iconBgColor: const Color(0xFF7C3AED),
                    label: '경로 A',
                    title: '공유 링크\n→ 상사 브라우저',
                    bullets: const [
                      '링크 URL 끝 #뒤에\n열쇠 포함',
                      '#뒤는 서버에\n전달되지 않음\n(브라우저 표준)',
                      '상사 브라우저가\n열쇠로 직접 복호화',
                    ],
                    highlightIndices: const [2],
                  ),
                ),
                const SizedBox(width: 10),
                // 경로 B
                Expanded(
                  child: _FlowStepSmall(
                    icon: Icons.extension_outlined,
                    iconBgColor: const Color(0xFF0891B2),
                    label: '경로 B',
                    title: '크롬 확장프로그램\n→ NCADS(아동학대정보시스템) 입력',
                    bullets: const [
                      '상담원 본인 구글\n계정 로그인 필수',
                      '기기의 열쇠로\n자동 복호화',
                      'NCADS에 자동 입력',
                    ],
                    highlightIndices: const [1],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── 복호화 설명 ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text('💡', style: TextStyle(fontSize: 13)),
                      SizedBox(width: 6),
                      Text(
                        '* 복호화는 뭔가요?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    '복호화란 암호화된 데이터를 열쇠(키)를 이용해 원래의 읽을 수 있는 형태로 되돌리는 과정입니다. '
                    '잠긴 금고를 열쇠로 열어 내용물을 꺼내는 것과 같습니다. '
                    '열쇠가 없으면 금고를 열 수 없듯, DASH 서버에는 열쇠가 전달되지 않아 서버에서는 '
                    '어떤 방법으로도 내용을 복호화할 수 없습니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF78350F),
                      height: 1.65,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),

            _Arrow(),

            // STEP 4
            _FlowStep(
              icon: Icons.task_alt_outlined,
              iconBgColor: const Color(0xFF16A34A),
              label: 'STEP 4',
              title: '전달 완료 후',
              rows: const [
                _FlowRow(symbol: '✅', text: 'NCADS(아동학대정보시스템)에 자동 입력 완료'),
                _FlowRow(
                  symbol: '🔒',
                  text: 'DASH 서버 암호문은 계속 보존\n(상담원 케이스 조회 가능, 삭제되지 않음)',
                ),
                _FlowRow(symbol: '📋', text: '아동 정보는 NCADS에 최종 보관·관리'),
              ],
              tagText: 'NCADS 최종 보관',
              tagColor: const Color(0xFF16A34A),
            ),

            const SizedBox(height: 32),

            // ── 섹션 PIN 설명 ────────────────────────────────────────
            _sectionTitle('PIN은 왜 필요한가요?'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 보호 효과 요약 ──────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 16, color: Color(0xFF2563EB)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'PIN을 설정하면 기기를 분실하거나 타인이 기기에 접근하더라도 '
                            'PIN 없이는 상담 기록을 열람할 수 없습니다. '
                            '기기 잠금(지문·패턴)이 우회되더라도 데이터는 암호화된 채로 보호됩니다.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1D4ED8),
                              height: 1.65,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'PIN = 열쇠를 잠그는 또 다른 열쇠',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '상담원님의 암호화 열쇠는 기기 안에 그냥 보관되지 않습니다. '
                    'PIN으로 한 번 더 잠근 상태로 저장됩니다. '
                    '즉, PIN은 열쇠를 꺼내기 위한 또 다른 열쇠입니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      height: 1.65,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 케이스 1: 최초 DB 생성
                  _PinCaseCard(
                    icon: Icons.lock_outline,
                    iconColor: const Color(0xFF3B6BFF),
                    title: '상담 기록 첫 저장 시 — PIN 설정',
                    steps: const [
                      '상담원님이 PIN을 최초 설정',
                      '기기 내부에서 암호화 열쇠 생성',
                      '그 열쇠를 PIN으로 한 번 더 암호화하여 기기에 저장',
                      '이후 모든 상담 기록은 이 열쇠로 암호화됨',
                    ],
                    note: 'PIN을 분실하면 암호화된 열쇠를 풀 수 없어, 기존에 저장된 기록을 다시 볼 수 없게 됩니다',
                  ),
                  const SizedBox(height: 10),
                  // 케이스 2: 크롬 익스텐션 최초 로그인
                  _PinCaseCard(
                    icon: Icons.extension_outlined,
                    iconColor: const Color(0xFF0891B2),
                    title: '크롬 익스텐션 최초 로그인 시 — PIN 입력',
                    steps: const [
                      '익스텐션에서 구글 계정으로 로그인',
                      'PIN 입력 요청 — 기기에 잠긴 열쇠를 꺼내기 위해',
                      'PIN으로 열쇠가 해제됨',
                      '익스텐션이 열쇠를 받아 암호문을 복호화',
                      'NCADS(아동학대정보시스템)에 자동 입력',
                    ],
                    note: 'PIN 인증을 거치면 열쇠가 해제되며, 타인이 기기를 사용하더라도 PIN 없이는 데이터를 열람할 수 없습니다',
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '* PIN번호는 DB를 처음 만들 때 생성하며, 프로필 설정에서 확인할 수 있어요.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                      height: 1.5,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── 섹션 2: 누가 볼 수 있나 ─────────────────────────────
            _sectionTitle('누가 데이터를 볼 수 있나요?'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _AccessRow(
                    subject: '상담원 본인',
                    icon: Icons.person_outline,
                    canAccess: true,
                    reason: '열쇠를 직접 보유하고 있어 복호화 가능',
                    isFirst: true,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _AccessRow(
                    subject: '상담원이 링크를 공유한 상사',
                    icon: Icons.supervisor_account_outlined,
                    canAccess: true,
                    reason: '공유 링크 안에 열쇠가 포함되어 있어 브라우저에서 복호화 가능',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _AccessRow(
                    subject: 'DASH 운영진 · 서버 관리자',
                    icon: Icons.business_outlined,
                    canAccess: false,
                    reason: '서버에 열쇠가 없어 암호문만 볼 수 있음. 기술적으로 열람 불가',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _AccessRow(
                    subject: '링크를 받지 않은 제3자',
                    icon: Icons.block_outlined,
                    canAccess: false,
                    reason: '열쇠도 없고 암호문에 접근할 방법도 없음',
                    isLast: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── 섹션 3: 서버에 저장되는 포맷 ────────────────────────
            _sectionTitle('서버에 실제 저장되는 형태'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '// DASH 서버 DB에 저장된 실제 데이터',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 식별 정보
                  const Text(
                    '// ── 식별 정보 (마스킹 처리) ──',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  _CodeLine(label: 'case_name', value: '김O재', isPlain: true, desc: '아동 이름 — 중간 글자 마스킹 처리'),
                  _CodeLine(label: 'dong', value: '마포구 서교동', isPlain: true, desc: '아동이 거주하는 동'),
                  const SizedBox(height: 8),
                  // 서비스 기록
                  const Text(
                    '// ── 서비스 기록 (평문 저장) ──',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  _CodeLine(label: 'status', value: 'Synced', isPlain: true, desc: '동기화 상태 — Synced: 서버 저장 완료'),
                  _CodeLine(label: 'service_date', value: '2024-03-15 14:30', isPlain: true, desc: '서비스 제공일시'),
                  _CodeLine(label: 'service_method', value: '방문', isPlain: true, desc: '서비스 제공방법'),
                  _CodeLine(label: 'service_type', value: '일반사례관리', isPlain: true, desc: '서비스 유형 / 제공유형'),
                  _CodeLine(label: 'travel_time', value: '20', isPlain: true, desc: '이동 소요시간 (분)'),
                  _CodeLine(label: 'location', value: '아동 가정', isPlain: true, desc: '서비스 제공 장소'),
                  _CodeLine(label: 'service_count', value: '3', isPlain: true, desc: '제공 횟수'),
                  const SizedBox(height: 8),
                  // 민감 내용 (암호화)
                  const Text(
                    '// ── 민감 내용 (AES-256 암호화) ──',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  _CodeLine(
                    label: 'encrypted_blob',
                    value: 'U2FsdGVkX1+a3f9b2c1e8d4…',
                    isPlain: false,
                    desc: 'AES-256 암호문 — 열쇠 없이 해독 절대 불가',
                  ),
                  _CodeLine(
                    label: 'service_description',
                    value: '(암호문 내 포함 — 열람 불가)',
                    isPlain: false,
                    desc: '서비스 내용 설명',
                  ),
                  _CodeLine(
                    label: 'agent_opinion',
                    value: '(암호문 내 포함 — 열람 불가)',
                    isPlain: false,
                    desc: '상담원 소견',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '초록색 항목은 평문(읽을 수 있는 값)으로 저장되며,\n'
              '붉은색 항목은 암호화된 상태로 DASH를 포함한 누구도 열람할 수 없습니다.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSub,
                height: 1.6,
                letterSpacing: -0.1,
              ),
            ),

            const SizedBox(height: 32),

            // ── 섹션 4: 기술 명세 ────────────────────────────────────
            _sectionTitle('적용된 암호화 기술'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _SpecRow(
                    label: '암호화 방식',
                    value: 'AES-256 (종단간 암호화, E2EE)',
                    isFirst: true,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _SpecRow(
                    label: '열쇠 생성 위치',
                    value: '상담원 기기 내부 (서버 미전송)',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _SpecRow(
                    label: '전송 구간',
                    value: 'HTTPS (전송 중 이중 암호화)',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _SpecRow(
                    label: 'PIN 저장',
                    value: '기기 보안 저장소 (서버 미저장)',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _SpecRow(
                    label: '서버 데이터 보존',
                    value: 'NCADS 자동 입력 후에도 DASH 서버 암호문 보존\n'
                        '(상담원 케이스 기록 계속 조회 가능)\n'
                        '최대 5년 후 자동 파기 (아동복지법 제28조)',
                    isLast: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Color(0xFF111827),
          letterSpacing: -0.3,
        ),
      );

  Widget _sectionSubtitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280),
          letterSpacing: -0.2,
        ),
      );
}

// ── 플로우 스텝 ─────────────────────────────────────────────────
class _FlowStep extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final String label;
  final String title;
  final List<_FlowRow> rows;
  final String tagText;
  final Color tagColor;

  const _FlowStep({
    required this.icon,
    required this.iconBgColor,
    required this.label,
    required this.title,
    required this.rows,
    required this.tagText,
    required this.tagColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: iconBgColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tagText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: tagColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  final String symbol;
  final String text;

  const _FlowRow({required this.symbol, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(symbol, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF374151),
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

// ── 작은 플로우 스텝 (두 갈래용) ────────────────────────────────
class _FlowStepSmall extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final String label;
  final String title;
  final List<String> bullets;
  final List<int> highlightIndices;

  const _FlowStepSmall({
    required this.icon,
    required this.iconBgColor,
    required this.label,
    required this.title,
    required this.bullets,
    this.highlightIndices = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: iconBgColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
              height: 1.4,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          ...bullets.asMap().entries.map(
            (entry) {
              final idx = entry.key;
              final b = entry.value;
              final isHighlighted = highlightIndices.contains(idx);
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: isHighlighted
                    ? Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF9C3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '∙ ',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: b,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF374151),
                                        height: 1.5,
                                        letterSpacing: -0.1,
                                      ),
                                    ),
                                    const TextSpan(
                                      text: ' *',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFD97706),
                                        fontWeight: FontWeight.w800,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '∙ ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              b,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF374151),
                                height: 1.5,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── 화살표 ───────────────────────────────────────────────────────
class _Arrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Column(
          children: [
            Container(width: 2, height: 10, color: const Color(0xFFCBD5E1)),
            const Icon(Icons.keyboard_arrow_down, color: Color(0xFFCBD5E1), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── 접근 권한 행 ─────────────────────────────────────────────────
class _AccessRow extends StatelessWidget {
  final String subject;
  final IconData icon;
  final bool canAccess;
  final String reason;
  final bool isFirst;
  final bool isLast;

  const _AccessRow({
    required this.subject,
    required this.icon,
    required this.canAccess,
    required this.reason,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: canAccess
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 17,
              color: canAccess
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subject,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: canAccess
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        canAccess ? '열람 가능' : '열람 불가',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: canAccess
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    height: 1.5,
                    letterSpacing: -0.1,
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

// ── 코드 라인 ────────────────────────────────────────────────────
class _CodeLine extends StatelessWidget {
  final String label;
  final String value;
  final bool isPlain;
  final String? desc;

  const _CodeLine({
    required this.label,
    required this.value,
    required this.isPlain,
    this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
              ),
              children: [
                TextSpan(
                  text: '"$label": ',
                  style: const TextStyle(color: Color(0xFF7DD3FC)),
                ),
                TextSpan(
                  text: '"$value"',
                  style: TextStyle(
                    color: isPlain
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFFFCA5A5),
                  ),
                ),
              ],
            ),
          ),
          if (desc != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 1),
              child: Text(
                '// $desc',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── PIN 케이스 카드 ──────────────────────────────────────────────
class _PinCaseCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> steps;
  final String note;

  const _PinCaseCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.steps,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...steps.asMap().entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${e.key + 1}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      e.value,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF374151),
                        height: 1.5,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    note,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF92400E),
                      height: 1.5,
                      letterSpacing: -0.1,
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

// ── 기술 명세 행 ─────────────────────────────────────────────────
class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isFirst;
  final bool isLast;

  const _SpecRow({
    required this.label,
    required this.value,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
                letterSpacing: -0.1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF111827),
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
