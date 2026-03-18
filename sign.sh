#!/usr/bin/env bash
set -euo pipefail

# Signing supports two modes:
#
# Mode 1 – Stored keystore (recommended for production / Play Store):
#   Set the following GitHub Actions repository secrets:
#     ANDROID_KEYSTORE_BASE64    base64-encoded .jks/.keystore file
#     ANDROID_KEY_ALIAS          key alias inside the keystore
#     ANDROID_KEYSTORE_PASSWORD  keystore password
#     ANDROID_KEY_PASSWORD       key password
#   APKs signed this way carry a consistent identity and can update
#   existing installations.
#
# Mode 2 – Ephemeral keystore (no secrets required, zero configuration):
#   When ANDROID_KEYSTORE_BASE64 is not set, a fresh key pair is generated
#   at build time.
#   ⚠ WARNING: A new key is created on every run, so the APK signature
#   changes with each build.  Android enforces signature continuity for
#   updates, meaning users MUST uninstall the old version before installing
#   a freshly signed one.  This mode is suitable for first-time sideloads,
#   nightly/test builds, or CI smoke tests.

BUNDLETOOL_VERSION="1.13.1"
BUNDLETOOL_JAR="bundletool-all-${BUNDLETOOL_VERSION}.jar"
KEYSTORE_FILE="acode.jks"

# Download bundletool if missing
if [ ! -f "$BUNDLETOOL_JAR" ]; then
  wget "https://github.com/google/bundletool/releases/download/${BUNDLETOOL_VERSION}/${BUNDLETOOL_JAR}"
fi

# Determine signing mode
if [ -n "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  # --- Mode 1: stored keystore ---
  : "${ANDROID_KEY_ALIAS:?ANDROID_KEY_ALIAS must be set when ANDROID_KEYSTORE_BASE64 is provided}"
  : "${ANDROID_KEYSTORE_PASSWORD:?ANDROID_KEYSTORE_PASSWORD must be set when ANDROID_KEYSTORE_BASE64 is provided}"
  : "${ANDROID_KEY_PASSWORD:?ANDROID_KEY_PASSWORD must be set when ANDROID_KEYSTORE_BASE64 is provided}"
  echo "Signing mode: stored keystore (ANDROID_KEYSTORE_BASE64 secret)"
  echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$KEYSTORE_FILE"
  KS_ALIAS="${ANDROID_KEY_ALIAS}"
  KS_PASS="${ANDROID_KEYSTORE_PASSWORD}"
  KEY_PASS="${ANDROID_KEY_PASSWORD}"
else
  # --- Mode 2: ephemeral keystore ---
  echo ""
  echo "WARNING: ANDROID_KEYSTORE_BASE64 secret is not set."
  echo "  Generating a one-time ephemeral keystore for this build."
  echo "  APKs signed with this key CANNOT update any previously installed version."
  echo "  Add ANDROID_KEYSTORE_BASE64, ANDROID_KEY_ALIAS, ANDROID_KEYSTORE_PASSWORD,"
  echo "  and ANDROID_KEY_PASSWORD as repository secrets for stable, update-compatible signing."
  echo ""
  KS_ALIAS="acode"
  # Use a random password so it doesn't appear in any persistent logs
  KS_PASS="$(openssl rand -hex 16)"
  KEY_PASS="$KS_PASS"
  keytool -genkey -v \
    -keystore "$KEYSTORE_FILE" \
    -alias "$KS_ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 9125 \
    -dname "CN=Acode CI Build, OU=CI, O=Acode, L=Unknown, ST=Unknown, C=US" \
    -storepass "$KS_PASS" \
    -keypass "$KEY_PASS" \
    -noprompt
fi

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
    --ks-pass="pass:${KS_PASS}" \
    --ks-key-alias="${KS_ALIAS}" \
    --key-pass="pass:${KEY_PASS}"

  unzip -o "$out" universal.apk
  mv -v universal.apk "${aab%.*}.apk"
done

# Remove keystore (ephemeral or decoded from secret)
rm -f "$KEYSTORE_FILE"
