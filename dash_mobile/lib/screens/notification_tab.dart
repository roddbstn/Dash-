import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:intl/intl.dart';

/// 알림 메시지에서 이메일 주소를 이름(@ 앞부분)으로 치환
String _cleanNotifMessage(String? msg) {
  if (msg == null || msg.isEmpty) return 'DB가 수정 완료되었어요.';
  return msg.replaceAllMapped(
    RegExp(r'([\w.+-]+)@[\w\-]+\.[\w.\-]+'),
    (m) {
      final local = m.group(1) ?? '상담원';
      // 이메일 로컬파트를 이름처럼 보이게 (마침표/플러스 제거)
      return local.replaceAll(RegExp(r'[.+_\-]'), ' ').trim();
    },
  );
}

class NotificationTab extends StatelessWidget {
  final List<dynamic> notifications;
  final List<dynamic> drafts;
  final Future<void> Function() onRefresh;
  final void Function(
    String name,
    String maskedName,
    String dong, {
    required dynamic caseId,
    int? draftId,
  }) onGoToForm;
  final void Function(String message) onShowToast;
  final void Function(int notifId) onNotificationRead;

  const NotificationTab({
    super.key,
    required this.notifications,
    required this.drafts,
    required this.onRefresh,
    required this.onGoToForm,
    required this.onShowToast,
    required this.onNotificationRead,
  });

  @override
  Widget build(BuildContext context) {
    // 중복 제거: 동일한 record_token(또는 사례명)에 대해 가장 최신 알림만 남김
    final Map<String, dynamic> uniqueNotifs = {};
    for (var n in notifications) {
      if (n['is_read'] == 0 || n['is_read'] == false) {
        // 토큰이 없으면 사례명을 키로 사용 (구형 알림 대응)
        final String key = n['record_token'] ?? "name_${n['case_name']}";

        if (!uniqueNotifs.containsKey(key)) {
          uniqueNotifs[key] = n;
        } else {
          // 이미 존재하면 생성 시각이 더 최신인 것으로 교체
          final existingTime = uniqueNotifs[key]['created_at'] ?? '';
          final newTime = n['created_at'] ?? '';
          if (newTime.compareTo(existingTime) > 0) {
            uniqueNotifs[key] = n;
          }
        }
      }
    }

    final unreadNotifs = uniqueNotifs.values.toList();
    unreadNotifs.sort(
      (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
    );

    if (unreadNotifs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 40, 24, 16),
            child: Text(
              '알림',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
            ),
          ),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded, size: 64, color: Color(0xFFDEE2E6)),
                  SizedBox(height: 16),
                  Text(
                    '아직 도착한 알림이 없어요',
                    style: TextStyle(color: Color(0xFFADB5BD), fontSize: 16, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 48, 24, 16),
          child: Text(
            '알림',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF222222),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            color: AppColors.primary,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: unreadNotifs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final n = unreadNotifs[index];
                final String caseName = n['case_name'] ?? '미지정';

                String dateStr = '';
                if (n['created_at'] != null) {
                  // 서버 타임스탬프는 UTC — 'Z' 접미사로 UTC 명시 후 로컬(KST)로 변환
                  final raw = n['created_at'] as String;
                  final dt = DateTime.parse(
                    raw.endsWith('Z') ? raw : '${raw}Z',
                  ).toLocal();
                  const days = ['월', '화', '수', '목', '금', '토', '일'];
                  final dayName = days[dt.weekday - 1];
                  dateStr = '${dt.month}.${dt.day} ($dayName) ${DateFormat('HH:mm').format(dt)}';
                }

                final String? nToken = n['record_token'];
                final int? notifId = n['id'];

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    debugPrint('🔔 Notification tapped: $notifId');
                    // 1. 알림 읽음 처리 (서버 및 로컬 즉시 반영)
                    if (notifId != null) {
                      ApiService.markNotificationRead(notifId);
                      onNotificationRead(notifId);
                    }

                    debugPrint('🔍 Found drafts length: ${drafts.length}');
                    // 2. 기록 매칭 및 이동
                    Map<String, dynamic>? foundDraft;
                    for (var d in drafts) {
                      final bool matchToken =
                          (nToken != null && d['share_token'] == nToken);
                      final bool matchName = (d['caseName'] == caseName);
                      if (matchToken || matchName) {
                        foundDraft = Map<String, dynamic>.from(d);
                        break;
                      }
                    }
                    debugPrint('🔍 Matched draft: $foundDraft');

                    if (foundDraft != null) {
                      final dong = foundDraft['dong'] ?? '';
                      onGoToForm(
                        foundDraft['caseName'] ?? caseName,
                        foundDraft['caseName'] ?? caseName,
                        dong,
                        caseId: foundDraft['case_id'] ?? foundDraft['id'],
                        draftId: foundDraft['id'],
                      );
                    } else {
                      onShowToast('해당 사례를 찾을 수 없어요. 😊');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF2F4F6)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F7FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.assignment_turned_in_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "$caseName 아동",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "${_cleanNotifMessage(n['message'])}\n수정 사항을 확인해 보세요.",
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: Color(0xFF4E5968),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    dateStr,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFADB5BD),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const Row(
                                    children: [
                                      Text(
                                        '자세히 보기',
                                        style: TextStyle(
                                          color: Color(0xFF8B95A1),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 16,
                                        color: Color(0xFFADB5BD),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
