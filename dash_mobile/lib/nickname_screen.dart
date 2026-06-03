import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/widgets/dash_button.dart';
import 'package:dash_mobile/pin_setup_screen.dart';

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isEnabled = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _isEnabled = _controller.text.trim().isNotEmpty);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _isSaving = true);

    // 저장은 백그라운드로 처리 (PIN 설정에 닉네임 불필요)
    final user = FirebaseAuth.instance.currentUser;
    StorageService.saveUserNickname(name).catchError((_) {});
    user?.updateDisplayName(name).catchError((_) {});
    ApiService.updateUserProfile(user?.uid ?? '', name, user?.email).catchError((_) {});

    if (mounted) {
      // 슬라이드 전환으로 즉시 이동
      await Navigator.of(context).push(_buildPinSlideRoute());
      // 뒤로가기로 돌아왔을 때 재시도 가능하도록 초기화
      if (mounted) setState(() => _isSaving = false);
    }
  }

  PageRouteBuilder<void> _buildPinSlideRoute() => PageRouteBuilder<void>(
    pageBuilder: (_, __, ___) => const PinSetupScreen(),
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 280),
  );

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
          automaticallyImplyLeading: false,
        ),
        body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 48),
                    const Text(
                      '상담원님의\n성함을 입력해주세요',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMain,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '동행자에게 보여질 이름이에요.',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSub,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 48),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      maxLength: 8,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      onSubmitted: (_) {
                        if (_isEnabled) _save();
                      },
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '이름 입력',
                        suffix: Text(
                          '${_controller.text.length}/8',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFADB5BD),
                          ),
                        ),
                        hintStyle: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFCED4DA),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE9ECEF)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE9ECEF)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
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
                      onTap: (_isEnabled && !_isSaving) ? _save : null,
                      text: '완료',
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
