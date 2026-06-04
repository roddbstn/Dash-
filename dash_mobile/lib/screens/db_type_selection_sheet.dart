import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/analytics_service.dart';

enum DbType { personal, shared }

Future<DbType?> showDbTypeSelectionSheet(BuildContext context) {
  return showModalBottomSheet<DbType>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    builder: (ctx) => const _DbTypeSelectionSheet(),
  );
}

class _DbTypeSelectionSheet extends StatelessWidget {
  const _DbTypeSelectionSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 핸들
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'DB 유형 선택',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
          ),
          const SizedBox(height: 6),
          const Text(
            '어떤 목적으로 작성하세요?',
            style: TextStyle(fontSize: 13, color: Color(0xFF8B95A1)),
          ),
          const SizedBox(height: 20),
          _TypeCard(
            icon: Icons.person_outline_rounded,
            title: '내 DB',
            description: '나만 보는 개인 기록이에요',
            onTap: () {
              AnalyticsService.dbTypeSelected('personal');
              Navigator.pop(context, DbType.personal);
            },
          ),
          const SizedBox(height: 12),
          _TypeCard(
            icon: Icons.people_outline_rounded,
            title: '공유할 DB',
            description: '동행자로서 담당자의 DB를 대신 작성하고 공유할 수 있어요',
            accent: true,
            onTap: () {
              AnalyticsService.dbTypeSelected('shared');
              Navigator.pop(context, DbType.shared);
            },
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool accent;
  final VoidCallback onTap;

  const _TypeCard({
    required this.icon,
    required this.title,
    required this.description,
    this.accent = false,
    required this.onTap,
  });

  @override
  State<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends State<_TypeCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.accent ? AppColors.primary : const Color(0xFF4E5968);
    final bgColor = widget.accent ? AppColors.primary.withValues(alpha: 0.06) : const Color(0xFFF8F9FA);
    final pressedColor = widget.accent ? AppColors.primary.withValues(alpha: 0.12) : const Color(0xFFEEF0F2);
    final borderColor = widget.accent ? AppColors.primary.withValues(alpha: 0.3) : const Color(0xFFE9ECEF);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: _isPressed ? pressedColor : bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.accent ? AppColors.primary.withValues(alpha: 0.12) : const Color(0xFFE9ECEF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
                    const SizedBox(height: 2),
                    Text(widget.description, style: const TextStyle(fontSize: 12, color: Color(0xFF8B95A1))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.5), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
