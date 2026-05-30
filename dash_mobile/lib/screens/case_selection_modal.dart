import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/analytics_service.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/create_case_screen.dart';
import 'package:dash_mobile/widgets/home_widgets.dart';
import 'package:dash_mobile/widgets/dash_button.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> showCaseSelectionModal({
  required BuildContext context,
  required List<dynamic> initialCounselors,
  required List<dynamic> initialCases,
  required String? initialSelectedCounselorId,
  required void Function(List<dynamic>) onCounselorsChanged,
  required void Function(List<dynamic>) onCasesChanged,
  required void Function(String?) onCounselorIdChanged,
  required void Function(
    String name,
    String maskedName,
    String dong, {
    required dynamic caseId,
    int? draftId,
  }) onGoToForm,
  required void Function(String message) onShowToast,
}) async {
  AnalyticsService.caseSelectionModalOpened();

  // DraggableScrollableSheet를 showModalBottomSheet builder 레벨에 배치해
  // setState가 sheet 자체를 rebuild하지 않도록 분리
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (modalContext) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => _CaseSelectionSheetContent(
        scrollController: scrollController,
        initialCounselors: initialCounselors,
        initialCases: initialCases,
        initialSelectedCounselorId: initialSelectedCounselorId ??
            (initialCounselors.isNotEmpty
                ? initialCounselors[0]['id']?.toString()
                : null),
        onCounselorsChanged: onCounselorsChanged,
        onCasesChanged: onCasesChanged,
        onCounselorIdChanged: onCounselorIdChanged,
        onGoToForm: onGoToForm,
        onShowToast: onShowToast,
      ),
    ),
  );
}

// ── sheet content StatefulWidget (DraggableScrollableSheet 밖에서 rebuild 안 됨) ──
class _CaseSelectionSheetContent extends StatefulWidget {
  final ScrollController scrollController;
  final List<dynamic> initialCounselors;
  final List<dynamic> initialCases;
  final String? initialSelectedCounselorId;
  final void Function(List<dynamic>) onCounselorsChanged;
  final void Function(List<dynamic>) onCasesChanged;
  final void Function(String?) onCounselorIdChanged;
  final void Function(
    String name,
    String maskedName,
    String dong, {
    required dynamic caseId,
    int? draftId,
  }) onGoToForm;
  final void Function(String message) onShowToast;

  const _CaseSelectionSheetContent({
    required this.scrollController,
    required this.initialCounselors,
    required this.initialCases,
    required this.initialSelectedCounselorId,
    required this.onCounselorsChanged,
    required this.onCasesChanged,
    required this.onCounselorIdChanged,
    required this.onGoToForm,
    required this.onShowToast,
  });

  @override
  State<_CaseSelectionSheetContent> createState() =>
      _CaseSelectionSheetContentState();
}

