#!/bin/bash
set -e

echo "=== Applying iOS configuration ==="

PLIST="ios/Runner/Info.plist"

if [ ! -f "$PLIST" ]; then
  echo "ERROR: $PLIST not found. Run 'flutter create --platforms ios .' first."
  exit 1
fi

# Helper: add a key-value pair to Info.plist if not already present
add_plist_string() {
  local key="$1" value="$2"
  if ! /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" &>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$PLIST"
    echo "  Added $key"
  fi
}

add_plist_bool() {
  local key="$1" value="$2"
  if ! /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" &>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :$key bool $value" "$PLIST"
    echo "  Added $key"
  fi
}

# 1. Set app display name
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Libretto" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Libretto" "$PLIST"
echo "  Set CFBundleDisplayName = Libretto"

# 2. Background modes — audio playback
if ! /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" &>/dev/null; then
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes array" "$PLIST"
fi
# Add 'audio' if not already present
if ! /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" 2>/dev/null | grep -q "audio"; then
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes: string audio" "$PLIST"
  echo "  Added UIBackgroundModes: audio"
fi

# 3. Usage descriptions (required by Apple for App Store review)
add_plist_string "NSLocalNetworkUsageDescription" "Libretto discovers media servers on your local network."
add_plist_string "NSFaceIDUsageDescription" "Libretto uses Face ID to protect your server credentials."

# 4. App Transport Security — allow HTTP for local network servers
# (Emby/Jellyfin/Plex on LAN often use HTTP)
if ! /usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity" "$PLIST" &>/dev/null; then
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$PLIST"
fi
/usr/libexec/PlistBuddy -c "Set :NSAppTransportSecurity:NSAllowsLocalNetworking true" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$PLIST"
# Allow arbitrary loads for user-configured servers that may use HTTP
/usr/libexec/PlistBuddy -c "Set :NSAppTransportSecurity:NSAllowsArbitraryLoads true" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" "$PLIST"
echo "  Configured ATS: local networking + arbitrary loads"

# 5. iPad support — enable full multitasking
add_plist_bool "UISupportsDocumentBrowser" false
# Ensure the app supports both iPhone and iPad
if /usr/libexec/PlistBuddy -c "Print :UIDeviceFamily" "$PLIST" &>/dev/null; then
  /usr/libexec/PlistBuddy -c "Delete :UIDeviceFamily" "$PLIST"
fi
/usr/libexec/PlistBuddy -c "Add :UIDeviceFamily array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UIDeviceFamily: integer 1" "$PLIST"  # iPhone
/usr/libexec/PlistBuddy -c "Add :UIDeviceFamily: integer 2" "$PLIST"  # iPad
echo "  Set UIDeviceFamily: iPhone + iPad"

# 6. Allow all orientations for iPad, portrait-only for iPhone
if /usr/libexec/PlistBuddy -c "Print :UISupportedInterfaceOrientations" "$PLIST" &>/dev/null; then
  /usr/libexec/PlistBuddy -c "Delete :UISupportedInterfaceOrientations" "$PLIST"
fi
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations: string UIInterfaceOrientationPortrait" "$PLIST"

if /usr/libexec/PlistBuddy -c "Print :UISupportedInterfaceOrientations~ipad" "$PLIST" &>/dev/null; then
  /usr/libexec/PlistBuddy -c "Delete :UISupportedInterfaceOrientations~ipad" "$PLIST"
fi
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations~ipad array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations~ipad: string UIInterfaceOrientationPortrait" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations~ipad: string UIInterfaceOrientationPortraitUpsideDown" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations~ipad: string UIInterfaceOrientationLandscapeLeft" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations~ipad: string UIInterfaceOrientationLandscapeRight" "$PLIST"
echo "  Set orientations: portrait (iPhone), all (iPad)"

# 7. Set deployment target in Podfile and Xcode project
IOS_MIN_VERSION="${IOS_MIN_VERSION:-16.0}"
if [ -f ios/Podfile ]; then
  sed -i '' "s/^platform :ios, .*/platform :ios, '${IOS_MIN_VERSION}'/" ios/Podfile
  # If no platform line exists, add it at the top
  if ! grep -q "^platform :ios" ios/Podfile; then
    sed -i '' "1i\\
platform :ios, '${IOS_MIN_VERSION}'
" ios/Podfile
  fi
  echo "  Set Podfile platform to iOS ${IOS_MIN_VERSION}"
fi

# Set in Xcode project
sed -i '' "s/IPHONEOS_DEPLOYMENT_TARGET = [0-9][0-9.]*/IPHONEOS_DEPLOYMENT_TARGET = ${IOS_MIN_VERSION}/g" \
  ios/Runner.xcodeproj/project.pbxproj
echo "  Set Xcode deployment target to iOS ${IOS_MIN_VERSION}"

echo "=== iOS configuration applied ==="
