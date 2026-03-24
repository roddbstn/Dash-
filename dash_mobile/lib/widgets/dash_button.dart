import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';

class DashButton extends StatefulWidget {
  final VoidCallback? onTap;
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final double borderRadius;
  final EdgeInsets padding;
  final double? width;
  final double height;
  final Widget? icon;

  const DashButton({
    super.key,
    required this.onTap,
    required this.text,
    this.backgroundColor = AppColors.primary,
    this.textColor = Colors.white,
    this.borderRadius = 16,
    this.padding = const EdgeInsets.symmetric(vertical: 18),
    this.width = double.infinity,
    this.height = 56,
    this.icon,
  });

  @override
  State<DashButton> createState() => _DashButtonState();
}

class _DashButtonState extends State<DashButton> with SingleTickerProviderStateMixin {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
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
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.onTap == null 
                ? const Color(0xFFDBE0E5)
                : (_isPressed 
                    ? Color.lerp(widget.backgroundColor, Colors.black, 0.1) 
                    : widget.backgroundColor),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: (_isPressed || widget.onTap == null) ? [] : [
              BoxShadow(
                color: widget.backgroundColor.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),

          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  widget.icon!,
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: widget.textColor,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
