import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/analytics_service.dart';
import 'package:dash_mobile/widgets/dash_button.dart';
import 'package:dash_mobile/widgets/dash_loading.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 순수 포매팅 유틸 — 상태 없음, 테스트 가능
// ─────────────────────────────────────────────────────────────────────────────

/// 제공일시 포매팅: "M.d (요일) HH:mm ~ HH:mm" 또는 날짜가 다른 경우 전체 날짜 포함
@visibleForTesting
String formatProvisionDate(String startStr, String endStr) {
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  try {
    if (startStr.isEmpty)
      return endStr.isNotEmpty ? formatSharedDbDate(endStr) : '';
    final start = DateTime.parse(startStr);
    final startFmt =
        '${start.month}.${start.day} (${days[start.weekday - 1]}) ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    if (endStr.isEmpty) return startFmt;
    final end = DateTime.parse(endStr);
    final isSameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    final endTimeFmt =
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    if (isSameDay) return '$startFmt ~ $endTimeFmt';
    final endFmt =
        '${end.month}.${end.day} (${days[end.weekday - 1]}) $endTimeFmt';
    return '$startFmt ~ $endFmt';
  } catch (_) {
    return startStr;
  }
}

/// 날짜 문자열 → "yyyy.MM.dd HH:mm" 포맷
@visibleForTesting
String formatSharedDbDate(String dateStr) {
  try {
    final dt = DateTime.parse(dateStr);
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return dateStr;
  }
}

/// 딥링크로 수신한 공유 DB를 미리보기하고 "내 DB로 저장" 하는 화면
///
/// 흐름:
///   1. 서버에서 공유 DB 메타정보를 fetch
///   2. E2EE 암호화된 경우 encryptionKey로 복호화하여 내용 표시
///   3. "내 DB로 저장" 버튼 → 서버 save-to-my-db API 호출 → 수신자 계정에 복사본 생성
class SharedDbPreviewScreen extends StatefulWidget {
  final String token;
  final String? fallbackKey; // 구버전 URL fragment에서 온 key (서버에 없을 때 fallback)
  final VoidCallback? onSaved;

  const SharedDbPreviewScreen({
    super.key,
    required this.token,
    this.fallbackKey,
    this.onSaved,
  });

  @override
  State<SharedDbPreviewScreen> createState() => _SharedDbPreviewScreenState();
}

