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
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _drafts = [];
  List<dynamic> _cases = [];
  List<dynamic> _notifications = [];
  bool _isSelectionMode = false;
  final List<int> _selectedCaseIds = [];
  
  // Real-time event subscription
  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initRealtime();
    _setupFCM();
    ApiService.checkHealth();
  }

  @override
  void dispose() {
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
      print('🚀 Initializing SSE for email: $email');
      _eventSub?.cancel();
      _eventSub = ApiService.streamEvents(email).listen((event) {
        final String? ev = event['event'];
        print('🔔 Server Event Received: $ev');
        
        // Initial setup/heartbeat event should not trigger a heavy refresh
        if (ev != 'connected') {
          _loadData();
        }
      });
    }
    
    _isInitializingSse = false;
  }

  Future<void> _loadData() async {
    await StorageService.initInitialData();
    final localDrafts = await StorageService.getDrafts();
    final cases = await StorageService.getCases();
    
    setState(() {
      _drafts = localDrafts;
      _cases = cases;
    });

    // Background Sync for offline drafts
    try {
      final pending = await StorageService.getPendingSyncs();
      if (pending.isNotEmpty) {
        bool syncedAny = false;
        List<dynamic> remaining = [];
        for (var data in pending) {
          final clientId = data['client_draft_id'];
          // Remove client_draft_id from payload before sending
          final payload = Map<String, dynamic>.from(data)..remove('client_draft_id');
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
            setState(() { _drafts = localDrafts; });
            _showToast('오프라인 기록이 자동 동기화되었습니다. ✨');
          }
        }
      }
    } catch (e) {
      print('Background Sync Error: $e');
    }

    // 서버에서 최신 상태 가져오기
    try {
      final String? userId = FirebaseAuth.instance.currentUser?.uid;
      final serverRecords = await ApiService.fetchRecords();
      
      // Fetch actual notifications from server table
      if (userId != null) {
        final serverNotifs = await ApiService.fetchNotifications(userId);
        if (mounted) {
          setState(() {
            _notifications = serverNotifs;
          });
        }
      }

      if (serverRecords.isNotEmpty || localDrafts.isNotEmpty) {
        // 로컬 데이터와 서버 데이터 병합 및 삭제 처리
        List<Map<String, dynamic>> updatedDrafts = [];
        
        for (var local in localDrafts) {
          final String? localToken = local['share_token'];
          
          final serverIdx = serverRecords.indexWhere((s) {
            final String serverId = s['id'].toString();
            final String? serverToken = s['share_token'];
            final String localId = local['id'].toString();
            return (serverId == localId) || (serverToken != null && serverToken == localToken);
          });
          
          if (serverIdx != -1) {
            // 서버에 존재하면 업데이트해서 유지
            final s = serverRecords[serverIdx];
            // Use server's raw data ONLY if it's not empty (E2EE sync records are empty)
            String finalDescription = local['serviceDescription'] ?? '';
            String finalOpinion = local['agentOpinion'] ?? '';
            
            if (s['service_description'] != null && s['service_description'].toString().isNotEmpty) {
              finalDescription = s['service_description'];
            }
            if (s['agent_opinion'] != null && s['agent_opinion'].toString().isNotEmpty) {
              finalOpinion = s['agent_opinion'];
            }

            // [E2EE] Support decryption of blob from server if provided
            final String? blob = s['encrypted_blob'];
            final String? keyStr = local['encryption_key'];
            if (blob != null && keyStr != null && blob.contains(':')) {
              try {
                final parts = blob.split(':');
                final iv = encrypt.IV.fromBase64(parts[0]);
                final encrypted = encrypt.Encrypted.fromBase64(parts[1]);
                final key = encrypt.Key.fromUtf8(keyStr.padRight(32).substring(0, 32));
                final encrypter = encrypt.Encrypter(encrypt.AES(key));
                final decrypted = encrypter.decrypt(encrypted, iv: iv);
                final decryptedData = jsonDecode(decrypted) as Map<String, dynamic>;
                
                // Content priority:
                // 1. Decrypted data from blob (contains reviewer edits)
                // 2. Server raw data (if any)
                // 3. Local data ( counselor's original)
                finalDescription = decryptedData['serviceDescription'] ?? decryptedData['service_description'] ?? finalDescription;
                finalOpinion = decryptedData['agentOpinion'] ?? decryptedData['agent_opinion'] ?? finalOpinion;
              } catch (e) {
                print('E2EE Decryption failed on merge: $e');
              }
            }

            // Priority merge for 'Synced' (draft) records:
            // Always trust local for metadata and encrypted content to prevent data loss or server lag reverts.
            updatedDrafts.add({
              ...local,
              'status': s['status'],
              'share_token': s['share_token'],
              'treatment': s['target_system_code'] ?? local['treatment'],
              'serviceDescription': finalDescription,
              'agentOpinion': finalOpinion,
              'startTime': (s['status'] == 'Reviewed' && s['start_time'] != null) ? s['start_time'] : (local['startTime'] ?? s['start_time']),
              'endTime': (s['status'] == 'Reviewed' && s['end_time'] != null) ? s['end_time'] : (local['endTime'] ?? s['end_time']),
              'serviceCount': (s['status'] == 'Reviewed') ? (s['service_count'] ?? local['serviceCount']) : (local['serviceCount'] ?? s['service_count']),
              'travelTime': (s['status'] == 'Reviewed') ? (s['travel_time'] ?? local['travelTime']) : (local['travelTime'] ?? s['travel_time']),
            });
          } else {
            // 서버에 없는데 token이 있다면, 다른 곳에서 삭제된 것으로 간주하고 로컬에서도 제거
            if (localToken == null || localToken.isEmpty) {
              // 아직 동기화 전인 로컬 전용 데이터는 유지
              updatedDrafts.add(local);
            } else {
              print('🗑️ Server record missing for token $localToken. Deleting local copy.');
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
      print('Sync failed: $e');
    }

    // NEW: Sync active tokens to clear orphaned drafts on the server
    try {
      final activeTokens = _drafts // Use _drafts which is already updated or localDrafts if not yet updated
          .map((d) => d['share_token'] as String?)
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>()
          .toList();
      
      // Always sync to clean server if drafts empty
      await ApiService.syncActiveRecords(activeTokens);
    } catch (e) {
      print('Orphan cleanup error: $e');
    }
  }

  Future<void> _setupFCM() async {
    final messaging = FirebaseMessaging.instance;
    
    // 1. 권한 요청
    final settings = await messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );
    
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // 2. 토큰 획득 및 서버 저장
      final token = await messaging.getToken();
      final user = FirebaseAuth.instance.currentUser;
      if (token != null && user != null) {
        await ApiService.saveFcmToken(user.uid, token);
        print('🔥 FCM Token Registered: ${token.substring(0, 8)}...');
      }
    }

    // 3. 포그라운드 메시지 리스너 (앱이 켜져 있을 때)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null && mounted) {
        _showToast('📢 ${message.notification!.title}: ${message.notification!.body}');
        _loadData(); // 알림 리스트 갱신
      }
    });

    // 4. 알림 클릭으로 앱이 열렸을 때 처리 가능 (필요 시)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('🚀 Notification opened app: ${message.data}');
      // 예: 특정 페이지로 바로 이동하는 로직 추가 가능
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
                  '이 DB 작성을 삭제할까요?',
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
                        onPressed: () => Navigator.pop(context, false),
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
                        onPressed: () => Navigator.pop(context, true),
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
    final draftToDelete = drafts.firstWhere((d) => d['id'] == draftId, orElse: () => null);

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
        builder: (context) =>
            FormScreen(caseId: caseId, caseName: maskedName, dong: dong, draftId: draftId),
      ),
    );
    if (result == true) {
      _loadData();
    }
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
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                          if (_isSelectionMode && _selectedCaseIds.isNotEmpty) {
                                            _showCaseDeleteConfirmation(modalContext);
                                          } else {
                                            setState(() {
                                              _isSelectionMode = !_isSelectionMode;
                                              if (!_isSelectionMode) _selectedCaseIds.clear();
                                            });
                                            setModalState(() {});
                                          }
                                        },
                                        child: Text(
                                          _isSelectionMode
                                              ? (_selectedCaseIds.isEmpty ? '취소' : '삭제')
                                              : '편집',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: _isSelectionMode ? AppColors.danger : AppColors.textSub,
                                            fontWeight: _isSelectionMode ? FontWeight.w700 : FontWeight.w500,
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
                                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 1.6,
                                    ),
                                    itemCount: _cases.length,
                                    itemBuilder: (context, index) {
                                      final c = _cases[index];
                                      final bool isSelected = _selectedCaseIds.contains(c['id']);
                                      final int sIndex = _selectedCaseIds.indexOf(c['id']) + 1;
                                      return _PressableCaseCard(
                                        caseData: c,
                                        isSelected: isSelected,
                                        sIndex: sIndex,
                                        isSelectionMode: _isSelectionMode,
                                        onTap: () {
                                          if (_isSelectionMode) {
                                            setState(() {
                                              if (isSelected) {
                                                _selectedCaseIds.remove(c['id']);
                                              } else {
                                                _selectedCaseIds.add(c['id']);
                                              }
                                            });
                                            setModalState(() {});
                                          } else {
                                            Navigator.pop(modalContext);
                                            _goToForm(c['realName'], c['maskedName'], c['dong'], caseId: c['id']);
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
                            MaterialPageRoute(builder: (context) => const CreateCaseScreen()),
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
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                            side: const BorderSide(color: Color(0xFFE5E8EB), width: 1),
                          ),
                          elevation: 4,
                          shadowColor: Colors.black.withOpacity(0.2),
                        ),
                        child: const Text(
                          '+ 사례 생성',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
        title: const Text(
          'Dash',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: AppColors.primary,
        unselectedItemColor: const Color(0xFF8B95A1),
        backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: '알림'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '프로필'),
        ],
      ),
      floatingActionButton: _currentIndex != 0 ? null : Container(
        margin: const EdgeInsets.only(bottom: 20),
        child: ElevatedButton(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreateCaseScreen()),
            );
            if (result == true) {
              _loadData();
              _showToast('사례를 생성하였어요. DB를 작성해보세요!');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.textMain,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100),
              side: const BorderSide(color: Color(0xFFE5E8EB), width: 1),
            ),
            elevation: 4,
            shadowColor: Colors.black.withOpacity(0.2),
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
    if (_currentIndex == 0) return _buildHomeTab();
    if (_currentIndex == 1) return _buildNotificationTab();
    return _buildProfileTab();
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
    unreadNotifs.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));

    if (unreadNotifs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none_rounded, size: 64, color: AppColors.border.withOpacity(0.8)),
            const SizedBox(height: 16),
            const Text(
              '아직 도착한 알림이 없어요',
              style: TextStyle(color: AppColors.textSub, fontSize: 16, fontWeight: FontWeight.w600),
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
          child: Text('알림', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF222222))),
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
                    print('🔔 Notification tapped: $notifId');
                    // 1. 알림 읽음 처리 (서버에만 알림, 블로킹 방지 위해 await 제거)
                    if (notifId != null) {
                      ApiService.markNotificationRead(notifId);
                    }

                    print('🔍 Found drafts length: ${_drafts.length}');
                    // 2. 기록 매칭 및 이동
                    Map<String, dynamic>? foundDraft;
                    for (var d in _drafts) {
                      final bool matchToken = (nToken != null && d['share_token'] == nToken);
                      final bool matchName = (d['caseName'] == caseName);
                      if (matchToken || matchName) {
                        foundDraft = Map<String, dynamic>.from(d);
                        break;
                      }
                    }
                    print('🔍 Matched draft: $foundDraft');

                    if (foundDraft != null) {
                      final dong = foundDraft['dong'] ?? '';
                      _goToForm(
                        foundDraft['caseName'] ?? caseName, 
                        foundDraft['caseName'] ?? caseName, 
                        dong, 
                        caseId: foundDraft['case_id'] ?? foundDraft['id'], 
                        draftId: foundDraft['id']
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
                          decoration: const BoxDecoration(color: Color(0xFFF1F7FF), shape: BoxShape.circle),
                          child: const Icon(Icons.assignment_turned_in_rounded, color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "$caseName 아동 사례",
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "DB 내용이 검토 완료되었어요.\n수정 사항을 확인해 보세요.",
                                style: TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF4E5968), fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(dateStr, style: const TextStyle(fontSize: 11, color: Color(0xFFADB5BD), fontWeight: FontWeight.w500)),
                                  const Row(
                                    children: [
                                      Text(
                                        '자세히 보기',
                                        style: TextStyle(color: Color(0xFF8B95A1), fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFFADB5BD)),
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
    if (_userName == null) { setState(() { _userName = user.displayName; }); }
    try {
      final serverUser = await ApiService.fetchUser(user.uid);
      if (serverUser != null && mounted) { setState(() { _userName = serverUser['name']; }); }
    } catch (e) { print('Error fetching profile: $e'); }
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: _userName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이름 수정', style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: '실명을 입력해주세요', border: OutlineInputBorder()), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(context);
              setState(() { _isProfileLoading = true; });
              final success = await ApiService.updateUserProfile(FirebaseAuth.instance.currentUser!.uid, newName);
              if (success) {
                setState(() { _userName = newName; });
                _showToast('이름이 수정되었습니다.');
              } else {
                _showToast('이름 수정에 실패했습니다.');
              }
              setState(() { _isProfileLoading = false; });
            },
            child: const Text('저장', style: TextStyle(fontWeight: FontWeight.w700)),
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
                  _userName ?? '사용자',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24, color: AppColors.textMain),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _showEditNameDialog,
                  icon: const Icon(Icons.edit, size: 20, color: Color(0xFF8B95A1)),
                  tooltip: '이름 수정',
                ),
              ],
            ),
            Text(email, style: const TextStyle(fontSize: 14, color: AppColors.textSub, fontWeight: FontWeight.w500)),
            const SizedBox(height: 48),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _buildProfileMenuItem(Icons.notifications_none, '알림 설정', () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Text('푸시 알림', style: TextStyle(fontWeight: FontWeight.w800)),
                        content: const Text('DB 검토 완료 및 중요 소식에 대한\n푸시 알림을 받으시겠습니까?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Color(0xFFADB5BD)))),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _showToast('알림 수신 동의가 완료되었습니다. ✨');
                            },
                            child: const Text('허용', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border),
                  _buildProfileMenuItem(Icons.lock_outline, '개인정보처리방침', () {
                    _showToast('개인정보처리방침 페이지로 이동합니다.');
                  }),
                  const Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border),
                  _buildProfileMenuItem(Icons.description_outlined, '서비스 약관', () {
                    _showToast('서비스 약관 페이지로 이동합니다.');
                  }),
                  const Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border),
                  _buildProfileMenuItem(Icons.logout, '로그아웃', () async {
                    await FirebaseAuth.instance.signOut();
                    if (mounted) Navigator.pushReplacementNamed(context, '/');
                  }, isDanger: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileMenuItem(IconData icon, String title, VoidCallback onTap, {bool isDanger = false}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: isDanger ? AppColors.danger : AppColors.textMain, size: 22),
      title: Text(title, style: TextStyle(color: isDanger ? AppColors.danger : AppColors.textMain, fontWeight: FontWeight.w600, fontSize: 16)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.border, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildHomeTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _InfoBanner(),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              const Color(0xFFC7E0FF).withValues(alpha: 0.25),
                              Colors.white,
                            ],
                            stops: const [0.0, 0.35],
                          ),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(
                                alpha: 0.06,
                              ),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.15,
                                    ),
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
                      ),

                      const SizedBox(height: 40),
                      if (_drafts.isNotEmpty) ...[
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '대기 중인 DB 목록',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ..._drafts.map((d) {
                          final foundCase = _cases.cast<Map<String, dynamic>?>().firstWhere(
                            (c) => c?['realName'] == d['caseName'] || c?['maskedName'] == d['caseName'],
                            orElse: () => null,
                          );
                          final dong = foundCase != null ? foundCase['dong'] : '미지정';
                          return _buildDraftCard(d, dong);
                        }),
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
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ); // RefreshIndicator
      },
    ); // LayoutBuilder
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
            border: Border.all(
              color: widget.isSelected ? AppColors.primary : AppColors.border,
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: _isPressed ? [] : [
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
                      color: widget.isSelected ? AppColors.primary : Colors.white,
                      border: Border.all(
                        color: widget.isSelected ? AppColors.primary : AppColors.border,
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

class _InfoBanner extends StatelessWidget {

  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF3FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 16,
            color: AppColors.primary.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Dash에서 DB를 어떻게 작성할까요?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color.fromARGB(255, 80, 93, 109),
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
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
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(24),
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
                  onTap: widget.onTap,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFF2F4F6)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.d['caseName']} 아동 사례',
                                style: const TextStyle(
                                  color: Color(0xFF222222),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '대상: ${() {
                                  final targets = widget.d['target'].toString().split(', ');
                                  if (targets.length > 1) {
                                    return "${targets[0]} 외 ${targets.length - 1}";
                                  }
                                  return widget.d['target'];
                                  }()} | ${widget.d['method'] ?? '방문'}\n${(() {
                                    final startStr = widget.d['startTime'];
                                    final endStr = widget.d['endTime'];
                                    if (startStr == null || endStr == null) return widget.d['datetime'] ?? '제공일시 미설정';
                                    
                                    final start = DateTime.tryParse(startStr);
                                    final end = DateTime.tryParse(endStr);
                                    if (start == null || end == null) return widget.d['datetime'] ?? '제공일시 미설정';

                                    final bool isSameDay = start.year == end.year && start.month == end.month && start.day == end.day;
                                    final fullFormat = DateFormat('MM.dd HH:mm');
                                    if (isSameDay) {
                                      return "${fullFormat.format(start)} ~ ${DateFormat('HH:mm').format(end)}";
                                    }
                                    return "${fullFormat.format(start)} ~ ${fullFormat.format(end)}";
                                  })()}',
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: (widget.d['status']?.toString().toLowerCase() == 'reviewed') ? AppColors.successLight : AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: (widget.d['status']?.toString().toLowerCase() == 'reviewed') ? AppColors.success : AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                (widget.d['status']?.toString().toLowerCase() == 'reviewed') ? '검토 완료' : '검토 대기',
                                style: TextStyle(
                                  color: (widget.d['status']?.toString().toLowerCase() == 'reviewed') ? AppColors.success : AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
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
  }
}
