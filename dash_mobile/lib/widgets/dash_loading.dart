
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

  /// t 시각의 이륙 진행도(0~1)와 world 좌표 반환
  ({double curved, double dx, double dy}) _launchAt(double t) {
    final launchT = ((t - 0.12) / 0.63).clamp(0.0, 1.0);
    final curved = Curves.easeIn.transform(launchT);
    return (
      curved: curved,
      dx: curved * (widget.size * 1.1),
      dy: curved * -(widget.size * 1.4),
    );
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

          // ── 등장 (0.00~0.12) ────────────────────────────────────
          final appearT = (t / 0.12).clamp(0.0, 1.0);
          final appearOpacity = Curves.easeOut.transform(appearT);
          final appearScale =
              0.6 + 0.4 * Curves.easeOutBack.transform(appearT.clamp(0.0, 1.0));

          // ── 이륙 (0.12~0.75) ────────────────────────────────────
          final main = _launchAt(t);
          final rotation = main.curved * 0.36;

          // ── 페이드아웃 (0.50~0.78) ──────────────────────────────
          final fadeOutT = ((t - 0.50) / 0.28).clamp(0.0, 1.0);
          final fadeOut =
              t < 0.50 ? 1.0 : (1.0 - Curves.easeIn.transform(fadeOutT));

          final opacity = (appearOpacity * fadeOut).clamp(0.0, 1.0);
          final scale = appearScale * (1.0 - 0.25 * main.curved);

          final isFlying = t > 0.14 && t < 0.75;

          // ── 트레일 파티클 (3개, 시간 지연된 이전 위치) ──────────
          final trailItems = <({double dx, double dy, double opacity, double sz})>[];
          for (int i = 1; i <= 3; i++) {
            final tPast = (t - i * 0.055).clamp(0.0, 1.0);
            final past = _launchAt(tPast);
            final hasPastLaunched = tPast > 0.12 && past.curved > 0.01;
            final trailOpacity = (hasPastLaunched && isFlying)
                ? (fadeOut * (0.55 - (i - 1) * 0.15)).clamp(0.0, 1.0)
                : 0.0;
            final trailSz = widget.size * (0.14 - (i - 1) * 0.03);
            trailItems.add((
              dx: past.dx,
              dy: past.dy,
              opacity: trailOpacity,
              sz: trailSz,
            ));
          }

          return Stack(
            alignment: Alignment.center,
            children: [
              // ── 트레일 파티클 (가장 먼 것부터) ──────────────────
              for (final tr in trailItems.reversed)
                Opacity(
                  opacity: tr.opacity,
                  child: Transform.translate(
                    offset: Offset(tr.dx, tr.dy),
                    child: Container(
                      width: tr.sz,
                      height: tr.sz,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),

              // ── 메인 로켓 ────────────────────────────────────────
              Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: Offset(main.dx, main.dy),
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
            ],
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
