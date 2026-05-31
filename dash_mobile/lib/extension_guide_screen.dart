import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';
import 'package:url_launcher/url_launcher.dart';

class ExtensionGuideScreen extends StatelessWidget {
  const ExtensionGuideScreen({super.key});

  static const _chromeStoreUrl =
      'https://chromewebstore.google.com/detail/dpncpmegjlgknkagcfjdaccbgmjncdef?utm_source=item-share-cb';

  Future<void> _openStore(BuildContext context) async {
    final uri = Uri.parse(_chromeStoreUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('링크를 열 수 없어요.')),
        );
      }
    }
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
          '확장프로그램',
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
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DASH 확장프로그램',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'PC 브라우저에 설치하면\n저장한 DB가 1초만에 자동입력돼요.',
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
                  const SizedBox(width: 12),
                  _TwoIconsDecoration(),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Chrome 설치 방법
            _InstallCard(
              browser: 'Chrome',
              icon: const Icon(Icons.extension, size: 18, color: Color(0xFF1A56DB)),
              steps: const [
                'PC에서 Chrome 브라우저를 열어주세요.',
                '아래 버튼을 눌러 Chrome 웹 스토어로 이동하세요.',
                '\'Chrome에 추가\' 버튼을 눌러 설치하세요.',
                '설치 후 확장프로그램 아이콘을 클릭하고\n같은 계정으로 로그인하세요.',
              ],
              actionLabel: 'Chrome 웹 스토어에서 설치하기',
              onAction: () => _openStore(context),
            ),
            const SizedBox(height: 12),

            // Edge 설치 방법
            _InstallCard(
              browser: 'Edge',
              icon: Image.asset('assets/images/edge_logo.png', width: 18, height: 18),
              steps: const [
                'PC에서 Edge 브라우저를 열어주세요.',
                '브라우저 오른쪽 상단 ··· 버튼을 클릭하세요.',
                '확장 → 확장 관리를 선택하세요.',
                '\'Chrome 웹 스토어\' 클릭 후 "DASH" 검색하세요.',
                '\'Chrome에 추가\' 버튼을 눌러 설치하세요.',
                '설치 후 확장프로그램 아이콘을 클릭하고\n같은 계정으로 로그인하세요.',
              ],
              actionLabel: 'Chrome 웹 스토어에서 설치하기',
              onAction: () => _openStore(context),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── 두 아이콘 겹침 장식 ────────────────────────────────────────────
class _TwoIconsDecoration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // DASH 로고 (뒤)
          Positioned(
            left: 0,
            top: 4,
            child: Opacity(
              opacity: 0.32,
              child: Transform.rotate(
                angle: 30 * pi / 180,
                child: Image.asset(
                  'assets/icons/logo_transparent.png',
                  width: 34,
                  height: 34,
                ),
              ),
            ),
          ),
          // 확장프로그램 아이콘 (앞)
          Positioned(
            right: 0,
            bottom: 4,
            child: Opacity(
              opacity: 0.32,
              child: Transform.rotate(
                angle: 30 * pi / 180,
                child: const Icon(
                  Icons.extension,
                  size: 34,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 설치 방법 카드 ────────────────────────────────────────────────
class _InstallCard extends StatelessWidget {
  final String browser;
  final Widget icon;
  final List<String> steps;
  final String actionLabel;
  final VoidCallback onAction;

  const _InstallCard({
    required this.browser,
    required this.icon,
    required this.steps,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 브라우저 헤더
          Row(
            children: [
              icon,
              const SizedBox(width: 8),
              Text(
                '$browser 브라우저',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF222222),
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 스텝 목록
          ...steps.asMap().entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${e.key + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.value,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF4E5968),
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 액션 버튼
          GestureDetector(
            onTap: onAction,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                actionLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
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
