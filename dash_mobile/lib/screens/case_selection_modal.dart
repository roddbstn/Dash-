import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/analytics_service.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/create_case_screen.dart';
import 'package:dash_mobile/widgets/home_widgets.dart';
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
  required Future<void> Function() onReloadData,
}) async {
  AnalyticsService.caseSelectionModalOpened();

  List<dynamic> counselors = List.from(initialCounselors);
  List<dynamic> cases = List.from(initialCases);
  String? selectedCounselorId = initialSelectedCounselorId ??
      (initialCounselors.isNotEmpty
          ? initialCounselors[0]['id']?.toString()
          : null);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (modalContext) {
      bool isEditingCounselors = false;

      return StatefulBuilder(
        builder: (context, setModalState) {
          final filteredCases = cases.where((c) {
            final cid = c['counselorId']?.toString();
            if (selectedCounselorId == null) return true;
            if (cid == null || cid.isEmpty) {
              return counselors.isNotEmpty &&
                  selectedCounselorId == counselors[0]['id']?.toString();
            }
            return cid == selectedCounselorId;
          }).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(30)),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '사례 선택',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800),
                              ),
                              GestureDetector(
                                onTap: () => setModalState(
                                    () => isEditingCounselors =
                                        !isEditingCounselors),
                                child: Text(
                                  isEditingCounselors ? '완료' : '편집',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isEditingCounselors
                                        ? AppColors.primary
                                        : AppColors.textSub,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'DB를 작성할 사례를 선택해주세요.',
                            style: TextStyle(
                                fontSize: 14, color: AppColors.textSub),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                    // ── 상담원 탭 ──────────────────────────────────
                    SizedBox(
                      height: 44,
                      child: isEditingCounselors
                          ? ReorderableListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24),
                              buildDefaultDragHandles: false,
                              onReorder: (oldIdx, newIdx) {
                                if (newIdx > oldIdx) newIdx--;
                                final item = counselors.removeAt(oldIdx);
                                counselors.insert(newIdx, item);
                                setModalState(() {});
                                onCounselorsChanged(List.from(counselors));
                                StorageService.saveCounselors(counselors);
                                ApiService.reorderCounselors(counselors);
                              },
                              itemCount: counselors.length,
                              itemBuilder: (ctx, i) {
                                final c = counselors[i];
                                return ReorderableDelayedDragStartListener(
                                  key: ValueKey(c['id']),
                                  index: i,
                                  child: _buildCounselorChip(
                                    c: c,
                                    isSelected: selectedCounselorId ==
                                        c['id']?.toString(),
                                    isEditing: true,
                                    onTap: null,
                                    onDelete: () async {
                                      final confirmed =
                                          await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor: Colors.white,
                                          surfaceTintColor:
                                              Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      16)),
                                          title: const Text('상담원 삭제',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  fontSize: 16)),
                                          content: const Text(
                                              '해당 상담원을 삭제하시겠어요?\n소속된 사례도 함께 삭제됩니다.',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  height: 1.5)),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(
                                                        ctx, false),
                                                child:
                                                    const Text('아니오')),
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(
                                                        ctx, true),
                                                child: const Text('삭제',
                                                    style: TextStyle(
                                                        color: AppColors
                                                            .danger))),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) {
                                        final cid =
                                            c['id']?.toString() ?? '';
                                        final updatedCases = cases
                                            .where((cs) =>
                                                cs['counselorId']
                                                    ?.toString() !=
                                                cid)
                                            .toList();
                                        await StorageService.saveCases(
                                            updatedCases);
                                        await ApiService.deleteCounselor(
                                            cid);
                                        AnalyticsService.counselorDeleted();
                                        cases = updatedCases;
                                        counselors.removeWhere((x) =>
                                            x['id']?.toString() == cid);
                                        if (selectedCounselorId == cid) {
                                          selectedCounselorId =
                                              counselors.isNotEmpty
                                                  ? counselors[0]['id']
                                                      ?.toString()
                                                  : null;
                                        }
                                        await StorageService
                                            .saveCounselors(counselors);
                                        onCounselorsChanged(
                                            List.from(counselors));
                                        onCasesChanged(List.from(cases));
                                        onCounselorIdChanged(
                                            selectedCounselorId);
                                        setModalState(() {});
                                      }
                                    },
                                  ),
                                );
                              },
                            )
                          : ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24),
                              itemCount: counselors.length,
                              itemBuilder: (ctx, i) {
                                final c = counselors[i];
                                return _buildCounselorChip(
                                  c: c,
                                  isSelected: selectedCounselorId ==
                                      c['id']?.toString(),
                                  isEditing: false,
                                  onTap: () {
                                    selectedCounselorId =
                                        c['id']?.toString();
                                    onCounselorIdChanged(selectedCounselorId);
                                    setModalState(() {});
                                  },
                                  onDelete: null,
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
                          : Scrollbar(
                              thumbVisibility: true,
                              child: GridView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                    20, 0, 20, 16),
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
                                    isEditing: isEditingCounselors,
                                    onTap: isEditingCounselors
                                        ? () {}
                                        : () {
                                            Navigator.pop(modalContext);
                                            onGoToForm(
                                              c['realName'],
                                              c['maskedName'],
                                              c['dong'],
                                              caseId: c['id'],
                                            );
                                          },
                                    onDelete: () async {
                                      final confirmed =
                                          await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor: Colors.white,
                                          surfaceTintColor:
                                              Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      16)),
                                          title: const Text('사례 삭제',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  fontSize: 16)),
                                          content: const Text(
                                              '해당 사례를 삭제하시겠어요?',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  height: 1.5)),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(
                                                        ctx, false),
                                                child:
                                                    const Text('아니오')),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('삭제',
                                                  style: TextStyle(
                                                      color:
                                                          AppColors.danger)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) {
                                        final updatedCases = cases
                                            .where((x) => x['id'] != c['id'])
                                            .toList();
                                        await StorageService.saveCases(
                                            updatedCases);
                                        cases = updatedCases;
                                        onCasesChanged(List.from(cases));
                                        setModalState(() {});
                                      }
                                    },
                                  );
                                },
                              ),
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
                          padding:
                              const EdgeInsets.fromLTRB(20, 18, 20, 18),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    final partnerCount = counselors
                                        .where((c) => c['isSelf'] != true)
                                        .length;
                                    if (partnerCount >= 3) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            '동행 파트너는 최대 3명까지 추가할 수 있습니다.'),
                                        duration: Duration(seconds: 2),
                                      ));
                                      return;
                                    }
                                    final name =
                                        await _showAddCounselorDialog(
                                            context);
                                    if (name != null && name.isNotEmpty) {
                                      final uid = FirebaseAuth
                                          .instance.currentUser?.uid;
                                      final newCounselor = {
                                        'id':
                                            'c_${DateTime.now().millisecondsSinceEpoch}',
                                        'name': name,
                                        'isSelf': false,
                                        'sortOrder': counselors.length,
                                      };
                                      counselors.add(newCounselor);
                                      await StorageService.saveCounselors(
                                          counselors);
                                      if (uid != null) {
                                        await ApiService.syncCounselor({
                                          'id': newCounselor['id'],
                                          'user_id': uid,
                                          'name': newCounselor['name'],
                                          'is_self': false,
                                          'sort_order':
                                              newCounselor['sortOrder'],
                                        });
                                      }
                                      AnalyticsService.counselorAdded();
                                      onCounselorsChanged(
                                          List.from(counselors));
                                      setModalState(() {});
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(100)),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    '동행 파트너 추가',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CreateCaseScreen(
                                        counselors: counselors,
                                        initialCounselorId:
                                            selectedCounselorId,
                                      ),
                                    ),
                                  );
                                  if (result == true) {
                                    await onReloadData();
                                    final freshCases =
                                        await StorageService.getCases();
                                    cases = freshCases;
                                    setModalState(() {});
                                    onShowToast(
                                        '사례를 추가하였어요. DB를 작성해보세요!');
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.textMain,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(100),
                                    side: const BorderSide(
                                        color: Color(0xFFE5E8EB), width: 1),
                                  ),
                                  elevation: 2,
                                  shadowColor:
                                      Colors.black.withValues(alpha: 0.12),
                                ),
                                child: const Text(
                                  '사례 추가',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15),
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
            },
          );
        },
      );
    },
  );
}

