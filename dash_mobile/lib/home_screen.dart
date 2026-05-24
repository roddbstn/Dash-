import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:dash_mobile/theme.dart';
import 'package:dash_mobile/storage_service.dart';
import 'package:dash_mobile/form_screen.dart';
import 'package:dash_mobile/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dash_mobile/analytics_service.dart';
import 'package:dash_mobile/vault_service.dart';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dash_mobile/screens/notification_tab.dart';
import 'package:dash_mobile/vault_recovery_screen.dart';
import 'package:dash_mobile/screens/profile_tab.dart';
import 'package:dash_mobile/screens/db_history_tab.dart';
import 'package:dash_mobile/screens/home_tab.dart';
import 'package:dash_mobile/screens/case_selection_modal.dart';
import 'package:dash_mobile/screens/db_type_selection_sheet.dart';
import 'package:intl/intl.dart';

// 로컬 알림 플러그인 초기화
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<dynamic> _drafts = [];
  List<dynamic> _sharedDrafts = [];
  Map<String, String> _keyMap = {};
  List<dynamic> _cases = [];
  List<dynamic> _notifications = [];
  List<dynamic> _counselors = [];
  String? _selectedCounselorId;
  late TabController _dbTabController;

  // Debounce _loadData to prevent duplicate card flicker from simultaneous calls
  bool _isLoadingData = false;
  bool _pendingLoadData = false;

  // Real-time event subscription
  StreamSubscription? _eventSub;
  StreamSubscription? _authSub;
  bool _notificationsEnabled = true;

  // 로딩 / 네트워크 상태
  bool _isLoadingInitial = true;
  bool _serverReachable = true;
  bool _hasPromptedVaultRecovery = false;

  String? _userName;
  final bool _isProfileLoading = false;
  int _currentIndex = 0;

  /// 홈에 표시할 나의 DB 목록 (Injected 제외, 공유받은 임시 로컬 드래프트 제외)
  List<dynamic> get _pendingDrafts => _drafts
      .where((d) => d['status'] != 'Injected' && d['isShared'] != true)
      .toList();

  // ── 라이프사이클 ────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _dbTabController = TabController(length: 2, vsync: this);
    _dbTabController.addListener(() {
      if (!_dbTabController.indexIsChanging) {
        AnalyticsService.dbTabSwitched(
          _dbTabController.index == 0 ? 'my_db' : 'shared_db',
        );
      }
    });
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.screenHome();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) AnalyticsService.setUser(uid);
    _loadData();
    _initRealtime();
    _setupFCM();
    _fetchUserProfile();

    // 다른 기기에서 계정 삭제 시 이 기기도 즉시 로그아웃 처리
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && mounted) {
        _eventSub?.cancel();
        if (!StorageService.intentionalLogout) {
          StorageService.clearSessionData().then((_) {
            GoogleSignIn().signOut().catchError((_) => null);
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

  // ── 실시간 SSE ──────────────────────────────────────────────────

  bool _isInitializingSse = false;
  void _initRealtime() async {
    if (_eventSub != null) return;
    if (_isInitializingSse) return;
    _isInitializingSse = true;

    User? user = FirebaseAuth.instance.currentUser;
    int retries = 0;
    while (user == null && retries < 5) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) { _isInitializingSse = false; return; }
      user = FirebaseAuth.instance.currentUser;
      retries++;
    }

    if (!mounted) { _isInitializingSse = false; return; }
    final email = user?.email;
    if (email != null) {
      debugPrint('🚀 Initializing SSE for email: $email');
      _eventSub = ApiService.streamEvents(email).listen(
        (event) {
          final String? ev = event['event'];
          debugPrint('🔔 Server Event Received: $ev');
          if (ev != 'connected' && mounted) _loadData();
        },
        onDone: () => _eventSub = null,
        onError: (_) => _eventSub = null,
      );
    }
    _isInitializingSse = false;
  }

  // ── 데이터 로딩 및 서버 동기화 ─────────────────────────────────

  Future<void> _loadData() async {
    if (FirebaseAuth.instance.currentUser == null) return;

    if (_isLoadingData) {
      _pendingLoadData = true;
      return;
    }
    _isLoadingData = true;
    _pendingLoadData = false;

    var localDrafts = await StorageService.getDrafts();
    final keyMap = await StorageService.getKeyMap();
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

    // 서버에서 상담원 목록 동기화
    if (userId != null) {
      final serverCounselors = await ApiService.fetchCounselors(userId);
      if (serverCounselors != null && serverCounselors.isNotEmpty) {
        counselors = serverCounselors.map<Map<String, dynamic>>((c) => {
              'id': c['id'],
              'name': c['name'],
              'isSelf': c['is_self'] == 1 || c['is_self'] == true,
              'sortOrder': c['sort_order'] ?? 0,
            }).toList();
        await StorageService.saveCounselors(counselors);
      }
    }

    // 서버에서 사례 목록 동기화
    {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final serverCases = await ApiService.fetchCases(uid);
        if (serverCases != null) {
          cases = serverCases
              .map<Map<String, dynamic>>((c) => {
                    'id': c['id'],
                    'maskedName': c['case_name'],
                    'realName': c['case_name'],
                    'dong': c['dong'] ?? '',
                    'targetSystem':
                        c['target_system_code'] ?? 'NCADS_v2',
                    'counselorId': c['counselor_id']?.toString(),
                  })
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
        _keyMap = keyMap;
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
          final payload = Map<String, dynamic>.from(data)
            ..remove('client_draft_id');
          final token = await ApiService.syncRecord(payload);

          if (token != null) {
            syncedAny = true;
            final idx =
                localDrafts.indexWhere((d) => d['id'] == clientId);
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
            setState(() => _drafts = localDrafts);
            _showToast('오프라인 기록이 자동 동기화되었습니다. ✨');
          }
        }
      }
    } catch (e) {
      debugPrint('Background Sync Error: $e');
    }

    // 서버에서 최신 상태 가져오기 (records + notifications 병렬 요청)
    try {
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      final results = await Future.wait([
        ApiService.fetchRecords(),
        if (uid != null)
          ApiService.fetchNotifications(uid)
        else
          Future.value(<dynamic>[]),
      ]);

      final List? serverRecords = results[0];
      final List serverNotifs = results[1] ?? [];

      if (mounted) {
        setState(() {
          final wasReachable = _serverReachable;
          _serverReachable = serverRecords != null;
          if (wasReachable && !_serverReachable) {
            AnalyticsService.offlineBannerShown();
          }
          _notifications = serverNotifs;
        });
      }

      localDrafts = await StorageService.getDrafts();

      if (serverRecords != null &&
          (serverRecords.isNotEmpty || localDrafts.isNotEmpty)) {
        final List sharedOnly = serverRecords
            .where((s) => s['record_type'] == 'shared')
            .toList();
        final List ownedServerRecords = serverRecords
            .where((s) => s['record_type'] != 'shared')
            .toList();
        if (mounted) {
          setState(() => _sharedDrafts = sharedOnly);
        }

        List<Map<String, dynamic>> updatedDrafts = [];

        for (var s in ownedServerRecords) {
          final String? serverToken = s['share_token'];
          final String serverId = s['id'].toString();

          final localIdx = localDrafts.indexWhere((l) {
            final String? localToken = l['share_token'];
            final String localId = l['id'].toString();
            final bool isUnsynced =
                localToken == null || localToken.isEmpty;
            return (serverToken != null && serverToken == localToken) ||
                (serverId == localId) ||
                (isUnsynced && l['caseName'] == s['case_name']);
          });

          if (localIdx != -1) {
            final local = localDrafts[localIdx];
            String finalDescription =
                local['serviceDescription'] ?? '';
            String finalOpinion = local['agentOpinion'] ?? '';

            if (s['service_description'] != null &&
                s['service_description'].toString().isNotEmpty) {
              finalDescription = s['service_description'];
            }
            if (s['agent_opinion'] != null &&
                s['agent_opinion'].toString().isNotEmpty) {
              finalOpinion = s['agent_opinion'];
            }

            // [E2EE] encryption_key → SecureStorage 자동 마이그레이션
            final String? sToken = s['share_token']?.toString();
            final String? legacyKey = s['encryption_key']?.toString();
            if (sToken != null &&
                legacyKey != null &&
                legacyKey.isNotEmpty &&
                !keyMap.containsKey(sToken)) {
              await StorageService.saveKeyToMap(sToken, legacyKey);
              keyMap[sToken] = legacyKey;
            }

            // [E2EE] 복호화
            final String? blob = s['encrypted_blob'];
            final String? keyStr =
                keyMap[s['share_token']?.toString()];
            if (blob != null &&
                keyStr != null &&
                blob.contains(':')) {
              try {
                final parts = blob.split(':');
                final iv = encrypt.IV.fromBase64(parts[0]);
                final encrypted =
                    encrypt.Encrypted.fromBase64(parts[1]);
                final key = encrypt.Key.fromUtf8(
                    keyStr.padRight(32).substring(0, 32));
                final encrypter = encrypt.Encrypter(
                    encrypt.AES(key, mode: encrypt.AESMode.cbc));
                final decrypted =
                    encrypter.decrypt(encrypted, iv: iv);
                final decryptedData =
                    jsonDecode(decrypted) as Map<String, dynamic>;
                finalDescription =
                    decryptedData['serviceDescription'] ??
                        decryptedData['service_description'] ??
                        finalDescription;
                finalOpinion = decryptedData['agentOpinion'] ??
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
              'treatment':
                  s['target_system_code'] ?? local['treatment'],
              'caseName': s['case_name'] ?? local['caseName'],
              'dong': s['dong'] ?? local['dong'],
              'serviceDescription': finalDescription,
              'agentOpinion': finalOpinion,
              'reviewed_at': s['reviewed_at'],
              'updated_at': s['updated_at'],
              'is_shared_db': s['is_shared_db'] == 1 || s['is_shared_db'] == true,
              'service_type':
                  s['service_type'] ?? local['service_type'],
              'service_category':
                  s['service_category'] ?? local['service_category'],
              'service_name':
                  s['service_name'] ?? local['service_name'],
              'startTime':
                  (s['status'] == 'Reviewed' && s['start_time'] != null)
                      ? s['start_time']
                      : (local['startTime'] ?? s['start_time']),
              'endTime':
                  (s['status'] == 'Reviewed' && s['end_time'] != null)
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
            // 로컬에 없는데 서버에만 있는 경우 (재설치 등)
            final String? reToken = s['share_token']?.toString();
            final String? reKey = s['encryption_key']?.toString();
            if (reToken != null &&
                reKey != null &&
                reKey.isNotEmpty &&
                !keyMap.containsKey(reToken)) {
              await StorageService.saveKeyToMap(reToken, reKey);
              keyMap[reToken] = reKey;
            }
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
              'is_server_only': true,
              'is_shared_db': s['is_shared_db'] == 1 || s['is_shared_db'] == true,
            });
          }
        }

        // 로컬에만 있는 데이터 보존
        for (var local in localDrafts) {
          final String? localToken = local['share_token'];
          final alreadyAdded = updatedDrafts.any(
            (u) =>
                (localToken != null && u['share_token'] == localToken) ||
                (local['id'].toString() == u['id'].toString()),
          );

          if (!alreadyAdded) {
            if (localToken == null || localToken.isEmpty) {
              updatedDrafts.add(local);
            } else {
              final bool confirmedDeletedOnServer =
                  ownedServerRecords.every(
                (s) => s['share_token'] != localToken,
              );
              if (!confirmedDeletedOnServer) {
                updatedDrafts.add(local);
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _drafts = updatedDrafts;
            _keyMap = keyMap;
          });
          await StorageService.saveDrafts(updatedDrafts);
          _checkAndPromptVaultRecovery(keyMap, updatedDrafts);
        }
      }
    } catch (e) {
      debugPrint('Sync failed: $e');
    }

    // 활성 토큰 동기화
    try {
      final activeTokens = _drafts
          .map((d) => d['share_token'] as String?)
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>()
          .toList();
      if (activeTokens.isNotEmpty) {
        await ApiService.syncActiveRecords(activeTokens);
      }
    } catch (e) {
      debugPrint('Orphan cleanup error: $e');
    }

    _isLoadingData = false;
    if (_pendingLoadData) {
      _pendingLoadData = false;
      _loadData();
    }
  }

  // ── FCM 설정 ────────────────────────────────────────────────────

  Future<void> _setupFCM() async {
    final messaging = FirebaseMessaging.instance;

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.max,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings);

    final prefs = await SharedPreferences.getInstance();
    final permissionAsked =
        prefs.getBool('fcm_permission_asked') ?? false;
    if (!permissionAsked) {
      await Future.delayed(const Duration(seconds: 3));
      await prefs.setBool('fcm_permission_asked', true);
    }

    final settings = await messaging.requestPermission(
        alert: true, badge: true, sound: true);

    if (mounted) {
      setState(() {
        _notificationsEnabled = settings.authorizationStatus ==
            AuthorizationStatus.authorized;
      });
    }

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      await messaging.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      final user = FirebaseAuth.instance.currentUser;
      if (token != null && user != null) {
        await ApiService.saveFcmToken(user.uid, token, user.email);
        debugPrint(
            '🔥 FCM Token Registered: ${token.substring(0, 8)}...');
      }
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final targetUserId = message.data['target_user_id'];
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (targetUserId != null && targetUserId != currentUid) return;

      final notification = message.notification;
      if (notification != null && mounted) {
        AnalyticsService.notificationReceived(
            notification.title ?? 'unknown');
        _loadData();
        flutterLocalNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'High Importance Notifications',
              channelDescription:
                  'This channel is used for important notifications.',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );

        // 사례담당자가 "내 DB로 저장" 완료 시 → 알림 탭 갱신
        if (message.data['type'] == 'db_saved_by_case_manager') {
          if (mounted) _loadData();
        }
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
          '🚀 Notification opened app: ${message.data}');
      final targetUserId = message.data['target_user_id'];
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (targetUserId != null && targetUserId != currentUid) return;
      _handleFcmNavigation(message.data);
    });

    final initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      final targetUserId = initialMessage.data['target_user_id'];
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (targetUserId == null || targetUserId == currentUid) {
        _handleFcmNavigation(initialMessage.data);
      }
    }
  }

  void _handleFcmNavigation(Map<String, dynamic> data) {
    final recordToken = data['record_token']?.toString();
    if (recordToken == null || recordToken.isEmpty) {
      setState(() => _currentIndex = 1);
      return;
    }
    final draft = _drafts.cast<Map<String, dynamic>?>().firstWhere(
      (d) => d?['share_token']?.toString() == recordToken,
      orElse: () => null,
    );
    if (draft != null && mounted) {
      setState(() => _currentIndex = 0);
      final caseName = draft['caseName']?.toString() ??
          draft['case_name']?.toString() ??
          '';
      final dong = draft['dong']?.toString() ?? '';
      final caseId = draft['caseId'] ?? draft['case_id'];
      final draftId = int.tryParse(draft['id']?.toString() ?? '');
      _goToForm(caseName, caseName, dong,
          caseId: caseId, draftId: draftId);
    } else {
      setState(() => _currentIndex = 1);
    }
  }

  // ── 사례담당자가 공유 DB 저장 완료 → 삭제 여부 안내 시트 ────────────
  // ── Vault 복구 ──────────────────────────────────────────────────

  void _checkAndPromptVaultRecovery(
      Map<String, String> keyMap, List<dynamic> drafts) {
    if (_hasPromptedVaultRecovery) return;
    if (keyMap.isNotEmpty) return;
    final hasSyncedDrafts = drafts.any((d) =>
        d['share_token'] != null &&
        (d['share_token']?.toString().isNotEmpty ?? false));
    if (!hasSyncedDrafts) return;
    _hasPromptedVaultRecovery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final pin = await StorageService.getPin();
      if (pin != null) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final vaultMap = await VaultService.decryptVault(pin, uid);
          if (vaultMap != null && mounted) {
            for (final entry in vaultMap.entries) {
              await StorageService.saveKeyToMap(
                  entry.key, entry.value.toString());
            }
            debugPrint('✅ Vault auto-recovered silently');
            _loadData();
            return;
          }
        }
      }
      // 앱에서는 Vault 복구 화면 표시 안 함 (PIN은 확장프로그램에서만 요구)
    });
  }

  void _navigateToVaultRecovery() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            VaultRecoveryScreen(onRecovered: _loadData),
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
                parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  // ── 프로필 로딩 ─────────────────────────────────────────────────

  Future<void> _fetchUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_userName == null) {
      final localNickname = await StorageService.getUserNickname();
      if (mounted) {
        setState(() {
          _userName =
              user.displayName?.isNotEmpty == true
                  ? user.displayName
                  : localNickname;
        });
      }
    }
    try {
      final serverUser = await ApiService.fetchUser(user.uid);
      if (serverUser != null && mounted) {
        setState(() => _userName = serverUser['name']);
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    }
  }

  // ── 네비게이션 ──────────────────────────────────────────────────

  void _goToForm(
    String name,
    String maskedName,
    String dong, {
    required dynamic caseId,
    int? draftId,
    bool dismissModalOnSave = false,
  }) async {
    // 신규 DB 생성 시 유형 선택
    DbType? dbType;
    if (draftId == null) {
      dbType = await showDbTypeSelectionSheet(context);
      if (dbType == null) return; // 유저가 시트 닫음
    }

    final isShared = dbType == DbType.shared;
    // 공유할 DB: FormScreen 닫히자마자 dialog를 즉시 띄우기 위한 Completer
    final urlCompleter = isShared ? Completer<String>() : null;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FormScreen(
          caseId: caseId,
          caseName: maskedName,
          dong: dong,
          draftId: draftId,
          userName: _userName,
          isSharedDb: isShared,
          onSyncComplete: () {
            if (mounted) _loadData();
          },
          onSharedDbReady: isShared
              ? (token, key) {
                  final url = '${ApiService.serverUrl}/?token=$token#key=$key';
                  if (!(urlCompleter!.isCompleted)) urlCompleter.complete(url);
                }
              : null,
        ),
      ),
    );

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

    // 저장 버튼으로 돌아온 경우 사례 선택 모달 닫기
    if (result == true && dismissModalOnSave && mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    // 공유할 DB 저장 시 즉시 공유 dialog 표시 (URL은 sync 완료 후 채워짐)
    if (result == true && isShared && urlCompleter != null && mounted) {
      _showShareDialogWithFuture(urlCompleter.future);
    }
  }

  void _showCaseSelectionModal() async {
    await showCaseSelectionModal(
      context: context,
      initialCounselors: _counselors,
      initialCases: _cases,
      initialSelectedCounselorId: _selectedCounselorId,
      onCounselorsChanged: (list) =>
          setState(() => _counselors = List.from(list)),
      onCasesChanged: (list) => setState(() => _cases = List.from(list)),
      onCounselorIdChanged: (id) =>
          setState(() => _selectedCounselorId = id),
      onGoToForm: (name, maskedName, dong, {required caseId, draftId}) {
        _goToForm(name, maskedName, dong,
            caseId: caseId, draftId: draftId, dismissModalOnSave: true);
      },
      onShowToast: _showToast,
      onReloadData: _loadData,
    );
  }

  // ── 삭제 액션 ───────────────────────────────────────────────────

  void _deleteDraft(int draftId) async {
    final drafts = await StorageService.getDrafts();
    final draftToDelete =
        drafts.firstWhere((d) => d['id'] == draftId, orElse: () => null);
    drafts.removeWhere((d) => d['id'] == draftId);
    await StorageService.saveDrafts(drafts);
    if (draftToDelete != null && draftToDelete['share_token'] != null) {
      ApiService.deleteRecord(draftToDelete['share_token']);
    }
    setState(() => _drafts = drafts);
  }

  Future<bool> _deleteSharedDraft(String recordId) async {
    final ok = await ApiService.removeSharedRecord(recordId);
    if (ok && mounted) {
      setState(() {
        _sharedDrafts.removeWhere((s) => s['id'].toString() == recordId);
      });
      return true;
    }
    return false;
  }

  /// 공유받은 DB 카드 탭 핸들러 — StorageService 동기화 후 FormScreen으로 이동
  Future<void> _onSharedDraftTap(dynamic d) async {
    final String caseName = d['case_name'] ?? d['caseName'] ?? '미지정';
    final String? shareToken = d['share_token'];
    final String? encKey =
        shareToken != null ? _keyMap[shareToken] : null;
    final dong = d['dong']?.toString() ?? '미지정';
    final localDrafts = await StorageService.getDrafts();

    String freshDescription =
        d['service_description'] ?? d['serviceDescription'] ?? '';
    String freshOpinion = d['agent_opinion'] ?? d['agentOpinion'] ?? '';

    Map<String, dynamic>? localDraft;
    if (shareToken != null) {
      localDraft = localDrafts
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (l) => l?['share_token']?.toString() == shareToken,
            orElse: () => null,
          );
    }

    if (localDraft != null) {
      localDraft = {
        ...localDraft,
        'serviceDescription': freshDescription,
        'agentOpinion': freshOpinion,
      };
      final idx = localDrafts.indexWhere(
          (l) => l['share_token']?.toString() == shareToken);
      if (idx != -1) {
        localDrafts[idx] = localDraft;
        await StorageService.saveDrafts(List<dynamic>.from(localDrafts));
      }
    } else {
      final newId = DateTime.now().millisecondsSinceEpoch;
      localDraft = {
        'id': newId,
        'caseName': caseName,
        'dong': dong,
        'status': 'Draft',
        'isShared': true,
        'share_token': shareToken,
        'encryption_key': encKey,
        'target': d['target'] ?? '피해아동',
        'method': d['method'] ?? '방문',
        'provision_type': d['provision_type'] ?? '제공',
        'service_type': d['service_type'] ?? '아보전',
        'service_name': d['service_name'] ?? '',
        'service_category': d['service_category'] ?? '',
        'location': d['location'] ?? '기관내',
        'travelTime':
            (d['travel_time'] ?? d['travelTime'] ?? '30').toString(),
        'serviceCount':
            (d['service_count'] ?? d['serviceCount'] ?? '1').toString(),
        'serviceDescription': freshDescription,
        'agentOpinion': freshOpinion,
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
  }

  // ── 공유할 DB 즉시 공유 다이얼로그 (URL은 sync 완료 후 채워짐) ───────
  void _showShareDialogWithFuture(Future<String> urlFuture) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: FutureBuilder<String>(
          future: urlFuture,
          builder: (context, snapshot) {
            final url = snapshot.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDE1E7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: const Text(
                            '나중에',
                            style: TextStyle(fontSize: 14, color: Color(0xFF868E96), fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('방금 저장한 DB 공유하기', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                const SizedBox(height: 6),
                const Text('링크를 복사해 사례 담당자에게 전달하세요.', style: TextStyle(fontSize: 14, color: Color(0xFF868E96))),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: url == null
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: url));
                            AnalyticsService.linkCopied();
                            if (ctx.mounted) Navigator.pop(ctx);
                            _showToast('링크가 복사되었습니다.');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.ios_share_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('링크 복사', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            ],
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── 토스트 ──────────────────────────────────────────────────────

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
              fontWeight: FontWeight.w500),
        ),
        backgroundColor: const Color(0xFF222222),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 40, left: 60, right: 60),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── 빌드 ────────────────────────────────────────────────────────

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
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
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
                      onTap: () {
                        setState(() => _currentIndex = 0);
                        AnalyticsService.tabSwitched('home');
                      },
                    ),
                    _NavBarItem(
                      icon: Badge(
                        isLabelVisible: _notifications.any(
                          (n) =>
                              n['is_read'] == 0 ||
                              n['is_read'] == false,
                        ),
                        backgroundColor: const Color(0xFFFF4D00),
                        child: const Icon(Icons.notifications),
                      ),
                      label: '알림',
                      selected: _currentIndex == 1,
                      onTap: () {
                        setState(() => _currentIndex = 1);
                        AnalyticsService.tabSwitched('notification');
                      },
                    ),
                    _NavBarItem(
                      icon: const Icon(Icons.history_rounded),
                      label: 'DB 내역',
                      selected: _currentIndex == 2,
                      onTap: () {
                        setState(() => _currentIndex = 2);
                        AnalyticsService.tabSwitched('db_history');
                      },
                    ),
                    _NavBarItem(
                      icon: const Icon(Icons.person),
                      label: '프로필',
                      selected: _currentIndex == 3,
                      onTap: () {
                        setState(() => _currentIndex = 3);
                        AnalyticsService.tabSwitched('profile');
                      },
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
      if (_isLoadingInitial) {
        return const Center(
            child: CircularProgressIndicator(strokeWidth: 2));
      }
      return Column(
        children: [
          if (!_serverReachable) _buildOfflineBanner(),
          Expanded(
            child: HomeTab(
              userName: _userName,
              pendingDrafts: _pendingDrafts,
              sharedDrafts: _sharedDrafts,
              cases: _cases,
              counselors: _counselors,
              dbTabController: _dbTabController,
              onRefresh: _loadData,
              onShowCaseSelection: _showCaseSelectionModal,
              onGoToForm: _goToForm,
              onDeleteMyDraft: (draftId) async => _deleteDraft(draftId),
              onSharedDraftTap: _onSharedDraftTap,
              onDeleteSharedDraft: _deleteSharedDraft,
            ),
          ),
        ],
      );
    }
    if (_currentIndex == 1) {
      return NotificationTab(
        notifications: _notifications,
        drafts: _drafts,
        onRefresh: _loadData,
        onGoToForm: _goToForm,
        onShowToast: _showToast,
        onNotificationRead: (notifId) {
          setState(() {
            final index =
                _notifications.indexWhere((n) => n['id'] == notifId);
            if (index != -1) _notifications[index]['is_read'] = 1;
          });
        },
      );
    }
    if (_currentIndex == 2) {
      return DbHistoryTab(
        injectedDrafts: _drafts
            .where((d) => d['status'] == 'Injected')
            .toList(),
      );
    }
    return ProfileTab(
      userName: _userName,
      isProfileLoading: _isProfileLoading,
      notificationsEnabled: _notificationsEnabled,
      cases: _cases,
      drafts: _drafts,
      notifications: _notifications,
      onNameChanged: (newName) => setState(() => _userName = newName),
      onNotificationsChanged: (enabled) =>
          setState(() => _notificationsEnabled = enabled),
      onResetComplete: () => setState(() {
        _drafts = [];
        _cases = [];
        _notifications = [];
      }),
      onCasesChanged: (cases) => setState(() => _cases = cases),
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
            const Icon(Icons.wifi_off_rounded,
                size: 15, color: Color(0xFFB45309)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '서버에 연결하지 못했습니다. 로컬 저장 기록만 표시됩니다.',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF92400E),
                    letterSpacing: -0.1),
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
                    letterSpacing: -0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 하단 네비게이션 아이템 ─────────────────────────────────────────

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
    final color = widget.selected
        ? AppColors.primary
        : const Color(0xFFBBBBBB);
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
