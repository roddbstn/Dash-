import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/vault_service.dart';

class VaultRecoveryScreen extends StatefulWidget {
  /// 복구 완료 후 호출될 콜백 (홈 화면 데이터 리로드용)
  final VoidCallback onRecovered;

  const VaultRecoveryScreen({super.key, required this.onRecovered});

  @override
  State<VaultRecoveryScreen> createState() => _VaultRecoveryScreenState();
}

class _VaultRecoveryScreenState extends State<VaultRecoveryScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isReady => _controller.text.length == 4;

  Future<void> _recover() async {
    final pin = _controller.text;
    if (pin.length != 4) return;
    setState(() { _isLoading = true; _errorMsg = null; });

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) { Navigator.pop(context); return; }

    final vaultMap = await VaultService.decryptVault(pin, userId);
    if (vaultMap == null) {
      setState(() { _isLoading = false; _errorMsg = 'PIN이 맞지 않거나, 복구할 데이터가 없어요'; });
      return;
    }

    for (final entry in vaultMap.entries) {
      await StorageService.saveKeyToMap(entry.key, entry.value.toString());
    }
    await StorageService.savePin(pin);

    if (mounted) {
      Navigator.pop(context);
      widget.onRecovered();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 뒤로가기 제스처 차단
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '나중에',
                  style: TextStyle(color: AppColors.textSub, fontSize: 14),
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                const Text(
                  '암호화 키를\n복구해주세요',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMain,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '앱을 재설치하면 기기에 저장된 보안 데이터가 초기화돼요.\n기존 PIN 번호를 입력하면 내 DB 데이터를 그대로 복구할 수 있어요.',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSub,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 48),
                TextField(
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
                  onChanged: (_) => setState(() { _errorMsg = null; }),
                  onSubmitted: (_) => _recover(),
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
                    errorText: _errorMsg,
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
                      borderSide: BorderSide(
                        color: _errorMsg != null ? Colors.red : const Color(0xFFE9ECEF),
                      ),
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
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      )
                    : SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isReady ? _recover : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            disabledBackgroundColor: const Color(0xFFE9ECEF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            '복구하기',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
