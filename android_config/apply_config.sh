#!/bin/bash
set -e

echo "=== Applying Android configuration ==="

# 1. Set app label in AndroidManifest.xml
sed -i 's/android:label="[^"]*"/android:label="Libretto"/' android/app/src/main/AndroidManifest.xml

# 2. Add network security config reference to manifest
sed -i 's/<application/<application android:networkSecurityConfig="@xml\/network_security_config"/' android/app/src/main/AndroidManifest.xml

# 3. Add permissions before <application> tag
sed -i '/<application/i \
    <uses-permission android:name="android.permission.INTERNET" \/>\
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" \/>\
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" \/>\
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" \/>\
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" \/>\
    <uses-permission android:name="android.permission.WAKE_LOCK" \/>\
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" \/>\
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" \/>' android/app/src/main/AndroidManifest.xml

# 4. Copy network security config
mkdir -p android/app/src/main/res/xml
cp android_config/network_security_config.xml android/app/src/main/res/xml/

# 5. Copy ProGuard rules
cp android_config/proguard-rules.pro android/app/

# 6. Enable ProGuard in build.gradle for release
sed -i '/release {/,/}/s/}/    minifyEnabled true\n                shrinkResources true\n                proguardFiles getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"\n            }/' android/app/build.gradle

# 7. Set package name / application ID
sed -i 's/namespace "com.libretto.libretto"/namespace "com.kyronageh.libretto"/' android/app/build.gradle
sed -i 's/applicationId "com.libretto.libretto"/applicationId "com.kyronageh.libretto"/' android/app/build.gradle

# 8. Set version from pubspec
VERSION=$(grep "^version:" pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
BUILD=$(grep "^version:" pubspec.yaml | sed 's/.*+//')
sed -i "s/versionCode .*/versionCode $BUILD/" android/app/build.gradle
sed -i "s/versionName .*/versionName \"$VERSION\"/" android/app/build.gradle

echo "=== Android configuration applied ==="
