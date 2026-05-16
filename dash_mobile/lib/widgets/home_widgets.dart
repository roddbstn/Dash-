import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:intl/intl.dart';

class PressableCaseCard extends StatefulWidget {
  final Map<String, dynamic> caseData;
  final bool isSelected;
  final int sIndex;
  final bool isSelectionMode;
  final bool isEditing;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const PressableCaseCard({
    super.key,
    required this.caseData,
    required this.isSelected,
    required this.sIndex,
    required this.isSelectionMode,
    this.isEditing = false,
    required this.onTap,
    this.onDelete,
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
              if (widget.isEditing && widget.onDelete != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.danger,
                      ),
                      child: const Icon(Icons.close, size: 14, color: Colors.white),
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
  final String? counselorName;

  const SwipeableDraftCard({
    super.key,
    required this.d,
    required this.onTap,
    required this.onDelete,
    this.index = 0,
    this.isLast = true,
    this.counselorName,
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
          }
        }
      } catch (_) {}
    }

    if (token != null && token.isNotEmpty) {
      // [Security] 키는 SecureStorage keyMap에서 조회, URL fragment(#)로 전달
      final String? key = await StorageService.getKeyFromMap(token);
      final host = ApiService.serverUrl;
      final keyParam = (key != null && key.isNotEmpty) ? '#key=$key' : '';
      await Clipboard.setData(ClipboardData(text: '$host/?token=$token$keyParam'));
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('클립보드에 복사되었습니다', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            backgroundColor: const Color(0xFF222222),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 40, left: 60, right: 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '저장 후 공유할 수 있어요',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
            backgroundColor: const Color(0xFF222222),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 40, left: 60, right: 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta!;
      if (_dragOffset > _maxSwipe * 1.2) _dragOffset = _maxSwipe * 1.2;
      if (_dragOffset < -_maxSwipe * 1.2) _dragOffset = -_maxSwipe * 1.2;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) async {
    if (_dragOffset > _maxSwipe * 0.7) {
      // 오른쪽 스와이프 → 공유
      setState(() => _dragOffset = 0);
      await _copyShareLink();
    } else if (_dragOffset > 0) {
      setState(() => _dragOffset = 0);
    } else if (_dragOffset < -_maxSwipe * 0.7) {
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
                  // 공유 배경 (오른쪽 스와이프 — 파란색, 왼쪽 정렬)
                  if (offset > 0)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: _maxSwipe,
                            height: double.infinity,
                            alignment: Alignment.center,
                            child: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                    ),
                  // 삭제 배경 (왼쪽 스와이프 — 빨간색, 오른쪽 정렬)
                  if (offset <= 0)
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
                                      child: Text.rich(
                                        TextSpan(children: [
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
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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

                          // 세로 모드: 텍스트 3행 + 상담원 태그
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // 왼쪽: 텍스트 3행
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text.rich(
                                      TextSpan(children: [
                                        TextSpan(
                                          text: '${widget.d['caseName']} 아동',
                                          style: const TextStyle(color: Color(0xFF222222), fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                                        ),
                                        if ((widget.d['dong']?.toString() ?? '').isNotEmpty)
                                          TextSpan(
                                            text: '  ${widget.d['dong']}',
                                            style: const TextStyle(color: Color(0xFFB0B8C1), fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: -0.2),
                                          ),
                                      ]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(subLine1, style: const TextStyle(color: Color(0xFF8B95A1), fontSize: 12, fontWeight: FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 2),
                                    Text(subLine2, style: const TextStyle(color: Color(0xFF8B95A1), fontSize: 12, fontWeight: FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              // 오른쪽: 상담원 태그 (미선택 스타일)
                              if (widget.counselorName != null) ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(color: const Color(0xFFDDE1E7), width: 1.5),
                                  ),
                                  child: Text(
                                    widget.counselorName!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textMain,
                                    ),
                                  ),
                                ),
                              ],
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
  final String? dong;
  final String? target;
  final String? method;
  final String? startTime;
  final String? endTime;
  final Future<bool> Function() onDelete;
  final bool isLast;
  final VoidCallback? onTap;

  const SwipeableSharedDraftCard({
    super.key,
    required this.caseName,
    required this.authorName,
    this.dong,
    this.target,
    this.method,
    this.startTime,
    this.endTime,
    required this.onDelete,
    this.isLast = true,
    this.onTap,
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
                    onTap: widget.onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.zero,
                        border: Border(),
                      ),
                      child: Builder(builder: (context) {
                        // 대상/방법 텍스트
                        final String subLine1 = [
                          if (widget.target != null && widget.target!.isNotEmpty) '대상: ${widget.target}',
                          if (widget.method != null && widget.method!.isNotEmpty) widget.method!,
                        ].join(' | ');

                        // 제공일시 텍스트
                        String subLine2 = '제공일시 미설정';
                        final start = DateTime.tryParse(widget.startTime ?? '');
                        final end = DateTime.tryParse(widget.endTime ?? '');
                        if (start != null && end != null) {
                          const days = ['월', '화', '수', '목', '금', '토', '일'];
                          final startFmt = '${start.month}.${start.day} (${days[start.weekday - 1]}) ${DateFormat('HH:mm').format(start)}';
                          final isSameDay = start.year == end.year && start.month == end.month && start.day == end.day;
                          if (isSameDay) {
                            subLine2 = '$startFmt~${DateFormat('HH:mm').format(end)}';
                          } else {
                            subLine2 = '$startFmt ~ ${end.month}.${end.day} (${days[end.weekday - 1]}) ${DateFormat('HH:mm').format(end)}';
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(children: [
                                      TextSpan(
                                        text: '${widget.caseName} 아동',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF222222)),
                                      ),
                                      if ((widget.dong?.isNotEmpty ?? false))
                                        TextSpan(
                                          text: '  ${widget.dong}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Color(0xFFB0B8C1)),
                                        ),
                                    ]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${widget.authorName} 상담원',
                                    style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            if (subLine1.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(subLine1, style: const TextStyle(fontSize: 12, color: Color(0xFF8B95A1))),
                            ],
                            const SizedBox(height: 2),
                            Text(subLine2, style: const TextStyle(fontSize: 12, color: Color(0xFF8B95A1))),
                          ],
                        );
                      }),
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

