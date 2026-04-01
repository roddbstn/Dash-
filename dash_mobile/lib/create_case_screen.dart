import 'package:flutter/material.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/widgets/dash_button.dart';


class CreateCaseScreen extends StatefulWidget {
  const CreateCaseScreen({super.key});

  @override
  State<CreateCaseScreen> createState() => _CreateCaseScreenState();
}

class _CreateCaseScreenState extends State<CreateCaseScreen> with SingleTickerProviderStateMixin {
  int _currentStep = 1;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dongController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  late AnimationController _cursorAnimationController;
  bool _isNextEnabled = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _cursorAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    
    _nameController.addListener(_updateNextButtonState);
    _dongController.addListener(_updateNextButtonState);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dongController.dispose();
    _nameFocusNode.dispose();
    _cursorAnimationController.dispose();
    super.dispose();
  }

  void _updateNextButtonState() {
    setState(() {
      if (_currentStep == 1) {
        _isNextEnabled = _nameController.text.isNotEmpty;
      } else {
        _isNextEnabled = _dongController.text.isNotEmpty;
      }
    });
  }

  String _getMaskedName(String name) {
    if (name.isEmpty) return "";
    int len = name.length;
    if (len <= 1) return name;

    List<String> chars = name.split('');
    if (len == 2) {
      chars[1] = 'O';
    } else {
      // Rule: mask all except first and last
      for (int i = 1; i < len - 1; i++) {
        if (chars[i] != ' ') {
          chars[i] = 'O';
        }
      }
    }
    return chars.join('');
  }

  void _handleNext() {
    if (_currentStep == 1) {
      setState(() {
        _currentStep = 2;
        _isNextEnabled = _dongController.text.isNotEmpty;
      });
    } else {
      _saveCase();
    }
  }

  Future<void> _saveCase() async {
    setState(() => _isLoading = true);
    try {
      final cases = await StorageService.getCases();
      final newCase = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'realName': _nameController.text,
        'maskedName': _getMaskedName(_nameController.text),
        'dong': _dongController.text,
        'createdAt': DateTime.now().toIso8601String(),
      };
      cases.add(newCase);
      await StorageService.saveCases(cases);
      
      // 서버와 동기화
      await ApiService.syncCase(newCase);
    } catch (e) {
      debugPrint('Save case error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textMain, size: 20),
          onPressed: () {
            if (_currentStep == 2) {
              setState(() {
                _currentStep = 1;
                _updateNextButtonState();
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, dynamic result) {
          if (didPop) return;
          if (_currentStep == 2) {
            setState(() {
              _currentStep = 1;
              _updateNextButtonState();
            });
          } else {
            Navigator.pop(context);
          }
        },
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 60), 
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : (_currentStep == 1 ? _buildNameStep() : _buildDongStep()),
            ),
          ],
        ),
      ),
    ),
      bottomNavigationBar: Container(
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
              onTap: _isNextEnabled ? _handleNext : null,
              text: _currentStep == 1 ? '다음' : '저장',
              backgroundColor: AppColors.primary,
              height: 56,
              borderRadius: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameStep() {
    final name = _nameController.text;
    
    // Logic: 
    // - Show 2 boxes by default for the start.
    // - Once name.length >= 2, just show exactly the number of boxes for the characters entered.
    int displayBoxCount = name.length < 2 ? 2 : name.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          '피해아동의 이름을\n 입력해주세요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.textMain,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '이름 중간 글자는 저장하지 않아요',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: AppColors.textSub),
        ),
        const SizedBox(height: 60),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _nameFocusNode.requestFocus();
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Hidden real TextField (Max 10)
              Opacity(
                opacity: 0,
                child: SizedBox(
                  width: double.infinity,
                  height: 72,
                  child: TextField(
                    key: const ValueKey('name_field_hidden'),
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    autofocus: true,
                    maxLength: 5,
                    keyboardType: TextInputType.name,
                    decoration: const InputDecoration(
                      counterText: "",
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      // Removed _handleNext() to prevent automatic step advancement
                      // Users must manually tap the 'Next' button
                    },
                  ),
                ),
              ),
              // Visual Boxes
              IgnorePointer(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(displayBoxCount, (index) {
                      final maskedName = _getMaskedName(name);
                      String char = "";
                      if (index < maskedName.length) {
                        char = maskedName[index];
                      }
                      
                      // Logic: Keep focus on the CURRENT syllable box being edited (last character) 
                      // for better Hangul flow, only advancing when a new syllable is started.
                      int activeIndex = name.isEmpty ? 0 : (name.length - 1);
                      final bool isFocused = _nameFocusNode.hasFocus && (index == activeIndex);
                      
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: 52,
                        height: 68,
                        decoration: BoxDecoration(
                          color: isFocused 
                              ? AppColors.primary.withValues(alpha: 0.05)
                              : const Color(0xFFF1F3F5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isFocused ? AppColors.primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Character
                            Text(
                              char,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textMain,
                              ),
                            ),
                            // Blinking Caret
                            if (isFocused) ...[
                              if (char.isNotEmpty) const SizedBox(width: 2),
                              FadeTransition(
                                opacity: _cursorAnimationController,
                                child: Container(
                                  width: 2,
                                  height: 28,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDongStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          '아동이 사는 동이름을\n입력해주세요',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textMain, height: 1.3),
        ),
        const SizedBox(height: 12),
        const Text(
          '예) 선화동, 유천동',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: AppColors.textSub),
        ),
        const SizedBox(height: 110),
        TextField(
          key: const ValueKey('dong_field'),
          controller: _dongController,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            hintText: '동 이름 입력',
            hintStyle: TextStyle(color: Color(0xFFADB5BD)),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.only(top: 8, bottom: 4),
            counterText: "",
          ),
          maxLength: 7,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_isNextEnabled) _handleNext();
          },
        ),
        Container(width: double.infinity, height: 2, color: AppColors.primary),
      ],
    );
  }
}
