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
  bool _isLoading = false;

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
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await StorageService.saveUserNickname(name);
      final user = FirebaseAuth.instance.currentUser;
      await user?.updateDisplayName(name);
      await ApiService.updateUserProfile(user?.uid ?? '', name, user?.email);
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PinSetupScreen()),
      );
    }
  }

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
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 60),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _buildContent(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _isLoading
          ? null
          : Container(
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
                    onTap: _isEnabled ? _save : null,
                    text: '완료',
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

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          '상담원 님의\n성함을 입력해주세요',
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
          '동행자에게 보여질 이름이에요',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: AppColors.textSub),
        ),
        const SizedBox(height: 80),
        TextField(
          controller: _controller,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            hintText: '이름 입력',
            hintStyle: TextStyle(color: Color(0xFF8B95A1)),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.only(top: 8, bottom: 4),
            counterText: '',
          ),
          maxLength: 10,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_isEnabled) _save();
          },
        ),
        Container(width: double.infinity, height: 2, color: AppColors.primary),
      ],
    );
  }
}
