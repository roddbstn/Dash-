import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '개인정보처리방침',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF222222),
            letterSpacing: -0.4,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _metaInfo('시행일자: 2026년 4월 2일'),
            const SizedBox(height: 20),

            _intro(),
            const SizedBox(height: 28),

            // 0. DASH 서비스의 개인정보 처리 원칙
            _Section(
              number: '0',
              title: 'DASH 서비스의 개인정보 처리 원칙',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlightBox(
                    '🔒 DASH 서버는 상담 내용을 볼 수 없습니다.\n\n'
                    '상담원이 모바일에 내용을 입력하면, 전송 전에 자물쇠가 채워집니다. '
                    '이것을 암호화라고 합니다. 암호화된 내용은 알아볼 수 없는 문자 덩어리가 되어 '
                    '서버로 이동합니다. 자물쇠를 여는 것은 복호화라고 하는데, 열쇠는 오직 '
                    '상담원 본인의 PC 확장 프로그램에만 있습니다. '
                    'DASH는 열쇠를 갖고 있지 않기 때문에 내용을 볼 수 없습니다.\n\n'
                    '— 사용 기술 안내 —\n'
                    '∙ AES-256: 미국 정부·금융기관·군에서 사용하는 암호화 방식입니다. '
                    '현재 기술로는 풀 수 없다고 알려져 있습니다.\n'
                    '∙ 종단간 암호화(E2EE): 보내는 기기에서 잠기고, 받는 기기에서만 열리는 방식입니다. '
                    '카카오톡 비밀채팅에 적용된 것과 같은 원리입니다.\n'
                    '∙ PIN 잠금 보관함: 열쇠 자체도 상담원이 설정한 PIN 번호로 한 번 더 잠겨 있어 '
                    '기기를 분실해도 내용이 보호됩니다.\n\n'
                    '∙ 모바일 입력 → 암호화(자물쇠) → 서버 경유 → 본인 PC에서만 잠금 해제 → 공식 시스템 입력\n'
                    '∙ 아동 이름은 중간 글자만 가려서(예: 김O재) 저장됩니다.\n'
                    '∙ 아동 정보는 오직 기관 공식 시스템에만 최종 저장됩니다.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 1. 수집 항목 및 목적
            _Section(
              number: '1',
              title: '개인정보 처리 항목 및 목적',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bodyText(
                    '서비스는 다음의 목적으로 개인정보를 처리합니다. '
                    '처리한 개인정보는 다음의 목적 이외의 용도로 사용되지 않습니다.',
                  ),
                  const SizedBox(height: 12),
                  _table(
                    headers: ['구분', '처리 항목', '처리 목적'],
                    rows: [
                      ['필수', '이름(닉네임), 이메일', '본인 확인, 서비스 제공'],
                      ['필수', '앱 사용 기록', '서비스 품질 향상'],
                      ['업무용\n임시처리', '상담 기록, 사례 정보\n(암호화 상태, 전송 후 삭제)', '공식 시스템 자동 입력 보조'],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2. 보유기간 및 파기 정책
            _Section(
              number: '2',
              title: '개인정보 보유기간 및 파기 정책',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bodyText('처리된 개인정보는 목적 달성 후 아래 기준에 따라 파기됩니다.'),
                  const SizedBox(height: 12),
                  _table(
                    headers: ['구분', '보유기간', '근거 법령'],
                    rows: [
                      ['일반 개인정보\n(이름, 이메일)', '회원 탈퇴 후 즉시 파기', '-'],
                      [
                        '상담 기록\n(service_drafts)',
                        '생성일로부터 5년\n→ 이후 자동 파기',
                        '아동복지법 제28조',
                      ],
                      ['로그인 기록', '1년', '통신비밀보호법'],
                      ['결제 기록\n(해당 시)', '5년', '전자상거래 소비자보호법'],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _highlightBox(
                    '📌 자동 파기 정책\n'
                    '법정 보존기간이 경과된 상담 기록은 매일 새벽 2시에 자동으로 파기됩니다. '
                    '파기 이력은 retention_policy_log 테이블에 기록되어 관리됩니다.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 3. 민감정보 처리
            _Section(
              number: '3',
              title: '민감정보 임시 처리',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bodyText(
                    '개인정보보호법 제23조에 따라 아동학대 상담 기록은 민감정보로 분류됩니다. '
                    'DASH는 이를 공식 시스템 자동 입력 목적으로만 임시 처리하며, '
                    '이용자(상담원)의 별도 동의를 받아 처리합니다.',
                  ),
                  const SizedBox(height: 8),
                  _bodyText(
                    '∙ 상담 내용은 기기에서 자물쇠가 채워진 뒤(암호화, AES-256) 서버로 전송됩니다.\n'
                    '  → 서버에는 잠긴 내용만 있어 DASH는 내용을 볼 수 없습니다.\n'
                    '  → 잠금을 풀 수 있는 열쇠(복호화 키)는 상담원 본인의 PC에만 있습니다.\n'
                    '∙ 기입 완료된 기록은 앱에서 즉시 삭제 처리됩니다.\n'
                    '∙ 미완료 기록은 아동복지법 제28조에 따라 최대 5년 보존 후 자동 파기됩니다.\n'
                    '∙ 업무 목적 외 제3자에게 제공되지 않습니다.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4. 처리위탁
            _Section(
              number: '4',
              title: '개인정보 처리위탁',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bodyText(
                    '서비스는 원활한 서비스 제공을 위해 아래와 같이 개인정보 처리 업무를 위탁하고 있습니다.',
                  ),
                  const SizedBox(height: 12),
                  _table(
                    headers: ['수탁업체', '위탁 업무 내용', '보유 및 이용기간'],
                    rows: [
                      [
                        'Google LLC\n(Firebase Auth)',
                        '이용자 인증 처리\n(Google 로그인)',
                        '위탁 계약 종료 시까지',
                      ],
                      [
                        'Google LLC\n(Firebase Cloud Messaging)',
                        '앱 푸시 알림 발송',
                        '위탁 계약 종료 시까지',
                      ],
                      [
                        'Railway\n(Cloudflare 인프라)',
                        '서버 및 데이터베이스 호스팅',
                        '위탁 계약 종료 시까지',
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  _bodyText(
                    '위탁업체가 처리하는 개인정보는 위탁 목적 범위 내에서만 이용되며, '
                    '개인정보보호법 제26조에 따라 수탁자를 교육·관리하고 있습니다.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 5. 정보주체 권리
            _Section(
              number: '5',
              title: '정보주체의 권리·의무 및 행사 방법',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bodyText('이용자는 언제든지 아래의 권리를 행사할 수 있습니다.'),
                  const SizedBox(height: 8),
                  _bodyText(
                    '∙ 개인정보 열람 요청 (처리 10일 이내)\n'
                    '∙ 오류 정정 요청\n'
                    '∙ 삭제 요청 (법정 보존기간 해당 시 제외)\n'
                    '∙ 처리 정지 요청',
                  ),
                  const SizedBox(height: 8),
                  _bodyText(
                    '권리 행사는 앱 내 [설정 → 내 데이터 관리] 또는 아래 개인정보 보호책임자 이메일로 신청하실 수 있습니다.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 6. 안전성 확보 조치
            _Section(
              number: '6',
              title: '개인정보 안전성 확보 조치',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bodyText('서비스는 개인정보보호법 제29조에 따라 다음과 같이 안전성 확보 조치를 시행합니다.'),
                  const SizedBox(height: 8),
                  _bodyText(
                    '∙ 종단간 암호화(E2EE): 민감 상담 기록 암호화 저장·전송\n'
                    '∙ 전송구간 암호화: TLS/HTTPS 통신 적용\n'
                    '∙ RSA 공개키 기반 키 분리 보관(user_key_vault)\n'
                    '∙ 접근 권한 최소화: 서비스 담당자만 접근 허용\n'
                    '∙ 정기적 보안 점검',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 7. 개인정보 보호책임자
            _Section(
              number: '7',
              title: '개인정보 보호책임자(CPO)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bodyText(
                    '이용자의 개인정보 관련 문의·불만 처리 및 피해 구제 등을 위해 '
                    '아래와 같이 개인정보 보호책임자를 지정하고 있습니다.',
                  ),
                  const SizedBox(height: 12),
                  _cpoCard(),
                  const SizedBox(height: 10),
                  _bodyText(
                    '개인정보 침해 신고는 개인정보 침해신고센터(privacy.kisa.or.kr)에도 신청하실 수 있습니다.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 8. 고지 의무
            _Section(
              number: '8',
              title: '개인정보처리방침 변경 고지',
              child: _bodyText(
                '본 개인정보처리방침은 법령·정책 변경 및 서비스 내용에 따라 변경될 수 있습니다. '
                '변경 시 앱 내 공지사항 또는 이메일을 통해 사전 고지합니다.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaInfo(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: Color(0xFF9CA3AF),
        letterSpacing: -0.1,
      ),
    );
  }

  Widget _intro() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'DASH(이하 "서비스")는 이용자의 개인정보를 소중히 여기며, '
        '「개인정보 보호법」을 준수합니다. 본 방침은 서비스가 어떤 개인정보를 '
        '수집하고, 어떻게 이용하며, 언제 파기하는지에 대해 안내합니다.',
        style: TextStyle(
          fontSize: 13,
          color: AppColors.primary,
          height: 1.6,
          letterSpacing: -0.2,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _bodyText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        color: Color(0xFF374151),
        height: 1.7,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _highlightBox(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF166534),
          height: 1.6,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Table(
        border: TableBorder.all(
          color: const Color(0xFFE5E7EB),
          width: 1,
          borderRadius: BorderRadius.circular(8),
        ),
        columnWidths: const {
          0: FlexColumnWidth(1.2),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(1.8),
        },
        children: [
          // 헤더
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF9FAFB)),
            children: headers
                .map(
                  (h) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Text(
                      h,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF374151),
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          // 데이터 행
          ...rows.map(
            (row) => TableRow(
              children: row
                  .map(
                    (cell) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Text(
                        cell,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                          height: 1.5,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cpoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cpoRow('성명', '강윤수'),
          const SizedBox(height: 6),
          _cpoRow('직책', '대표'),
          const SizedBox(height: 6),
          _cpoRow('이메일', 'yunsooga@gmail.com'),
          const SizedBox(height: 6),
          _cpoRow('전화번호', '010-4871-3893'),
        ],
      ),
    );
  }

  Widget _cpoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ),
      ],
    );
  }
}

// ── 섹션 위젯 ─────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final String number;
  final String title;
  final Widget child;

  const _Section({
    required this.number,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  number,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Padding(padding: const EdgeInsets.only(left: 4), child: child),
      ],
    );
  }
}
