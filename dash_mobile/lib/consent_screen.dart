import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/privacy_policy_screen.dart';
import 'package:dash_mobile/terms_screen.dart';
import 'package:dash_mobile/security_detail_screen.dart';
import 'package:dash_mobile/analytics_service.dart';
import 'package:dash_mobile/nickname_screen.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  // 필수
  bool _consentPrivacy = false;
  bool _consentTerms = false;
  // 선택
  bool _consentMarketing = false;
  // 민감정보 (별도 필수)
  bool _consentSensitive = false;

  // 상세 펼침 상태
  bool _expandPrivacy = false;
  bool _expandTerms = false;
  bool _expandMarketing = false;
  bool _expandSensitive = false;

  bool get _allRequired =>
      _consentPrivacy && _consentTerms && _consentSensitive;

  bool get _allChecked =>
      _consentPrivacy && _consentTerms && _consentMarketing && _consentSensitive;

  void _toggleAll(bool value) {
    AnalyticsService.consentAllToggled(value);
    setState(() {
      _consentPrivacy = value;
      _consentTerms = value;
      _consentMarketing = value;
      _consentSensitive = value;
    });
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenConsent();
  }

  Future<void> _proceed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('consent_v1_completed', true);
    await prefs.setBool('consent_marketing', _consentMarketing);
    AnalyticsService.consentComplete(marketingAgreed: _consentMarketing);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NicknameScreen()),
      );
    }
  }

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
          '서비스 이용 동의',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF222222),
            letterSpacing: -0.4,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 전체 동의 카드 ──
                  _AllAgreeCard(
                    allChecked: _allChecked,
                    onChanged: _toggleAll,
                  ),
                  const SizedBox(height: 28),

                  // ── 섹션 1: 필수 동의 ──
                  _sectionLabel('필수 동의'),
                  const SizedBox(height: 10),
                  _ConsentTile(
                    title: '개인정보 수집·이용 동의',
                    badge: '필수',
                    badgeColor: AppColors.primary,
                    checked: _consentPrivacy,
                    expanded: _expandPrivacy,
                    onToggle: (v) {
                      AnalyticsService.consentCheckboxToggled('privacy', v);
                      setState(() => _consentPrivacy = v);
                    },
                    onExpand: () {
                      AnalyticsService.consentDropdownToggled('privacy', !_expandPrivacy);
                      setState(() => _expandPrivacy = !_expandPrivacy);
                    },
                    detail: '∙ 수집 항목: 이름(닉네임), 이메일 주소, 앱 사용 기록\n'
                        '∙ 수집 목적: 서비스 제공, 본인 확인, 상담 기록 관리\n'
                        '∙ 보유 기간: 회원 탈퇴 후 즉시 파기\n'
                        '  (단, 관계 법령에 따른 보존 기간 별도 적용)',
                    onViewFull: () {
                      AnalyticsService.consentFullDocViewed('privacy_policy');
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
                    },
                  ),
                  const SizedBox(height: 8),
                  _ConsentTile(
                    title: '서비스 이용약관 동의',
                    badge: '필수',
                    badgeColor: AppColors.primary,
                    checked: _consentTerms,
                    expanded: _expandTerms,
                    onToggle: (v) {
                      AnalyticsService.consentCheckboxToggled('terms', v);
                      setState(() => _consentTerms = v);
                    },
                    onExpand: () {
                      AnalyticsService.consentDropdownToggled('terms', !_expandTerms);
                      setState(() => _expandTerms = !_expandTerms);
                    },
                    detail: 'DASH 서비스 이용에 관한 이용자와 서비스 제공자의 권리·의무 및 '
                        '책임사항을 규정합니다. 서비스를 이용하시려면 본 약관에 동의하셔야 합니다.',
                    onViewFull: () {
                      AnalyticsService.consentFullDocViewed('terms');
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsScreen()));
                    },
                  ),
                  const SizedBox(height: 28),

                  // ── 섹션 2: 선택 동의 ──
                  _sectionLabel('선택 동의'),
                  const SizedBox(height: 10),
                  _ConsentTile(
                    title: '마케팅 정보 수신 동의',
                    badge: '선택',
                    badgeColor: const Color(0xFF8E8E93),
                    checked: _consentMarketing,
                    expanded: _expandMarketing,
                    onToggle: (v) {
                      AnalyticsService.consentCheckboxToggled('marketing', v);
                      setState(() => _consentMarketing = v);
                    },
                    onExpand: () {
                      AnalyticsService.consentDropdownToggled('marketing', !_expandMarketing);
                      setState(() => _expandMarketing = !_expandMarketing);
                    },
                    detail: '∙ 서비스 업데이트·기능 안내를 이메일·앱 알림으로 받습니다.\n'
                        '∙ 동의하지 않아도 서비스 이용에 제한이 없습니다.\n'
                        '∙ 수신 동의 후 설정 화면에서 언제든 철회 가능합니다.',
                  ),
                  const SizedBox(height: 28),

                  // ── 섹션 3: 민감정보 동의 ──
                  _sectionLabel('민감정보 처리 동의'),
                  const SizedBox(height: 6),
                  // ── 보안 안내 박스 ──────────────────────────────
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Text('🔒', style: TextStyle(fontSize: 13)),
                            SizedBox(width: 6),
                            Text(
                              'DASH는 구조적으로 내용을 볼 수 없습니다',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1D4ED8),
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                              height: 1.55,
                              letterSpacing: -0.1,
                            ),
                            children: const [
                              TextSpan(text: '입력하신 내용은 기기를 떠나기 전에 암호화됩니다. '),
                              TextSpan(
                                text: '암호 열쇠는 상담원님의 기기에서만 생성되며, DASH 서버에는 전달되지 않습니다.',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(text: ' 열쇠 없이는 DASH 운영진을 포함해 누구도 내용을 열어볼 수 없습니다.\n'),
                              TextSpan(text: 'DASH는 처음 설계 단계부터 운영진도 데이터에 접근할 수 없는 구조를 지향했습니다. 카카오 비밀채팅, 네이버 MYBOX 보안 폴더 등 국내 주요 서비스에서도 채택한 종단간 암호화(E2EE) 방식과 동일한 원리입니다.'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () {
                              AnalyticsService.consentFullDocViewed('security_detail');
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityDetailScreen()));
                            },
                            child: const Text(
                              '→ 암호화 구조 자세히 보기',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2563EB),
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ConsentTile(
                    title: '업무용 상담 기록 임시 처리 동의',
                    badge: '필수',
                    badgeColor: const Color(0xFFFF6B35),
                    checked: _consentSensitive,
                    expanded: _expandSensitive,
                    onToggle: (v) {
                      AnalyticsService.consentCheckboxToggled('sensitive', v);
                      setState(() => _consentSensitive = v);
                    },
                    onExpand: () {
                      AnalyticsService.consentDropdownToggled('sensitive', !_expandSensitive);
                      setState(() => _expandSensitive = !_expandSensitive);
                    },
                    detail: '∙ 처리 내용: 상담 기록, 사례 정보를 공식 시스템 입력을 위해 임시 처리\n'
                        '∙ 처리 목적: 모바일 앱 및 크롬·엣지·웨일 브라우저 확장프로그램 연계를 통한 아동학대정보시스템(NCADS) 서비스 제공 DB 자동 기입 업무 보조\n'
                        '∙ 보관 기간: DASH 서버의 암호문은 회원 탈퇴 전까지 보존\n'
                        '  (암호문은 서버에서 확인 불가)\n'
                        '  미사용 계정은 최대 5년 후 자동 파기 (아동복지법 제28조)\n'
                        '∙ 기기 내 데이터는 AES-256 암호화 후 전송되며,\n'
                        '  서버에서는 복호화가 불가능합니다 (종단간 암호화, E2EE).',
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          // ── 하단 버튼 ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_allRequired)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '필수 항목과 민감정보 동의를 모두 체크해 주세요.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSub,
                        letterSpacing: -0.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _allRequired ? _proceed : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: const Color(0xFFE5E8EB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      '동의하고 시작하기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _allRequired
                            ? Colors.white
                            : const Color(0xFFAAAAAA),
                        letterSpacing: -0.3,
                      ),
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

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF8E8E93),
        letterSpacing: 0.2,
      ),
    );
  }
}

