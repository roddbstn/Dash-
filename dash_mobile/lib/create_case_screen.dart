import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/widgets/dash_button.dart';
import 'package:dash_mobile/analytics_service.dart';

// ── 행 데이터 모델 ──────────────────────────────────────────────────────────
class _RowData {
  String? counselorId;
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController dongCtrl = TextEditingController();
  final FocusNode nameFocusNode = FocusNode();
  bool nameFocused = false;

  bool get isValid =>
      counselorId != null &&
      nameCtrl.text.trim().isNotEmpty &&
      dongCtrl.text.trim().isNotEmpty;

  void dispose() {
    nameCtrl.dispose();
    dongCtrl.dispose();
    nameFocusNode.dispose();
  }
}

// ── 화면 ──────────────────────────────────────────────────────────────────────
class CreateCaseScreen extends StatefulWidget {
  final List<dynamic> counselors;
  final String? initialCounselorId;

  const CreateCaseScreen({
    super.key,
    this.counselors = const [],
    this.initialCounselorId,
  });

  @override
  State<CreateCaseScreen> createState() => _CreateCaseScreenState();
}

class _CreateCaseScreenState extends State<CreateCaseScreen> {
  late List<Map<String, dynamic>> _counselors;
  final List<_RowData> _rows = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenCreateCase();
    _counselors = List<Map<String, dynamic>>.from(
      widget.counselors.map((c) => Map<String, dynamic>.from(c)),
    );
    // 첫 행 추가 (모달에서 선택된 상담원 유지)
    _addRow(defaultCounselorId: widget.initialCounselorId);
  }

  @override
  void dispose() {
    for (final r in _rows) r.dispose();
    super.dispose();
  }

  // ── 이름 마스킹 ────────────────────────────────────────────────────────────
  String _mask(String name) {
    if (name.isEmpty) return '';
    final len = name.length;
    if (len <= 1) return name;
    final chars = name.split('');
    if (len == 2) {
      chars[1] = 'O';
    } else {
      for (int i = 1; i < len - 1; i++) {
        if (chars[i] != ' ') chars[i] = 'O';
      }
    }
    return chars.join('');
  }

  // ── 행 추가 ────────────────────────────────────────────────────────────────
  void _addRow({String? defaultCounselorId}) {
    final row = _RowData()..counselorId = defaultCounselorId;
    row.nameCtrl.addListener(() => setState(() {}));
    row.dongCtrl.addListener(() => setState(() {}));
    row.nameFocusNode.addListener(() {
      setState(() => row.nameFocused = row.nameFocusNode.hasFocus);
    });
    setState(() => _rows.add(row));
  }

  void _removeRow(int index) {
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  // ── 유효성 ─────────────────────────────────────────────────────────────────
  bool get _hasAnyValid => _rows.any((r) => r.isValid);

  String _counselorName(String? id) {
    if (id == null) return '선택';
    return _counselors.firstWhere(
      (c) => c['id']?.toString() == id,
      orElse: () => {'name': '선택'},
    )['name']?.toString() ?? '선택';
  }

  // ── 상담원 선택 바텀시트 ───────────────────────────────────────────────────
  Future<void> _showCounselorSheet(int rowIndex) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _CounselorSheet(
        counselors: _counselors,
        selectedId: _rows[rowIndex].counselorId,
        onSelect: (id) {
          setState(() => _rows[rowIndex].counselorId = id);
          Navigator.pop(ctx);
        },
        onAddCounselor: () async {
          Navigator.pop(ctx);
          await _showAddCounselorSheet(rowIndex);
        },
      ),
    );
  }

  // ── 상담원 추가 바텀시트 ───────────────────────────────────────────────────
  // 시트 ctx를 외부로 넘기지 않고, Navigator.pop(ctx, name)으로 결과값만 반환
  Future<void> _showAddCounselorSheet(int rowIndex) async {
    final ctrl = TextEditingController();
    final String? newName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (sheetCtx, setSt) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDE1E7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '상담원 추가',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF111827), letterSpacing: -0.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  '추가할 상담원의 이름을 입력해주세요.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF8B95A1), letterSpacing: -0.2),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLength: 10,
                  onChanged: (_) => setSt(() {}),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) Navigator.pop(sheetCtx, v.trim());
                  },
                  decoration: InputDecoration(
                    hintText: '예) 이상훈',
                    hintStyle: const TextStyle(color: Color(0xFFC4C9D0)),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFDDE1E7), width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFDDE1E7), width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DashButton(
                  onTap: ctrl.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(sheetCtx, ctrl.text.trim()),
                  text: '추가하기',
                  backgroundColor: AppColors.primary,
                  height: 52,
                  borderRadius: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    ctrl.dispose();

    // 시트가 닫힌 후 안전하게 처리 (ctx 참조 없음)
    if (newName == null || newName.isEmpty || !mounted) return;
    _doAddCounselor(newName, rowIndex);
  }

  void _doAddCounselor(String name, int rowIndex) {
    final alreadyExists = _counselors.any((c) => c['name']?.toString() == name);
    if (alreadyExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\'$name\'은(는) 이미 있는 상담원이에요.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    final tempId = 'new_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _counselors.add({'id': tempId, 'name': name});
      _rows[rowIndex].counselorId = tempId;
    });
    // 서버 저장 (비동기, 실패해도 로컬은 유지)
    ApiService.syncCounselor({'name': name});
  }

  // ── 확인 (저장) ────────────────────────────────────────────────────────────
  Future<void> _handleConfirm() async {
    final validRows = _rows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final cases = await StorageService.getCases();
      for (final row in validRows) {
        final counselorId = row.counselorId;
        final realName = row.nameCtrl.text.trim();
        final newCase = {
          'id': DateTime.now().millisecondsSinceEpoch + validRows.indexOf(row),
          'realName': realName,
          'maskedName': _mask(realName),
          'dong': row.dongCtrl.text.trim(),
          'counselorId': counselorId,
          'createdAt': DateTime.now().toIso8601String(),
        };
        cases.add(newCase);
        await StorageService.saveCases(cases);
        await ApiService.syncCase({...newCase, 'counselor_id': counselorId});
        AnalyticsService.caseCreated();
      }
    } catch (e) {
      debugPrint('Save cases error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pop(context, true);
      }
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: const Text(
            '사례 추가',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textMain, letterSpacing: -0.4),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textMain, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                children: [
                  // ── 헤더 라벨 ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 108,
                          child: Text('상담원', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFADB5BD))),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('아동 이름', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFADB5BD))),
                        ),
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 84,
                          child: Text('동', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFADB5BD))),
                        ),
                        const SizedBox(width: 8),
                        const SizedBox(width: 36),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── 행 목록 ────────────────────────────────────────────
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: _rows.length + 1, // +1 = 추가 버튼
                      itemBuilder: (ctx, i) {
                        if (i == _rows.length) return _buildAddRowButton();
                        return _buildRow(i);
                      },
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: _isLoading
            ? null
            : Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, -4))],
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: DashButton(
                      onTap: _hasAnyValid ? _handleConfirm : null,
                      text: '확인',
                      backgroundColor: AppColors.primary,
                      height: 56,
                      borderRadius: 12,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  // ── 사례 행 ────────────────────────────────────────────────────────────────
  Widget _buildRow(int index) {
    final row = _rows[index];
    final name = row.nameCtrl.text;
    final masked = _mask(name);
    final counselorName = _counselorName(row.counselorId);
    final isSelected = row.counselorId != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 상담원 선택 버튼
          SizedBox(
            width: 108,
            height: 48,
            child: GestureDetector(
              onTap: () => _showCounselorSheet(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFF0F4FF) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : const Color(0xFFDDE1E7),
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        counselorName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? AppColors.primary : const Color(0xFF8B95A1),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFFADB5BD)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 아동 이름 (마스킹 오버레이)
          Expanded(
            child: SizedBox(
              height: 48,
              child: Stack(
                children: [
                  // 마스킹 표시 레이어 (포인터 무시, 텍스트+테두리 담당)
                  IgnorePointer(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: row.nameFocused ? AppColors.primary : const Color(0xFFDDE1E7),
                          width: 1.5,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      child: name.isEmpty
                          ? const Text('이름 입력', style: TextStyle(fontSize: 14, color: Color(0xFFC4C9D0)))
                          : Text(masked, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF222222))),
                    ),
                  ),
                  // 실제 입력 필드 (글자 투명, 커서만 보임)
                  Positioned.fill(
                    child: TextField(
                      controller: row.nameCtrl,
                      focusNode: row.nameFocusNode,
                      maxLength: 5,
                      keyboardType: TextInputType.name,
                      style: const TextStyle(color: Colors.transparent, fontSize: 14),
                      cursorColor: AppColors.primary,
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 동 입력
          SizedBox(
            width: 84,
            height: 48,
            child: TextField(
              controller: row.dongCtrl,
              maxLength: 7,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: '유천동',
                hintStyle: const TextStyle(color: Color(0xFFC4C9D0), fontSize: 13),
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFDDE1E7), width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFDDE1E7), width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 삭제 버튼
          GestureDetector(
            onTap: _rows.length > 1 ? () => _removeRow(index) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _rows.length > 1 ? const Color(0xFFF1F3F5) : const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: _rows.length > 1 ? const Color(0xFFADB5BD) : const Color(0xFFDDE1E7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 사례 추가 버튼 ──────────────────────────────────────────────────────────
  Widget _buildAddRowButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: GestureDetector(
        onTap: () => _addRow(),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC8D0DA), width: 1.5, style: BorderStyle.solid),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, size: 20, color: Color(0xFF8B95A1)),
              const SizedBox(width: 6),
              const Text('사례 추가', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF8B95A1), letterSpacing: -0.2)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 상담원 선택 바텀시트 위젯 ─────────────────────────────────────────────────
class _CounselorSheet extends StatelessWidget {
  final List<Map<String, dynamic>> counselors;
  final String? selectedId;
  final void Function(String id) onSelect;
  final VoidCallback onAddCounselor;

  const _CounselorSheet({
    required this.counselors,
    required this.selectedId,
    required this.onSelect,
    required this.onAddCounselor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: const Color(0xFFDDE1E7), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('상담원 선택', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827), letterSpacing: -0.4)),
            ),
          ),
          const SizedBox(height: 12),
          // 상담원 목록
          ...counselors.map((c) {
            final id = c['id']?.toString() ?? '';
            final name = c['name']?.toString() ?? '';
            final isSelected = id == selectedId;
            return InkWell(
              onTap: () => onSelect(id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600,
                          color: isSelected ? AppColors.primary : const Color(0xFF222222),
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_rounded, color: AppColors.primary, size: 20),
                  ],
                ),
              ),
            );
          }),
          const Divider(height: 1, color: Color(0xFFF1F3F5)),
          // 상담원 추가 버튼
          InkWell(
            onTap: onAddCounselor,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded, size: 18, color: AppColors.primary),
                  SizedBox(width: 10),
                  Text('상담원 추가', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: -0.2)),
                ],
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
