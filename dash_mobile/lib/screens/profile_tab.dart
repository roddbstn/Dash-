import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/analytics_service.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/privacy_policy_screen.dart';
import 'package:dash_mobile/user_guide_screen.dart';
import 'package:dash_mobile/extension_guide_screen.dart';
import 'package:dash_mobile/security_detail_screen.dart';
import 'package:dash_mobile/terms_screen.dart';
import 'package:dash_mobile/widgets/home_widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dash_mobile/vault_service.dart';
import 'package:dash_mobile/pin_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileTab extends StatefulWidget {
  final String? userName;
  final bool isProfileLoading;
  final bool notificationsEnabled;
  final List<dynamic> cases;
  final List<dynamic> drafts;
  final List<dynamic> notifications;
  final void Function(String newName) onNameChanged;
  final void Function(bool enabled) onNotificationsChanged;
  final void Function() onResetComplete;
  final void Function(List<dynamic> cases) onCasesChanged;
  final List<dynamic> counselors;
  final void Function(String message) onShowToast;
  final bool extensionLoggedIn;

  const ProfileTab({
    super.key,
    required this.userName,
    required this.isProfileLoading,
    required this.notificationsEnabled,
    required this.cases,
    required this.drafts,
    required this.notifications,
    required this.counselors,
    required this.onNameChanged,
    required this.onNotificationsChanged,
    required this.onResetComplete,
    required this.onCasesChanged,
    required this.onShowToast,
    this.extensionLoggedIn = true,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _isProfileLoading = false;

  @override
  void initState() {
    super.initState();
    _isProfileLoading = widget.isProfileLoading;
  }

  void _showExtensionGuide(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExtensionGuideScreen()),
    );
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: widget.userName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '이름 수정',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '입력한 성함은 공유된 DB에 \'작성자\'로 표시됩니다.\n정확한 실명을 입력해주세요.',
              style: TextStyle(fontSize: 13, color: Color(0xFF8B95A1), height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 10,
              decoration: const InputDecoration(
                hintText: '실명을 입력해주세요',
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFFADB5BD)),
                counterText: "",
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFF2F4F6)),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
              autofocus: true,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '취소',
              style: TextStyle(
                color: Color(0xFFADB5BD),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(context);
              setState(() {
                _isProfileLoading = true;
              });
              final user = FirebaseAuth.instance.currentUser;
              final success = await ApiService.updateUserProfile(
                user?.uid ?? '',
                newName,
                user?.email,
              );
              if (success) {
                widget.onNameChanged(newName);
                // 기존 케이스들의 user_name도 서버에 갱신 (syncCase가 서버 프로필 이름 사용)
                for (final c in widget.cases) {
                  ApiService.syncCase(c);
                }
                widget.onShowToast('이름이 수정되었습니다.');
              } else {
                widget.onShowToast('이름 수정에 실패했습니다.');
              }
              setState(() {
                _isProfileLoading = false;
              });
            },
            child: const Text(
              '저장',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value == false) {
      // 알림 끄기 시 확인 모달 노출
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            '푸시 알림 off',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: const Text(
            'DB 검토 완료 및 중요 소식에 대한\n푸시 알림을 받지 않으시겠습니까?',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSub,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                '취소',
                style: TextStyle(
                  color: Color(0xFFADB5BD),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                '확인',
                style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        widget.onNotificationsChanged(false);
        widget.onShowToast('알림이 비활성화되었습니다.');
      }
    } else {
      // 알림 켜기
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        widget.onNotificationsChanged(true);
        widget.onShowToast('푸시 알림이 활성화되었습니다. ✨');
      } else {
        widget.onShowToast('알림 권한이 거부되어 있습니다. 설정에서 허용해주세요.');
      }
    }
  }

  Future<bool?> _showLogoutConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            '로그아웃',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: const Text(
            '정말 로그아웃 하시겠습니까?',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSub,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                '취소',
                style: TextStyle(
                  color: Color(0xFFADB5BD),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                '확인',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showDeleteAccountConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            '계정 탈퇴',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: const Text(
            '정말 탈퇴하시겠습니까?\n계정은 복구되지 않아요.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSub,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                '아니오',
                style: TextStyle(
                  color: Color(0xFFADB5BD),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                '탈퇴하기',
                style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final email = user.email;
    try {
      // [1] 서버 데이터(사례, 볼트 등) 삭제 요청 — 실패 시 1회 재시도
      bool serverDeleted = await ApiService.deleteUser(uid, email: email);
      if (!serverDeleted) {
        await Future.delayed(const Duration(seconds: 2));
        serverDeleted = await ApiService.deleteUser(uid, email: email);
        if (!serverDeleted) {
          debugPrint('⚠️ [DELETE] 서버 데이터 삭제 실패 — 로컬 데이터만 정리 후 탈퇴 진행');
        }
      }

      // [2] Firebase Auth 계정 삭제 시도
      try {
        await user.delete();
      } catch (e) {
        debugPrint('🔒 Firebase Auth delete require re-auth: $e');
        // 보안상 바로 삭제가 안 될 수 있지만, 서버 데이터는 위에서 지웠으므로 진행
      }

      // [3] 세션 파괴 및 로컬 데이터 초기화
      await StorageService.clearAllData();
      await GoogleSignIn().disconnect().catchError((_) => null);
      await GoogleSignIn().signOut().catchError((_) => null);
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        widget.onShowToast('계정이 정상적으로 탈퇴되었습니다.');
        Navigator.of(context).pushNamedAndRemoveUntil('/onboarding', (route) => false);
      }
    } catch (e) {
      debugPrint('❌ Account deletion error: $e');
      await StorageService.clearAllData();
      await GoogleSignIn().disconnect().catchError((_) => null);
      await GoogleSignIn().signOut().catchError((_) => null);
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        widget.onShowToast('탈퇴 및 로그아웃이 완료되었습니다.');
        Navigator.of(context).pushNamedAndRemoveUntil('/onboarding', (route) => false);
      }
    }
  }

  Future<void> _syncPinToVault(String newPin) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final keyMap = await StorageService.getKeyMap();
      if (keyMap.isEmpty) {
        debugPrint('✅ Vault sync skipped: no keys to sync');
        return;
      }
      final firstEntry = keyMap.entries.first;
      await VaultService.syncKey(user.uid, firstEntry.key, firstEntry.value, newPin);
      for (final entry in keyMap.entries.skip(1)) {
        await VaultService.syncKey(user.uid, entry.key, entry.value, newPin);
      }
      debugPrint('✅ Vault synced with new PIN (${keyMap.length} keys)');
    } catch (e) {
      debugPrint('❌ Error syncing vault with new PIN: $e');
    }
  }

  void _showPinManagementDialog() async {
    final pin = await StorageService.getPin();
    if (!mounted) return;

    // PIN 미설정 상태 → 최초 PIN 생성 모달
    if (pin == null) {
      _showPinCreationDialog();
      return;
    }

    // 서버 vault를 현재 로컬 PIN으로 재동기화 (옛날 PIN 무효화)
    unawaited(_syncPinToVault(pin));

    // PIN 설정 상태 → 기존 PIN 관리 모달
    showDialog(
      context: context,
      builder: (ctx) {
        bool showPin = false;
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              contentPadding: const EdgeInsets.only(left: 24, right: 24, top: 20, bottom: 0),
              actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              title: const Text(
                '보안 PIN 설정',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '현재 설정된 보안 PIN 번호입니다.',
                    style: TextStyle(fontSize: 14, color: AppColors.textSub),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        showPin ? pin : '****',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setStateSB(() => showPin = !showPin),
                        icon: Icon(
                          showPin ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _showPinChangeDialog(pin);
                    },
                    child: const Text(
                      'PIN 변경하기',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _showPinResetWarningDialog();
                    },
                    child: const Text(
                      'PIN 초기화하기',
                      style: TextStyle(
                        color: Color(0xFFADB5BD),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SecurityDetailScreen()),
                    );
                  },
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Text(
                    '→ 왜 설정하나요?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    '닫기',
                    style: TextStyle(
                      color: AppColors.textMain,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPinChangeDialog(String currentPin) {
    final newPinController = TextEditingController();
    bool isLoading = false;
    bool pinComplete = false;
    String? errorMsg;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setStateSB) {
          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('PIN 변경', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '새 PIN 번호를 입력해주세요.\n변경 시 암호화 키도 새 PIN으로 재암호화됩니다.',
                  style: TextStyle(fontSize: 14, color: AppColors.textSub, height: 1.5),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPinController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 4,
                  obscureText: true,
                  autofocus: true,
                  onChanged: (val) {
                    if (val.length == 4 && !pinComplete) {
                      if (val == currentPin) {
                        setStateSB(() => errorMsg = '현재 PIN과 동일해요');
                        return;
                      }
                      setStateSB(() { pinComplete = true; errorMsg = null; });
                      Future.delayed(const Duration(milliseconds: 700), () async {
                        if (!ctx.mounted) return;
                        setStateSB(() => isLoading = true);
                        try {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) { Navigator.pop(ctx); return; }
                          final keyMap = await StorageService.getKeyMap();
                          if (keyMap.isNotEmpty) {
                            for (final entry in keyMap.entries) {
                              await VaultService.syncKey(user.uid, entry.key, entry.value, val);
                            }
                          }
                          await StorageService.savePin(val);
                          if (mounted) {
                            Navigator.pop(ctx);
                            widget.onShowToast('PIN이 변경되었습니다');
                          }
                        } catch (e) {
                          setStateSB(() { isLoading = false; pinComplete = false; errorMsg = '변경 중 오류가 발생했어요'; });
                        }
                      });
                    } else if (val.length < 4) {
                      setStateSB(() { pinComplete = false; errorMsg = null; });
                    }
                  },
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '새 PIN 4자리',
                    errorText: errorMsg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (isLoading)
                  const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                else
                  _PinCompleteIndicatorInline(visible: pinComplete),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소', style: TextStyle(color: AppColors.textSub)),
              ),
            ],
          );
        });
      },
    );
  }

  void _showPinCreationDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool obscure = true;
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              contentPadding: const EdgeInsets.only(left: 24, right: 24, top: 20, bottom: 0),
              actionsPadding: const EdgeInsets.only(right: 16, bottom: 8),
              title: const Text(
                '보안 PIN 생성',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PC의 확장 프로그램에서 로그인할 때 필요해요.\n작성한 DB 내용은 서버가 읽을 수 없도록 암호화되기 때문에, 상담원님만의 고유 PIN 번호로 인증해야 해요',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSub,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 4,
                    obscureText: obscure,
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.left,
                    onChanged: (val) {
                      setStateSB(() {});
                      if (val.length == 4) {
                        setStateSB(() {});
                        Future.delayed(const Duration(milliseconds: 700), () async {
                          if (!ctx.mounted) return;
                          final newPin = controller.text;
                          await StorageService.savePin(newPin);
                          await _syncPinToVault(newPin);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (mounted) widget.onShowToast('PIN이 설정되었습니다.');
                        });
                      }
                    },
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '_ _ _ _',
                      hintStyle: const TextStyle(
                        fontSize: 24,
                        letterSpacing: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFCED4DA),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF2F4F6),
                      contentPadding: const EdgeInsets.only(
                        left: 20, right: 10, top: 20, bottom: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          color: const Color(0xFFADB5BD),
                        ),
                        onPressed: () => setStateSB(() => obscure = !obscure),
                      ),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 8),
                  _PinCompleteIndicatorInline(visible: controller.text.length == 4),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    '취소',
                    style: TextStyle(
                      color: Color(0xFFADB5BD),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPinResetWarningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String input = '';
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.danger,
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '주의사항',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PIN 번호를 초기화하면 모든 사례와 DB가 삭제되며 복구가 불가능해요. 진행하시겠습니까?',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textMain,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "동의하신다면 아래에 '초기화'를 입력해주세요.",
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (val) => setStateSB(() => input = val.trim()),
                    decoration: InputDecoration(
                      hintText: '\'초기화\' 입력',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFBEC4CC),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.danger,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    '취소',
                    style: TextStyle(
                      color: Color(0xFFADB5BD),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: input == '초기화'
                      ? () async {
                          Navigator.pop(ctx);
                          await _executePinReset();
                        }
                      : null,
                  child: Text(
                    '확인',
                    style: TextStyle(
                      color: input == '초기화'
                          ? AppColors.danger
                          : const Color(0xFFADB5BD),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _executePinReset() async {
    // 1. 세션 데이터만 초기화 (동의·온보딩 플래그는 유지)
    await StorageService.clearSessionData();

    // 2. PIN 재설정 필요 플래그 저장 (앱 재실행 시 PinSetupScreen으로 강제 이동)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pin_setup_required', true);

    // 3. 서버 vault 비우기
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await ApiService.deleteAllRecords();
    }

    AnalyticsService.pinReset();
    if (!mounted) return;
    widget.onResetComplete();
    widget.onShowToast('PIN 및 로컬 DB 데이터가 안전하게 완전히 삭제되었습니다.');

    // 4. PIN 설정 화면으로 즉시 이동
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PinSetupScreen()),
        (route) => false,
      );
    }
  }

  Widget _buildNotificationToggleItem() {
    return ListTile(
      enabled: false, // 영역 터치 피드백 비활성화
      leading: const Icon(
        Icons.notifications_none,
        color: AppColors.textMain,
        size: 22,
      ),
      title: const Text(
        '알림 설정',
        style: TextStyle(
          color: AppColors.textMain,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
      ),
      trailing: Transform.scale(
        scale: 0.85,
        child: Switch(
          value: widget.notificationsEnabled,
          onChanged: _toggleNotifications,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.primary,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: const Color(0xFFE5E8EB),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '-';

    // 현재 보유 DB: 기입 완료(Injected)·공유 임시 제외
    final dbCount = widget.drafts
        .where((d) => d['status'] != 'Injected' && d['isShared'] != true)
        .length;
    // 내 사례: self 상담원 소속 사례만
    final selfMatches = widget.counselors.where((c) => c['isSelf'] == true);
    final selfCounselor = selfMatches.isEmpty ? null : selfMatches.first;
    final selfCounselorId = selfCounselor?['id']?.toString();
    final caseCount = widget.cases.where((c) {
      final cid = c['counselorId']?.toString() ?? '';
      return cid.isEmpty || cid == selfCounselorId;
    }).length;
    // 누적 DB: 개인 드래프트 전체 (기입 완료 포함, 공유 DB 제외)
    final totalCreated = widget.drafts.where((d) => d['isShared'] != true).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이름 + 수정 버튼
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              RichText(
                text: TextSpan(
                  text: '${widget.userName ?? '사용자'}님',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    letterSpacing: -0.5,
                    color: Color(0xFF222222),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _showEditNameDialog,
                child: const Icon(Icons.edit, size: 16, color: Color(0xFF8B95A1)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            email,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 20),
          // 확장프로그램 미설치 배너
          if (!widget.extensionLoggedIn) ...[
            _ExtensionBanner(onTap: () => _showExtensionGuide(context)),
            const SizedBox(height: 16),
          ],
          // 통계 카드
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _StatItem(label: '보유 DB', value: '$dbCount개'),
                _StatDivider(),
                _StatItem(label: '보유 사례', value: '$caseCount개'),
                _StatDivider(),
                _StatItem(label: '누적 DB', value: '$totalCreated개'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                  _buildNotificationToggleItem(),
                  const Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: AppColors.border,
                  ),
                  PressableProfileMenuItem(
                    icon: Icons.menu_book_outlined,
                    title: '이용 안내',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const UserGuideScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: AppColors.border,
                  ),
                  PressableProfileMenuItem(
                    icon: Icons.lock_outline,
                    title: '개인정보처리방침',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: AppColors.border,
                  ),
                  PressableProfileMenuItem(
                    icon: Icons.description_outlined,
                    title: '서비스 약관',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TermsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: AppColors.border,
                  ),
                  PressableProfileMenuItem(
                    icon: Icons.password_outlined,
                    title: '보안 PIN 확인',
                    onTap: () {
                      _showPinManagementDialog();
                    },
                  ),
                  const Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: AppColors.border,
                  ),
                  PressableProfileMenuItem(
                    icon: Icons.logout,
                    title: '로그아웃',
                    onTap: () async {
                      final confirmed = await _showLogoutConfirmationDialog();
                      if (confirmed == true) {
                        // 정상 로그아웃 플래그 설정 → authStateChanges 리스너가 cases/PIN 삭제하지 않음
                        StorageService.intentionalLogout = true;
                        // 로그아웃 시 사례·드래프트·PIN·Salt 등 모든 로컬 개인정보 데이터를 완전 파괴 (개인정보 보호법 준수 및 다중 계정 충돌 방지)
                        await StorageService.clearSessionData();
                        // disconnect()는 네트워크 요청이라 hang할 수 있으므로 타임아웃 처리
                        await GoogleSignIn()
                            .disconnect()
                            .timeout(
                              const Duration(seconds: 3),
                              onTimeout: () => null,
                            )
                            .catchError((_) => null);
                        await GoogleSignIn().signOut().catchError((_) => null);
                        await FirebaseAuth.instance.signOut();
                        if (mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            '/onboarding',
                            (route) => false,
                          );
                        }
                      }
                    },
                    isDanger: false,
                  ), // 로그아웃은 이제 검정색
                  const Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: AppColors.border,
                  ),
                  PressableProfileMenuItem(
                    icon: Icons.delete_forever_outlined,
                    title: '계정 탈퇴',
                    onTap: () async {
                      final confirmed =
                          await _showDeleteAccountConfirmationDialog();
                      if (confirmed == true && mounted) {
                        await StorageService.clearAllData();
                        if (mounted) await _deleteAccount();
                      }
                    },
                    isDanger: true,
                  ), // 계정 탈퇴는 빨간색
                ],
              ),
            ),
          ],
        ),
  );
}
}


