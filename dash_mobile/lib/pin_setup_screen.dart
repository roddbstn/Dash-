import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/vault_service.dart';
import 'package:dash_mobile/analytics_service.dart';
import 'package:dash_mobile/widgets/dash_loading.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  bool _pinComplete = false;
  bool _saveCalled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isReady => _controller.text.length == 4;

  Future<void> _save() async {
    if (_saveCalled || !_isReady) return;
    _saveCalled = true;
    setState(() => _isLoading = true);
    final pin = _controller.text;
    try {
      await StorageService.savePin(pin);
      AnalyticsService.pinSet();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pin_setup_required');
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await StorageService.setRegistered(uid);
      await _syncPinToVault(pin);
    } catch (_) {}
    if (mounted) {
      // '/' 대신 '/home'으로 직접 이동 — StreamBuilder 재구독 시 auth null emit으로
      // onboarding 화면이 깜빡이거나 고착되는 문제 방지
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    }
  }

  Future<void> _syncPinToVault(String newPin) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final keyMap = await StorageService.getKeyMap();
      if (keyMap.isNotEmpty) {
        for (final entry in keyMap.entries) {
          await VaultService.syncKey(user.uid, entry.key, entry.value, newPin);
        }
      } else {
        final restored = await VaultService.decryptVault(newPin, user.uid);
        if (restored != null && restored.isNotEmpty) {
          for (final entry in restored.entries) {
            await StorageService.saveKeyToMap(entry.key, entry.value as String);
          }
          debugPrint('✅ PinSetupScreen: vault에서 ${restored.length}개 키 복원 완료');
        } else {
          try {
            await VaultService.initEmptyVault(user.uid, newPin, force: true);
          } catch (vaultError) {
            debugPrint('❌ PinSetupScreen: vault 초기화 실패: $vaultError');
            // Vault 초기화 실패 시 사용자에게 알림 (PIN은 저장됐으나 서버 연동 실패)
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('보안 Vault 초기화에 실패했습니다. 네트워크를 확인하고 앱을 재시작해 주세요.'),
                  duration: Duration(seconds: 4),
                ),
              );
            }
          }
        }
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
          // push로 진입(닉네임→PIN)이면 canPop=true → 뒤로가기 자동 표시
          // 재설치 플로우(_PostLoginRouter에서 위젯으로 렌더)면 canPop=false → 버튼 없음
        ),
        body: _isLoading
            ? const DashLoadingOverlay()
            : Padding(
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
                      'PC의 확장 프로그램에서 로그인할 때 필요해요. 앱을 재설치하면 보안을 위해 PIN을 다시 설정해야 해요.',
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
                      onChanged: (val) {
                        setState(() {});
                        if (val.length == 4 && !_pinComplete) {
                          setState(() => _pinComplete = true);
                          Future.delayed(
                            const Duration(milliseconds: 700),
                            _save,
                          );
                        }
                      },
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
                          borderSide: const BorderSide(
                            color: Color(0xFFE9ECEF),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFE9ECEF),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
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
                    const SizedBox(height: 12),
                    _PinCompleteIndicator(visible: _pinComplete),
                    if (!_pinComplete)
                      Text(
                        _controller.text.isEmpty
                            ? '숫자 4자리를 입력해주세요'
                            : '${4 - _controller.text.length}자리 더 입력해주세요',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSub,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ── 녹색 체크 인디케이터 ─────────────────────────────────────────────────────
class _PinCompleteIndicator extends StatelessWidget {
  final bool visible;
  const _PinCompleteIndicator({required this.visible});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween<double>(begin: 0.5, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        ),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: visible
          ? Row(
              key: const ValueKey('check'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Color(0xFF16A34A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 9.5,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '설정 완료',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF16A34A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(key: ValueKey('empty')),
    );
  }
}
