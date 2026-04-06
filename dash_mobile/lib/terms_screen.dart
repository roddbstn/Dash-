import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

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
          '서비스 이용약관',
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

            _Section(
              number: '1',
              title: '목적',
              child: _bodyText(
                'DASH 서비스 이용약관(이하 "약관")은 DASH(이하 "서비스")를 제공하는 '
                '서비스 제공자(이하 "제공자")와 서비스를 이용하는 이용자(이하 "이용자") '
                '간의 권리·의무 및 책임사항을 규정함을 목적으로 합니다.',
              ),
            ),
            const SizedBox(height: 20),

            _Section(
              number: '2',
              title: '서비스 개요 및 이용 대상',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bodyText(
                    'DASH는 아동보호 관련 기관 소속 상담원이 상담 기록을 작성하고, '
                    '이를 기관 공식 시스템(NCADS 등)에 안전하게 전달하기 위한 '
                    '보안 전송 보조 도구입니다.',
                  ),
                  const SizedBox(height: 10),
                  _bulletText('서비스 이용 대상: 기관으로부터 승인된 상담원'),
                  _bulletText('서비스 범위: 상담 기록 작성, 암호화 전송, 검토 워크플로우'),
                  _bulletText('서비스는 공식 DB 입력 시스템을 대체하지 않으며, 보조 전송 도구로서만 기능합니다.'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _Section(
              number: '3',
              title: '이용자 의무',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bodyText('이용자는 서비스를 이용함에 있어 다음 사항을 준수하여야 합니다.'),
                  const SizedBox(height: 10),
                  _bulletText('계정 및 접속 정보를 타인에게 양도·대여하거나 공유하지 않을 것'),
                  _bulletText('서비스를 통해 처리한 아동 관련 정보를 업무 목적 외 용도로 활용하지 않을 것'),
                  _bulletText('서비스를 통해 취득한 정보를 기관 외부에 유출하지 않을 것'),
                  _bulletText('관계 법령(아동복지법, 개인정보보호법 등)을 준수할 것'),
                  _bulletText('서비스의 정상적인 운영을 방해하는 행위를 하지 않을 것'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _Section(
              number: '4',
              title: '제공자의 의무',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bulletText('서비스 내 전송 데이터를 종단간 암호화(E2EE)로 보호합니다.'),
                  _bulletText('시스템 전송 완료 후 서버의 상담 데이터를 즉시 삭제합니다.'),
                  _bulletText('서비스 장애 발생 시 신속하게 복구하기 위해 노력합니다.'),
                  _bulletText('이용자의 개인정보를 개인정보처리방침에 따라 처리합니다.'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _Section(
              number: '5',
              title: '서비스 변경 및 중단',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bodyText(
                    '제공자는 서비스의 내용, 기능, 이용 방법 등을 변경할 수 있으며, '
                    '변경 사항은 서비스 내 공지 또는 앱 업데이트를 통해 사전 안내합니다.',
                  ),
                  const SizedBox(height: 8),
                  _bodyText(
                    '다음의 경우 사전 통지 없이 서비스를 일시 중단하거나 종료할 수 있습니다.',
                  ),
                  const SizedBox(height: 8),
                  _bulletText('시스템 점검, 교체, 고장 등 기술적 사유가 있는 경우'),
                  _bulletText('천재지변, 국가 비상사태 등 불가항력적 사유가 있는 경우'),
                  _bulletText('서비스의 유지가 더 이상 어렵다고 판단되는 경우'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _Section(
              number: '6',
              title: '면책 조항',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bulletText(
                    '이용자가 서비스를 이용하여 기대하는 결과를 얻지 못한 것에 대해 '
                    '제공자는 책임을 지지 않습니다.',
                  ),
                  _bulletText(
                    '이용자의 귀책 사유로 인한 서비스 이용 장애에 대해 제공자는 책임을 지지 않습니다.',
                  ),
                  _bulletText(
                    '이용자가 이 약관을 위반하여 발생한 손해에 대해 제공자는 책임을 지지 않습니다.',
                  ),
                  _bulletText(
                    '서비스는 공식 기관 시스템의 운영에 관여하지 않으며, '
                    '공식 시스템 오류로 인한 손해에 대해 책임을 지지 않습니다.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _Section(
              number: '7',
              title: '약관의 변경',
              child: _bodyText(
                '제공자는 관련 법령을 위반하지 않는 범위에서 이 약관을 변경할 수 있습니다. '
                '약관 변경 시 시행일 7일 전에 앱 내 공지를 통해 안내합니다. '
                '변경 후에도 서비스를 계속 이용하면 변경된 약관에 동의한 것으로 간주합니다.',
              ),
            ),
            const SizedBox(height: 20),

            _Section(
              number: '8',
              title: '분쟁 해결',
              child: _bodyText(
                '서비스 이용 관련 분쟁은 제공자와 이용자 간 상호 협의하여 해결하는 것을 원칙으로 합니다. '
                '협의가 이루어지지 않을 경우 관련 법령에 따라 처리합니다.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaInfo(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF8E8E93),
          letterSpacing: -0.1,
        ),
      );

  Widget _bodyText(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF444444),
          height: 1.65,
          letterSpacing: -0.1,
        ),
      );

  Widget _bulletText(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '∙  ',
              style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
            ),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF444444),
                  height: 1.55,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      );
}

// ── 공통 섹션 위젯 ──────────────────────────────────────────────────────────
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
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: child,
        ),
      ],
    );
  }
}
