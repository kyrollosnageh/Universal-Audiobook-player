#!/bin/bash
set -e

echo "=== Setting up iOS code signing ==="

# Requires these CI secrets:
# - IOS_CERTIFICATE_BASE64: Base64-encoded .p12 distribution certificate
# - IOS_CERTIFICATE_PASSWORD: Password for the .p12 certificate
# - IOS_PROVISIONING_PROFILE_BASE64: Base64-encoded .mobileprovision file
# - IOS_KEYCHAIN_PASSWORD: Temporary keychain password (can be random)

if [ -z "$IOS_CERTIFICATE_BASE64" ]; then
  echo "WARNING: IOS_CERTIFICATE_BASE64 not set — skipping signing"
  exit 0
fi

KEYCHAIN_PATH="$HOME/Library/Keychains/build.keychain-db"
CERT_PATH="$HOME/build_certificate.p12"
PROFILE_PATH="$HOME/build_provision.mobileprovision"

# 1. Decode certificate and provisioning profile
echo "$IOS_CERTIFICATE_BASE64" | tr -d '[:space:]' | base64 --decode > "$CERT_PATH"
echo "$IOS_PROVISIONING_PROFILE_BASE64" | tr -d '[:space:]' | base64 --decode > "$PROFILE_PATH"

# 2. Create and configure temporary keychain
security create-keychain -p "$IOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" 2>/dev/null || true
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$IOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" "$(security list-keychains -d user | tr -d '"')"

# 3. Import certificate to keychain
security import "$CERT_PATH" -k "$KEYCHAIN_PATH" -P "$IOS_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -k "$IOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# 4. Install provisioning profile
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c "Print UUID" /dev/stdin <<< \
  "$(security cms -D -i "$PROFILE_PATH")")
cp "$PROFILE_PATH" "$PROFILE_DIR/$PROFILE_UUID.mobileprovision"

# 5. Update Xcode project to use manual signing
PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
  # Set manual code signing
  sed -i '' 's/CODE_SIGN_STYLE = Automatic/CODE_SIGN_STYLE = Manual/g' "$PBXPROJ"

  # Set provisioning profile UUID
  sed -i '' "s/PROVISIONING_PROFILE_SPECIFIER = \"\"/PROVISIONING_PROFILE_SPECIFIER = \"$PROFILE_UUID\"/g" "$PBXPROJ"

  echo "  Configured manual signing in Xcode project"
fi

echo "=== iOS code signing configured ==="
