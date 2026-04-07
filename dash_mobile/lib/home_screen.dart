import 'package:flutter/material.dart';
import 'dart:async';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/create_case_screen.dart';
import 'package:dash_mobile/form_screen.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:dash_mobile/widgets/dash_button.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dash_mobile/privacy_policy_screen.dart';
import 'package:dash_mobile/terms_screen.dart';
import 'package:dash_mobile/user_guide_screen.dart';

// 로컬 알림 플러그인 초기화
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<dynamic> _drafts = [];
  List<dynamic> _cases = [];
  List<dynamic> _notifications = [];
  bool _isSelectionMode = false;
  bool _isPlusPressed = false;
  final List<int> _selectedCaseIds = [];

  // Debounce _loadData to prevent duplicate card flicker from simultaneous calls
  bool _isLoadingData = false;
  bool _pendingLoadData = false;

  // Real-time event subscription
  StreamSubscription? _eventSub;
  bool _notificationsEnabled = true;

  // 로딩 / 네트워크 상태
  bool _isLoadingInitial = true;   // 앱 첫 진입 시 로딩 스피너 표시용
  bool _serverReachable = true;    // false = 서버 미응답, 오프라인 배너 표시

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _initRealtime();
    _setupFCM();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 App returned to foreground. Resuming SSE...');
      _initRealtime();
      _loadData();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      debugPrint('💤 App backgrounded. Suspending SSE...');
      _eventSub?.cancel();
      _eventSub = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventSub?.cancel();
    super.dispose();
  }

  bool _isInitializingSse = false;
  void _initRealtime() async {
    if (_isInitializingSse) return;
    _isInitializingSse = true;

    // Wait for login state stabilization
    User? user = FirebaseAuth.instance.currentUser;
    int retries = 0;
    while (user == null && retries < 5) {
      await Future.delayed(const Duration(seconds: 1));
      user = FirebaseAuth.instance.currentUser;
      retries++;
    }

    final email = user?.email;
    if (email != null) {
      debugPrint('🚀 Initializing SSE for email: $email');
      _eventSub?.cancel();
      _eventSub = ApiService.streamEvents(email).listen((event) {
        final String? ev = event['event'];
        debugPrint('🔔 Server Event Received: $ev');

        // Initial setup/heartbeat event should not trigger a heavy refresh
        if (ev != 'connected') {
          _loadData();
        }
      });
    }

    _isInitializingSse = false;
  }

  Future<void> _loadData() async {
    // Debounce: if already loading, mark pending and return
    if (_isLoadingData) {
      _pendingLoadData = true;
      return;
    }
    _isLoadingData = true;
    _pendingLoadData = false;

    final localDrafts = await StorageService.getDrafts();
    final cases = await StorageService.getCases();

    if (mounted) {
      setState(() {
        _drafts = localDrafts;
        _cases = cases;
        _isLoadingInitial = false;
      });
    }

    // Background Sync for offline drafts
    try {
      final pending = await StorageService.getPendingSyncs();
      if (pending.isNotEmpty) {
        bool syncedAny = false;
        List<dynamic> remaining = [];
        for (var data in pending) {
          final clientId = data['client_draft_id'];
          // Remove client_draft_id from payload before sending
          final payload = Map<String, dynamic>.from(data)
            ..remove('client_draft_id');
          final token = await ApiService.syncRecord(payload);

          if (token != null) {
            syncedAny = true;
            final idx = localDrafts.indexWhere((d) => d['id'] == clientId);
            if (idx != -1) {
              localDrafts[idx]['share_token'] = token;
              localDrafts[idx]['status'] = 'Synced';
            }
          } else {
            remaining.add(data);
          }
        }

        if (syncedAny) {
          await StorageService.saveDrafts(localDrafts);
          await StorageService.savePendingSyncs(remaining);
          if (mounted) {
            setState(() {
              _drafts = localDrafts;
            });
            _showToast('오프라인 기록이 자동 동기화되었습니다. ✨');
          }
        }
      }
    } catch (e) {
      debugPrint('Background Sync Error: $e');
    }

    // 서버에서 최신 상태 가져오기 (records + notifications 병렬 요청)
    try {
      final String? userId = FirebaseAuth.instance.currentUser?.uid;

      final results = await Future.wait([
        ApiService.fetchRecords(),
        if (userId != null) ApiService.fetchNotifications(userId) else Future.value(<dynamic>[]),
      ]);

      final serverRecords = results[0] as List<dynamic>?;
      final serverNotifs = results[1] as List<dynamic>;

      if (mounted) {
        setState(() {
          _serverReachable = serverRecords != null;
          _notifications = serverNotifs;
        });
      }

      if (serverRecords != null && (serverRecords.isNotEmpty || localDrafts.isNotEmpty)) {
        // 로컬 데이터와 서버 데이터 병합 및 삭제 처리
        List<Map<String, dynamic>> updatedDrafts = [];

        // 1. 서버에 있는 데이터를 기준으로 로컬과 대조하여 병합
        for (var s in serverRecords) {
          final String? serverToken = s['share_token'];
          final String serverId = s['id'].toString();

          final localIdx = localDrafts.indexWhere((l) {
            final String? localToken = l['share_token'];
            final String localId = l['id'].toString();
            return (serverToken != null && serverToken == localToken) ||
                (serverId == localId);
          });

          if (localIdx != -1) {
            // 로컬에 이미 있으면 병합 (상태 업데이트 및 데이터 보정)
            final local = localDrafts[localIdx];
            String finalDescription = local['serviceDescription'] ?? '';
            String finalOpinion = local['agentOpinion'] ?? '';

            if (s['service_description'] != null &&
                s['service_description'].toString().isNotEmpty) {
              finalDescription = s['service_description'];
            }
            if (s['agent_opinion'] != null &&
                s['agent_opinion'].toString().isNotEmpty) {
              finalOpinion = s['agent_opinion'];
            }

            // [E2EE] 복호화 로직 (동일)
            final String? blob = s['encrypted_blob'];
            final String? keyStr = local['encryption_key'];
            if (blob != null && keyStr != null && blob.contains(':')) {
              try {
                final parts = blob.split(':');
                final iv = encrypt.IV.fromBase64(parts[0]);
                final encrypted = encrypt.Encrypted.fromBase64(parts[1]);
                final key = encrypt.Key.fromUtf8(
                  keyStr.padRight(32).substring(0, 32),
                );
                final encrypter = encrypt.Encrypter(encrypt.AES(key));
                final decrypted = encrypter.decrypt(encrypted, iv: iv);
                final decryptedData =
                    jsonDecode(decrypted) as Map<String, dynamic>;
                finalDescription =
                    decryptedData['serviceDescription'] ??
                    decryptedData['service_description'] ??
                    finalDescription;
                finalOpinion =
                    decryptedData['agentOpinion'] ??
                    decryptedData['agent_opinion'] ??
                    finalOpinion;
              } catch (e) {
                debugPrint('E2EE Decryption failed on merge: $e');
              }
            }

            updatedDrafts.add({
              ...local,
              'status': s['status'],
              'share_token': s['share_token'],
              'treatment': s['target_system_code'] ?? local['treatment'],
              'caseName': s['case_name'] ?? local['caseName'],
              'dong': s['dong'] ?? local['dong'],
              'serviceDescription': finalDescription,
              'agentOpinion': finalOpinion,
              'startTime':
                  (s['status'] == 'Reviewed' && s['start_time'] != null)
                  ? s['start_time']
                  : (local['startTime'] ?? s['start_time']),
              'endTime': (s['status'] == 'Reviewed' && s['end_time'] != null)
                  ? s['end_time']
                  : (local['endTime'] ?? s['end_time']),
              'serviceCount': (s['status'] == 'Reviewed')
                  ? (s['service_count'] ?? local['serviceCount'])
                  : (local['serviceCount'] ?? s['service_count']),
              'travelTime': (s['status'] == 'Reviewed')
                  ? (s['travel_time'] ?? local['travelTime'])
                  : (local['travelTime'] ?? s['travel_time']),
            });
          } else {
            // 로컬에 없는데 서버에만 있는 경우 (다른 기기에서 작성했거나 재설치 등)
            // 비암호화 정보들만이라도 복구하여 목록에 표시
            updatedDrafts.add({
              'id': s['id'],
              'caseName': s['case_name'],
              'dong': s['dong'],
              'target': s['target'] ?? '',
              'provision_type': s['provision_type'],
              'method': s['method'],
              'service_type': s['service_type'],
              'service_name': s['service_name'],
              'location': s['location'],
              'startTime': s['start_time'],
              'endTime': s['end_time'],
              'serviceCount': s['service_count'],
              'travelTime': s['travel_time'],
              'serviceDescription': s['service_description'] ?? '',
              'agentOpinion': s['agent_opinion'] ?? '',
              'share_token': s['share_token'],
              'status': s['status'],
              'is_server_only': true, // 로컬 복구 데이터 표시용
            });
          }
        }

        // 2. 로컬에만 있는 데이터(동기화 전인 것들)들 보존
        for (var local in localDrafts) {
          final String? localToken = local['share_token'];
          final alreadyAdded = updatedDrafts.any(
            (u) =>
                (localToken != null && u['share_token'] == localToken) ||
                (local['id'].toString() == u['id'].toString()),
          );

          if (!alreadyAdded) {
            // 서버 목록에는 없지만 로컬에 있는 경우
            if (localToken == null || localToken.isEmpty) {
              // 아직 동기화 전인 데이터는 당연히 유지
              updatedDrafts.add(local);
            } else {
              // 서버에 토큰이 있는데 서버 응답에 없으면 서버에서 삭제된 것이므로 로컬에서도 제거
              debugPrint(
                '🗑️ Record with token $localToken not found on server (deleted). Removing local copy.',
              );
              // updatedDrafts에 추가하지 않음으로써 로컬에서도 삭제
            }
          }
        }

        if (mounted) {
          setState(() {
            _drafts = updatedDrafts;
          });
          await StorageService.saveDrafts(updatedDrafts);
        }
      }
    } catch (e) {
      debugPrint('Sync failed: $e');
    }

    // Sync active tokens AFTER merge is complete so we never send stale/empty list
    try {
      // Use the FINAL merged _drafts (which already includes server-only records)
      final activeTokens =
          _drafts
              .map((d) => d['share_token'] as String?)
              .where((t) => t != null && t.isNotEmpty)
              .cast<String>()
              .toList();

      // Guard: never send an empty list right after a save — it would wipe all server records
      if (activeTokens.isNotEmpty) {
        await ApiService.syncActiveRecords(activeTokens);
      }
    } catch (e) {
      debugPrint('Orphan cleanup error: $e');
    }

    // Release debounce lock and re-run if a call came in while we were loading
    _isLoadingData = false;
    if (_pendingLoadData) {
      _pendingLoadData = false;
      _loadData();
    }
  }

  Future<void> _setupFCM() async {
    final messaging = FirebaseMessaging.instance;

    // 1. Android 알림 채널 설정 (포그라운드 팝업용) — 권한 요청보다 먼저 실행
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.max,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // 2. 플러그인 초기화
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );

    // 3. 권한 요청 — 최초 실행 시 3초 유예 (온보딩 직후 팝업 방지)
    final prefs = await SharedPreferences.getInstance();
    final permissionAsked = prefs.getBool('fcm_permission_asked') ?? false;
    if (!permissionAsked) {
      await Future.delayed(const Duration(seconds: 3));
      await prefs.setBool('fcm_permission_asked', true);
    }

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 알림 권한 상태에 따른 토글 초기화
    if (mounted) {
      setState(() {
        _notificationsEnabled =
            settings.authorizationStatus == AuthorizationStatus.authorized;
      });
    }

    // 4. 토큰 획득 및 서버 저장
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      final token = await messaging.getToken();
      final user = FirebaseAuth.instance.currentUser;
      if (token != null && user != null) {
        await ApiService.saveFcmToken(user.uid, token, user.email);
        debugPrint('🔥 FCM Token Registered: ${token.substring(0, 8)}...');
      }
    }

    // 5. 포그라운드 메시지 리스너 (앱이 켜져 있을 때)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null && mounted) {
        // 시스템 알림 팝업 표시
        flutterLocalNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: Importance.max,
              priority: Priority.high,
              ticker: 'ticker',
            ),
          ),
        );

        _loadData(); // 알림 리스트 및 배지 상태 갱신
      }
    });

    // 6. 알림 클릭으로 앱이 열렸을 때 처리
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🚀 Notification opened app: ${message.data}');
      setState(() => _currentIndex = 1); // 알림 탭으로 이동
    });
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
        setState(() => _notificationsEnabled = false);
        _showToast('알림이 비활성화되었습니다.');
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
        setState(() => _notificationsEnabled = true);
        _showToast('푸시 알림이 활성화되었습니다. ✨');
      } else {
        _showToast('알림 권한이 거부되어 있습니다. 설정에서 허용해주세요.');
      }
    }
  }

  void _showCaseDeleteConfirmation(BuildContext modalContext) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '정말 삭제할까요?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  '삭제하면 복구할 수 없습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.textSub),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFF2F4F6),
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '아니오',
                          style: TextStyle(
                            color: AppColors.textSub,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          _confirmCaseDelete();
                          Navigator.pop(context); // Close dialog
                          // Navigator.pop(modalContext); // Keep modal open as requested
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '네',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showDraftDeleteConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'DB 삭제',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: const Text(
            '이 DB 작성을 삭제할까요?\n삭제하면 복구할 수 없습니다.',
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
                '삭제',
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
    return result ?? false;
  }

  void _confirmCaseDelete() async {
    final remainingCases = _cases
        .where((c) => !_selectedCaseIds.contains(c['id']))
        .toList();
    await StorageService.saveCases(remainingCases);
    setState(() {
      _cases = remainingCases;
      _isSelectionMode = false;
      _selectedCaseIds.clear();
    });
  }

  void _deleteDraft(int draftId) async {
    final drafts = await StorageService.getDrafts();
    final draftToDelete = drafts.firstWhere(
      (d) => d['id'] == draftId,
      orElse: () => null,
    );

    drafts.removeWhere((d) => d['id'] == draftId);
    await StorageService.saveDrafts(drafts);

    if (draftToDelete != null && draftToDelete['share_token'] != null) {
      ApiService.deleteRecord(draftToDelete['share_token']);
    }

    setState(() {
      _drafts = drafts;
    });
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: const Color(0xFF222222),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 40, left: 60, right: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _goToForm(
    String name,
    String maskedName,
    String dong, {
    required dynamic caseId,
    int? draftId,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FormScreen(
          caseId: caseId,
          caseName: maskedName,
          dong: dong,
          draftId: draftId,
        ),
      ),
    );
    // 무조건 로드하여 알림 상태 동기화
    _loadData();
  }

  void _showCaseSelectionModal() async {
    setState(() {
      _isSelectionMode = false;
      _selectedCaseIds.clear();
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollController) {
                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (_isSelectionMode) {
                          setState(() {
                            _isSelectionMode = false;
                            _selectedCaseIds.clear();
                          });
                          setModalState(() {});
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5E8EB),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      '사례 선택',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (_cases.isNotEmpty)
                                      GestureDetector(
                                        onTap: () {
                                          if (_isSelectionMode &&
                                              _selectedCaseIds.isNotEmpty) {
                                            _showCaseDeleteConfirmation(
                                              modalContext,
                                            );
                                          } else {
                                            setState(() {
                                              _isSelectionMode =
                                                  !_isSelectionMode;
                                              if (!_isSelectionMode)
                                                _selectedCaseIds.clear();
                                            });
                                            setModalState(() {});
                                          }
                                        },
                                        child: Text(
                                          _isSelectionMode
                                              ? (_selectedCaseIds.isEmpty
                                                    ? '취소'
                                                    : '삭제')
                                              : '편집',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: _isSelectionMode
                                                ? AppColors.danger
                                                : AppColors.textSub,
                                            fontWeight: _isSelectionMode
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (_cases.isNotEmpty)
                                  const Text(
                                    'DB를 작성할 사례를 선택해주세요.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSub,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          Expanded(
                            child: _cases.isEmpty
                                ? const Center(
                                    child: Text(
                                      '담당 사례들을 추가해주세요.',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Color(0xFFADB5BD),
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  )
                                : GridView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      0,
                                      20,
                                      40,
                                    ),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                          childAspectRatio: 1.6,
                                        ),
                                    itemCount: _cases.length,
                                    itemBuilder: (context, index) {
                                      final c = _cases[index];
                                      final bool isSelected = _selectedCaseIds
                                          .contains(c['id']);
                                      final int sIndex =
                                          _selectedCaseIds.indexOf(c['id']) + 1;
                                      return _PressableCaseCard(
                                        caseData: c,
                                        isSelected: isSelected,
                                        sIndex: sIndex,
                                        isSelectionMode: _isSelectionMode,
                                        onTap: () {
                                          if (_isSelectionMode) {
                                            setState(() {
                                              if (isSelected) {
                                                _selectedCaseIds.remove(
                                                  c['id'],
                                                );
                                              } else {
                                                _selectedCaseIds.add(c['id']);
                                              }
                                            });
                                            setModalState(() {});
                                          } else {
                                            Navigator.pop(modalContext);
                                            _goToForm(
                                              c['realName'],
                                              c['maskedName'],
                                              c['dong'],
                                              caseId: c['id'],
                                            );
                                          }
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 20,
                      bottom: 40,
                      child: ElevatedButton(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CreateCaseScreen(),
                            ),
                          );
                          if (result == true) {
                            await _loadData();
                            setModalState(() {});
                            _showToast('사례를 생성하였어요. DB를 작성해보세요!');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.textMain,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                            side: const BorderSide(
                              color: Color(0xFFE5E8EB),
                              width: 1,
                            ),
                          ),
                          elevation: 4,
                          shadowColor: Colors.black.withValues(alpha: 0.2),
                        ),
                        child: const Text(
                          '+ 사례 생성',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    setState(() {
      _isSelectionMode = false;
      _selectedCaseIds.clear();
    });
  }

  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: Image.asset(
          'assets/icons/logo.png',
          height: 28, // height can be adjusted later if needed
          fit: BoxFit.contain,
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))
          ],
        ),
        child: SafeArea(
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: BottomNavigationBar(
                elevation: 0,
                currentIndex: _currentIndex,
                onTap: (index) => setState(() => _currentIndex = index),
                selectedItemColor: AppColors.primary,
                unselectedItemColor: const Color(0xFF8B95A1),
                backgroundColor: Colors.transparent, // Uses container's white
                items: [
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.home_filled),
                    label: '홈',
                  ),
                  BottomNavigationBarItem(
                    icon: Badge(
                      label: null, // 숫자 대신 점만 표시
                      isLabelVisible: _notifications.any(
                        (n) => n['is_read'] == 0 || n['is_read'] == false,
                      ),
                      backgroundColor: const Color(0xFFFF4D00), // 주황빛 도는 빨간색
                      child: const Icon(Icons.notifications),
                    ),
                    label: '알림',
                  ),
                  const BottomNavigationBarItem(icon: Icon(Icons.person), label: '프로필'),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: _currentIndex != 0
          ? null
          : Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CreateCaseScreen(),
                    ),
                  );
                  if (result == true) {
                    _loadData();
                    _showToast('사례를 생성하였어요. DB를 작성해보세요!');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.textMain,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                    side: const BorderSide(color: Color(0xFFE5E8EB), width: 1),
                  ),
                  elevation: 4,
                  shadowColor: Colors.black.withValues(alpha: 0.2),
                ),
                child: const Text(
                  '+ 사례 생성',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_currentIndex == 0) {
      // 첫 진입 로딩 스피너
      if (_isLoadingInitial) {
        return const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
      // 오프라인 배너 + 홈 탭
      return Column(
        children: [
          if (!_serverReachable) _buildOfflineBanner(),
          Expanded(child: _buildHomeTab()),
        ],
      );
    }
    if (_currentIndex == 1) return _buildNotificationTab();
    return _buildProfileTab();
  }

  Widget _buildOfflineBanner() {
    return Material(
      color: const Color(0xFFFFF7ED),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 15, color: Color(0xFFB45309)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '서버에 연결하지 못했습니다. 로컬 저장 기록만 표시됩니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF92400E),
                  letterSpacing: -0.1,
                ),
              ),
            ),
            GestureDetector(
              onTap: _loadData,
              child: const Text(
                '재시도',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTab() {
    // 중복 제거: 동일한 record_token(또는 사례명)에 대해 가장 최신 알림만 남김
    final Map<String, dynamic> uniqueNotifs = {};
    for (var n in _notifications) {
      if (n['is_read'] == 0 || n['is_read'] == false) {
        // 토큰이 없으면 사례명을 키로 사용 (구형 알림 대응)
        final String key = n['record_token'] ?? "name_${n['case_name']}";

        if (!uniqueNotifs.containsKey(key)) {
          uniqueNotifs[key] = n;
        } else {
          // 이미 존재하면 생성 시각이 더 최신인 것으로 교체
          final existingTime = uniqueNotifs[key]['created_at'] ?? '';
          final newTime = n['created_at'] ?? '';
          if (newTime.compareTo(existingTime) > 0) {
            uniqueNotifs[key] = n;
          }
        }
      }
    }

    final unreadNotifs = uniqueNotifs.values.toList();
    unreadNotifs.sort(
      (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
    );

    if (unreadNotifs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 64,
              color: AppColors.border.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 16),
            const Text(
              '아직 도착한 알림이 없어요',
              style: TextStyle(
                color: Color(0xFFADB5BD),
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Text(
            '알림',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF222222),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            color: AppColors.primary,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: unreadNotifs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final n = unreadNotifs[index];
                final String caseName = n['case_name'] ?? '미지정';

                String dateStr = '';
                if (n['created_at'] != null) {
                  final dt = DateTime.parse(n['created_at']).toLocal();
                  dateStr = DateFormat('MM/dd HH:mm').format(dt);
                }

                final String? nToken = n['record_token'];
                final int? notifId = n['id'];

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    debugPrint('🔔 Notification tapped: $notifId');
                    // 1. 알림 읽음 처리 (서버 및 로컬 즉시 반영)
                    if (notifId != null) {
                      ApiService.markNotificationRead(notifId);
                      setState(() {
                        // 로컬 알림 리스트에서 해당 알림 읽음 처리 (배지 점을 즉시 없애기 위함)
                        final index = _notifications.indexWhere(
                          (n) => n['id'] == notifId,
                        );
                        if (index != -1) {
                          _notifications[index]['is_read'] = 1;
                        }
                      });
                    }

                    debugPrint('🔍 Found drafts length: ${_drafts.length}');
                    // 2. 기록 매칭 및 이동
                    Map<String, dynamic>? foundDraft;
                    for (var d in _drafts) {
                      final bool matchToken =
                          (nToken != null && d['share_token'] == nToken);
                      final bool matchName = (d['caseName'] == caseName);
                      if (matchToken || matchName) {
                        foundDraft = Map<String, dynamic>.from(d);
                        break;
                      }
                    }
                    debugPrint('🔍 Matched draft: $foundDraft');

                    if (foundDraft != null) {
                      final dong = foundDraft['dong'] ?? '';
                      _goToForm(
                        foundDraft['caseName'] ?? caseName,
                        foundDraft['caseName'] ?? caseName,
                        dong,
                        caseId: foundDraft['case_id'] ?? foundDraft['id'],
                        draftId: foundDraft['id'],
                      );
                    } else {
                      _showToast('해당 사례를 찾을 수 없어요. 😊');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF2F4F6)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F7FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.assignment_turned_in_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "$caseName 아동",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "DB 내용이 검토 완료되었어요.\n수정 사항을 확인해 보세요.",
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: Color(0xFF4E5968),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    dateStr,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFADB5BD),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const Row(
                                    children: [
                                      Text(
                                        '자세히 보기',
                                        style: TextStyle(
                                          color: Color(0xFF8B95A1),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 16,
                                        color: Color(0xFFADB5BD),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  String? _userName;
  bool _isProfileLoading = false;

  Future<void> _fetchUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_userName == null) {
      setState(() {
        _userName = user.displayName;
      });
    }
    try {
      final serverUser = await ApiService.fetchUser(user.uid);
      if (serverUser != null && mounted) {
        setState(() {
          _userName = serverUser['name'];
        });
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    }
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: _userName);
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
        content: TextField(
          controller: controller,
          maxLength: 10, // ✅ 최대 10글자 제한
          decoration: const InputDecoration(
            hintText: '실명을 입력해주세요',
            hintStyle: TextStyle(fontSize: 14, color: Color(0xFFADB5BD)),
            counterText: "", // ✅ 글자수 카운터 숨기기
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
                setState(() {
                  _userName = newName;
                });
                _showToast('이름이 수정되었습니다.');
              } else {
                _showToast('이름 수정에 실패했습니다.');
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

  Widget _buildProfileTab() {
    if (_userName == null && !_isProfileLoading) {
      _fetchUserProfile();
    }

    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '-';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 54,
              backgroundColor: Color(0xFFF2F4F6),
              child: Icon(Icons.person, size: 54, color: Color(0xFF8B95A1)),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${_userName ?? '사용자'}님',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _showEditNameDialog,
                  icon: const Icon(
                    Icons.edit,
                    size: 20,
                    color: Color(0xFF8B95A1),
                  ),
                  tooltip: '이름 수정',
                ),
              ],
            ),
            Text(
              email,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSub,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 48),
            Container(
              width: double.infinity,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
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
                  _PressableProfileMenuItem(
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
                  _PressableProfileMenuItem(
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
                  _PressableProfileMenuItem(
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
                  _PressableProfileMenuItem(
                    icon: Icons.logout,
                    title: '로그아웃',
                    onTap: () async {
                      final confirmed = await _showLogoutConfirmationDialog();
                      if (confirmed == true) {
                        await StorageService.clearAllData();
                        await GoogleSignIn().disconnect().catchError(
                          (_) => null,
                        );
                        await GoogleSignIn().signOut().catchError((_) => null);
                        await FirebaseAuth.instance.signOut();
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
                  _PressableProfileMenuItem(
                    icon: Icons.delete_forever_outlined,
                    title: '계정 탈퇴',
                    onTap: () async {
                      final confirmed =
                          await _showDeleteAccountConfirmationDialog();
                      if (confirmed == true) {
                        await StorageService.clearAllData();
                        await _deleteAccount();
                      }
                    },
                    isDanger: true,
                  ), // 계정 탈퇴는 빨간색
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      // [1] 서버 데이터(상례, 볼트 등) 삭제 요청 (404 무시)
      await ApiService.deleteUser(uid, email: email);

      // [2] Firebase Auth 계정 삭제 시도
      try {
        await user.delete();
      } catch (e) {
        debugPrint('🔒 Firebase Auth delete require re-auth: $e');
        // 보안상 바로 삭제가 안 될 수 있지만, 서버 데이터는 위에서 지웠으므로 진행
      }

      // [3] 세션 파괴 (가장 중요: 다음에 계정 선택창이 뜨도록)
      // signOut() 전에 토스트 표시 — signOut 후 context가 unmount될 수 있음
      if (mounted) _showToast('계정이 정상적으로 탈퇴되었습니다.');
      await GoogleSignIn().disconnect().catchError((_) => null);
      await GoogleSignIn().signOut().catchError((_) => null);
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('❌ Account deletion error: $e');
      // 에러 발생 시에도 일단 세션은 강제 종료
      if (mounted) _showToast('탈퇴 및 로그아웃이 완료되었습니다.');
      await GoogleSignIn().disconnect().catchError((_) => null);
      await GoogleSignIn().signOut().catchError((_) => null);
      await FirebaseAuth.instance.signOut();
    }
  }

  void _showPinManagementDialog() async {
    final pin = await StorageService.getPin();
    if (!mounted) return;

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
              actionsPadding: const EdgeInsets.only(right: 16, bottom: 8),
              title: const Text(
                '보안 PIN 관리',
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
                        pin == null ? '미설정 상태' : (showPin ? pin : '****'),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                        ),
                      ),
                      if (pin != null)
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
    // 1. Wipe local storage (clears PIN, cases, drafts, salt)
    await StorageService.clearAllData();

    // 2. Wipe server vault memory specifically to prevent decrypting old data
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await ApiService.saveVault(user.uid, '', '');
      // 3. Delete all active records from the server to prevent them from showing back up
      await ApiService.syncActiveRecords([]);
    }

    setState(() {
      _drafts = [];
      _cases = [];
      _notifications = [];
    });

    _showToast('PIN 및 로컬 DB 데이터가 안전하게 완전히 삭제되었습니다.');
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
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      trailing: Transform.scale(
        scale: 0.85,
        child: Switch(
          value: _notificationsEnabled,
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

  Widget _buildHomeTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet = constraints.maxWidth > 650;
        final bool isLandscape = constraints.maxWidth > constraints.maxHeight;
        final bool isPadLandscape = isTablet && isLandscape;
        final bool isPadPortrait = isTablet && !isLandscape;

        Widget layoutContent;
        if (isPadLandscape) {
          layoutContent = KeyedSubtree(
            key: const ValueKey('pad-landscape'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 66,
                  child: _buildDbList(
                    isPad: true,
                    padWidth: (constraints.maxWidth - 40 - 16) * 0.66,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 34,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCtaCard(),
                      const SizedBox(height: 12),
                      _InfoBanner(),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else if (isPadPortrait) {
          layoutContent = KeyedSubtree(
            key: const ValueKey('pad-portrait'),
            child: Column(
              children: [
                _buildGuideAndCta(),
                const SizedBox(height: 40),
                _buildDbList(
                  isPad: true,
                  padWidth: constraints.maxWidth - 40,
                  crossAxisCount: 2,
                ),
                const SizedBox(height: 100),
              ],
            ),
          );
        } else {
          layoutContent = KeyedSubtree(
            key: const ValueKey('mobile'),
            child: Column(
              children: [
                _buildGuideAndCta(),
                const SizedBox(height: 40),
                _buildDbList(isPad: false),
                const SizedBox(height: 100),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          )),
                          child: child,
                        ),
                      );
                    },
                    child: layoutContent,
                  ),
                ),
              ),
            ),
          ),
        ); // RefreshIndicator
      },
    ); // LayoutBuilder
  }

  Widget _buildCtaCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFF90C2FF).withValues(alpha: 0.55),
            Colors.white,
          ],
          stops: const [0.0, 0.65],
        ),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTapDown: (_) => setState(() => _isPlusPressed = true),
            onTapUp: (_) => setState(() => _isPlusPressed = false),
            onTapCancel: () => setState(() => _isPlusPressed = false),
            onTap: _showCaseSelectionModal,
            child: AnimatedScale(
              scale: _isPlusPressed ? 0.94 : 1.0,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isPlusPressed
                      ? const Color(0xFFF2F4F6)
                      : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: _isPlusPressed
                      ? []
                      : [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: const Icon(
                  Icons.add_circle_outline,
                  color: AppColors.primary,
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          DashButton(
            onTap: _showCaseSelectionModal,
            text: '사무실 밖에서 DB 쓰기',
            backgroundColor: AppColors.primary,
            width: double.infinity,
            height: 60,
          ),
        ],
      ),
    );
  }

  Widget _buildGuideAndCta() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoBanner(),
        const SizedBox(height: 15),
        _buildCtaCard(),
      ],
    );
  }

  Widget _buildDbList({bool isPad = false, double padWidth = 0, int crossAxisCount = 3}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_drafts.isNotEmpty) ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '대기 중인 DB 목록',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (isPad && padWidth > 0)
            Builder(
              builder: (context) {
                double spacing = 16.0;
                // Calculate item width exactly using the given area
                double itemWidth = (padWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;
                // We add a tiny floor to avoid layout constraints overflow
                itemWidth = itemWidth.floorToDouble();
                
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: _drafts.map((d) {
                    final foundCase = _cases
                        .cast<Map<String, dynamic>?>()
                        .firstWhere(
                          (c) =>
                              c?['realName'] == d['caseName'] ||
                              c?['maskedName'] == d['caseName'],
                          orElse: () => null,
                        );
                    final dong = foundCase != null ? foundCase['dong'] : '미지정';
                    return SizedBox(
                      width: itemWidth,
                      child: _buildDraftCard(d, dong),
                    );
                  }).toList(),
                );
              },
            )
          else ...[
            ..._drafts.map((d) {
              final foundCase = _cases
                  .cast<Map<String, dynamic>?>()
                  .firstWhere(
                    (c) =>
                        c?['realName'] == d['caseName'] ||
                        c?['maskedName'] == d['caseName'],
                    orElse: () => null,
                  );
              final dong = foundCase != null ? foundCase['dong'] : '미지정';
              return _buildDraftCard(d, dong);
            }),
          ],
          const SizedBox(height: 30),
        ] else ...[
          const SizedBox(height: 60),
          const Center(
            child: Text(
              '사례를 선택해 DB를 만들어주세요',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFFADB5BD),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 60),
        ],
      ],
    );
  }

  Widget _buildDraftCard(dynamic d, String dong) {
    final foundCase = _cases.cast<Map<String, dynamic>?>().firstWhere(
      (c) =>
          c?['realName'] == d['caseName'] || c?['maskedName'] == d['caseName'],
      orElse: () => null,
    );

    return _SwipeableDraftCard(
      key: ValueKey(d['id']),
      d: d,
      onTap: () => _goToForm(
        foundCase?['realName'] ?? d['caseName'],
        d['caseName'],
        dong,
        caseId: foundCase?['id'] ?? d['id'],
        draftId: d['id'],
      ),
      onDelete: () async {
        final confirmed = await _showDraftDeleteConfirmation();
        if (confirmed) {
          _deleteDraft(d['id']);
          return true;
        }
        return false;
      },
    );
  }
}

