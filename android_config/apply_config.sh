#!/bin/bash
set -e

echo "=== Applying Android configuration ==="

GRADLE_FILE="android/app/build.gradle.kts"

# Detect Groovy vs Kotlin DSL
if [ ! -f "$GRADLE_FILE" ]; then
  GRADLE_FILE="android/app/build.gradle"
fi

if [ ! -f "$GRADLE_FILE" ]; then
  echo "ERROR: No build.gradle or build.gradle.kts found"
  exit 1
fi

echo "Using: $GRADLE_FILE"

# 1. Set app label in AndroidManifest.xml
sed -i 's/android:label="[^"]*"/android:label="Libretto"/' android/app/src/main/AndroidManifest.xml

# 2. Add network security config reference to manifest
if ! grep -q 'networkSecurityConfig' android/app/src/main/AndroidManifest.xml; then
  sed -i 's/<application/<application android:networkSecurityConfig="@xml\/network_security_config"/' android/app/src/main/AndroidManifest.xml
fi

# 3. Add permissions before <application> tag (only if not already present)
if ! grep -q 'FOREGROUND_SERVICE_MEDIA_PLAYBACK' android/app/src/main/AndroidManifest.xml; then
  sed -i '/<application/i \
    <uses-permission android:name="android.permission.INTERNET" \/>\
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" \/>\
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" \/>\
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" \/>\
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" \/>\
    <uses-permission android:name="android.permission.WAKE_LOCK" \/>\
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" \/>\
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" \/>' android/app/src/main/AndroidManifest.xml
fi

# 4. Copy network security config
mkdir -p android/app/src/main/res/xml
cp android_config/network_security_config.xml android/app/src/main/res/xml/

# 5. Copy ProGuard rules
cp android_config/proguard-rules.pro android/app/

# 6. Set minSdkVersion to 21 (Android 5.0) for broader device support
if [[ "$GRADLE_FILE" == *.kts ]]; then
  sed -i "s/minSdk = flutter.minSdkVersion/minSdk = 21/" "$GRADLE_FILE"
  # Fallback: if the pattern doesn't match, try the numeric pattern
  sed -i 's/minSdk = [0-9]\{2,\}/minSdk = 21/' "$GRADLE_FILE"
else
  sed -i "s/minSdkVersion flutter.minSdkVersion/minSdkVersion 21/" "$GRADLE_FILE"
  sed -i 's/minSdkVersion [0-9]\{2,\}/minSdkVersion 21/' "$GRADLE_FILE"
fi

echo "=== Android configuration applied ==="
