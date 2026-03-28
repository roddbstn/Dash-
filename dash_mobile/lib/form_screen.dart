import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dash_mobile/widgets/provision_date_time_picker.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dash_mobile/widgets/dash_button.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class FormScreen extends StatefulWidget {
  final dynamic caseId;
  final String caseName;
  final String dong;
  final int? draftId;

  const FormScreen({
    super.key,
    required this.caseId,
    required this.caseName,
    required this.dong,
    this.draftId,
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
  String _selectedService = '아동권리교육';
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
  bool _showOtherTargetField = false;
  bool _showOtherLocationField = false;
  bool _isManualTravelTime = false;
  bool _isLoading = false;
  bool _showDateTimeError = false;
  Map<String, dynamic>? _currentDraft;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  final List<String> _serviceOptions = [
    '의류지원', '성폭력(예방)교육', '사례회의', '아동 양육기술 상담/교육', '식품지원', '아동권리교육',
    '외부기관연계지원', '복지서비스정보물제공', '안전교육', '아동 안전점검 및 상담', '사건처리 및 절차지원', '학대예방교육'
  ];

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
    }
  }

  void _handleSave() async {
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
      if (isSameDay) {
        dateTimeString = "${DateFormat('MM.dd HH:mm').format(_startDate!)} ~ ${DateFormat('HH:mm').format(_endDate!)}";
      } else {
        dateTimeString = "${DateFormat('MM.dd HH:mm').format(_startDate!)} ~ ${DateFormat('MM.dd HH:mm').format(_endDate!)}";
      }
    }

    final draftData = {
      'id': widget.draftId ?? DateTime.now().millisecondsSinceEpoch,
      'caseName': widget.caseName,
      'target': targetValue,
      'provision_type': _selectedProvisionType,
      'method': _selectedMethod,
      'service_type': _selectedServiceType,
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
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
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
    setState(() => _isLoading = true);
    
    final userId = await StorageService.getUserId();
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final serverDraftData = {
      'case_id': widget.caseId,
      'case_name': widget.caseName,
      'dong': widget.dong,
      'user_id': userId,
      'user_email': userEmail,
      'target': targetValue,
      'provision_type': _selectedProvisionType,
      'method': _selectedMethod,
      'service_type': _selectedServiceType,
      'service_name': _selectedService,
      'location': _selectedLocation == '기타' ? _otherLocationController.text : _selectedLocation,
      'start_time': _startDate?.toIso8601String(),
      'end_time': _endDate?.toIso8601String(),
      'service_count': int.tryParse(_serviceCountController.text) ?? 1,
      'travel_time': _travelTime,
      'service_description': _serviceController.text, 
      'agent_opinion': _opinionController.text,       
      'encrypted_blob': encryptedBlob,
      'share_token': _currentDraft?['share_token'],
    };
    
    final shareToken = await ApiService.syncRecord(serverDraftData);
    if (shareToken != null) {
      final updatedDrafts = await StorageService.getDrafts();
      final idx = updatedDrafts.indexWhere((d) => d['id'].toString() == targetId.toString());
      if (idx != -1) {
        updatedDrafts[idx]['share_token'] = shareToken;
        updatedDrafts[idx]['status'] = 'Synced';
        await StorageService.saveDrafts(updatedDrafts);
        setState(() { _currentDraft = updatedDrafts[idx]; });
      }
    } else {
      final pending = await StorageService.getPendingSyncs();
      serverDraftData['client_draft_id'] = targetId;
      pending.add(serverDraftData);
      await StorageService.savePendingSyncs(pending);
    }
    
    setState(() => _isLoading = false);
    if (mounted) {
      if (shareToken != null) {
         Navigator.pop(context, true);
      } else {
        _showSuccessDialog(true);
      }
    }
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
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
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
                      _showShareModal(); 
                    }, 
                    text: '공유하기', 
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

  void _showShareModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('공유하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildShareItem(label: '카카오톡', icon: Icons.chat, color: const Color(0xFFFEE500), iconColor: Colors.black, onTap: () { Navigator.pop(context); _showToast('SDK가 필요합니다.'); }),
                  _buildShareItem(label: '메신저', icon: Icons.send, color: AppColors.primary, iconColor: Colors.white, onTap: () {
                    Navigator.pop(context);
                    final String token = _currentDraft?['share_token'] ?? '';
                    final String key = _currentDraft?['encryption_key'] ?? '';
                    final String host = ApiService.baseUrl.replaceAll('/api', '');
                    final url = "$host/?token=$token${key.isNotEmpty ? '#$key' : ''}";
                    Share.share('[${widget.caseName} 서비스 제공 DB]\n\n$url');
                  }),
                  _buildShareItem(label: '링크 복사', icon: Icons.link, color: const Color(0xFFF2F4F6), iconColor: AppColors.textMain, onTap: () {
                    Navigator.pop(context);
                    final String token = _currentDraft?['share_token'] ?? '';
                    final String key = _currentDraft?['encryption_key'] ?? '';
                    final String host = ApiService.baseUrl.replaceAll('/api', '');
                    if (token.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: "$host/?token=$token${key.isNotEmpty ? '#$key' : ''}"));
                      _showToast('링크가 복사되었습니다.');
                    } else {
                       _showToast('저장이 필요합니다.');
                    }
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShareItem({required String label, required IconData icon, required Color color, required Color iconColor, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: iconColor)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSub)),
        ],
      ),
    );
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
    // Status color and label logic
    final bool isReviewed = (_currentDraft?['status']?.toString().toLowerCase() == 'reviewed');

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: () => Navigator.pop(context)),
        title: Text(widget.draftId == null ? 'DB 생성' : 'DB 수정', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (widget.draftId != null) IconButton(icon: const Icon(Icons.ios_share, size: 22), onPressed: _showShareModal),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : Column(
        children: [
          // Case Info (Pinned to top)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  Text("${widget.caseName} 아동", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text(widget.dong, style: const TextStyle(color: Color(0xFF8B95A1), fontSize: 13)),
                  const Spacer(),
                  // Status Tag added at the right end (Only shows in Edit mode)
                  if (widget.draftId != null) 
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isReviewed ? AppColors.successLight : AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isReviewed ? AppColors.success : AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isReviewed ? '검토 완료' : '검토 대기',
                            style: TextStyle(
                              color: isReviewed ? AppColors.success : AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Form Sections (Scrollable)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              child: Column(
                children: [
                  _buildSection(label: '서비스 내용', child: TextField(controller: _serviceController, maxLines: null, decoration: const InputDecoration(hintText: '입력해주세요', border: InputBorder.none))),
                  _buildSection(label: '상담원 소견', child: TextField(controller: _opinionController, maxLines: null, decoration: const InputDecoration(hintText: '입력해주세요', border: InputBorder.none))),
                  _buildSection(
                    label: '대상자',
                    child: Wrap(
                      spacing: 8,
                      children: ['피해아동', '사례관리대상자', '가족구성원', '가족전체', '시설', '기타'].map((t) => _buildChip(t, _selectedTargets.contains(t), (val) {
                        setState(() {
                          if (_selectedTargets.contains(val)) _selectedTargets.remove(val); else _selectedTargets.add(val);
                        });
                      })).toList(),
                    ),
                  ),
                  _buildSection(label: '제공구분', child: Wrap(spacing: 8, children: ['제공', '부가업무', '거부'].map((t) => _buildChip(t, _selectedProvisionType == t, (val) => setState(() => _selectedProvisionType = val))).toList())),
                  _buildSection(label: '제공방법', child: Wrap(spacing: 8, children: ['방문', '내방', '전화'].map((t) => _buildChip(t, _selectedMethod == t, (val) => setState(() => _selectedMethod = val))).toList())),
                  _buildSection(label: '서비스유형', child: Wrap(spacing: 8, children: ['아보전', '연계', '통합'].map((t) => _buildChip(t, _selectedServiceType == t, (val) => setState(() => _selectedServiceType = val))).toList())),
                  _buildSection(label: '제공서비스', child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _selectedService, items: _serviceOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => _selectedService = v!)))),
                  _buildSection(
                    label: '제공장소',
                    child: Wrap(
                      spacing: 8,
                      children: ['기관내', '아동가정', '유관기관', '기타'].map((t) => _buildChip(t, _selectedLocation == t, (val) {
                        setState(() { _selectedLocation = val; _showOtherLocationField = val == '기타'; });
                      })).toList(),
                    ),
                  ),
                  if (_showOtherLocationField) _buildSection(label: '기타 장소', child: TextField(controller: _otherLocationController)),
                  _buildSection(
                    label: '제공일시',
                    child: InkWell(
                      onTap: _selectDateTime,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(border: Border.all(color: (_showDateTimeError && _startDate == null) ? Colors.red : Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                        child: Text(_startDate == null ? '일시 선택' : "${DateFormat('MM.dd HH:mm').format(_startDate!)} ~ ${DateFormat('MM.dd HH:mm').format(_endDate!)}"),
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
                                  decoration: const InputDecoration(hintText: '0'),
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
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        child: DashButton(onTap: () { if (_startDate == null) setState(() => _showDateTimeError = true); else _handleSave(); }, text: '저장', backgroundColor: AppColors.primary, height: 56),
      ),
    );
  }

  Widget _buildSection({required String label, String? subLabel, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.black.withOpacity(0.05))),
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
