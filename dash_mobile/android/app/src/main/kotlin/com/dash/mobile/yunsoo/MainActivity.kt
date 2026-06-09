package com.dash.mobile.yunsoo

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15 edge-to-edge: 시스템 창 인셋을 Flutter가 직접 처리하도록 설정
        // deprecated setStatusBarColor / setNavigationBarColor 경고 해소
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }
}