// ── 확장프로그램 미설치 배너 ────────────────────────────────────────
class _ExtensionBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _ExtensionBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFEEF3FC),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111111),
                    letterSpacing: -0.3,
                    height: 1.35,
                  ),
                  children: [
                    TextSpan(text: 'DASH '),
                    TextSpan(
                      text: '확장프로그램\n',
                      style: TextStyle(color: Color(0xFF1A56DB)),
                    ),
                    TextSpan(text: '아직 설치하지 않으셨네요!'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            // 확장프로그램 단일 아이콘 장식 (오른쪽 및 높이 가운데 배치)
            SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 8,
                    top: -6,
                    child: Opacity(
                      opacity: 0.32,
                      child: Transform.rotate(
                        angle: 30 * pi / 180,
                        child: const Icon(
                          Icons.extension,
                          size: 68,
                          color: Color(0xFF1A56DB),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 30),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Color(0xFF111111), fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111111)),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: const Color(0xFFF2F4F6));
  }
}

// PIN 입력 완료 시 녹색 체크 인디케이터 (다이얼로그용)
class _PinCompleteIndicatorInline extends StatelessWidget {
  final bool visible;
  const _PinCompleteIndicatorInline({required this.visible});

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
                  width: 13,
                  height: 13,
                  decoration: const BoxDecoration(
                    color: Color(0xFF16A34A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 9),
                ),
                const SizedBox(width: 8),
                const Text(
                  '설정 완료',
                  style: TextStyle(
                    fontSize: 13,
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
