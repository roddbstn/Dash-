import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/widgets/home_widgets.dart';
import 'package:dash_mobile/user_guide_screen.dart';

class HomeTab extends StatelessWidget {
  final String? userName;
  final List<dynamic> pendingDrafts;
  final List<dynamic> sharedDrafts;
  final List<dynamic> cases;
  final List<dynamic> counselors;
  final TabController dbTabController;
  final Future<void> Function() onRefresh;
  final VoidCallback onShowCaseSelection;
  final void Function(
    String name,
    String maskedName,
    String dong, {
    required dynamic caseId,
    int? draftId,
  }) onGoToForm;
  final Future<void> Function(int draftId) onDeleteMyDraft;
  final Future<void> Function(dynamic d) onSharedDraftTap;
  final Future<bool> Function(String recordId) onDeleteSharedDraft;

  const HomeTab({
    super.key,
    required this.userName,
    required this.pendingDrafts,
    required this.sharedDrafts,
    required this.cases,
    required this.counselors,
    required this.dbTabController,
    required this.onRefresh,
    required this.onShowCaseSelection,
    required this.onGoToForm,
    required this.onDeleteMyDraft,
    required this.onSharedDraftTap,
    required this.onDeleteSharedDraft,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet = constraints.maxWidth > 650;

        if (isTablet) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 12),
                child: Column(
                  children: [
                    _buildGuideAndCta(context),
                    const SizedBox(height: 20),
                    _buildDbList(
                        context, isPad: true, padWidth: constraints.maxWidth - 40),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          );
        }

        // 모바일: 상단 배경 + 드래그 가능한 DB 시트
        return Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: const Color(0xFFF5F6F8),
                padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGreetingHeader(),
                    const SizedBox(height: 28),
                    _buildCtaCard(),
                    const SizedBox(height: 32),
                    _buildPcGuideBanner(context),
                  ],
                ),
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.50,
              minChildSize: 0.38,
              maxChildSize: 0.91,
              snap: true,
              snapSizes: const [0.38, 0.50, 0.91],
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x18000000),
                        blurRadius: 24,
                        spreadRadius: 0,
                        offset: Offset(0, -6),
                      ),
                    ],
                  ),
                  child: RefreshIndicator(
                    onRefresh: onRefresh,
                    color: AppColors.primary,
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                        child: _buildDbList(context, isPad: false),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ── 상단 인사말 ─────────────────────────────────────────────────
  Widget _buildGreetingHeader() {
    final int totalCount = pendingDrafts.length + sharedDrafts.length;
    final String displayName =
        (userName != null && userName!.trim().isNotEmpty) ? userName! : '안녕하세요';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset('assets/icons/logo_transparent.png', width: 36, height: 36),
        const SizedBox(height: 20),
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Color(0xFF222222),
            ),
            children: [
              TextSpan(text: '안녕하세요! $displayName님'),
              TextSpan(
                text: '.',
                style: TextStyle(color: AppColors.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '기입할 DB가 $totalCount개 있어요',
          style: const TextStyle(fontSize: 15, color: Color(0xFF888888)),
        ),
      ],
    );
  }

  // ── CTA 버튼 카드 ────────────────────────────────────────────────
  Widget _buildCtaCard() {
    return GestureDetector(
      onTap: onShowCaseSelection,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 14,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'DB 작성하기',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PC 이용 안내 배너 ────────────────────────────────────────────
  Widget _buildPcGuideBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UserGuideScreen()),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEEF3FC),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '이용 안내',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111111),
                        letterSpacing: -0.3,
                        height: 1.35,
                      ),
                      children: [
                        TextSpan(text: 'PC에서 DB\n'),
                        TextSpan(
                          text: '확인하려면?',
                          style: TextStyle(color: Color(0xFF1A56DB)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              height: 76,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 10,
                    child: Container(
                      width: 64,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primary.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 29,
                            height: 3,
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 21,
                            height: 3,
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 22,
                    top: 54,
                    child: Container(
                      width: 20,
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFFBFDBFE),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 60,
                    child: Container(
                      width: 40,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFBFDBFE),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1A56DB),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 태블릿: 인사말 + 배너 + CTA ──────────────────────────────────
  Widget _buildGuideAndCta(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGreetingHeader(),
        const SizedBox(height: 20),
        _buildPcGuideBanner(context),
        const SizedBox(height: 10),
        _buildCtaCard(),
      ],
    );
  }

  // ── DB 목록 섹션 ─────────────────────────────────────────────────
  Widget _buildDbList(BuildContext context,
      {bool isPad = false, double padWidth = 0}) {
    return AnimatedBuilder(
      animation: dbTabController,
      builder: (context, _) {
        final isMyDb = dbTabController.index == 0;

        // 개인 DB / 공유할 DB 분리 (bool true 또는 int 1 모두 처리)
        bool isSharedDb(d) => d['is_shared_db'] == true || d['is_shared_db'] == 1;
        final personalDrafts = pendingDrafts
            .where((d) => !isSharedDb(d))
            .toList();
        final sharedDbDrafts = pendingDrafts
            .where((d) => isSharedDb(d))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DB 목록',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF222222)),
            ),
            const SizedBox(height: 15),
            _buildSegmentControl(
              personalDrafts.length + sharedDrafts.length,
              sharedDbDrafts.length,
            ),
            const SizedBox(height: 15),
            if (isMyDb) ...[
              // 개인 DB + 공유받은 DB
              if (personalDrafts.isEmpty && sharedDrafts.isEmpty)
                _buildEmptyHint('사례를 선택해 DB를 만들어주세요')
              else
                Column(
                  children: [
                    ...personalDrafts.asMap().entries.map<Widget>((entry) {
                      final idx = entry.key;
                      final d = entry.value;
                      final foundCase =
                          cases.cast<Map<String, dynamic>?>().firstWhere(
                                (c) =>
                                    c?['realName'] == d['caseName'] ||
                                    c?['maskedName'] == d['caseName'],
                                orElse: () => null,
                              );
                      final dong =
                          foundCase != null ? foundCase['dong'] : '미지정';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildDraftCardInBox(context, d, dong,
                            index: idx),
                      );
                    }),
                    ...sharedDrafts.asMap().entries.map<Widget>((entry) {
                      final idx = entry.key;
                      final d = entry.value;
                      return Padding(
                        padding: EdgeInsets.only(
                            bottom: idx == sharedDrafts.length - 1 ? 0 : 8),
                        child: _buildSharedDraftCardInBox(context, d),
                      );
                    }),
                  ],
                ),
            ] else ...[
              // 공유할 DB
              if (sharedDbDrafts.isEmpty)
                _buildEmptyHint('동행자 사례 DB를 만들어 공유해보세요')
              else
                Column(
                  children: sharedDbDrafts.asMap().entries.map<Widget>((entry) {
                    final idx = entry.key;
                    final d = entry.value;
                    final foundCase =
                        cases.cast<Map<String, dynamic>?>().firstWhere(
                              (c) =>
                                  c?['realName'] == d['caseName'] ||
                                  c?['maskedName'] == d['caseName'],
                              orElse: () => null,
                            );
                    final dong =
                        foundCase != null ? foundCase['dong'] : '미지정';
                    return Padding(
                      padding: EdgeInsets.only(
                          bottom: idx == sharedDbDrafts.length - 1 ? 0 : 8),
                      child: _buildDraftCardInBox(context, d, dong,
                          index: idx),
                    );
                  }).toList(),
                ),
            ],
            const SizedBox(height: 30),
          ],
        );
      },
    );
  }

  // ── 세그먼트 탭 컨트롤 ────────────────────────────────────────────
  Widget _buildSegmentControl(int myCount, int sharedCount) {
    final isFirst = dbTabController.index == 0;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pillWidth = constraints.maxWidth / 2;
          return SizedBox(
            height: 38,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  left: isFirst ? 0 : pillWidth,
                  top: 0,
                  bottom: 0,
                  width: pillWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    children: [
                      _buildSegmentTab('나의 DB', 0, 0),
                      _buildSegmentTab('공유할 DB', 1, 0),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSegmentTab(String label, int index, int count) {
    final isActive = dbTabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => dbTabController.animateTo(index),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? const Color(0xFF222222) : const Color(0xFF888888),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyHint(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFFADB5BD),
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ── 나의 DB 카드 ─────────────────────────────────────────────────
  Widget _buildDraftCardInBox(BuildContext context, dynamic d, String dong,
      {int index = 0}) {
    final foundCase = cases.cast<Map<String, dynamic>?>().firstWhere(
          (c) =>
              c?['realName'] == d['caseName'] ||
              c?['maskedName'] == d['caseName'],
          orElse: () => null,
        );

    final counselorId = foundCase?['counselorId']?.toString();
    final counselor = counselorId != null
        ? counselors.cast<Map<String, dynamic>?>().firstWhere(
            (c) => c?['id']?.toString() == counselorId,
            orElse: () => null,
          )
        : (counselors.isNotEmpty
            ? counselors[0] as Map<String, dynamic>?
            : null);
    final counselorName = counselor?['name']?.toString();

    return SwipeableDraftCard(
      key: ValueKey(d['id']),
      d: d,
      index: index,
      isLast: true,
      counselorName: counselorName,
      onTap: () => onGoToForm(
        foundCase?['realName'] ?? d['caseName'],
        d['caseName'],
        dong,
        caseId: foundCase?['id'] ?? d['id'],
        draftId: d['id'],
      ),
      onDelete: () async {
        final confirmed = await _showDeleteDraftDialog(context);
        if (confirmed) {
          await onDeleteMyDraft(d['id']);
          return true;
        }
        return false;
      },
    );
  }

  // ── 공유받은 DB 카드 ──────────────────────────────────────────────
  Widget _buildSharedDraftCardInBox(BuildContext context, dynamic d) {
    final String caseName = d['case_name'] ?? d['caseName'] ?? '미지정';
    final String authorName = d['author_name'] ?? '담당자';
    final String recordId = d['id'].toString();

    return SwipeableSharedDraftCard(
      key: ValueKey('shared_$recordId'),
      caseName: caseName,
      authorName: authorName,
      dong: d['dong']?.toString(),
      target: d['target']?.toString(),
      method: d['method']?.toString(),
      startTime: d['start_time']?.toString() ?? d['startTime']?.toString(),
      endTime: d['end_time']?.toString() ?? d['endTime']?.toString(),
      isLast: true,
      onTap: () => onSharedDraftTap(d),
      onDelete: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('공유받은 DB 삭제',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            content: const Text(
              '내 목록에서만 삭제돼요.\n사례 담당자의 DB에는 영향이 없어요.',
              style: TextStyle(
                  fontSize: 14, color: AppColors.textSub, height: 1.6),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소',
                      style: TextStyle(
                          color: Color(0xFFADB5BD),
                          fontWeight: FontWeight.w600))),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('삭제',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700))),
            ],
          ),
        );
        if (confirmed == true) {
          return await onDeleteSharedDraft(recordId);
        }
        return false;
      },
    );
  }

  // ── 나의 DB 삭제 확인 다이얼로그 ──────────────────────────────────
  Future<bool> _showDeleteDraftDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('DB 삭제',
            style:
                TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: const Text(
          '이 DB 작성을 삭제할까요?\n삭제하면 복구할 수 없습니다.',
          style: TextStyle(
              fontSize: 14, color: AppColors.textSub, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소',
                  style: TextStyle(
                      color: Color(0xFFADB5BD),
                      fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제',
                  style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w800))),
        ],
      ),
    );
    return result ?? false;
  }
}
