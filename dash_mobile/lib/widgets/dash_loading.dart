import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';

/// 로고 로켓 이륙 루프 애니메이션 — 로딩 인디케이터 전용
class DashLoadingIndicator extends StatefulWidget {
  /// 위젯 크기 (로고 이미지 너비/높이)
  final double size;
  const DashLoadingIndicator({super.key, this.size = 72});

  @override
  State<DashLoadingIndicator> createState() => _DashLoadingIndicatorState();
}

class _DashLoadingIndicatorState extends State<DashLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size + 80,
      height: widget.size + 80,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;

          // 0.00~0.12: 등장 (fade+scale in)
          final appearT = (t / 0.12).clamp(0.0, 1.0);
          final appearOpacity = Curves.easeOut.transform(appearT);
          final appearScale = 0.6 + 0.4 * Curves.easeOutBack.transform(appearT.clamp(0.0, 1.0));

          // 0.12~0.75: 이륙 (ease-in 가속, 우측 상단)
          final launchT = ((t - 0.12) / 0.63).clamp(0.0, 1.0);
          final launchCurved = Curves.easeIn.transform(launchT);
          final dx = launchCurved * (widget.size * 1.1);
          final dy = launchCurved * -(widget.size * 1.4);
          final rotation = launchCurved * 0.36;

          // 0.50~0.78: 페이드아웃
          final fadeOutT = ((t - 0.50) / 0.28).clamp(0.0, 1.0);
          final fadeOut = t < 0.50 ? 1.0 : (1.0 - Curves.easeIn.transform(fadeOutT));

          // 0.78~1.0: 대기 (투명)
          final opacity = (appearOpacity * fadeOut).clamp(0.0, 1.0);
          final scale = appearScale * (1.0 - 0.25 * launchCurved);

          return Center(
            child: Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: Offset(dx, dy),
                child: Transform.rotate(
                  angle: rotation,
                  child: Transform.scale(
                    scale: scale,
                    child: Image.asset(
                      'assets/icons/logo_transparent.png',
                      width: widget.size,
                      height: widget.size,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 전체 화면 로딩 오버레이
class DashLoadingOverlay extends StatelessWidget {
  const DashLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: DashLoadingIndicator()),
    );
  }
}