class _CaseSelectionSheetContentState
    extends State<_CaseSelectionSheetContent> {
  late List<dynamic> counselors;
  late List<dynamic> cases;
  late String? selectedCounselorId;

  @override
  void initState() {
    super.initState();
    counselors = List.from(widget.initialCounselors);
    cases = List.from(widget.initialCases);
    selectedCounselorId = widget.initialSelectedCounselorId;
  }

  Future<void> _deleteCounselor(dynamic c) async {
    if (!mounted) return;
    final cid = c['id']?.toString() ?? '';
    final updatedCases = cases
        .where((cs) => cs['counselorId']?.toString() != cid)
        .toList();
    await StorageService.saveCases(updatedCases);
    await ApiService.deleteCounselor(cid);
    AnalyticsService.counselorDeleted();
    if (!mounted) return;
    setState(() {
      cases = updatedCases;
      counselors.removeWhere((x) => x['id']?.toString() == cid);
      if (selectedCounselorId == cid) {
        selectedCounselorId =
            counselors.isNotEmpty ? counselors[0]['id']?.toString() : null;
      }
    });
    await StorageService.saveCounselors(counselors);
    widget.onCounselorsChanged(List.from(counselors));
    widget.onCasesChanged(List.from(cases));
    widget.onCounselorIdChanged(selectedCounselorId);
  }

  @override
  Widget build(BuildContext context) {
    final filteredCases = cases.where((c) {
      final cid = c['counselorId']?.toString();
      if (selectedCounselorId == null) return true;
      if (cid == null || cid.isEmpty) {
        return counselors.isNotEmpty &&
            selectedCounselorId == counselors[0]['id']?.toString();
      }
      return cid == selectedCounselorId;
    }).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── 헤더 ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E8EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '사례 선택',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'DB를 작성할 사례를 선택해주세요.',
                  style: TextStyle(fontSize: 14, color: AppColors.textSub),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          // ── 상담원 탭 ──────────────────────────────────
          SizedBox(
            height: 44,
            child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: counselors.length,
                    itemBuilder: (ctx, i) {
                      final c = counselors[i];
                      return _CounselorChip(
                        key: ValueKey(c['id']),
                        c: c,
                        isSelected:
                            selectedCounselorId == c['id']?.toString(),
                        isEditing: false,
                        onTap: () {
                          setState(() {
                            selectedCounselorId = c['id']?.toString();
                          });
                          widget.onCounselorIdChanged(selectedCounselorId);
                        },
                        onDelete: () => _deleteCounselor(c),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          // ── 사례 그리드 ────────────────────────────────
          Expanded(
            child: filteredCases.isEmpty
                ? Center(
                    child: Text(
                      cases.isEmpty
                          ? '담당 사례들을 추가해주세요.'
                          : '이 상담원의 사례가 없어요.',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFFADB5BD),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  )
                : GridView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.6,
                      ),
                      itemCount: filteredCases.length,
                      itemBuilder: (context, index) {
                        final c = filteredCases[index];
                        return PressableCaseCard(
                          caseData: c,
                          isSelected: false,
                          sIndex: 0,
                          isSelectionMode: false,
                          isEditing: false,
                          onTap: () {
                                  widget.onGoToForm(
                                    c['realName'],
                                    c['maskedName'],
                                    c['dong'],
                                    caseId: c['id'],
                                  );
                                },
                          onDelete: () async {
                            final deletedId = c['id'];
                            final updatedCases = cases
                                .where((x) => x['id'] != deletedId)
                                .toList();
                            await StorageService.saveCases(updatedCases);
                            await ApiService.deleteCase(deletedId);
                            if (!mounted) return;
                            setState(() => cases = updatedCases);
                            widget.onCasesChanged(List.from(cases));
                          },
                        );
                      },
                    ),
          ),
          // ── 하단 버튼 바 ────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: DashButton(
                        backgroundColor: Colors.white,
                        textColor: AppColors.textMain,
                        border: Border.all(color: const Color(0xFFE5E8EB)),
                        text: '상담원 추가',
                        onTap: () async {
                          final partnerCount = counselors
                              .where((c) => c['isSelf'] != true)
                              .length;
                          if (partnerCount >= 3) {
                            _showModalToast(
                                context, '동행 상담원은 3명까지 등록할 수 있어요');
                            return;
                          }
                          final name =
                              await _showAddCounselorDialog(context);
                          if (name != null &&
                              name.isNotEmpty &&
                              mounted) {
                            final uid =
                                FirebaseAuth.instance.currentUser?.uid;
                            final newCounselor = {
                              'id':
                                  'c_${DateTime.now().millisecondsSinceEpoch}',
                              'name': name,
                              'isSelf': false,
                              'sortOrder': counselors.length,
                            };
                            setState(() => counselors.add(newCounselor));
                            await StorageService.saveCounselors(counselors);
                            if (uid != null) {
                              await ApiService.syncCounselor({
                                'id': newCounselor['id'],
                                'user_id': uid,
                                'name': newCounselor['name'],
                                'is_self': false,
                                'sort_order': newCounselor['sortOrder'],
                              });
                            }
                            AnalyticsService.counselorAdded();
                            widget.onCounselorsChanged(List.from(counselors));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DashButton(
                        text: '사례 추가',
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CreateCaseScreen(
                                counselors: counselors,
                                initialCounselorId: selectedCounselorId,
                              ),
                            ),
                          );
                          if (result != null &&
                              result != false &&
                              mounted) {
                            if (result is String) {
                              setState(
                                  () => selectedCounselorId = result);
                              widget.onCounselorIdChanged(
                                  selectedCounselorId);
                            }
                            final freshCases = await StorageService.getCases();
                            final freshCounselors = await StorageService.getCounselors();
                            if (!mounted) return;
                            setState(() {
                              cases = freshCases;
                              counselors = freshCounselors;
                            });
                            widget.onCounselorsChanged(List.from(freshCounselors));
                            widget.onCasesChanged(List.from(freshCases));
                            widget.onShowToast(
                                '사례를 추가하였어요. DB를 작성해보세요!');
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CounselorChip extends StatefulWidget {
  final Map<String, dynamic> c;
  final bool isSelected;
  final bool isEditing;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _CounselorChip({
    super.key,
    required this.c,
    required this.isSelected,
    required this.isEditing,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_CounselorChip> createState() => _CounselorChipState();
}

class _CounselorChipState extends State<_CounselorChip> {
  bool _pressed = false;

  void _showDeleteSheet() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        message: const Text('소속된 사례도 함께 삭제됩니다.'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onDelete?.call();
            },
            child: const Text('삭제'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('취소'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTapDown: widget.isEditing ? null : (_) => setState(() => _pressed = true),
              onTapUp: widget.isEditing ? null : (_) => setState(() => _pressed = false),
              onTapCancel: widget.isEditing ? null : () => setState(() => _pressed = false),
              onTap: widget.isEditing ? null : widget.onTap,
              onLongPress: (!widget.isEditing &&
                      widget.onDelete != null &&
                      widget.c['isSelf'] != true)
                  ? () {
                      setState(() => _pressed = true);
                      Future.delayed(const Duration(milliseconds: 120), () {
                        if (mounted) setState(() => _pressed = false);
                      });
                      _showDeleteSheet();
                    }
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: widget.isSelected && !widget.isEditing
                      ? AppColors.primary
                      : Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: widget.isSelected && !widget.isEditing
                        ? AppColors.primary
                        : const Color(0xFFDDE1E7),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  widget.c['name']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: widget.isSelected && !widget.isEditing
                        ? Colors.white
                        : AppColors.textMain,
                  ),
                ),
              ),
            ),
            if (widget.isEditing &&
                widget.onDelete != null &&
                widget.c['isSelf'] != true)
              Positioned(
                top: -6,
                right: 2,
                child: GestureDetector(
                  onTap: widget.onDelete,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Color(0xFF222222),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _showAddCounselorDialog(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _AddCounselorSheet(),
  );
}

// controller를 StatefulWidget이 소유해 Flutter 생명주기에 따라 안전하게 해제
class _AddCounselorSheet extends StatefulWidget {
  const _AddCounselorSheet();

  @override
  State<_AddCounselorSheet> createState() => _AddCounselorSheetState();
}

class _AddCounselorSheetState extends State<_AddCounselorSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE1E7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '상담원 추가',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                  letterSpacing: -0.5),
            ),
            const SizedBox(height: 6),
            const Text(
              '상담원은 최대 3명까지 추가할 수 있어요',
              style: TextStyle(fontSize: 14, color: Color(0xFF8B95A1), letterSpacing: -0.2),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLength: 7,
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
              },
              decoration: InputDecoration(
                hintText: '예) 이상훈',
                hintStyle: const TextStyle(color: Color(0xFFC4C9D0)),
                counterText: '',
                suffix: Text(
                  '${_ctrl.text.length}/7',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFADB5BD)),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFFDDE1E7), width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFFDDE1E7), width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DashButton(
              onTap: _ctrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, _ctrl.text.trim()),
              text: '추가하기',
              backgroundColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

void _showModalToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(
          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
    ),
    backgroundColor: const Color(0xFF222222),
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.only(bottom: 40, left: 60, right: 60),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
    duration: const Duration(seconds: 2),
  ));
}
