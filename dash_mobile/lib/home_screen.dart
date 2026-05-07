import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:dash_mobile/analytics_service.dart';
import 'package:dash_mobile/vault_service.dart';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dash_mobile/widgets/home_widgets.dart';
import 'package:dash_mobile/screens/notification_tab.dart';
import 'package:dash_mobile/screens/profile_tab.dart';
import 'package:dash_mobile/screens/db_history_tab.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dash_mobile/user_guide_screen.dart';

// 로컬 알림 플러그인 초기화
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<dynamic> _drafts = [];
  List<dynamic> _sharedDrafts = [];
  List<dynamic> _cases = [];
  List<dynamic> _notifications = [];
  List<dynamic> _counselors = [];
  String? _selectedCounselorId;
  bool _isSelectionMode = false;
  bool _isPlusPressed = false;
  final List<int> _selectedCaseIds = [];
  late TabController _dbTabController;

  // Debounce _loadData to prevent duplicate card flicker from simultaneous calls
  bool _isLoadingData = false;
  bool _pendingLoadData = false;

  // Real-time event subscription
  StreamSubscription? _eventSub;
  StreamSubscription? _authSub; // 타 기기 계정 삭제 감지용
  bool _notificationsEnabled = true;

  // 로딩 / 네트워크 상태
  bool _isLoadingInitial = true; // 앱 첫 진입 시 로딩 스피너 표시용
  bool _serverReachable = true; // false = 서버 미응답, 오프라인 배너 표시
  bool _isModalOpen = false; // 바텀 모달 열림 여부 (FAB 숨김 제어)

  @override
  void initState() {
    super.initState();
    _dbTabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.screenHome();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) AnalyticsService.setUser(uid);
    _loadData();
    _initRealtime();
    _setupFCM();
    _fetchUserProfile();

    // 다른 기기에서 계정 삭제 시 이 기기도 즉시 로그아웃 처리
    // (이 기기에서 직접 로그아웃하는 경우엔 cases/PIN을 삭제하지 않음)
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && mounted) {
        _eventSub?.cancel();
        if (!StorageService.intentionalLogout) {
          // 원격 계정 삭제 — 모든 로컬 데이터 초기화
          StorageService.clearSessionData().then((_) {
            GoogleSignIn().signOut().catchError((_) {});
          });
        }
        StorageService.intentionalLogout = false;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 App returned to foreground. Resuming SSE...');
      AnalyticsService.appForegrounded();
      _initRealtime();
      _loadData();
      VaultService.retryPendingKeys();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      debugPrint('💤 App backgrounded. Suspending SSE...');
      _eventSub?.cancel();
      _eventSub = null;
    }
  }

  @override
  void dispose() {
    _dbTabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _eventSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  bool _isInitializingSse = false;
  void _initRealtime() async {
    // 이미 SSE가 살아있으면 재연결 불필요
    if (_eventSub != null) return;
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
      _eventSub = ApiService.streamEvents(email).listen(
        (event) {
          final String? ev = event['event'];
          debugPrint('🔔 Server Event Received: $ev');

          // Initial setup/heartbeat event should not trigger a heavy refresh
          if (ev != 'connected') {
            _loadData();
          }
        },
        onDone: () {
          // 스트림이 완전히 종료되면 구독 초기화 (재연결 허용)
          _eventSub = null;
        },
        onError: (_) {
          _eventSub = null;
        },
      );
    }

    _isInitializingSse = false;
  }

  Future<void> _loadData() async {
    // 다른 기기에서 계정 삭제 시 currentUser가 null이 됨 — 즉시 중단
    if (FirebaseAuth.instance.currentUser == null) return;

    // Debounce: if already loading, mark pending and return
    if (_isLoadingData) {
      _pendingLoadData = true;
      return;
    }
    _isLoadingData = true;
    _pendingLoadData = false;

    var localDrafts = await StorageService.getDrafts();
    var cases = await StorageService.getCases();
    var counselors = await StorageService.getCounselors();

    // 상담원이 없으면 기본 "내 사례" 상담원 생성
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (counselors.isEmpty && userId != null) {
      final selfCounselor = {
        'id': 'self_$userId',
        'name': '내 사례',
        'isSelf': true,
        'sortOrder': 0,
      };
      counselors = [selfCounselor];
      await StorageService.saveCounselors(counselors);
      await ApiService.syncCounselor({
        'id': selfCounselor['id'],
        'user_id': userId,
        'name': selfCounselor['name'],
        'is_self': true,
        'sort_order': 0,
      });
    }

    // 서버에서 상담원 복구 (로컬이 비어있을 때)
    if (counselors.length <= 1 && userId != null) {
      final serverCounselors = await ApiService.fetchCounselors(userId);
      if (serverCounselors != null && serverCounselors.length > 1) {
        counselors = serverCounselors.map<Map<String, dynamic>>((c) => {
          'id': c['id'],
          'name': c['name'],
          'isSelf': c['is_self'] == 1 || c['is_self'] == true,
          'sortOrder': c['sort_order'] ?? 0,
        }).toList();
        await StorageService.saveCounselors(counselors);
      }
    }

    // 사례 목록이 비어있으면 (재로그인 후 등) 서버에서 복구
    if (cases.isEmpty) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        final serverCases = await ApiService.fetchCases(userId);
        if (serverCases != null && serverCases.isNotEmpty) {
          cases = serverCases
              .map<Map<String, dynamic>>(
                (c) => {
                  'id': c['id'],
                  'maskedName': c['case_name'],
                  'realName': c['case_name'],
                  'dong': c['dong'] ?? '',
                  'targetSystem': c['target_system_code'] ?? 'NCADS_v2',
                },
              )
              .toList();
          await StorageService.saveCases(cases);
        }
      }
    }

    if (mounted) {
      setState(() {
        _drafts = localDrafts;
        _cases = cases;
        _counselors = counselors;
        if (_selectedCounselorId == null && counselors.isNotEmpty) {
          _selectedCounselorId = counselors[0]['id']?.toString();
        }
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
          AnalyticsService.pendingSyncRetried(
            successCount: pending.length - remaining.length,
            failureCount: remaining.length,
          );
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
        if (userId != null)
          ApiService.fetchNotifications(userId)
        else
          Future.value(<dynamic>[]),
      ]);

      final List? serverRecords = results[0];
      final List serverNotifs = results[1] ?? [];

      if (mounted) {
        setState(() {
          final wasReachable = _serverReachable;
          _serverReachable = serverRecords != null;
          if (wasReachable && !_serverReachable)
            AnalyticsService.offlineBannerShown();
          _notifications = serverNotifs;
        });
      }

      // Background sync(_syncRecordInBackground)가 share_token을 저장했을 수 있으므로
      // 서버 병합 직전 최신 로컬 데이터를 다시 읽어 race condition으로 인한 중복을 방지
      localDrafts = await StorageService.getDrafts();

      if (serverRecords != null &&
          (serverRecords.isNotEmpty || localDrafts.isNotEmpty)) {
        // 공유받은 레코드 분리 (병합 로직에서 제외)
        final List sharedOnly = serverRecords
            .where((s) => s['record_type'] == 'shared')
            .toList();
        final List ownedServerRecords = serverRecords
            .where((s) => s['record_type'] != 'shared')
            .toList();
        if (mounted) {
          setState(() => _sharedDrafts = sharedOnly);
        }

        // 로컬 데이터와 서버 데이터 병합 및 삭제 처리
        List<Map<String, dynamic>> updatedDrafts = [];

        // 1. 서버에 있는 데이터를 기준으로 로컬과 대조하여 병합
        for (var s in ownedServerRecords) {
          final String? serverToken = s['share_token'];
          final String serverId = s['id'].toString();

          final localIdx = localDrafts.indexWhere((l) {
            final String? localToken = l['share_token'];
            final String localId = l['id'].toString();
            final bool isUnsynced = localToken == null || localToken.isEmpty;
            return (serverToken != null && serverToken == localToken) ||
                (serverId == localId) ||
                (isUnsynced && l['caseName'] == s['case_name']);
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
                final encrypter = encrypt.Encrypter(
                  encrypt.AES(key, mode: encrypt.AESMode.cbc),
                );
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
              'reviewed_at': s['reviewed_at'],
              'updated_at': s['updated_at'],
              'service_type': s['service_type'] ?? local['service_type'],
              'service_category': s['service_category'] ?? local['service_category'],
              'service_name': s['service_name'] ?? local['service_name'],
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
              'reviewed_at': s['reviewed_at'],
              'updated_at': s['updated_at'],
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
              // 서버 응답 목록에서 해당 토큰을 명시적으로 못 찾은 경우에만 삭제
              // (서버에 레코드가 있는데 타이밍 문제로 포함 안 됐을 수 있으므로 이중 확인)
              final bool confirmedDeletedOnServer = ownedServerRecords.every(
                (s) => s['share_token'] != localToken,
              );
              if (confirmedDeletedOnServer) {
                debugPrint(
                  '🗑️ Record with token $localToken not found on server (deleted). Removing local copy.',
                );
                // updatedDrafts에 추가하지 않음으로써 로컬에서도 삭제
              } else {
                // 서버에 있는 레코드인데 병합 로직에서 누락된 경우 — 유지
                updatedDrafts.add(local);
              }
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
      final activeTokens = _drafts
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
      // iOS: 포그라운드에서도 시스템 알림 표시 (기본값은 숨김)
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

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

      if (notification != null && mounted) {
        AnalyticsService.notificationReceived(notification.title ?? 'unknown');
        _loadData(); // 알림 리스트 및 배지 상태 갱신

        // Android: 직접 로컬 알림 팝업 표시 (iOS는 setForegroundNotificationPresentationOptions로 처리)
        if (android != null) {
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
        }
      }
    });

    // 6. 알림 클릭으로 앱이 열렸을 때 처리
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🚀 Notification opened app: ${message.data}');
      setState(() => _currentIndex = 1); // 알림 탭으로 이동
    });
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
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FormScreen(
          caseId: caseId,
          caseName: maskedName,
          dong: dong,
          draftId: draftId,
          userName: _userName,
          // 서버 동기화 완료 후 _loadData() 호출 (race condition 방지)
          onSyncComplete: () {
            if (mounted) _loadData();
          },
        ),
      ),
    );
    // pop 직후: 로컬 스토리지만 읽어 즉시 화면 반영 (서버 매칭 없음)
    final freshDrafts = await StorageService.getDrafts();
    final freshCases = await StorageService.getCases();
    if (mounted) {
      setState(() {
        _drafts = freshDrafts;
        _cases = freshCases;
      });
    }
    if (result == true && draftId != null && mounted) {
      _showToast('$maskedName 아동 DB가 수정되었습니다');
    }
  }

  void _showCaseSelectionModal() async {
    setState(() {
      _isSelectionMode = false;
      _selectedCaseIds.clear();
      _isModalOpen = true;
      if (_selectedCounselorId == null && _counselors.isNotEmpty) {
        _selectedCounselorId = _counselors[0]['id']?.toString();
      }
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (modalContext) {
        bool isEditingCounselors = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            // 현재 선택된 상담원의 사례만 필터링
            final filteredCases = _cases.where((c) {
              final cid = c['counselorId']?.toString();
              if (_selectedCounselorId == null) return true;
              // counselorId가 없는 사례는 첫 번째(내 사례) 상담원에 귀속
              if (cid == null || cid.isEmpty) {
                return _counselors.isNotEmpty &&
                    _selectedCounselorId == _counselors[0]['id']?.toString();
              }
              return cid == _selectedCounselorId;
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // ── 드래그 핸들 + 헤더 ─────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE5E8EB),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
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
                                GestureDetector(
                                  onTap: () {
                                    setModalState(() {
                                      isEditingCounselors =
                                          !isEditingCounselors;
                                    });
                                  },
                                  child: Text(
                                    isEditingCounselors ? '완료' : '편집',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isEditingCounselors
                                          ? AppColors.primary
                                          : AppColors.textSub,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'DB를 작성할 사례를 선택해주세요.',
                              style: TextStyle(
                                  fontSize: 14, color: AppColors.textSub),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),

                      // ── 상담원 탭 ──────────────────────────────
                      SizedBox(
                        height: 44,
                        child: isEditingCounselors
                            ? ReorderableListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24),
                                buildDefaultDragHandles: false,
                                onReorder: (oldIdx, newIdx) {
                                  setState(() {
                                    if (newIdx > oldIdx) newIdx--;
                                    final item =
                                        _counselors.removeAt(oldIdx);
                                    _counselors.insert(newIdx, item);
                                  });
                                  setModalState(() {});
                                  StorageService.saveCounselors(_counselors);
                                  ApiService.reorderCounselors(_counselors);
                                },
                                itemCount: _counselors.length,
                                itemBuilder: (ctx, i) {
                                  final c = _counselors[i];
                                  return ReorderableDelayedDragStartListener(
                                    key: ValueKey(c['id']),
                                    index: i,
                                    child: _buildCounselorChip(
                                      c: c,
                                      isSelected: _selectedCounselorId ==
                                          c['id']?.toString(),
                                      isEditing: true,
                                      onTap: null,
                                      onDelete: () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: Colors.white,
                                            surfaceTintColor:
                                                Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        16)),
                                            title: const Text('상담원 삭제',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    fontSize: 16)),
                                            content: const Text(
                                                '해당 상담원을 삭제하시겠어요?\n소속된 사례도 함께 삭제됩니다.',
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    height: 1.5)),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          ctx, false),
                                                  child:
                                                      const Text('아니오')),
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          ctx, true),
                                                  child: const Text('삭제',
                                                      style: TextStyle(
                                                          color: AppColors
                                                              .danger))),
                                            ],
                                          ),
                                        );
                                        if (confirmed == true) {
                                          final cid =
                                              c['id']?.toString() ?? '';
                                          // 소속 사례 삭제
                                          final updatedCases = _cases
                                              .where((cs) =>
                                                  cs['counselorId']
                                                      ?.toString() !=
                                                  cid)
                                              .toList();
                                          await StorageService.saveCases(
                                              updatedCases);
                                          await ApiService.deleteCounselor(
                                              cid);
                                          setState(() {
                                            _counselors.removeWhere((x) =>
                                                x['id']?.toString() == cid);
                                            _cases = updatedCases;
                                            if (_selectedCounselorId ==
                                                cid) {
                                              _selectedCounselorId =
                                                  _counselors.isNotEmpty
                                                      ? _counselors[0]['id']
                                                          ?.toString()
                                                      : null;
                                            }
                                          });
                                          await StorageService.saveCounselors(
                                              _counselors);
                                          setModalState(() {});
                                        }
                                      },
                                    ),
                                  );
                                },
                              )
                            : ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24),
                                itemCount: _counselors.length,
                                itemBuilder: (ctx, i) {
                                  final c = _counselors[i];
                                  return _buildCounselorChip(
                                    c: c,
                                    isSelected: _selectedCounselorId ==
                                        c['id']?.toString(),
                                    isEditing: false,
                                    onTap: () {
                                      setState(() => _selectedCounselorId =
                                          c['id']?.toString());
                                      setModalState(() {});
                                    },
                                    onDelete: null,
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 16),

                      // ── 사례 그리드 ────────────────────────────
                      Expanded(
                        child: filteredCases.isEmpty
                            ? Center(
                                child: Text(
                                  _cases.isEmpty
                                      ? '담당 사례들을 추가해주세요.'
                                      : '이 상담원의 사례가 없어요.',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFFADB5BD),
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              )
                            : Scrollbar(
                                thumbVisibility: true,
                                child: GridView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 0, 20, 16),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 1.6,
                                  ),
                                  itemCount: filteredCases.length,
                                  itemBuilder: (context, index) {
                                    final c = filteredCases[index];
                                    final bool isSelected =
                                        _selectedCaseIds.contains(c['id']);
                                    final int sIndex =
                                        _selectedCaseIds.indexOf(c['id']) +
                                            1;
                                    return PressableCaseCard(
                                      caseData: c,
                                      isSelected: isSelected,
                                      sIndex: sIndex,
                                      isSelectionMode: _isSelectionMode,
                                      onTap: () {
                                        Navigator.pop(modalContext);
                                        _goToForm(
                                          c['realName'],
                                          c['maskedName'],
                                          c['dong'],
                                          caseId: c['id'],
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                      ),

                      // ── 하단 버튼 바 (흰색 구분선) ────────────
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(20, 18, 20, 18),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      final partnerCount = _counselors
                                          .where((c) => c['isSelf'] != true)
                                          .length;
                                      if (partnerCount >= 3) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                          content: Text(
                                              '동행 파트너는 최대 3명까지 추가할 수 있습니다.'),
                                          duration: Duration(seconds: 2),
                                        ));
                                        return;
                                      }
                                      final name =
                                          await _showAddCounselorDialog(
                                              context);
                                      if (name != null && name.isNotEmpty) {
                                        final uid = FirebaseAuth
                                            .instance.currentUser?.uid;
                                        final newCounselor = {
                                          'id':
                                              'c_${DateTime.now().millisecondsSinceEpoch}',
                                          'name': name,
                                          'isSelf': false,
                                          'sortOrder': _counselors.length,
                                        };
                                        setState(() => _counselors
                                            .add(newCounselor));
                                        await StorageService.saveCounselors(
                                            _counselors);
                                        if (uid != null) {
                                          await ApiService.syncCounselor({
                                            'id': newCounselor['id'],
                                            'user_id': uid,
                                            'name': newCounselor['name'],
                                            'is_self': false,
                                            'sort_order':
                                                newCounselor['sortOrder'],
                                          });
                                        }
                                        setModalState(() {});
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(100)),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      '동행 파트너 추가',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CreateCaseScreen(
                                          counselors: _counselors,
                                          initialCounselorId:
                                              _selectedCounselorId,
                                        ),
                                      ),
                                    );
                                    if (result == true) {
                                      await _loadData();
                                      setModalState(() {});
                                      _showToast(
                                          '사례를 추가하였어요. DB를 작성해보세요!');
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: AppColors.textMain,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(100),
                                      side: const BorderSide(
                                          color: Color(0xFFE5E8EB), width: 1),
                                    ),
                                    elevation: 2,
                                    shadowColor:
                                        Colors.black.withValues(alpha: 0.12),
                                  ),
                                  child: const Text(
                                    '사례 추가',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (mounted) {
      setState(() {
        _isSelectionMode = false;
        _selectedCaseIds.clear();
        _isModalOpen = false;
      });
    }
  }

  /// 상담원 칩 위젯
  Widget _buildCounselorChip({
    required Map<String, dynamic> c,
    required bool isSelected,
    required bool isEditing,
    required VoidCallback? onTap,
    required VoidCallback? onDelete,
  }) {
    return Padding(
      key: ValueKey(c['id']),
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: isEditing ? null : onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected && !isEditing ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: isSelected && !isEditing
                      ? AppColors.primary
                      : const Color(0xFFDDE1E7),
                  width: 1.5,
                ),
              ),
              child: Text(
                c['name']?.toString() ?? '',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected && !isEditing
                      ? Colors.white
                      : AppColors.textMain,
                ),
              ),
            ),
          ),
          if (isEditing && onDelete != null && c['isSelf'] != true)
            Positioned(
              top: -6,
              right: 2,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFF222222),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 동행 파트너(상담원) 이름 입력 다이얼로그
  Future<String?> _showAddCounselorDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('동행 파트너 추가',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '최대 3명 · 7글자까지 입력 가능합니다.',
              style: TextStyle(fontSize: 12, color: Color(0xFF868E96)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 7,
              decoration: const InputDecoration(
                hintText: '홍길동 대리님',
                hintStyle: TextStyle(color: Color(0xFFADB5BD)),
                counterStyle: TextStyle(fontSize: 11, color: Color(0xFFADB5BD)),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('추가',
                  style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
  }

  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 0,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 80,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Row(
                  children: [
                    _NavBarItem(
                      icon: const Icon(Icons.home_filled),
                      label: '홈',
                      selected: _currentIndex == 0,
                      onTap: () => setState(() => _currentIndex = 0),
                    ),
                    _NavBarItem(
                      icon: Badge(
                        isLabelVisible: _notifications.any(
                          (n) => n['is_read'] == 0 || n['is_read'] == false,
                        ),
                        backgroundColor: const Color(0xFFFF4D00),
                        child: const Icon(Icons.notifications),
                      ),
                      label: '알림',
                      selected: _currentIndex == 1,
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                    _NavBarItem(
                      icon: const Icon(Icons.history_rounded),
                      label: 'DB 내역',
                      selected: _currentIndex == 2,
                      onTap: () => setState(() => _currentIndex = 2),
                    ),
                    _NavBarItem(
                      icon: const Icon(Icons.person),
                      label: '프로필',
                      selected: _currentIndex == 3,
                      onTap: () => setState(() => _currentIndex = 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_currentIndex == 0) {
      // 첫 진입 로딩 스피너
      if (_isLoadingInitial) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      // 오프라인 배너 + 홈 탭
      return Column(
        children: [
          if (!_serverReachable) _buildOfflineBanner(),
          Expanded(child: _buildHomeTab()),
        ],
      );
    }
    if (_currentIndex == 1)
      return NotificationTab(
        notifications: _notifications,
        drafts: _drafts,
        onRefresh: _loadData,
        onGoToForm: _goToForm,
        onShowToast: _showToast,
        onNotificationRead: (notifId) {
          setState(() {
            final index = _notifications.indexWhere((n) => n['id'] == notifId);
            if (index != -1) {
              _notifications[index]['is_read'] = 1;
            }
          });
        },
      );
    if (_currentIndex == 2)
      return DbHistoryTab(
        injectedDrafts: _drafts
            .where((d) => d['status'] == 'Injected')
            .toList(),
      );
    return ProfileTab(
      userName: _userName,
      isProfileLoading: _isProfileLoading,
      notificationsEnabled: _notificationsEnabled,
      cases: _cases,
      drafts: _drafts,
      notifications: _notifications,
      onNameChanged: (newName) {
        setState(() => _userName = newName);
      },
      onNotificationsChanged: (enabled) {
        setState(() => _notificationsEnabled = enabled);
      },
      onResetComplete: () {
        setState(() {
          _drafts = [];
          _cases = [];
          _notifications = [];
        });
      },
      onCasesChanged: (cases) {
        setState(() => _cases = cases);
      },
      onShowToast: _showToast,
    );
  }

  Widget _buildOfflineBanner() {
    return Material(
      color: const Color(0xFFFFF7ED),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 15,
              color: Color(0xFFB45309),
            ),
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

  String? _userName;
  bool _isProfileLoading = false;

  /// 홈에 표시할 나의 DB 목록 (Injected 제외, 공유받은 임시 로컬 드래프트 제외)
  List<dynamic> get _pendingDrafts => _drafts
      .where((d) => d['status'] != 'Injected' && d['isShared'] != true)
      .toList();

  Future<void> _fetchUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Firebase Auth displayName 또는 로컬 닉네임 우선 표시
    if (_userName == null) {
      final localNickname = await StorageService.getUserNickname();
      if (mounted) {
        setState(() {
          _userName = user.displayName?.isNotEmpty == true
              ? user.displayName
              : localNickname;
        });
      }
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
                      _buildGreetingHeader(),
                      const SizedBox(height: 16),
                      _buildPcGuideBanner(),
                      const SizedBox(height: 10),
                      _buildCtaCard(),
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
                const SizedBox(height: 20),
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
                const SizedBox(height: 20),
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
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 12),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position:
                              Tween<Offset>(
                                begin: const Offset(0, 0.04),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
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

  // ── 좌상단 인사말 + DB 카운트 (CTA 카드 밖)
  Widget _buildGreetingHeader() {
    final int totalDbCount = _pendingDrafts.length + _sharedDrafts.length;
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w400,
          color: Color(0xFF222222),
          letterSpacing: -0.6,
          height: 1.35,
        ),
        children: [
          if (_userName != null && _userName!.trim().isNotEmpty)
            TextSpan(
              text: '$_userName님,',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          if (_userName != null && _userName!.trim().isNotEmpty)
            const TextSpan(text: '\n기입할 DB는 '),
          if (_userName == null || _userName!.trim().isEmpty)
            const TextSpan(text: '기입할 DB는 '),
          TextSpan(
            text: '$totalDbCount개',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 24,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
              decorationThickness: 2.0,
            ),
          ),
          const TextSpan(text: '예요'),
        ],
      ),
    );
  }

  Widget _buildCtaCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
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
          // ── + 버튼 (가운데 정렬, DB 작성 버튼 위)
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
                  color: _isPlusPressed ? const Color(0xFFF2F4F6) : Colors.white,
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
                  size: 40,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DashButton(
            onTap: _showCaseSelectionModal,
            text: 'DB 작성하기',
            backgroundColor: AppColors.primary,
            width: double.infinity,
            height: 60,
          ),
        ],
      ),
    );
  }

  Widget _buildUserGreeting() {
    if (_userName == null || _userName!.trim().isEmpty)
      return const SizedBox.shrink();
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: _userName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF222222),
              letterSpacing: -0.4,
            ),
          ),
          const TextSpan(
            text: '님',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w400,
              color: Color(0xFF8B95A1),
              letterSpacing: -0.4,
            ),
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
        // 1. 좌상단 인사말 + 카운트
        _buildGreetingHeader(),
        const SizedBox(height: 20),
        // 2. 배너 (CTA 바로 위)
        _buildPcGuideBanner(),
        const SizedBox(height: 10),
        // 3. CTA 카드 (배너 아래)
        _buildCtaCard(),
      ],
    );
  }

  Widget _buildPcGuideBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UserGuideScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF1B2340), Color(0xFF2A3F80)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // 아이콘 컨테이너
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.computer_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            // 텍스트
            const Expanded(
              child: Text(
                'PC에서 DB 확인하려면?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 화살표 버튼
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDbList({
    bool isPad = false,
    double padWidth = 0,
    int crossAxisCount = 3,
  }) {
    final pendingDrafts = _pendingDrafts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 탭 메뉴 (카카오T 스타일, 좌정렬) ──────────────────
        TabBar(
          controller: _dbTabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: const Color(0xFF222222),
          indicatorWeight: 2.5,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: const Color(0xFF222222),
          unselectedLabelColor: const Color(0xFF8B95A1),
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
          ),
          dividerColor: AppColors.border,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.only(right: 24, bottom: 2),
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: const [
            Tab(text: '나의 DB'),
            Tab(text: '공유받은 DB'),
          ],
        ),
        const SizedBox(height: 16),

        // ── 탭 콘텐츠 ─────────────────────────────────────────
        AnimatedBuilder(
          animation: _dbTabController,
          builder: (context, _) {
            final isMyDb = _dbTabController.index == 0;
            if (isMyDb) {
              // 나의 DB 탭
              if (pendingDrafts.isNotEmpty) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      children: pendingDrafts.asMap().entries.map<Widget>((entry) {
                        final idx = entry.key;
                        final d = entry.value;
                        final foundCase = _cases.cast<Map<String, dynamic>?>().firstWhere(
                          (c) =>
                              c?['realName'] == d['caseName'] ||
                              c?['maskedName'] == d['caseName'],
                          orElse: () => null,
                        );
                        final dong = foundCase != null ? foundCase['dong'] : '미지정';
                        return _buildDraftCardInBox(d, dong, index: idx, isLast: idx == pendingDrafts.length - 1);
                      }).toList(),
                    ),
                  ),
                );
              } else {
                return _buildEmptyHint('사례를 선택해 DB를 만들어주세요');
              }
            } else {
              // 공유받은 DB 탭
              if (_sharedDrafts.isNotEmpty) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      children: _sharedDrafts.asMap().entries.map<Widget>((entry) {
                        final idx = entry.key;
                        final d = entry.value;
                        return _buildSharedDraftCardInBox(d, isLast: idx == _sharedDrafts.length - 1);
                      }).toList(),
                    ),
                  ),
                );
              } else {
                return _buildEmptyHint('동행자에게 DB 공유를 요청하세요');
              }
            }
          },
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildEmptyHint(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFFADB5BD),
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildDraftCardInBox(dynamic d, String dong, {int index = 0, bool isLast = false}) {
    final foundCase = _cases.cast<Map<String, dynamic>?>().firstWhere(
      (c) =>
          c?['realName'] == d['caseName'] || c?['maskedName'] == d['caseName'],
      orElse: () => null,
    );

    // 해당 사례의 상담원 이름 조회
    final counselorId = foundCase?['counselorId']?.toString();
    final counselor = counselorId != null
        ? _counselors.cast<Map<String, dynamic>?>().firstWhere(
            (c) => c?['id']?.toString() == counselorId,
            orElse: () => null,
          )
        : (_counselors.isNotEmpty ? _counselors[0] as Map<String, dynamic>? : null);
    final counselorName = counselor?['name']?.toString();

    return SwipeableDraftCard(
      key: ValueKey(d['id']),
      d: d,
      index: index,
      isLast: isLast,
      counselorName: counselorName,
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

  Widget _buildSharedDraftCardInBox(dynamic d, {bool isLast = false}) {
    final String caseName = d['case_name'] ?? d['caseName'] ?? '미지정';
    final String authorName = d['author_name'] ?? '담당자';
    final String? shareToken = d['share_token'];
    final String? encKey = d['encryption_key']?.toString();
    final String recordId = d['id'].toString();
    final String shareUrl = shareToken != null
        ? '${ApiService.serverUrl}/?token=$shareToken${(encKey != null && encKey.isNotEmpty) ? '&key=$encKey' : ''}'
        : '';

    return SwipeableSharedDraftCard(
      key: ValueKey('shared_$recordId'),
      caseName: caseName,
      authorName: authorName,
      shareUrl: shareUrl,
      isLast: isLast,
      onTap: () async {
        final dong = d['dong']?.toString() ?? '미지정';
        final localDrafts = await StorageService.getDrafts();

        // 이미 로컬에 같은 share_token 드래프트가 있으면 재사용
        Map<String, dynamic>? localDraft;
        if (shareToken != null) {
          localDraft = localDrafts.cast<Map<String, dynamic>?>().firstWhere(
            (l) => l?['share_token']?.toString() == shareToken,
            orElse: () => null,
          );
        }

        // 없으면 서버 레코드 데이터로 로컬 드래프트 생성
        if (localDraft == null) {
          final newId = DateTime.now().millisecondsSinceEpoch;
          localDraft = {
            'id': newId,
            'caseName': caseName,
            'dong': dong,
            'status': 'Draft',
            'isShared': true, // 나의 DB 목록에 중복 노출 방지용
            'share_token': shareToken,
            'encryption_key': encKey,
            'target': d['target'] ?? '피해아동',
            'method': d['method'] ?? '방문',
            'provision_type': d['provision_type'] ?? '제공',
            'service_type': d['service_type'] ?? '아보전',
            'service_name': d['service_name'] ?? '',
            'service_category': d['service_category'] ?? '',
            'location': d['location'] ?? '기관내',
            'travelTime': (d['travel_time'] ?? d['travelTime'] ?? '30').toString(),
            'serviceCount': (d['service_count'] ?? d['serviceCount'] ?? '1').toString(),
            'serviceDescription': d['service_description'] ?? d['serviceDescription'] ?? '',
            'agentOpinion': d['agent_opinion'] ?? d['agentOpinion'] ?? '',
            'startTime': d['start_time'] ?? d['startTime'],
            'endTime': d['end_time'] ?? d['endTime'],
          };
          await StorageService.saveDrafts([...localDrafts, localDraft]);
        }

        if (mounted) {
          _goToForm(
            caseName,
            caseName,
            dong,
            caseId: d['case_id'] ?? d['id'],
            draftId: int.tryParse(localDraft['id'].toString()),
          );
        }
      },
      onDelete: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              '목록에서 삭제',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            content: const Text(
              '공유받은 DB를 목록에서 삭제할까요?',
              style: TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  '삭제',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          final ok = await ApiService.removeSharedRecord(recordId);
          if (ok && mounted) {
            setState(() {
              _sharedDrafts.removeWhere((s) => s['id'].toString() == recordId);
            });
            return true;
          }
        }
        return false;
      },
    );
  }
}

class _NavBarItem extends StatefulWidget {
  final Widget icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavBarItem> createState() => _NavBarItemState();
}

class _NavBarItemState extends State<_NavBarItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? const Color(0xFF222222) : const Color(0xFFBEC7D0);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.90 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(
                data: IconThemeData(color: color, size: 24),
                child: widget.icon,
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
