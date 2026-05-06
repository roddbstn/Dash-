import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:dash_mobile/theme.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:dash_mobile/widgets/dash_button.dart';

class ProvisionDateTimePicker extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;

  const ProvisionDateTimePicker({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
  });

  @override
  State<ProvisionDateTimePicker> createState() => _ProvisionDateTimePickerState();
}

class _ProvisionDateTimePickerState extends State<ProvisionDateTimePicker> {
  DateTime? _startSelectedDate;
  DateTime? _endSelectedDate;
  late int _startHour;
  late int _startMinute;
  late int _endHour;
  late int _endMinute;
  String? _errorMessage;
  Timer? _errorTimer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startSelectedDate = widget.initialStartDate ?? DateTime(now.year, now.month, now.day);
    _endSelectedDate = widget.initialEndDate; // null이면 단일 선택 상태 (범위 없음)
    
    _startHour = widget.initialStartDate?.hour ?? now.hour;
    _startMinute = widget.initialStartDate?.minute ?? now.minute;
    
    final defaultEnd = widget.initialEndDate ?? now.add(const Duration(hours: 1));
    _endHour = defaultEnd.hour;
    _endMinute = defaultEnd.minute;
  }

  void _showInternalError(String message) {
    setState(() => _errorMessage = message);
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _errorMessage = null);
    });
  }

  void _onDateClick(DateTime date) {
    setState(() {
      if (_startSelectedDate == null || (_startSelectedDate != null && _endSelectedDate != null)) {
        _startSelectedDate = date;
        _endSelectedDate = null;
      } else {
        if (date.isBefore(_startSelectedDate!)) {
          _endSelectedDate = _startSelectedDate;
          _startSelectedDate = date;
        } else if (date == _startSelectedDate) {
          // Do nothing or clear? Usually keep one selected.
        } else {
          _endSelectedDate = date;
        }
      }
    });
  }

  void _onApply() {
    if (_startSelectedDate == null) {
      _showInternalError('날짜를 먼저 선택해주세요.');
      return;
    }

    final endDay = _endSelectedDate ?? _startSelectedDate!;
    final start = DateTime(_startSelectedDate!.year, _startSelectedDate!.month, _startSelectedDate!.day, _startHour, _startMinute);
    final end = DateTime(endDay.year, endDay.month, endDay.day, _endHour, _endMinute);

    if (end.isBefore(start)) {
      _showInternalError('종료 시간이 시작 시간보다 빠를 수 없습니다.');
      return;
    }

    Navigator.pop(context, {'start': start, 'end': end});
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Stack(
      children: [
        Container(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.88),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header (not scrollable)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '제공일시 선택',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textMain),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textMain),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Scrollable body
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, bottomInset + 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Calendar Section
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: _CustomCalendar(
                          startSelectedDate: _startSelectedDate,
                          endSelectedDate: _endSelectedDate,
                          onDateSelected: _onDateClick,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Time Selection Section
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                const Text('시작', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSub)),
                                const SizedBox(height: 8),
                                _TimeWheelPicker(
                                  hour: _startHour,
                                  minute: _startMinute,
                                  onChanged: (h, m) => setState(() { _startHour = h; _startMinute = m; }),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('종료', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSub)),
                                const SizedBox(height: 8),
                                _TimeWheelPicker(
                                  hour: _endHour,
                                  minute: _endMinute,
                                  onChanged: (h, m) => setState(() { _endHour = h; _endMinute = m; }),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Apply Button
                      DashButton(
                        onTap: _onApply,
                        text: '확인',
                        backgroundColor: AppColors.primary,
                        height: 52,
                        borderRadius: 16,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Internal Toast Error
        if (_errorMessage != null)
          Positioned(
            bottom: 110,
            left: 24,
            right: 24,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CustomCalendar extends StatefulWidget {
  final DateTime? startSelectedDate;
  final DateTime? endSelectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const _CustomCalendar({this.startSelectedDate, this.endSelectedDate, required this.onDateSelected});

  @override
  State<_CustomCalendar> createState() => _CustomCalendarState();
}

class _CustomCalendarState extends State<_CustomCalendar> {
  late DateTime _viewMonth;

  @override
  void initState() {
    super.initState();
    _viewMonth = DateTime((widget.startSelectedDate ?? DateTime.now()).year, (widget.startSelectedDate ?? DateTime.now()).month);
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
    final firstDayOffset = DateTime(_viewMonth.year, _viewMonth.month, 1).weekday - 1; // 0=Mon, 6=Sun
    
    return Column(
      children: [
        // Month Header
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: AppColors.primary, size: 28),
              onPressed: () => setState(() => _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1)),
            ),
            const SizedBox(width: 8),
            Text(
              DateFormat('yyyy년 M월').format(_viewMonth),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textMain),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: AppColors.primary, size: 28),
              onPressed: () => setState(() => _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Day Names
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['월', '화', '수', '목', '금', '토', '일']
              .map((d) => SizedBox(
                    width: 32,
                    child: Text(d, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        // Dates Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 0,
          ),
          itemCount: daysInMonth + firstDayOffset,
          itemBuilder: (context, index) {
            if (index < firstDayOffset) return const SizedBox.shrink();
            
            final day = index - firstDayOffset + 1;
            final date = DateTime(_viewMonth.year, _viewMonth.month, day);
            
            bool isStart = widget.startSelectedDate != null && 
                           widget.startSelectedDate!.year == date.year &&
                           widget.startSelectedDate!.month == date.month &&
                           widget.startSelectedDate!.day == date.day;
            
            bool isEnd = widget.endSelectedDate != null && 
                         widget.endSelectedDate!.year == date.year &&
                         widget.endSelectedDate!.month == date.month &&
                         widget.endSelectedDate!.day == date.day;
            
            bool isInRange = false;
            if (widget.startSelectedDate != null && widget.endSelectedDate != null) {
              isInRange = date.isAfter(widget.startSelectedDate!) && date.isBefore(widget.endSelectedDate!);
            }

            final isSelected = isStart || isEnd;
            // 시작=종료가 같은 날짜면 범위 표시 없음 (단일 선택)
            final isSingleDate = isStart && isEnd;
            bool isStartInRange = isStart && widget.endSelectedDate != null && !isSingleDate;
            bool isEndInRange = isEnd && widget.startSelectedDate != null && !isSingleDate;

            return GestureDetector(
              onTap: () => widget.onDateSelected(date),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                alignment: Alignment.center,
                children: [
                  // 중간 날짜: 전체 너비, 높이 44px (원보다 위아래로 4px 여유)
                  if (isInRange)
                    Positioned(
                      left: 0,
                      right: 0,
                      height: 44,
                      child: ColoredBox(color: AppColors.primaryLight),
                    ),
                  // 시작 날짜: 전체 너비, 왼쪽 끝 rounded (원을 감싸는 캡슐 왼쪽)
                  if (isStartInRange)
                    Positioned(
                      left: 0,
                      right: 0,
                      height: 44,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(22),
                            bottomLeft: Radius.circular(22),
                          ),
                        ),
                      ),
                    ),
                  // 종료 날짜: 전체 너비, 오른쪽 끝 rounded (원을 감싸는 캡슐 오른쪽)
                  if (isEndInRange)
                    Positioned(
                      left: 0,
                      right: 0,
                      height: 44,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(22),
                            bottomRight: Radius.circular(22),
                          ),
                        ),
                      ),
                    ),
                  // Selected circle
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                        color: isSelected ? Colors.white : AppColors.textMain,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TimeWheelPicker extends StatelessWidget {
  final int hour;
  final int minute;
  final Function(int, int) onChanged;

  const _TimeWheelPicker({required this.hour, required this.minute, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Center Indicator (Selection Box)
          Center(
            child: Container(
              height: 40,
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFF2F4F6), width: 1),
                  bottom: BorderSide(color: Color(0xFFF2F4F6), width: 1),
                ),
              ),
            ),
          ),
          // Wheels
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildWheel(
                context, 
                24, 
                hour, 
                (val) => onChanged(val, minute)
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(':', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
              _buildWheel(
                context, 
                60, 
                minute, 
                (val) => onChanged(hour, val)
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWheel(BuildContext context, int count, int initialValue, ValueChanged<int> onSelect) {
    return SizedBox(
      width: 50,
      child: CupertinoPicker(
        itemExtent: 44,
        selectionOverlay: const SizedBox.shrink(),
        scrollController: FixedExtentScrollController(initialItem: initialValue),
        onSelectedItemChanged: onSelect,
        useMagnifier: true,
        magnification: 1.1,
        looping: true,
        children: List.generate(count, (index) {
          return Center(
            child: Text(
              index.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.primary.withValues(alpha: index == initialValue ? 1.0 : 0.2),
              ),
            ),
          );
        }),
      ),
    );
  }
}
