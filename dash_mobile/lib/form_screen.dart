import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:intl/intl.dart';
import 'package:dash_mobile/widgets/provision_date_time_picker.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dash_mobile/widgets/dash_button.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:dash_mobile/analytics_service.dart';
import 'package:dash_mobile/crash_service.dart';
import 'package:dash_mobile/vault_service.dart';
import 'package:dash_mobile/service_data.dart';

class FormScreen extends StatefulWidget {
  final dynamic caseId;
  final String caseName;
  final String dong;
  final int? draftId;
  final bool isEmbedded;
  final VoidCallback? onSyncComplete;
  final String? userName;

  const FormScreen({
    super.key,
    required this.caseId,
    required this.caseName,
    required this.dong,
    this.draftId,
    this.isEmbedded = false,
    this.onSyncComplete,
    this.userName,
  });

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  // Form Data
  Set<String> _selectedTargets = {'피해아동'};
  String _selectedProvisionType = '제공';
  String _selectedMethod = '방문';
  String _selectedServiceType = '아보전';
  String _selectedServiceCategory = '아동학대대상자 및 가족 지원';
  String _selectedService = '아동 안전점검 및 상담';
  String _selectedLocation = '기관내';
  int _travelTime = 30;
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _serviceController = TextEditingController();
  final TextEditingController _opinionController = TextEditingController();
  final TextEditingController _otherTargetController = TextEditingController();
  final TextEditingController _otherLocationController = TextEditingController();
  final TextEditingController _travelTimeController = TextEditingController();
  final TextEditingController _serviceCountController = TextEditingController(text: '1');
  final FocusNode _serviceFocusNode = FocusNode();
  final FocusNode _opinionFocusNode = FocusNode();
  bool _showOtherTargetField = false;
  bool _showOtherLocationField = false;
  bool _isManualTravelTime = false;
  bool _isLoading = false;
  bool _showDateTimeError = false;
  Map<String, dynamic>? _currentDraft;
  // 공유받은 DB를 열었을 때, 아무것도 수정하지 않은 상태의 지문(fingerprint)
  String? _sharedDraftFingerprint;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenForm();
    _travelTimeController.text = ""; 
    if (widget.draftId != null) {
      _loadDraftData();
    }
  }

  @override
  void dispose() {
    _travelTimeController.dispose();
    _serviceCountController.dispose();
    _serviceController.dispose();
    _opinionController.dispose();
    _otherTargetController.dispose();
    _otherLocationController.dispose();
    _serviceFocusNode.dispose();
    _opinionFocusNode.dispose();
    super.dispose();
  }


  Future<void> _loadDraftData() async {
    final drafts = await StorageService.getDrafts();
    final draft = drafts.firstWhere(
      (d) => d['id'].toString() == widget.draftId.toString(), 
      orElse: () => null
    );
    if (draft != null) {
      setState(() {
        _currentDraft = draft;
        final rawTargets = (draft['target'] ?? '피해아동').toString().split(', ');
        _selectedTargets = rawTargets.where((t) => ['피해아동', '사례관리대상자', '가족전체', '가족구성원', '시설', '기타'].contains(t)).toSet();
        
        final otherTargets = rawTargets.where((t) => !['피해아동', '사례관리대상자', '가족전체', '가족구성원', '시설', '기타'].contains(t)).toList();
        if (otherTargets.isNotEmpty) {
          _selectedTargets.add('기타');
          _showOtherTargetField = true;
          _otherTargetController.text = otherTargets.join(', ');
        }
        
        _serviceController.text = draft['serviceDescription'] ?? draft['service_description'] ?? '';
        _opinionController.text = draft['agentOpinion'] ?? draft['agent_opinion'] ?? '';
        _selectedMethod = draft['method'] ?? '방문';
        _selectedProvisionType = draft['provision_type'] ?? '제공';
        _selectedServiceType = draft['service_type'] ?? '아보전';
        _selectedService = draft['service_name'] ?? '아동권리교육';
        _selectedServiceCategory = draft['service_category'] ?? findServiceCategory(_selectedService);
        _selectedLocation = draft['location'] ?? '기관내';
        if (_selectedLocation != '기관내' && _selectedLocation != '아동가정' && _selectedLocation != '유관기관') {
           _showOtherLocationField = true;
           _otherLocationController.text = _selectedLocation;
           _selectedLocation = '기타';
        }

        _travelTime = int.tryParse((draft['travelTime'] ?? draft['travel_time'] ?? '0').toString()) ?? 0;
        _isManualTravelTime = ![5, 10, 15, 20, 30].contains(_travelTime);
        if (_isManualTravelTime && _travelTime > 0) {
          _travelTimeController.text = _travelTime.toString();
        }
        
        _serviceCountController.text = (draft['serviceCount'] ?? draft['service_count'] ?? '1').toString();

        final startTimeStr = draft['startTime'] ?? draft['start_time'];
        if (startTimeStr != null) _startDate = DateTime.tryParse(startTimeStr);
        final endTimeStr = draft['endTime'] ?? draft['end_time'];
        if (endTimeStr != null) _endDate = DateTime.tryParse(endTimeStr);
      });
      // 공유받은 DB는 변경 전 지문 저장 → 저장 버튼 비활성화에 사용
      if (draft['isShared'] == true) {
        _sharedDraftFingerprint = _captureFormFingerprint();
      }
    }
  }

  /// 현재 폼 상태를 문자열로 직렬화 (공유 DB 변경 감지용)
  String _captureFormFingerprint() {
    final sortedTargets = [..._selectedTargets]..sort();
    return [
      sortedTargets.join(','),
      _selectedProvisionType,
      _selectedMethod,
      _selectedServiceType,
      _selectedServiceCategory,
      _selectedService,
      _selectedLocation,
      _travelTime.toString(),
      _serviceController.text.trim(),
      _opinionController.text.trim(),
      _serviceCountController.text,
      _startDate?.toIso8601String() ?? '',
      _endDate?.toIso8601String() ?? '',
      _otherTargetController.text.trim(),
      _otherLocationController.text.trim(),
    ].join('||');
  }

  void _handleSave() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final drafts = await StorageService.getDrafts();
    
    List<String> finalTargets = _selectedTargets.where((t) => t != '기타').toList();
    if (_selectedTargets.contains('기타') && _otherTargetController.text.isNotEmpty) {
      finalTargets.add(_otherTargetController.text);
    }
    final targetValue = finalTargets.join(', ');

    String? encryptionKey = _currentDraft?['encryption_key'];
    if (encryptionKey == null) {
      final random = math.Random.secure();
      final values = List<int>.generate(16, (i) => random.nextInt(256));
      encryptionKey = base64Url.encode(values).replaceAll('=', '');
    }

    String? dateTimeString;
    if (_startDate != null && _endDate != null) {
      final bool isSameDay = _startDate!.year == _endDate!.year && _startDate!.month == _endDate!.month && _startDate!.day == _endDate!.day;
      final days = ['월', '화', '수', '목', '금', '토', '일'];
      final startFormatted = "${_startDate!.month}.${_startDate!.day} (${days[_startDate!.weekday - 1]}) ${DateFormat('HH:mm').format(_startDate!)}";
      if (isSameDay) {
        dateTimeString = "$startFormatted ~ ${DateFormat('HH:mm').format(_endDate!)}";
      } else {
        final endFormatted = "${_endDate!.month}.${_endDate!.day} (${days[_endDate!.weekday - 1]}) ${DateFormat('HH:mm').format(_endDate!)}";
        dateTimeString = "$startFormatted ~ $endFormatted";
      }
    }

    final draftData = {
      'id': widget.draftId ?? DateTime.now().millisecondsSinceEpoch,
      'caseName': widget.caseName,
      'dong': widget.dong,
      'target': targetValue,
      'provision_type': _selectedProvisionType,
      'method': _selectedMethod,
      'service_type': _selectedServiceType,
      'service_category': _selectedServiceCategory,
      'service_name': _selectedService,
      'location': _selectedLocation == '기타' ? _otherLocationController.text : _selectedLocation,
      'datetime': dateTimeString,
      'startTime': _startDate?.toIso8601String(),
      'endTime': _endDate?.toIso8601String(),
      'serviceDescription': _serviceController.text,
      'agentOpinion': _opinionController.text,
      'serviceCount': _serviceCountController.text.isEmpty ? '1' : _serviceCountController.text,
      'travelTime': _travelTime,
      'updatedAt': DateTime.now().toIso8601String(),
      'encryption_key': encryptionKey,
    };

    final key = encrypt.Key.fromUtf8(encryptionKey.padRight(32).substring(0, 32));
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(jsonEncode(draftData), iv: iv);
    final encryptedBlob = "${iv.base64}:${encrypted.base64}";

    final int targetId = (widget.draftId ?? draftData['id']) as int;
    final index = drafts.indexWhere((d) => d['id'].toString() == targetId.toString());
    if (index != -1) {
      drafts[index] = draftData;
    } else {
      drafts.add(draftData);
    }

    await StorageService.saveDrafts(drafts);

    final String targetFullList = finalTargets.isNotEmpty ? finalTargets.join(', ') : '-';

    final userId = await StorageService.getUserId();
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? '';

    // [Security] PIN 확인 (로컬, 빠름)
    String? pin = await StorageService.getPin();
    if (pin == null) {
      pin = await _showPinSetupDialog();
      if (pin != null) AnalyticsService.pinSet();
      if (pin == null) return;
    }

    final serverDraftData = {
      'case_id': widget.caseId,
      'case_name': widget.caseName,
      'dong': widget.dong,
      'user_id': userId,
      'user_email': userEmail,
      'user_name': widget.userName,
      'target': targetFullList,
      'provision_type': _selectedProvisionType,
      'method': _selectedMethod,
      'service_type': _selectedServiceType,
      'service_category': _selectedServiceCategory,
      'service_name': _selectedService,
      'location': _selectedLocation == '기타' ? _otherLocationController.text : _selectedLocation,
      'start_time': _startDate?.toIso8601String(),
      'end_time': _endDate?.toIso8601String(),
      'service_count': int.tryParse(_serviceCountController.text) ?? 1,
      'travel_time': _travelTime,
      'service_description': '',
      'agent_opinion': '',
      'encrypted_blob': encryptedBlob,
      'encryption_key': encryptionKey,
      'share_token': _currentDraft?['share_token'],
    };

    // 로컬 저장 완료 → 즉시 홈으로 전환, 서버 동기화는 백그라운드에서 진행
    if (mounted) Navigator.pop(context, true);

    // [Background] 서버 동기화 (화면 전환 후 실행)
    _syncRecordInBackground(
      userId: userId,
      pin: pin,
      targetId: targetId,
      serverDraftData: serverDraftData,
      encryptionKey: encryptionKey,
      provisionType: _selectedProvisionType,
      targetFullList: targetFullList,
      hasServiceDescription: _serviceController.text.isNotEmpty,
      hasAgentOpinion: _opinionController.text.isNotEmpty,
    );
  }

  Future<void> _syncRecordInBackground({
    required String userId,
    required String pin,
    required int targetId,
    required Map<String, dynamic> serverDraftData,
    required String encryptionKey,
    required String provisionType,
    required String targetFullList,
    required bool hasServiceDescription,
    required bool hasAgentOpinion,
  }) async {
    try {
    final shareToken = await ApiService.syncRecord(serverDraftData);
    if (shareToken != null) {
      AnalyticsService.recordSaved(
        provisionType: provisionType,
        target: targetFullList,
        hasServiceDescription: hasServiceDescription,
        hasAgentOpinion: hasAgentOpinion,
      );
      AnalyticsService.recordSyncSuccess();

      final updatedDrafts = await StorageService.getDrafts();
      final idx = updatedDrafts.indexWhere((d) => d['id'].toString() == targetId.toString());
      if (idx != -1) {
        updatedDrafts[idx]['share_token'] = shareToken;
        updatedDrafts[idx]['status'] = 'Synced';
        await StorageService.saveDrafts(updatedDrafts);
      }
      unawaited(_syncKeyToVault(userId, shareToken, encryptionKey, pin));
      // 동기화 완료 → 홈화면에서 _loadData() 트리거 (share_token 저장 후 호출)
      widget.onSyncComplete?.call();
    } else {
      AnalyticsService.recordSyncFailure('no_share_token');
      final pending = await StorageService.getPendingSyncs();
      serverDraftData['client_draft_id'] = targetId;
      pending.add(serverDraftData);
      await StorageService.savePendingSyncs(pending);
      // 오프라인 큐 저장 후에도 콜백 (홈화면 로컬 상태 갱신)
      widget.onSyncComplete?.call();
    }
    } catch (e, stack) {
      CrashService.recordError(e, stack, reason: 'syncRecordInBackground');
      AnalyticsService.recordSyncFailure('unexpected_error');
      widget.onSyncComplete?.call();
    }
  }

  // [Security] PIN Setup Dialog (Simple 4-digit)
  Future<String?> _showPinSetupDialog() async {
    final controller = TextEditingController();
    bool obscure = true;

    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('개인정보 보안 (PIN 번호 4자리)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '작성한 DB 내용은 서버가 읽을 수 없도록 강력히 암호화돼요.\nPC 환경에서 DB를 자동 기입할 때 PIN 번호가 필요해요. (최초 1회 설정)',
                style: TextStyle(fontSize: 14, color: AppColors.textSub, height: 1.5),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 4,
                obscureText: obscure,
                style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold),
                textAlign: TextAlign.left,
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFFF2F4F6),
                  contentPadding: const EdgeInsets.only(left: 20, right: 10, top: 20, bottom: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: const Color(0xFFADB5BD)),
                    onPressed: () => setState(() => obscure = !obscure),
                  ),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('취소', style: TextStyle(color: Color(0xFFADB5BD), fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () async {
                if (controller.text.length == 4) {
                  await StorageService.savePin(controller.text);
                  Navigator.pop(context, controller.text);
                }
              },
              child: const Text('설정 완료', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  // [Security] Sync Encryption Key to User's Vault (E2EE)
  Future<void> _syncKeyToVault(String userId, String recordId, String keyStr, String pin) async {
    try {
      await VaultService.syncKey(userId, recordId, keyStr, pin);
    } catch (e, stack) {
      debugPrint('❌ Vault sync failed, queuing for retry: $e');
      CrashService.recordError(e, stack, reason: 'syncKeyToVault');
      await VaultService.enqueueFailedKey(
        userId: userId,
        recordId: recordId,
        encryptionKey: keyStr,
      );
    }
  }

  void _showServicePicker() {
    String tempCategory = _selectedServiceCategory;
    String tempService = _selectedService;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final services = kServiceCategories[tempCategory] ?? [];
          return SizedBox(
            height: MediaQuery.of(context).size.height
                - MediaQuery.of(context).padding.top
                - kToolbarHeight
                - 8,
            child: Column(
              children: [
                // 헤더
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('제공서비스 선택',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedServiceCategory = tempCategory;
                            _selectedService = tempService;
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('완료',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 좌: 대분류
                      SizedBox(
                        width: 185,
                        child: ListView(
                          children: kServiceCategories.keys.map((cat) {
                            final isActive = cat == tempCategory;
                            return InkWell(
                              onTap: () => setModal(() {
                                tempCategory = cat;
                                if (!kServiceCategories[cat]!.contains(tempService)) {
                                  tempService = kServiceCategories[cat]!.first;
                                }
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 13),
                                color: isActive
                                    ? AppColors.primaryLight
                                    : Colors.transparent,
                                child: Text(
                                  cat,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: isActive
                                        ? AppColors.primary
                                        : AppColors.textMain,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      // 우: 소분류
                      Expanded(
                        child: ListView(
                          children: services.map((svc) {
                            final isActive = svc == tempService;
                            return InkWell(
                              onTap: () => setModal(() => tempService = svc),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 13),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        svc,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isActive
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          color: isActive
                                              ? AppColors.primary
                                              : AppColors.textMain,
                                        ),
                                      ),
                                    ),
                                    if (isActive)
                                      const Icon(Icons.check,
                                          size: 16, color: AppColors.primary),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
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

  void _showSuccessDialog(bool isOffline) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (isOffline ? Colors.orange : AppColors.primary).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isOffline ? Icons.wifi_off_rounded : Icons.check_circle_rounded,
                    color: isOffline ? Colors.orange : AppColors.primary,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isOffline ? '오프라인 임시저장' : 'DB 준비 끝!',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textMain),
                ),
                const SizedBox(height: 12),
                Text(
                  isOffline ? '네트워크 연결 시 자동 동기화됩니다.' : '리뷰 링크를 공유해보세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSub, fontSize: 15),
                ),
                const SizedBox(height: 32),
                if (!isOffline) 
                  DashButton(
                    onTap: () { 
                      Navigator.pop(context); 
                      _copyShareLink(); 
                    }, 
                    text: '링크 복사하기', 
                    backgroundColor: AppColors.primary, 
                    height: 54
                  ),
                if (!isOffline) const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () { 
                      Navigator.pop(context); 
                      Navigator.pop(this.context, true); 
                    }, 
                    child: const Text('홈으로 가기', style: TextStyle(color: Color(0xFF8B95A1), fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, textAlign: TextAlign.center), backgroundColor: Colors.black87, behavior: SnackBarBehavior.floating));
  }

  Future<void> _copyShareLink() async {
    String? token = _currentDraft?['share_token'];
    String? key = _currentDraft?['encryption_key'];
    // 백그라운드 sync가 완료됐을 수 있으므로 스토리지에서 최신 값 재조회
    if ((token == null || token.isEmpty || key == null || key.isEmpty) && widget.draftId != null) {
      final drafts = await StorageService.getDrafts();
      final fresh = drafts.firstWhere(
        (d) => d['id'].toString() == widget.draftId.toString(),
        orElse: () => null,
      );
      token = fresh?['share_token'] ?? token;
      key = fresh?['encryption_key'] ?? key;
    }
    final String host = ApiService.baseUrl.replaceAll('/api', '');
    if (token != null && token.isNotEmpty) {
      final keyParam = (key != null && key.isNotEmpty) ? '&key=$key' : '';
      Clipboard.setData(ClipboardData(text: "$host/?token=$token$keyParam"));
      AnalyticsService.linkCopied();
      _showToast('링크가 복사되었습니다.');
    } else {
      _showToast('저장이 필요합니다.');
    }
  }


  Future<void> _selectDateTime() async {
    final result = await showModalBottomSheet<Map<String, DateTime>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProvisionDateTimePicker(initialStartDate: _startDate, initialEndDate: _endDate),
    );
    if (result != null) setState(() { _startDate = result['start']; _endDate = result['end']; });
  }

  @override
  Widget build(BuildContext context) {
    final bool isReviewed = (_currentDraft?['status']?.toString().toLowerCase() == 'reviewed');

    if (widget.isEmbedded) {
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Material(
          color: AppColors.bg,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildCaseInfoHeader(isReviewed: isReviewed, showBackButton: true),
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        child: _buildFormSections(),
                      ),
                    ),
                    _buildSaveBar(),
                  ],
                ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: () => Navigator.pop(context)),
          title: Text(widget.draftId == null ? 'DB 생성' : 'DB 수정', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          centerTitle: true,
          actions: [
            if (widget.draftId != null) IconButton(icon: const Icon(Icons.ios_share, size: 24), onPressed: _copyShareLink),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildCaseInfoHeader(isReviewed: isReviewed, showBackButton: false),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                      child: _buildFormSections(),
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: _buildSaveBar(),
      ),
    );
  }

  Widget _buildCaseInfoHeader({required bool isReviewed, required bool showBackButton}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            if (showBackButton) ...[
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.textSub),
              ),
              const SizedBox(width: 12),
            ],
            Text("${widget.caseName} 아동", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text(widget.dong, style: const TextStyle(color: Color(0xFF8B95A1), fontSize: 13)),
            const Spacer(),
            if (widget.draftId != null) ...[
              if (showBackButton)
                GestureDetector(
                  onTap: _copyShareLink,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.ios_share, size: 22, color: AppColors.textSub),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFormSections() {
    final leftSections = <Widget>[
      _buildSection(
        label: '서비스 내용',
        child: _buildDismissibleTextField(
          controller: _serviceController,
          focusNode: _serviceFocusNode,
          hintText: '입력해주세요',
        ),
      ),
      _buildSection(
        label: '상담원 소견',
        child: _buildDismissibleTextField(
          controller: _opinionController,
          focusNode: _opinionFocusNode,
          hintText: '입력해주세요',
        ),
      ),
      _buildSection(
        label: '대상자',
        child: Wrap(
          spacing: 8,
          children: ['피해아동', '사례관리대상자', '가족구성원', '가족전체', '시설', '기타'].map((t) => _buildChip(t, _selectedTargets.contains(t), (val) {
            setState(() {
              if (_selectedTargets.contains(val)) {
                _selectedTargets.remove(val);
              } else {
                _selectedTargets.add(val);
              }
            });
          })).toList(),
        ),
      ),
    ];

    final rightSections = <Widget>[
      _buildSection(label: '제공구분', child: Wrap(spacing: 8, children: ['제공', '부가업무', '거부'].map((t) => _buildChip(t, _selectedProvisionType == t, (val) => setState(() => _selectedProvisionType = val))).toList())),
      _buildSection(label: '제공방법', child: Wrap(spacing: 8, children: ['방문', '내방', '전화'].map((t) => _buildChip(t, _selectedMethod == t, (val) => setState(() => _selectedMethod = val))).toList())),
      _buildSection(label: '서비스유형', child: Wrap(spacing: 8, children: ['아보전', '연계', '통합'].map((t) => _buildChip(t, _selectedServiceType == t, (val) => setState(() => _selectedServiceType = val))).toList())),
      _buildSection(
        label: '제공서비스',
        child: InkWell(
          onTap: _showServicePicker,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$_selectedServiceCategory :: $_selectedService',
                    style: const TextStyle(fontSize: 13, color: AppColors.textMain),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down,
                    size: 20, color: AppColors.textSub),
              ],
            ),
          ),
        ),
      ),
      _buildSection(
        label: '제공장소',
        child: Wrap(
          spacing: 8,
          children: ['기관내', '아동가정', '유관기관', '기타'].map((t) => _buildChip(t, _selectedLocation == t, (val) {
            setState(() { _selectedLocation = val; _showOtherLocationField = val == '기타'; });
          })).toList(),
        ),
      ),
      if (_showOtherLocationField)
        _buildSection(
          label: '기타 장소',
          child: TextField(
            controller: _otherLocationController,
            inputFormatters: [LengthLimitingTextInputFormatter(10)],
            decoration: const InputDecoration(
              hintText: '최대 10자 입력',
              hintStyle: TextStyle(color: Color(0xFF8B95A1)),
            ),
          ),
        ),
      _buildSection(
        label: '제공일시',
        child: InkWell(
          onTap: _selectDateTime,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: (_showDateTimeError && _startDate == null) ? Colors.red : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _startDate == null ? '일시 선택' : "${DateFormat('MM.dd HH:mm').format(_startDate!)} ~ ${DateFormat('MM.dd HH:mm').format(_endDate!)}",
              style: TextStyle(color: _startDate == null ? const Color(0xFF8B95A1) : AppColors.textMain),
            ),
          ),
        ),
      ),
      _buildSection(label: '서비스 제공횟수', child: Row(children: [SizedBox(width: 40, child: TextField(controller: _serviceCountController, textAlign: TextAlign.center)), const Text('회')])),
      _buildSection(
        label: '이동소요시간',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...[5, 10, 15, 20, 30].map((t) => _buildChip("$t분", (!_isManualTravelTime && _travelTime == t), (val) => setState(() { _travelTime = t; _isManualTravelTime = false; }))),
                _buildChip("직접 입력", _isManualTravelTime, (val) => setState(() => _isManualTravelTime = true)),
              ],
            ),
            if (_isManualTravelTime) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _travelTimeController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [LengthLimitingTextInputFormatter(7)],
                      decoration: const InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(color: Color(0xFF8B95A1)),
                      ),
                      onChanged: (v) => setState(() => _travelTime = int.tryParse(v) ?? 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('분', style: TextStyle(fontSize: 14, color: AppColors.textSub)),
                ],
              ),
            ],
          ],
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > kTabletBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(children: leftSections)),
              const SizedBox(width: 16),
              Expanded(child: Column(children: rightSections)),
            ],
          );
        }
        return Column(children: [...leftSections, ...rightSections]);
      },
    );
  }

  Widget _buildSaveBar() {
    // 공유받은 DB는 아무 변경도 없을 때 저장 버튼 비활성화
    final bool isSharedUnchanged = _sharedDraftFingerprint != null &&
        _sharedDraftFingerprint == _captureFormFingerprint();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: DashButton(
            onTap: isSharedUnchanged
                ? null
                : () {
                    if (_startDate == null) {
                      setState(() => _showDateTimeError = true);
                    } else {
                      _handleSave();
                    }
                  },
            text: '저장',
            backgroundColor: AppColors.primary,
            height: 56,
          ),
        ),
      ),
    );
  }

  Widget _buildDismissibleTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: null,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF8B95A1)),
        border: InputBorder.none,
        suffixIcon: ListenableBuilder(
          listenable: focusNode,
          builder: (context, child) {
            if (!focusNode.hasFocus) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () => focusNode.unfocus(),
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 8, bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '완료',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSection({required String label, String? subLabel, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.black.withValues(alpha: 0.05))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textSub)),
        if (subLabel != null) Text(subLabel, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  Widget _buildChip(String label, bool isSelected, Function(String) onSelected) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) => onSelected(label),
      selectedColor: AppColors.primaryLight,
      labelStyle: TextStyle(color: isSelected ? AppColors.primary : Colors.black87),
      showCheckmark: false,
    );
  }
}