class _SharedDbPreviewScreenState extends State<SharedDbPreviewScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _saveComplete = false;
  String? _error;

  // 공유 DB 메타정보
  String _caseName = '';
  String _authorName = '';
  String _dong = '';
  String _serviceDescription = '';
  String _agentOpinion = '';
  String _provisionType = '';
  String _method = '';
  String _serviceType = '';
  String _serviceCategory = '';
  String _serviceName = '';
  String _target = '';
  String _location = '';
  String _startTime = '';
  String _endTime = '';
  String _createdAt = '';
  String _serviceCount = '';
  String _travelTime = '';

  String? _encryptionKey;

  @override
  void initState() {
    super.initState();
    _fetchSharedRecord();
  }

  Future<void> _fetchSharedRecord() async {
    try {
      // 키와 레코드 병렬 요청
      final results = await Future.wait([
        ApiService.fetchSharedRecord(widget.token),
        ApiService.fetchSharedKey(widget.token),
      ]);
      final data = results[0] as Map<String, dynamic>?;
      final fetchedKey = results[1] as String?;

      if (data == null) {
        setState(() {
          _error = '존재하지 않거나 만료된 공유 링크입니다.';
          _isLoading = false;
        });
        return;
      }

      // 본인이 작성한 링크면 화면을 열지 않고 조용히 닫기
      final ownerUid = data['owner_user_id']?.toString();
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (ownerUid != null && myUid != null && ownerUid == myUid) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // 서버에 key가 없으면 구버전 URL fragment key를 fallback으로 사용
      _encryptionKey = fetchedKey ?? widget.fallbackKey;

      String desc = data['service_description'] ?? '';
      String opinion = data['agent_opinion'] ?? '';

      // E2EE 복호화 시도
      final blob = data['encrypted_blob']?.toString();
      final keyStr = _encryptionKey;
      if (blob != null &&
          keyStr != null &&
          keyStr.isNotEmpty &&
          blob.contains(':')) {
        try {
          final parts = blob.split(':');
          final iv = encrypt.IV.fromBase64(parts[0]);
          final encrypted = encrypt.Encrypted.fromBase64(parts[1]);
          final key = encrypt.Key.fromUtf8(
            keyStr.padRight(32).substring(0, 32),
          );
          final encrypter = encrypt.Encrypter(
            encrypt.AES(key, mode: encrypt.AESMode.cbc),
          );
          final decrypted = encrypter.decrypt(encrypted, iv: iv);
          final decryptedData = jsonDecode(decrypted) as Map<String, dynamic>;
          desc =
              decryptedData['serviceDescription'] ??
              decryptedData['service_description'] ??
              desc;
          opinion =
              decryptedData['agentOpinion'] ??
              decryptedData['agent_opinion'] ??
              opinion;
        } catch (e) {
          debugPrint('🔓 E2EE 복호화 실패: $e');
        }
      }

      if (mounted) {
        setState(() {
          _caseName = data['case_name'] ?? '';
          _authorName = data['author_name'] ?? '';
          _dong = data['dong'] ?? '';
          _serviceDescription = desc;
          _agentOpinion = opinion;
          _provisionType = data['provision_type'] ?? '';
          _method = data['method'] ?? '';
          _serviceType = data['service_type'] ?? '';
          _serviceCategory =
              data['service_category'] ?? data['serviceCategory'] ?? '';
          _serviceName = data['service_name'] ?? '';
          _target = data['target'] ?? '';
          _location = data['location'] ?? '';
          _startTime = data['start_time'] ?? '';
          _endTime = data['end_time'] ?? '';
          _createdAt = data['created_at'] ?? '';
          _serviceCount = (data['service_count'] ?? data['serviceCount'] ?? '')
              .toString();
          _travelTime = (data['travel_time'] ?? data['travelTime'] ?? '')
              .toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ 공유 DB 조회 실패: $e');
      if (mounted) {
        setState(() {
          _error = '공유 DB를 불러오는 데 실패했습니다.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveToMyDb() async {
    setState(() => _isSaving = true);

    try {
      // E2EE 복호화된 값(또는 원본 평문)을 함께 전달 — 서버 측 신규 토큰에 키 없음 문제 해결
      final success = await ApiService.saveSharedToMyDb(
        widget.token,
        serviceDescription: _serviceDescription,
        agentOpinion: _agentOpinion,
      );
      if (mounted) {
        if (success) {
          setState(() {
            _saveComplete = true;
            _isSaving = false;
          });
          widget.onSaved?.call();
          AnalyticsService.deepLinkDbSaved(widget.token);
        } else {
          setState(() => _isSaving = false);
          _showToast('저장에 실패했습니다. 다시 시도해주세요.');
        }
      }
    } catch (e) {
      debugPrint('❌ 내 DB로 저장 실패: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        if (e.toString().contains('own_record')) {
          _showToast('본인이 작성한 DB는 저장할 수 없습니다.');
        } else {
          _showToast('저장에 실패했습니다. 다시 시도해주세요.');
        }
      }
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: const Color(0xFF222222),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 40, left: 60, right: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF191F28)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '공유 DB',
          style: TextStyle(
            color: Color(0xFF191F28),
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const DashLoadingOverlay()
          : _error != null
          ? _buildErrorState()
          : _saveComplete
          ? _buildSuccessState()
          : _buildPreview(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.link_off_rounded,
                size: 28,
                color: Color(0xFFE03131),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '연결할 수 없는 링크예요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textMain,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '아래의 경우에 해당할 수 있어요:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSub,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildErrorReasonItem(
                    title: '72시간 자동 만료',
                    description: '보안 및 개인정보 보호를 위해 생성된 시점으로부터 72시간이 지난 링크는 자동으로 만료돼요.',
                  ),
                  const SizedBox(height: 12),
                  _buildErrorReasonItem(
                    title: '기록 삭제',
                    description: '작성자가 앱 내에서 해당 사례 DB를 삭제하면, 서버에서도 데이터가 즉시 영구 파기되어 링크가 비활성화돼요.',
                  ),
                  const SizedBox(height: 12),
                  _buildErrorReasonItem(
                    title: '본인 작성 링크 접속',
                    description: '이중 저장을 방지하기 위해 작성자 본인은 본인이 공유한 링크를 열 수 없어요.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: DashButton(
                text: '돌아가기',
                onTap: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorReasonItem({required String title, required String description}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 3.5),
          child: Icon(
            Icons.fiber_manual_record,
            size: 6,
            color: AppColors.textSub,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSub,
                  height: 1.5,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      size: 36,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '$_caseName 아동 DB를\n저장했어요',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF222222),
                      letterSpacing: -0.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '확장프로그램에서 확인하세요',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8B95A1),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 최하단 CTA 영역
        Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).padding.bottom + 16,
          ),
          child: DashButton(text: '확인', onTap: () => Navigator.pop(context)),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더 카드
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE9ECEF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            _caseName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF191F28),
                            ),
                          ),
                          if (_dong.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F3F5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _dong,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7684),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (_createdAt.isNotEmpty)
                            Text(
                              _formatDate(_createdAt),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8B95A1),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_authorName 상담원 작성',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7684),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 메타정보
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE9ECEF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '서비스 정보',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4E5968),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_provisionType.isNotEmpty)
                        _metaRow('제공구분', _provisionType),
                      if (_method.isNotEmpty) _metaRow('제공방법', _method),
                      if (_serviceType.isNotEmpty)
                        _metaRow('서비스유형', _serviceType),
                      if (_serviceName.isNotEmpty)
                        _metaRow(
                          '제공서비스',
                          _serviceCategory.isNotEmpty
                              ? '$_serviceCategory :: $_serviceName'
                              : _serviceName,
                        ),
                      if (_target.isNotEmpty) _metaRow('대상자', _target),
                      if (_location.isNotEmpty) _metaRow('제공장소', _location),
                      if (_startTime.isNotEmpty || _endTime.isNotEmpty)
                        _metaRow(
                          '제공일시',
                          _formatProvisionDate(_startTime, _endTime),
                        ),
                      if (_serviceCount.isNotEmpty && _serviceCount != '0')
                        _metaRow('제공횟수', '$_serviceCount회'),
                      if (_travelTime.isNotEmpty && _travelTime != '0')
                        _metaRow('이동소요시간', '$_travelTime분'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 서비스 내용
                if (_serviceDescription.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE9ECEF)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '서비스 내용',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4E5968),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _serviceDescription,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF333D4B),
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 상담원 소견
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE9ECEF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '상담원 소견',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4E5968),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _agentOpinion.isNotEmpty
                            ? _agentOpinion
                            : '(작성된 소견 없음)',
                        style: TextStyle(
                          fontSize: 14,
                          color: _agentOpinion.isNotEmpty
                              ? const Color(0xFF333D4B)
                              : const Color(0xFFADB5BD),
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 100), // 하단 CTA 버튼 공간
              ],
            ),
          ),
        ),

        // 하단 CTA
        Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).padding.bottom + 16,
          ),
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
          child: DashButton(
            text: '내 DB로 저장',
            onTap: _isSaving ? null : _saveToMyDb,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8B95A1),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF333D4B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 최상단 @visibleForTesting 함수로 위임
  String _formatProvisionDate(String startStr, String endStr) =>
      formatProvisionDate(startStr, endStr);

  String _formatDate(String dateStr) => formatSharedDbDate(dateStr);
}