class _PressableCaseCard extends StatefulWidget {
  final Map<String, dynamic> caseData;
  final bool isSelected;
  final int sIndex;
  final bool isSelectionMode;
  final VoidCallback onTap;

  const _PressableCaseCard({
    required this.caseData,
    required this.isSelected,
    required this.sIndex,
    required this.isSelectionMode,
    required this.onTap,
  });

  @override
  State<_PressableCaseCard> createState() => _PressableCaseCardState();
}

class _PressableCaseCardState extends State<_PressableCaseCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: _isPressed ? const Color(0xFFF2F4F6) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: widget.isSelected
                ? Border.all(color: AppColors.primary, width: 2)
                : Border.all(color: Colors.black.withValues(alpha: 0.05)),
            boxShadow: _isPressed
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.caseData['maskedName'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.caseData['dong'],
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSub.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isSelectionMode)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isSelected
                          ? AppColors.primary
                          : Colors.white,
                      border: Border.all(
                        color: widget.isSelected
                            ? AppColors.primary
                            : AppColors.border,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        widget.isSelected ? '${widget.sIndex}' : '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatefulWidget {
  const _InfoBanner();

  @override
  State<_InfoBanner> createState() => _InfoBannerState();
}

class _InfoBannerState extends State<_InfoBanner> {
  bool _isLeftPressed = false;
  bool _isRightPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isAnyPressed = _isLeftPressed || _isRightPressed;

