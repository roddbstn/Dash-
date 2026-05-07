import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// 비정상 종료 및 비치명적 오류 수집 서비스
/// Firebase Crashlytics를 통해 운영 중 발생하는 오류를 추적합니다.
class CrashService {
  static FirebaseCrashlytics get _c => FirebaseCrashlytics.instance;

  /// 비치명적 오류 기록 (앱이 종료되지 않는 백그라운드 오류)
  static Future<void> recordError(
    dynamic error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    if (kDebugMode) {
      debugPrint('🔴 CrashService [$reason]: $error');
      return; // 디버그 모드에서는 Crashlytics 전송 안 함
    }
    try {
      await _c.recordError(error, stack, reason: reason, fatal: fatal);
    } catch (_) {}
  }

  /// 사용자 ID를 Crashlytics 세션에 연결 (어느 유저가 크래시를 겪었는지 파악)
  static Future<void> setUserId(String userId) async {
    if (kDebugMode) return;
    try {
      await _c.setUserIdentifier(userId);
    } catch (_) {}
  }

  /// 커스텀 키-값 (디버깅에 유용한 상태 정보)
  static Future<void> setKey(String key, Object value) async {
    if (kDebugMode) return;
    try {
      if (value is String) {
        await _c.setCustomKey(key, value);
      } else if (value is int) {
        await _c.setCustomKey(key, value);
      } else if (value is bool) {
        await _c.setCustomKey(key, value);
      }
    } catch (_) {}
  }
}
