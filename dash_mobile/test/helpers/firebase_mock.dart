// =============================================================================
// Firebase 테스트 모킹 헬퍼
// firebase_core_platform_interface ^6.0.0 기준
//
// Firebase Core + Firebase Auth 채널을 최소한으로 모킹하여
// 단위 테스트에서 FirebaseAuth.instance.currentUser == null 상태를 만듭니다.
//
// 사용법:
//   setUpAll(() async => await setupFirebaseMocks());
// =============================================================================

import 'package:firebase_core/firebase_core.dart';
// test.dart: CoreInitializeResponse, CoreFirebaseOptions, TestFirebaseCoreHostApi 노출
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Firebase Core Mock (v6 타입명: Core* prefix)
// ─────────────────────────────────────────────────────────────────────────────

class _MockFirebaseCoreHostApi extends TestFirebaseCoreHostApi {
  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions options,
  ) async {
    return CoreInitializeResponse(
      name: appName,
      options: options,
      isAutomaticDataCollectionEnabled: false,
      pluginConstants: {},
    );
  }

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async => [];

  @override
  Future<CoreFirebaseOptions> optionsFromResource() async =>
      throw UnimplementedError();
}

// ─────────────────────────────────────────────────────────────────────────────
// setupFirebaseMocks — 테스트 setUpAll에서 한 번만 호출
// ─────────────────────────────────────────────────────────────────────────────

Future<void> setupFirebaseMocks() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase Core Pigeon 채널 모킹 (setUp = v6 메서드명)
  TestFirebaseCoreHostApi.setUp(_MockFirebaseCoreHostApi());

  // 2. Firebase 초기화 (Dart 레지스트리에 [DEFAULT] 앱 등록)
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'test_api_key',
      appId: '1:111111111111:android:test_app_id',
      messagingSenderId: '111111111111',
      projectId: 'test_project',
    ),
  );

  // 3. Firebase Auth Pigeon 채널 모킹
  //    registerIdTokenListener / registerAuthStateListener 호출 시
  //    가짜 EventChannel 이름을 반환 → currentUser는 null 유지
  _mockBasicMessageChannel(
    'dev.flutter.pigeon.firebase_auth_platform_interface'
    '.FirebaseAuthHostApi.registerIdTokenListener',
    responsePayload: <Object?>['fake_id_token_event_channel'],
  );
  _mockBasicMessageChannel(
    'dev.flutter.pigeon.firebase_auth_platform_interface'
    '.FirebaseAuthHostApi.registerAuthStateListener',
    responsePayload: <Object?>['fake_auth_state_event_channel'],
  );
}

/// Pigeon BasicMessageChannel을 모킹합니다.
/// [responsePayload]: codec.encodeMessage에 전달할 응답 데이터
void _mockBasicMessageChannel(
  String channelName, {
  required List<Object?> responsePayload,
}) {
  const codec = StandardMessageCodec();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(channelName, (ByteData? message) async {
    return codec.encodeMessage(responsePayload);
  });
}

/// 테스트 종료 후 Auth 채널 모킹 해제 (필요 시 tearDownAll에서 호출)
void tearDownFirebaseMocks() {
  for (final name in [
    'dev.flutter.pigeon.firebase_auth_platform_interface'
        '.FirebaseAuthHostApi.registerIdTokenListener',
    'dev.flutter.pigeon.firebase_auth_platform_interface'
        '.FirebaseAuthHostApi.registerAuthStateListener',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(name, null);
  }
}