// ── 전체 동의 카드 ──────────────────────────────────────────────
class _AllAgreeCard extends StatelessWidget {
  final bool allChecked;
  final ValueChanged<bool> onChanged;

  const _AllAgreeCard({required this.allChecked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!allChecked),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: allChecked
              ? AppColors.primaryLight
              : const Color(0xFFF7F8F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: allChecked ? AppColors.primary : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: allChecked ? AppColors.primary : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      allChecked ? AppColors.primary : const Color(0xFFCDD1D5),
                  width: 2,
                ),
              ),
              child: allChecked
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '전체 동의',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF222222),
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 개별 동의 항목 타일 ──────────────────────────────────────────
class _ConsentTile extends StatelessWidget {
  final String title;
  final String badge;
  final Color badgeColor;
  final bool checked;
  final bool expanded;
  final ValueChanged<bool> onToggle;
  final VoidCallback onExpand;
  final String detail;
  final VoidCallback? onViewFull;

  const _ConsentTile({
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.checked,
    required this.expanded,
    required this.onToggle,
    required this.onExpand,
    required this.detail,
    this.onViewFull,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: checked ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // 메인 행
          InkWell(
            onTap: () => onToggle(!checked),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
              child: Row(
                children: [
                  // 체크박스
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: checked ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: checked
                            ? AppColors.primary
                            : const Color(0xFFCDD1D5),
                        width: 1.5,
                      ),
                    ),
                    child: checked
                        ? const Icon(Icons.check, color: Colors.white, size: 13)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  // 배지
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  // 제목
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF222222),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  // 상세 펼침 버튼
                  IconButton(
                    onPressed: onExpand,
                    icon: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color(0xFF8E8E93),
                        size: 20,
                      ),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 상세 내용
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: AnimatedOpacity(
                opacity: expanded ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: expanded
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(44, 0, 14, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                                height: 1.7,
                                letterSpacing: -0.1,
                              ),
                            ),
                            if (onViewFull != null) ...[
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: onViewFull,
                                child: const Text(
                                  '전문 보기 →',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2563EB),
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
