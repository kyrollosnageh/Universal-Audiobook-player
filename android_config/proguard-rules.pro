# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Dio / OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }

# Drift SQLite
-keep class drift.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }

# Keep Libretto models
-keep class com.libretto.** { *; }