    return AnimatedScale(
      scale: isAnyPressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: isAnyPressed
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Left: 이용 안내
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _isLeftPressed = true),
                  onTapUp: (_) => setState(() => _isLeftPressed = false),
                  onTapCancel: () => setState(() => _isLeftPressed = false),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const UserGuideScreen(),
                      ),
                    );
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    decoration: BoxDecoration(
                      color: _isLeftPressed
                          ? const Color(0xFFF2F4F6)
                          : Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text('📋', style: TextStyle(fontSize: 17)),
                        SizedBox(width: 7),
                        Text(
                          '이용 안내',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF222222),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Vertical divider
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 1,
                  color: AppColors.bg, // 배경색과 동일한 색으로 변경
                ),
              ),
              // Right: 개인 정보
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _isRightPressed = true),
                  onTapUp: (_) => setState(() => _isRightPressed = false),
                  onTapCancel: () => setState(() => _isRightPressed = false),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    );
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    decoration: BoxDecoration(
                      color: _isRightPressed
                          ? const Color(0xFFF2F4F6)
                          : Colors.white,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text('🔒', style: TextStyle(fontSize: 17)),
                        SizedBox(width: 7),
                        Text(
                          '개인 정보',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF222222),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeableDraftCard extends StatefulWidget {
  final dynamic d;
  final VoidCallback onTap;
  final Future<bool> Function() onDelete;

  const _SwipeableDraftCard({
    super.key,
    required this.d,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_SwipeableDraftCard> createState() => _SwipeableDraftCardState();
}

class _SwipeableDraftCardState extends State<_SwipeableDraftCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0;
  static const double _maxSwipe = 90.0;
  bool _isCardPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(
      begin: 0,
      end: -_maxSwipe,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta!;
      if (_dragOffset > 0) _dragOffset = 0;
      if (_dragOffset < -_maxSwipe * 1.2) _dragOffset = -_maxSwipe * 1.2;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) async {
    if (_dragOffset < -_maxSwipe * 0.7) {
      _controller.forward(from: _dragOffset / -_maxSwipe);
      _dragOffset = -_maxSwipe;
      final confirmed = await widget.onDelete();
      if (!confirmed && mounted) {
        _controller.reverse();
        setState(() => _dragOffset = 0);
      }
    } else if (_dragOffset < -_maxSwipe / 3) {
      _controller.forward(from: _dragOffset / -_maxSwipe);
      _dragOffset = -_maxSwipe;
    } else {
      _controller.reverse(from: _dragOffset / -_maxSwipe);
      _dragOffset = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final offset = _controller.isAnimating ? _animation.value : _dragOffset;
        return AnimatedScale(
          scale: _isCardPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () async {
                          final confirmed = await widget.onDelete();
                          if (!confirmed && mounted) {
                            _controller.reverse();
                            setState(() => _dragOffset = 0);
                          }
                        },
                        child: Container(
                          width: _maxSwipe,
                          height: double.infinity,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.delete,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(offset, 0),
                  child: GestureDetector(
                    onHorizontalDragUpdate: _onHorizontalDragUpdate,
                    onHorizontalDragEnd: _onHorizontalDragEnd,
                    onTapDown: (_) => setState(() => _isCardPressed = true),
                    onTapUp: (_) => setState(() => _isCardPressed = false),
                    onTapCancel: () => setState(() => _isCardPressed = false),
                    onTap: widget.onTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _isCardPressed
                            ? const Color(0xFFF2F4F6)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                        boxShadow: _isCardPressed
                            ? []
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: Builder(builder: (context) {
                        final bool isReviewed = widget.d['status']?.toString().toLowerCase() == 'reviewed';
                        final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

                        // ── 대상 텍스트 ──────────────────────────
                        final targets = widget.d['target'].toString().split(', ');
                        final String targetText = targets.length > 1
                            ? "${targets[0]} 외 ${targets.length - 1}"
                            : widget.d['target'].toString();
                        final String subLine1 = '대상: $targetText | ${widget.d['method'] ?? '방문'}';

                        // ── 제공일시 텍스트 ──────────────────────
                        final startStr = widget.d['startTime'];
                        final endStr = widget.d['endTime'];
                        String subLine2;
                        if (startStr == null || endStr == null) {
                          subLine2 = widget.d['datetime'] ?? '제공일시 미설정';
                        } else {
                          final start = DateTime.tryParse(startStr);
                          final end = DateTime.tryParse(endStr);
                          if (start == null || end == null) {
                            subLine2 = widget.d['datetime'] ?? '제공일시 미설정';
                          } else {
                            final bool isSameDay = start.year == end.year &&
                                start.month == end.month &&
                                start.day == end.day;
                            final days = ['월', '화', '수', '목', '금', '토', '일'];
                            final String startFmt =
                                "${start.month}.${start.day} (${days[start.weekday - 1]}) ${DateFormat('HH:mm').format(start)}";
                            if (isSameDay) {
                              subLine2 = "$startFmt ~ ${DateFormat('HH:mm').format(end)}";
                            } else {
                              final String endFmt =
                                  "${end.month}.${end.day} (${days[end.weekday - 1]}) ${DateFormat('HH:mm').format(end)}";
                              subLine2 = "$startFmt ~ $endFmt";
                            }
                          }
                        }

                        // ── 상태 태그 위젯 ──────────────────────
                        final Widget statusTag = Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isReviewed
                                ? AppColors.successLight
                                : AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: isReviewed
                                      ? AppColors.success
                                      : AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isReviewed ? '검토 완료' : '검토 대기',
                                style: TextStyle(
                                  color: isReviewed
                                      ? AppColors.success
                                      : AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );

                        // ── 가로 모드: 태그를 타이틀 오른쪽에 ────
                        if (isLandscape) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 타이틀 + 태그 (태그는 오른쪽 끝 고정)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${widget.d['caseName']} 아동',
                                      style: const TextStyle(
                                        color: Color(0xFF222222),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  statusTag,
                                ],
                              ),
                              const SizedBox(height: 8),
                              // 서브텍스트 1: 대상 | 방법 (1줄)
                              Text(
                                subLine1,
                                style: const TextStyle(
                                  color: Color(0xFF8B95A1),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              // 서브텍스트 2: 제공일시 (1줄)
                              Text(
                                subLine2,
                                style: const TextStyle(
                                  color: Color(0xFF8B95A1),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          );
                        }

                        // ── 세로 모드: 태그 오른쪽 고정 (기존 구조) ──
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${widget.d['caseName']} 아동',
                                    style: const TextStyle(
                                      color: Color(0xFF222222),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$subLine1\n$subLine2',
                                    style: const TextStyle(
                                      color: Color(0xFF8B95A1),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            statusTag,
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PressableProfileMenuItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDanger;

  const _PressableProfileMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  State<_PressableProfileMenuItem> createState() =>
      _PressableProfileMenuItemState();
}

class _PressableProfileMenuItemState extends State<_PressableProfileMenuItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: _isPressed ? const Color(0xFFF2F4F6) : Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(
              widget.icon,
              color: widget.isDanger ? AppColors.danger : AppColors.textMain,
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  color: widget.isDanger
                      ? AppColors.danger
                      : AppColors.textMain,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.border, size: 20),
          ],
        ),
      ),
    );
  }
}
