#!/usr/bin/env bash
set -euo pipefail

# Required env vars (set in GitHub Actions secrets)
: "${ANDROID_KEYSTORE_BASE64:?Missing ANDROID_KEYSTORE_BASE64}"
: "${ANDROID_KEY_ALIAS:?Missing ANDROID_KEY_ALIAS}"
: "${ANDROID_KEYSTORE_PASSWORD:?Missing ANDROID_KEYSTORE_PASSWORD}"
: "${ANDROID_KEY_PASSWORD:?Missing ANDROID_KEY_PASSWORD}"

BUNDLETOOL_VERSION="1.13.1"
BUNDLETOOL_JAR="bundletool-all-${BUNDLETOOL_VERSION}.jar"
KEYSTORE_FILE="acode.jks"

# Download bundletool if missing
if [ ! -f "$BUNDLETOOL_JAR" ]; then
  wget "https://github.com/google/bundletool/releases/download/${BUNDLETOOL_VERSION}/${BUNDLETOOL_JAR}"
fi

# Recreate keystore from secret
echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$KEYSTORE_FILE"

# Cleanup previous outputs
rm -f ./*.apks ./*.apk toc.pb || true

echo "Working dir: $PWD"
ls -la

# Convert each AAB to signed universal APK
shopt -s nullglob
for aab in ./*.aab; do
  out="${aab%.*}.apks"

  java -jar "$BUNDLETOOL_JAR" build-apks \
    --bundle="$aab" \
    --mode=universal \
    --output="$out" \
    --ks="$KEYSTORE_FILE" \
    --ks-pass="pass:${ANDROID_KEYSTORE_PASSWORD}" \
    --ks-key-alias="${ANDROID_KEY_ALIAS}" \
    --key-pass="pass:${ANDROID_KEY_PASSWORD}"

  unzip -o "$out" universal.apk
  mv -v universal.apk "${aab%.*}.apk"
done

# Remove decoded keystore
rm -f "$KEYSTORE_FILE"
