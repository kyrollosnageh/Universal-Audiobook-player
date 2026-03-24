#!/bin/bash
set -e

echo "=== Setting up release signing ==="

# Decode keystore (strip any whitespace/newlines from the base64 string)
echo "$KEYSTORE_BASE64" | tr -d '[:space:]' | base64 --decode > android/app/libretto-release.jks

# Create key.properties (trimmed — no leading spaces)
cat > android/key.properties <<PROPS
storePassword=$KEYSTORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=libretto-release.jks
PROPS

# Detect Kotlin DSL vs Groovy
if [ -f "android/app/build.gradle.kts" ]; then
  GRADLE_FILE="android/app/build.gradle.kts"
  echo "Detected Kotlin DSL: $GRADLE_FILE"

  # For Kotlin DSL, create a signing config block
  # Insert keystore loading and signingConfigs before the android { block
  cat > /tmp/signing_block.txt <<'KTS'
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

KTS

  # Prepend the properties loading to the file
  cat /tmp/signing_block.txt "$GRADLE_FILE" > /tmp/build.gradle.kts.tmp
  mv /tmp/build.gradle.kts.tmp "$GRADLE_FILE"

  # Add signingConfigs inside android { block, before buildTypes
  sed -i '/buildTypes {/i \
    signingConfigs {\
        create("release") {\
            keyAlias = keystoreProperties["keyAlias"] as String\
            keyPassword = keystoreProperties["keyPassword"] as String\
            storeFile = file(keystoreProperties["storeFile"] as String)\
            storePassword = keystoreProperties["storePassword"] as String\
        }\
    }' "$GRADLE_FILE"

  # Replace debug signing with release signing
  sed -i 's/signingConfig = signingConfigs.getByName("debug")/signingConfig = signingConfigs.getByName("release")/' "$GRADLE_FILE"

else
  GRADLE_FILE="android/app/build.gradle"
  echo "Detected Groovy DSL: $GRADLE_FILE"

  # Groovy DSL signing
  sed -i '/android {/i \
def keystoreProperties = new Properties()\
def keystorePropertiesFile = rootProject.file("key.properties")\
if (keystorePropertiesFile.exists()) {\
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\
}' "$GRADLE_FILE"

  sed -i '/buildTypes {/i \
    signingConfigs {\
        release {\
            keyAlias keystoreProperties["keyAlias"]\
            keyPassword keystoreProperties["keyPassword"]\
            storeFile file(keystoreProperties["storeFile"])\
            storePassword keystoreProperties["storePassword"]\
        }\
    }' "$GRADLE_FILE"

  sed -i 's/signingConfig signingConfigs.debug/signingConfig signingConfigs.release/' "$GRADLE_FILE"
fi

echo "=== Release signing configured ==="
