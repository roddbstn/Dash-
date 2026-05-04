import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class PressableCaseCard extends StatefulWidget {
  final Map<String, dynamic> caseData;
  final bool isSelected;
  final int sIndex;
  final bool isSelectionMode;
  final VoidCallback onTap;

  const PressableCaseCard({
    super.key,
    required this.caseData,
    required this.isSelected,
    required this.sIndex,
    required this.isSelectionMode,
    required this.onTap,
  });

  @override
  State<PressableCaseCard> createState() => _PressableCaseCardState();
}

class _PressableCaseCardState extends State<PressableCaseCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: _isPressed ? const Color(0xFFF2F4F6) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: widget.isSelected
                ? Border.all(color: AppColors.primary, width: 2)
                : Border.all(color: Colors.black.withValues(alpha: 0.05)),
            boxShadow: _isPressed
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.caseData['maskedName'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.caseData['dong'],
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSub.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isSelectionMode)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isSelected ? AppColors.primary : Colors.white,
                      border: Border.all(
                        color: widget.isSelected ? AppColors.primary : AppColors.border,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        widget.isSelected ? '${widget.sIndex}' : '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


class SwipeableDraftCard extends StatefulWidget {
  final dynamic d;
  final VoidCallback onTap;
  final Future<bool> Function() onDelete;
  final int index;
  final bool isLast;

  const SwipeableDraftCard({
    super.key,
    required this.d,
    required this.onTap,
    required this.onDelete,
    this.index = 0,
    this.isLast = true,
  });

  @override
  State<SwipeableDraftCard> createState() => _SwipeableDraftCardState();
}

class _SwipeableDraftCardState extends State<SwipeableDraftCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0;
  static const double _maxSwipe = 90.0;
  bool _isCardPressed = false;
  bool _isSharePressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(
      begin: 0,
      end: -_maxSwipe,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copyShareLink() async {
    String? token = widget.d['share_token']?.toString();
    String? key = widget.d['encryption_key']?.toString();

    if (token == null || token.isEmpty) {
      final caseName = widget.d['caseName']?.toString() ?? '';
      try {
        final records = await ApiService.fetchRecords();
        if (records != null) {
          final match = records.firstWhere(
            (r) => r['case_name']?.toString() == caseName && (r['share_token']?.toString() ?? '').isNotEmpty,
            orElse: () => null,
          );
          if (match != null) {
            token = match['share_token']?.toString();
            key ??= match['encryption_key']?.toString();
          }
        }
      } catch (_) {}
    }

    if (token != null && token.isNotEmpty) {
      if ((key == null || key.isEmpty) && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('주의', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            content: const Text(
              '이 레코드의 암호화 키를 찾을 수 없어\n서비스 내용·상담원 소견이 리뷰어 화면에 표시되지 않을 수 있습니다.\n\n앱을 재설치했거나 다른 기기에서 생성된 경우 발생합니다.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('그래도 공유', style: TextStyle(color: AppColors.primary))),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      final host = ApiService.serverUrl;
      final keyParam = (key != null && key.isNotEmpty) ? '&key=$key' : '';
      await Clipboard.setData(ClipboardData(text: '$host/?token=$token$keyParam'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('링크가 복사되었습니다.', textAlign: TextAlign.center),
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('저장 후 공유할 수 있어요.', textAlign: TextAlign.center),
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta!;
      if (_dragOffset > 0) _dragOffset = 0;
      if (_dragOffset < -_maxSwipe * 1.2) _dragOffset = -_maxSwipe * 1.2;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) async {
    if (_dragOffset < -_maxSwipe * 0.7) {
      _controller.forward(from: _dragOffset / -_maxSwipe);
      _dragOffset = -_maxSwipe;
      final confirmed = await widget.onDelete();
      if (!confirmed && mounted) {
        _controller.reverse();
        setState(() => _dragOffset = 0);
      }
    } else if (_dragOffset < -_maxSwipe / 3) {
      _controller.forward(from: _dragOffset / -_maxSwipe);
      _dragOffset = -_maxSwipe;
    } else {
      _controller.reverse(from: _dragOffset / -_maxSwipe);
      _dragOffset = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final offset = _controller.isAnimating ? _animation.value : _dragOffset;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _isCardPressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOutCubic,
              child: Stack(
                children: [
                  // 삭제 배경
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () async {
                            final confirmed = await widget.onDelete();
                            if (!confirmed && mounted) {
                              _controller.reverse();
                              setState(() => _dragOffset = 0);
                            }
                          },
                          child: Container(
                            width: _maxSwipe,
                            height: double.infinity,
                            alignment: Alignment.center,
                            child: const Icon(Icons.delete, color: Colors.white, size: 30),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 카드 본체
                  Transform.translate(
                    offset: Offset(offset, 0),
                    child: GestureDetector(
                      onHorizontalDragUpdate: _onHorizontalDragUpdate,
                      onHorizontalDragEnd: _onHorizontalDragEnd,
                      onTapDown: (_) => setState(() => _isCardPressed = true),
                      onTapUp: (_) => setState(() => _isCardPressed = false),
                      onTapCancel: () => setState(() => _isCardPressed = false),
                      onTap: widget.onTap,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _isCardPressed ? const Color(0xFFF2F4F6) : Colors.white,
                          borderRadius: BorderRadius.zero,
                          border: const Border(),
                        ),
                        child: Builder(builder: (context) {
                          final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

                          // 대상 텍스트
                          final targets = widget.d['target'].toString().split(', ');
                          final String targetText = targets.length > 1
                              ? '${targets[0]} 외 ${targets.length - 1}'
                              : widget.d['target'].toString();
                          final String subLine1 = '대상: $targetText | ${widget.d['method'] ?? '방문'}';

                          // 제공일시 텍스트
                          final startStr = widget.d['startTime'];
                          final endStr = widget.d['endTime'];
                          String subLine2;
                          if (startStr == null || endStr == null) {
                            subLine2 = widget.d['datetime'] ?? '제공일시 미설정';
                          } else {
                            final start = DateTime.tryParse(startStr);
                            final end = DateTime.tryParse(endStr);
                            if (start == null || end == null) {
                              subLine2 = widget.d['datetime'] ?? '제공일시 미설정';
                            } else {
                              final bool isSameDay = start.year == end.year &&
                                  start.month == end.month &&
                                  start.day == end.day;
                              final days = ['월', '화', '수', '목', '금', '토', '일'];
                              final String startFmt =
                                  '${start.month}.${start.day} (${days[start.weekday - 1]}) ${DateFormat('HH:mm').format(start)}';
                              if (isSameDay) {
                                subLine2 = '$startFmt ~ ${DateFormat('HH:mm').format(end)}';
                              } else {
                                final String endFmt =
                                    '${end.month}.${end.day} (${days[end.weekday - 1]}) ${DateFormat('HH:mm').format(end)}';
                                subLine2 = '$startFmt ~ $endFmt';
                              }
                            }
                          }

                          // 가로 모드
                          if (isLandscape) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: RichText(
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        text: TextSpan(children: [
                                          TextSpan(
                                            text: '${widget.d['caseName']} 아동',
                                            style: const TextStyle(color: Color(0xFF222222), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                                          ),
                                          if ((widget.d['dong']?.toString() ?? '').isNotEmpty)
                                            TextSpan(
                                              text: '  ${widget.d['dong']}',
                                              style: const TextStyle(color: Color(0xFFB0B8C1), fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: -0.2),
                                            ),
                                        ]),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(subLine1, style: const TextStyle(color: Color(0xFF8B95A1), fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text(subLine2, style: const TextStyle(color: Color(0xFF8B95A1), fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            );
                          }

                          // 세로 모드: 파란 번호 + 텍스트 3행 + 공유 버튼
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // 왼쪽: 파란 번호
                              SizedBox(
                                width: 32,
                                child: Text(
                                  '${widget.index + 1}',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 가운데: 텍스트 3행
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    RichText(
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(children: [
                                        TextSpan(
                                          text: '${widget.d['caseName']} 아동',
                                          style: const TextStyle(color: Color(0xFF222222), fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                                        ),
                                        if ((widget.d['dong']?.toString() ?? '').isNotEmpty)
                                          TextSpan(
                                            text: '  ${widget.d['dong']}',
                                            style: const TextStyle(color: Color(0xFFB0B8C1), fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: -0.2),
                                          ),
                                      ]),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(subLine1, style: const TextStyle(color: Color(0xFF8B95A1), fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 2),
                                    Text(subLine2, style: const TextStyle(color: Color(0xFF8B95A1), fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 오른쪽: 공유 버튼 (세로 정가운데)
                              GestureDetector(
                                onTap: _copyShareLink,
                                onTapDown: (_) => setState(() => _isSharePressed = true),
                                onTapUp: (_) => setState(() => _isSharePressed = false),
                                onTapCancel: () => setState(() => _isSharePressed = false),
                                child: AnimatedScale(
                                  scale: _isSharePressed ? 0.95 : 1.0,
                                  duration: const Duration(milliseconds: 100),
                                  curve: Curves.easeOutCubic,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 100),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _isSharePressed
                                          ? const Color(0xFFBFDAFF)
                                          : const Color(0xFFE0EFFF),
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: Text(
                                      '공유',
                                      style: TextStyle(
                                        color: _isSharePressed
                                            ? AppColors.primary.withValues(alpha: 0.8)
                                            : AppColors.primary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 카드 사이 구분선 (마지막 카드 제외)
            if (!widget.isLast)
              const Divider(height: 1, thickness: 1, color: Color(0xFFF2F4F6)),
          ],
        );
      },
    );
  }
}


class PressableProfileMenuItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDanger;

  const PressableProfileMenuItem({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  State<PressableProfileMenuItem> createState() =>
      _PressableProfileMenuItemState();
}

class _PressableProfileMenuItemState extends State<PressableProfileMenuItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: _isPressed ? const Color(0xFFF2F4F6) : Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(
              widget.icon,
              color: widget.isDanger ? AppColors.danger : AppColors.textMain,
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  color: widget.isDanger ? AppColors.danger : AppColors.textMain,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.border, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── 공유받은 DB 카드 (스와이프 삭제) ─────────────────────────────────────
class SwipeableSharedDraftCard extends StatefulWidget {
  final String caseName;
  final String authorName;
  final String shareUrl;
  final Future<bool> Function() onDelete;
  final bool isLast;

  const SwipeableSharedDraftCard({
    super.key,
    required this.caseName,
    required this.authorName,
    required this.shareUrl,
    required this.onDelete,
    this.isLast = true,
  });

  @override
  State<SwipeableSharedDraftCard> createState() => _SwipeableSharedDraftCardState();
}

class _SwipeableSharedDraftCardState extends State<SwipeableSharedDraftCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0;
  static const double _maxSwipe = 90.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0, end: -_maxSwipe)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta!;
      if (_dragOffset > 0) _dragOffset = 0;
      if (_dragOffset < -_maxSwipe * 1.2) _dragOffset = -_maxSwipe * 1.2;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) async {
    if (_dragOffset < -_maxSwipe * 0.7) {
      _controller.forward(from: _dragOffset / -_maxSwipe);
      _dragOffset = -_maxSwipe;
      final confirmed = await widget.onDelete();
      if (!confirmed && mounted) {
        _controller.reverse();
        setState(() => _dragOffset = 0);
      }
    } else if (_dragOffset < -_maxSwipe / 3) {
      _controller.forward(from: _dragOffset / -_maxSwipe);
      _dragOffset = -_maxSwipe;
    } else {
      _controller.reverse(from: _dragOffset / -_maxSwipe);
      _dragOffset = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final offset = _controller.isAnimating ? _animation.value : _dragOffset;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () async {
                          final confirmed = await widget.onDelete();
                          if (!confirmed && mounted) {
                            _controller.reverse();
                            setState(() => _dragOffset = 0);
                          }
                        },
                        child: Container(
                          width: _maxSwipe,
                          height: double.infinity,
                          alignment: Alignment.center,
                          child: const Icon(Icons.delete, color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(offset, 0),
                  child: GestureDetector(
                    onHorizontalDragUpdate: _onHorizontalDragUpdate,
                    onHorizontalDragEnd: _onHorizontalDragEnd,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.zero,
                        border: Border(),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.folder_shared_rounded, color: AppColors.primary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${widget.caseName} 아동',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${widget.authorName} 상담원이 공유함',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF8B95A1)),
                                ),
                              ],
                            ),
                          ),
                          if (widget.shareUrl.isNotEmpty)
                            GestureDetector(
                              onTap: () async {
                                final uri = Uri.parse(widget.shareUrl);
                                if (await canLaunchUrl(uri)) {
                                  launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '웹에서 보기',
                                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (!widget.isLast)
              const Divider(height: 1, thickness: 1, color: Color(0xFFF2F4F6)),
          ],
        );
      },
    );
  }
}

