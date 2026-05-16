import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/vault_service.dart';
import 'package:dash_mobile/widgets/dash_button.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isReady => _controller.text.length == 4;

  Future<void> _save() async {
    if (!_isReady) return;
    setState(() => _isLoading = true);
    final pin = _controller.text;
    try {
      await StorageService.savePin(pin);
      await _syncPinToVault(pin);
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  Future<void> _syncPinToVault(String newPin) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final keyMap = await StorageService.getKeyMap();
      if (keyMap.isNotEmpty) {
        // 기존 키가 있으면 모두 새 PIN으로 재암호화하여 Vault 갱신
        final firstEntry = keyMap.entries.first;
        await VaultService.syncKey(user.uid, firstEntry.key, firstEntry.value, newPin);
        for (final entry in keyMap.entries.skip(1)) {
          await VaultService.syncKey(user.uid, entry.key, entry.value, newPin);
        }
      } else {
        // keyMap이 비어있어도 빈 Vault를 서버에 생성하여 salt를 확립
        // → 이후 form_screen에서 syncKey 호출 시 같은 salt를 재사용하므로 PIN 일관성 보장
        await VaultService.initEmptyVault(user.uid, newPin);
      }
    } catch (e) {
      debugPrint('❌ PinSetupScreen: vault sync error: $e');
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
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              const Text(
                '보안 PIN 번호를\n설정해주세요',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'PC의 확장 프로그램에서 로그인할 때 필요해요.\n작성한 DB 내용은 서버가 읽을 수 없도록 암호화되기 때문에, 상담원님만의 고유 PIN 번호로 인증해야 해요',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSub,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 48),
              StatefulBuilder(
                builder: (context, setStateSB) {
                  return TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 4,
                    obscureText: _obscure,
                    autofocus: true,
                    style: const TextStyle(
                      fontSize: 28,
                      letterSpacing: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    onChanged: (_) => setState(() {}),
                    textAlign: TextAlign.left,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '_ _ _ _',
                      hintStyle: const TextStyle(
                        fontSize: 28,
                        letterSpacing: 12,
                        fontWeight: FontWeight.bold,
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
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: const Color(0xFFADB5BD),
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => _save(),
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                _controller.text.isEmpty
                    ? '숫자 4자리를 입력해주세요'
                    : _isReady
                        ? '입력 완료'
                        : '${4 - _controller.text.length}자리 더 입력해주세요',
                style: TextStyle(
                  fontSize: 13,
                  color: _isReady ? AppColors.primary : AppColors.textSub,
                  fontWeight: FontWeight.w500,
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
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : DashButton(
                      onTap: _isReady ? _save : null,
                      text: 'PIN 설정 완료',
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
}