Widget _buildCounselorChip({
  required Map<String, dynamic> c,
  required bool isSelected,
  required bool isEditing,
  required VoidCallback? onTap,
  required VoidCallback? onDelete,
}) {
  return Padding(
    key: ValueKey(c['id']),
    padding: const EdgeInsets.only(right: 8),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: isEditing ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected && !isEditing
                  ? AppColors.primary
                  : Colors.white,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: isSelected && !isEditing
                    ? AppColors.primary
                    : const Color(0xFFDDE1E7),
                width: 1.5,
              ),
            ),
            child: Text(
              c['name']?.toString() ?? '',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected && !isEditing
                    ? Colors.white
                    : AppColors.textMain,
              ),
            ),
          ),
        ),
        if (isEditing && onDelete != null && c['isSelf'] != true)
          Positioned(
            top: -6,
            right: 2,
            child: GestureDetector(
              onTap: onDelete,
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
  );
}

Future<String?> _showAddCounselorDialog(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('동행 파트너 추가',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '최대 3명 · 7글자까지 입력 가능합니다.',
            style: TextStyle(fontSize: 12, color: Color(0xFF868E96)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 7,
            decoration: const InputDecoration(
              hintText: '홍길동 대리님',
              hintStyle: TextStyle(color: Color(0xFFADB5BD)),
              counterStyle:
                  TextStyle(fontSize: 11, color: Color(0xFFADB5BD)),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('취소')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('추가',
                style: TextStyle(color: AppColors.primary))),
      ],
    ),
  );
  controller.dispose();
  return result;
}
