# Flutter 엔진
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# OkHttp / Okio (Firebase Auth 내부 HTTP 클라이언트)
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okio.** { *; }
-dontwarn okio.**
-keep class com.android.okhttp.** { *; }
-dontwarn com.android.okhttp.**

# 스택트레이스 복구용 (선택 사항: 배포 후 크래시 분석에 유용)
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
